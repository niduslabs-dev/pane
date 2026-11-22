import CoreGraphics
import Foundation
import Testing

@testable import PaneCore

/// Board 27: the window follows the screen Android shows (folded or not), and reshapes.
@Suite struct LiveScreenTests {
    /// Pixel 9 Pro Fold: `config.ini`'s inner screen and the folded outer screen
    /// (`.claude/research/fold-stretch.md`).
    static let inner = PixelSize(width: 2076, height: 2152)
    static let folded = PixelSize(width: 1080, height: 2424)

    // MARK: Live size

    @Test func foldedDisplayWinsOverTheConfiguredScreen() {
        #expect(LiveScreen.size(foldedDisplay: Self.folded, configured: Self.inner) == Self.folded)
        #expect(LiveScreen.size(foldedDisplay: nil, configured: Self.inner) == Self.inner)
        #expect(LiveScreen.size(foldedDisplay: nil, configured: nil) == nil)
    }

    @Test func aFrameOfAnotherSizeThanRequestedIsDropped() {
        #expect(LiveScreen.frame(liveSize: Self.folded, matches: Self.folded))
        #expect(!LiveScreen.frame(liveSize: Self.folded, matches: Self.inner))
        #expect(!LiveScreen.frame(liveSize: Self.inner, matches: Self.folded))
        // No config.ini: nothing to compare, so the frame is shown.
        #expect(LiveScreen.frame(liveSize: nil, matches: Self.inner))
    }

    @Test func readsFoldedDisplayFromTheWire() throws {
        var image = Android_Emulation_Control_Image()
        image.format.format = .rgba8888
        image.format.width = 2
        image.format.height = 4
        image.format.foldedDisplay.width = 1080
        image.format.foldedDisplay.height = 2424
        image.image = Data(repeating: 0, count: 2 * 4 * 4)
        let folded: [UInt8] = try image.serializedBytes()
        let pool = FramePixelBufferPool()
        let frame = try #require(try folded.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) })
        #expect(frame.foldedDisplay == Self.folded)
        #expect(frame.size == PixelSize(width: 2, height: 4))

        image.format.clearFoldedDisplay()
        let open: [UInt8] = try image.serializedBytes()
        let unfolded = try #require(try open.withUnsafeBytes { try StreamFrameDecoder.decode($0, into: pool) })
        #expect(unfolded.foldedDisplay == nil)
    }

    @Test func remembersOnlyAShapeOtherThanTheConfiguredOne() {
        #expect(LiveScreen.remembered(liveSize: Self.folded, configured: Self.inner) == Self.folded)
        #expect(LiveScreen.remembered(liveSize: Self.inner, configured: Self.inner) == nil)
        #expect(LiveScreen.remembered(liveSize: nil, configured: Self.inner) == nil)
        #expect(LiveScreen.parse(LiveScreen.stored(Self.folded)) == Self.folded)
        #expect(LiveScreen.parse("1080") == nil)
        #expect(LiveScreen.parse("0x2424") == nil)
    }

    // MARK: Clicks while folded

    /// The research's case: Settings open on the folded screen, "Apps" at device (250, 1061).
    /// Mapped against the inner screen's size the click went to (480, 941), "Connected devices".
    @Test func aClickOnAppsWhileFoldedLandsOnApps() {
        let layout = DeviceFrameLayout(
            spec: DeviceFrameLayoutTests.boardSpec, deviceSize: Self.folded, screenHeight: 819)
        let screen = CGRect(origin: .zero, size: layout.screenRect.size)
        let mapping = ScreenMapping(screenRect: screen, deviceSize: Self.folded)
        let apps = CGPoint(
            x: (250.5 / 1080) * screen.width, y: (1061.5 / 2424) * screen.height)
        #expect(mapping.devicePoint(for: apps) == DevicePoint(x: 250, y: 1061))
    }

    @Test func requestsTheFoldedShape() {
        let size = ScreenMapping.requestedImageSize(
            screenPoints: CGSize(width: 365, height: 819), backingScale: 2, deviceSize: Self.folded)
        #expect(size.width * 2424 / 1080 - size.height <= 2)
        let turned = ScreenMapping.requestedImageSize(
            screenPoints: CGSize(width: 819, height: 365), backingScale: 2, deviceSize: Self.folded, quadrants: 1)
        #expect(turned.width > turned.height)
    }

    // MARK: Height rule

    private static let minWidth: CGFloat = 270
    private static let floor: CGFloat = 360

    private func minimum(_ device: PixelSize, quadrants: Int) -> CGFloat {
        DeviceFrameLayout.smallestScreenHeight(
            forWindowWidth: Self.minWidth, spec: DeviceFrameLayoutTests.boardSpec, deviceSize: device,
            quadrants: quadrants, floor: Self.floor)
    }

    @Test func aForcedRaiseOnFoldNeverSticks() {
        let chosen = Self.floor
        let foldedMinimum = minimum(Self.folded, quadrants: 0)
        #expect(foldedMinimum > Self.floor)
        // Folded at the smallest size: raised so the window is wide enough.
        #expect(ScreenHeightRule.shown(chosen: chosen, minimum: foldedMinimum) == foldedMinimum)
        // Unfolded again: back to the chosen 360.
        #expect(ScreenHeightRule.shown(chosen: chosen, minimum: minimum(Self.inner, quadrants: 0)) == Self.floor)
    }

    @Test func aForcedRaiseOnATurnNeverSticks() {
        let pixel8 = PixelSize(width: 1080, height: 2400)
        let chosen = Self.floor
        // Turned, a phone is wide: the floor holds. Back to portrait it needs the raise, and
        // turning again returns to the chosen height.
        #expect(ScreenHeightRule.shown(chosen: chosen, minimum: minimum(pixel8, quadrants: 1)) == Self.floor)
        let portrait = ScreenHeightRule.shown(chosen: chosen, minimum: minimum(pixel8, quadrants: 0))
        #expect(portrait > Self.floor)
        #expect(ScreenHeightRule.shown(chosen: chosen, minimum: minimum(pixel8, quadrants: 1)) == Self.floor)
    }

    @Test func aManualSizeShrinksOnlyToFitTheDisplay() {
        #expect(ScreenHeightRule.shown(chosen: 819, minimum: 360, displayFit: 900) == 819)
        #expect(ScreenHeightRule.shown(chosen: 819, minimum: 360, displayFit: 700) == 700)
        #expect(ScreenHeightRule.shown(chosen: 819, minimum: 457, displayFit: 400) == 457)
    }

    // MARK: Morph

    @Test func theMorphMovesEveryRectTogether() {
        let spec = DeviceFrameLayoutTests.boardSpec
        let open = DeviceFrameLayout(spec: spec, deviceSize: Self.inner, screenHeight: 819)
        let shut = DeviceFrameLayout(spec: spec, deviceSize: Self.folded, screenHeight: 819)
        #expect(
            DeviceFrameLayout.interpolated(from: open, to: shut, progress: 0).windowContentSize
                == open.windowContentSize)
        #expect(DeviceFrameLayout.interpolated(from: open, to: shut, progress: 1) == shut)
        // A spring's overshoot never takes the window past its target.
        #expect(DeviceFrameLayout.interpolated(from: open, to: shut, progress: 1.002) == shut)
        let half = DeviceFrameLayout.interpolated(from: open, to: shut, progress: 0.5)
        #expect(half.screenRect.width == (open.screenRect.width + shut.screenRect.width) / 2)
        #expect(half.bodyRect.width == (open.bodyRect.width + shut.bodyRect.width) / 2)
        #expect(
            half.buttons[0].visibleRect.minX == (open.buttons[0].visibleRect.minX + shut.buttons[0].visibleRect.minX)
                / 2)
    }

    @Test func acrossATurnTheButtonsTakeTheirNewEdge() {
        let spec = DeviceFrameLayoutTests.boardSpec
        let portrait = DeviceFrameLayout(spec: spec, deviceSize: Self.folded, screenHeight: 819)
        let turned = DeviceFrameLayout(spec: spec, deviceSize: Self.folded, screenHeight: 819, quadrants: 1)
        let half = DeviceFrameLayout.interpolated(from: portrait, to: turned, progress: 0.5)
        #expect(half.buttons == turned.buttons)
        #expect(half.quadrants == 1)
    }

    // MARK: Reshape steps

    @Test func anEarlyFrameWaitsForTheMorph() {
        var transition = ReshapeTransition()
        #expect(transition.acceptsInput)
        transition.begin(reduceMotion: false)
        #expect(!transition.acceptsInput)
        #expect(transition.holdsFrames)
        let step1 = transition.frameArrived()

        #expect(!step1)
        #expect(transition.holdsFrames)
        let step2 = transition.morphSettled()

        #expect(step2)
        #expect(transition.phase == .clearing)
        #expect(!transition.acceptsInput)
        transition.cleared()
        #expect(transition.acceptsInput)
    }

    @Test func aLateFrameHoldsTheVeil() {
        var transition = ReshapeTransition()
        transition.begin(reduceMotion: false)
        let step3 = transition.morphSettled()

        #expect(!step3)
        #expect(transition.phase == .reshaping(frameIn: false, settled: true))
        #expect(transition.holdsFrames)
        let step4 = transition.frameArrived()

        #expect(step4)
        #expect(transition.clear == .unveil)
    }

    @Test func reduceMotionCrossfadesAsSoonAsTheFrameArrives() {
        var transition = ReshapeTransition()
        transition.begin(reduceMotion: true)
        #expect(transition.phase == .reshaping(frameIn: false, settled: true))
        let step5 = transition.frameArrived()

        #expect(step5)
        #expect(transition.clear == .crossfade)
        transition.cleared()
        #expect(transition.acceptsInput)
    }

    @Test func aNewShapeMidReshapeStartsOver() {
        var transition = ReshapeTransition()
        transition.begin(reduceMotion: false)
        transition.frameArrived()
        transition.begin(reduceMotion: false)
        #expect(transition.phase == .reshaping(frameIn: false, settled: false))
        // A clear that was running when the new shape came doesn't open input.
        transition.cleared()
        #expect(!transition.acceptsInput)
        transition.reset()
        #expect(transition.acceptsInput)
    }
}
