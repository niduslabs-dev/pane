import AVFoundation
import CoreGraphics
import Foundation
import Testing

@testable import PaneCore

@Suite struct FrameRecorderTests {
    private func image(width: Int, height: Int, gray: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private let wait = FrameRecorder.EncoderWait(limit: .seconds(1), poll: .milliseconds(5))

    private func scratchURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "pane-recording-\(UUID().uuidString).mov")
    }

    @Test func writesAVariableRateMovieFromFrameTimes() async throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // An odd size is rounded down to even for H.264.
        let recorder = FrameRecorder(url: url, size: PixelSize(width: 161, height: 351))
        let start: UInt64 = 1_700_000_000_000_000
        // Uneven gaps, as a change-driven stream sends: 0, 16 ms, 50 ms, 1 s, 1.5 s.
        let offsets: [UInt64] = [0, 16_000, 50_000, 1_000_000, 1_500_000]
        for (index, offset) in offsets.enumerated() {
            let written = await recorder.append(
                image(width: 160, height: 350, gray: CGFloat(index) / 5), timestampMicroseconds: start + offset)
            #expect(written)
            // The encoder takes frames as fast as a real stream sends them.
            try await Task.sleep(for: .milliseconds(20))
        }
        // A frame stamped no later than the one before is newer content: it goes just after it.
        #expect(await recorder.append(image(width: 160, height: 350, gray: 1), timestampMicroseconds: start))
        try await Task.sleep(for: .milliseconds(20))
        // A rotated frame is letterboxed, not rejected.
        #expect(
            await recorder.append(
                image(width: 350, height: 160, gray: 1), timestampMicroseconds: start + 1_600_000))
        try await recorder.finish()
        #expect(await recorder.framesWritten == 7)

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(abs(duration.seconds - 1.6) < 0.05)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width: 160, height: 350))
        let formats = try await track.load(.formatDescriptions)
        #expect(formats.first.map(CMFormatDescriptionGetMediaSubType) == kCMVideoCodecType_H264)
    }

    @Test func noFramesMeansNoMovie() async throws {
        let url = scratchURL()
        let recorder = FrameRecorder(url: url, size: PixelSize(width: 64, height: 64))
        await #expect(throws: FrameRecorder.RecorderError.notRecording) { try await recorder.finish() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func frame(width: Int, height: Int, gray: UInt8, timestamp: UInt64) throws -> StreamFrame {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), Int32(gray), CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return StreamFrame(
            size: PixelSize(width: width, height: height), pixelBuffer: pixels, sequence: 0,
            timestampMicroseconds: timestamp, rotationQuadrants: 0)
    }

    private func movie(_ url: URL) async throws -> (seconds: Double, samples: Int) {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var samples = 0
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 { samples += 1 }
        }
        return (duration.seconds, samples)
    }

    /// A still screen sends no frames, yet the movie has the frame from Start and lasts until Stop.
    @Test func stillScreenMakesAMovieAsLongAsTheRecording() async throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let start: UInt64 = 1_700_000_000_000_000
        let onScreen = try frame(width: 64, height: 128, gray: 200, timestamp: start - 3_000_000)
        let recorder = FrameRecorder(
            url: url, size: PixelSize(width: 64, height: 128), start: start, firstFrame: onScreen)
        try await recorder.finish(at: start + 5_000_000, onScreen: onScreen, wait: wait)
        #expect(await recorder.framesWritten == 2)
        let result = try await movie(url)
        #expect(abs(result.seconds - 5) < 0.05)
        #expect(try await brightness(url, at: 0) > 150)
        #expect(try await brightness(url, at: 4.9) > 150)
    }

    /// A frame shown at Stop that the recorder never got (it raced Stop) closes the movie.
    @Test func aNewerFrameOnScreenAtStopClosesTheMovie() async throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let start: UInt64 = 1_700_000_000_000_000
        let recorder = FrameRecorder(
            url: url, size: PixelSize(width: 64, height: 128), start: start,
            firstFrame: try frame(width: 64, height: 128, gray: 220, timestamp: start - 1_000_000))
        let shown = try frame(width: 64, height: 128, gray: 20, timestamp: start + 1_000_000)
        try await recorder.finish(at: start + 2_000_000, onScreen: shown, wait: wait)
        #expect(abs(try await movie(url).seconds - 2) < 0.05)
        #expect(try await brightness(url, at: 0) > 150)
        #expect(try await brightness(url, at: 1.99) < 100)
    }

    /// The middle pixel's green channel of the frame at `seconds`.
    private func brightness(_ url: URL, at seconds: Double) async throws -> Int {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(
            image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        return Int(try #require(context.data).load(fromByteOffset: 1, as: UInt8.self))
    }

    /// Frames between Start and Stop keep their own times; the closing frame is the newest.
    @Test func framesBetweenStartAndStopKeepTheirTimes() async throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let start: UInt64 = 1_700_000_000_000_000
        let size = PixelSize(width: 64, height: 128)
        let recorder = FrameRecorder(
            url: url, size: size, start: start,
            firstFrame: try frame(width: 64, height: 128, gray: 10, timestamp: start - 1_000_000))
        #expect(await recorder.append(try frame(width: 64, height: 128, gray: 90, timestamp: start + 1_000_000)))
        try await Task.sleep(for: .milliseconds(20))
        // Rotated mid-recording: letterboxed.
        #expect(await recorder.append(try frame(width: 128, height: 64, gray: 160, timestamp: start + 2_000_000)))
        try await recorder.finish(at: start + 3_000_000, wait: wait)
        #expect(await recorder.framesWritten == 4)
        let result = try await movie(url)
        #expect(abs(result.seconds - 3) < 0.05)
        #expect(result.samples == 4)
    }

    /// Stop within one frame of Start still makes a short, valid movie.
    @Test func stopRightAfterStart() async throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let start: UInt64 = 1_700_000_000_000_000
        let onScreen = try frame(width: 64, height: 128, gray: 50, timestamp: start - 1)
        let recorder = FrameRecorder(
            url: url, size: PixelSize(width: 64, height: 128), start: start, firstFrame: onScreen)
        try await recorder.finish(at: start, onScreen: onScreen, wait: wait)
        #expect(await recorder.framesWritten == 2)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// Nothing on screen at Start and nothing after it: still no movie.
    @Test func noFrameAtAllMeansNoMovie() async throws {
        let url = scratchURL()
        let start: UInt64 = 1_700_000_000_000_000
        let recorder = FrameRecorder(url: url, size: PixelSize(width: 64, height: 64), start: start)
        await #expect(throws: FrameRecorder.RecorderError.notRecording) {
            try await recorder.finish(at: start + 1_000_000, wait: wait)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// Start can't run on the main actor's time, so Record's press only makes the recorder; the
    /// writer starts on the actor, or on the first frame when nobody called `start()`.
    @Test func theWriterStartsOnTheActorNotAtCreation() async throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let start: UInt64 = 1_700_000_000_000_000
        let onScreen = try frame(width: 64, height: 128, gray: 50, timestamp: start - 1)
        let recorder = FrameRecorder(
            url: url, size: PixelSize(width: 64, height: 128), start: start, firstFrame: onScreen)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try await recorder.start()
        try await recorder.start()
        #expect(await recorder.append(try frame(width: 64, height: 128, gray: 90, timestamp: start + 10_000)))
        try await recorder.finish(at: start + 50_000, wait: wait)
        // The frame on screen at Start, the one after it, and the last one again at Stop.
        #expect(await recorder.framesWritten == 3)
    }

    /// A writer that can't start fails every step the same way, so Record's rollback and
    /// Stop's "couldn't save" see the same error whichever comes first.
    @Test func aWriterThatCantStartFailsEveryStep() async throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "pane-missing-\(UUID().uuidString)")
        let url = missing.appending(path: "movie.mov")
        let start: UInt64 = 1_700_000_000_000_000
        let onScreen = try frame(width: 64, height: 128, gray: 50, timestamp: start - 1)
        let recorder = FrameRecorder(
            url: url, size: PixelSize(width: 64, height: 128), start: start, firstFrame: onScreen)
        await #expect(throws: FrameRecorder.RecorderError.self) { try await recorder.start() }
        await #expect(throws: FrameRecorder.RecorderError.self) { try await recorder.start() }
        #expect(!(await recorder.append(try frame(width: 64, height: 128, gray: 90, timestamp: start + 10_000))))
        await #expect(throws: FrameRecorder.RecorderError.self) {
            try await recorder.finish(at: start + 50_000, onScreen: onScreen, wait: wait)
        }
        #expect(await recorder.framesWritten == 0)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
    }

    @Test func aspectFitCentres() {
        let fitted = FrameRecorder.aspectFit(
            CGSize(width: 200, height: 100), in: CGRect(x: 0, y: 0, width: 100, height: 200))
        #expect(fitted == CGRect(x: 0, y: 75, width: 100, height: 50))
    }
}
