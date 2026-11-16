import CoreGraphics
import Foundation

/// A colour read from the screen, 8 bits a channel.
public struct PickedColour: Sendable, Equatable, Hashable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// "rgb(26, 27, 34)", as CSS writes it.
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }

    /// "#1A1B22".
    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

/// Reads colours out of a frame's tightly packed RGBA rows (top row first), for Pick Colour.
public struct PixelGrid: Sendable {
    public var size: PixelSize
    public var pixels: Data
    public var bytesPerRow: Int

    public init?(size: PixelSize, pixels: Data, bytesPerRow: Int? = nil) {
        let rowBytes = bytesPerRow ?? size.width * ScreenFrame.bytesPerPixel
        guard size.width > 0, size.height > 0, rowBytes >= size.width * ScreenFrame.bytesPerPixel,
            pixels.count >= rowBytes * (size.height - 1) + size.width * ScreenFrame.bytesPerPixel
        else { return nil }
        self.size = size
        self.pixels = pixels
        self.bytesPerRow = rowBytes
    }

    /// The pixels of an image whose data is RGBA or RGBX, 8 bits a channel (as Pane's frames
    /// are). Nil for any other layout.
    public init?(image: CGImage) {
        let bitsPerChannel = 8
        guard image.bitsPerComponent == bitsPerChannel,
            image.bitsPerPixel == bitsPerChannel * ScreenFrame.bytesPerPixel,
            [.noneSkipLast, .premultipliedLast, .last].contains(image.alphaInfo),
            let data = image.dataProvider?.data as Data?
        else { return nil }
        self.init(
            size: PixelSize(width: image.width, height: image.height), pixels: data, bytesPerRow: image.bytesPerRow)
    }

    /// The colour at a pixel; coordinates outside the image are clamped to its edge.
    public func colour(x: Int, y: Int) -> PickedColour {
        let column = min(max(x, 0), size.width - 1)
        let row = min(max(y, 0), size.height - 1)
        let offset = pixels.startIndex + row * bytesPerRow + column * ScreenFrame.bytesPerPixel
        return PickedColour(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
    }

    /// The image pixel under a point on the drawn screen (`viewSize` points, y down).
    public func pixel(at point: CGPoint, viewSize: CGSize) -> (x: Int, y: Int) {
        guard viewSize.width > 0, viewSize.height > 0 else { return (0, 0) }
        let x = Int((point.x / viewSize.width * CGFloat(size.width)).rounded(.down))
        let y = Int((point.y / viewSize.height * CGFloat(size.height)).rounded(.down))
        return (min(max(x, 0), size.width - 1), min(max(y, 0), size.height - 1))
    }

    /// The square of pixels around one, row by row, for the loupe: `2 × radius + 1` a side,
    /// with the centre pixel in the middle. Past the image's edge the edge pixel repeats.
    public func neighbourhood(x: Int, y: Int, radius: Int) -> [[PickedColour]] {
        (-radius...radius).map { dy in (-radius...radius).map { dx in colour(x: x + dx, y: y + dy) } }
    }
}
