import CoreGraphics
import Testing

@testable import PaneCore

@Suite struct ScreenSizingTests {
    private let pixel8 = PixelSize(width: 1080, height: 2400)
    private let density = 420
    /// A 14-inch MacBook Pro: 1512 points wide on 302 mm, at 2×.
    private let retina = DisplayMetrics(backingScale: 2, widthPoints: 1512, widthMillimetres: 302)
    /// A 24-inch 1080p display at 1×: 1920 points on 527 mm.
    private let standard = DisplayMetrics(backingScale: 1, widthPoints: 1920, widthMillimetres: 527)

    @Test func pointAccurateIsOneDpPerPoint() {
        // 2400 px × 160 / 420 = 914.3 dp, the same on any display.
        let size = ScreenSizing.longSide(.point, deviceSize: pixel8, density: density, display: retina)
        #expect(abs((size ?? 0) - 914.2857) < 0.001)
        #expect(ScreenSizing.longSide(.point, deviceSize: pixel8, density: density, display: standard) == size)
    }

    @Test func pixelAccurateIsOnePixelPerBackingPixel() {
        #expect(ScreenSizing.longSide(.pixel, deviceSize: pixel8, density: density, display: retina) == 1200)
        #expect(ScreenSizing.longSide(.pixel, deviceSize: pixel8, density: density, display: standard) == 2400)
    }

    @Test func physicalMatchesTheRealPhone() {
        // 2400 / 420 = 5.714 in. Retina: 1512 pt / 11.89 in = 127.2 pt per inch → 726.7 pt.
        let retinaSize = ScreenSizing.longSide(.physical, deviceSize: pixel8, density: density, display: retina)
        #expect(abs((retinaSize ?? 0) - 726.7) < 0.1)
        // 1080p 24-inch: 1920 / 20.75 in = 92.5 pt per inch → 528.8 pt.
        let standardSize = ScreenSizing.longSide(.physical, deviceSize: pixel8, density: density, display: standard)
        #expect(abs((standardSize ?? 0) - 528.8) < 0.1)
    }

    @Test func physicalNeedsAPhysicalSize() {
        let unknown = DisplayMetrics(backingScale: 2, widthPoints: 1512, widthMillimetres: 0)
        #expect(ScreenSizing.longSide(.physical, deviceSize: pixel8, density: density, display: unknown) == nil)
        #expect(ScreenSizing.longSide(.fit, deviceSize: pixel8, density: density, display: retina) == nil)
    }

    @Test func landscapeUsesTheSameLongSide() {
        let turned = ScreenSizing.longSide(.pixel, deviceSize: pixel8.transposed, density: density, display: retina)
        #expect(turned == 1200)
    }

    @Test func zoomStepsThroughTheSortedSizes() {
        let sizes: [CGFloat] = [914.3, 1200, 726.7, 780]
        #expect(ScreenSizing.step(from: 780, among: sizes, up: true) == 914.5)
        #expect(ScreenSizing.step(from: 780, among: sizes, up: false) == 726.5)
        #expect(ScreenSizing.step(from: 1200, among: sizes, up: true) == nil)
        #expect(ScreenSizing.step(from: 726.7, among: sizes, up: false) == nil)
        // Between sizes (after a manual resize), the nearest in that direction.
        #expect(ScreenSizing.step(from: 800, among: sizes, up: true) == 914.5)
    }
}
