import AppKit
import PaneCore
import SwiftUI

/// Every size, colour and type style Pane draws with, named after `docs/mac-app-design.md` and the
/// approved board on the Pane design canvas (frame geometry and colours from its `renderVals`).
/// Views never hold raw numbers.
enum Theme {
    /// The studio spacing scale (design guide 1.1); only the steps Pane uses.
    enum Space {
        static let xl: CGFloat = 24
    }

    /// The window around the device: a title row, then the frame with insets on three sides.
    enum Window {
        /// The title row: traffic lights, centred device name and meta, then the tools.
        static let titleRowHeight: CGFloat = 52
        /// Left, right and bottom inset around the frame (design token `space.xl`).
        static let contentInset = Space.xl
        static let titleRowLeadingPadding: CGFloat = 20
        /// Room the system's traffic lights take after the leading padding.
        static let trafficLightsWidth: CGFloat = 52
        /// Between the traffic lights, the title and the tools.
        static let titleRowGap: CGFloat = 12
        static let titleRowTrailingPadding: CGFloat = 12
        static let titleLineSpacing: CGFloat = 1
        static let toolButtonSize: CGFloat = 28
        static let toolButtonRadius: CGFloat = 8
        static let toolIconSize: CGFloat = 16
        static let toolSpacing: CGFloat = 2
        /// Width of the tools group, so the centred title stays centred on the window.
        static let toolsWidth: CGFloat = 92
        static let disabledToolOpacity: CGFloat = 0.45
    }

    /// The device frame we draw: body, bezel, screen corners, punch hole and side buttons.
    enum Frame {
        /// The drawn screen's height; the width follows the device's aspect (1080 × 2400 → 315).
        static let screenHeight: CGFloat = 700
        /// The screen height the button positions below were designed at.
        static let referenceScreenHeight: CGFloat = 700
        static let bezel: CGFloat = 10
        static let bodyRadius: CGFloat = 46
        static let screenRadius: CGFloat = 36
        static let punchHoleDiameter: CGFloat = 11
        static let punchHoleTop: CGFloat = 12
        static let punchHoleRingWidth: CGFloat = 1.5
        /// The body's outer hairline, then a body-coloured gap, then a faint inner ring.
        static let edgeWidth: CGFloat = 1
        static let innerEdgeInset: CGFloat = 3
        static let innerEdgeWidth: CGFloat = 0.5
        static let buttonDepth: CGFloat = 3
        /// The power button widens by a point on hover, to show it's clickable.
        static let buttonDepthHover: CGFloat = 4
        static let buttonCornerRadius: CGFloat = 2
        static let buttonHitDepth: CGFloat = 14
        static let buttonHitOutset: CGFloat = 4
        static let buttons = [
            FrameButtonSpec(button: .power, top: 150, length: 56),
            FrameButtonSpec(button: .volumeUp, top: 232, length: 46),
            FrameButtonSpec(button: .volumeDown, top: 278, length: 46),
        ]
        /// Used until the AVD's `config.ini` or the first frame says otherwise.
        static let fallbackDeviceSize = PixelSize(width: 1080, height: 2400)

        static let spec = FrameSpec(
            screenHeight: screenHeight, referenceScreenHeight: referenceScreenHeight, bezel: bezel,
            bodyRadius: bodyRadius, screenRadius: screenRadius, punchHoleDiameter: punchHoleDiameter,
            punchHoleTop: punchHoleTop, buttons: buttons, buttonDepth: buttonDepth, buttonHitDepth: buttonHitDepth,
            buttonHitOutset: buttonHitOutset, titleRowHeight: Window.titleRowHeight,
            contentInset: Window.contentInset)
    }

    /// Type styles (design guide 1.2).
    enum Typeface {
        static let windowTitle = Font.system(size: 13, weight: .semibold)
        static let meta = Font.system(size: 11)
        static let screenMessage = Font.system(size: 13)
    }

    /// Colours, light and dark (ink). Light values are the board's `light`, dark its `ink`.
    enum Palette {
        /// Window background, title bar included (`titleBarMatchesContent`). The board's dark
        /// value is ink glass (`#1C1B22` at 94% over the desktop); the spike draws it solid.
        static let surface = dynamic(light: 0xF4F4F6, dark: 0x1C1B22)
        static let text = dynamic(light: 0x17161C, dark: 0xF4F4F6)
        static let textSecondary = dynamic(light: 0x64636C, dark: 0xB9B8C2)
        static let icon = dynamic(light: 0x3E3D45, dark: 0xD6D5DD)
        static let frameBody = dynamic(light: 0x1F1E25, dark: 0x0E0E12)
        static let frameEdge = dynamic(light: 0x17161C, lightAlpha: 0.55, dark: 0xF4F4F6, darkAlpha: 0.22)
        static let frameInnerEdge = dynamic(light: 0xFFFFFF, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.06)
        static let frameButton = dynamic(light: 0x2B2A32, dark: 0x3A3943)
        static let frameButtonHover = dynamic(light: 0x5A5964, dark: 0x7A7984)
        static let punchHole = NSColor(hex: 0x0B0B0E)
        static let punchHoleRing = NSColor(hex: 0x1E1E24)
        /// The screen before the first frame and in the no-emulator state.
        static let screenOff = NSColor(hex: 0x000000)
        static let screenEmpty = NSColor(hex: 0x111116)
        static let screenMessage = NSColor(hex: 0xB9B8C2)

        static func dynamic(
            light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1
        ) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
            }
        }
    }
}

extension NSColor {
    /// An sRGB colour from `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let channelMax: CGFloat = 255
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / channelMax, green: CGFloat((hex >> 8) & 0xFF) / channelMax,
            blue: CGFloat(hex & 0xFF) / channelMax, alpha: alpha)
    }
}

extension Theme {
    /// Values for logging, not drawing.
    enum Diagnostics {
        /// How often frame rate, drops and latency are logged while frames arrive.
        static let frameStatsInterval: Double = 1
    }
}
