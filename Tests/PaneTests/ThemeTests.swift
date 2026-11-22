import AppKit
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
        // Title row 52, frame 720, toolbar band 54 (Device Hub's).
        #expect(layout.windowContentSize.height == 826)
        // The board's window is 388 wide with the frame centred; Pane derives it from the
        // inset plus the buttons' depth on both sides, a point wider.
        #expect(layout.windowContentSize.width == 389)
    }

    /// Board 28: one set of points; a tablet's on the top edge from the right end, the rest on
    /// the right edge from the top.
    @Test func buttonsPerKind() {
        let points = Theme.Frame.buttons.map { [$0.offset, $0.length] }
        #expect(points == [[150, 56], [232, 46], [278, 46]])
        for kind in [DeviceKind.phone, .foldable] {
            #expect(Theme.Frame.buttons(for: kind).allSatisfy { $0.edge == .right && $0.end == .top })
            #expect(Theme.Frame.spec(for: kind) == Theme.Frame.spec)
        }
        let tablet = Theme.Frame.buttons(for: .tablet)
        #expect(tablet.allSatisfy { $0.edge == .top && $0.end == .right })
        #expect(tablet.map { [$0.offset, $0.length] } == points)
        #expect(tablet.map(\.button) == [.power, .volumeUp, .volumeDown])
    }
}

@Suite struct GlassTests {
    /// WCAG contrast between two sRGB colours.
    private func contrast(_ a: [CGFloat], _ b: [CGFloat]) -> CGFloat {
        func luminance(_ c: [CGFloat]) -> CGFloat {
            let l = c.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func channels(_ color: NSColor, _ appearance: NSAppearance.Name) -> [CGFloat] {
        let resolved = color.resolved(for: NSAppearance(named: appearance)!)
        return [resolved.redComponent, resolved.greenComponent, resolved.blueComponent]
    }

    /// The worst case behind the glass is pure black in light and pure white in dark: the
    /// tint alone must keep secondary text at 4.5:1.
    @MainActor @Test func secondaryTextKeepsItsContrastOverAnyDesktop() {
        let paper = channels(Theme.Palette.surface, .aqua).map { $0 * Theme.Glass.lightTintOpacity }
        #expect(contrast(channels(Theme.Palette.textSecondary, .aqua), paper) >= 4.5)
        let ink = channels(Theme.Palette.surface, .darkAqua).map {
            $0 * Theme.Glass.darkTintOpacity + (1 - Theme.Glass.darkTintOpacity)
        }
        #expect(contrast(channels(Theme.Palette.textSecondary, .darkAqua), ink) >= 4.5)
    }

    @Test func glassInBothModesUnlessReducedOrHighContrast() {
        #expect(GlassBackgroundView.showsGlass(reduceTransparency: false, increaseContrast: false))
        #expect(!GlassBackgroundView.showsGlass(reduceTransparency: true, increaseContrast: false))
        #expect(!GlassBackgroundView.showsGlass(reduceTransparency: false, increaseContrast: true))
    }
}
