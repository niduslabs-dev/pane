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

    private func scratchURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "pane-recording-\(UUID().uuidString).mov")
    }

    @Test func writesAVariableRateMovieFromFrameTimes() async throws {
        let url = scratchURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // An odd size is rounded down to even for H.264.
        let recorder = try FrameRecorder(url: url, size: PixelSize(width: 161, height: 351))
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
        // A frame that doesn't move time forward is skipped.
        #expect(await !recorder.append(image(width: 160, height: 350, gray: 1), timestampMicroseconds: start))
        // A rotated frame is letterboxed, not rejected.
        #expect(
            await recorder.append(
                image(width: 350, height: 160, gray: 1), timestampMicroseconds: start + 1_600_000))
        try await recorder.finish()
        #expect(await recorder.framesWritten == 6)

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
        let recorder = try FrameRecorder(url: url, size: PixelSize(width: 64, height: 64))
        await #expect(throws: FrameRecorder.RecorderError.notRecording) { try await recorder.finish() }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aspectFitCentres() {
        let fitted = FrameRecorder.aspectFit(
            CGSize(width: 200, height: 100), in: CGRect(x: 0, y: 0, width: 100, height: 200))
        #expect(fitted == CGRect(x: 0, y: 75, width: 100, height: 50))
    }
}
