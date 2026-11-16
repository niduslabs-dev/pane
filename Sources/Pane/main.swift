import AppKit
import PaneCore
import SwiftUI
import os

/// Creates the one Pane window and wires focus loss to releasing any held touch or key.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private let model = PaneModel()
    private var window: NSWindow?
    /// An attach request (`pane://attach?avd=`) that arrived before the model started.
    private var pendingAttach: String?
    private var started = false
    /// True while the takeover script runs, so the menu item can't start a second run.
    private var takeoverRunning = false
    private let log = Logger(subsystem: "dev.niduslabs.pane", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make(target: self)
        let window = PaneWindow(model: model)
        window.delegate = self
        model.onWindowContentSizeChange = { [weak window] size in window?.setContentSizeKeepingTop(size) }
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        if let trailing = window.trafficLightsTrailingEdge {
            model.titleLeadingInset = trailing + Theme.Window.titleGap
        }
        let launchAttach = AttachRequest.avdName(fromArguments: CommandLine.arguments)
        // Opened by the emulator wrapper: stay in the background, as `open -g` asked.
        if launchAttach == nil { NSApp.activate() }
        model.start()
        started = true
        if let name = pendingAttach ?? launchAttach {
            pendingAttach = nil
            model.requestAttach(avdName: name)
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// `pane://attach?avd=<name>` from the emulator wrapper: show that AVD.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            #if DEBUG
                if handleCheckURL(url) { continue }
            #endif
            guard let name = AttachRequest.avdName(from: url) else {
                log.error("Ignored URL \(url.absoluteString, privacy: .public)")
                continue
            }
            if started {
                model.requestAttach(avdName: name)
            } else {
                pendingAttach = name
            }
        }
    }

    #if DEBUG
        /// Background checks can't drag files or press keys in a window that isn't in front, so
        /// the debug build takes `pane://check-hover?file=…`, `check-hover-end`,
        /// `check-drop?file=…` and `check-paste`, which call the same handlers.
        private func handleCheckURL(_ url: URL) -> Bool {
            let files = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .filter { $0.name == "file" }.compactMap(\.value).map { URL(filePath: $0) }
            switch url.host() {
            case "check-hover": _ = model.dragChanged(files: files)
            case "check-hover-end": _ = model.dragChanged(files: nil)
            case "check-drop": _ = model.drop(files: files)
            case "check-paste": model.paste()
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
                if let window { alert.beginSheetModal(for: window, completionHandler: nil) } else { alert.runModal() }
            }
        }
    }

    func applicationWillResignActive(_ notification: Notification) { model.releaseAll() }
    func windowDidResignKey(_ notification: Notification) {
        model.releaseAll()
        model.windowResignedKey()
    }

    /// Keys go to the emulator's screen whenever the window is key.
    func windowDidBecomeKey(_ notification: Notification) {
        (notification.object as? NSWindow)?.makeFirstResponder(model.screenView)
        model.windowBecameKey()
    }

    /// Snaps every resize to the device's shape: the largest frame that fits the proposed size.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let proposed = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let available = sender.screen?.visibleFrame.size ?? proposed
        let height = model.screenHeight(fitting: proposed, available: available)
        let content = model.windowContentSize(screenHeight: height)
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
    }

    /// Follows a drag (which clears the chosen size); a resize that skipped `windowWillResize`
    /// (Accessibility) is snapped to the device's shape here. Sizes the model set itself
    /// already match and are left alone, even when taller than the screen.
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? PaneWindow else { return }
        let content = window.contentRect(forFrameRect: window.frame).size
        // AppKit rounds frames to whole points, so "already the model's size" is within a point.
        let expected = model.layout.windowContentSize
        if !window.inLiveResize, abs(content.width - expected.width) < 1, abs(content.height - expected.height) < 1 {
            return
        }
        let available = window.screen?.visibleFrame.size ?? content
        model.windowResized(screenHeight: model.screenHeight(fitting: content, available: available))
        let snapped = model.layout.windowContentSize
        if !window.inLiveResize, abs(snapped.width - content.width) >= 1 || abs(snapped.height - content.height) >= 1 {
            window.setContentSizeKeepingTop(snapped)
        }
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        model.backingScaleChanged()
        model.displayChanged()
    }

    func windowDidChangeScreen(_ notification: Notification) { model.displayChanged() }

    // MARK: Window menu sizes

    @objc func chooseSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ScreenSizeMode(rawValue: raw) else { return }
        model.applySize(mode)
    }

    @objc func zoomIn(_ sender: Any?) { model.zoom(in: true) }
    @objc func zoomOut(_ sender: Any?) { model.zoom(in: false) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(chooseSize(_:)):
            guard let raw = item.representedObject as? String, let mode = ScreenSizeMode(rawValue: raw) else {
                return false
            }
            item.state = model.sizeMode == mode ? .on : .off
            return model.isAvailable(mode)
        case #selector(zoomIn(_:)): return model.canZoom(in: true)
        case #selector(zoomOut(_:)): return model.canZoom(in: false)
        case #selector(toggleTakeover(_:)):
            item.state = EmulatorTakeover.isInstalled() ? .on : .off
            return !takeoverRunning
        default: return true
        }
    }
    func applicationWillTerminate(_ notification: Notification) { model.releaseAll() }

    /// Finishes a running recording before quitting: this quit is put off, the movie is
    /// written, then Pane quits again. (Replying later from a task never ran: AppKit's wait
    /// for the reply doesn't service the main actor.)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let finishing = model.stopRecording() else { return .terminateNow }
        Task {
            await finishing.value
            sender.terminate(nil)
        }
        return .terminateCancel
    }

    func windowWillClose(_ notification: Notification) { model.stopRecording() }

    /// The green button zooms to the largest frame that fits the screen (no full screen).
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        let available = window.screen?.visibleFrame ?? newFrame
        let height = model.screenHeight(fitting: available.size, available: available.size)
        let content = model.windowContentSize(screenHeight: height)
        let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
        return NSRect(
            x: min(max(window.frame.midX - size.width / 2, available.minX), available.maxX - size.width),
            y: max(window.frame.maxY - size.height, available.minY), width: size.width, height: size.height)
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

    init(model: PaneModel) {
        toolbarController = TitlebarToolbar(model: model)
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
/// system draws its glass pill and sizes the traffic lights as in Device Hub.
@MainActor
final class TitlebarToolbar: NSObject, NSToolbarDelegate {
    private static let more = NSToolbarItem.Identifier("pane.more")
    private let model: PaneModel

    init(model: PaneModel) {
        self.model = model
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
        let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
        item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        item.label = "More"
        item.toolTip = "More"
        item.showsIndicator = false
        // Bordered gives the system's glass pill, as Device Hub's More has.
        item.isBordered = true
        item.menu = MoreMenu.make(model: model)
        return item
    }
}

/// The More menu. Rebuilt each time it opens, so its items follow the model.
@MainActor
final class MoreMenu: NSObject, NSMenuDelegate {
    private let model: PaneModel

    private init(model: PaneModel) {
        self.model = model
    }

    static func make(model: PaneModel) -> NSMenu {
        let menu = NSMenu(title: "More")
        let delegate = MoreMenu(model: model)
        menu.delegate = delegate
        objc_setAssociatedObject(menu, &associationKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        delegate.menuNeedsUpdate(menu)
        return menu
    }

    nonisolated(unsafe) private static var associationKey: UInt8 = 0

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let restart = NSMenuItem(title: "Restart Emulator", action: #selector(restart), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)
        menu.addItem(.separator())
        let share = NSMenuItem(title: "Share Clipboard", action: #selector(toggleClipboard), keyEquivalent: "")
        share.target = self
        share.state = model.sharesClipboard ? .on : .off
        share.toolTip = "Copied text moves between this Mac and the device while Pane is in front."
        menu.addItem(share)
    }

    @objc private func toggleClipboard() { model.sharesClipboard.toggle() }

    @objc private func restart() { model.restartEmulator() }
}
