import AppKit
import PaneCore
import SwiftUI

/// Settings (canvas board 14), the studio's SettingsWindow: a "Settings" page title inside the
/// content, then groups of SettingsRows in r14 cards. One setting per row, switches only, one
/// caption line at most, longer text behind an ⓘ, no footer notes. Changes apply at once. The
/// Pane group is last and holds the version and updates (board 15); while an update waits for
/// a restart its banner leads the page.
struct SettingsView: View {
    @Bindable var settings: PaneSettings
    let takeover: TakeoverSwitch
    @Bindable var updates: UpdateModel
    /// Opens the folder picker for Save to.
    let chooseFolder: () -> Void
    /// The app's version, for the last group.
    var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    @Environment(\.titleBarHeight) private var titleBarHeight
    @Environment(\.settingsSizing) private var sizing
    @Environment(\.settingsScrollTarget) private var scrollTarget
    @Environment(\.settingsInfo) private var info
    @State private var scrollPosition = ScrollPosition(edge: .top)

    /// The scroll view fills the window below the title bar, and the window controller sizes
    /// the window to the page (`SettingsSizing`), so the page's own insets are the only space
    /// around it. Rows scrolled up under the title bar fade out before they reach the traffic
    /// lights.
    var body: some View {
        ScrollView {
            page.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                sizing?.contentHeightChanged(titleBarHeight + $0)
            }
            .overlayPreferenceValue(InfoAnchorKey.self) { anchor in
                if let anchor, let info, info.isShown {
                    GeometryReader { proxy in
                        // A click anywhere else closes it and is swallowed, as with a popover.
                        Color.clear.contentShape(Rectangle()).onTapGesture { info.isShown = false }
                        TakeoverInfoPopover()
                            .offset(
                                x: proxy[anchor].minX + Theme.InfoPopover.leading,
                                y: proxy[anchor].maxY + Theme.InfoPopover.gap)
                    }
                }
            }
        }
        .scrollPosition($scrollPosition)
        .onChange(of: scrollTarget, initial: true) {
            if scrollTarget == .paneGroup { scrollPosition.scrollTo(edge: .bottom) }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollIndicators(.automatic)
        .mask { scrollEdgeMask }
        .frame(width: Kit.Settings.width)
        .frame(maxHeight: .infinity)
        .padding(.top, titleBarHeight)
        .background(SurfaceBackground(kind: .settings).ignoresSafeArea())
        .foregroundStyle(Kit.Colour.bodyText)
        .environment(\.cardScale, .window)
    }

    /// The scroll-edge effect: over its first `scrollEdgeFade` points rows fade out instead of
    /// being cut off. A mask, not a band painted on top, so what shows through is the window's
    /// own backdrop (`titleBarMatchesContent`). At rest the fade ends at the page title.
    private var scrollEdgeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Kit.Settings.scrollEdgeFade)
            Color.black
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(Kit.Font.pageTitle)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Kit.Settings.titleToGroups)
            VStack(alignment: .leading, spacing: Kit.Settings.groupSpacing) {
                if updates.isReady { UpdateBanner(model: updates) }
                group("Emulators", anchorsInfo: true) {
                    takeoverRow
                    SwitchRow(title: "Start emulators without sound", isOn: $settings.startsWithoutSound)
                }
                group("Capture") {
                    SettingsRow("Save to") {
                        NidusSelect(
                            label: "Save to", selection: SaveChoice(settings.captureDestination),
                            options: SaveChoice.options(lastFolder: settings.captureFolderPath)
                        ) { choice in
                            if let destination = choice.destination {
                                settings.captureDestination = destination
                            } else {
                                chooseFolder()
                            }
                        }
                        .accessibilityIdentifier("settings-save-to")
                    }
                    SwitchRow(
                        title: "Include device frame", caption: "Adds Pane's frame to screenshots.",
                        isOn: $settings.includesDeviceFrame)
                }
                group("Input") {
                    SwitchRow(
                        title: "Share clipboard", caption: "Copied text moves both ways while Pane is in front.",
                        isOn: $settings.sharesClipboard)
                }
                group("Pane") {
                    VersionRow(updates: updates, version: version)
                    SwitchRow(
                        title: "Install updates automatically",
                        caption: "Downloads in the background and installs when Pane quits.",
                        isOn: $updates.installsAutomatically)
                }
            }
        }
        .padding(.top, Kit.Settings.titleBarGap)
        .padding([.horizontal, .bottom], Kit.Settings.inset)
        .frame(width: Kit.Settings.width, alignment: .leading)
    }

    /// "Show all emulators in Pane" with its ⓘ. While the script runs the switch dims and the
    /// caption says "Changing…"; a failure puts the switch back and says so in the error colour.
    private var takeoverRow: some View {
        HStack(spacing: Kit.Row.labelControlGap) {
            VStack(alignment: .leading, spacing: Kit.Row.captionGap) {
                HStack(spacing: Kit.Row.titleInfoGap) {
                    Text("Show all emulators in Pane").font(Kit.Font.body)
                    Button {
                        info?.isShown.toggle()
                    } label: {
                        Image(systemName: "info.circle").font(Kit.Font.chevron)
                            .foregroundStyle(Kit.Colour.secondaryText)
                    }
                    .buttonStyle(.nidusPlain)
                    .accessibilityLabel("More info")
                }
                StatusSwap(key: takeover.caption) {
                    Text(takeover.caption).font(Kit.Font.caption)
                        .foregroundStyle(takeover.state == .failed ? Kit.Colour.error : Kit.Colour.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // The label is the text on the left, so the ⓘ stays its own button; the switch
            // carries the name for VoiceOver.
            Toggle("Show all emulators in Pane", isOn: Binding(get: { takeover.isOn }, set: { takeover.set($0) }))
                .toggleStyle(.nidusSwitch)
                .labelsHidden()
                .disabled(takeover.state == .changing)
                .accessibilityLabel("Show all emulators in Pane")
                .accessibilityIdentifier("settings-takeover-switch")
                .accessibilityHint(takeover.caption)
        }
        .padding(.horizontal, Kit.Row.horizontalPadding)
        .padding(.vertical, Kit.Row.verticalPadding)
    }

    /// A group label (11 medium, inset 4) 6 above its card.
    /// `anchorsInfo`: the ⓘ popover opens under this group's card.
    private func group<Content: View>(_ label: String, anchorsInfo: Bool = false, @ViewBuilder rows: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: Kit.Settings.labelToCard) {
            Text(label).font(Kit.Font.groupLabel).foregroundStyle(Kit.Colour.secondaryText)
                .padding(.leading, Kit.Settings.labelInset)
                .accessibilityAddTraits(.isHeader)
            RowCard(content: rows)
                .anchorPreference(key: InfoAnchorKey.self, value: .bounds) { anchorsInfo ? $0 : nil }
        }
    }
}

/// The Emulators card's bounds, where the ⓘ popover hangs from.
private struct InfoAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Whether Show all emulators in Pane's ⓘ popover is open. The window owns it, so Esc closes
/// the popover before the window.
@MainActor
@Observable
final class SettingsInfo {
    var isShown = false
}

/// The ⓘ popover (board 14): 280 wide, 12 pt text, `surfaceMenu` with a hairline and a
/// shadow, 6 pt under the card so the row's own caption stays readable.
private struct TakeoverInfoPopover: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.InfoPopover.radius, style: .continuous)
        Text(
            "Pane adds a small launcher to your shell setup, so an emulator started anywhere opens in Pane without its own window. It applies to new terminal windows. Turning this off removes it."
        )
        .font(Kit.Font.small)
        .lineSpacing(Theme.InfoPopover.lineSpacing)
        .foregroundStyle(Kit.Colour.bodyText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.InfoPopover.paddingH)
        .padding(.vertical, Theme.InfoPopover.paddingV)
        .frame(width: Theme.InfoPopover.width, alignment: .leading)
        .background(
            MenuSurface(shape: shape)
                .shadow(
                    color: .black.opacity(Theme.Menu.shadowOpacity), radius: Theme.Menu.shadowRadius,
                    y: Theme.Menu.shadowY)
        )
        .overlay(Hairline(shape: shape))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// "Version 1.0" with Check for Updates. The caption carries the check's result in place:
/// "Checking…" with a spinner, "Up to date · checked just now", "Downloading 1.1…", or
/// "Couldn't check. Try again later." in the error colour.
private struct VersionRow: View {
    let updates: UpdateModel
    let version: String

    var body: some View {
        // The caption reads the clock when the page draws; Settings is redrawn on every open
        // and on each update event, which is often enough for "today".
        let caption = updates.versionCaption()
        HStack(spacing: Kit.Row.labelControlGap) {
            VStack(alignment: .leading, spacing: Kit.Row.captionGap) {
                Text(version.isEmpty ? "Pane" : "Version \(version)").font(Kit.Font.body)
                StatusSwap(key: caption) {
                    HStack(spacing: Kit.Row.titleInfoGap) {
                        if updates.isChecking {
                            ProgressView().controlSize(.mini).accessibilityHidden(true)
                        }
                        Text(caption).font(Kit.Font.caption).monospacedDigit()
                            .foregroundStyle(updates.hasFailed ? Kit.Colour.error : Kit.Colour.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button("Check for Updates") { updates.perform(.check) }.buttonStyle(.nidusSmall)
                .disabled(!updates.canCheck)
                .accessibilityIdentifier("settings-check-updates")
        }
        .padding(.horizontal, Kit.Row.horizontalPadding)
        .padding(.vertical, Kit.Row.verticalPadding)
    }
}

/// Save to's choices: macOS's own screenshot folder, the Desktop, the folder chosen last, and
/// Choose folder…, which opens the picker instead of becoming the selection.
enum SaveChoice: Hashable {
    case destination(CaptureDestination)
    case choose

    init(_ destination: CaptureDestination) { self = .destination(destination) }

    var destination: CaptureDestination? {
        if case .destination(let destination) = self { return destination }
        return nil
    }

    @MainActor
    static func options(
        lastFolder: String?, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SelectOption<SaveChoice>] {
        var options = [
            SelectOption(
                value: SaveChoice(.system), label: "Same as macOS screenshots",
                accessibilityLabel: "Same as macOS screenshots"),
            SelectOption(value: SaveChoice(.desktop), label: "Desktop", accessibilityLabel: "Desktop"),
        ]
        if let lastFolder {
            let url = URL(filePath: lastFolder, directoryHint: .isDirectory)
            options.append(
                SelectOption(
                    value: SaveChoice(.folder(lastFolder)), label: FolderDisplay.path(url, home: home),
                    accessibilityLabel: "\(url.lastPathComponent), \(FolderDisplay.plainPath(url))",
                    icon: FolderDisplay.icon(for: url), monospaced: true, keywords: [url.lastPathComponent]))
        }
        options.append(
            SelectOption(value: .choose, label: "Choose folder\u{2026}", accessibilityLabel: "Choose folder"))
        return options
    }
}

extension EnvironmentValues {
    /// Where the Settings page reports its height (`SettingsSizing`).
    @Entry var settingsSizing: SettingsSizing?
    /// Where the page scrolls to when it opens.
    @Entry var settingsScrollTarget = SettingsScrollTarget.top
    /// The ⓘ popover's open state.
    @Entry var settingsInfo: SettingsInfo?
}

enum SettingsScrollTarget: Equatable {
    case top
    /// The last group, for Check for Updates… in the app menu.
    case paneGroup
}

/// Takes the Settings window's full content height (title bar, then the page with its gap and
/// insets) to the window controller, which sizes the window to it up to
/// `Kit.Settings.maxHeight`. A class, not a closure, in the environment: SwiftUI compares it by
/// identity, so it doesn't invalidate the page on every update.
@MainActor
final class SettingsSizing {
    let contentHeightChanged: (CGFloat) -> Void

    init(contentHeightChanged: @escaping (CGFloat) -> Void) { self.contentHeightChanged = contentHeightChanged }
}

/// The Settings window: closable only. Esc closes the ⓘ popover if it is open, else the window.
final class SettingsWindow: NSWindow {
    var info: SettingsInfo?

    override func cancelOperation(_ sender: Any?) {
        if let info, info.isShown {
            info.isShown = false
        } else {
            performClose(sender)
        }
    }
}

/// Owns the Settings window. It is as tall as the page, up to `Kit.Settings.maxHeight`, past
/// which the page scrolls, and opens centred on the active screen every time.
///
/// SwiftUI reports the page's height and this controller sets the frame, rather than the
/// hosting controller's preferred size: that path counts the title bar's safe area on top of a
/// page that already leaves room for it, which leaves a gap under the last card.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hosting: NSHostingView<AnyView>?
    private let settings: PaneSettings
    private let takeover: TakeoverSwitch
    private let updates: UpdateModel
    private let info = SettingsInfo()
    /// The content height last reported (title bar and page), 0 until the page has laid out.
    private var contentHeight: CGFloat = 0
    /// Set by `show()` until the window has its size: it's centred and brought forward then.
    private var presentPending = false
    private lazy var sizing = SettingsSizing { [weak self] height in self?.contentHeightChanged(height) }

    init(settings: PaneSettings, takeover: TakeoverSwitch, updates: UpdateModel) {
        self.settings = settings
        self.takeover = takeover
        self.updates = updates
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Opens Settings, or brings it forward. `target` is where the page scrolls to.
    func show(scrollTo target: SettingsScrollTarget = .top) {
        takeover.refresh()
        let window = self.window ?? makeWindow()
        let titleBarHeight = window.frame.height - window.contentLayoutRect.height
        hosting?.rootView = AnyView(
            SettingsView(settings: settings, takeover: takeover, updates: updates) { [weak self] in
                self?.chooseFolder()
            }
            .environment(\.titleBarHeight, titleBarHeight)
            .environment(\.settingsSizing, sizing)
            .environment(\.settingsScrollTarget, target)
            .environment(\.settingsInfo, info)
            .displayOptions())
        presentPending = true
        hosting?.layoutSubtreeIfNeeded()
        // A reopen with the page unchanged reports no new height: use the last one.
        if contentHeight > 0 { resize(window, to: contentHeight) }
    }

    /// A result nobody is looking at any more ("Up to date", a failed check) is cleared.
    func windowWillClose(_ notification: Notification) {
        updates.perform(.dismiss)
        info.isShown = false
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: Kit.Settings.width, height: Kit.Settings.maxHeight),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.paintsSurfaceUnderTitleBar()
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // No saved frame or restored state: Settings always opens centred (`centre`).
        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.delegate = self
        window.info = info
        DisplayOptions.applyDebugContrast(to: window)
        let hosting = NSHostingView(rootView: AnyView(EmptyView()))
        hosting.sizingOptions = []
        // The page places itself below the title bar (`titleBarHeight`), so SwiftUI gets no
        // safe area of its own to inset by.
        hosting.safeAreaRegions = []
        window.contentView = hosting
        self.window = window
        self.hosting = hosting
        return window
    }

    private func contentHeightChanged(_ height: CGFloat) {
        guard height > 0, let window else { return }
        contentHeight = height
        resize(window, to: height)
    }

    /// Sizes the window to the page, up to the maximum, then centres it: the size has to be
    /// known first, since a later resize keeps the old origin and would leave the window off
    /// centre. The first size after `show()` also brings it forward.
    private func resize(_ window: NSWindow, to height: CGFloat) {
        let size = NSSize(width: Kit.Settings.width, height: min(height, Kit.Settings.maxHeight))
        guard presentPending || window.frame.size != size else { return }
        window.setFrame(NSRect(origin: window.frame.origin, size: size), display: !presentPending)
        Self.centre(window)
        if presentPending {
            presentPending = false
            WindowPresence.present(window)
        }
    }

    /// Centres `window` in the visible frame of the active screen: the screen with the key
    /// window, else the one whose menu bar is active. `NSWindow.center()` sits a third from
    /// the top and only on the window's own screen.
    static func centre(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }

    /// Save to ▸ Choose folder…: a folder picker on the Settings window.
    private func chooseFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Screenshots and recordings are saved here."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.settings.captureDestination = .folder(url.path(percentEncoded: false))
        }
    }

    #if DEBUG
        /// Sets Save to as the picker would, for background checks (a file panel needs focus).
        func checkChooseFolder(_ path: String) { settings.captureDestination = .folder(path) }
    #endif
}
