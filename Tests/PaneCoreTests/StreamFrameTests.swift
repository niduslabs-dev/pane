import CoreVideo
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCProtobuf
import IOSurface
import SwiftProtobuf
import Synchronization
import Testing

@testable import PaneCore

@Suite struct StreamFrameTests {
    /// An `Image` message as the emulator sends it: RGBA rows whose pixel at (x, y) is
    /// (x, y, x + y, alpha) so every byte says where it came from.
    static func imageMessage(
        width: Int, height: Int, sequence: UInt32 = 7, timestamp: UInt64 = 1_234_567, alpha: UInt8 = 0,
        rotation: Android_Emulation_Control_Rotation.SkinRotation = .landscape
    ) throws -> [UInt8] {
        var image = Android_Emulation_Control_Image()
        image.format.format = .rgba8888
        image.format.width = UInt32(width)
        image.format.height = UInt32(height)
        image.format.rotation.rotation = rotation
        image.seq = sequence
        image.timestampUs = timestamp
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width { pixels += [UInt8(x), UInt8(y), UInt8(x + y), alpha] }
        }
        image.image = Data(pixels)
        return try image.serializedBytes()
    }

    @Test func decodesTheFieldsWithoutTheProtobufCopy() throws {
        let bytes = try Self.imageMessage(width: 5, height: 3)
        let fields = try bytes.withUnsafeBytes { try StreamFrameDecoder.fields(of: $0) }
        #expect(fields.format.width == 5)
        #expect(fields.format.height == 3)
        #expect(fields.format.rotation.rotation == .landscape)
        #expect(fields.sequence == 7)
        #expect(fields.timestampMicroseconds == 1_234_567)
        #expect(fields.pixels.count == 5 * 3 * 4)
        #expect(Array(bytes[fields.pixels].prefix(8)) == [0, 0, 0, 0, 1, 0, 1, 0])
    }

    @Test func skipsUnknownAndDeprecatedFields() throws {
        var image = Android_Emulation_Control_Image()
        image.format.width = 2
        image.format.height = 1
        image.width = 99
        image.height = 99
        image.image = Data([1, 2, 3, 4, 5, 6, 7, 8])
        image.seq = 3
        var bytes = try image.serializedBytes() as [UInt8]
        // Field 9, fixed64, then field 10, fixed32: neither is in the proto.
        bytes += [0x49] + [UInt8](repeating: 0xAB, count: 8) + [0x55] + [UInt8](repeating: 0xCD, count: 4)
        let fields = try bytes.withUnsafeBytes { try StreamFrameDecoder.fields(of: $0) }
        #expect(fields.format.width == 2)
        #expect(fields.sequence == 3)
        #expect(Array(bytes[fields.pixels]) == [1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test func refusesATruncatedMessage() throws {
        let bytes = try Self.imageMessage(width: 4, height: 4)
        #expect(throws: StreamFrameDecoder.DecodeError.truncated) {
            try bytes.dropLast(3).withUnsafeBytes { try StreamFrameDecoder.fields(of: $0) }
        }
    }

    @Test func copiesThePixelsIntoAnOpaqueBGRASurface() throws {
        let pool = FramePixelBufferPool()
        let bytes = try Self.imageMessage(width: 5, height: 3, alpha: 0)
        let frame = try #require(try bytes.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) })
        #expect(frame.size == PixelSize(width: 5, height: 3))
        #expect(frame.sequence == 7)
        #expect(frame.timestampMicroseconds == 1_234_567)
        #expect(frame.rotationQuadrants == 1)
        #expect(frame.surface != nil)
        #expect(CVPixelBufferGetPixelFormatType(frame.pixelBuffer) == kCVPixelFormatType_32BGRA)

        let buffer = frame.pixelBuffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        // Pixel (3, 2): RGBA (3, 2, 5, 0) becomes BGRA (5, 2, 3, 255).
        let offset = 2 * rowBytes + 3 * 4
        #expect([base[offset], base[offset + 1], base[offset + 2], base[offset + 3]] == [5, 2, 3, 255])
        // The tools get RGBA back.
        let rgba = frame.rgbaPixels()
        let grid = try #require(PixelGrid(size: frame.size, pixels: rgba))
        #expect(grid.colour(x: 3, y: 2) == PickedColour(red: 3, green: 2, blue: 5))
    }

    @Test func emptyOrShortFramesAreSkipped() throws {
        let pool = FramePixelBufferPool()
        var off = Android_Emulation_Control_Image()
        off.format.width = 0
        off.format.height = 0
        let offBytes = try off.serializedBytes() as [UInt8]
        #expect(try offBytes.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) } == nil)

        var short = Android_Emulation_Control_Image()
        short.format.width = 4
        short.format.height = 4
        short.image = Data(count: 10)
        let shortBytes = try short.serializedBytes() as [UInt8]
        #expect(try shortBytes.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) } == nil)
    }

    /// The point of the pool: a stalled consumer can't grow memory, and released buffers are
    /// reused rather than allocated again.
    @Test func thePoolIsBoundedAndReusesBuffers() throws {
        let pool = FramePixelBufferPool(maxBuffers: 3)
        let bytes = try Self.imageMessage(width: 8, height: 8)
        func decode() throws -> StreamFrame? {
            try bytes.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) }
        }
        var held = [StreamFrame]()
        for _ in 0..<3 { held.append(try #require(try decode())) }
        // All three are out: the next frame is dropped, not allocated.
        #expect(try decode() == nil)
        let freedSurface = try #require(held[0].surface.map(IOSurfaceGetID))
        held.removeFirst()
        let next = try #require(try decode())
        #expect(next.surface.map(IOSurfaceGetID) == freedSurface)
    }

    /// A recording takes streamed frames: one of the movie's size as it is, another drawn in.
    @Test func recordsStreamedFrames() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pane-stream-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = FrameRecorder(url: url, size: PixelSize(width: 16, height: 32))
        let pool = FramePixelBufferPool()
        for (index, size) in [(16, 32), (16, 32), (32, 16)].enumerated() {
            let bytes = try Self.imageMessage(
                width: size.0, height: size.1, timestamp: 1_000_000 + UInt64(index) * 100_000)
            let frame = try #require(try bytes.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) })
            #expect(await recorder.append(frame))
            try await Task.sleep(for: .milliseconds(20))
        }
        try await recorder.finish()
        #expect(await recorder.framesWritten == 3)
    }

    @Test func aNewSizeStartsANewPool() throws {
        let pool = FramePixelBufferPool(maxBuffers: 1)
        let small = try Self.imageMessage(width: 4, height: 4)
        let large = try Self.imageMessage(width: 6, height: 6)
        let first = try #require(try small.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) })
        // The old size's buffer is still out, yet the new size gets its own.
        let second = try #require(try large.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) })
        #expect(first.size != second.size)
    }
}

/// A stream restart against a real HTTP/2 gRPC server on loopback: the old RPC ends on the
/// server, and its pool (with every buffer it handed out) is freed.
@Suite(.timeLimit(.minutes(1))) struct StreamRestartTests {
    /// Stands in for the emulator: `streamScreenshot` sends a frame every few milliseconds
    /// until the client goes away; `streamInputEvent` reads until the client closes it.
    final class FakeEmulator: RegistrableRPCService, Sendable {
        let streamsStarted = Mutex(0)
        let streamsEnded = Mutex(0)

        func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
            router.registerHandler(
                forMethod: Android_Emulation_Control_EmulatorController.Method.streamScreenshot.descriptor,
                deserializer: ProtobufDeserializer<Android_Emulation_Control_ImageFormat>(),
                serializer: ProtobufSerializer<Android_Emulation_Control_Image>()
            ) { request, _ in
                StreamingServerResponse { writer in
                    self.streamsStarted.withLock { $0 += 1 }
                    defer { self.streamsEnded.withLock { $0 += 1 } }
                    var format: Android_Emulation_Control_ImageFormat?
                    for try await message in request.messages { format = message }
                    let width = Int(format?.width ?? 1)
                    let height = Int(format?.height ?? 1)
                    var image = Android_Emulation_Control_Image()
                    image.format.width = UInt32(width)
                    image.format.height = UInt32(height)
                    image.image = Data(count: width * height * ScreenFrame.bytesPerPixel)
                    var sequence: UInt32 = 0
                    while !Task.isCancelled {
                        image.seq = sequence
                        sequence += 1
                        try await writer.write(image)
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    return [:]
                }
            }
            router.registerHandler(
                forMethod: Android_Emulation_Control_EmulatorController.Method.streamInputEvent.descriptor,
                deserializer: ProtobufDeserializer<Android_Emulation_Control_InputEvent>(),
                serializer: ProtobufSerializer<Google_Protobuf_Empty>()
            ) { request, _ in
                for try await _ in request.messages {}
                return StreamingServerResponse(single: ServerResponse(message: Google_Protobuf_Empty()))
            }
        }
    }

    @Test func restartingEndsTheOldStreamAndFreesItsBuffers() async throws {
        let emulator = FakeEmulator()
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0), transportSecurity: .plaintext)
        let server = GRPCServer(transport: transport, services: [emulator])
        let serverTask = Task { try await server.serve() }
        defer {
            server.beginGracefulShutdown()
            serverTask.cancel()
        }
        let port = try #require(try await transport.listeningAddress.ipv4?.port)
        let connection = try EmulatorConnection(
            emulator: RunningEmulator(pid: 1, grpcPort: port, token: GRPCToken("test"), avdName: "fake"),
            deviceSize: PixelSize(width: 64, height: 64))
        let connectionTask = Task { try await connection.run() }
        defer { connectionTask.cancel() }

        weak var firstPool: FramePixelBufferPool?
        var lastFrame: StreamFrame?
        #expect(try await Self.readFrames(5, from: connection, pool: &firstPool) == 5)
        // The second stream, at another size, as a resize starts it.
        let second = Task { () async throws -> StreamFrame? in
            for try await frame in connection.screenFrames(size: PixelSize(width: 48, height: 48)) {
                return frame
            }
            return nil
        }
        lastFrame = try await second.value
        #expect(lastFrame?.size == PixelSize(width: 48, height: 48))

        try await waitUntil { emulator.streamsEnded.withLock { $0 } == 2 }
        #expect(emulator.streamsStarted.withLock { $0 } == 2)
        try await waitUntil { firstPool == nil }
        #expect(firstPool == nil)
    }

    /// Reads `count` frames from a stream at 32 × 32 with its own pool, then stops reading, as
    /// a restart does. `pool` is left as a weak reference to that pool.
    private static func readFrames(
        _ count: Int, from connection: EmulatorConnection, pool weakPool: inout FramePixelBufferPool?
    ) async throws -> Int {
        let pool = FramePixelBufferPool()
        weakPool = pool
        var seen = 0
        for try await _ in connection.screenFrames(size: PixelSize(width: 32, height: 32), pool: pool) {
            seen += 1
            if seen == count { break }
        }
        return seen
    }

    /// Polls `condition` every 10 ms for up to 5 s.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }
}
