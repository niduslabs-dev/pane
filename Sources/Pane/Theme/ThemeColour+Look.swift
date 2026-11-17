import AppKit
import SwiftUI

/// How Pane draws a token colour. Always through these, never the generated `color` or
/// `platformColor`: SwiftUI resolves `Color(nsColor:)` with a plain light or dark appearance
/// even when contrast is increased, so only `ColourLook` (which also reads the system setting
/// and `-PaneIncreaseContrast`) picks the Increase Contrast values reliably.
extension ThemeColour {
    /// Follows the drawing appearance and Increase Contrast.
    var nsColor: NSColor {
        let colour = self
        return NSColor(name: nil) { appearance in colour.value(for: ColourLook(appearance)).nsColor }
    }

    /// `nsColor` for SwiftUI.
    var swiftUI: Color { Color(nsColor: nsColor) }

    /// The token with every alpha at 1: the same colour where no blur is drawn under it
    /// (Reduce Transparency, Increase Contrast).
    var opaque: ThemeColour {
        ThemeColour(
            light: light.opaque, dark: dark.opaque, lightContrast: lightContrast.opaque,
            darkContrast: darkContrast.opaque)
    }

    /// The Increase Contrast step in every look: text that sits on a shade which would take
    /// the plain value under 4.5:1 (the switcher's model line on its pressed shade, board 20).
    var contrastStep: ThemeColour {
        ThemeColour(light: lightContrast, dark: darkContrast, lightContrast: lightContrast, darkContrast: darkContrast)
    }

    func value(for look: ColourLook) -> RGBA {
        switch look {
        case .light: light
        case .dark: dark
        case .lightContrast: lightContrast
        case .darkContrast: darkContrast
        }
    }
}

extension ThemeColour.RGBA {
    /// One fixed value, for a surface that is only ever drawn in one mode.
    var nsColor: NSColor { NSColor(hex: hex, alpha: alpha) }
    var swiftUI: Color { Color(nsColor: nsColor) }
    var opaque: Self { Self(hex) }
}
