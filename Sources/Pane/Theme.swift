import AppKit
import PaneCore
import SwiftUI

/// Every size, colour and type style Pane draws with, named after `docs/mac-app-design.md` and the
/// approved board on the Pane design canvas (frame geometry and colours from its `renderVals`).
/// Views never hold raw numbers.
enum Theme {
    /// The studio spacing scale (design guide 1.1); only the steps Pane uses.
    enum Space {
        static let xxs: CGFloat = 4
        static let m: CGFloat = 12
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// What the screen shows when there is no live picture: no emulator (canvas option A),
    /// starting and booting, all on the dark off screen.
    enum Screen {
        /// Between the title and its meta line.
        static let lineGap = Space.xxs
        /// Above the Start capsule (the board's 20 on top of the 4 pt line gap).
        static let actionGap: CGFloat = 20
        /// Above "Choose another emulator" (the board's 12 on top of the line gap).
        static let linkGap = Space.m
        static let horizontalPadding = Space.xxl
        /// Below the spinner while starting or booting.
        static let progressGap = Space.m
    }

    /// The can't-connect card, which takes the frame's place (canvas error state).
    enum ErrorCard {
        static let radius: CGFloat = 14
        static let hairline: CGFloat = 0.5
        static let hairlineIncreasedContrast: CGFloat = 1
        static let horizontalPadding = Space.xxl
        static let gap = Space.m
        static let glyphSize: CGFloat = 40
        /// Extra room above the button (the board's 4 on top of the 12 pt gap).
        static let actionExtraGap = Space.xxs
    }

    /// Capsule actions (design guide, Controls).
    enum Capsule {
        static let height: CGFloat = 30
        /// Start on the screen is a little wider than a standard capsule, as on the board.
        static let startPadding: CGFloat = 20
        static let standardPadding: CGFloat = 16
        static let disabledOpacity: CGFloat = 0.45
    }

    /// The `blurSwap` status line (design guide 2).
    enum StatusSwap {
        static let blur: CGFloat = 6
        static let offsetY: CGFloat = 5
        static let springResponse: Double = 0.4
        static let springDamping: Double = 0.9
        /// Reduce Motion's plain crossfade.
        static let fadeDuration: Double = 0.2
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

    /// Ink glass (design guide `inkGlass`): behind-window blur under an ink tint, dark mode only.
    enum Glass {
        static let material = NSVisualEffectView.Material.hudWindow
        static let tintOpacity: CGFloat = 0.86
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
        static let screenTitle = Font.system(size: 15, weight: .semibold)
        static let screenMeta = Font.system(size: 12)
        static let capsule = Font.system(size: 13, weight: .semibold)
        static let link = Font.system(size: 12)
        static let cardTitle = Font.system(size: 15)
        static let cardBody = Font.system(size: 12)
        static let status = Font.system(size: 12)
    }

    /// Colours, light and dark (ink). Light values are the board's `light`, dark its `ink`.
    enum Palette {
        /// Window background, title bar included (`titleBarMatchesContent`). Dark mode draws it
        /// as ink glass (`Glass`) unless transparency is reduced or contrast increased.
        static let surface = dynamic(light: 0xF4F4F6, dark: 0x1C1B22)
        static let text = dynamic(light: 0x17161C, dark: 0xF4F4F6)
        static let textSecondary = dynamic(
            light: 0x64636C, dark: 0xB9B8C2, contrastLight: 0x45444C, contrastDark: 0xDCDBE3)
        /// The error card (`surfaceCard`): paper recessed in light, ink raised in dark.
        static let card = dynamic(light: 0xECECEF, dark: 0x24232B)
        static let hairline = dynamic(
            light: 0x17161C, lightAlpha: 0.12, dark: 0xF4F4F6, darkAlpha: 0.14, contrastLight: 0x17161C,
            contrastLightAlpha: 0.45, contrastDark: 0xF4F4F6, contrastDarkAlpha: 0.5)
        /// `actionPrimary`: moss with white text, darker under Increase Contrast.
        static let actionPrimary = dynamic(
            light: 0x4F7A4A, dark: 0x4F7A4A, contrastLight: 0x3A5C36, contrastDark: 0x3A5C36)
        static let actionPrimaryPressed = dynamic(light: 0x466E41, dark: 0x5A8A54)
        static let onAction = NSColor(hex: 0xFFFFFF)
        /// Text on the always-dark off screen.
        static let screenTitle = NSColor(hex: 0xF4F4F6)
        static let screenMeta = dynamic(
            light: 0xB9B8C2, dark: 0xB9B8C2, contrastLight: 0xDCDBE3, contrastDark: 0xDCDBE3)
        /// `link` on the dark screen: moss for dark surfaces.
        static let screenLink = dynamic(
            light: 0x8DBB82, dark: 0x8DBB82, contrastLight: 0xB2D8A8, contrastDark: 0xB2D8A8)
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

        /// A colour for light and dark, with optional Increase Contrast variants (which default
        /// to the normal ones).
        static func dynamic(
            light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1,
            contrastLight: UInt32? = nil, contrastLightAlpha: CGFloat? = nil,
            contrastDark: UInt32? = nil, contrastDarkAlpha: CGFloat? = nil
        ) -> NSColor {
            NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ])
                switch match {
                case .accessibilityHighContrastDarkAqua:
                    return NSColor(hex: contrastDark ?? dark, alpha: contrastDarkAlpha ?? darkAlpha)
                case .accessibilityHighContrastAqua:
                    return NSColor(hex: contrastLight ?? light, alpha: contrastLightAlpha ?? lightAlpha)
                case .darkAqua:
                    return NSColor(hex: dark, alpha: darkAlpha)
                default:
                    return NSColor(hex: light, alpha: lightAlpha)
                }
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

    /// Timings for starting, watching and stopping emulators. Not drawn, but named here so the
    /// model holds no raw numbers.
    enum Timing {
        /// How often to check a booting emulator's `getStatus`.
        static let bootPoll: Duration = .seconds(1)
        /// A `getStatus` that takes longer than this counts as a failure.
        static let statusTimeout: Duration = .seconds(3)
        /// How often to look for the registration file while a started emulator comes up (the
        /// folder may not exist yet, so the watcher alone can't be relied on).
        static let startPoll: Duration = .seconds(1)
        /// Give up on a started emulator that hasn't registered by then.
        static let startTimeout: Duration = .seconds(120)
        /// SIGTERM, then SIGKILL after this.
        static let stopGracePeriod: Duration = .seconds(10)
        static let stopKillWait: Duration = .seconds(5)
        static let stopPoll: Duration = .milliseconds(200)
    }
}
