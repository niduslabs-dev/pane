import AppKit
import QuartzCore
import SwiftUI

// The Nidus kit's containers, as in Drop: the notification panel's card, the window backdrops,
// info cards, Settings rows and the button row.

extension EnvironmentValues {
    /// The window's title bar height, read from the window (Settings).
    @Entry var titleBarHeight: CGFloat = 0
    /// Cards at the popup's 400 pt scale (radius 10, padding 12) or window scale (radius 14,
    /// padding 12 × 16), per the guide's InfoCard.
    @Entry var cardScale = CardScale.panel
}

enum CardScale {
    case panel
    case window

    var cornerRadius: CGFloat { self == .panel ? Kit.Card.cornerRadius : Kit.Radius.card }
    var horizontalPadding: CGFloat { self == .panel ? Kit.Card.horizontalPadding : Kit.Space.l }
}

/// What Reduce Transparency and Increase Contrast ask for. Debug builds also take
/// `-PaneReduceTransparency YES` and `-PaneIncreaseContrast YES`, so a background check sees
/// the fallbacks without changing system settings.
@MainActor
enum DisplayOptions {
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || debugFlag("PaneReduceTransparency")
    }

    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast || debugFlag("PaneIncreaseContrast")
    }

    /// Gives a window the high-contrast look when only the debug flag asks for it (the
    /// system setting changes every window's appearance by itself).
    static func applyDebugContrast(to window: NSWindow) {
        guard debugFlag("PaneIncreaseContrast") else { return }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        window.appearance = NSAppearance(
            named: isDark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
    }

    fileprivate static func debugFlag(_ key: String) -> Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: key)
        #else
            false
        #endif
    }
}

extension View {
    /// Goes on every hosting root. In a debug build `-PaneIncreaseContrast YES` and
    /// `-PaneReduceTransparency YES` reach SwiftUI's environment the way the system settings
    /// do, so colours resolve to their Increase Contrast values, hairlines thicken and glass
    /// turns solid. Setting only the window's appearance doesn't: SwiftUI resolves colours from
    /// its own environment. Release builds leave the environment to the system.
    func displayOptions() -> some View {
        #if DEBUG
            transformEnvironment(\._colorSchemeContrast) { contrast in
                if DisplayOptions.debugFlag("PaneIncreaseContrast") { contrast = .increased }
            }
            .transformEnvironment(\._accessibilityReduceTransparency) { reduce in
                if DisplayOptions.debugFlag("PaneReduceTransparency") { reduce = true }
            }
        #else
            self
        #endif
    }
}

/// A hairline edge (`border.hairline`): `width` normally, 1 pt under Increase Contrast, where
/// `Kit.Colour.hairline` also turns to the control boundary colour.
struct Hairline<S: InsettableShape>: View {
    let shape: S
    var width = Kit.Radius.cardHairline
    var colour = Kit.Colour.hairline
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        shape.strokeBorder(colour, lineWidth: Kit.hairlineWidth(width, contrast: contrast))
    }
}

extension Kit {
    /// A hairline's width: thicker under Increase Contrast, never thinner.
    static func hairlineWidth(_ width: CGFloat, contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? max(width, Radius.hairlineIncreasedContrast) : width
    }
}

/// The card a notification panel's content sits in: rounded, the surface over the popover
/// material, a hairline border, the same inset on all four sides.
struct PanelCard<Content: View>: View {
    var spacing: CGFloat = Kit.Panel.spacing
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.Panel.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: spacing) { content }
            .font(Kit.Font.body)
            .foregroundStyle(Kit.Colour.bodyText)
            .padding(Kit.panelInset)
            .frame(width: Kit.Panel.width, alignment: .leading)
            .background { SurfaceBackground(kind: .popup).clipShape(shape) }
            .overlay { Hairline(shape: shape) }
    }
}

/// A window's backdrop. Light: the white surface, over the popover material for the popup.
/// Dark: the ink glass (`Kit.Glass`), or solid ink with Reduce Transparency or Increase
/// Contrast.
struct SurfaceBackground: View {
    enum Kind {
        case popup
        case settings
    }
    let kind: Kind
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let solid = reduceTransparency || contrast == .increased || DisplayOptions.reduceTransparency
        if colorScheme == .dark {
            if solid {
                Kit.Glass.solid
            } else {
                ZStack {
                    VisualEffectBackground(material: Kit.Glass.darkMaterial)
                    if kind == .settings {
                        Kit.Glass.settingsTint.opacity(Kit.Glass.settingsTintOpacity)
                    } else {
                        Kit.Glass.panelTint.opacity(Kit.Glass.panelTintOpacity)
                    }
                }
            }
        } else if kind == .popup, !solid {
            ZStack {
                VisualEffectBackground(material: Kit.Glass.lightPopupMaterial)
                Kit.Colour.surface.opacity(Kit.Panel.surfaceOpacity)
            }
        } else {
            Kit.Colour.surface
        }
    }
}

/// An always-active behind-window material, so the backdrop doesn't dim while Pane is in the
/// background (the popup never takes focus).
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// The kit's info card: neutral by default, or warn or error.
struct InfoCard<Content: View>: View {
    var kind = CardKind.ok
    var spacing: CGFloat = Kit.Card.rowSpacing
    @ViewBuilder var content: Content
    @Environment(\.cardScale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: spacing) { content }
            .font(Kit.Font.small)
            .foregroundStyle(kind.text)
            .padding(.vertical, Kit.Card.verticalPadding)
            .padding(.horizontal, scale.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(kind.fill, in: shape)
            .overlay { Hairline(shape: shape) }
    }
}

/// A window-scale card (r14, 0.5 hairline, no shadow) holding SettingsRows: the install
/// window's options and every Settings group.
struct RowCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.Radius.card, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(Kit.Colour.hairline)
                            .frame(height: Kit.hairlineWidth(Kit.Radius.cardHairline, contrast: contrast))
                            .padding(.horizontal, Kit.Row.dividerInset)
                    }
                    row
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Kit.Colour.infoFill, in: shape)
        .overlay { Hairline(shape: shape) }
    }
}

/// The SettingsRow primitive: a title (with an optional ⓘ and one caption line) on the
/// left and one control on the right, padded 16 × 12.
struct SettingsRow<Control: View, Info: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var info: Info
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: Kit.Row.labelControlGap) {
            VStack(alignment: .leading, spacing: Kit.Row.captionGap) {
                HStack(spacing: Kit.Row.titleInfoGap) {
                    Text(title).font(Kit.Font.body).foregroundStyle(Kit.Colour.bodyText)
                    info
                }
                if let caption {
                    Text(caption).font(Kit.Font.caption).foregroundStyle(Kit.Colour.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, Kit.Row.horizontalPadding)
        .padding(.vertical, Kit.Row.verticalPadding)
    }
}

extension SettingsRow where Info == EmptyView {
    init(_ title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.init(title: title, caption: caption, info: { EmptyView() }, control: control)
    }
}

/// A switch as a whole SettingsRow: the row toggles on click, Space toggles it when
/// focused, and VoiceOver reads it as one switch named by the title, with the caption as its
/// hint. The switch is drawn on its own (`.labelsHidden()`), so its accessibility frame is
/// the switch's 34 × 20, not the row.
struct SwitchRow: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Kit.Control.switchLabelSpacing) {
            // The label side takes the clicks the switch doesn't, so the whole row toggles. It
            // is a button outside the switch (not a gesture on the row, which would make SwiftUI
            // give the switch's accessibility element the row's frame), hidden from VoiceOver
            // and Tab, which reach the switch.
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: Kit.Control.captionSpacing) {
                    Text(title).font(Kit.Font.body).foregroundStyle(Kit.Colour.bodyText)
                    if let caption {
                        Text(caption).font(Kit.Font.caption).foregroundStyle(Kit.Colour.secondaryText).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : Kit.Control.disabledOpacity)
            }
            .buttonStyle(RowLabelButtonStyle())
            .focusable(false)
            .accessibilityHidden(true)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.nidusSwitch)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityHint(caption ?? "")
        }
        .padding(.horizontal, Kit.Row.horizontalPadding)
        .padding(.vertical, Kit.Row.verticalPadding)
    }

    private func toggle() {
        guard isEnabled else { return }
        withAnimation(reduceMotion ? nil : Kit.Motion.toggle) { isOn.toggle() }
    }
}

/// A row's label as a button: drawn as it is, no press shade and no dimming of its own.
private struct RowLabelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The bottom row: an optional link on the left, buttons on the right. When long labels
/// (a long app name in "Open <name>", a translation) don't fit on one line, the link moves
/// above the buttons, then the buttons stack, right-aligned; a label is never squeezed.
struct ButtonRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Kit.Button.spacing) {
                leading
                Spacer(minLength: Kit.Button.spacing)
                trailing
            }
            VStack(alignment: .trailing, spacing: Kit.Button.spacing) {
                HStack {
                    leading
                    Spacer(minLength: 0)
                }
                HStack(spacing: Kit.Button.spacing) { trailing }
            }
            VStack(alignment: .trailing, spacing: Kit.Button.spacing) {
                HStack {
                    leading
                    Spacer(minLength: 0)
                }
                trailing
            }
        }
    }
}

extension ButtonRow where Leading == EmptyView {
    init(@ViewBuilder trailing: () -> Trailing) {
        self.init(leading: { EmptyView() }, trailing: trailing)
    }
}

/// The popup a new download gets: a borderless, non-activating panel at the top right that
/// floats above other apps on every Space (and beside full-screen apps) and never activates
/// Pane, so whatever the user is typing into stays the active app. Clicking it makes it key
/// (still without activating Pane), so Tab, Space, Return and Esc then work in it.
final class PopupPanel: NSPanel {
    /// Esc while the panel is key.
    var onCancel: () -> Void = {}

    init() {
        super.init(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // Our own slide and blur are the only motion; the system's zoom-in would double it.
        animationBehavior = .none
        isReleasedWhenClosed = false
        title = "Pane"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel() }
}

/// The window an opened disk image gets (Open With, a double-click): a normal titled

extension NSWindow {
    /// Our SwiftUI surface paints the whole window, title bar band included: no title bar
    /// material or separator of its own, and a clear window background, so the band can't
    /// show a different colour from the content (light surface, or dark ink glass).
    func paintsSurfaceUnderTitleBar() {
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isOpaque = false
        backgroundColor = .clear
    }
}

/// (response 0.4, damping 0.9), one step per display refresh. The target can move while it
/// runs (the content resizes as the board fills in). Also the update popup's entrance.
@MainActor
final class FrameSlide: NSObject {
    private weak var window: NSWindow?
    var target: NSRect
    private let offset: CGFloat
    private let spring = Spring(response: Kit.Motion.popupResponse, dampingRatio: Kit.Motion.popupDamping)
    private var link: CADisplayLink?
    private var startTime: CFTimeInterval = 0

    init(window: NSWindow, target: NSRect, offset: CGFloat) {
        self.window = window
        self.target = target
        self.offset = offset
    }

    var isRunning: Bool { link != nil }

    func start() {
        window?.setFrame(target.offsetBy(dx: offset, dy: 0), display: false)
        startTime = CACurrentMediaTime()
        // The screen's link, not the window's: the window starts off the screen's edge,
        // where it has no display to tick with.
        let screen = NSScreen.main ?? NSScreen.screens.first
        let link = screen?.displayLink(target: self, selector: #selector(step(_:)))
        link?.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - startTime
        let progress = spring.value(target: 1.0, time: elapsed)
        let settled = elapsed >= spring.settlingDuration(target: 1.0, epsilon: Kit.Motion.settleEpsilon)
        let remaining = settled ? 0 : (1 - progress) * offset
        window?.setFrame(target.offsetBy(dx: remaining, dy: 0), display: true)
        if settled { stop() }
    }
}

extension PopupPanel {
    /// The top right of the screen with the active menu bar, inside its visible frame (so
    /// below the menu bar whatever its height, and clear of a Dock on the right).
    ///
    /// `NSScreen.main` is the screen of the key window, else the one whose menu bar is
    /// active: the one the user is working on, which is where a notification would appear too.
    static func frame(for size: CGSize) -> NSRect? {
        guard size.width > 0, size.height > 0, let screen = NSScreen.main ?? NSScreen.screens.first else {
            return nil
        }
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.maxX - Kit.Popup.screenInset - size.width,
            y: visible.maxY - Kit.Popup.screenInset - size.height, width: size.width, height: size.height)
    }
}

/// How Pane's secondary windows come forward. A debug build with `-PaneBackgroundCheck YES`
/// never covers what the user is doing: windows are ordered in at the normal level behind
/// every other window, Pane isn't activated and nothing becomes key. `screencapture -l` still
/// captures them, and checks drive them through the accessibility API.
@MainActor
enum WindowPresence {
    static var isBackgroundCheck: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "PaneBackgroundCheck")
        #else
            false
        #endif
    }

    /// Shows `window` as the one the user is working in.
    static func present(_ window: NSWindow) {
        if isBackgroundCheck {
            orderInBehind(window)
        } else {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Shows a window that must not take focus (the popup).
    static func presentWithoutFocus(_ window: NSWindow) {
        if isBackgroundCheck {
            orderInBehind(window)
        } else {
            window.orderFrontRegardless()
        }
    }

    private static func orderInBehind(_ window: NSWindow) {
        window.level = .normal
        window.orderBack(nil)
    }
}
