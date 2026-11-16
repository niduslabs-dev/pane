import CoreGraphics

/// A size in device or image pixels.
public struct PixelSize: Sendable, Equatable, Hashable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String { "\(width)×\(height)" }

    /// The same size turned a quarter (width and height swapped).
    public var transposed: PixelSize { PixelSize(width: height, height: width) }
}

/// A point on the device's display, in device pixels of its natural (portrait) orientation:
/// what `MouseEvent` and `Touch` take.
public struct DevicePoint: Sendable, Equatable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Maps points in the window's screen area to device pixels, and picks the image size to ask for.
///
/// `screenRect` is the drawn screen in view points with y growing downwards (a flipped view).
/// `quadrants` is how many quarter turns counter-clockwise the device is rotated from portrait
/// (0 = portrait), as `Image.format.rotation` reports. The spike only draws portrait; the
/// other cases follow Android Studio's `EmulatorView` and are unverified on a device.
public struct ScreenMapping: Sendable, Equatable {
    public var screenRect: CGRect
    public var deviceSize: PixelSize
    public var quadrants: Int

    public init(screenRect: CGRect, deviceSize: PixelSize, quadrants: Int = 0) {
        self.screenRect = screenRect
        self.deviceSize = deviceSize
        self.quadrants = ((quadrants % 4) + 4) % 4
    }

    /// The device pixel under a view point, or nil when the point is outside the screen.
    public func devicePoint(for point: CGPoint) -> DevicePoint? {
        guard screenRect.width > 0, screenRect.height > 0 else { return nil }
        // The far edges are excluded so a point maps to exactly one pixel row and column.
        guard point.x >= screenRect.minX, point.x < screenRect.maxX, point.y >= screenRect.minY,
            point.y < screenRect.maxY
        else { return nil }
        return clampedDevicePoint(for: point)
    }

    /// The device pixel nearest a view point, clamping points outside the screen to its edge.
    /// Used for the release that ends a drag which left the screen.
    public func clampedDevicePoint(for point: CGPoint) -> DevicePoint {
        let u = unit((point.x - screenRect.minX) / max(screenRect.width, .leastNonzeroMagnitude))
        let v = unit((point.y - screenRect.minY) / max(screenRect.height, .leastNonzeroMagnitude))
        let (nx, ny): (CGFloat, CGFloat)
        switch quadrants {
        case 1: (nx, ny) = (1 - v, u)
        case 2: (nx, ny) = (1 - u, 1 - v)
        case 3: (nx, ny) = (v, 1 - u)
        default: (nx, ny) = (u, v)
        }
        return DevicePoint(x: pixel(nx, count: deviceSize.width), y: pixel(ny, count: deviceSize.height))
    }

    /// The image size to request from `streamScreenshot`: the screen area in backing pixels,
    /// never larger than the device, aspect kept. Both sides are always set, because the
    /// emulator ignores scaling when only one is.
    public static func requestedImageSize(
        screenPoints: CGSize, backingScale: CGFloat, deviceSize: PixelSize, quadrants: Int = 0
    ) -> PixelSize {
        let displayed = quadrants % 2 == 0 ? deviceSize : deviceSize.transposed
        guard displayed.width > 0, displayed.height > 0 else { return displayed }
        let wantedWidth = screenPoints.width * backingScale
        let wantedHeight = screenPoints.height * backingScale
        let scale = min(1, wantedWidth / CGFloat(displayed.width), wantedHeight / CGFloat(displayed.height))
        guard scale > 0 else { return PixelSize(width: 1, height: 1) }
        return PixelSize(
            width: max(1, Int((CGFloat(displayed.width) * scale).rounded())),
            height: max(1, Int((CGFloat(displayed.height) * scale).rounded()))
        )
    }

    private func unit(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

    private func pixel(_ fraction: CGFloat, count: Int) -> Int {
        min(max(Int((fraction * CGFloat(count)).rounded(.down)), 0), max(count - 1, 0))
    }
}
