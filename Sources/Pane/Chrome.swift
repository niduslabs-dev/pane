import AppKit
import PaneCore
import SwiftUI

/// The title bar, matching Device Hub's: the system's traffic lights, the device name over its
/// model and Android version, left-aligned, then a glass pill holding More (Device Hub's
/// full-screen button is left out).
struct TitleBar: View {
    let model: PaneModel

    var body: some View {
        // No spacing: the spacer only pushes the title left, and a gap before it would take
        // the name's room in a narrow window.
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Window.titleLineSpacing) {
                SwitcherButton(model: model)
                Text(model.meta)
                    .font(Theme.Typeface.meta)
                    .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, Theme.TitleButton.paddingH)
            .padding(.vertical, Theme.TitleButton.paddingV)
            .background(
                RoundedRectangle(cornerRadius: Theme.TitleButton.radius, style: .continuous)
                    .fill(
                        Color(nsColor: Theme.Palette.shade)
                            .opacity(
                                model.pointerOverTitle || model.menu?.anchor == .title
                                    ? Theme.TitleButton.hoverOpacity : 0))
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { model.switcherFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, frame in model.switcherFrame = frame }
                }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.onShowSwitcher() }
            .accessibilityIdentifier("window-title")
            Spacer(minLength: 0)
        }
        .padding(.leading, model.titleLeadingInset - Theme.TitleButton.paddingH)
        .padding(.trailing, Theme.Window.titleRowTrailingPadding)
    }
}

/// The device name in the title, as a button (board 13): under the pointer it gets a soft
/// shade and a chevron, and a click opens the emulator switcher under it. The title bar takes
/// real clicks and pointer moves before SwiftUI does, so the window reports the pointer
/// (`model.pointerOverTitle`) and routes a click on `model.switcherFrame` here; Accessibility
/// presses the button itself.
struct SwitcherButton: View {
    let model: PaneModel

    var body: some View {
        let isOpen = model.menu?.anchor == .title
        let showsChrome = model.pointerOverTitle || isOpen
        Button {
            model.onShowSwitcher()
        } label: {
            HStack(spacing: Theme.TitleButton.chevronGap) {
                Text(model.title)
                    .font(Theme.Typeface.titleRowName)
                    .foregroundStyle(Color(nsColor: Theme.Palette.text))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: Theme.TitleButton.chevronSize, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                    .opacity(showsChrome ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plainRow)
        .accessibilityLabel("\(model.title), switch emulator")
        .accessibilityHint("Shows the emulators.")
    }
}

/// The floating toolbar under the device, as in Device Hub: a glass capsule with Home,
/// Screenshot and Record, and a glass circle with Rotate. Back is an edge swipe on the screen,
/// as on the phone. Screenshot and Record are Device Hub's SF Symbols; its Home and Rotate glyphs
/// are private to Apple, so Pane draws its own (`PaneSymbol`).
struct DeviceToolbar: View {
    let model: PaneModel

    var body: some View {
        // While a tool is on, the pill that names it takes the toolbar's place.
        if let tool = model.tools.active, let state = model.tools.pill {
            ToolModePill(tools: model.tools, tool: tool, state: state)
        } else {
            toolbar
        }
    }

    private var toolbar: some View {
        let live = model.status == .live
        return GlassGroup(spacing: Theme.Toolbar.capsuleGap) {
            HStack(spacing: Theme.Toolbar.capsuleGap) {
                capsule {
                    ToolbarButton(symbol: PaneSymbol.home, label: "Home") { model.pressHome() }
                        .accessibilityIdentifier(identifier("toolbar-home", live: live))
                    ToolbarButton(symbol: .system("camera.viewfinder"), label: "Screenshot") { model.saveScreenshot() }
                        .accessibilityIdentifier(identifier("toolbar-screenshot", live: live))
                    RecordButton(model: model)
                        .accessibilityIdentifier(identifier("toolbar-record", live: live))
                }
                ToolbarButton(
                    symbol: PaneSymbol.rotateLeft, label: "Rotate left", width: Theme.Toolbar.circleSize,
                    height: Theme.Toolbar.circleSize
                ) { model.rotate() }
                .accessibilityIdentifier(identifier("toolbar-rotate", live: live))
                .glassSurface(in: Circle())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("toolbar-circle")
            }
        }
        .disabled(!live)
    }

    /// A button's identifier for the measured check, with "-disabled" while there is nothing
    /// to act on: dimmed icons are exempt from the contrast minimum the enabled ones meet.
    private func identifier(_ name: String, live: Bool) -> String {
        live ? name : name + "-disabled"
    }

    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: Theme.Toolbar.buttonSpacing, content: content)
            .padding(.horizontal, Theme.Toolbar.capsulePadding)
            .frame(height: Theme.Toolbar.capsuleHeight)
            .glassSurface(in: Capsule())
            .contentShape(.accessibility, Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("toolbar-capsule")
    }
}

/// Record: starts and stops a recording; the tooltip shows how long it has run.
struct RecordButton: View {
    let model: PaneModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ToolbarButton(
                symbol: .system(model.recordingStartedAt == nil ? "record.circle" : "record.circle.fill"),
                label: label(at: context.date),
                tint: model.recordingStartedAt == nil ? nil : Color(nsColor: Theme.Palette.recording)
            ) { model.toggleRecording() }
        }
    }

    private func label(at date: Date) -> String {
        guard let start = model.recordingStartedAt else { return "Record" }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        let secondsPerMinute = 60
        return String(format: "Stop recording (%d:%02d)", seconds / secondsPerMinute, seconds % secondsPerMinute)
    }
}

/// A toolbar icon button in the primary text colour (as Device Hub's are): hover and press
/// shades per the guide, dimmed in place when disabled.
struct ToolbarButton: View {
    let symbol: PaneSymbol
    let label: String
    var tint: Color?
    var width = Theme.Toolbar.buttonWidth
    var height = Theme.Toolbar.buttonHeight
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            symbol.image
                .font(.system(size: Theme.Toolbar.iconSize, weight: .regular))
                .foregroundStyle(tint ?? Color(nsColor: Theme.Palette.text))
                .frame(width: width, height: height)
        }
        .buttonStyle(ToolbarButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shade =
            configuration.isPressed ? Theme.Toolbar.pressedOpacity : (hovered ? Theme.Toolbar.hoverOpacity : 0)
        configuration.label
            .background(Capsule().fill(Color(nsColor: Theme.Palette.shade).opacity(isEnabled ? shade : 0)))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : Theme.Toolbar.disabledOpacity)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: Theme.Toolbar.hoverDuration), value: hovered)
    }
}

extension View {
    /// Liquid Glass on macOS 26 and later (interactive), the ink-glass material before it, and a
    /// solid raised fill with a hairline when transparency is reduced.
    func glassSurface(in shape: some Shape) -> some View {
        modifier(GlassSurface(shape: shape))
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Color(nsColor: Theme.Palette.pill)))
                .overlay(shape.stroke(Color(nsColor: Theme.Palette.hairline), lineWidth: Theme.Toolbar.hairline))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color(nsColor: Theme.Palette.hairline), lineWidth: Theme.Toolbar.hairline))
        }
    }
}

/// Groups glass shapes so neighbouring capsules read as one toolbar (macOS 26 and later).
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// A toolbar symbol: an SF Symbol, or one of Pane's own custom symbols. Pane's are drawn by
/// `scripts/make-symbols.py` from measurements of Device Hub's toolbar (Apple's are private) and
/// compiled into the app's asset catalog by `scripts/build-app.sh`. A bare `swift build` has no
/// catalog, so each falls back to the nearest SF Symbol.
enum PaneSymbol: Equatable {
    case system(String)
    case custom(String, fallback: String)

    /// Nine rounded app-icon squares, like Device Hub's Home.
    static let home = PaneSymbol.custom("pane.home", fallback: "square.grid.3x3.fill")
    /// A device with two arrows turning counter-clockwise, like Device Hub's Rotate Left.
    static let rotateLeft = PaneSymbol.custom("pane.rotate.left", fallback: "rectangle.portrait.rotate")

    var image: Image {
        switch self {
        case .system(let name):
            Image(systemName: name)
        case .custom(let name, let fallback):
            NSImage(symbolName: name, bundle: .main, variableValue: 0) != nil
                ? Image(name, bundle: .main) : Image(systemName: fallback)
        }
    }
}
