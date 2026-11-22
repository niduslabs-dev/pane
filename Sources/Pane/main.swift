import AppKit
import PaneCore
import PaneTakeover
import SwiftUI
import os

/// The app: its windows (one per emulator), the menu bar, and requests from outside
/// (`pane://attach?avd=` from the emulator wrapper).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var controllers: [PaneWindowController] = []
    private var roster = WindowRoster<ObjectIdentifier>()
    /// The window the menu bar acts on when none is key (Pane in the background).
    private weak var lastActive: PaneWindowController?
    /// An attach request (`pane://attach?avd=`) that arrived before the first window opened.
    private var pendingAttach: String?
    private var started = false
    /// Settings' "Show all emulators in Pane" (`TakeoverSwitch`, `EmulatorTakeover`).
    private lazy var takeover = TakeoverSwitch(settings: .shared, backend: Self.takeoverBackend())
    /// Repairs the wrapper when the SDK's folder changes while Pane runs.
    private lazy var sdkWatcher = SDKFolderWatcher { [weak self] in
        Task { @MainActor in self?.takeover.folderChanged() }
    }
    private lazy var settingsWindow = SettingsWindowController(
        settings: .shared, takeover: takeover, updates: updates)
    /// The state every update surface and Check for Updates… read; fed by `updateDriver`
    /// when Sparkle runs.
    let updates = UpdateModel(
        currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    private var updateDriver: UpdateDriver?
    /// The update popup, Pane's `UpdateSurface`.
    private lazy var updatePopup = UpdatePopupController(model: updates)
    private let log = Logger(subsystem: "dev.niduslabs.pane", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(target: self)
        FocusVisibility.shared.start()
        let launchAttach = AttachRequest.avdName(fromArguments: CommandLine.arguments)
        // Opened by the emulator wrapper: stay in the background, as `open -g` asked.
        let activates = launchAttach == nil && !WindowPresence.isBackgroundCheck
        let first = openWindow(showing: nil, activate: activates)
        if activates { NSApp.activate() }
        started = true
        if let name = pendingAttach ?? launchAttach {
            pendingAttach = nil
            first.model.requestAttach(avdName: name)
        }
        startUpdates()
        startTakeover()
        #if DEBUG
            // Shows whether mouse events reach the app at all, for scripted background checks.
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .scrollWheel, .keyDown]) {
                event in
                Logger(subsystem: "dev.niduslabs.pane", category: "events").debug(
                    "AppKit \(String(describing: event.type), privacy: .public) window \(event.windowNumber) at \(event.locationInWindow.x), \(event.locationInWindow.y)"
                )
                return event
            }
        #endif
    }

    /// Closing the last window quits Pane. Emulators keep running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Windows

    /// The model of the window the menu bar's commands go to, for menus that change shape with
    /// it (the Device menu's fold group).
    var activeModel: PaneModel? { activeController?.model }

    /// The window the menu bar's commands go to: the key or main one, else the last one used.
    private var activeController: PaneWindowController? {
        let front = NSApp.keyWindow ?? NSApp.mainWindow
        return controllers.first { $0.window === front } ?? lastActive ?? controllers.first
    }

    private func controller(showing avd: String) -> PaneWindowController? {
        roster.window(showing: avd).flatMap { id in controllers.first { ObjectIdentifier($0) == id } }
    }

    /// Opens a window. `avd` is what it shows (nil for the first window: the AVD remembered
    /// from last time, else any running emulator).
    @discardableResult
    private func openWindow(showing avd: String?, activate: Bool) -> PaneWindowController {
        let controller = PaneWindowController(initialAVD: avd)
        let id = ObjectIdentifier(controller)
        controllers.append(controller)
        roster.add(id, showing: avd)
        lastActive = lastActive ?? controller
        controller.model.isShownElsewhere = { [weak self] name in
            self?.roster.avdsShown(except: id).contains(name) ?? false
        }
        controller.model.startingAVDs = { [weak self] in
            Set(
                (self?.controllers ?? []).filter { [.starting, .booting].contains($0.model.status) }
                    .compactMap(\.model.shownAVDName))
        }
        controller.model.showWindow = { [weak self] name in
            self?.controller(showing: name)?.window.makeKeyAndOrderFront(nil)
        }
        controller.onShownAVDChange = { [weak self] name in self?.roster.set(name, for: id) }
        controller.onBecameKey = { [weak self, weak controller] in self?.lastActive = controller }
        controller.openInNewWindow = { [weak self] name in self?.showInNewWindow(name) }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.controllers.removeAll { $0 === controller }
            self.roster.remove(id)
        }
        let front = lastActive
        controller.start(activate: activate)
        // A second window with no remembered place sits a step right of and below the one in
        // front, as new windows do.
        if let front, front !== controller,
            controller.model.shownAVDName.flatMap(PaneSettings.shared.windowTopLeft(for:)) == nil
        {
            let frame = front.window.frame
            controller.window.setFrameTopLeftPoint(
                CGPoint(x: frame.minX + Theme.Window.cascadeStep, y: frame.maxY - Theme.Window.cascadeStep))
        }
        return controller
    }

    /// The switcher's "Open in New Window": the AVD's own window if it has one, else a new
    /// one, attached when the AVD runs and started headless when it doesn't.
    private func showInNewWindow(_ avd: String) {
        if let existing = controller(showing: avd) {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = openWindow(showing: avd, activate: true)
        controller.model.switchTo(avdName: avd)
    }

    /// File › New Window: a window for the first emulator that doesn't have one.
    @objc func newWindow(_ sender: Any?) {
        guard let avd = avdForNewWindow else { return }
        openWindow(showing: avd, activate: true)
    }

    private var avdForNewWindow: String? {
        roster.avdForNewWindow(
            avds: AvdCatalog.list(in: PaneModel.avdHome).map(\.name),
            running: EmulatorDiscovery.runningEmulators(in: PaneModel.registrationFolder).map(\.avdName))
    }

    /// `pane://attach?avd=<name>` from the emulator wrapper: show that AVD, in its own window
    /// when the ones open are busy with other emulators.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            #if DEBUG
                if handleCheckURL(url) { continue }
            #endif
            guard let name = AttachRequest.avdName(from: url) else {
                log.error("Ignored URL \(url.absoluteString, privacy: .public)")
                continue
            }
            guard started else {
                pendingAttach = name
                continue
            }
            attach(name)
        }
    }

    /// The takeover's real work, on this Mac's SDK and launchd. A debug build refuses it unless
    /// a check points it at scratch folders (`PANE_REAL_SDK` and `PANE_LAUNCH_AGENTS`), so a
    /// debug copy never wraps the real SDK.
    private static func takeoverBackend() -> TakeoverSwitch.Backend {
        let environment = ProcessInfo.processInfo.environment
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.niduslabs.pane"
        let helper = EmulatorLauncher.helperURL().map { $0.appending(path: "Contents/MacOS/PaneEmulator") }
        let setup = EmulatorTakeover.Setup(bundleID: bundleID, helperExecutable: helper, environment: environment)
        #if DEBUG
            let allowed = environment["PANE_REAL_SDK"] != nil && environment["PANE_LAUNCH_AGENTS"] != nil
        #else
            let allowed = true
        #endif
        func guarded() throws(EmulatorTakeover.Failure) {
            if !allowed { throw .agentRefused("debug build without PANE_REAL_SDK and PANE_LAUNCH_AGENTS") }
        }
        return TakeoverSwitch.Backend(
            resolveSDK: { await EmulatorTakeover.resolveSDK(shellTimeout: Theme.Timing.loginShell) },
            candidateSDK: {
                if let override = environment["PANE_REAL_SDK"] {
                    return EmulatorTakeover.sdkRoot(URL(filePath: override, directoryHint: .isDirectory))
                }
                return AndroidSDK.emulatorExecutable().flatMap {
                    EmulatorTakeover.sdkRoot($0.deletingLastPathComponent().deletingLastPathComponent())
                }
            },
            install: { sdk throws(EmulatorTakeover.Failure) in
                try guarded()
                try await EmulatorTakeover.install(sdk: sdk, setup: setup)
            },
            uninstall: { sdk throws(EmulatorTakeover.Failure) in
                try guarded()
                try await EmulatorTakeover.uninstall(sdk: sdk, setup: setup)
            },
            ensure: { sdk throws(EmulatorTakeover.Failure) in
                try guarded()
                return try await EmulatorTakeover.ensure(sdk: sdk, setup: setup)
            },
            isWrapped: { sdk in TakeoverRepair.launcherState(sdk: sdk, script: setup.script) == .wrapped(current: true)
            },
            agentStatus: { EmulatorTakeover.agentStatus(setup: setup) },
            sdkExists: { FileManager.default.fileExists(atPath: $0.appending(path: "emulator").path) })
    }

    /// On launch: undo the old shadow SDK if it's there (turning the new switch on when the old
    /// one was), then repair the wrapper and watch the SDK while Pane runs.
    private func startTakeover() {
        #if DEBUG
            let migrates = ProcessInfo.processInfo.environment["PANE_SHADOW_SDK"] != nil
        #else
            let migrates = true
        #endif
        let legacy = migrates ? EmulatorTakeover.legacyState() : .none
        if legacy != .none, let script = Bundle.main.url(forResource: "emulator-takeover", withExtension: "sh") {
            log.info("Found the shadow SDK setup (\(String(describing: legacy), privacy: .public)); removing it")
            takeover.migrate(wasOn: legacy == .on) {
                let output = try await EmulatorTakeover.runLegacyUninstall(script: script)
                Logger(subsystem: "dev.niduslabs.pane", category: "takeover").info(
                    "Shadow SDK uninstall: \(output, privacy: .public)")
            }
        }
        takeover.onSDKChange = { [weak self] sdk in self?.watchTakeoverSDK(sdk) }
        takeover.launched()
        watchTakeoverSDK(takeover.isOn ? takeover.sdk : nil)
    }

    private func watchTakeoverSDK(_ sdk: URL?) {
        if let sdk {
            sdkWatcher.start(sdk: sdk)
        } else {
            sdkWatcher.stop()
        }
    }

    private func attach(_ avd: String) {
        let idle = controllers.filter { $0.model.emulator == nil && $0.model.status != .starting }
        switch roster.placement(for: avd, idle: idle.map { ObjectIdentifier($0) }) {
        case .existing(let id), .reuse(let id):
            controllers.first { ObjectIdentifier($0) == id }?.model.requestAttach(avdName: avd)
        case .newWindow:
            // Stays behind whatever is in front: the wrapper opened Pane in the background.
            openWindow(showing: avd, activate: false).model.requestAttach(avdName: avd)
        }
    }

    #if DEBUG
        /// Background checks can't drag files, press keys or type in a window that isn't in
        /// front, so the debug build takes `pane://check-…` URLs that call the same handlers:
        /// `check-hover?file=…`, `check-hover-end`, `check-drop?file=…`, `check-paste`,
        /// `check-open-link?text=…` (the sheet, prefilled), `check-location?lat=…&lon=…` (the
        /// sheet, prefilled), `check-gif?file=…`, `check-switcher` (opens the title's menu),
        /// `check-settings`, `check-update?state=…`, `check-drop-hover?on=1|0` (the pointer over the
        /// drop card, which holds a finished card open), `check-restart` and `check-shutdown` (their sheets),
        /// `check-export-gif?file=…` (the Export GIF sheet for that recording), `check-more` (More's
        /// menu), `check-posture?n=…` (asks for a posture by number), `check-save-folder?path=…` (Save to, as the folder picker would
        /// set it) and `check-select?label=…` (opens a select's menu).
        private func handleCheckURL(_ url: URL) -> Bool {
            guard let controller = activeController else { return false }
            let model = controller.model
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let files = items.filter { $0.name == "file" }.compactMap(\.value).map { URL(filePath: $0) }
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            switch url.host() {
            case "check-hover": _ = model.dragChanged(files: files)
            case "check-hover-end": _ = model.dragChanged(files: nil)
            case "check-drop": _ = model.drop(files: files)
            case "check-paste": model.paste()
            case "check-click":
                // A click at a point of the screen (x, y in its points), through the same path
                // as a real one: posted clicks don't reach a background window.
                if let x = value("x").flatMap(Double.init), let y = value("y").flatMap(Double.init) {
                    model.screenView.onPointer?(.down, CGPoint(x: x, y: y))
                    model.screenView.onPointer?(.up, CGPoint(x: x, y: y))
                }
            case "check-inspect": model.tools.toggle(.inspect)
            case "check-open-link": controller.showOpenLink(text: value("text") ?? "")
            case "check-location": controller.showCustomLocation(latitude: value("lat"), longitude: value("lon"))
            case "check-gif": if let file = files.first { model.exportGIF(from: file) }
            case "check-switcher": controller.showSwitcher()
            case "check-switcher-hover":
                // title=1: the pointer on the trigger; row=N: on that row; button=1: on its button.
                if let title = value("title") { model.checkPointerOverTitle(title == "1") }
                if let row = value("row").flatMap(Int.init), let menu = model.menu {
                    menu.hover(row)
                    menu.isButtonHovered = value("button") == "1"
                }
            case "check-takeover":
                takeover.demo(
                    value("state") ?? "on", sdk: URL(filePath: value("sdk") ?? "/", directoryHint: .isDirectory))
            case "check-settings":
                // scroll=pane: opens at the Pane group, as Check for Updates… does.
                if value("scroll") == "pane" { settingsWindow.show(scrollTo: .paneGroup) } else { showSettings(nil) }
            case "check-whats-new": settingsWindow.checkWhatsNew(open: true, empty: value("empty") == "1")
            case "check-whats-new-close": settingsWindow.checkWhatsNew(open: false)
            case "check-drop-hover": model.drop.isHovered = value("on") == "1"
            case "check-restart": controller.restart()
            case "check-shutdown": controller.shutDown()
            case "check-export-gif":
                if let file = files.first { model.settings.lastRecording = file }
                controller.chooseRecordingToExport()
            case "check-more": controller.toggleMoreMenu()
            case "check-posture":
                // A posture by number, also one the AVD doesn't list (the refusal's pill).
                if let posture = value("n").flatMap(Int.init).flatMap(DevicePosture.init(rawValue:)) {
                    model.setPosture(posture)
                }
            case "check-update": showUpdateCheck(value("state") ?? "")
            case "check-save-folder": if let path = value("path") { settingsWindow.checkChooseFolder(path) }
            case "check-select":
                _ = SelectDemo.openers[value("label") ?? ""]?(value("keyboard") == "1")
            default: return false
            }
            return true
        }
    #endif

    // MARK: Updates

    /// Starts Sparkle in a release build that carries a feed. Debug builds leave it off,
    /// except with `-PaneUpdateFeed <url>`, which runs it against a local test appcast.
    private func startUpdates() {
        updates.openURL = { NSWorkspace.shared.open($0) }
        updates.noteLaunch()
        updates.surface = updatePopup
        var feed: URL?
        var isDebug = false
        #if DEBUG
            isDebug = true
            feed = UserDefaults.standard.string(forKey: UpdateDriver.feedOverrideKey).flatMap(URL.init(string:))
        #endif
        guard
            UpdateDriver.shouldStart(
                isDebug: isDebug, feedOverride: feed, info: Bundle.main.infoDictionary ?? [:])
        else { return }
        let driver = UpdateDriver(model: updates, feedOverride: feed)
        driver.start()
        updateDriver = driver
    }

    /// Check for Updates… opens Settings at the Pane group and runs the same check as the
    /// button there: the Version row's caption reports it.
    @objc func checkForUpdates(_ sender: Any?) {
        settingsWindow.show(scrollTo: .paneGroup)
        updates.perform(.check)
    }

    #if DEBUG
        /// `pane://check-update?state=…`: shows an update surface in a state, with the board's
        /// example update, so every state can be captured without a feed.
        private func showUpdateCheck(_ state: String) {
            let update = AvailableUpdate(
                version: Self.demoUpdateVersion, size: 6_000_000,  // design-ok: debug demo data
                notes: ["Settings shows an update in the version row", "What's new opens from Settings"],
                releaseNotesURL: URL(string: "https://github.com/niduslabs-dev/pane/releases"))
            let checked = Date.now.addingTimeInterval(-Theme.Timing.updateCheckDemoAge)
            func downloading(_ progress: UpdateProgress) -> UpdateModel.Phase { .downloading(update, progress) }
            updates.demoFlags()
            // Found only waits for Download with Install updates automatically off (board 22).
            updates.installsAutomatically = state != "available"
            switch state {
            case "ready": updates.demo(.ready(update), surface: true, lastChecked: checked)
            case "later":
                updates.demo(.ready(update), surface: false, lastChecked: checked)
                updates.demoFlags(deferred: true)
            case "laterfail":
                updates.demo(.ready(update), surface: false, lastChecked: checked)
                updates.demoFlags(deferred: true, restartFailed: true)
            case "installing": updates.demo(.installing(update), surface: false, lastChecked: checked)
            case "available": updates.demo(.available(update), surface: true, lastChecked: checked)
            case "downloading":
                // From the popup's Download: the popup is up first, then follows the download.
                updates.demo(.available(update), surface: true, lastChecked: checked)
                updates.demo(
                    downloading(UpdateProgress(received: 2_520_000, expected: 6_000_000)), surface: true,
                    lastChecked: checked)
            case "downloading-quiet":
                updates.demo(
                    downloading(UpdateProgress(received: 2_520_000, expected: 6_000_000)), surface: false,
                    lastChecked: checked)
            case "nosize": updates.demo(downloading(UpdateProgress()), surface: false, lastChecked: checked)
            case "preparing":
                updates.demo(
                    downloading(UpdateProgress(stage: .preparing, received: 6_000_000, expected: 6_000_000)),
                    surface: false, lastChecked: checked)
            case "checking": updates.demo(.checking, surface: false, lastChecked: checked)
            case "uptodate": updates.demo(.upToDate, surface: false, lastChecked: .now)
            case "failed": updates.demo(.failed(.check), surface: false, lastChecked: checked)
            case "dlfailed":
                updates.demo(.failed(.download(version: update.version)), surface: false, lastChecked: checked)
            case "verifyfailed":
                updates.demo(.failed(.verify(version: update.version)), surface: false, lastChecked: checked)
            case "notchecked": updates.demo(.idle, surface: false, lastChecked: nil)
            case "disabled": updates.demo(.idle, surface: false, lastChecked: nil, enabled: false)
            case "updated":
                updates.demo(.idle, surface: false, lastChecked: checked)
                updates.demoFlags(updatedTo: updates.currentVersion)
            default: updates.demo(.idle, surface: false, lastChecked: checked)
            }
        }

        /// The demo states' update, the board's example.
        static let demoUpdateVersion = "1.0.3"
    #endif

    // MARK: Settings

    /// Settings… in the app menu (Command-comma) and in More.
    @objc func showSettings(_ sender: Any?) { settingsWindow.show() }

    func applicationWillResignActive(_ notification: Notification) {
        for controller in controllers { controller.model.releaseAll() }
    }

    // MARK: Menu bar commands (they act on the window in front)

    @objc func runDeviceCommand(_ sender: NSMenuItem) {
        guard let command = sender.deviceCommand else { return }
        activeController?.perform(command)
    }

    @objc func chooseSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ScreenSizeMode(rawValue: raw) else { return }
        activeController?.model.applySize(mode)
    }

    @objc func zoomIn(_ sender: Any?) { activeController?.model.zoom(in: true) }
    @objc func zoomOut(_ sender: Any?) { activeController?.model.zoom(in: false) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let model = activeController?.model
        switch item.action {
        case #selector(runDeviceCommand(_:)):
            return DeviceMenu.validate(item, model: model)
        case #selector(newWindow(_:)):
            return avdForNewWindow != nil
        case #selector(chooseSize(_:)):
            guard let model, let raw = item.representedObject as? String, let mode = ScreenSizeMode(rawValue: raw)
            else { return false }
            item.state = model.sizeMode == mode ? .on : .off
            return model.isAvailable(mode)
        case #selector(zoomIn(_:)): return model?.canZoom(in: true) ?? false
        case #selector(zoomOut(_:)): return model?.canZoom(in: false) ?? false
        case #selector(checkForUpdates(_:)): return updates.canCheck
        default: return true
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in controllers { controller.model.releaseAll() }
    }

    /// Finishes running recordings before quitting: this quit is put off, the movies are
    /// written, then Pane quits again. (Replying later from a task never ran: AppKit's wait
    /// for the reply doesn't service the main actor.)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let finishing = controllers.compactMap { $0.model.stopRecording() }
        guard !finishing.isEmpty else { return .terminateNow }
        Task {
            for task in finishing { await task.value }
            sender.terminate(nil)
        }
        return .terminateCancel
    }
}

/// A titled window whose title bar is the content (`titleBarMatchesContent`): full-size content
/// view, transparent title bar, no separator, background equal to the content's.
///
/// An empty unified toolbar makes the title bar as tall as the board's title row, so the system
/// centres the traffic lights in it. Its real height is read back after layout (`titleBarHeight`)
/// and should match `Theme.Window.titleRowHeight`; the device run checks this.
@MainActor
final class PaneWindow: NSWindow {
    private let toolbarController: TitlebarToolbar
    private weak var hosting: FirstClickHostingView<PaneContentView>?
    private let model: PaneModel
    /// The centre reshapes keep, so the window server's rounding never walks the window sideways.
    var heldCentre = HeldCentre()

    init(model: PaneModel, onMore: @escaping () -> Void) {
        toolbarController = TitlebarToolbar(onMore: onMore)
        self.model = model
        let size = model.layout.windowContentSize
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        title = "Pane"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        let toolbar = NSToolbar(identifier: "pane.titlebar")
        toolbar.delegate = toolbarController
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        self.toolbar = toolbar
        toolbarStyle = .unified
        // Clear so the ink glass shows; `GlassBackgroundView` paints paper or ink otherwise.
        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        // No full screen: the green button zooms to the largest frame that fits instead.
        collectionBehavior.insert(.fullScreenNone)

        let hosting = FirstClickHostingView(rootView: PaneContentView(model: model))
        hosting.onPointerMove = { [weak model] point in model?.pointerMoved(to: point) }
        self.hosting = hosting
        acceptsMouseMovedEvents = true
        hosting.safeAreaRegions = []
        // The model sizes the window (`setContentSizeKeepingTop`); SwiftUI must not pin it.
        hosting.sizingOptions = []
        contentView = GlassBackgroundView(content: hosting)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: Dropping files (the window is the drop target; the screen shows the highlight)

    private func files(in sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
    }

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        model.dragChanged(files: files(in: sender)) ? .copy : []
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let drag = model.drop.drag, !drag.card.isRefused else {
            // A refused drop (no emulator, only folders) shows macOS's not-allowed pointer.
            if model.drop.drag != nil { NSCursor.operationNotAllowed.set() }
            return []
        }
        return .copy
    }

    func draggingExited(_ sender: (any NSDraggingInfo)?) { _ = model.dragChanged(files: nil) }
    func draggingEnded(_ sender: any NSDraggingInfo) { _ = model.dragChanged(files: nil) }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        model.drop(files: files(in: sender))
    }

    /// Resizes the content, keeping the window's top edge and horizontal centre where they are
    /// and the whole window on its screen.
    func setContentSizeKeepingTop(_ size: CGSize) {
        setFrame(frameKeepingTop(forContentSize: size, from: frame), display: true, animate: false)
    }

    /// Where the system's traffic lights end, in content coordinates, so the title can sit
    /// after them without assuming their size.
    var trafficLightsTrailingEdge: CGFloat? {
        guard let zoom = standardWindowButton(.zoomButton), let container = zoom.superview else { return nil }
        return container.convert(zoom.frame, to: nil).maxX
    }

    /// Moves while the window is key arrive here; the hosting view's tracking area covers the
    /// rest (an inactive window).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .mouseMoved { hosting?.reportPointer(event) }
        // The title bar takes clicks before the content under it, so a click on the device
        // name is handed to the emulator switcher here.
        if event.type == .leftMouseDown, attachedSheet == nil {
            model.isTitleFocused = false
            let point = CGPoint(x: event.locationInWindow.x, y: frame.height - event.locationInWindow.y)
            if model.switcherFrame.contains(point) {
                model.onShowSwitcher()
                return
            }
            // Any other click in the title row closes the open switcher, as a click outside
            // a menu does.
            if point.y < Theme.Window.titleRowHeight, !toolbarController.isOverMore(event) { model.closeMenu() }
        }
        super.sendEvent(event)
    }

    /// Lets a window taller than the screen (Pixel Accurate on a small display) hang off the
    /// bottom, as the Simulator does; only the title bar is kept below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let visible = (screen ?? self.screen)?.visibleFrame else { return frameRect }
        var rect = frameRect
        if rect.maxY > visible.maxY { rect.origin.y = visible.maxY - rect.height }
        return rect
    }

    /// The title bar's real height, for checking it against the title row.
    var titleBarHeight: CGFloat { frame.height - contentLayoutRect.height }
}

/// SIGTERM (a logout, `kill`) quits through `terminate`, so a running recording is finished
/// instead of left unreadable.
signal(SIGTERM, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSource.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
terminationSource.resume()

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

/// Lets the title row's tools and the screen's buttons act on the first click into an inactive
/// window, as the iOS Simulator's toolbar does, instead of that click only focusing the window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    /// Where the pointer is over the window (y down), or nil when it leaves; drives the frame
    /// buttons sliding out.
    var onPointerMove: ((CGPoint?) -> Void)?
    private var pointerTracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        pointerTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        reportPointer(event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        reportPointer(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerMove?(nil)
    }

    func reportPointer(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPointerMove?(isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y))
    }
}

/// The title bar's one toolbar item, More, as Device Hub has it: a real `NSToolbar` item, so the
/// system draws its glass pill and sizes the traffic lights as in Device Hub. It opens Pane's
/// own menu panel, not an `NSMenu`.
@MainActor
final class TitlebarToolbar: NSObject, NSToolbarDelegate {
    private static let more = NSToolbarItem.Identifier("pane.more")
    private let onMore: () -> Void

    init(onMore: @escaping () -> Void) {
        self.onMore = onMore
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.more]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.more]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.more else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        // Drawn in the toolbar's ink (`textPrimary`), as the device toolbar's icons are, not
        // as a template: AppKit dims a template glyph in an inactive window to 2.2:1 on the
        // pill, even under Increase Contrast.
        item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [Theme.Palette.text]))
        item.label = "More"
        item.toolTip = "More"
        // Bordered gives the system's glass pill, as Device Hub's More has.
        item.isBordered = true
        item.target = self
        item.action = #selector(pressMore(_:))
        return item
    }

    @objc private func pressMore(_ sender: Any?) { onMore() }

    /// Gives More's button the accessibility identifier `window-more`, so the measured check
    /// (`tools/design/checks/measured`) finds it. AppKit draws the item's view itself (not an
    /// `NSButton`), so it is found by its role and name once the window is on screen.
    static func identifyMore(in window: NSWindow) {
        guard let frame = window.contentView?.superview else { return }
        func visit(_ view: NSView) -> Bool {
            if view.accessibilityRole() == .button, view.accessibilityLabel() == "More" || view.toolTip == "More" {
                view.setAccessibilityIdentifier("window-more")
                return true
            }
            return view.subviews.contains(where: visit)
        }
        _ = visit(frame)
    }

    /// Whether a click is on More, which opens and closes its menu on its own: the system
    /// owns the button's view, so this takes the title row's right end, which More fills.
    func isOverMore(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        return event.locationInWindow.x > window.frame.width - Theme.Window.titleRowTrailingPadding
    }
}
