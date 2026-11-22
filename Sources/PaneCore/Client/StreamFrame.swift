import Accelerate
import CoreVideo
import Foundation
import GRPCCore
import IOSurface
import SwiftProtobuf

/// One frame of the screen stream, in a pooled IOSurface-backed `CVPixelBuffer` (32BGRA, opaque,
/// sRGB, top row first) that a layer can show without another copy.
///
/// Streamed frames used to be a fresh `Data` per frame (the protobuf decode's copy of
/// `Image.image`) wrapped in a `CGImage`. At 40-60 frames a second of 4 to 10 MB each, macOS's
/// allocator kept hundreds of MB of freed large blocks dirty (`Malloc Large (empty)` in
/// `vmmap`), so Pane's footprint swung up to 1.1 GB with almost nothing live. Pooled buffers
/// are reused instead, and Core Animation reads the IOSurface directly instead of converting
/// the `CGImage`.
public struct StreamFrame: @unchecked Sendable {
    // `@unchecked`: the buffer is written once, in `StreamFrameDecoder.decode`, before the
    // frame is handed on, and only read after that.

    public let size: PixelSize
    public let pixelBuffer: CVPixelBuffer
    /// Increases by one per frame the emulator produced; a gap means frames were dropped.
    public let sequence: UInt32
    /// When the emulator produced the frame, in its own clock, for latency checks.
    public let timestampMicroseconds: UInt64
    /// Quarter turns counter-clockwise from portrait, as the emulator reports it.
    public let rotationQuadrants: Int
    /// The folded screen's exact size in device pixels, natural (portrait) orientation, when the
    /// device is folded (`ImageFormat.foldedDisplay`); nil when it isn't. The frame's own size
    /// is scaled, so it gives only the aspect.
    public let foldedDisplay: PixelSize?

    public init(
        size: PixelSize, pixelBuffer: CVPixelBuffer, sequence: UInt32, timestampMicroseconds: UInt64,
        rotationQuadrants: Int, foldedDisplay: PixelSize? = nil
    ) {
        self.size = size
        self.pixelBuffer = pixelBuffer
        self.sequence = sequence
        self.timestampMicroseconds = timestampMicroseconds
        self.rotationQuadrants = rotationQuadrants
        self.foldedDisplay = foldedDisplay
    }

    /// The surface behind the buffer, for `CALayer.contents`.
    public var surface: IOSurfaceRef? { CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() }

    /// The pixels as tightly packed RGBA rows (the layout `ScreenFrame` and `PixelGrid` use).
    /// A copy, for the tools that read colours; the display path never calls it.
    public func rgbaPixels() -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let rowBytes = size.width * ScreenFrame.bytesPerPixel
        var data = Data(count: rowBytes * size.height)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return data }
        data.withUnsafeMutableBytes { out in
            var source = vImage_Buffer(
                data: base, height: vImagePixelCount(size.height), width: vImagePixelCount(size.width),
                rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer))
            var destination = vImage_Buffer(
                data: out.baseAddress, height: vImagePixelCount(size.height), width: vImagePixelCount(size.width),
                rowBytes: rowBytes)
            // BGRA and RGBA swap the same two channels both ways.
            _ = vImagePermuteChannels_ARGB8888(
                &source, &destination, StreamFrameDecoder.swapRedBlue, vImage_Flags(kvImageNoFlags))
        }
        return data
    }
}

/// Reuses IOSurface-backed BGRA pixel buffers of one size for one stream.
///
/// At most `maxBuffers` are out at once: frames still on screen, queued, or held by a
/// recording. When all are out the next frame is dropped (and shows as a sequence gap), so a
/// stalled consumer can never grow memory. A new size makes a new pool; the old one's buffers
/// are freed as their frames are released.
///
/// The emulator sends frames only when its screen changes, so after a burst the pool would keep
/// its spare buffers (one frame each) for as long as the screen stays still. Once no frame has
/// come for `idleTrimDelay` they are freed; the buffer on screen stays, held by its frame.
public final class FramePixelBufferPool: @unchecked Sendable {
    // `@unchecked`: `buffer(size:)` runs on the one task that iterates a stream's responses and
    // the trim on a timer's queue; both take `lock`.

    /// Enough for the frame on screen, one being shown, one queued and a recorder's own hold.
    public static let defaultMaxBuffers = 6
    /// How long the screen stays still before the spare buffers are freed. Long enough that a
    /// scroll or an animation, whose frames come tens of milliseconds apart, never trims.
    public static let defaultIdleTrimDelay: Duration = .seconds(2)  // design-ok: engine timing, not a UI value

    public let maxBuffers: Int
    private let idleTrimDelay: Duration
    private let idleTrimTimer: any IdleTrimTimer
    private let lock = NSLock()
    private var pool: CVPixelBufferPool?
    private var poolSize: PixelSize?

    /// `idleTrimTimer` is for tests, which drive the trim by hand.
    public init(
        maxBuffers: Int = FramePixelBufferPool.defaultMaxBuffers,
        idleTrimDelay: Duration = FramePixelBufferPool.defaultIdleTrimDelay,
        idleTrimTimer: any IdleTrimTimer = DispatchIdleTrimTimer()
    ) {
        self.maxBuffers = maxBuffers
        self.idleTrimDelay = idleTrimDelay
        self.idleTrimTimer = idleTrimTimer
    }

    deinit { idleTrimTimer.cancel() }

    /// A buffer of `size`, or nil when `maxBuffers` are already out (or CoreVideo fails).
    public func buffer(size: PixelSize) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if poolSize != size {
            if let pool { CVPixelBufferPoolFlush(pool, .excessBuffers) }
            pool = Self.makePool(size: size)
            poolSize = size
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        let threshold = [kCVPixelBufferPoolAllocationThresholdKey as String: maxBuffers] as CFDictionary
        let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, threshold, &buffer)
        idleTrimTimer.schedule(after: idleTrimDelay) { [weak self] in self?.trimSpareBuffers() }
        return result == kCVReturnSuccess ? buffer : nil
    }

    /// Frees every buffer no frame holds. The idle timer calls it.
    func trimSpareBuffers() {
        lock.lock()
        defer { lock.unlock() }
        if let pool { CVPixelBufferPoolFlush(pool, .excessBuffers) }
    }

    private static func makePool(size: PixelSize) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        return pool
    }
}

/// Runs a stream pool's idle trim. Each request replaces the one before, so the action runs
/// only once `delay` passes with no newer request.
public protocol IdleTrimTimer: AnyObject, Sendable {
    func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void)
    func cancel()
}

/// The trim's timer in the app: one `DispatchSourceTimer` on a utility queue, pushed back on
/// every request.
public final class DispatchIdleTrimTimer: IdleTrimTimer, @unchecked Sendable {
    // `@unchecked`: `timer` is made once under `lock`; a dispatch source is thread-safe.
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?

    public init() {}

    deinit { timer?.cancel() }

    public func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let source: DispatchSourceTimer
        if let timer {
            source = timer
        } else {
            source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            source.schedule(deadline: .distantFuture)
            source.activate()
            timer = source
        }
        source.setEventHandler(handler: action)
        source.schedule(deadline: .now() + Self.interval(delay))
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        timer?.schedule(deadline: .distantFuture)
    }

    private static func interval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        let attosecondsPerNanosecond: Int64 = 1_000_000_000
        let nanosecondsPerSecond: Int64 = 1_000_000_000
        return .nanoseconds(Int(seconds * nanosecondsPerSecond + attoseconds / attosecondsPerNanosecond))
    }
}

/// Reads a streamed `Image` message straight from the wire bytes into a pooled buffer, so the
/// pixels are copied once (and swizzled to BGRA on the way) instead of into a fresh `Data`.
public enum StreamFrameDecoder {
    enum DecodeError: Error, Equatable {
        case truncated
        case unsupportedWireType(Int)
    }

    /// RGBA to BGRA and back.
    static let swapRedBlue: [UInt8] = [2, 1, 0, 3]
    /// The alpha byte of BGRA: the emulator's alpha is not coverage, so frames are drawn opaque.
    private static let alphaChannelMask: UInt8 = 0x1
    private static let opaque: [UInt8] = [0, 0, 0, UInt8.max]
    // An immutable property list, read only.
    nonisolated(unsafe) private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB).flatMap {
        $0.copyPropertyList()
    }

    /// The fields of an `Image` message, with the pixels as a range of the message's bytes.
    struct Fields: Equatable {
        var format = Android_Emulation_Control_ImageFormat()
        var pixels: Range<Int> = 0..<0
        var sequence: UInt32 = 0
        var timestampMicroseconds: UInt64 = 0
    }

    /// Splits an `Image` message into its fields without copying the pixels. Unknown fields are
    /// skipped, as protobuf requires.
    static func fields(of bytes: UnsafeRawBufferPointer) throws -> Fields {
        var fields = Fields()
        var reader = WireReader(bytes: bytes)
        while !reader.isAtEnd {
            let key = try reader.varint()
            let field = Int(key >> 3)
            let wireType = Int(key & 0x7)
            switch (field, wireType) {
            case (1, WireReader.lengthDelimited):
                let range = try reader.lengthDelimited()
                fields.format = try Android_Emulation_Control_ImageFormat(
                    serializedBytes: Data(bytes[range]))
            case (4, WireReader.lengthDelimited):
                fields.pixels = try reader.lengthDelimited()
            case (5, WireReader.varintType):
                fields.sequence = UInt32(truncatingIfNeeded: try reader.varint())
            case (6, WireReader.varintType):
                fields.timestampMicroseconds = try reader.varint()
            default:
                try reader.skip(wireType: wireType)
            }
        }
        return fields
    }

    /// The frame in an `Image` message, or nil for the empty frames an inactive display sends,
    /// a short pixel field, or no free buffer in `pool`.
    public static func decode(_ bytes: UnsafeRawBufferPointer, into pool: FramePixelBufferPool) throws -> StreamFrame? {
        let fields = try fields(of: bytes)
        let size = PixelSize(width: Int(fields.format.width), height: Int(fields.format.height))
        let rowBytes = size.width * ScreenFrame.bytesPerPixel
        guard size.width > 0, size.height > 0, fields.pixels.count >= rowBytes * size.height,
            let buffer = pool.buffer(size: size)
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer), let pixels = bytes.baseAddress else { return nil }
        var source = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: pixels + fields.pixels.lowerBound),
            height: vImagePixelCount(size.height), width: vImagePixelCount(size.width), rowBytes: rowBytes)
        var destination = vImage_Buffer(
            data: base, height: vImagePixelCount(size.height), width: vImagePixelCount(size.width),
            rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        let error = vImagePermuteChannelsWithMaskedInsert_ARGB8888(
            &source, &destination, swapRedBlue, alphaChannelMask, opaque, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }
        if let sRGB, let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, sRGB)
        }
        return StreamFrame(
            size: size, pixelBuffer: buffer, sequence: fields.sequence,
            timestampMicroseconds: fields.timestampMicroseconds,
            rotationQuadrants: fields.format.rotation.rotation.rawValue,
            foldedDisplay: foldedDisplay(of: fields.format))
    }

    /// `foldedDisplay` as a size, or nil when the frame has none (or an empty one).
    static func foldedDisplay(of format: Android_Emulation_Control_ImageFormat) -> PixelSize? {
        guard format.hasFoldedDisplay, format.foldedDisplay.width > 0, format.foldedDisplay.height > 0 else {
            return nil
        }
        return PixelSize(width: Int(format.foldedDisplay.width), height: Int(format.foldedDisplay.height))
    }
}

/// The gRPC deserializer for `streamScreenshot`'s responses: each `Image` into `pool`.
struct StreamFrameDeserializer: MessageDeserializer {
    let pool: FramePixelBufferPool

    func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> StreamFrame? {
        try serializedMessageBytes.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) }
    }
}

/// Just enough of the protobuf wire format to walk one message's top-level fields.
struct WireReader {
    static let varintType = 0
    static let fixed64Type = 1
    static let lengthDelimited = 2
    static let fixed32Type = 5
    private static let fixed64Bytes = 8
    private static let fixed32Bytes = 4
    private static let varintPayloadBits: UInt64 = 0x7F
    private static let varintContinues: UInt8 = 0x80
    private static let varintShift: UInt64 = 7
    private static let maxVarintShift: UInt64 = 63

    let bytes: UnsafeRawBufferPointer
    private(set) var offset = 0

    init(bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func varint() throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard offset < bytes.count, shift <= Self.maxVarintShift else {
                throw StreamFrameDecoder.DecodeError.truncated
            }
            let byte = bytes[offset]
            offset += 1
            value |= (UInt64(byte) & Self.varintPayloadBits) << shift
            if byte & Self.varintContinues == 0 { return value }
            shift += Self.varintShift
        }
    }

    mutating func lengthDelimited() throws -> Range<Int> {
        let length = try varint()
        guard length <= UInt64(bytes.count - offset) else { throw StreamFrameDecoder.DecodeError.truncated }
        let range = offset..<(offset + Int(length))
        offset = range.upperBound
        return range
    }

    mutating func skip(wireType: Int) throws {
        switch wireType {
        case Self.varintType: _ = try varint()
        case Self.fixed64Type: try advance(Self.fixed64Bytes)
        case Self.lengthDelimited: _ = try lengthDelimited()
        case Self.fixed32Type: try advance(Self.fixed32Bytes)
        default: throw StreamFrameDecoder.DecodeError.unsupportedWireType(wireType)
        }
    }

    private mutating func advance(_ count: Int) throws {
        guard count <= bytes.count - offset else { throw StreamFrameDecoder.DecodeError.truncated }
        offset += count
    }
}
