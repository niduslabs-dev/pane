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
        buttons: [
            FrameButtonSpec(button: .power, offset: 150, length: 56),
            FrameButtonSpec(button: .volumeUp, offset: 232, length: 46),
            FrameButtonSpec(button: .volumeDown, offset: 278, length: 46),
        ],
        buttonDepth: 3, buttonHitDepth: 14, buttonHitOutset: 4, titleRowHeight: 52, contentInset: 24,
        bottomInset: 24)

    private static let pixel8 = PixelSize(width: 1080, height: 2400)

    @Test func matchesTheBoardForA1080By2400Device() {
        let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8)
        // Body 335 × 720 below the 52 pt title row, 24 + 3 pt in from the left.
        #expect(layout.bodyRect == CGRect(x: 27, y: 52, width: 335, height: 720))
        #expect(layout.screenRect == CGRect(x: 37, y: 62, width: 315, height: 700))
        #expect(layout.windowContentSize == CGSize(width: 389, height: 796))
        #expect(layout.bodyRadius == 46)
        #expect(layout.screenRadius == 36)
    }

    @Test func buttonsAndHitAreasMatchTheBoard() {
        let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8)
        let byButton = Dictionary(uniqueKeysWithValues: layout.buttons.map { ($0.button, $0) })
        #expect(byButton[.power]?.visibleRect == CGRect(x: 362, y: 202, width: 3, height: 56))
        #expect(byButton[.power]?.hitRect == CGRect(x: 362, y: 198, width: 14, height: 64))
        #expect(byButton[.power]?.roundedCorners == [.topRight, .bottomRight])
        // The rocker's hit areas meet at the seam instead of overlapping, and only its outer
        // ends are rounded.
        #expect(byButton[.volumeUp]?.hitRect == CGRect(x: 362, y: 280, width: 14, height: 50))
        #expect(byButton[.volumeDown]?.hitRect == CGRect(x: 362, y: 330, width: 14, height: 50))
        #expect(byButton[.volumeUp]?.roundedCorners == [.topRight])
        #expect(byButton[.volumeDown]?.roundedCorners == [.bottomRight])
        #expect(layout.button(at: CGPoint(x: 372, y: 329.9)) == .volumeUp)
        #expect(layout.button(at: CGPoint(x: 372, y: 330)) == .volumeDown)
        #expect(layout.button(at: CGPoint(x: 372, y: 199)) == .power)
        #expect(layout.button(at: CGPoint(x: 372, y: 272)) == nil)
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

    @Test func theFrameScalesWithTheScreenButHairlinesDoNot() {
        let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8, screenHeight: 350)
        #expect(layout.screenRect.size == CGSize(width: 158, height: 350))
        #expect(layout.bodyRect.size == CGSize(width: 168, height: 360))
        #expect(layout.bodyRadius == 23)
        #expect(layout.screenRadius == 18)
        let power = layout.buttons.first { $0.button == .power }
        // Positions halve; the 3 pt depth and the title row don't.
        #expect(power?.visibleRect == CGRect(x: layout.bodyRect.maxX, y: 52 + 75, width: 3, height: 28))
        #expect(layout.windowContentSize == CGSize(width: 168 + 54, height: 52 + 360 + 24))
    }

    @Test func fittingFindsTheLargestScreenThatFits() {
        let range: ClosedRange<CGFloat> = 360...2400
        let exact = DeviceFrameLayout.screenHeight(
            fitting: CGSize(width: 389, height: 796), spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: 0,
            range: range)
        #expect(exact == 700)
        // Too wide for its height: the height decides, and the result fits both ways.
        let wide = DeviceFrameLayout.screenHeight(
            fitting: CGSize(width: 900, height: 600), spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: 0,
            range: range)
        let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8, screenHeight: wide)
        #expect(layout.windowContentSize.height <= 600)
        #expect(layout.windowContentSize.height > 600 - 2)
        // Never below the minimum or above the maximum.
        let tiny = DeviceFrameLayout.screenHeight(
            fitting: CGSize(width: 50, height: 50), spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: 0,
            range: range)
        #expect(tiny == 360)
        let landscape = DeviceFrameLayout.screenHeight(
            fitting: CGSize(width: 2000, height: 500), spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: 1,
            range: range)
        let turned = DeviceFrameLayout(
            spec: Self.boardSpec, deviceSize: Self.pixel8, screenHeight: landscape, quadrants: 1)
        #expect(turned.windowContentSize.height <= 500)
        #expect(turned.windowContentSize.width <= 2000)
    }

    @Test func theSmallestScreenKeepsTheWindowWideEnough() {
        let portrait = DeviceFrameLayout.smallestScreenHeight(
            forWindowWidth: 270, spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: 0, floor: 360)
        let width = { (height: CGFloat) in
            DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8, screenHeight: height)
                .windowContentSize.width
        }
        #expect(portrait > 360)
        #expect(width(portrait) >= 270)
        #expect(width(portrait - 1) < 270)
        // Turned sideways the window is wide already, so the floor stands.
        let landscape = DeviceFrameLayout.smallestScreenHeight(
            forWindowWidth: 270, spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: 1, floor: 360)
        #expect(landscape == 360)
    }

    @Test func landscapePutsTheButtonsOnTop() {
        let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: 1)
        // The body turns: 720 × 335, with room for the buttons' depth above it.
        #expect(layout.bodyRect == CGRect(x: 24, y: 55, width: 720, height: 335))
        #expect(layout.screenRect == CGRect(x: 34, y: 65, width: 700, height: 315))
        let power = layout.buttons.first { $0.button == .power }
        #expect(power?.edge == .top)
        #expect(power?.visibleRect == CGRect(x: 24 + 150, y: 52, width: 56, height: 3))
        #expect(power?.roundedCorners == [.topLeft, .topRight])
        #expect(layout.windowContentSize == CGSize(width: 768, height: 55 + 335 + 24))
    }

    @Test func everyOrientationKeepsTheButtonsOutside() {
        for quadrants in 0..<4 {
            let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: quadrants)
            let expected: FrameEdge = [.right, .top, .left, .bottom][quadrants]
            for button in layout.buttons {
                #expect(button.edge == expected)
                #expect(!button.visibleRect.intersects(layout.bodyRect))
                #expect(button.visibleRect.minX >= 0 && button.visibleRect.minY >= 0)
                #expect(button.visibleRect.maxX <= layout.windowContentSize.width)
                #expect(button.visibleRect.maxY <= layout.windowContentSize.height)
            }
            #expect(layout.bodyRect.contains(layout.screenRect))
        }
        // Upside down: the buttons are on the left, and the hover state grows outwards.
        let flipped = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8, quadrants: 2)
        let power = flipped.buttons.first { $0.button == .power }
        #expect(power?.visibleRect(depth: 4).maxX == flipped.bodyRect.minX)
        #expect(power?.visibleRect(depth: 4).width == 4)
    }

    @Test func onlyTheNearestButtonWithinReachReacts() {
        let layout = DeviceFrameLayout(spec: Self.boardSpec, deviceSize: Self.pixel8)
        // Power is drawn at x 362...365, y 202...258.
        #expect(layout.nearestButton(to: CGPoint(x: 340, y: 230), within: 24) == .power)  // from the screen side
        #expect(layout.nearestButton(to: CGPoint(x: 389, y: 230), within: 24) == .power)  // from outside the frame
        #expect(layout.nearestButton(to: CGPoint(x: 330, y: 230), within: 24) == nil)  // 32 pt away
        // Between power and volume up (280...330), the closer one wins.
        #expect(layout.nearestButton(to: CGPoint(x: 364, y: 262), within: 24) == .power)
        #expect(layout.nearestButton(to: CGPoint(x: 364, y: 276), within: 24) == .volumeUp)
        #expect(layout.nearestButton(to: CGPoint(x: 364, y: 340), within: 24) == .volumeDown)
    }

    @Test func keyNamesAreW3C() {
        #expect(FrameButton.power.keyName == "Power")
        #expect(FrameButton.volumeUp.keyName == "AudioVolumeUp")
        #expect(FrameButton.volumeDown.keyName == "AudioVolumeDown")
    }
}

@Suite struct RotationTests {
    @Test func zAnglesStayInTheProtoRange() {
        #expect([0, 1, 2, 3, 4, -1].map(EmulatorConnection.zRotationDegrees(quadrants:)) == [0, 90, 180, -90, 0, -90])
    }
}

/// Which orientations a rotation follows while turns are waiting.
struct RotationRequestsTests {
    @Test func eachPressTurnsOnceMoreFromTheLastAsked() {
        var requests = RotationRequests()
        #expect(requests.ask(from: 0) == 1)
        #expect(requests.ask(from: 0) == 2)
        #expect(requests.ask(from: 0) == 3)
        #expect(requests.ask(from: 0) == 0)
        #expect(requests.waiting == [1, 2, 3, 0])
    }

    @Test func aLateFrameForAnEarlierPressIsStillFollowed() {
        var requests = RotationRequests()
        _ = requests.ask(from: 0)
        _ = requests.ask(from: 0)
        #expect(requests.follows(1))
        requests.shown(1)
        #expect(requests.waiting == [2])
        #expect(requests.isWaiting(for: 2))
    }

    @Test func anOrientationOnTheWayIsIgnoredWhileWaiting() {
        var requests = RotationRequests()
        _ = requests.ask(from: 2)
        #expect(requests.follows(3))
        #expect(!requests.follows(0))
        requests.shown(3)
        #expect(requests.follows(0))
    }

    @Test func givingUpOnTheLatestFollowsAnythingAgain() {
        var requests = RotationRequests()
        _ = requests.ask(from: 0)
        let latest = requests.ask(from: 0)
        requests.giveUp(on: 1)
        #expect(requests.isWaiting(for: latest))
        requests.giveUp(on: latest)
        #expect(requests.waiting.isEmpty)
        #expect(requests.follows(0))
    }
}
