import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Turns a recording into an animated GIF with ImageIO: frames sampled at a fixed rate and
/// scaled down, looping forever.
public enum GifExporter {
    public struct Options: Sendable, Equatable {
        /// The GIF's longer side in pixels; a smaller movie keeps its own size.
        public var maxSide: Int
        public var framesPerSecond: Double

        public init(maxSide: Int, framesPerSecond: Double) {
            self.maxSide = maxSide
            self.framesPerSecond = framesPerSecond
        }
    }

    public enum ExportError: Error, Equatable {
        case noVideo
        case cannotWrite
    }

    /// The moments to sample: one every `1 / framesPerSecond` from the start, at least one.
    public static func frameTimes(duration: Double, framesPerSecond: Double) -> [Double] {
        guard framesPerSecond > 0, duration > 0 else { return [0] }
        let count = max(1, Int((duration * framesPerSecond).rounded(.up)))
        return (0..<count).map { Double($0) / framesPerSecond }
    }

    /// `size` scaled so its longer side is at most `maxSide`, never enlarged.
    public static func fittedSize(_ size: CGSize, maxSide: Int) -> CGSize {
        let longer = max(size.width, size.height)
        guard longer > CGFloat(maxSide), longer > 0 else { return size }
        let scale = CGFloat(maxSide) / longer
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Writes `movie` as a GIF at `gif` and returns how many frames it has. Cancelling the
    /// task stops the export and removes the partial file.
    @discardableResult
    public static func export(movie: URL, to gif: URL, options: Options) async throws -> Int {
        let asset = AVURLAsset(url: movie)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.noVideo }
        let duration = try await asset.load(.duration).seconds
        let natural = try await track.load(.naturalSize)
        let times = frameTimes(duration: duration, framesPerSecond: options.framesPerSecond)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = fittedSize(natural, maxSide: options.maxSide)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        guard
            let destination = CGImageDestinationCreateWithURL(
                gif as CFURL, UTType.gif.identifier as CFString, times.count, nil)
        else { throw ExportError.cannotWrite }
        let loopForever = 0
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopForever]] as CFDictionary)
        let frameProperties =
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFUnclampedDelayTime: 1 / options.framesPerSecond,
                    kCGImagePropertyGIFDelayTime: 1 / options.framesPerSecond,
                ]
            ] as CFDictionary
        var written = 0
        var last: CGImage?
        for seconds in times {
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: gif)
                throw CancellationError()
            }
            let time = CMTime(seconds: seconds, preferredTimescale: timescale)
            // A moment with no decodable frame (the very end) repeats the frame before it.
            let image = (try? await generator.image(at: time).image) ?? last
            guard let image else { continue }
            CGImageDestinationAddImage(destination, image, frameProperties)
            last = image
            written += 1
        }
        guard written > 0 else { throw ExportError.noVideo }
        guard CGImageDestinationFinalize(destination) else { throw ExportError.cannotWrite }
        return written
    }

    private static let timescale: CMTimeScale = 600
}
