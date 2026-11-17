import AppKit
import PaneCore
import SwiftUI

private typealias T = ThemeTokens

/// Every size, colour and type style Pane draws with, named after `docs/mac-app-design.md` and the
/// approved board on the Pane design canvas. Shared values read `ThemeTokens` (the studio's
/// generated tokens, `scripts/sync-tokens.sh`); change one in `assets/tokens.json`, never here.
/// The numbers still written out are Pane's own, with no token yet (`design/adoption/pane.md`,
/// group C). Views never hold raw numbers.
enum Theme {
    /// The studio spacing scale (design guide 1.1).
    enum Space {
        static let xxxs = T.Space.xxxs
        static let xxs = T.Space.xxs
        static let xs = T.Space.xs
        static let s = T.Space.s
        static let m = T.Space.m
        static let l = T.Space.l
        static let xl = T.Space.xl
        static let xxl = T.Space.xxl
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
        static let radius = T.Radius.card
        static let hairline = T.Border.hairline
        static let hairlineIncreasedContrast = T.Border.hairlineIncreasedContrast
        static let horizontalPadding = Space.xxl
        static let gap = Space.m
        static let glyphSize: CGFloat = 40
        /// Extra room above the button (the board's 4 on top of the 12 pt gap).
        static let actionExtraGap = Space.xxs
    }

    /// Capsule actions (design guide, Controls).
    enum Capsule {
        static let height = T.Size.Button.height
        /// Start on the screen is a little wider than a standard capsule, as on the board.
        static let startPadding: CGFloat = 20
        static let standardPadding = T.Size.Button.paddingX
        /// The secondary capsule's edge on the dark screen.
        static let border = T.Border.control
        static let disabledOpacity = Opacity.disabled
    }

    /// The `blurSwap` status line (design guide 2).
    /// Dropping files on the device (the canvas's "Option A · Card on the device screen" and
    /// "Option A · Drag card, refined", variant 1): one card on the screen, the drag card while
    /// files hover and the result card after the drop. The card is a notification panel's
    /// anatomy inside the screen.
    enum Drop {
        /// The card is the screen less this on each side.
        static let sideMargin = Space.l
        /// A refused drag's card sits this far under the screen's top, clear of Start.
        static let refusedTop = Space.xl
        /// A status title ("No emulator running") wraps to at most this many lines.
        static let statusTitleLines = 2
        static let inset = T.Size.NotificationPanel.inset
        static let radius = T.Radius.card
        static let hairline = T.Border.hairline
        static let shadowOpacity = Double(T.Shadow.menu.colour.light.alpha)
        /// SwiftUI's shadow radius is half the token's blur.
        static let shadowRadius = T.Shadow.menu.blur / 2
        static let shadowY = T.Shadow.menu.y
        /// Between the header, the app row, the status and the buttons.
        static let sectionGap = Space.l
        static let media = T.Size.NotificationPanel.media
        static let mediaGap = T.Size.NotificationPanel.mediaGap
        /// An icon tile's corner is this share of its side.
        static let tileRatio = T.Radius.iconTileRatio
        /// The generic tile's glyph in a 60 slot, and in a 32 one.
        static let tileGlyph = T.Size.Icon.rowLarge + Space.s
        static let listGlyph = T.Size.Icon.rowLarge
        /// The title to the chip, in the drag card.
        static let chipGap = Space.xxs
        /// The title to its meta line, in the result card.
        static let metaGap = Space.xxxs
        static let chipPaddingH = Space.s
        static let chipPaddingV = Space.xxxs
        /// Several items in the 60 slot: three 32 tiles stepping diagonally, each ringed in the
        /// card's colour so they read apart.
        static let stackTile = T.Size.Icon.list
        /// Tiles in the stack.
        static let stackCount = 3
        static let stackRing = T.Border.focusRing
        /// The dim under the card and the moss outline round the screen while a drop is
        /// accepted: `tool.select` with a paper halo, as Inspect's outline.
        static let outlineWidth = T.App.Pane.Size.Chip.outline + T.Border.hairline / 2
        static let haloWidth = T.Border.hairline
        /// The reading spinner appears only when aapt or the device takes longer than this.
        static let spinnerDelay: Duration = .seconds(1)
        /// aapt and the icon read, and the version lookup, each stop after this.
        static let readTimeout: Duration = .seconds(3)
        /// A push and an install may run this long.
        static let transferTimeout: Duration = .seconds(600)
        /// How often the bytes on the device are read while a file is pushed.
        static let progressPoll: Duration = .milliseconds(100)
        static let progressCeiling = T.Motion.progressCeiling
        static let progressHeight = T.Size.Progress.height
        static let progressRadius = T.Size.Progress.radius
        static let statusGap = Space.xs
        static let rowIcon = T.Size.Icon.row
        static let rowGap = Space.xs
        static let failureGap = Space.s
        /// The warning and Details boxes.
        static let boxPaddingH = Space.m
        static let boxPaddingV = Space.m
        static let detailsPaddingV = Space.s
        static let boxRadius = T.Size.InfoCard.panelRadius
        static let boxGap = Space.s
        static let buttonGap = Space.s
        /// Several files: rows 44 tall with a 32 icon.
        static let listRowHeight = T.Size.MenuPanel.tallRowHeight
        static let listIcon = T.Size.Icon.list
        static let listIconGap = T.Size.Select.rowIconGap
        static let listRowGap = Space.xxs
        static let listHeadGap = Space.m
        static let listActionGap = Space.s
        /// A finished card closes itself this long after its last result (`dismissible`).
        static let afterDone: Duration = .seconds(T.Motion.Duration.afterDone)
        static let fadeDuration = T.Motion.Duration.fade
        /// Most apps Pane reads while dragging; a bigger drag is counted, not read.
        static let maxReadsWhileDragging = 8
    }

    enum StatusSwap {
        static let blur = T.Motion.Distance.swapBlur
        static let offsetY = T.Motion.Distance.swapOffset
        static let springResponse = T.Motion.Spring.swap.response
        static let springDamping = T.Motion.Spring.swap.dampingFraction
        /// Reduce Motion's plain crossfade.
        static let fadeDuration = T.Motion.Duration.fade
    }

    /// The window around the device, with the title row and toolbar measured from Apple's Device
    /// Hub (AX bounds, Xcode 27): a 52 pt title row, the frame with side insets, then the
    /// toolbar's band.
    enum Window {
        /// The title row: traffic lights, the device name and meta left-aligned, then More.
        static let titleRowHeight = T.App.Pane.Size.TitleRow.height
        /// Left and right inset around the frame (design token `space.xl`).
        static let contentInset = Space.xl
        /// From the end of the system's traffic lights to the title (Device Hub: 80 → 108).
        static let titleGap = T.App.Pane.Size.TitleRow.titleLeading
        /// Used until the window reports where its traffic lights end.
        static let fallbackTitleLeading: CGFloat = 108
        /// Room kept clear of the title on the right; More is a real toolbar item over it.
        static let titleRowTrailingPadding: CGFloat = 56
        static let titleLineSpacing: CGFloat = 0
        /// The narrowest the window gets: the switcher, the widest menu drawn inside the window,
        /// with its edge margin on both sides. A narrow device's smallest screen grows to it.
        static let minWidth = Menu.switcherWidth + 2 * Menu.edgeMargin
        /// How far a second window opens down and right of the one in front.
        static let cascadeStep: CGFloat = 28
    }

    /// The floating toolbar under the device (Device Hub's): a glass capsule with Home,
    /// Screenshot and Record, and a glass circle with Rotate, centred in their band.
    enum Toolbar {
        /// From the frame's bottom to the window's bottom.
        static let bandHeight = T.Size.GlassToolbar.band
        static let capsuleHeight = T.Size.GlassToolbar.capsule
        static let capsulePadding = Space.xxs
        static let capsuleGap = Space.s
        static let buttonWidth = T.Size.GlassToolbar.buttonWidth
        static let buttonHeight = T.Size.GlassToolbar.buttonHeight
        static let buttonSpacing = Space.xxxs
        /// The rotate circle's diameter.
        static let circleSize = T.Size.GlassToolbar.circle
        static let iconSize = T.Size.GlassToolbar.icon
        static let hairline = T.Border.hairline
        static let disabledOpacity = Opacity.disabled
        /// Hover and press shades over a button.
        static let hoverOpacity = T.Opacity.toolbarHover
        static let pressedOpacity = T.Opacity.toolbarPressed
        static let hoverDuration = T.Motion.Duration.hover
        /// Record while recording widens to the red icon and the elapsed time (board 16,
        /// "Recording timer"): tabular digits that roll (`numericRoll`).
        static let recordingGap = Space.xxs
        static let recordingPaddingH = Space.s
        static let timeFont = T.TypeScale.bodyMedium.font
        /// Recording's enter and leave (board 19): the width on `Spring.toggle`, the time in
        /// and out by blurSwap; Reduce Motion, the width at once and the content crossfading
        /// over `fade`.
        static var recordingMorph: Animation { T.Motion.Spring.toggle.animation }
        static var recordingFade: Animation { .easeOut(duration: T.Motion.Duration.fade) }
        /// The press shade lets go over the hover duration instead of snapping off.
        static var pressRelease: Animation { .easeOut(duration: hoverDuration) }
    }

    /// The flash over the device screen when a screenshot lands (`captureFlash`, board 18).
    enum CaptureFlash {
        /// Pane's own value until `app.pane.opacity.captureFlash` is a token
        /// (`design/adoption/pane.md`).
        static let peakOpacity: Double = 0.5
        static let fadeDuration = T.Motion.Duration.fade
    }

    /// The window's glass: behind-window blur under an ink tint in dark (`inkGlass`) and a
    /// paper tint in light (Pane only; the guide's light mode is solid paper).
    enum Glass {
        static let darkMaterial = NSVisualEffectView.Material.hudWindow
        static let lightMaterial = NSVisualEffectView.Material.underWindowBackground
        // Secondary text keeps 5.6:1 with pure white behind (#3C3B41).
        static let darkTintOpacity = CGFloat(T.Opacity.glassTint)
        // Secondary text (#64636C) keeps 4.5:1 even with pure black behind the glass (#E3E3E5,
        // 4.6:1). At 92% it measured 4.496:1, a hair under (`GlassTests`).
        static let lightTintOpacity = T.App.Pane.Colour.glassLight.light.alpha
    }

    /// The device frame we draw: body, bezel, screen corners, punch hole and side buttons.
    enum Frame {
        /// The drawn screen's height; the width follows the device's aspect (1080 × 2400 → 315).
        static let screenHeight: CGFloat = 700
        /// How small and large the window may make the screen's long side. The window's own
        /// minimum width (`Window.minWidth`) can raise the floor for a narrow device.
        static let minScreenHeight: CGFloat = 360
        static let maxScreenHeight: CGFloat = 2400
        /// The screen height the button positions below were designed at.
        static let referenceScreenHeight: CGFloat = 700
        static let bezel = T.App.Pane.Size.Frame.bezel
        static let bodyRadius = T.App.Pane.Size.Frame.bodyRadius
        static let screenRadius = T.App.Pane.Size.Frame.screenRadius
        static let punchHoleDiameter = T.App.Pane.Size.Frame.punchHole
        static let punchHoleTop: CGFloat = 12
        static let punchHoleRingWidth: CGFloat = 1.5
        /// The body's outer hairline, then a body-coloured gap, then a faint inner ring.
        static let edgeWidth: CGFloat = 1
        static let innerEdgeInset: CGFloat = 3
        static let innerEdgeWidth: CGFloat = 0.5
        /// How far a button stands proud of the body at rest (the layout's depth).
        static let buttonDepth = T.App.Pane.Size.Frame.buttonDepth
        /// Out when the pointer comes near, as the iOS Simulator's buttons slide out.
        static let buttonDepthNear = T.App.Pane.Size.Frame.buttonDepthNear
        /// Pushed in while the mouse is down.
        static let buttonDepthPressed = T.App.Pane.Size.Frame.buttonDepthPressed
        /// How close the pointer must come to a button's outline to slide it out.
        static let buttonProximity = T.App.Pane.Size.Frame.buttonProximity
        static let buttonSpringResponse = T.App.Pane.Motion.Spring.frameButton.response
        static let buttonSpringDamping = T.App.Pane.Motion.Spring.frameButton.dampingFraction
        /// The faint light outline every button has.
        static let buttonEdgeWidth: CGFloat = 0.75
        static let buttonCornerRadius: CGFloat = 2
        static let buttonHitDepth = T.App.Pane.Size.Frame.buttonHitDepth
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
        /// The device name in the title row (not the type scale's 22 pt `windowTitle`).
        static let titleRowName = T.TypeScale.bodyEmphasis.font
        static let meta = T.TypeScale.caption.font
        static let screenTitle = T.TypeScale.sectionTitle.font
        static let screenMeta = T.TypeScale.callout.font
        static let capsule = T.TypeScale.bodyEmphasis.font
        static let link = T.TypeScale.callout.font
        /// The secondary capsule on the dark screen, and adb's reason behind Details.
        static let screenSecondary = T.TypeScale.bodyMedium.font
        static let statusDetail = Font.system(size: 11, design: .monospaced)
        static let cardTitle = Font.system(size: 15)
        static let cardBody = T.TypeScale.callout.font
        static let status = T.TypeScale.callout.font
        static let menuRow = T.TypeScale.body.font
        static let menuDetail = T.TypeScale.caption.font
        static let menuTag = T.TypeScale.groupLabel.font
        /// The drop card: the header line ("dev_android36 · splito-1.4.0.apk · 61 MB") with the
        /// emulator's name in emphasis, the app's name, its meta line, the chip and adb's line.
        static let dropHeader = T.TypeScale.caption.font
        static let dropHeaderStrong = Font.system(
            size: T.TypeScale.caption.size, weight: T.TypeScale.bodyEmphasis.weight)
        static let dropTitle = T.TypeScale.panelTitle.font
        static let dropTitleTracking = T.TypeScale.panelTitle.tracking
        /// The version after the name: the title's size, regular.
        static let dropTitleVersion = Font.system(size: T.TypeScale.panelTitle.size)
        static let dropMeta = T.TypeScale.callout.font
        static let dropChip = Font.system(size: T.TypeScale.caption.size, weight: T.TypeScale.groupLabel.weight)
        static let dropRowTitle = T.TypeScale.bodyEmphasis.font
        static let dropRow = T.TypeScale.body.font
        static let dropDetails = ThemeType(
            size: T.TypeScale.caption.size, weight: T.TypeScale.caption.weight, family: .mono
        ).font
    }

    /// Colours, light and dark (ink). Light values are the board's `light`, dark its `ink`.
    enum Palette {
        /// Window background, title bar included (`titleBarMatchesContent`). Dark mode draws it
        /// as ink glass (`Glass`) unless transparency is reduced or contrast increased.
        static let surface = dynamic(
            T.App.Pane.Colour.glassLight.light.opaque, dark: T.Colour.Role.glassTint.dark)
        /// The window where no glass is drawn (Reduce Transparency, Increase Contrast): paper in
        /// light, `surfaceBaseSolid` in dark.
        static let surfaceSolid = dynamic(
            T.App.Pane.Colour.glassLight.light.opaque, dark: T.Colour.Role.surfaceBaseSolid.dark)
        static let text = T.Colour.Role.textPrimary.nsColor
        static let textSecondary = T.Colour.Role.textSecondary.nsColor
        /// The error card (`surfaceCard`): paper recessed in light, ink raised in dark.
        static let card = T.Colour.Role.surfaceCard.nsColor
        /// `hairline`: `controlBoundary` under Increase Contrast.
        static let hairline = T.Colour.Role.hairline.nsColor
        /// `actionPrimary`: moss with white text, darker under Increase Contrast.
        static let actionPrimary = T.Colour.Role.actionPrimary.nsColor
        static let actionPrimaryHover = T.Colour.Role.actionPrimaryHover.nsColor
        static let actionPrimaryPressed = T.Colour.Role.actionPrimaryPressed.nsColor
        static let onAction = T.Colour.Role.onAction.nsColor
        /// Text on the always-dark off screen.
        static let screenTitle = T.Colour.Brand.paper.nsColor
        static let screenMeta = T.Colour.Role.textSecondary.alwaysDark.nsColor
        /// `link` on the dark screen: moss for dark surfaces.
        static let screenLink = T.Colour.Role.link.alwaysDark.nsColor
        static let icon = T.Colour.Role.toolbarIcon.nsColor
        /// The toolbar capsules and More button when transparency is reduced.
        static let pill = T.Colour.Role.surfacePill.nsColor
        /// Hover and press shades on toolbar buttons: ink in light, paper in dark.
        static let shade = T.Colour.Role.toolbarShade.nsColor
        /// Record while recording.
        static let recording = T.Colour.Role.recording.nsColor
        /// The screenshot flash over the device screen (`captureFlash`): white in both modes,
        /// as the device's own camera flash is.
        static let captureFlash = NSColor.white
        static let frameBody = T.App.Pane.Colour.frameBody.nsColor
        static let frameEdge = T.App.Pane.Colour.frameEdge.nsColor
        static let frameInnerEdge = dynamic(light: 0xFFFFFF, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.06)
        static let frameButton = T.App.Pane.Colour.frameButton.nsColor
        /// A button near the pointer or pressed: slightly lighter.
        static let frameButtonNear = T.App.Pane.Colour.frameButtonNear.nsColor
        static let frameButtonEdge = T.App.Pane.Colour.frameButtonEdge.nsColor
        static let punchHole = NSColor(hex: 0x0B0B0E)
        static let punchHoleRing = NSColor(hex: 0x1E1E24)
        /// Behind the live picture before its first frame.
        static let screenOff = T.App.Pane.Colour.screenOff.nsColor
        /// The screen with nothing on it: no emulator, starting, booting.
        static let screenEmpty = T.App.Pane.Colour.screenEmpty.nsColor
        /// The secondary capsule on the always-dark screen (Show emulators in Finder, Stop).
        static let screenSecondary = T.Colour.Role.actionSecondary.alwaysDark.nsColor
        static let screenSecondaryEdge = T.Colour.Role.hairline.alwaysDark.nsColor
        /// The press shade on the always-dark screen's capsules.
        static let screenShade = T.Colour.Role.toolbarShade.alwaysDark.nsColor

        /// One fixed value in light and another in dark, the same under Increase Contrast.
        static func dynamic(_ light: ThemeColour.RGBA, dark: ThemeColour.RGBA) -> NSColor {
            ThemeColour(light: light, dark: dark, lightContrast: light, darkContrast: dark).nsColor
        }

        /// A colour for light and dark, with optional Increase Contrast variants (which default
        /// to the normal ones).
        static func dynamic(
            light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1,
            contrastLight: UInt32? = nil, contrastLightAlpha: CGFloat? = nil,
            contrastDark: UInt32? = nil, contrastDarkAlpha: CGFloat? = nil
        ) -> NSColor {
            NSColor(name: nil) { appearance in
                switch ColourLook(appearance) {
                case .darkContrast:
                    return NSColor(hex: contrastDark ?? dark, alpha: contrastDarkAlpha ?? darkAlpha)
                case .lightContrast:
                    return NSColor(hex: contrastLight ?? light, alpha: contrastLightAlpha ?? lightAlpha)
                case .dark:
                    return NSColor(hex: dark, alpha: darkAlpha)
                case .light:
                    return NSColor(hex: light, alpha: lightAlpha)
                }
            }
        }
    }
}

/// Which of its four values a dynamic colour draws with. Increase Contrast counts when the
/// appearance asks for it, and also whenever the system setting (or, in a debug build,
/// `-PaneIncreaseContrast YES`) is on: SwiftUI resolves `Color(nsColor:)` with a plain light or
/// dark appearance even when its environment's contrast is increased (measured in Settings).
enum ColourLook {
    case light, dark, lightContrast, darkContrast

    nonisolated init(_ appearance: NSAppearance) {
        let match = appearance.bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ])
        let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        let increased =
            match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            || Self.increaseContrastIsOn
        switch (isDark, increased) {
        case (true, true): self = .darkContrast
        case (true, false): self = .dark
        case (false, true): self = .lightContrast
        case (false, false): self = .light
        }
    }

    nonisolated static var increaseContrastIsOn: Bool {
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast { return true }
        #if DEBUG
            return UserDefaults.standard.bool(forKey: "PaneIncreaseContrast")
        #else
            return false
        #endif
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
        static let hairline = T.Border.hairline
        static let shadowOpacity: Double = 0.3
        static let shadowRadius: CGFloat = 8
        static let shadowY: CGFloat = 3
        static let fadeDuration = T.Motion.Duration.fade
        /// The pill is at most the device screen less this on each side (320 pt on board 18's
        /// 368 pt screen); a long folder name truncates in the middle. Relative, not a fixed
        /// width, so the pill never overhangs a smaller screen.
        static let sideInset = Space.xl
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
        static let bodyGap = Space.l
        static let footerGap = Space.xl
        static let buttonGap = Space.s
        /// A file name in a sheet row wraps to at most this many lines.
        static let fileNameLines = 2
        static let fieldHeight = T.Size.Field.height
        static let fieldRadius = T.Radius.control
        static let fieldPaddingH = T.Size.Field.paddingX
        static let fieldLabelGap = Space.xs
        static let fieldBorder = T.Border.control
        static let fieldHalo = T.Border.openRing
        static let busyOpacity = Opacity.disabled
        static let recentLabelInset = Space.xxs
        static let cardInset = Space.xxs
        static let cardRadius = T.Radius.card
        /// Off the scale: a recent link's row is 9 + 14 + 9, so two fit the board's card.
        static let rowPaddingV: CGFloat = 9
        static let hairline = T.Border.hairline
        static let rowRadius = T.Radius.menuRow
        static let rowPaddingH = Space.m
        static let listGap = Space.xxxs
        static let problemGap = Space.s
        /// Two fields side by side (latitude and longitude).
        static let fieldPairGap = Space.m
    }

    /// Settings' ⓘ popover (board 14).
    enum InfoPopover {
        static let width: CGFloat = 280
        static let paddingH: CGFloat = 14
        static let paddingV = Space.m
        static let radius = T.Radius.menu
        /// Under the card it explains, and in from the card's left edge.
        static let gap = Kit.Space.xs
        static let leading: CGFloat = 150
        /// 12 pt text at the board's 1.45 line height.
        static let lineSpacing: CGFloat = 5.4
    }

    /// The app icon in the update surfaces.
    enum AppIcon {
        /// macOS's icon grid puts the tile at 824 of the file's 1024 points; drawing the file
        /// this much larger makes the tile fill the slot the board gives it.
        static let tileScale: CGFloat = 1024 / 824
    }

    /// `opacity.disabled`: a control that can't be used now stays in place at this opacity,
    /// applied once (`PlainRowButtonStyle`).
    enum Opacity {
        static let disabled = CGFloat(T.Opacity.disabled)
    }

    /// Pane's own menu panel (boards 7 and 13, kit board 16): More, the emulator switcher and
    /// the emulators menu. Never an `NSMenu`, so the highlight is moss.
    enum Menu {
        static let width = T.Size.MenuPanel.width
        static let switcherWidth: CGFloat = 262
        static let submenuWidth: CGFloat = 150
        static let switcherSubmenuWidth: CGFloat = 242
        static let inset = Space.xs
        static let radius = T.Radius.menu
        static let rowSpacing = Space.xxxs
        static let rowHeight = T.Size.Select.rowHeight
        /// A row with a second line (an emulator: name over model and Android version).
        static let tallRowHeight = T.Size.MenuPanel.tallRowHeight
        static let rowRadius = T.Radius.menuRow
        static let rowPaddingH = T.Size.Select.rowPaddingX
        static let rowGap = T.Size.Select.rowIconGap
        static let lineSpacing: CGFloat = 1
        static let checkSlot = T.Size.Select.checkSlot
        static let checkSize = T.Size.Select.check
        static let chevronSize = T.Size.Select.chevron
        static let headerHeight = T.Size.MenuPanel.headerHeight
        static let headerBottomPadding = Space.xxxs
        static let dividerHeight = T.Border.hairline
        static let dividerMarginV = Space.xxs
        static let hairline = T.Border.hairline
        static let tagPaddingH = Space.s
        static let tagPaddingV = Space.xxxs
        static let shadowOpacity = Double(T.Shadow.menu.colour.light.alpha)
        /// SwiftUI's shadow radius is half the token's blur.
        static let shadowRadius = T.Shadow.menu.blur / 2
        static let shadowY = T.Shadow.menu.y
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
        static let radius = T.Radius.control
        static let hoverOpacity = T.Opacity.toolbarHover
        static let chevronGap = Space.xs
        static let chevronSize: CGFloat = 8
    }

    /// The pill that takes the toolbar's place while a tool is on (boards 9 to 11): the tool's
    /// icon and name, or its state, and Done.
    enum ModePill {
        static let height = T.Size.ModePill.height
        static let minWidth = T.Size.ModePill.minWidth
        static let paddingLeading = Space.m
        static let paddingTrailing = Space.xxs
        static let gap = Space.s
        static let iconSize = T.Size.ModePill.icon
        static let buttonHeight = T.Size.Button.smallHeight
        static let buttonPaddingH = T.Size.Button.smallPaddingX
        static let hairline = T.Border.hairline
        static let buttonHairline = T.Border.control
        static let shadowOpacity: Double = 0.10
        static let shadowRadius: CGFloat = 1.5
        static let shadowY: CGFloat = 1
    }

    /// Inspect layout, Measure and Pick colour: what they draw over the live screen (boards 9
    /// to 11). Their colours are fixed, not per mode, because they sit on the device's screen.
    enum Tools {
        /// The outline around the inspected view, the measured line and the snap guides.
        static let outlineWidth = T.App.Pane.Size.Chip.outline
        static let outlineRadius = T.Radius.sm
        /// The paper halo on each side of an outline or line, so it holds up on any app.
        static let haloWidth: CGFloat = 1
        static let guideDash: [CGFloat] = [4, 3]
        /// Chips: a size on an outline, a distance on a guide, a length on a line, a hex.
        static let chipHeight = T.App.Pane.Size.Chip.height
        /// Chip text: `groupLabel` (11 medium) with fixed-width digits, so a changing number
        /// doesn't jitter.
        @MainActor static let chipFont = NSFont.monospacedDigitSystemFont(
            ofSize: T.TypeScale.groupLabel.size, weight: .medium)
        static let chipPaddingH = T.App.Pane.Size.Chip.paddingX
        static let chipRadius = T.Radius.sm
        static let chipGap = Space.xs
        static let chipRing = T.Border.hairline
        /// The pinned view's details card.
        static let cardWidth: CGFloat = 250
        static let cardPaddingH = Space.m
        static let cardPaddingV: CGFloat = 10
        static let cardRadius = T.Radius.menu
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
    static let sheetTitle = T.TypeScale.sectionTitle.font
    static let sheetBody = T.TypeScale.body.font
    static let sheetLabel = T.TypeScale.groupLabel.font
    @MainActor static let toolChip = Font(Theme.Tools.chipFont)
    static let toolCard = T.TypeScale.caption.font.monospacedDigit()
    static let modePill = Font.system(size: 12, weight: .medium)
    static let modePillButton = T.TypeScale.callout.font
    static let menuShortcut = T.TypeScale.callout.font
    static let menuHeader = T.TypeScale.groupLabel.font
    static let sheetRecent = T.TypeScale.callout.font
    /// A recent link on Open link (board 8): links are code, so `callout` in the mono face.
    static let sheetRecentLink = ThemeType(
        size: T.TypeScale.callout.size, weight: T.TypeScale.callout.weight, family: .mono
    ).font
    static let sheetSecondary = T.TypeScale.bodyMedium.font
    static let notice = Font.system(size: 12, weight: .medium)
}

extension Theme.Palette {
    /// `tool.select`: outlines, the measured line and the loupe's chosen pixel. Moss, the same
    /// in both modes (4.2:1 on a light device screen, 3.7:1 on a dark one).
    static let toolSelect = T.App.Pane.Colour.toolSelect.nsColor
    /// `tool.guide`: distances and snap guides. Amber, always dashed.
    static let toolGuide = T.App.Pane.Colour.toolGuide.nsColor
    /// `tool.halo`: paper on each side of an outline or line.
    static let toolHalo = T.App.Pane.Colour.toolHalo.nsColor
    /// `tool.fill`: the inspected view's wash.
    static let toolFill = T.App.Pane.Colour.toolFill.nsColor
    /// `tool.chip`: chips, the details card and the loupe's outer ring. Ink with paper text in
    /// both modes, because they sit on the device, not on Pane.
    static let toolChip = T.App.Pane.Colour.toolChip.nsColor
    /// `tool.chip` where no blur is drawn under the inspect card.
    static let toolChipSolid = T.App.Pane.Colour.toolChip.opaque.nsColor
    static let toolChipText = T.App.Pane.Colour.toolChipText.nsColor
    static let toolChipSecondary = T.Colour.Brand.mutedOnDark.nsColor
    static let toolChipRing = T.App.Pane.Colour.toolChipEdge.nsColor
    /// `scrim`: dims the device under the drop card while a drop is accepted or running.
    static let dropScrim = T.Colour.Role.scrim.nsColor
    /// Menu panels (`surfaceMenu`): white in light, raised ink in dark over a blur, solid under
    /// Increase Contrast.
    static let menuPanel = T.Colour.Role.surfaceMenu.nsColor
    /// `surfaceMenu` where no blur is drawn (Reduce Transparency, Increase Contrast).
    static let menuPanelSolid = T.Colour.Role.surfaceMenu.opaque.nsColor
    /// `hairline`, and `controlBoundary` under Increase Contrast.
    static let menuPanelHairline = T.Colour.Role.hairline.nsColor
    /// The row under the pointer or the keys (`highlight`).
    static let menuHighlight = T.Colour.Role.highlight.nsColor
    /// A menu's tick: the link moss of each mode.
    static let menuCheck = T.Colour.Role.link.nsColor
    /// The mode pill: `surfaceRaised` with its Done button on paper or raised ink.
    static let modePill = T.Colour.Role.surfacePill.nsColor
    static let modePillButton = T.Colour.Role.actionSecondary.nsColor
    /// The short notice line over the screen (always dark, over any app).
    static let toolSurface = T.App.Pane.Colour.toolChip.nsColor
    static let toolHairline = T.App.Pane.Colour.toolChipEdge.nsColor
    static let toolText = T.App.Pane.Colour.toolChipText.nsColor
    /// Sheet surfaces (design guide roles): the sheet itself, fields on it, secondary buttons.
    static let sheetSurface = T.Colour.Role.surfaceBaseSolid.nsColor
    static let fieldSurface = T.Colour.Role.surfaceRaised.nsColor
    static let secondaryAction = T.Colour.Role.actionSecondary.nsColor
    /// The Recent list's card on a sheet: recessed in light, raised in dark.
    static let sheetCard = T.Colour.Role.surfaceCard.nsColor
    /// A field's focus ring (moss) and its halo; red when the field's value was refused.
    static let fieldFocus = T.Colour.Role.focusRing.nsColor
    static let fieldFocusHalo = T.Colour.Role.openRing.nsColor
    static let problemText = T.Colour.Role.Status.danger.nsColor
    static let problemHalo = T.Colour.Role.Status.dangerFill.nsColor
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
        /// A start that hasn't answered by then says so and offers Stop (board 4).
        static let slowStart: Duration = .seconds(30)
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
