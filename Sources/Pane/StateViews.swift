import AppKit
import PaneCore
import SwiftUI

/// No emulator running (canvas option A): the frame stays, and the dark screen offers Start for
/// the selected AVD. With two or more AVDs, "Choose another emulator" opens their menu.
struct NoEmulatorScreen: View {
    let model: PaneModel
    @State private var menuOpen = false

    var body: some View {
        ZStack {
            if menuOpen {
                // A click anywhere else closes the menu, as a native menu does.
                Color.clear.contentShape(Rectangle()).onTapGesture { menuOpen = false }
            }
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
                if model.avds.count >= 2 {
                    Button {
                        model.reloadAVDs()
                        menuOpen.toggle()
                    } label: {
                        Text("Choose another emulator")
                            .font(Theme.Typeface.link)
                            .foregroundStyle(Color(nsColor: Theme.Palette.screenLink))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .padding(.top, Theme.Screen.linkGap)
                    .overlay(alignment: .top) {
                        if menuOpen {
                            // Below the link's top padding and the link itself, then 4 pt.
                            AvdMenu(model: model) { menuOpen = false }
                                .fixedSize()
                                .offset(y: Theme.Screen.linkGap + Theme.AvdMenu.linkHeight + Theme.AvdMenu.gap)
                        }
                    }
                    .zIndex(1)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Screen.horizontalPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.Palette.screenEmpty))
        .onExitCommand { menuOpen = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            menuOpen = false
        }
    }
}

/// The emulators menu (canvas EmptyMenu, the guide's Select menu): every AVD as name over
/// model and Android version, a Running tag on any with an emulator up, then Show emulators in
/// Finder. Choosing a running one attaches; any other is shown with Start ready.
struct AvdMenu: View {
    let model: PaneModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.AvdMenu.rowSpacing) {
            ForEach(model.avds) { avd in
                AvdMenuRow(avd: avd, isRunning: model.runningAVDNames.contains(avd.name)) {
                    model.choose(avd)
                    close()
                }
            }
            Rectangle()
                .fill(Color(nsColor: Theme.Palette.menuDivider))
                .frame(height: Theme.AvdMenu.dividerHeight)
                .padding(.horizontal, Theme.AvdMenu.rowPaddingH)
                .padding(.vertical, Theme.AvdMenu.dividerPaddingV)
            MenuRowButton(label: "Show emulators in Finder") {
                close()
                NSWorkspace.shared.open(PaneModel.avdHome)
            } content: { highlighted in
                Text("Show emulators in Finder")
                    .font(Theme.Typeface.menuRow)
                    .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenTitle))
            }
        }
        .padding(Theme.AvdMenu.inset)
        .frame(width: Theme.AvdMenu.width)
        .background(
            RoundedRectangle(cornerRadius: Theme.AvdMenu.radius, style: .continuous)
                .fill(Color(nsColor: Theme.Palette.menuSurface))
                .shadow(
                    color: .black.opacity(Theme.AvdMenu.shadowOpacity), radius: Theme.AvdMenu.shadowRadius,
                    y: Theme.AvdMenu.shadowY)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.AvdMenu.radius, style: .continuous)
                .strokeBorder(Color(nsColor: Theme.Palette.menuHairline), lineWidth: Theme.AvdMenu.hairline)
        )
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Emulators")
    }
}

private struct AvdMenuRow: View {
    let avd: AvdInfo
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        MenuRowButton(label: accessibilityText, action: action) { highlighted in
            HStack(spacing: Theme.AvdMenu.tagGap) {
                VStack(alignment: .leading, spacing: Theme.AvdMenu.lineSpacing) {
                    Text(avd.name)
                        .font(Theme.Typeface.menuRow)
                        .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenTitle))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(Theme.Typeface.menuDetail)
                            .foregroundStyle(
                                highlighted
                                    ? Color.white.opacity(Theme.AvdMenu.highlightedDetailOpacity)
                                    : Color(nsColor: Theme.Palette.screenMeta))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if isRunning {
                    Text("Running")
                        .font(Theme.Typeface.menuTag)
                        .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenMeta))
                        .padding(.horizontal, Theme.AvdMenu.tagPaddingH)
                        .padding(.vertical, Theme.AvdMenu.tagPaddingV)
                        .overlay(
                            Capsule().strokeBorder(
                                highlighted
                                    ? Color.white.opacity(Theme.AvdMenu.highlightedTagStrokeOpacity)
                                    : Color(nsColor: Theme.Palette.menuHairline),
                                lineWidth: Theme.AvdMenu.hairline))
                }
            }
        }
    }

    private var detail: String {
        [avd.profile.modelName, avd.profile.androidVersion].compactMap { $0 }.joined(separator: " · ")
    }

    /// "dev_android36, Pixel 8, Android 16, running".
    private var accessibilityText: String {
        ([avd.name, avd.profile.modelName, avd.profile.androidVersion].compactMap { $0 }
            + (isRunning ? ["running"] : []))
            .joined(separator: ", ")
    }
}

/// A menu row: the system selection colour under the pointer, white text on it.
private struct MenuRowButton<Content: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content(hovered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.AvdMenu.rowPaddingH)
                .padding(.vertical, Theme.AvdMenu.rowPaddingV)
                .background(
                    RoundedRectangle(cornerRadius: Theme.AvdMenu.rowRadius, style: .continuous)
                        .fill(hovered ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
    }
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
        default: model.reconnectAttempt > 0 ? "Reconnecting…" : "Connecting…"
        }
    }
}

/// Over the live screen while files are dragged over the window (an accent outline and what a
/// drop would do) and while a drop runs (the `blurSwap` status line: "Installing Splito…",
/// "Installed.", or adb's error). Never takes clicks.
struct DropOverlay: View {
    let model: PaneModel
    let cornerRadius: CGFloat

    var body: some View {
        let hover = model.dropHover
        let status = model.transferStatus
        ZStack {
            if hover != nil || status != nil {
                Color(nsColor: Theme.Palette.screenEmpty).opacity(Theme.Drop.scrimOpacity)
                if let hover {
                    Text(hover)
                        .font(Theme.Typeface.screenTitle)
                        .foregroundStyle(Color(nsColor: Theme.Palette.screenTitle))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color(nsColor: Theme.Palette.screenLink), lineWidth: Theme.Drop.outlineWidth)
                } else if let status {
                    VStack(spacing: Theme.Screen.progressGap) {
                        if model.isTransferring {
                            ProgressView()
                                .controlSize(.small)
                                .colorScheme(.dark)
                        }
                        StatusLine(text: status)
                            .font(Theme.Typeface.status)
                            .foregroundStyle(Color(nsColor: Theme.Palette.screenTitle))
                    }
                    .padding(.horizontal, Theme.Screen.horizontalPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: Theme.Drop.fadeDuration), value: hover != nil || status != nil)
        .allowsHitTesting(false)
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
