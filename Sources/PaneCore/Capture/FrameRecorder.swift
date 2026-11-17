import AVFoundation
import CoreGraphics
import CoreVideo

/// Records the frames Pane already receives into an H.264 `.mov`.
///
/// Each frame is stamped with the emulator's own frame time, so the movie has the stream's
/// variable frame rate (the emulator sends a frame only when the screen changes). The movie's
/// size is the first frame's, rounded down to even numbers for H.264; later frames of another
/// size (a resize or rotation mid-recording) are drawn aspect-fit on black.
public actor FrameRecorder {
    public enum RecorderError: Error, Equatable {
        case cannotStart(String)
        case notRecording
    }

    public nonisolated let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let size: PixelSize
    private var firstTimestamp: UInt64?
    private var lastTimestamp: UInt64?
    private var finished = false
    public private(set) var framesWritten = 0

    /// Microseconds, the unit of `Image.timestampUs`.
    private static let timescale: CMTimeScale = 1_000_000

    public init(url: URL, size: PixelSize) throws {
        let even = PixelSize(width: max(2, size.width / 2 * 2), height: max(2, size.height / 2 * 2))
        self.url = url
        self.size = even
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw RecorderError.cannotStart(String(describing: error))
        }
        input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: even.width, AVVideoHeightKey: even.height,
            ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: even.width, kCVPixelBufferHeightKey as String: even.height,
            ])
        guard writer.canAdd(input) else { throw RecorderError.cannotStart("The writer can't take H.264 video.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw RecorderError.cannotStart(String(describing: writer.error))
        }
    }

    /// Adds one frame stamped `timestampMicroseconds` (the emulator's clock). Frames that don't
    /// move time forward, or arrive while the encoder is busy, are skipped; returns whether this
    /// one was written.
    @discardableResult
    public func append(_ image: CGImage, timestampMicroseconds: UInt64) -> Bool {
        append(timestampMicroseconds: timestampMicroseconds) { pool in
            guard let buffer = Self.buffer(from: pool) else { return nil }
            draw(image, into: buffer)
            return buffer
        }
    }

    /// Adds one streamed frame. A frame of the movie's own size goes to the encoder as it is,
    /// with no copy; any other size is drawn aspect-fit on black.
    @discardableResult
    public func append(_ frame: StreamFrame) -> Bool {
        append(timestampMicroseconds: frame.timestampMicroseconds) { pool in
            if frame.size == size { return frame.pixelBuffer }
            guard let buffer = Self.buffer(from: pool) else { return nil }
            let source = frame.pixelBuffer
            CVPixelBufferLockBaseAddress(source, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
            let bitsPerComponent = 8
            guard let base = CVPixelBufferGetBaseAddress(source),
                let context = CGContext(
                    data: base, width: frame.size.width, height: frame.size.height,
                    bitsPerComponent: bitsPerComponent, bytesPerRow: CVPixelBufferGetBytesPerRow(source),
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                let image = context.makeImage()
            else { return nil }
            draw(image, into: buffer)
            return buffer
        }
    }

    private func append(timestampMicroseconds: UInt64, frame: (CVPixelBufferPool) -> CVPixelBuffer?) -> Bool {
        guard !finished, writer.status == .writing else { return false }
        if let last = lastTimestamp, timestampMicroseconds <= last { return false }
        if firstTimestamp == nil {
            firstTimestamp = timestampMicroseconds
            writer.startSession(atSourceTime: .zero)
        }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool, let buffer = frame(pool) else {
            return false
        }
        let elapsed = Int64(timestampMicroseconds - (firstTimestamp ?? timestampMicroseconds))
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: elapsed, timescale: Self.timescale)) else {
            return false
        }
        lastTimestamp = timestampMicroseconds
        framesWritten += 1
        return true
    }

    private static func buffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }

    /// Ends the movie. With no frames written there is no movie: the file is removed and this
    /// throws `notRecording`.
    public func finish() async throws {
        guard !finished else { return }
        finished = true
        guard framesWritten > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.notRecording
        }
        input.markAsFinished()
        // Holds the last frame on screen until now's frame time, not just its own instant.
        if let last = lastTimestamp, let first = firstTimestamp {
            writer.endSession(atSourceTime: CMTime(value: Int64(last - first), timescale: Self.timescale))
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw RecorderError.cannotStart(String(describing: writer.error))
        }
    }

    private func draw(_ image: CGImage, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bitsPerComponent = 8
        guard
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: size.width, height: size.height,
                bitsPerComponent: bitsPerComponent, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: Self.aspectFit(CGSize(width: image.width, height: image.height), in: bounds))
    }

    /// The largest rect with `content`'s aspect, centred in `bounds`.
    static func aspectFit(_ content: CGSize, in bounds: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0 else { return bounds }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let fitted = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2, width: fitted.width,
            height: fitted.height)
    }
}
