import AppKit
import PaneCore
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
    /// True while the takeover script runs, so the menu item can't start a second run.
    private var takeoverRunning = false
    private let log = Logger(subsystem: "dev.niduslabs.pane", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(target: self)
        let launchAttach = AttachRequest.avdName(fromArguments: CommandLine.arguments)
        // Opened by the emulator wrapper: stay in the background, as `open -g` asked.
        let first = openWindow(showing: nil, activate: launchAttach == nil)
        if launchAttach == nil { NSApp.activate() }
        started = true
        if let name = pendingAttach ?? launchAttach {
            pendingAttach = nil
            first.model.requestAttach(avdName: name)
        }
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
        /// sheet, prefilled), `check-gif?file=…` and `check-switcher` (opens the title's menu).
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
            case "check-open-link": controller.showOpenLink(text: value("text") ?? "")
            case "check-location": controller.showCustomLocation(latitude: value("lat"), longitude: value("lon"))
            case "check-gif": if let file = files.first { model.exportGIF(from: file) }
            case "check-switcher": controller.showSwitcher()
            default: return false
            }
            return true
        }
    #endif

    // MARK: Show All Emulators in Pane

    /// Turns the emulator takeover on or off by running the bundled script.
    @objc func toggleTakeover(_ sender: NSMenuItem) {
        guard !takeoverRunning else { return }
        guard let script = Bundle.main.url(forResource: "emulator-takeover", withExtension: "sh") else {
            log.error("emulator-takeover.sh is missing from the app")
            NSSound.beep()
            return
        }
        let action: EmulatorTakeover.Action = EmulatorTakeover.isInstalled() ? .uninstall : .install
        let app = Bundle.main.bundleURL
        takeoverRunning = true
        log.info("Takeover \(action.rawValue, privacy: .public)")
        Task {
            defer { takeoverRunning = false }
            do {
                let output = try await EmulatorTakeover.run(action, script: script, app: app)
                log.info("Takeover output: \(output, privacy: .public)")
            } catch {
                log.error("Takeover failed: \(String(describing: error), privacy: .public)")
                let alert = NSAlert()
                alert.messageText = "Couldn't change where emulators open."
                alert.informativeText = (error as? EmulatorTakeover.Failure)?.output ?? error.localizedDescription
                if let window = activeController?.window {
                    alert.beginSheetModal(for: window, completionHandler: nil)
                } else {
                    alert.runModal()
                }
            }
        }
    }

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
        case #selector(toggleTakeover(_:)):
            item.state = EmulatorTakeover.isInstalled() ? .on : .off
            return !takeoverRunning
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
        model.dropHover == nil ? [] : .copy
    }

    func draggingExited(_ sender: (any NSDraggingInfo)?) { _ = model.dragChanged(files: nil) }
    func draggingEnded(_ sender: any NSDraggingInfo) { _ = model.dragChanged(files: nil) }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        model.drop(files: files(in: sender))
    }

    /// Resizes the content, keeping the window's top edge and horizontal centre where they are
    /// and the whole window on its screen.
    func setContentSizeKeepingTop(_ size: CGSize) {
        let newFrame = frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var origin = CGPoint(x: frame.midX - newFrame.width / 2, y: frame.maxY - newFrame.height)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - newFrame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - newFrame.height)
        }
        setFrame(NSRect(origin: origin, size: newFrame.size), display: true, animate: false)
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
        item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        item.label = "More"
        item.toolTip = "More"
        // Bordered gives the system's glass pill, as Device Hub's More has.
        item.isBordered = true
        item.target = self
        item.action = #selector(pressMore(_:))
        return item
    }

    @objc private func pressMore(_ sender: Any?) { onMore() }

    /// Whether a click is on More, which opens and closes its menu on its own: the system
    /// owns the button's view, so this takes the title row's right end, which More fills.
    func isOverMore(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        return event.locationInWindow.x > window.frame.width - Theme.Window.titleRowTrailingPadding
    }
}
