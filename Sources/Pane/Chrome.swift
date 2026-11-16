import AppKit
import PaneCore
import SwiftUI

/// The title bar (Layout 2): the system's traffic lights, the device name over its model and
/// Android version, left-aligned, then one round More button.
struct TitleBar: View {
    let model: PaneModel

    var body: some View {
        HStack(spacing: Theme.Window.titleGap) {
            VStack(alignment: .leading, spacing: Theme.Window.titleLineSpacing) {
                Text(model.title)
                    .font(Theme.Typeface.windowTitle)
                    .foregroundStyle(Color(nsColor: Theme.Palette.text))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.meta)
                    .font(Theme.Typeface.meta)
                    .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            MoreButton(model: model)
        }
        .padding(.leading, model.titleLeadingInset)
        .padding(.trailing, Theme.Window.titleRowTrailingPadding)
    }
}

/// More: a round glass button with the menu of less frequent actions.
struct MoreButton: View {
    let model: PaneModel
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            showMenu()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Theme.Window.moreIconSize, weight: .regular))
                .foregroundStyle(Color(nsColor: Theme.Palette.icon))
                .frame(width: Theme.Window.moreButtonSize, height: Theme.Window.moreButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(in: Circle())
        .background(MenuAnchorView(anchor: anchor))
        .help("More")
        .accessibilityLabel("More")
    }

    private func showMenu() {
        let menu = NSMenu()
        let restart = NSMenuItem(title: "Restart Emulator", action: nil, keyEquivalent: "")
        if model.emulator != nil {
            let handler = MenuAction { model.restartEmulator() }
            restart.target = handler
            restart.action = #selector(MenuAction.run)
            restart.representedObject = handler
        }
        restart.isEnabled = model.emulator != nil && model.ownsEmulator
        menu.addItem(restart)
        guard let view = anchor.view else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY), in: view)
    }
}

/// The floating toolbar under the device: [Home, Screenshot, Record] and [Rotate], two glass
/// capsules that read as one toolbar. Back is an edge swipe on the screen, as on the phone.
struct DeviceToolbar: View {
    let model: PaneModel

    var body: some View {
        let live = model.status == .live
        GlassGroup(spacing: Theme.Toolbar.capsuleGap) {
            HStack(spacing: Theme.Toolbar.capsuleGap) {
                capsule {
                    ToolbarButton(symbol: "circle", label: "Home") { model.pressHome() }
                    ToolbarButton(symbol: "camera.viewfinder", label: "Save screenshot") { model.saveScreenshot() }
                    RecordButton(model: model)
                }
                capsule {
                    ToolbarButton(symbol: "rotate.right", label: "Rotate") { model.rotate() }
                }
            }
        }
        .disabled(!live)
    }

    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: Theme.Toolbar.buttonSpacing, content: content)
            .padding(.horizontal, Theme.Toolbar.capsulePadding)
            .frame(height: Theme.Toolbar.capsuleHeight)
            .glassSurface(in: Capsule())
    }
}

/// Record: starts and stops a recording; the tooltip shows how long it has run.
struct RecordButton: View {
    let model: PaneModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ToolbarButton(
                symbol: model.recordingStartedAt == nil ? "record.circle" : "record.circle.fill",
                label: label(at: context.date),
                tint: model.recordingStartedAt == nil ? nil : Color(nsColor: Theme.Palette.recording)
            ) { model.toggleRecording() }
        }
    }

    private func label(at date: Date) -> String {
        guard let start = model.recordingStartedAt else { return "Record screen" }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        let secondsPerMinute = 60
        return String(format: "Stop recording (%d:%02d)", seconds / secondsPerMinute, seconds % secondsPerMinute)
    }
}

/// A toolbar icon button: hover and press shades per the guide, dimmed in place when disabled.
struct ToolbarButton: View {
    let symbol: String
    let label: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Theme.Toolbar.iconSize, weight: .regular))
                .foregroundStyle(tint ?? Color(nsColor: Theme.Palette.icon))
                .frame(width: Theme.Toolbar.buttonWidth, height: Theme.Toolbar.buttonHeight)
        }
        .buttonStyle(ToolbarButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
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
