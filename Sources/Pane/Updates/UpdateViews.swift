import AppKit
import SwiftUI
import os

/// Pane's icon on the update surfaces: the app's own icon, read from the bundle, so there is
/// no second copy of the artwork.
struct PaneIcon: View {
    let size: CGFloat

    var body: some View {
        // The icon file follows macOS's grid: its tile is 824 of 1024 points, with room for the
        // shadow around it. The boards draw the tile at the full size, so scale it up to fill.
        Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
            .frame(width: size, height: size)
            .scaleEffect(Theme.AppIcon.tileScale)
            .accessibilityHidden(true)
    }
}

/// The update popup (canvas board 15): "Pane 1.1 is ready" after a silent download, with the
/// version step and size, up to three release-note lines, Release notes, Later and Restart to
/// Update. With automatic installs off it asks first ("Pane 1.1 is available", Download), then
/// shows the download with a bar while Restart to Update waits, disabled in place.
struct UpdatePopupView: View {
    let model: UpdateModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PanelCard {
            HStack(spacing: Kit.Header.spacing) {
                PaneIcon(size: Kit.Header.appIcon)
                (Text("Pane").font(Kit.Font.captionStrong).foregroundStyle(Kit.Colour.bodyText)
                    + Text(" \u{00B7} Update").foregroundStyle(Kit.Colour.secondaryText))
                    .lineLimit(1)
            }
            .font(Kit.Font.caption)
            .accessibilityElement(children: .combine)
            HStack(spacing: Kit.Icon.titleSpacing) {
                PaneIcon(size: Kit.Icon.size)
                VStack(alignment: .leading, spacing: Kit.Update.titleSpacing) {
                    StatusSwap(key: model.popupTitle) {
                        Text(model.popupTitle).font(Kit.Font.title).tracking(Kit.Font.titleTracking)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VersionStep(model: model).font(Kit.Font.subtitle)
                }
            }
            if let notes = model.update?.notes, !notes.isEmpty {
                NotesCard(lines: notes)
            }
            if let fraction = model.barFraction(ceiling: Kit.Motion.progressCeiling) {
                DownloadBar(fraction: fraction)
            }
            ButtonRow {
                if model.update?.releaseNotesURL != nil {
                    Button("Release notes") { model.openReleaseNotes() }.buttonStyle(.nidusLink())
                }
            } trailing: {
                Button("Later") { model.perform(.later) }.buttonStyle(.nidusSecondary)
                    .keyboardShortcut(.cancelAction)
                if case .available = model.phase {
                    Button("Download") { model.perform(.download) }.buttonStyle(.nidusPrimary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Restart to Update") { model.perform(.restart) }.buttonStyle(.nidusPrimary)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.isReady)
                }
            }
            .padding(.top, Kit.Panel.buttonRowTopPadding)
        }
        .animation(reduceMotion ? nil : Kit.Motion.progress, value: model.isReady)
    }
}

/// "1.0 → 1.1 · 6 MB, downloaded", the new version in the body colour.
private struct VersionStep: View {
    let model: UpdateModel

    var body: some View {
        let new = model.update?.version ?? ""
        let size = model.sizeDetail.map { " \u{00B7} \($0)" } ?? ""
        (Text("\(model.currentVersion) \u{2192} ").foregroundStyle(Kit.Colour.secondaryText)
            + Text(new).fontWeight(.semibold).foregroundStyle(Kit.Colour.bodyText)
            + Text(size).foregroundStyle(Kit.Colour.secondaryText))
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel("\(model.currentVersion) to \(new)\(size)")
    }
}

/// The release-note lines as a bulleted list on the info fill.
private struct NotesCard: View {
    let lines: [String]

    var body: some View {
        InfoCard(spacing: Kit.Update.noteSpacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: Kit.Update.bulletGap) {
                    Text("\u{2022}").accessibilityHidden(true)
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(Kit.Colour.bodyText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lines.joined(separator: ". "))
    }
}

/// The download's bar (the kit's ProgressSteps bar): moss on a faint track. The caller holds
/// it under the ceiling until the update is verified.
private struct DownloadBar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = Capsule()
        GeometryReader { geometry in
            shape.fill(Kit.Colour.accent)
                .frame(width: geometry.size.width * min(max(fraction, 0), 1))
        }
        .frame(height: Kit.Progress.height)
        .background(Kit.Colour.track, in: shape)
        .clipShape(shape)
        .animation(reduceMotion ? nil : Kit.Motion.progress, value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Download")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The banner at the top of Settings while an update waits for a restart: "Pane 1.1 is ready",
/// "Installs next time Pane quits, or now." and Restart to Update.
struct UpdateBanner: View {
    let model: UpdateModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.Radius.card, style: .continuous)
        HStack(spacing: Kit.Update.bannerSpacing) {
            PaneIcon(size: Kit.Update.bannerIcon)
            VStack(alignment: .leading, spacing: 0) {
                Text(model.popupTitle).font(Kit.Font.calloutTitle).foregroundStyle(Kit.Colour.bodyText)
                Text("Installs next time Pane quits, or now.").font(Kit.Font.caption)
                    .foregroundStyle(Kit.Colour.secondaryText)
            }
            Spacer(minLength: 0)
            Button("Restart to Update") { model.perform(.restart) }
                .buttonStyle(NidusButtonStyle(kind: .primary, size: .small))
        }
        .padding(.horizontal, Kit.Row.horizontalPadding)
        .padding(.vertical, Kit.Row.verticalPadding)
        .background(Kit.Colour.accent.opacity(Kit.Update.bannerFillOpacity), in: shape)
        .overlay { Hairline(shape: shape) }
        .accessibilityElement(children: .contain)
    }
}

/// Pane's `UpdateSurface`: the top-right notification panel. It never takes focus and never
/// activates Pane. It shows an update that is ready or waits for Download, and follows a
/// download started from its own Download button. Everything else the model reports ("up to
/// date", a failed check, a download after Check for Updates) shows in Settings' Version row,
/// which reads the model itself.
@MainActor
final class UpdatePopupController: UpdateSurface {
    private let model: UpdateModel
    private let popup = PopupPanel()
    private var hosting: NSHostingView<AnyView>?
    private var slide: FrameSlide?
    /// Shown, or waiting for its first size to slide in.
    private(set) var isPresented = false
    private var entrancePending = false

    init(model: UpdateModel) {
        self.model = model
        popup.title = "Pane Update"
        popup.onCancel = { [weak model] in model?.perform(.later) }
        DisplayOptions.applyDebugContrast(to: popup)
    }

    /// Whether the popup shows `presentation`. A download is followed only when the popup was
    /// already up: one started by Check for Updates shows in Settings until it is ready.
    nonisolated static func shows(_ presentation: UpdatePresentation?, whilePresented: Bool) -> Bool {
        switch presentation {
        case .available, .ready: true
        case .downloading: whilePresented
        case .upToDate, .error, nil: false
        }
    }

    func updatePresentationChanged(_ presentation: UpdatePresentation?) {
        let shows = Self.shows(presentation, whilePresented: isPresented)
        if shows, !isPresented {
            present()
        } else if !shows, isPresented {
            isPresented = false
            entrancePending = false
            slide?.stop()
            slide = nil
            popup.orderOut(nil)
            hosting?.rootView = AnyView(EmptyView())
        }
    }

    /// Hosts the popup view; the entrance waits for SwiftUI's first size (`fittingSize` is
    /// zero until the content has laid out).
    private func present() {
        isPresented = true
        entrancePending = true
        let root = AnyView(
            UpdatePopupView(model: model)
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: { $0.size }) { [weak self] size in self?.resize(to: size) }
                .displayOptions())
        if let hosting {
            hosting.rootView = root
        } else {
            let hosting = FirstClickHostingView(rootView: root)
            hosting.sizingOptions = []
            popup.contentView = hosting
            self.hosting = hosting
        }
        if let hosting { resize(to: hosting.fittingSize) }
    }

    private func resize(to size: CGSize) {
        guard isPresented, let frame = PopupPanel.frame(for: size) else { return }
        if entrancePending {
            entrancePending = false
            beginEntrance(at: frame)
        } else if let slide, slide.isRunning {
            slide.target = frame
        } else {
            popup.setFrame(frame, display: true)
        }
        popup.invalidateShadow()
    }

    /// The spring slide from the right edge, or a fade with Reduce Motion.
    private func beginEntrance(at frame: NSRect) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            popup.setFrame(frame, display: true)
            popup.alphaValue = 0
            WindowPresence.presentWithoutFocus(popup)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Kit.Motion.fadeDuration
                popup.animator().alphaValue = 1
            }
        } else {
            popup.alphaValue = 1
            let slide = FrameSlide(window: popup, target: frame, offset: frame.width + Kit.Popup.screenInset)
            slide.start()
            WindowPresence.presentWithoutFocus(popup)
            self.slide = slide
        }
        UpdateModel.log.info("Update popup shown")
    }
}
