import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

// The Nidus component kit (Components.dc.html) as styles on real SwiftUI controls, so
// VoiceOver, keyboard shortcuts, dark mode and Increase Contrast keep working.
//
// Keyboard: every control here is focusable with Tab even when macOS Keyboard navigation
// is off (the design asks for it in onboarding, the popup and the centred window), shows
// the moss focus ring, and Space presses or toggles it. A standard `Button` only joins the
// key loop when Keyboard navigation is on, so the styles make the label focusable
// themselves with the `.edit` interaction, which macOS always lets Tab reach (as it does
// text fields), and draw their own ring.

extension View {
    /// Tab-focusable regardless of the Keyboard navigation setting, with Space running
    /// `onSpace`. The system focus effect is off; the caller draws `FocusRing`.
    func nidusFocusable(_ focused: FocusState<Bool>.Binding, enabled: Bool, onSpace: @escaping () -> Void)
        -> some View
    {
        focusable(enabled, interactions: .edit)
            .focused(focused)
            .focusEffectDisabled()
            .onKeyPress(.space) {
                guard enabled else { return .ignored }
                onSpace()
                return .handled
            }
    }

    /// A button label never wraps or truncates: the button grows to fit it, and the row
    /// around it makes room (`ButtonRow`).
    func singleLineLabel() -> some View {
        lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
}

/// The focusVisible behaviour: whether focus rings show. Hidden until the user presses a
/// keyboard focus key (Tab, Shift-Tab or an arrow), then shown while they keep using the
/// keyboard; any mouse click hides them again until the next such key. One value for the
/// whole app, fed by a local event monitor, so every window agrees.
@MainActor
@Observable
final class FocusVisibility {
    static let shared = FocusVisibility()

    private(set) var isVisible = false
    @ObservationIgnored private var monitor: Any?

    /// Tab, and the arrows, which move focus in lists and between buttons.
    private static let focusKeys: Set<UInt16> = Set(
        [kVK_Tab, kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow].map { UInt16($0) })

    /// Starts watching events. Called once at launch; later calls do nothing.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        ]) { event in
            MainActor.assumeIsolated {
                FocusVisibility.shared.observe(type: event.type, keyCode: event.type == .keyDown ? event.keyCode : 0)
            }
            return event
        }
    }

    /// Applies one event: a focus key shows rings, a click hides them. Other keys (Space,
    /// Return, typing) leave them as they are.
    func observe(type: NSEvent.EventType, keyCode: UInt16) {
        switch type {
        case .keyDown where Self.focusKeys.contains(keyCode):
            if !isVisible { isVisible = true }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if isVisible { isVisible = false }
        default:
            break
        }
    }
}

/// The kit's focus ring: solid moss, 2 pt, 2 pt outside the control's shape. Drawn only
/// after keyboard use (`FocusVisibility`) and while the window is key: SwiftUI gives the
/// first control focus as soon as a window shows, and a ring the user didn't ask for would
/// suggest keys go there.
///
/// The ring is in the view tree only while it shows. SwiftUI makes a button's or a select's
/// accessibility frame the union of everything it draws, so a ring kept at opacity 0 would
/// grow the control's frame by the ring's 4 pt on every side: VoiceOver's outline and the
/// measured check would read a 36 pt select instead of 28.
struct FocusRing<S: InsettableShape>: ViewModifier {
    let isFocused: Bool
    let shape: S
    @Environment(\.appearsActive) private var appearsActive

    func body(content: Content) -> some View {
        let shown = isFocused && appearsActive && FocusVisibility.shared.isVisible
        content.overlay {
            if shown {
                shape.inset(by: -(Kit.Control.focusRingOffset + Kit.Control.focusRing / 2))
                    .stroke(Kit.Colour.focusRing, lineWidth: Kit.Control.focusRing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Buttons

/// Primary (moss capsule), secondary (paper capsule with a hairline) and link (text). The
/// select is its own control (`NidusSelect`, Select.swift). A `PrimitiveButtonStyle`, so it
/// can trigger the button from Space and draw its own pressed state; Return still reaches
/// `.keyboardShortcut`.
struct NidusButtonStyle: PrimitiveButtonStyle {
    enum Kind {
        case primary
        case secondary
        case link(Color)
        /// The label as drawn, with only the press shade and the focus ring: disclosure rows
        /// and the ⓘ button.
        case plain
    }
    enum Size {
        case regular
        case small
        /// 240 × 38, for the install window and onboarding.
        case hero
    }

    var kind: Kind = .secondary
    var size: Size = .regular
    var font: Font?
    /// Reports this button's keyboard focus and takes focus requests (`FocusLink`).
    var focusLink: FocusLink?

    func makeBody(configuration: Configuration) -> some View {
        NidusButtonBody(configuration: configuration, kind: kind, size: size, font: font, focusLink: focusLink)
    }
}

/// Keyboard focus between kit controls that can't share a `FocusState` (each kit button
/// keeps its own). A button given a link reports its focus into `isFocused` and takes focus
/// when `request()` is called. `isFocused` keeps its last value while the button is
/// disabled, so a row can tell that the button which just dimmed had focus and move it on
/// (macOS can't keep focus on a disabled control).
@MainActor
@Observable
final class FocusLink {
    /// The linked control had focus when it was last enabled.
    var isFocused = false
    /// Bumped by `request()`; the linked control takes focus on each change.
    private(set) var requests = 0

    func request() { requests += 1 }
}

extension PrimitiveButtonStyle where Self == NidusButtonStyle {
    static var nidusPrimary: NidusButtonStyle { NidusButtonStyle(kind: .primary) }
    static var nidusSecondary: NidusButtonStyle { NidusButtonStyle(kind: .secondary) }
    static var nidusSmall: NidusButtonStyle { NidusButtonStyle(kind: .secondary, size: .small) }
    static var nidusHeroPrimary: NidusButtonStyle { NidusButtonStyle(kind: .primary, size: .hero) }
    static var nidusHeroSecondary: NidusButtonStyle { NidusButtonStyle(kind: .secondary, size: .hero) }
    static var nidusPlain: NidusButtonStyle { NidusButtonStyle(kind: .plain) }
    static func nidusLink(_ colour: Color = Kit.Colour.link, font: Font = Kit.Font.link) -> NidusButtonStyle {
        NidusButtonStyle(kind: .link(colour), font: font)
    }
}

private struct NidusButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let kind: NidusButtonStyle.Kind
    let size: NidusButtonStyle.Size
    let font: Font?
    let focusLink: FocusLink?

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var bounds = CGSize.zero
    @FocusState private var isFocused: Bool

    var body: some View {
        styled
            .contentShape(shape)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { bounds = $0 }
            .gesture(press, including: isEnabled ? .all : .none)
            .onHover { hovering in withAnimation(Kit.Motion.hover) { isHovered = hovering && isEnabled } }
            .modifier(FocusRing(isFocused: isFocused, shape: shape))
            .nidusFocusable($isFocused, enabled: isEnabled) { configuration.trigger() }
            .opacity(isEnabled ? 1 : Kit.Control.disabledOpacity)
            .animation(Kit.Motion.enable, value: isEnabled)
            .onChange(of: isFocused) { if isEnabled { focusLink?.isFocused = isFocused } }
            .onChange(of: focusLink?.requests) { if isEnabled { isFocused = true } }
    }

    private var height: CGFloat {
        switch size {
        case .small: Kit.Button.smallHeight
        case .regular: Kit.Button.height
        case .hero: Kit.Button.heroHeight
        }
    }

    private var horizontalPadding: CGFloat { size == .small ? Kit.Button.smallPadding : Kit.Button.padding }

    /// Hero capsules are a fixed 240 wide; the others fit their label.
    private var heroWidth: CGFloat? { size == .hero ? Kit.Button.heroWidth : nil }

    private var shape: RoundedRectangle {
        switch kind {
        case .primary, .secondary: RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        case .link: RoundedRectangle(cornerRadius: Kit.Button.linkFocusRadius, style: .continuous)
        case .plain: RoundedRectangle(cornerRadius: Kit.Control.cornerRadius, style: .continuous)
        }
    }

    @ViewBuilder private var styled: some View {
        let label = configuration.label.singleLineLabel()
        switch kind {
        case .primary:
            label
                .font(font ?? (size == .hero ? Kit.Font.heroPrimaryButton : Kit.Font.primaryButton))
                .foregroundStyle(Kit.Colour.onAccent)
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: heroWidth, minHeight: height)
                .background(primaryFill, in: shape)
        case .secondary:
            label
                .font(font ?? (size == .hero ? Kit.Font.heroButton : Kit.Font.button))
                .foregroundStyle(Kit.Colour.bodyText)
                .padding(.horizontal, horizontalPadding)
                .frame(minWidth: heroWidth, minHeight: height)
                .background(paper)
                .overlay { Hairline(shape: shape, width: Kit.Button.hairline) }
        case .link(let colour):
            label
                .font(font ?? Kit.Font.link)
                .foregroundStyle(isPressed ? Kit.Colour.accentPressed : colour)
                .underline(isHovered)
                .padding(.horizontal, Kit.Button.linkPadding)
        case .plain:
            // A row's own layout decides its width; only labels of capsules are kept on one line.
            configuration.label
                .background {
                    shape.fill(
                        Kit.Colour.shade.opacity(
                            isPressed ? Kit.Button.pressShade : isHovered ? Kit.Button.hoverShade : 0))
                }
        }
    }

    private var primaryFill: Color {
        isPressed ? Kit.Colour.accentPressed : isHovered ? Kit.Colour.accentHover : Kit.Colour.accent
    }

    /// Paper with the board's hover and press shade over it.
    private var paper: some View {
        shape.fill(Kit.Colour.paper)
            .overlay {
                shape.fill(
                    Kit.Colour.ink.opacity(isPressed ? Kit.Button.pressShade : isHovered ? Kit.Button.hoverShade : 0))
            }
    }

    /// Presses on mouse down, triggers on mouse up inside, like a native button.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let inside = CGRect(origin: .zero, size: bounds).contains(value.location)
                if inside != isPressed { withAnimation(Kit.Motion.hover) { isPressed = inside } }
            }
            .onEnded { value in
                withAnimation(Kit.Motion.hover) { isPressed = false }
                if CGRect(origin: .zero, size: bounds).contains(value.location) { configuration.trigger() }
            }
    }
}

// MARK: - Toggles

/// The kit's switch (34 × 20, moss track, white knob): label on the left, switch on the
/// right. The whole row toggles on click; Space toggles it when focused. The kit has no
/// checkboxes; every on/off choice is this switch.
///
/// With `.labelsHidden()` it draws only the switch, and that is also its accessibility
/// element and frame (34 × 20, as AppKit's switch), which VoiceOver outlines and the measured
/// check reads. Settings rows use it that way (`SwitchRow`); with the label drawn, the element
/// is the whole row.
struct NidusSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        NidusSwitchBody(configuration: configuration)
    }
}

extension ToggleStyle where Self == NidusSwitchStyle {
    static var nidusSwitch: NidusSwitchStyle { NidusSwitchStyle() }
}

private struct NidusSwitchBody: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.labelsVisibility) private var labelsVisibility
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var isFocused: Bool

    var body: some View {
        content
            .onTapGesture { toggle() }
            .nidusFocusable($isFocused, enabled: isEnabled) { toggle() }
            .opacity(isEnabled ? 1 : Kit.Control.disabledOpacity)
            .animation(Kit.Motion.enable, value: isEnabled)
            // One element named by the label's text (or the caller's accessibility label when
            // it's hidden), read as a switch with its state, and toggled by VoiceOver's press
            // like the native switch.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(configuration.isOn ? "on" : "off")
            .accessibilityAction { toggle() }
    }

    @ViewBuilder private var content: some View {
        if labelsVisibility == .hidden {
            track
        } else {
            HStack(spacing: Kit.Control.switchLabelSpacing) {
                VStack(alignment: .leading, spacing: Kit.Control.captionSpacing) { configuration.label }
                Spacer(minLength: 0)
                track
            }
            .contentShape(Rectangle())
        }
    }

    private func toggle() {
        guard isEnabled else { return }
        withAnimation(reduceMotion ? nil : Kit.Motion.toggle) { configuration.isOn.toggle() }
    }

    private var track: some View {
        let shape = Capsule()
        return shape.fill(configuration.isOn ? Kit.Colour.accent : Kit.Colour.switchOff)
            .overlay {
                // The off track's edge is for Increase Contrast only (the Switch contract).
                shape.strokeBorder(Kit.Colour.controlBoundary, lineWidth: Kit.Control.switchBorder)
                    .opacity(!configuration.isOn && contrast == .increased ? 1 : 0)
            }
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle().fill(Color.white)
                    .shadow(
                        color: .black.opacity(Kit.Control.knobShadowOpacity), radius: Kit.Control.knobShadowRadius,
                        y: Kit.Control.knobShadowY
                    )
                    .frame(width: Kit.Control.switchKnob, height: Kit.Control.switchKnob)
                    .padding(Kit.Control.switchInset)
            }
            .frame(width: Kit.Control.switchWidth, height: Kit.Control.switchHeight)
            .modifier(FocusRing(isFocused: isFocused, shape: shape))
    }
}

// MARK: - Fields

extension View {
    /// The kit's text field: paper, radius 8, a 3:1 boundary, a moss border when focused
    /// (and the ring after keyboard use), red when the last attempt failed.
    func nidusField(isFocused: Bool, isError: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Kit.Control.cornerRadius, style: .continuous)
        return textFieldStyle(.plain)
            .font(Kit.Font.body)
            .foregroundStyle(Kit.Colour.bodyText)
            .padding(.vertical, Kit.Control.fieldVerticalPadding)
            .padding(.horizontal, Kit.Control.fieldHorizontalPadding)
            .background(Kit.Colour.paper, in: shape)
            .overlay {
                shape.strokeBorder(
                    isError ? Kit.Colour.error : isFocused ? Kit.Colour.accent : Kit.Colour.controlBoundary,
                    lineWidth: Kit.Control.fieldBorder)
            }
            .overlay {
                shape.inset(by: -(Kit.Control.focusRingOffset + Kit.Control.focusRing / 2))
                    .stroke(
                        isError ? Kit.Colour.error : Kit.Colour.focusRing, lineWidth: Kit.Control.focusRing
                    )
                    .opacity(isError || (isFocused && FocusVisibility.shared.isVisible) ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .animation(Kit.Motion.hover, value: isFocused)
    }
}

// MARK: - Info cards

/// The kit's info cards: neutral (signer, steps, notices), warn (amber) and error (red).
enum CardKind {
    case ok
    case warn
    case error

    var fill: Color {
        switch self {
        case .ok: Kit.Colour.infoFill
        case .warn: Kit.Colour.warnFill
        case .error: Kit.Colour.errorFill
        }
    }

    var icon: Color {
        switch self {
        case .ok: Kit.Colour.good
        case .warn: Kit.Colour.warning
        case .error: Kit.Colour.error
        }
    }

    var text: Color {
        switch self {
        case .warn: Kit.Colour.warnText
        case .ok, .error: Kit.Colour.bodyText
        }
    }

    var title: Color {
        switch self {
        case .warn: Kit.Colour.warnTitle
        case .ok, .error: Kit.Colour.bodyText
        }
    }
}

// MARK: - Progress capsule

/// The primary capsule as the progress (Progress board): moss fills it left to right over
/// moss at 22%, and the label reads "Installing… 62%" with rolling, monospaced digits. The
/// label is drawn twice and clipped by the fill, body text over the unfilled part and
/// white over the moss, so every glyph keeps its contrast wherever the edge passes.
/// Reduce Motion: the fill and the digits jump to each value.
struct ProgressCapsule: View {
    /// Held under `Kit.Motion.progressCeiling` by the caller until done.
    let fraction: Double
    var size: NidusButtonStyle.Size = .regular
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = Capsule()
        let clamped = min(max(fraction, 0), 1)
        let percent = Int((clamped * 100).rounded())
        label(colour: Kit.Colour.bodyText, percent: percent)
            .padding(.horizontal, Kit.Button.padding)
            .frame(minWidth: size == .hero ? Kit.Button.heroWidth : nil, minHeight: height)
            .background { shape.fill(Kit.Colour.accent.opacity(Kit.Motion.progressTrackOpacity)) }
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    let width = geometry.size.width * clamped
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Kit.Colour.accent).frame(width: width)
                        label(colour: Kit.Colour.onAccent, percent: percent)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .mask(alignment: .leading) { Rectangle().frame(width: width) }
                    }
                }
            }
            .clipShape(shape)
            .animation(reduceMotion ? nil : Kit.Motion.progress, value: clamped)
            .accessibilityElement()
            .accessibilityLabel("Installing")
            .accessibilityValue("\(percent) percent")
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var height: CGFloat { size == .hero ? Kit.Button.heroHeight : Kit.Button.height }

    private func label(colour: Color, percent: Int) -> some View {
        Text("Installing\u{2026} \(percent)%")
            .font(size == .hero ? Kit.Font.heroPrimaryButton : Kit.Font.primaryButton)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(percent)))
            .animation(reduceMotion ? nil : Kit.Motion.numbers, value: percent)
            .foregroundStyle(colour)
            .singleLineLabel()
    }
}

/// A button label that blur-swaps when its text changes, in a button that stays the same
/// view (Not now, Cancel, Show in Finder). `fills` centres it in a fixed-width capsule.
struct SwapLabel: View {
    let title: String
    var fills = false

    var body: some View {
        StatusSwap(key: title) { Text(title).frame(maxWidth: fills ? .infinity : nil) }
    }
}
