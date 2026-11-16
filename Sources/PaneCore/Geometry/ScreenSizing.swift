import CoreGraphics

/// The Window menu's sizes, like the iOS Simulator's: each gives the device screen's long side
/// in points (the window adds the frame and chrome around it).
public enum ScreenSizeMode: String, Sendable, CaseIterable {
    /// As big as the real phone: millimetres on the Mac's display equal millimetres on the device.
    case physical
    /// One Android dp per Mac point (dp = px × 160 / density).
    case point
    /// One device pixel per backing pixel.
    case pixel
    /// The largest that fits the screen's visible area.
    case fit
}

/// What the sizes are worked out from.
public struct DisplayMetrics: Sendable, Equatable {
    /// The display's backing scale (2 on Retina).
    public var backingScale: CGFloat
    /// The display's width in points and in millimetres (`CGDisplayScreenSize`); zero
    /// millimetres when the display doesn't report a physical size.
    public var widthPoints: CGFloat
    public var widthMillimetres: CGFloat

    public init(backingScale: CGFloat, widthPoints: CGFloat, widthMillimetres: CGFloat) {
        self.backingScale = backingScale
        self.widthPoints = widthPoints
        self.widthMillimetres = widthMillimetres
    }
}

public enum ScreenSizing {
    /// Android's baseline density: one dp is one pixel at 160 dpi.
    public static let baselineDensity: CGFloat = 160
    public static let millimetresPerInch: CGFloat = 25.4

    /// The screen's long side in points for a mode; nil for `fit` (the caller fits it to the
    /// window's screen) and for `physical` on a display with no physical size.
    public static func longSide(
        _ mode: ScreenSizeMode, deviceSize: PixelSize, density: Int, display: DisplayMetrics
    ) -> CGFloat? {
        let longPixels = CGFloat(max(deviceSize.width, deviceSize.height))
        guard longPixels > 0 else { return nil }
        switch mode {
        case .point:
            guard density > 0 else { return nil }
            return longPixels * baselineDensity / CGFloat(density)
        case .pixel:
            guard display.backingScale > 0 else { return nil }
            return longPixels / display.backingScale
        case .physical:
            guard density > 0, display.widthMillimetres > 0, display.widthPoints > 0 else { return nil }
            let deviceInches = longPixels / CGFloat(density)
            let pointsPerInch = display.widthPoints / (display.widthMillimetres / millimetresPerInch)
            return deviceInches * pointsPerInch
        case .fit:
            return nil
        }
    }

    /// The next size up (or down) from `current` among `sizes`, for Zoom In and Zoom Out.
    /// Sizes within half a point of `current` count as the same.
    public static func step(from current: CGFloat, among sizes: [CGFloat], up: Bool) -> CGFloat? {
        let tolerance: CGFloat = 0.5
        let sorted = Set(sizes.map { ($0 / tolerance).rounded() * tolerance }).sorted()
        return up ? sorted.first { $0 > current + tolerance } : sorted.last { $0 < current - tolerance }
    }
}
