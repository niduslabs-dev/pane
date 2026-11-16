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

    /// The emulators menu under "Choose another emulator" (board 6): a menu panel, this far
    /// under the link.
    enum AvdMenu {
        static let gap = Space.xxs
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
    /// Dropping files on the device: the highlight while dragging and the status line after.
    enum Drop {
        /// The accent outline around the screen while files are dragged over the window.
        static let outlineWidth: CGFloat = 1.5
        /// The scrim under the label and the status line, so both read over any app.
        static let scrimOpacity: Double = 0.72
        /// How long "Installed." stays; an error stays longer so it can be read.
        static let doneDuration: Duration = .seconds(2)
        static let errorDuration: Duration = .seconds(5)
        static let fadeDuration: Double = 0.15
    }

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
        /// How far a second window opens down and right of the one in front.
        static let cascadeStep: CGFloat = 28
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

extension Theme.Frame {
    /// The frame's colours and line widths for a screenshot with Include Device Frame, in the
    /// window's light or dark look.
    @MainActor
    static func exportStyle(appearance: NSAppearance) -> ReadOnlyBox<FrameStyle> {
        var style: FrameStyle?
        appearance.performAsCurrentDrawingAppearance {
            style = FrameStyle(
                body: Theme.Palette.frameBody.cgColor, edge: Theme.Palette.frameEdge.cgColor,
                innerEdge: Theme.Palette.frameInnerEdge.cgColor, button: Theme.Palette.frameButton.cgColor,
                buttonEdge: Theme.Palette.frameButtonEdge.cgColor, punchHole: Theme.Palette.punchHole.cgColor,
                punchHoleRing: Theme.Palette.punchHoleRing.cgColor, edgeWidth: edgeWidth,
                innerEdgeInset: innerEdgeInset, innerEdgeWidth: innerEdgeWidth, buttonEdgeWidth: buttonEdgeWidth,
                buttonCornerRadius: buttonCornerRadius, punchHoleRingWidth: punchHoleRingWidth)
        }
        // `performAsCurrentDrawingAppearance` runs its block before returning.
        return ReadOnlyBox(value: style!)
    }
}

extension Theme {
    /// The short line over the bottom of the screen ("Copied.", "Saved GIF.", an error).
    enum Notice {
        static let doneDuration: Duration = .seconds(2)
        static let errorDuration: Duration = .seconds(5)
        static let bottomInset = Space.xl
        static let paddingH = Space.m
        static let height: CGFloat = 28
        static let gap = Space.s
        static let hairline: CGFloat = 0.5
        static let shadowOpacity: Double = 0.3
        static let shadowRadius: CGFloat = 8
        static let shadowY: CGFloat = 3
        static let fadeDuration: Double = 0.15
    }

    /// Export Recording as GIF: small and light enough to drop into a pull request.
    enum Export {
        static let gif = GifExporter.Options(maxSide: 640, framesPerSecond: 15)
    }

    /// Sheets (design guide, Sheet): Open Link and Custom Location.
    enum Sheet {
        static let width: CGFloat = 355
        static let inset = Space.xl
        static let descriptionGap = Space.s
        static let bodyGap: CGFloat = 16
        static let footerGap = Space.xl
        static let buttonGap = Space.s
        static let fieldHeight: CGFloat = 28
        static let fieldRadius: CGFloat = 8
        static let fieldPaddingH: CGFloat = 11
        static let fieldLabelGap: CGFloat = 6
        static let fieldBorder: CGFloat = 1
        static let fieldHalo: CGFloat = 3
        static let busyOpacity: CGFloat = 0.45
        static let recentLabelInset = Space.xxs
        static let cardInset = Space.xxs
        static let cardRadius: CGFloat = 14
        static let rowPaddingV: CGFloat = 9
        static let hairline: CGFloat = 0.5
        static let rowRadius: CGFloat = 7
        static let rowPaddingH = Space.m
        static let listGap: CGFloat = 2
        static let problemGap = Space.s
        /// Two fields side by side (latitude and longitude).
        static let fieldPairGap = Space.m
    }

    /// Pane's own menu panel (boards 7 and 13, kit board 16): More, the emulator switcher and
    /// the emulators menu. Never an `NSMenu`, so the highlight is moss.
    enum Menu {
        static let width: CGFloat = 232
        static let switcherWidth: CGFloat = 262
        static let submenuWidth: CGFloat = 150
        static let switcherSubmenuWidth: CGFloat = 242
        static let inset: CGFloat = 6
        static let radius: CGFloat = 10
        static let rowSpacing: CGFloat = 2
        static let rowHeight: CGFloat = 32
        /// A row with a second line (an emulator: name over model and Android version).
        static let tallRowHeight: CGFloat = 44
        static let rowRadius: CGFloat = 7
        static let rowPaddingH: CGFloat = 10
        static let rowGap: CGFloat = 10
        static let lineSpacing: CGFloat = 1
        static let checkSlot: CGFloat = 14
        static let checkSize: CGFloat = 11
        static let chevronSize: CGFloat = 9
        static let headerHeight: CGFloat = 22
        static let headerBottomPadding: CGFloat = 2
        static let dividerHeight: CGFloat = 0.5
        static let dividerMarginV = Space.xxs
        static let hairline: CGFloat = 0.5
        static let tagPaddingH = Space.s
        static let tagPaddingV: CGFloat = 2
        static let shadowOpacity: Double = 0.22
        static let shadowRadius: CGFloat = 14
        static let shadowY: CGFloat = 10
        static let disabledOpacity: CGFloat = 0.45
        /// More's menu opens this far under the title row's button, right edges this far in.
        static let moreTop: CGFloat = 48
        static let moreTrailing = Space.s
        /// The switcher opens under the device name, its left edge on the name button's.
        static let switcherTop: CGFloat = 49
        /// A submenu to the side sits this far from its menu; the switcher's opens over the
        /// menu, this far right of its edge and below its row.
        static let submenuGap = Space.xxs
        static let switcherSubmenuShift: CGFloat = 51
        static let switcherSubmenuDrop: CGFloat = 7
        static let edgeMargin = Space.xxs
    }

    /// The device name in the title as a button (board 13): a soft shade and a chevron under
    /// the pointer.
    enum TitleButton {
        static let paddingH: CGFloat = 9
        static let paddingV = Space.xxs
        static let radius: CGFloat = 8
        static let hoverOpacity: Double = 0.06
        static let chevronGap: CGFloat = 6
        static let chevronSize: CGFloat = 8
    }

    /// The pill that takes the toolbar's place while a tool is on (boards 9 to 11): the tool's
    /// icon and name, or its state, and Done.
    enum ModePill {
        static let height: CGFloat = 36
        static let minWidth: CGFloat = 216
        static let paddingLeading = Space.m
        static let paddingTrailing = Space.xxs
        static let gap = Space.s
        static let iconSize: CGFloat = 13
        static let buttonHeight: CGFloat = 28
        static let buttonPaddingH: CGFloat = 14
        static let hairline: CGFloat = 0.5
        static let buttonHairline: CGFloat = 1
        static let shadowOpacity: Double = 0.10
        static let shadowRadius: CGFloat = 1.5
        static let shadowY: CGFloat = 1
    }

    /// Inspect layout, Measure and Pick colour: what they draw over the live screen (boards 9
    /// to 11). Their colours are fixed, not per mode, because they sit on the device's screen.
    enum Tools {
        /// The outline around the inspected view, the measured line and the snap guides.
        static let outlineWidth: CGFloat = 1.5
        static let outlineRadius: CGFloat = 6
        /// The paper halo on each side of an outline or line, so it holds up on any app.
        static let haloWidth: CGFloat = 1
        static let guideDash: [CGFloat] = [4, 3]
        /// Chips: a size on an outline, a distance on a guide, a length on a line, a hex.
        static let chipHeight: CGFloat = 20
        static let chipPaddingH: CGFloat = 7
        static let chipRadius: CGFloat = 6
        static let chipGap: CGFloat = 6
        static let chipRing: CGFloat = 0.5
        /// The pinned view's details card.
        static let cardWidth: CGFloat = 250
        static let cardPaddingH = Space.m
        static let cardPaddingV: CGFloat = 10
        static let cardRadius: CGFloat = 10
        static let cardRowGap: CGFloat = 5
        static let cardColumnGap: CGFloat = 10
        static let cardKeyWidth: CGFloat = 52
        /// One line of the card's 11 pt text, for placing the card.
        static let cardLineHeight: CGFloat = 14
        /// From the outline to the card, and from the screen's edge to either.
        static let cardGap: CGFloat = 14
        static let cardMargin = Space.s
        static let cardShadowOpacity: Double = 0.3
        static let cardShadowRadius: CGFloat = 10
        static let cardShadowY: CGFloat = 8
        /// The measured line's end caps.
        static let capLength: CGFloat = 12
        /// The loupe: this many screen pixels on each side of the one under the pointer, each
        /// drawn 12 pt square, in a circle with a paper ring inside an ink ring.
        static let loupeRadius = 3
        static let loupeCell: CGFloat = 12
        static let loupePaperRing: CGFloat = 1.5
        static let loupeInkRing: CGFloat = 1.5
        /// From the pointer to the loupe's edge, and from the loupe to its chip.
        static let loupeOffset: CGFloat = 14
        static let loupeChipGap = Space.s
        static let swatchSize: CGFloat = 10
        static let swatchRadius: CGFloat = 3
        static let loupeShadowOpacity: Double = 0.35
        /// Measure locks a line to level or upright within this many degrees.
        static let axisSnapDegrees: CGFloat = 8
        /// Measure snaps an end to a view's edge within this many screen points.
        static let edgeSnapPoints: CGFloat = 5
        /// Wait this long after the screen last changed before reading the layout again, and
        /// read it anyway once changes have gone on this long.
        static let refreshDebounce: Duration = .milliseconds(450)
        static let refreshMaxWait: Duration = .seconds(3)
        /// When reads keep finding the same layout, the gap between them doubles from the
        /// first value up to the second.
        static let unchangedBackoffStart: Duration = .seconds(2)
        static let unchangedBackoffMax: Duration = .seconds(16)
        /// How long "Copied" stays in the chip and the pill.
        static let copiedDuration: Duration = .seconds(2)
        /// A layout read may take this long (animations make uiautomator wait for idle).
        static let dumpTimeout: Duration = .seconds(15)
    }
}

extension Theme.Typeface {
    static let sheetTitle = Font.system(size: 15, weight: .semibold)
    static let sheetBody = Font.system(size: 13)
    static let sheetLabel = Font.system(size: 11, weight: .medium)
    static let toolChip = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let toolCard = Font.system(size: 11).monospacedDigit()
    static let modePill = Font.system(size: 12, weight: .medium)
    static let modePillButton = Font.system(size: 12)
    static let menuShortcut = Font.system(size: 12)
    static let menuHeader = Font.system(size: 11, weight: .medium)
    static let sheetRecent = Font.system(size: 12)
    static let sheetSecondary = Font.system(size: 13, weight: .medium)
    static let notice = Font.system(size: 12, weight: .medium)
}

extension Theme.Palette {
    /// `tool.select`: outlines, the measured line and the loupe's chosen pixel. Moss, the same
    /// in both modes (4.2:1 on a light device screen, 3.7:1 on a dark one).
    static let toolSelect = NSColor(hex: 0x4F7A4A)
    /// `tool.guide`: distances and snap guides. Amber, always dashed.
    static let toolGuide = NSColor(hex: 0xB25E00)
    /// `tool.halo`: paper on each side of an outline or line.
    static let toolHalo = NSColor(hex: 0xF4F4F6, alpha: 0.9)
    /// `tool.fill`: the inspected view's wash.
    static let toolFill = NSColor(hex: 0x4F7A4A, alpha: 0.16)
    /// `tool.chip`: chips, the details card and the loupe's outer ring. Ink with paper text in
    /// both modes, because they sit on the device, not on Pane.
    static let toolChip = NSColor(hex: 0x17161C, alpha: 0.92)
    static let toolChipText = NSColor(hex: 0xF4F4F6)
    static let toolChipSecondary = NSColor(hex: 0xB9B8C2)
    static let toolChipRing = NSColor(hex: 0xF4F4F6, alpha: 0.30)
    /// Menu panels: white in light, raised ink in dark.
    static let menuPanel = dynamic(light: 0xFFFFFF, dark: 0x24232B, darkAlpha: 0.96)
    static let menuPanelHairline = dynamic(light: 0x17161C, lightAlpha: 0.12, dark: 0xF4F4F6, darkAlpha: 0.12)
    /// The row under the pointer or the keys: moss 10% in light, light moss 16% in dark.
    static let menuHighlight = dynamic(light: 0x4F7A4A, lightAlpha: 0.10, dark: 0x8DBB82, darkAlpha: 0.16)
    /// A menu's tick: the link moss of each mode.
    static let menuCheck = dynamic(light: 0x466E41, dark: 0x8DBB82)
    /// The mode pill: `surfaceRaised` with its Done button on paper or raised ink.
    static let modePill = dynamic(light: 0xFFFFFF, dark: 0x2C2B33)
    static let modePillButton = dynamic(light: 0xF4F4F6, dark: 0x2C2B33, darkAlpha: 0.9)
    /// The short notice line over the screen (always dark, over any app).
    static let toolSurface = NSColor(hex: 0x17161C, alpha: 0.92)
    static let toolHairline = NSColor(hex: 0xF4F4F6, alpha: 0.30)
    static let toolText = NSColor(hex: 0xF4F4F6)
    /// Sheet surfaces (design guide roles): the sheet itself, fields on it, secondary buttons.
    static let sheetSurface = dynamic(light: 0xFFFFFF, dark: 0x24232B)
    static let fieldSurface = dynamic(light: 0xFFFFFF, dark: 0x2C2B33, darkAlpha: 0.9)
    static let secondaryAction = dynamic(light: 0xF4F4F6, dark: 0x2C2B33, darkAlpha: 0.9)
    /// The Recent list's card on a sheet.
    static let sheetCard = dynamic(light: 0xF4F4F6, dark: 0x1C1B22)
    /// A field's focus ring (moss) and its halo; red when the field's value was refused.
    static let fieldFocus = NSColor(hex: 0x4F7A4A)
    static let fieldFocusHalo = dynamic(light: 0x4F7A4A, lightAlpha: 0.25, dark: 0x8DBB82, darkAlpha: 0.6)
    static let problemText = dynamic(light: 0xC4271B, dark: 0xFF8A80)
    static let problemHalo = dynamic(light: 0xFDECEA, dark: 0xFF8A80, darkAlpha: 0.25)
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
        /// How long `-PaneTakeoverCheck changing` holds the switch in its changing state.
        static let takeoverCheckHold: Duration = .seconds(120)
        /// How long ago `pane://check-update` says the last check was.
        static let updateCheckDemoAge: TimeInterval = 3 * 3600
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
        /// How often the Mac's clipboard is checked for a change while the window is key.
        static let clipboardPoll: Duration = .milliseconds(500)
        /// Between setting the device's clipboard and pressing paste: `setClipboard` returns
        /// once scheduled, before Android has the text.
        static let pasteAfterClipboard: Duration = .milliseconds(150)
        /// Wait this long after the last resize before asking for frames at the new size.
        static let frameRestartDebounce: Duration = .milliseconds(200)
    }
}
