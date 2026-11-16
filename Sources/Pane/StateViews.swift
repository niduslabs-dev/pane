import AppKit
import PaneCore
import SwiftUI

/// No emulator running (canvas option A): the frame stays, and the dark screen offers Start for
/// the selected AVD. With two or more AVDs, "Choose another emulator" opens their menu (one of
/// Pane's menu panels) under the link.
struct NoEmulatorScreen: View {
    let model: PaneModel
    @State private var linkFrame = CGRect.zero

    var body: some View {
        if model.avds.isEmpty {
            noEmulatorsSetUp
        } else {
            startScreen
        }
    }

    /// No emulators at all (board 3): nothing to start, so the screen says so and offers the
    /// folder instead.
    private var noEmulatorsSetUp: some View {
        VStack(spacing: Theme.Screen.lineGap) {
            Text("No emulators set up.")
                .font(Theme.Typeface.screenTitle)
                .foregroundStyle(Color(nsColor: Theme.Palette.screenTitle))
            Text("Create one in Android Studio's Device Manager.")
                .font(Theme.Typeface.screenMeta)
                .foregroundStyle(Color(nsColor: Theme.Palette.screenMeta))
            Button("Show Emulators in Finder") { model.onCommand(.showEmulatorsInFinder) }
                .buttonStyle(ScreenSecondaryCapsuleStyle())
                .padding(.top, Theme.Screen.actionGap)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Screen.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.Palette.screenEmpty))
    }

    private var startScreen: some View {
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
                    model.onShowEmulators(CGPoint(x: linkFrame.midX, y: linkFrame.maxY + Theme.AvdMenu.gap))
                } label: {
                    Text("Choose another emulator")
                        .font(Theme.Typeface.link)
                        .foregroundStyle(Color(nsColor: Theme.Palette.screenLink))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { linkFrame = proxy.frame(in: .global) }
                            .onChange(of: proxy.frame(in: .global)) { _, frame in linkFrame = frame }
                    }
                )
                .padding(.top, Theme.Screen.linkGap)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Screen.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.Palette.screenEmpty))
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
            if isSlowStart {
                Button("Stop") { model.stopStarting() }
                    .buttonStyle(ScreenSecondaryCapsuleStyle())
                    .padding(.top, Theme.Screen.actionGap - Theme.Screen.progressGap)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Screen.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: Theme.Palette.screenEmpty))
        .animation(.easeOut(duration: Theme.StatusSwap.fadeDuration), value: isSlowStart)
    }

    /// A start that hasn't answered after 30 s: the line says so and Stop appears (board 4).
    private var isSlowStart: Bool { model.status == .starting && model.isSlowStart }

    private var statusText: String {
        switch model.status {
        case .starting: model.isSlowStart ? "Still starting. This can take a minute." : "Starting \(model.title)…"
        case .booting: "Booting Android…"
        default: model.reconnectAttempt > 0 ? "Reconnecting…" : "Connecting…"
        }
    }
}

/// Over the live screen while files are dragged over the window (an accent outline and what a
/// drop would do) and while a drop runs (the `blurSwap` status line: "Installing Splito…",
/// "Installed.", or what went wrong in a plain sentence, with adb's own reason behind Details).
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
                        if let detail = model.transferDetail, !model.isTransferring {
                            if model.showsTransferDetail {
                                Text(detail)
                                    .font(Theme.Typeface.statusDetail)
                                    .foregroundStyle(Color(nsColor: Theme.Palette.screenMeta))
                                    .multilineTextAlignment(.center)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, Theme.Drop.detailsGap - Theme.Screen.progressGap)
                                    .transition(.opacity)
                            } else {
                                Button("Details") { model.showTransferDetail() }
                                    .buttonStyle(.plain)
                                    .font(Theme.Typeface.link)
                                    .foregroundStyle(Color(nsColor: Theme.Palette.screenLink))
                                    .accessibilityHint("Shows the reason adb gave.")
                                    .padding(.top, Theme.Drop.detailsGap - Theme.Screen.progressGap)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Screen.horizontalPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: Theme.Drop.fadeDuration), value: hover != nil || status != nil)
        .animation(.easeOut(duration: Theme.Drop.fadeDuration), value: model.showsTransferDetail)
        // Only a failure that has Details takes clicks; every other state lets them through.
        .allowsHitTesting(model.transferDetail != nil && !model.isTransferring)
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
        SheetPresenter.confirm(
            on: window, message: "Restart \(model.title)?",
            detail: "Pane didn't start this emulator. Restarting it closes any apps running on it.",
            action: "Restart Emulator"
        ) { model.restartEmulator() }
    }
}

/// The secondary capsule on the always-dark screen: a raised ink surface with a hairline.
struct ScreenSecondaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.screenSecondary)
            .foregroundStyle(Color(nsColor: Theme.Palette.screenTitle))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Theme.Capsule.standardPadding)
            .frame(height: Theme.Capsule.height)
            .background(Capsule().fill(Color(nsColor: Theme.Palette.screenSecondary)))
            .overlay(
                Capsule().strokeBorder(
                    Color(nsColor: Theme.Palette.screenSecondaryEdge), lineWidth: Theme.Toolbar.hairline * 2)
            )
            .overlay(Capsule().fill(Color.white.opacity(configuration.isPressed ? Theme.Toolbar.pressedOpacity : 0)))
            .contentShape(Capsule())
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
