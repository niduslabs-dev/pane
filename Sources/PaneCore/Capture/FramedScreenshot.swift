import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The colours and line widths the device frame is drawn with around a screenshot. Widths are
/// in the same design points as `FrameSpec` (for its reference screen height).
public struct FrameStyle {
    public var body: CGColor
    public var edge: CGColor
    public var innerEdge: CGColor
    public var button: CGColor
    public var buttonEdge: CGColor
    public var punchHole: CGColor
    public var punchHoleRing: CGColor
    public var edgeWidth: CGFloat
    public var innerEdgeInset: CGFloat
    public var innerEdgeWidth: CGFloat
    public var buttonEdgeWidth: CGFloat
    public var buttonCornerRadius: CGFloat
    public var punchHoleRingWidth: CGFloat

    public init(
        body: CGColor, edge: CGColor, innerEdge: CGColor, button: CGColor, buttonEdge: CGColor, punchHole: CGColor,
        punchHoleRing: CGColor, edgeWidth: CGFloat, innerEdgeInset: CGFloat, innerEdgeWidth: CGFloat,
        buttonEdgeWidth: CGFloat, buttonCornerRadius: CGFloat, punchHoleRingWidth: CGFloat
    ) {
        self.body = body
        self.edge = edge
        self.innerEdge = innerEdge
        self.button = button
        self.buttonEdge = buttonEdge
        self.punchHole = punchHole
        self.punchHoleRing = punchHoleRing
        self.edgeWidth = edgeWidth
        self.innerEdgeInset = innerEdgeInset
        self.innerEdgeWidth = innerEdgeWidth
        self.buttonEdgeWidth = buttonEdgeWidth
        self.buttonCornerRadius = buttonCornerRadius
        self.punchHoleRingWidth = punchHoleRingWidth
    }
}

/// Include Device Frame: draws Pane's own frame around a full-size screenshot, on a
/// transparent background, at the screenshot's own pixel scale.
public enum FramedScreenshot {
    /// The frame's layout for a screenshot `screenshotSize` pixels large: the window's layout
    /// with no title row, insets or toolbar band, scaled so the screen is the screenshot.
    public static func layout(spec: FrameSpec, screenshotSize: PixelSize, quadrants: Int) -> DeviceFrameLayout {
        let turned = quadrants % 2 != 0
        let portrait = turned ? screenshotSize.transposed : screenshotSize
        let scale = spec.referenceScreenHeight > 0 ? CGFloat(portrait.height) / spec.referenceScreenHeight : 1
        var bare = spec
        bare.titleRowHeight = 0
        bare.contentInset = 0
        bare.bottomInset = 0
        bare.buttonDepth = (spec.buttonDepth * scale).rounded()
        return DeviceFrameLayout(
            spec: bare, deviceSize: portrait, screenHeight: CGFloat(portrait.height), quadrants: quadrants)
    }

    /// The screenshot inside the frame. `quadrants` is how the device is turned, which the
    /// screenshot (already upright) doesn't say.
    public static func render(screenshot: CGImage, spec: FrameSpec, quadrants: Int, style: FrameStyle) -> CGImage? {
        let size = PixelSize(width: screenshot.width, height: screenshot.height)
        let layout = layout(spec: spec, screenshotSize: size, quadrants: quadrants)
        let scale = spec.referenceScreenHeight > 0 ? layout.screenHeight / spec.referenceScreenHeight : 1
        let canvas = layout.windowContentSize
        let bitsPerComponent = 8
        guard
            let context = CGContext(
                data: nil, width: Int(canvas.width.rounded(.up)), height: Int(canvas.height.rounded(.up)),
                bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Layout rects have y growing down; flip so they can be used as they are.
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: 1, y: -1)

        for button in layout.buttons {
            let path = CGPath(
                roundedRect: button.visibleRect.insetBy(dx: 0, dy: 0),
                cornerWidth: min(style.buttonCornerRadius * scale, button.visibleRect.width / 2),
                cornerHeight: min(style.buttonCornerRadius * scale, button.visibleRect.height / 2), transform: nil)
            context.addPath(path)
            context.setFillColor(style.button)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(style.buttonEdge)
            context.setLineWidth(style.buttonEdgeWidth * scale)
            context.strokePath()
        }

        let body = layout.bodyRect
        context.addPath(roundedPath(body, radius: layout.bodyRadius))
        context.setFillColor(style.body)
        context.fillPath()
        let edgeWidth = style.edgeWidth * scale
        context.addPath(
            roundedPath(body.insetBy(dx: edgeWidth / 2, dy: edgeWidth / 2), radius: layout.bodyRadius - edgeWidth / 2))
        context.setStrokeColor(style.edge)
        context.setLineWidth(edgeWidth)
        context.strokePath()
        let innerInset = style.innerEdgeInset * scale
        context.addPath(
            roundedPath(body.insetBy(dx: innerInset, dy: innerInset), radius: layout.bodyRadius - innerInset))
        context.setStrokeColor(style.innerEdge)
        context.setLineWidth(style.innerEdgeWidth * scale)
        context.strokePath()

        context.saveGState()
        context.addPath(roundedPath(layout.screenRect, radius: layout.screenRadius))
        context.clip()
        // Images draw bottom up; flip back inside the screen's rect.
        context.translateBy(x: layout.screenRect.minX, y: layout.screenRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(screenshot, in: CGRect(origin: .zero, size: layout.screenRect.size))
        context.restoreGState()

        let hole = layout.punchHoleRect
        context.setFillColor(style.punchHole)
        context.fillEllipse(in: hole)
        let ring = style.punchHoleRingWidth * scale
        context.setStrokeColor(style.punchHoleRing)
        context.setLineWidth(ring)
        context.strokeEllipse(in: hole.insetBy(dx: ring / 2, dy: ring / 2))
        return context.makeImage()
    }

    public static func image(fromPNG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    public static func png(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let fitted = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: fitted, cornerHeight: fitted, transform: nil)
    }
}
