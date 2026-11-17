import AVFoundation
import CoreGraphics
import CoreVideo

/// Records the frames Pane already receives into an H.264 `.mov`.
///
/// Each frame is stamped with the emulator's own frame time, so the movie has the stream's
/// variable frame rate (the emulator sends a frame only when the screen changes). Given Start
/// and the frame on screen then, the movie begins with that frame at time 0 and `finish(at:)`
/// writes the last frame again at Stop, so a still screen still makes a movie as long as the
/// recording (`RecordingTimeline`). The movie's size is the one asked for, rounded down to even
/// numbers for H.264; frames of another size (a resize or rotation mid-recording) are drawn
/// aspect-fit on black.
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
    private var timeline: RecordingTimeline
    /// The frame on screen at Start, written at time 0 before anything else.
    private var seed: StreamFrame?
    /// The last frame written, its buffer and the emulator's time for it, to write again at Stop.
    private var last: (buffer: CVPixelBuffer, timestamp: UInt64)?
    private var finished = false
    /// Set once Stop begins: frames still arriving from the stream are no longer taken.
    private var closing = false
    public private(set) var framesWritten = 0

    /// Microseconds, the unit of `Image.timestampUs`.
    private static let timescale: CMTimeScale = 1_000_000

    /// How long Stop waits for a busy encoder to take the first or closing frame, and how often
    /// it looks.
    public struct EncoderWait: Sendable {
        public var limit: Duration
        public var poll: Duration

        public init(limit: Duration, poll: Duration) {
            self.limit = limit
            self.poll = poll
        }
    }

    /// - Parameters:
    ///   - start: Start in the frames' clock (wall-clock microseconds). Nil makes the first
    ///     frame written Start.
    ///   - firstFrame: the frame on screen at Start, written at time 0.
    public init(url: URL, size: PixelSize, start: UInt64? = nil, firstFrame: StreamFrame? = nil) throws {
        timeline = RecordingTimeline(origin: start)
        seed = start == nil ? nil : firstFrame
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
        writer.startSession(atSourceTime: .zero)
    }

    /// Adds one frame stamped `timestampMicroseconds` (the emulator's clock). A frame stamped no
    /// later than the one before goes just after it (`RecordingTimeline`); one that arrives while
    /// the encoder is busy is skipped. Returns whether this one was written.
    @discardableResult
    public func append(_ image: CGImage, timestampMicroseconds: UInt64) -> Bool {
        guard !closing else { return false }
        writeSeed()
        return append(timestampMicroseconds: timestampMicroseconds) { pool in
            guard let buffer = Self.buffer(from: pool) else { return nil }
            draw(image, into: buffer)
            return buffer
        }
    }

    /// Adds one streamed frame. A frame of the movie's own size goes to the encoder as it is,
    /// with no copy; any other size is drawn aspect-fit on black.
    @discardableResult
    public func append(_ frame: StreamFrame) -> Bool {
        guard !closing else { return false }
        writeSeed()
        return append(timestampMicroseconds: frame.timestampMicroseconds) { pool in buffer(for: frame, from: pool) }
    }

    private func writeSeed() {
        guard let frame = seed else { return }
        // Kept for the next try when the encoder is busy; any later frame written drops it.
        append(timestampMicroseconds: frame.timestampMicroseconds, at: 0) { pool in buffer(for: frame, from: pool) }
    }

    private func buffer(for frame: StreamFrame, from pool: CVPixelBufferPool) -> CVPixelBuffer? {
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

    @discardableResult
    private func append(
        timestampMicroseconds: UInt64, at fixedTime: Int64? = nil, frame: (CVPixelBufferPool) -> CVPixelBuffer?
    ) -> Bool {
        guard !finished, writer.status == .writing else { return false }
        guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool, let buffer = frame(pool) else {
            return false
        }
        let time = fixedTime ?? timeline.time(forFrameAt: timestampMicroseconds)
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: time, timescale: Self.timescale)) else {
            return false
        }
        timeline.wrote(at: time, timestamp: timestampMicroseconds)
        last = (buffer, timestampMicroseconds)
        seed = nil
        framesWritten += 1
        return true
    }

    private static func buffer(from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }

    /// Ends the movie. Given Stop (`stop`, the frames' clock), the last frame is written again
    /// there so the movie lasts until Stop; `onScreen` is the frame showing at Stop, written
    /// instead when it is newer than the last one the recorder got. Without Stop the movie ends
    /// at its last frame. With no frames written there is no movie: the file is removed and
    /// this throws `notRecording`.
    public func finish(at stop: UInt64? = nil, onScreen: StreamFrame? = nil, wait: EncoderWait? = nil) async throws {
        guard !finished, !closing else { return }
        closing = true
        if seed != nil {
            await waitForEncoder(wait)
            writeSeed()
        }
        if let stop {
            await writeClosingFrame(at: stop, onScreen: onScreen, wait: wait)
        }
        finished = true
        guard framesWritten > 0, let lastWritten = timeline.lastWritten else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.notRecording
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: lastWritten, timescale: Self.timescale))
        await writer.finishWriting()
        if writer.status != .completed {
            throw RecorderError.cannotStart(String(describing: writer.error))
        }
    }

    /// Writes the last frame again at the stop time, so the movie lasts until Stop. A frame
    /// showing at Stop that the recorder never got (it raced Stop) is written first, at its own
    /// time, so it is the one the movie ends on. Waits for the encoder if it is still busy.
    private func writeClosingFrame(at stop: UInt64, onScreen: StreamFrame?, wait: EncoderWait?) async {
        if let onScreen, last.map({ onScreen.timestampMicroseconds > $0.timestamp }) ?? true {
            await waitForEncoder(wait)
            append(timestampMicroseconds: onScreen.timestampMicroseconds) { pool in buffer(for: onScreen, from: pool) }
        }
        guard let last, let end = timeline.end(stoppedAt: stop) else { return }
        await waitForEncoder(wait)
        append(timestampMicroseconds: last.timestamp, at: end) { pool in Self.copy(last.buffer, from: pool) }
    }

    /// A copy of `source` in a buffer of the movie's own, so the closing frame is a sample of
    /// its own rather than the encoder's last buffer handed over again.
    private static func copy(_ source: CVPixelBuffer, from pool: CVPixelBufferPool) -> CVPixelBuffer? {
        guard let copy = buffer(from: pool) else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        guard let from = CVPixelBufferGetBaseAddress(source), let to = CVPixelBufferGetBaseAddress(copy),
            CVPixelBufferGetHeight(source) == CVPixelBufferGetHeight(copy)
        else { return nil }
        let rows = CVPixelBufferGetHeight(source)
        let fromRow = CVPixelBufferGetBytesPerRow(source)
        let toRow = CVPixelBufferGetBytesPerRow(copy)
        let rowBytes = min(fromRow, toRow)
        for row in 0..<rows {
            memcpy(to + row * toRow, from + row * fromRow, rowBytes)
        }
        return copy
    }

    /// Waits for the encoder to take another frame, up to `wait.limit`; not at all without one.
    private func waitForEncoder(_ wait: EncoderWait?) async {
        guard let wait else { return }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: wait.limit)
        while !input.isReadyForMoreMediaData, clock.now < deadline {
            try? await Task.sleep(for: wait.poll)
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
