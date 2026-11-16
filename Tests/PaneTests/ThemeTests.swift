import CoreGraphics
import PaneCore
import Testing

@testable import Pane

/// The app's real `Theme` reproduces the approved board for the emulator Pane is built against.
@Suite struct ThemeTests {
    @Test func frameMatchesTheBoard() {
        let layout = DeviceFrameLayout(spec: Theme.Frame.spec, deviceSize: Theme.Frame.fallbackDeviceSize)
        #expect(layout.bodyRect.size == CGSize(width: 335, height: 720))
        #expect(layout.screenRect.size == CGSize(width: 315, height: 700))
        // Title row 52, frame 720, toolbar band 88 (Layout 2).
        #expect(layout.windowContentSize.height == 860)
        // The board's window is 388 wide with the frame centred; Pane derives it from the
        // inset plus the buttons' depth on both sides, a point wider.
        #expect(layout.windowContentSize.width == 389)
    }
}

@Suite struct GlassTests {
    @Test func glassInBothModesUnlessReducedOrHighContrast() {
        #expect(GlassBackgroundView.showsGlass(reduceTransparency: false, increaseContrast: false))
        #expect(!GlassBackgroundView.showsGlass(reduceTransparency: true, increaseContrast: false))
        #expect(!GlassBackgroundView.showsGlass(reduceTransparency: false, increaseContrast: true))
    }
}
