import AppKit
import SwiftUI

/// The Nidus component kit's tokens (`docs/mac-app-design.md`; the canvas's "Nidus kit and Pane
/// pieces" board): the values Drop's Settings, notification panel, buttons, switch and select
/// are drawn with, unchanged, so the same surfaces look the same in every Nidus app. Pane's own
/// pieces (the title row, the toolbar, the device frame) stay in `Theme`.
enum Kit {
    /// The notification panel's content inset, the same on all four sides.
    static let panelInset: CGFloat = 18

    /// The studio spacing scale (`docs/mac-app-design.md` 1.1). Every gap and inset is one of
    /// these; anything off the scale says which optical fix it is where it's declared.
    enum Space {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// The studio radii (`docs/mac-app-design.md` 1.4): capsules for actions, `control` for
    /// value controls, `card` for containers at window scale.
    enum Radius {
        static let control: CGFloat = 8
        static let card: CGFloat = 14
        /// The thin hairline every card and sheet list carries, with no shadow.
        static let cardHairline: CGFloat = 0.5
        /// Every hairline under Increase Contrast (`border.hairlineIncreasedContrast`).
        static let hairlineIncreasedContrast: CGFloat = 1
    }

    /// The panel card (boards 1-3, Update, Warning, Fallback, Password, Licence).
    enum Panel {
        static let width: CGFloat = 400
        static let spacing: CGFloat = 16
        /// The Licence board packs its taller content a little closer.
        static let licenceSpacing: CGFloat = Space.m
        static let cornerRadius: CGFloat = 18
        /// The boards' card is the surface at 92% over the popover material.
        static let surfaceOpacity: Double = 0.92
        static let titleSpacing: CGFloat = 2
        static let updateTitleSpacing: CGFloat = 4
        static let buttonRowTopPadding: CGFloat = 2
    }

    /// Dark mode's "ink glass" (DarkMode board, option 3): a dark behind-window material with
    /// an ink tint over it. Reduce Transparency gets solid ink instead. Light mode is the
    /// white surface (over the popover material for the popup).
    enum Glass {
        static let darkMaterial = NSVisualEffectView.Material.hudWindow
        static let lightPopupMaterial = NSVisualEffectView.Material.popover
        /// The popup and the centred window, and onboarding.
        static let panelTint = Color(nsColor: NSColor(hex: 0x1C1B22))
        static let panelTintOpacity: Double = 0.86
        /// Settings' window behind its groups.
        static let settingsTint = Color(nsColor: NSColor(hex: 0x18171D))
        static let settingsTintOpacity: Double = 0.88
        /// Reduce Transparency: solid ink.
        static let solidPanel = Color(nsColor: NSColor(hex: 0x232229))
        static let solidWindow = Color(nsColor: NSColor(hex: 0x1C1B21))
    }

    /// Where the popup sits: the Arrival board's top right, this far inside the visible
    /// frame (below the menu bar, left of the Dock if it's on the right).
    /// The Updates board: the update popup and the Settings banner.
    enum Update {
        /// Title to the "1.0 → 1.1" line.
        static let titleSpacing: CGFloat = 3
        /// Between release-note lines.
        static let noteSpacing: CGFloat = Space.xxs
        static let bulletGap: CGFloat = Space.xs
        static let bannerSpacing: CGFloat = Space.m
        static let bannerIcon: CGFloat = 28
        /// The banner's moss tint over the window.
        static let bannerFillOpacity: Double = 0.10
    }

    enum Popup {
        static let screenInset: CGFloat = 12
    }

    enum Icon {
        static let size: CGFloat = 60
        static let cornerRadius: CGFloat = 14
        static let licenceSize: CGFloat = 48
        static let licenceCornerRadius: CGFloat = 12
        static let glyph: CGFloat = 30
        static let placeholderGlyphScale: CGFloat = 0.9
        static let placeholderFillOpacity: Double = 0.5
        static let licenceGlyph: CGFloat = 26
        /// Off the scale on purpose: the NotificationPanel row's icon-to-title gap (guide 3,
        /// "row (gap 14)"), which optically balances the 60 pt tile against 17 pt text.
        static let titleSpacing: CGFloat = 14
        /// The green check on board 3's icon.
        static let badge: CGFloat = 24
        static let badgeBorder: CGFloat = 2
        static let badgeOffset: CGFloat = 6
        static let badgeStroke: CGFloat = 2.2
    }

    enum Font {
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let licenceTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let subtitle = SwiftUI.Font.system(size: 12)
        static let body = SwiftUI.Font.system(size: 13)
        static let small = SwiftUI.Font.system(size: 12)
        static let caption = SwiftUI.Font.system(size: 11)
        static let captionStrong = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let calloutTitle = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let button = SwiftUI.Font.system(size: 13, weight: .medium)
        static let primaryButton = SwiftUI.Font.system(size: 13, weight: .semibold)
        /// The hero capsules (240 × 38) on the install window and onboarding: 14 pt, as on
        /// the InstallWindow board.
        static let heroButton = SwiftUI.Font.system(size: 14)
        static let heroPrimaryButton = SwiftUI.Font.system(size: 14, weight: .semibold)
        /// `windowTitle`: an app's name centred in the install window.
        static let windowTitle = SwiftUI.Font.system(size: 22, weight: .semibold)
        /// `pageTitle`: "Settings".
        static let pageTitle = SwiftUI.Font.system(size: 20, weight: .semibold)
        /// `sectionTitle`: sheet titles.
        static let sectionTitle = SwiftUI.Font.system(size: 15, weight: .semibold)
        /// `groupLabel`: the label above a Settings card.
        static let groupLabel = SwiftUI.Font.system(size: 11, weight: .medium)
        /// The disclosure chevron and the ⓘ glyph.
        static let chevron = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let link = SwiftUI.Font.system(size: 12)
        /// Title tracking: -0.01em of 17 pt.
        static let titleTracking: CGFloat = -0.17
    }

    /// The kit's info cards: neutral (ok), warn and error.
    enum Card {
        static let verticalPadding: CGFloat = Space.m
        static let horizontalPadding: CGFloat = Space.m
        /// The popup's 400 pt scale keeps a smaller radius than window cards (guide, InfoCard).
        static let cornerRadius: CGFloat = 10
        static let rowSpacing: CGFloat = Space.s
        static let iconSpacing: CGFloat = 8
        static let calloutSpacing: CGFloat = 10
        static let calloutLineSpacing: CGFloat = 4
        static let rowIcon: CGFloat = 14
        static let rowGlyph: CGFloat = 12
        static let calloutIcon: CGFloat = 16
        static let calloutGlyph: CGFloat = 13
        static let lineSpacing: CGFloat = 2.5
        /// The neutral fill's ink share, for drawings that mix it into a solid colour.
        static let fillOpacity: Double = 0.04
        static let darkFillOpacity: Double = 0.06
    }

    /// The kit's buttons: capsules for actions, radius 8 for value controls (select, field).
    enum Button {
        /// The three heights: small 28, standard 30, hero 38 (guide, Controls).
        static let height: CGFloat = 30
        static let padding: CGFloat = 16
        static let heroHeight: CGFloat = 38
        static let heroWidth: CGFloat = 240
        /// Settings' Change… and Quit Drop.
        static let smallHeight: CGFloat = 28
        static let smallPadding: CGFloat = 14
        static let spacing: CGFloat = 8
        static let linkPadding: CGFloat = 2
        static let linkFocusRadius: CGFloat = 4
        /// Secondary hover and press: ink over the paper, as on the board.
        static let hoverShade: Double = 0.04
        static let pressShade: Double = 0.08
        static let hairline: CGFloat = 1
    }

    /// The kit's value controls.
    enum Control {
        static let cornerRadius: CGFloat = 8
        /// The focusVisible ring: solid moss, 2 pt, 2 pt outside the control's shape.
        static let focusRing: CGFloat = 2
        static let focusRingOffset: CGFloat = 2
        static let disabledOpacity: Double = 0.45
        static let switchWidth: CGFloat = 34
        static let switchHeight: CGFloat = 20
        static let switchKnob: CGFloat = 16
        static let switchInset: CGFloat = 2
        static let switchBorder: CGFloat = 1
        static let knobShadowOpacity: Double = 0.25
        static let knobShadowRadius: CGFloat = 1
        static let knobShadowY: CGFloat = 1
        static let switchLabelSpacing: CGFloat = Space.l
        static let captionSpacing: CGFloat = 2
        static let fieldVerticalPadding: CGFloat = 7
        static let fieldHorizontalPadding: CGFloat = 11
        static let fieldBorder: CGFloat = 1
    }

    /// The Nidus select (`NidusSelect`) and its menu (SelectMenu board).
    enum Select {
        static let height: CGFloat = 28
        static let minWidth: CGFloat = 144
        static let cornerRadius: CGFloat = Radius.control
        static let leading: CGFloat = 10
        static let trailing: CGFloat = Space.s
        /// Between the value and the chevron.
        static let spacing: CGFloat = Space.s
        /// Between the folder icon and the path, in the closed select.
        static let iconSpacing: CGFloat = Space.xs
        static let icon: CGFloat = 16
        static let chevron: CGFloat = 9
        static let fontSize: CGFloat = 13
        /// The soft moss ring the select wears while its menu is open, outside its edge.
        static let openRing: CGFloat = 3
        static let openRingOpacityLight: Double = 0.25
        static let openRingOpacityDark: Double = 0.35

        /// Between the select's bottom edge and the menu's top edge.
        static let menuGap: CGFloat = Space.xxs
        static let menuRadius: CGFloat = 10
        static let menuPadding: CGFloat = Space.xs
        static let menuHairline: CGFloat = 0.5
        /// Ink glass in dark: #24232B at 96% over the behind-window blur.
        static let menuDarkTint: UInt32 = 0x24232B
        static let menuDarkTintOpacity: Double = 0.96
        static let rowHeight: CGFloat = 32
        static let rowRadius: CGFloat = 7
        static let rowGap: CGFloat = Space.xxxs
        static let rowPadding: CGFloat = 10
        static let rowIconSpacing: CGFloat = 10
        static let check: CGFloat = 14
        static let checkWeight: SwiftUI.Font.Weight = .bold
        static let checkSize: CGFloat = 12
        /// Hover and keyboard highlight: moss over the surface.
        static let highlightLight: Double = 0.10
        static let highlightDark: Double = 0.16
        /// Typed letters count as one search while they come this close together.
        static let typeaheadWindow: TimeInterval = 1
    }

    enum Header {
        static let spacing: CGFloat = 6
        static let icon: CGFloat = 11
        /// Drop's own app icon before the "Drop" label.
        static let appIcon: CGFloat = 14
    }

    enum Progress {
        static let height: CGFloat = 6
        static let spacing: CGFloat = 8
        static let trackOpacity: Double = 0.08
    }

    /// The SettingsWindow primitive (SettingsV2 board).
    enum Settings {
        static let width: CGFloat = 560
        /// Taller content scrolls inside the window.
        static let maxHeight: CGFloat = 720
        /// Left, right and bottom of the page: the last card ends this far above the
        /// window's bottom edge, as the cards sit this far in from the sides.
        static let inset: CGFloat = Space.xl
        /// From the title bar's bottom (read from the window) to the page title, as the
        /// board draws it: 28 + 12 on today's title bar.
        static let titleBarGap: CGFloat = Space.m
        /// How far the scroll-edge fade runs below the title bar: rows scrolled up under it
        /// fade out over this distance and are gone under the traffic lights. Equal to
        /// `titleBarGap`, so at rest the fade ends exactly at the title.
        static let scrollEdgeFade: CGFloat = titleBarGap
        static let titleToGroups: CGFloat = Space.xxl
        static let groupSpacing: CGFloat = Space.l
        static let labelToCard: CGFloat = Space.xs
        static let labelInset: CGFloat = Space.xxs
        /// Between a row's controls (the popup's Install to row).
        static let rowSpacing: CGFloat = Space.s
        /// The ⓘ popover's text width.
        static let infoWidth: CGFloat = 260
    }

    /// The SettingsRow primitive: one setting, label left, control right.
    enum Row {
        static let horizontalPadding: CGFloat = Space.l
        static let verticalPadding: CGFloat = Space.m
        static let labelControlGap: CGFloat = Space.l
        static let titleInfoGap: CGFloat = Space.xs
        static let captionGap: CGFloat = Space.xxxs
        static let dividerInset: CGFloat = Space.l
    }

    /// The kit's colours as dynamic colours: light, dark, and an Increase Contrast variant
    /// of each. Every text colour was measured on rendered pixels (`.claude/screens/app-v2/
    /// measurements.md`); the hex values are the Components board's.
    enum Colour {
        /// Moss: the accent in both modes. White on it is 4.98:1.
        static let accent = Color(nsColor: .nidus(light: 0x4F7A4A, dark: 0x4F7A4A, contrast: 0x3B5D38))
        static let accentHover = Color(
            nsColor: .nidus(light: 0x456B41, dark: 0x527F4C, contrast: 0x34522F, darkContrast: 0x3B5D38))
        static let accentPressed = Color(
            nsColor: .nidus(light: 0x3B5D38, dark: 0x456B41, contrast: 0x2C4529, darkContrast: 0x34522F))
        /// Links and accent icons: a shade under moss on light (#466E41; moss itself measured
        /// 4.48:1 on the info card and 4.2:1 on Settings' rows, under 4.5), light moss on dark.
        static let link = Color(
            nsColor: .nidus(light: 0x466E41, dark: 0x8DBB82, contrast: 0x3B5D38, darkContrast: 0xA9D19F))
        static let onAccent = Color.white
        /// Ink: body text.
        static let bodyText = Color(
            nsColor: .nidus(light: 0x17161C, dark: 0xF4F4F6, contrast: 0x000000, darkContrast: 0xFFFFFF))
        /// Captions, subtitles, info lines. A shade under the kit's #6B6A73, which measured
        /// 4.36:1 on Settings' grouped rows: 5.9:1 on white, 4.8:1 on those rows, 8:1 on dark.
        static let secondaryText = Color(
            nsColor: .nidus(light: 0x64636C, dark: 0xB9B8C2, contrast: 0x3E3D45, darkContrast: 0xDCDBE3))
        /// Decoration and pending-step glyphs only, never text: 3:1 against the surface.
        static let tertiaryText = Color(nsColor: .controlBoundary)
        /// The panel and window surface.
        static let surface = Color(nsColor: .nidus(light: 0xFFFFFF, dark: 0x232229))
        /// Secondary buttons, the select and fields.
        static let paper = Color(nsColor: .paper)
        /// The board's hairline: ink at 12% (paper at 14% on dark); the boundary colour under
        /// Increase Contrast.
        static let hairline = Color(nsColor: .hairline)
        /// Boundaries that carry a control's state (the off switch track, fields): 3:1.
        static let controlBoundary = Color(nsColor: .controlBoundary)
        static let focusRing = Color(nsColor: .focusRing)
        static let switchOff = Color(nsColor: .nidus(light: 0xD8D7DE, dark: 0x4A4952))
        /// The neutral info card's fill.
        static let infoFill = Color(nsColor: .infoFill)
        /// Green status icons (signed, notarized, done steps).
        static let good = Color(
            nsColor: .nidus(light: 0x2F7A3A, dark: 0x8DBB82, contrast: 0x225C2B, darkContrast: 0xA9D19F))
        /// The Installed check's fill, with white on it in both modes (5.3:1).
        static let success = Color(nsColor: .nidus(light: 0x2F7A3A, dark: 0x2F7A3A, contrast: 0x225C2B))
        static let warnFill = Color(nsColor: .warnFill)
        static let warnText = Color(
            nsColor: .nidus(light: 0x6B4300, dark: 0xF5D3A1, contrast: 0x4A2F00, darkContrast: 0xFFE7C4))
        static let warnTitle = Color(
            nsColor: .nidus(light: 0x4A2F00, dark: 0xF5D3A1, contrast: 0x2E1D00, darkContrast: 0xFFE7C4))
        /// The warn icon, and Install Anyway (4.67:1 on white).
        static let warning = Color(
            nsColor: .nidus(light: 0xB25E00, dark: 0xF0A44B, contrast: 0x8A4800, darkContrast: 0xFFC27A))
        static let errorFill = Color(nsColor: .errorFill)
        /// The error icon and error text (5.75:1 on white, 6.9:1 on the dark surface).
        static let error = Color(
            nsColor: .nidus(light: 0xC4271B, dark: 0xFF8A80, contrast: 0x9E1D13, darkContrast: 0xFFB0A8))
        static let placeholderTile = Color(nsColor: .quaternaryLabelColor)
        static let separator = Color(nsColor: .hairline)
        static let textBackground = Color(nsColor: .textBackgroundColor)
        static let folder = link
    }

    /// Motion values from Purge (`.claude/research/purge-design.md`), re-implemented. Every
    /// animation has a Reduce Motion path, written beside its use.
    enum Motion {
        /// Popup entrance: the window slides in by its width, the content sharpens and settles.
        static let popupResponse: Double = 0.4
        static let popupDamping: Double = 0.9
        static let popupBlur: CGFloat = 6
        static let popupOffset: CGFloat = 8
        static var popup: Animation { .spring(response: popupResponse, dampingFraction: popupDamping) }
        /// Reduce Motion: a fade, no slide or blur.
        static let fadeDuration: Double = 0.2
        static var fade: Animation { .easeOut(duration: fadeDuration) }
        /// How close to its target the window frame spring counts as settled, in points.
        static let settleEpsilon: Double = 0.001

        /// Status line swap: blur, drift and fade (Purge's blurFade).
        static let swapBlur: CGFloat = 6
        static let swapOffset: CGFloat = 5
        static var swap: Animation { .spring(response: 0.4, dampingFraction: 0.9) }

        /// The progress bar never passes this until the install is done.
        static let progressCeiling: Double = 0.9
        static var progress: Animation { .easeInOut(duration: 0.3) }
        /// The filling button stays up at least this long, so a fast install doesn't flash past.
        static let installingHold: Duration = .milliseconds(900)
        /// Less work than this left at the click: no fill at all, straight to done (Progress
        /// board, "Usual case").
        static let skipProgressBelow: Duration = .milliseconds(400)
        /// The progress capsule's unfilled part: moss at this opacity.
        static let progressTrackOpacity: Double = 0.22

        /// The drawn Installed check.
        static var checkDraw: Animation { .easeInOut(duration: 0.6) }
        static let checkScaleFrom: CGFloat = 0.85
        static var checkScale: Animation { .spring(response: 0.35, dampingFraction: 0.7) }
        /// The beat between the badge scaling in and the stroke starting.
        static let checkBeat: Double = 0.15

        /// Numbers that change roll: progress, sizes.
        static var numbers: Animation { .easeInOut(duration: 0.45) }

        /// Onboarding: the old page blurs out, the new page's elements blur in in turn.
        static let pageBlur: CGFloat = 8
        static var page: Animation { .easeInOut(duration: 0.35) }
        static let staggerBlur: CGFloat = 10
        static let staggerDuration: Double = 0.45
        static let staggerStep: Double = 0.08

        /// Control states (Purge's button rules).
        static var hover: Animation { .easeOut(duration: 0.12) }
        static var enable: Animation { .easeInOut(duration: 0.28) }
        static var toggle: Animation { .spring(response: 0.25, dampingFraction: 0.85) }
    }
}

extension NSColor {
    /// A colour from the kit: `light` and `dark`, and their Increase Contrast variants
    /// (`contrast` for light, `darkContrast` for dark; each falls back to its mode's value).
    static func nidus(
        light: UInt32, dark: UInt32, contrast: UInt32? = nil, darkContrast: UInt32? = nil, alpha: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex: UInt32
            switch ColourLook(appearance) {
            case .dark: hex = dark
            case .lightContrast: hex = contrast ?? light
            case .darkContrast: hex = darkContrast ?? dark
            case .light: hex = light
            }
            return NSColor(hex: hex, alpha: alpha)
        }
    }

    /// One colour per appearance, for the translucent tokens.
    static func nidus(light: NSColor, dark: NSColor, contrast: NSColor, darkContrast: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            switch ColourLook(appearance) {
            case .dark: dark
            case .lightContrast: contrast
            case .darkContrast: darkContrast
            case .light: light
            }
        }
    }

    private static let ink: UInt32 = 0x17161C
    private static let paperHex: UInt32 = 0xF4F4F6

    static let controlBoundary = nidus(light: 0x8A8992, dark: 0x7A7983, contrast: 0x5E5D66, darkContrast: 0xA09FA8)
    /// Secondary buttons, the select and fields: paper on light, #2C2B33 at 90% on the dark
    /// glass (solid under Increase Contrast).
    static let paper = nidus(
        light: NSColor(hex: paperHex), dark: NSColor(hex: 0x2C2B33, alpha: 0.9), contrast: NSColor(hex: paperHex),
        darkContrast: NSColor(hex: 0x2C2B33))
    static let hairline = nidus(
        light: NSColor(hex: ink, alpha: 0.12), dark: NSColor(hex: paperHex, alpha: 0.12),
        contrast: .controlBoundary, darkContrast: .controlBoundary)
    /// Solid moss, so the ring clears 3:1 on every surface (5:1 on white, 7.9:1 on ink).
    static let focusRing = nidus(light: 0x4F7A4A, dark: 0x8DBB82, contrast: 0x3B5D38, darkContrast: 0xA9D19F)
    static let infoFill = nidus(
        light: NSColor(hex: ink, alpha: 0.04), dark: NSColor(hex: paperHex, alpha: 0.06),
        contrast: NSColor(hex: ink, alpha: 0.08), darkContrast: NSColor(hex: paperHex, alpha: 0.12))
    static let warnFill = nidus(
        light: NSColor(hex: 0xFFF4E0), dark: NSColor(hex: 0xFFAA3C, alpha: 0.14), contrast: NSColor(hex: 0xFFF4E0),
        darkContrast: NSColor(hex: 0xFFAA3C, alpha: 0.2))
    static let errorFill = nidus(
        light: NSColor(hex: 0xFDECEA), dark: NSColor(hex: 0xFF5A50, alpha: 0.14), contrast: NSColor(hex: 0xFDECEA),
        darkContrast: NSColor(hex: 0xFF5A50, alpha: 0.2))
}
