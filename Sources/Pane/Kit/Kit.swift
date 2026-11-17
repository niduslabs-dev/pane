import AppKit
import SwiftUI

private typealias T = ThemeTokens

/// The Nidus component kit's values under the names the kit's views use (`docs/mac-app-design.md`;
/// the canvas's "Nidus kit and Pane pieces" board): Drop's Settings, notification panel, buttons,
/// switch and select, so the same surfaces look the same in every Nidus app. Every shared value
/// reads `ThemeTokens` (`scripts/sync-tokens.sh`); change one in `assets/tokens.json`, never here.
/// The values written out below are Drop's own, with no token yet (`design/adoption/pane.md`,
/// group C); they move to tokens when Drop adopts them. Pane's own pieces (the title row, the
/// toolbar, the device frame) stay in `Theme`.
enum Kit {
    /// The notification panel's content inset, the same on all four sides.
    static let panelInset = T.Size.NotificationPanel.inset

    /// The studio spacing scale (`docs/mac-app-design.md` 1.1). Every gap and inset is one of
    /// these; anything off the scale says which optical fix it is where it's declared.
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

    /// The studio radii (`docs/mac-app-design.md` 1.4): capsules for actions, `control` for
    /// value controls, `card` for containers at window scale.
    enum Radius {
        static let control = T.Radius.control
        static let card = T.Radius.card
        /// The thin hairline every card and sheet list carries, with no shadow.
        static let cardHairline = T.Border.hairline
        /// Every hairline under Increase Contrast.
        static let hairlineIncreasedContrast = T.Border.hairlineIncreasedContrast
    }

    /// The panel card (boards 1-3, Update, Warning, Fallback, Password, Licence).
    enum Panel {
        static let width = T.Size.NotificationPanel.width
        static let spacing = T.Space.l
        /// The Licence board packs its taller content a little closer.
        static let licenceSpacing = T.Space.m
        static let cornerRadius = T.Radius.panel
        /// The boards' card is the surface at 92% over the popover material (Drop's own).
        static let surfaceOpacity: Double = 0.92
        static let titleSpacing = T.Space.xxxs
        static let updateTitleSpacing = T.Space.xxs
        static let buttonRowTopPadding = T.Space.xxxs
    }

    /// Dark mode's "ink glass" (DarkMode board, option 3): a dark behind-window material with
    /// an ink tint over it. Reduce Transparency gets solid ink instead. Light mode is the
    /// white surface (over the popover material for the popup).
    enum Glass {
        static let darkMaterial = NSVisualEffectView.Material.hudWindow
        static let lightPopupMaterial = NSVisualEffectView.Material.popover
        /// The popup and the centred window, and onboarding.
        static let panelTint = T.Colour.Role.glassTint.swiftUI
        static let panelTintOpacity = T.Opacity.glassTint
        /// Settings' window behind its groups (Drop's own).
        static let settingsTint = Color(nsColor: NSColor(hex: 0x18171D))
        static let settingsTintOpacity: Double = 0.88
        /// Reduce Transparency or Increase Contrast: solid ink (`surfaceBaseSolid`), the popup
        /// and the windows alike, the same as the emulator window's.
        static let solid = T.Colour.Role.surfaceBaseSolid.dark.swiftUI
    }

    /// The Updates board: the update popup and the Settings banner.
    enum Update {
        /// Title to the "1.0 → 1.1" line (Drop's own, off the scale).
        static let titleSpacing: CGFloat = 3
        /// Between release-note lines.
        static let noteSpacing = T.Space.xxs
        static let bulletGap = T.Space.xs
        static let bannerSpacing = T.Space.m
        static let bannerIcon: CGFloat = 28
        /// The banner's moss tint over the window.
        static let bannerFillOpacity: Double = 0.10
    }

    /// Where the popup sits: the Arrival board's top right, this far inside the visible
    /// frame (below the menu bar, left of the Dock if it's on the right).
    enum Popup {
        static let screenInset = T.Space.m
    }

    enum Icon {
        static let size = T.Size.NotificationPanel.media
        static let cornerRadius: CGFloat = 14
        static let licenceSize: CGFloat = 48
        static let licenceCornerRadius: CGFloat = 12
        static let glyph: CGFloat = 30
        static let placeholderGlyphScale: CGFloat = 0.9
        static let placeholderFillOpacity: Double = 0.5
        static let licenceGlyph: CGFloat = 26
        /// The NotificationPanel row's icon-to-title gap, which optically balances the 60 pt tile
        /// against 17 pt text.
        static let titleSpacing = T.Size.NotificationPanel.mediaGap
        /// The green check on board 3's icon.
        static let badge: CGFloat = 24
        static let badgeBorder: CGFloat = 2
        static let badgeOffset: CGFloat = 6
        static let badgeStroke: CGFloat = 2.2
    }

    enum Font {
        static let title = T.TypeScale.panelTitle.font
        static let licenceTitle = T.TypeScale.sectionTitle.font
        static let subtitle = T.TypeScale.callout.font
        static let body = T.TypeScale.body.font
        static let small = T.TypeScale.callout.font
        static let caption = T.TypeScale.caption.font
        static let captionStrong = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let calloutTitle = T.TypeScale.bodyEmphasis.font
        static let button = T.TypeScale.bodyMedium.font
        static let primaryButton = T.TypeScale.bodyEmphasis.font
        /// The hero capsules (240 × 38) on the install window and onboarding: 14 pt, as on
        /// the InstallWindow board (Drop's own; no 14 in the type scale).
        static let heroButton = SwiftUI.Font.system(size: 14)
        static let heroPrimaryButton = SwiftUI.Font.system(size: 14, weight: .semibold)
        /// An app's name centred in the install window.
        static let windowTitle = T.TypeScale.windowTitle.font
        /// "Settings".
        static let pageTitle = T.TypeScale.pageTitle.font
        /// Sheet titles.
        static let sectionTitle = T.TypeScale.sectionTitle.font
        /// The label above a Settings card.
        static let groupLabel = T.TypeScale.groupLabel.font
        /// The disclosure chevron and the ⓘ glyph.
        static let chevron = SwiftUI.Font.system(size: 11, weight: .semibold)
        static let link = T.TypeScale.callout.font
        static let titleTracking = T.TypeScale.panelTitle.tracking
    }

    /// The kit's info cards: neutral (ok), warn and error.
    enum Card {
        static let verticalPadding = T.Size.NotificationPanel.detailsPadY
        static let horizontalPadding = T.Space.m
        /// The popup's 400 pt scale keeps a smaller radius than window cards (guide, InfoCard).
        static let cornerRadius = T.Size.InfoCard.panelRadius
        static let rowSpacing = T.Size.NotificationPanel.detailsRowGap
        static let iconSpacing = T.Space.s
        static let calloutSpacing: CGFloat = 10
        static let calloutLineSpacing: CGFloat = 4
        static let rowIcon = T.Size.Icon.row
        static let rowGlyph: CGFloat = 12
        static let calloutIcon = T.Size.Icon.rowLarge
        static let calloutGlyph = T.Size.Icon.body
        static let lineSpacing: CGFloat = 2.5
    }

    /// The kit's buttons: capsules for actions, radius 8 for value controls (select, field).
    enum Button {
        /// The three heights: small 28, standard 30, hero 38 (guide, Controls).
        static let height = T.Size.Button.height
        static let padding = T.Size.Button.paddingX
        static let heroHeight = T.Size.Button.heroHeight
        static let heroWidth = T.Size.Button.heroWidth
        /// Settings' Change… and Quit Drop.
        static let smallHeight = T.Size.Button.smallHeight
        static let smallPadding = T.Size.Button.smallPaddingX
        static let spacing = T.Space.s
        static let linkPadding = T.Space.xxxs
        static let linkFocusRadius = T.Radius.xs
        /// Secondary hover and press: ink over the paper, as on the board.
        static let hoverShade = T.Opacity.hoverShade
        static let pressShade = T.Opacity.pressShade
        static let hairline = T.Border.control
    }

    /// The kit's value controls.
    enum Control {
        static let cornerRadius = T.Radius.control
        /// The focusVisible ring: solid moss, 2 pt, 2 pt outside the control's shape.
        static let focusRing = T.Border.focusRing
        static let focusRingOffset = T.Border.focusOffset
        static let disabledOpacity = T.Opacity.disabled
        static let switchWidth = T.Size.Switch.width
        static let switchHeight = T.Size.Switch.height
        static let switchKnob = T.Size.Switch.knob
        static let switchInset = T.Size.Switch.inset
        static let switchBorder = T.Border.control
        static let knobShadowOpacity = Double(T.Shadow.knob.colour.light.alpha)
        /// SwiftUI's shadow radius is half the token's blur.
        static let knobShadowRadius = T.Shadow.knob.blur / 2
        static let knobShadowY = T.Shadow.knob.y
        static let switchLabelSpacing = T.Space.l
        static let captionSpacing = T.Space.xxxs
        static let fieldVerticalPadding = T.Size.Field.paddingY
        static let fieldHorizontalPadding = T.Size.Field.paddingX
        static let fieldBorder = T.Border.control
    }

    /// The Nidus select (`NidusSelect`) and its menu (SelectMenu board).
    enum Select {
        static let height = T.Size.Select.height
        static let minWidth = T.Size.Select.minWidth
        static let cornerRadius = T.Radius.control
        static let leading = T.Size.Select.paddingLeading
        static let trailing = T.Space.s
        /// Between the value and the chevron.
        static let spacing = T.Space.s
        /// Between the folder icon and the path, in the closed select.
        static let iconSpacing = T.Space.xs
        static let icon = T.Size.Select.icon
        static let chevron = T.Size.Select.chevron
        static let fontSize = T.TypeScale.body.size
        /// The soft moss ring the select wears while its menu is open, outside its edge.
        static let openRing = T.Border.openRing

        /// Between the select's bottom edge and the menu's top edge.
        static let menuGap = T.Space.xxs
        static let menuRadius = T.Radius.menu
        static let menuPadding = T.Space.xs
        static let menuHairline = T.Border.hairline
        static let rowHeight = T.Size.Select.rowHeight
        static let rowRadius = T.Radius.menuRow
        static let rowGap = T.Space.xxxs
        static let rowPadding = T.Size.Select.rowPaddingX
        static let rowIconSpacing = T.Size.Select.rowIconGap
        /// The tick's slot, and the tick itself.
        static let check = T.Size.Select.checkSlot
        static let checkWeight: SwiftUI.Font.Weight = .bold
        static let checkSize = T.Size.Select.check
        /// Typed letters count as one search while they come this close together.
        static let typeaheadWindow = T.Motion.Duration.typeahead
    }

    enum Header {
        static let spacing = T.Space.xs
        static let icon = T.Size.NotificationPanel.header
        /// Drop's own app icon before the "Drop" label.
        static let appIcon = T.Size.Icon.row
    }

    enum Progress {
        static let height = T.Size.Progress.height
        static let spacing = T.Space.s
    }

    /// The SettingsWindow primitive (SettingsV2 board).
    enum Settings {
        static let width = T.Size.SettingsWindow.width
        /// Taller content scrolls inside the window.
        static let maxHeight = T.Size.SettingsWindow.maxHeight
        /// Left, right and bottom of the page: the last card ends this far above the
        /// window's bottom edge, as the cards sit this far in from the sides.
        static let inset = T.Space.xl
        /// From the title bar's bottom (read from the window) to the page title, as the
        /// board draws it: 28 + 12 on today's title bar.
        static let titleBarGap = T.Space.m
        /// How far the scroll-edge fade runs below the title bar: rows scrolled up under it
        /// fade out over this distance and are gone under the traffic lights. Equal to
        /// `titleBarGap`, so at rest the fade ends exactly at the title.
        static let scrollEdgeFade: CGFloat = titleBarGap
        static let titleToGroups = T.Space.xxl
        static let groupSpacing = T.Space.l
        static let labelToCard = T.Space.xs
        static let labelInset = T.Space.xxs
        /// Between a row's controls (the popup's Install to row).
        static let rowSpacing = T.Space.s
        /// The ⓘ popover's text width.
        static let infoWidth: CGFloat = 260
    }

    /// The SettingsRow primitive: one setting, label left, control right.
    enum Row {
        static let horizontalPadding = T.Space.l
        static let verticalPadding = T.Space.m
        static let labelControlGap = T.Space.l
        static let titleInfoGap = T.Space.xs
        static let captionGap = T.Space.xxxs
        static let dividerInset = T.Space.l
    }

    /// The kit's colours: the shared roles, each with its Increase Contrast values, resolved
    /// through `ColourLook`.
    enum Colour {
        /// Moss: the accent in both modes. White on it is 4.98:1.
        static let accent = T.Colour.Role.actionPrimary.swiftUI
        static let accentHover = T.Colour.Role.actionPrimaryHover.swiftUI
        static let accentPressed = T.Colour.Role.actionPrimaryPressed.swiftUI
        /// Links and accent icons: a shade under moss on light, light moss on dark.
        static let link = T.Colour.Role.link.swiftUI
        static let onAccent = T.Colour.Role.onAction.swiftUI
        /// Body text.
        static let bodyText = T.Colour.Role.textPrimary.swiftUI
        /// Captions, subtitles, info lines.
        static let secondaryText = T.Colour.Role.textSecondary.swiftUI
        /// Decoration and pending-step glyphs only, never text: 3:1 against the surface.
        static let tertiaryText = T.Colour.Role.controlBoundary.swiftUI
        /// The panel and window surface.
        static let surface = T.Colour.Role.surfaceBaseSolid.swiftUI
        /// Secondary buttons, the select and fields.
        static let paper = T.Colour.Role.surfaceRaised.swiftUI
        /// Ink: the hover and press shade over paper controls (`opacity.hoverShade`, `pressShade`).
        static let ink = T.Colour.Brand.ink.swiftUI
        /// The shade over a borderless row: ink in light, paper in dark.
        static let shade = T.Colour.Role.toolbarShade.swiftUI
        /// The thin edge on cards and controls; the boundary colour under Increase Contrast.
        static let hairline = T.Colour.Role.hairline.swiftUI
        /// Boundaries that carry a control's state (the off switch track, fields): 3:1.
        static let controlBoundary = T.Colour.Role.controlBoundary.swiftUI
        static let focusRing = T.Colour.Role.focusRing.swiftUI
        /// The soft ring a select wears while its menu is open.
        static let openRing = T.Colour.Role.openRing.swiftUI
        /// The hovered or keyboard-highlighted menu row.
        static let highlight = T.Colour.Role.highlight.swiftUI
        /// The select's menu panel: blurred in dark, `menuSurfaceSolid` where no blur is drawn.
        static let menuSurface = T.Colour.Role.surfaceMenu.swiftUI
        static let menuSurfaceSolid = T.Colour.Role.surfaceMenu.opaque.swiftUI
        /// A progress bar's unfilled part.
        static let track = T.Colour.Role.track.swiftUI
        static let switchOff = T.Colour.Role.switchOff.swiftUI
        /// The neutral info card's fill.
        static let infoFill = T.Colour.Role.surfaceCard.swiftUI
        /// Green status icons (signed, notarized, done steps).
        static let good = T.Colour.Role.Status.good.swiftUI
        /// The Installed check's fill, with white on it in both modes (5.3:1).
        static let success = T.Colour.Role.Status.success.swiftUI
        static let warnFill = T.Colour.Role.Status.warningFill.swiftUI
        static let warnText = T.Colour.Role.Status.warningText.swiftUI
        /// Drop's own warn-card title, a step darker than `warnText`.
        static let warnTitle = Color(
            nsColor: NSColor(name: nil) { appearance in
                switch ColourLook(appearance) {
                case .light: NSColor(hex: 0x4A2F00)
                case .lightContrast: NSColor(hex: 0x2E1D00)
                case .dark: NSColor(hex: 0xF5D3A1)
                case .darkContrast: NSColor(hex: 0xFFE7C4)
                }
            })
        /// The warn icon, and Install Anyway (4.67:1 on white).
        static let warning = T.Colour.Role.Status.warning.swiftUI
        static let errorFill = T.Colour.Role.Status.dangerFill.swiftUI
        /// The error icon and error text.
        static let error = T.Colour.Role.Status.danger.swiftUI
        static let placeholderTile = Color(nsColor: .quaternaryLabelColor)
        static let separator = hairline
        static let textBackground = Color(nsColor: .textBackgroundColor)
        static let folder = link
    }

    /// Motion values from Purge (`.claude/research/purge-design.md`), re-implemented. Every
    /// animation has a Reduce Motion path, written beside its use.
    enum Motion {
        /// Popup entrance: the window slides in by its width, the content sharpens and settles.
        static let popupResponse = T.Motion.Spring.slideIn.response
        static let popupDamping = T.Motion.Spring.slideIn.dampingFraction
        static let popupBlur: CGFloat = 6
        static let popupOffset = T.Motion.Distance.slideOffset
        static var popup: Animation { T.Motion.Spring.slideIn.animation }
        /// Reduce Motion: a fade, no slide or blur.
        static let fadeDuration = T.Motion.Duration.fade
        static var fade: Animation { .easeOut(duration: fadeDuration) }
        /// How close to its target the window frame spring counts as settled, in points.
        static let settleEpsilon: Double = 0.001

        /// Status line swap: blur, drift and fade (Purge's blurFade).
        static let swapBlur = T.Motion.Distance.swapBlur
        static let swapOffset = T.Motion.Distance.swapOffset
        static var swap: Animation { T.Motion.Spring.swap.animation }

        /// The progress bar never passes this until the install is done.
        static let progressCeiling = T.Motion.progressCeiling
        static var progress: Animation { .easeInOut(duration: 0.3) }
        /// The filling button stays up at least this long, so a fast install doesn't flash past.
        /// Drop's 900 ms, not `minDwell` (600 ms), until Drop decides (MIGRATION, Drop row 5).
        static let installingHold: Duration = .milliseconds(900)
        /// Less work than this left at the click: no fill at all, straight to done (Progress
        /// board, "Usual case").
        static let skipProgressBelow: Duration = .milliseconds(400)
        /// The progress capsule's unfilled part: moss at this opacity.
        static let progressTrackOpacity: Double = 0.22

        /// The drawn Installed check.
        static var checkDraw: Animation { .easeInOut(duration: 0.6) }
        static let checkScaleFrom: CGFloat = 0.85
        static var checkScale: Animation { T.Motion.Spring.check.animation }
        /// The beat between the badge scaling in and the stroke starting.
        static let checkBeat: Double = 0.15

        /// Numbers that change roll: progress, sizes.
        static var numbers: Animation { .easeInOut(duration: T.Motion.Duration.numbers) }

        /// Onboarding: the old page blurs out, the new page's elements blur in in turn.
        static let pageBlur = T.Motion.Distance.pageBlur
        static var page: Animation { .easeInOut(duration: T.Motion.Duration.page) }
        static let staggerBlur = T.Motion.Distance.staggerBlur
        static let staggerDuration = T.Motion.Duration.stagger
        static let staggerStep = T.Motion.Duration.staggerStep

        /// Control states (Purge's button rules).
        static var hover: Animation { .easeOut(duration: T.Motion.Duration.hover) }
        static var enable: Animation { .easeInOut(duration: T.Motion.Duration.enable) }
        static var toggle: Animation { T.Motion.Spring.toggle.animation }
    }
}
