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
        static let s: CGFloat = 8
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

    /// The emulators menu under "Choose another emulator" (canvas EmptyMenu; the guide's Select
    /// menu metrics): always on the dark screen.
    enum AvdMenu {
        static let width: CGFloat = 248
        static let inset: CGFloat = 6
        static let radius: CGFloat = 8
        static let rowSpacing: CGFloat = 2
        static let rowRadius: CGFloat = 6
        static let rowPaddingH: CGFloat = 10
        static let rowPaddingV: CGFloat = 6
        static let lineSpacing: CGFloat = 1
        static let tagGap = Space.s
        static let tagPaddingH = Space.s
        static let tagPaddingV: CGFloat = 2
        static let hairline: CGFloat = 0.5
        static let dividerHeight: CGFloat = 0.5
        static let dividerPaddingV = Space.xxs
        /// The link's line height and the gap below it, so the menu opens 4 pt under the link.
        static let linkHeight: CGFloat = 15
        static let gap = Space.xxs
        static let shadowOpacity: Double = 0.45
        static let shadowRadius: CGFloat = 15
        static let shadowY: CGFloat = 10
        static let highlightedDetailOpacity: Double = 0.82
        static let highlightedTagStrokeOpacity: Double = 0.6
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

    /// The window around the device, with the title row and toolbar measured from Apple's Device
    /// Hub (AX bounds, Xcode 27): a 52 pt title row, the frame with side insets, then the
    /// toolbar's band.
    enum Window {
        /// The title row: traffic lights, the device name and meta left-aligned, then More.
        static let titleRowHeight: CGFloat = 52
        /// Left and right inset around the frame (design token `space.xl`).
        static let contentInset = Space.xl
        /// From the end of the system's traffic lights to the title (Device Hub: 80 → 108).
        static let titleGap: CGFloat = 28
        /// Used until the window reports where its traffic lights end.
        static let fallbackTitleLeading: CGFloat = 108
        /// Room kept clear of the title on the right; More is a real toolbar item over it.
        static let titleRowTrailingPadding: CGFloat = 56
        static let titleLineSpacing: CGFloat = 0
    }

    /// The floating toolbar under the device (Device Hub's): a glass capsule with Home,
    /// Screenshot and Record, and a glass circle with Rotate, centred in their band.
    enum Toolbar {
        /// From the frame's bottom to the window's bottom.
        static let bandHeight: CGFloat = 54
        static let capsuleHeight: CGFloat = 36
        static let capsulePadding = Space.xxs
        static let capsuleGap = Space.s
        static let buttonWidth: CGFloat = 32
        static let buttonHeight: CGFloat = 28
        static let buttonSpacing: CGFloat = 2
        /// The rotate circle's diameter.
        static let circleSize: CGFloat = 36
        static let iconSize: CGFloat = 15
        static let hairline: CGFloat = 0.5
        static let disabledOpacity: CGFloat = 0.45
        /// Hover and press shades over a button (design guide Controls: +4%, +8%).
        static let hoverOpacity: Double = 0.06
        static let pressedOpacity: Double = 0.12
        static let hoverDuration: Double = 0.12
    }

    /// The window's glass: behind-window blur under an ink tint in dark (`inkGlass`) and a
    /// paper tint in light (Pane only; the guide's light mode is solid paper).
    enum Glass {
        static let darkMaterial = NSVisualEffectView.Material.hudWindow
        static let lightMaterial = NSVisualEffectView.Material.underWindowBackground
        // Secondary text keeps 5.6:1 with pure white behind (#3C3B41).
        static let darkTintOpacity: CGFloat = 0.86
        // Secondary text (#64636C) keeps 4.5:1 even with pure black behind the glass (#E0E0E2).
        static let lightTintOpacity: CGFloat = 0.92
    }

    /// The device frame we draw: body, bezel, screen corners, punch hole and side buttons.
    enum Frame {
        /// The drawn screen's height; the width follows the device's aspect (1080 × 2400 → 315).
        static let screenHeight: CGFloat = 700
        /// How small and large the window may make the screen's long side.
        static let minScreenHeight: CGFloat = 360
        static let maxScreenHeight: CGFloat = 2400
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
        /// How far a button stands proud of the body at rest (the layout's depth).
        static let buttonDepth: CGFloat = 3
        /// Out when the pointer comes near, as the iOS Simulator's buttons slide out.
        static let buttonDepthNear: CGFloat = 7
        /// Pushed in while the mouse is down.
        static let buttonDepthPressed: CGFloat = 1
        /// How close the pointer must come to a button's outline to slide it out.
        static let buttonProximity: CGFloat = 24
        static let buttonSpringResponse: Double = 0.25
        static let buttonSpringDamping: Double = 0.85
        /// The faint light outline every button has.
        static let buttonEdgeWidth: CGFloat = 0.75
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
        /// Used when the AVD doesn't say (`hw.lcd.density`): a Pixel 8's.
        static let fallbackDensity = 420

        static let spec = FrameSpec(
            screenHeight: screenHeight, referenceScreenHeight: referenceScreenHeight, bezel: bezel,
            bodyRadius: bodyRadius, screenRadius: screenRadius, punchHoleDiameter: punchHoleDiameter,
            punchHoleTop: punchHoleTop, buttons: buttons, buttonDepth: buttonDepth, buttonHitDepth: buttonHitDepth,
            buttonHitOutset: buttonHitOutset, titleRowHeight: Window.titleRowHeight,
            contentInset: Window.contentInset, bottomInset: Toolbar.bandHeight)
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
        static let menuRow = Font.system(size: 13)
        static let menuDetail = Font.system(size: 11)
        static let menuTag = Font.system(size: 11, weight: .medium)
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
        static let icon = dynamic(
            light: 0x3E3D45, dark: 0xD6D5DD, contrastLight: 0x17161C, contrastDark: 0xF4F4F6)
        /// The toolbar capsules and More button when transparency is reduced (`surfaceRaised`).
        static let pill = dynamic(light: 0xFFFFFF, dark: 0x2C2B33)
        /// Hover and press shades on toolbar buttons: ink in light, paper in dark.
        static let shade = dynamic(light: 0x17161C, dark: 0xF4F4F6)
        /// Record while recording.
        static let recording = dynamic(
            light: 0xD93A2B, dark: 0xFF5A4B, contrastLight: 0xB0281B, contrastDark: 0xFF7A6E)
        static let frameBody = dynamic(light: 0x1F1E25, dark: 0x0E0E12)
        static let frameEdge = dynamic(light: 0x17161C, lightAlpha: 0.55, dark: 0xF4F4F6, darkAlpha: 0.22)
        static let frameInnerEdge = dynamic(light: 0xFFFFFF, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.06)
        static let frameButton = dynamic(light: 0x2B2A32, dark: 0x3A3943)
        /// A button near the pointer or pressed: slightly lighter.
        static let frameButtonNear = dynamic(light: 0x3A3943, dark: 0x4A4953)
        static let frameButtonEdge = dynamic(
            light: 0xFFFFFF, lightAlpha: 0.22, dark: 0xFFFFFF, darkAlpha: 0.26, contrastLight: 0xFFFFFF,
            contrastLightAlpha: 0.5, contrastDark: 0xFFFFFF, contrastDarkAlpha: 0.55)
        static let punchHole = NSColor(hex: 0x0B0B0E)
        static let punchHoleRing = NSColor(hex: 0x1E1E24)
        /// The screen before the first frame and in the no-emulator state.
        static let screenOff = NSColor(hex: 0x000000)
        static let screenEmpty = NSColor(hex: 0x111116)
        /// The emulators menu on the dark screen.
        static let menuSurface = NSColor(hex: 0x2C2B33, alpha: 0.96)
        static let menuHairline = NSColor(hex: 0xF4F4F6, alpha: 0.16)
        static let menuDivider = NSColor(hex: 0xF4F4F6, alpha: 0.14)

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
        /// Retries before the can't-connect card: 0.5, 1, 2, 4, 4 s apart.
        static let reconnect = ReconnectPolicy(maxAttempts: 5, initialDelay: .milliseconds(500), maxDelay: .seconds(4))
        /// While live, `getStatus` this often, so a stopped or wedged emulator is noticed (the
        /// screen stream alone just goes quiet).
        static let heartbeat: Duration = .seconds(5)
        /// How far one mouse-wheel line moves the scrolling finger, in screen points.
        static let wheelLinePoints: CGFloat = 24
        /// Lift the wheel's finger once the wheel has been still this long.
        static let wheelRelease: Duration = .milliseconds(150)
        /// How long a turn may take to show before Pane stops waiting for it.
        static let rotationSettle: Duration = .seconds(10)
        /// Wait this long after the last resize before asking for frames at the new size.
        static let frameRestartDebounce: Duration = .milliseconds(200)
    }
}
