import CoreGraphics
import Testing

@testable import PaneCore

@Suite struct ScreenMappingTests {
    private let device = PixelSize(width: 1080, height: 2400)
    /// The board's screen: 315 × 700 points, here placed at the frame's bezel.
    private let screen = CGRect(x: 10, y: 10, width: 315, height: 700)

    @Test func cornersAndCentre() {
        let mapping = ScreenMapping(screenRect: screen, deviceSize: device)
        #expect(mapping.devicePoint(for: CGPoint(x: 10, y: 10)) == DevicePoint(x: 0, y: 0))
        #expect(mapping.devicePoint(for: CGPoint(x: 167.5, y: 360)) == DevicePoint(x: 540, y: 1200))
        #expect(mapping.devicePoint(for: CGPoint(x: 324.99, y: 709.99)) == DevicePoint(x: 1079, y: 2399))
    }

    @Test func outsideTheScreenIsNil() {
        let mapping = ScreenMapping(screenRect: screen, deviceSize: device)
        #expect(mapping.devicePoint(for: CGPoint(x: 9.9, y: 100)) == nil)
        #expect(mapping.devicePoint(for: CGPoint(x: 325, y: 100)) == nil)
        #expect(mapping.devicePoint(for: CGPoint(x: 100, y: 710)) == nil)
    }

    @Test func clampingPinsToTheEdge() {
        let mapping = ScreenMapping(screenRect: screen, deviceSize: device)
        #expect(mapping.clampedDevicePoint(for: CGPoint(x: -50, y: 360)) == DevicePoint(x: 0, y: 1200))
        #expect(mapping.clampedDevicePoint(for: CGPoint(x: 900, y: 9_000)) == DevicePoint(x: 1079, y: 2399))
    }

    /// Mapping is in points, so the backing scale must not change where a click lands.
    @Test(arguments: [1.0, 2.0, 3.0])
    func backingScaleDoesNotMoveTaps(scale: CGFloat) {
        let mapping = ScreenMapping(screenRect: screen, deviceSize: device)
        let point = CGPoint(x: 10 + 100.25, y: 10 + 200.5)
        #expect(mapping.devicePoint(for: point) == DevicePoint(x: 343, y: 687))
    }

    @Test func rotationsFollowTheDevice() {
        let landscape = CGRect(x: 0, y: 0, width: 700, height: 315)
        let topLeft = CGPoint(x: 0, y: 0)
        let bottomRight = CGPoint(x: 699.99, y: 314.99)
        let quarter = ScreenMapping(screenRect: landscape, deviceSize: device, quadrants: 1)
        #expect(quarter.devicePoint(for: topLeft) == DevicePoint(x: 1079, y: 0))
        #expect(quarter.devicePoint(for: bottomRight) == DevicePoint(x: 0, y: 2399))
        let half = ScreenMapping(screenRect: screen, deviceSize: device, quadrants: 2)
        #expect(half.devicePoint(for: CGPoint(x: 10, y: 10)) == DevicePoint(x: 1079, y: 2399))
        let threeQuarters = ScreenMapping(screenRect: landscape, deviceSize: device, quadrants: -1)
        #expect(threeQuarters.quadrants == 3)
        #expect(threeQuarters.devicePoint(for: topLeft) == DevicePoint(x: 0, y: 2399))
    }

    @Test func requestsBackingPixelsBothSidesSet() {
        let retina = ScreenMapping.requestedImageSize(
            screenPoints: CGSize(width: 315, height: 700), backingScale: 2, deviceSize: device)
        #expect(retina == PixelSize(width: 630, height: 1400))
        let standard = ScreenMapping.requestedImageSize(
            screenPoints: CGSize(width: 315, height: 700), backingScale: 1, deviceSize: device)
        #expect(standard == PixelSize(width: 315, height: 700))
    }

    @Test func neverRequestsMoreThanTheDevice() {
        let size = ScreenMapping.requestedImageSize(
            screenPoints: CGSize(width: 315, height: 700), backingScale: 4, deviceSize: device)
        #expect(size == device)
    }

    @Test func rotatedRequestsAreLandscape() {
        let size = ScreenMapping.requestedImageSize(
            screenPoints: CGSize(width: 700, height: 315), backingScale: 2, deviceSize: device, quadrants: 1)
        #expect(size == PixelSize(width: 1400, height: 630))
    }
}

@Suite struct DeviceFrameLayoutTests {
    /// The approved board's values (Pane design canvas, live state).
    static let boardSpec = FrameSpec(
        screenHeight: 700, referenceScreenHeight: 700, bezel: 10, bodyRadius: 46, screenRadius: 36,
        punchHoleDiameter: 11, punchHoleTop: 12,
        buttons: [
            FrameButtonSpec(button: .power, top: 150, length: 56),
            FrameButtonSpec(button: .volumeUp, top: 232, length: 46),
            FrameButtonSpec(button: .volumeDown, top: 278, length: 46),
        ],
        buttonDepth: 3, buttonHitDepth: 14, buttonHitOutset: 4, titleRowHeight: 52, contentInset: 24)

    @Test func matchesTheBoardForA1080By2400Device() {
        let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: PixelSize(width: 1080, height: 2400))
        #expect(layout.bodyRect == CGRect(x: 0, y: 0, width: 335, height: 720))
        #expect(layout.screenRect == CGRect(x: 10, y: 10, width: 315, height: 700))
        // 11 pt hole, 12 pt from the screen's top, centred.
        #expect(layout.punchHoleRect == CGRect(x: 162, y: 22, width: 11, height: 11))
        #expect(layout.windowContentSize.height == 796)
        #expect(layout.bodyOriginInWindow == CGPoint(x: 27, y: 52))
    }

    @Test func buttonsAndHitAreasMatchTheBoard() {
        let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: PixelSize(width: 1080, height: 2400))
        let byButton = Dictionary(uniqueKeysWithValues: layout.buttons.map { ($0.button, $0) })
        #expect(byButton[.power]?.visibleRect == CGRect(x: 335, y: 150, width: 3, height: 56))
        #expect(byButton[.power]?.hitRect == CGRect(x: 335, y: 146, width: 14, height: 64))
        // The rocker's hit areas meet at the seam instead of overlapping.
        #expect(byButton[.volumeUp]?.hitRect == CGRect(x: 335, y: 228, width: 14, height: 50))
        #expect(byButton[.volumeDown]?.hitRect == CGRect(x: 335, y: 278, width: 14, height: 50))
        #expect(layout.button(at: CGPoint(x: 345, y: 277.9)) == .volumeUp)
        #expect(layout.button(at: CGPoint(x: 345, y: 278)) == .volumeDown)
        #expect(layout.button(at: CGPoint(x: 345, y: 147)) == .power)
        #expect(layout.button(at: CGPoint(x: 345, y: 220)) == nil)
    }

    @Test func screenWidthFollowsTheDeviceAspect() {
        let tall = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: PixelSize(width: 1344, height: 2992))
        #expect(tall.screenRect.height == 700)
        #expect(tall.screenRect.width == 314)
        let wide = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: PixelSize(width: 1440, height: 2560))
        #expect(wide.screenRect.width == 394)
        // Screen 394, bezels 2 × 10, side margins 2 × (24 inset + 3 button depth).
        #expect(wide.windowContentSize.width == 468)
    }

    @Test func buttonPositionsScaleWithScreenHeight() {
        var spec = Self.boardSpec
        spec.screenHeight = 350
        let layout = DeviceFrameLayout(spec: spec, deviceSize: PixelSize(width: 1080, height: 2400))
        let power = layout.buttons.first { $0.button == .power }
        #expect(power?.visibleRect == CGRect(x: layout.bodyRect.maxX, y: 75, width: 3, height: 28))
    }

    @Test func keyNamesAreW3C() {
        #expect(FrameButton.power.keyName == "Power")
        #expect(FrameButton.volumeUp.keyName == "AudioVolumeUp")
        #expect(FrameButton.volumeDown.keyName == "AudioVolumeDown")
    }
}
