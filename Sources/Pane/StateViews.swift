import AppKit
import PaneCore
import SwiftUI

/// No emulator running (canvas option A): the frame stays, and the dark screen offers Start for
/// the selected AVD plus a menu of the others.
struct NoEmulatorScreen: View {
    let model: PaneModel

    var body: some View {
        VStack(spacing: Theme.Screen.lineGap) {
            Text("No emulator running.")
                .font(Theme.Typeface.screenTitle)
                .foregroundStyle(Color(nsColor: Theme.Palette.screenTitle))
            Text(model.selectedAVD?.summary ?? "No emulators set up.")
                .font(Theme.Typeface.screenMeta)
                .foregroundStyle(Color(nsColor: Theme.Palette.screenMeta))
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Start") { model.startSelectedEmulator() }
                .buttonStyle(CapsuleButtonStyle(horizontalPadding: Theme.Capsule.startPadding))
                .disabled(model.selectedAVD == nil)
                .padding(.top, Theme.Screen.actionGap)
            if let problem = model.startProblem {
                Text(problem)
                    .font(Theme.Typeface.screenMeta)
                    .foregroundStyle(Color(nsColor: Theme.Palette.screenMeta))
                    .padding(.top, Theme.Screen.linkGap)
            }
            if !model.avds.isEmpty {
                AvdMenuLink(model: model)
                    .padding(.top, Theme.Screen.linkGap)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Screen.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.Palette.screenEmpty))
    }
}

/// "Choose another emulator": a link that opens a menu of every AVD, the selected one ticked.
struct AvdMenuLink: View {
    let model: PaneModel
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            showMenu()
        } label: {
            Text("Choose another emulator")
                .font(Theme.Typeface.link)
                .foregroundStyle(Color(nsColor: Theme.Palette.screenLink))
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
        .accessibilityAddTraits(.isButton)
    }

    private func showMenu() {
        model.reloadAVDs()
        let menu = NSMenu()
        for avd in model.avds {
            let item = NSMenuItem(title: avd.summary, action: nil, keyEquivalent: "")
            item.state = avd.name == model.selectedAVD?.name ? .on : .off
            let handler = MenuAction { model.selectAVD(avd.name) }
            item.target = handler
            item.action = #selector(MenuAction.run)
            item.representedObject = handler
            menu.addItem(item)
        }
        guard let view = anchor.view else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY), in: view)
    }
}

/// Holds the AppKit view a menu pops up from.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = FlippedView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A menu item's closure; kept alive by the item's `representedObject`.
@MainActor
final class MenuAction: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func run() { action() }
}

/// Starting or booting: a spinner and a `blurSwap` status line on the dark screen.
struct ProgressScreen: View {
    let model: PaneModel

    var body: some View {
        VStack(spacing: Theme.Screen.progressGap) {
            ProgressView()
                .controlSize(.small)
                .colorScheme(.dark)
            StatusLine(text: statusText)
                .font(Theme.Typeface.status)
                .foregroundStyle(Color(nsColor: Theme.Palette.screenMeta))
        }
        .padding(.horizontal, Theme.Screen.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.Palette.screenEmpty))
    }

    private var statusText: String {
        switch model.status {
        case .starting: "Starting \(model.title)…"
        case .booting: "Booting Android…"
        default: "Connecting…"
        }
    }
}

/// A status line that swaps in place (`blurSwap`): the old text blurs and drifts up as the new
/// one sharpens in from below. Reduce Motion makes it a plain crossfade.
struct StatusLine: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Text(text)
                .lineLimit(1)
                .id(text)
                .transition(reduceMotion ? .opacity : .blurSwap)
        }
        .animation(
            reduceMotion
                ? .easeInOut(duration: Theme.StatusSwap.fadeDuration)
                : .spring(response: Theme.StatusSwap.springResponse, dampingFraction: Theme.StatusSwap.springDamping),
            value: text
        )
        .accessibilityElement(children: .combine)
    }
}

private struct BlurSwapModifier: ViewModifier {
    let blur: CGFloat
    let offsetY: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: blur).offset(y: offsetY).opacity(opacity)
    }
}

extension AnyTransition {
    static var blurSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurSwapModifier(blur: Theme.StatusSwap.blur, offsetY: Theme.StatusSwap.offsetY, opacity: 0),
                identity: BlurSwapModifier(blur: 0, offsetY: 0, opacity: 1)),
            removal: .modifier(
                active: BlurSwapModifier(blur: Theme.StatusSwap.blur, offsetY: -Theme.StatusSwap.offsetY, opacity: 0),
                identity: BlurSwapModifier(blur: 0, offsetY: 0, opacity: 1))
        )
    }
}

/// Can't connect (canvas error state): a card in the frame's place with Restart emulator.
/// Restarting an emulator Pane didn't start asks first.
struct ErrorCard: View {
    let model: PaneModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Theme.ErrorCard.gap) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: Theme.ErrorCard.glyphSize, weight: .light))
                .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                .accessibilityHidden(true)
            Text("Can't reach \(model.title).")
                .font(Theme.Typeface.cardTitle)
                .foregroundStyle(Color(nsColor: Theme.Palette.text))
            Text("Pane couldn't connect to it. Restarting the emulator usually fixes this.")
                .font(Theme.Typeface.cardBody)
                .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
            Button("Restart emulator") { restart() }
                .buttonStyle(CapsuleButtonStyle(horizontalPadding: Theme.Capsule.standardPadding))
                .padding(.top, Theme.ErrorCard.actionExtraGap)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.ErrorCard.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.ErrorCard.radius, style: .continuous)
                .fill(Color(nsColor: Theme.Palette.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.ErrorCard.radius, style: .continuous)
                .strokeBorder(
                    Color(nsColor: Theme.Palette.hairline),
                    lineWidth: contrast == .increased
                        ? Theme.ErrorCard.hairlineIncreasedContrast : Theme.ErrorCard.hairline)
        )
    }

    private func restart() {
        if model.ownsEmulator {
            model.restartEmulator()
            return
        }
        guard let window = model.screenView.window ?? NSApp.windows.first(where: { $0 is PaneWindow }) else { return }
        let alert = NSAlert()
        alert.messageText = "Restart \(model.title)?"
        alert.informativeText = "Pane didn't start this emulator. Restarting it closes any apps running on it."
        let restart = alert.addButton(withTitle: "Restart Emulator")
        restart.hasDestructiveAction = true
        restart.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { model.restartEmulator() }
        }
    }
}

/// The primary capsule (`actionPrimary`): moss, white semibold text, darker while pressed,
/// dimmed in place when disabled.
struct CapsuleButtonStyle: ButtonStyle {
    let horizontalPadding: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.capsule)
            .foregroundStyle(Color(nsColor: Theme.Palette.onAction))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, horizontalPadding)
            .frame(height: Theme.Capsule.height)
            .background(
                Capsule().fill(
                    Color(
                        nsColor: configuration.isPressed
                            ? Theme.Palette.actionPrimaryPressed : Theme.Palette.actionPrimary
                    ))
            )
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : Theme.Capsule.disabledOpacity)
    }
}
