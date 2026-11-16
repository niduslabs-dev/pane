import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import SwiftProtobuf
import os

/// One screen image from `streamScreenshot`: tightly packed RGBA8888 rows, top row first.
///
/// The proto says rows are bottom up; on emulator 37.2.13 on Apple Silicon they arrive top down
/// (checked in the research), so they're passed through unflipped.
public struct ScreenFrame: Sendable {
    public var size: PixelSize
    public var pixels: Data
    /// Increases by one per frame the emulator produced; a gap means frames were dropped.
    public var sequence: UInt32
    /// When the emulator produced the frame, in its own clock, for latency checks.
    public var timestampMicroseconds: UInt64
    /// Quarter turns counter-clockwise from portrait, as the emulator reports it.
    public var rotationQuadrants: Int

    public static let bytesPerPixel = 4
}

/// What the window sends to the emulator. Coordinates are device pixels.
public enum InputCommand: Sendable, Equatable {
    /// The primary button (a finger) down at a point, or moved while down.
    case press(DevicePoint)
    /// The button (finger) lifted at a point. Always sent to end a press, so no touch sticks.
    case release(DevicePoint)
    /// A hardware key down or up, by its W3C key name (`Power`, `AudioVolumeUp`).
    case key(name: String, isDown: Bool)
}

/// A plaintext HTTP/2 gRPC connection to one emulator on loopback, authenticated with its
/// bearer token, and the long-lived input stream.
///
/// Call `run()` from a task and keep it running; cancel that task (or call `shutdown()`) to
/// close the connection. Frames and input only flow while `run()` is running.
public final class EmulatorConnection: Sendable {
    public typealias Transport = HTTP2ClientTransport.Posix

    private let client: GRPCClient<Transport>
    private let controller: Android_Emulation_Control_EmulatorController.Client<Transport>
    private let inputEvents: AsyncStream<Android_Emulation_Control_InputEvent>
    private let inputContinuation: AsyncStream<Android_Emulation_Control_InputEvent>.Continuation
    private let callOptions: CallOptions
    private static let log = Logger(subsystem: "dev.niduslabs.pane", category: "connection")

    /// The ceiling for one message: a full-size RGBA frame plus room for the envelope.
    public static func maxMessageBytes(for deviceSize: PixelSize) -> Int {
        let messageOverheadBytes = 64 * 1024
        return deviceSize.width * deviceSize.height * ScreenFrame.bytesPerPixel + messageOverheadBytes
    }

    public init(emulator: RunningEmulator, deviceSize: PixelSize) throws {
        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(address: "127.0.0.1", port: emulator.grpcPort),
            transportSecurity: .plaintext
        )
        client = GRPCClient(transport: transport, interceptors: [BearerTokenInterceptor(token: emulator.token)])
        controller = Android_Emulation_Control_EmulatorController.Client(wrapping: client)
        var options = CallOptions.defaults
        // grpc-swift-nio-transport 2.12.0 sizes the client's inbound decoder from the *request*
        // limit, so both are raised; the default 4 MiB is smaller than one full-size frame.
        options.maxRequestMessageBytes = Self.maxMessageBytes(for: deviceSize)
        options.maxResponseMessageBytes = Self.maxMessageBytes(for: deviceSize)
        callOptions = options
        (inputEvents, inputContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    /// Runs the connection and the input stream until cancelled or until either fails.
    public func run() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.client.runConnections() }
            group.addTask {
                let events = self.inputEvents
                _ = try await self.controller.streamInputEvent(
                    options: self.callOptions,
                    requestProducer: { writer in
                        for await event in events {
                            try await writer.write(event)
                        }
                    }
                )
            }
            defer { self.shutdown() }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Closes the input stream and the connection.
    public func shutdown() {
        inputContinuation.finish()
        client.beginGracefulShutdown()
    }

    /// Queues one input command on the long-lived input stream; never blocks.
    public func send(_ command: InputCommand) {
        var event = Android_Emulation_Control_InputEvent()
        switch command {
        case .press(let point), .release(let point):
            var mouse = Android_Emulation_Control_MouseEvent()
            mouse.x = Int32(point.x)
            mouse.y = Int32(point.y)
            mouse.buttons = command == .press(point) ? Self.primaryButton : 0
            event.mouseEvent = mouse
        case .key(let name, let isDown):
            var key = Android_Emulation_Control_KeyboardEvent()
            key.key = name
            key.eventType = isDown ? .keydown : .keyup
            event.keyEvent = key
        }
        Self.log.debug("Input \(String(describing: command), privacy: .public)")
        inputContinuation.yield(event)
    }

    /// `MouseEvent.buttons` bit for the primary (left) button.
    private static let primaryButton: Int32 = 1

    /// The emulator's version and boot state, as a cheap authenticated round trip. Fails after
    /// `timeout`, so a stopped or wedged emulator is noticed.
    public func status(timeout: Duration) async throws -> (version: String, booted: Bool) {
        var options = callOptions
        options.timeout = timeout
        let status = try await controller.getStatus(Google_Protobuf_Empty(), options: options)
        return (status.version, status.booted)
    }

    /// Streams RGBA frames at `size` (both sides always set; the emulator keeps the aspect and
    /// never exceeds the device). The emulator sends a frame only when the screen changes.
    /// Cancelling the iteration ends the RPC.
    public func screenFrames(size: PixelSize) -> AsyncThrowingStream<ScreenFrame, any Error> {
        var format = Android_Emulation_Control_ImageFormat()
        format.format = .rgba8888
        format.width = UInt32(size.width)
        format.height = UInt32(size.height)
        let request = format
        let controller = controller
        let options = callOptions
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await controller.streamScreenshot(request, options: options) { response in
                        for try await image in response.messages {
                            guard let frame = Self.frame(from: image) else { continue }
                            continuation.yield(frame)
                        }
                    }
                    continuation.finish()
                } catch {
                    Self.log.error("Screen stream ended: \(String(describing: error), privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Wraps an `Image`; nil for the empty frames an inactive display sends, or a short buffer.
    static func frame(from image: Android_Emulation_Control_Image) -> ScreenFrame? {
        let size = PixelSize(width: Int(image.format.width), height: Int(image.format.height))
        guard size.width > 0, size.height > 0,
            image.image.count >= size.width * size.height * ScreenFrame.bytesPerPixel
        else { return nil }
        return ScreenFrame(
            size: size, pixels: image.image, sequence: image.seq, timestampMicroseconds: image.timestampUs,
            rotationQuadrants: image.format.rotation.rotation.rawValue)
    }
}

/// Adds `authorization: Bearer <grpc.token>` to every call, as Android Studio does.
struct BearerTokenInterceptor: ClientInterceptor {
    let token: GRPCToken

    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingClientRequest<Input>,
        context: ClientContext,
        next: (StreamingClientRequest<Input>, ClientContext) async throws -> StreamingClientResponse<Output>
    ) async throws -> StreamingClientResponse<Output> {
        var request = request
        request.metadata.replaceOrAddString(token.bearerHeaderValue, forKey: "authorization")
        return try await next(request, context)
    }
}
