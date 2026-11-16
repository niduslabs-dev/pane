import AppKit
import PaneCore
import SwiftUI
import UniformTypeIdentifiers
import os

/// One Pane window and the emulator it shows: owns the window's model, is the window's
/// delegate, runs the menus' commands, presents the sheets and the emulator switcher, and
/// remembers where each emulator's window sits.
@MainActor
final class PaneWindowController: NSObject, NSWindowDelegate, NSMenuItemValidation {
    let model: PaneModel
    private(set) var window: PaneWindow!
    /// Asked for a second window (the switcher's Open in New Window).
    var openInNewWindow: (String) -> Void = { _ in }
    /// Told when the window became key or closed.
    var onBecameKey: () -> Void = {}
    var onClose: () -> Void = {}
    /// Told when the AVD the window is about changed.
    var onShownAVDChange: (String?) -> Void = { _ in }

    /// The AVD the window's position belongs to; nil until one is placed.
    private var placedAVD: String?
    /// True while Pane itself moves or resizes the window, so that isn't taken for a drag.
    private var isAdjustingFrame = false
    private var openSheet: NSWindow?
    private let log = Logger(subsystem: "dev.niduslabs.pane", category: "window")

    init(settings: PaneSettings = .shared, initialAVD: String? = nil) {
        model = PaneModel(settings: settings, initialAVD: initialAVD)
        super.init()
        let more = NSMenu(title: "More")
        for item in DeviceMenu.moreItems(target: self, action: #selector(runDeviceCommand(_:))) { more.addItem(item) }
        window = PaneWindow(model: model, moreMenu: more)
        window.delegate = self
        model.onWindowContentSizeChange = { [weak self] size in
            guard let self else { return }
            self.isAdjustingFrame = true
            self.window.setContentSizeKeepingTop(size)
            self.isAdjustingFrame = false
        }
        model.onShowSwitcher = { [weak self] in self?.showSwitcher() }
        model.onCommand = { [weak self] command in self?.perform(command) }
        model.onDeviceGone = { [weak self] in
            guard let self, let sheet = self.openSheet, sheet.sheetParent != nil else { return }
            self.window.endSheet(sheet)
        }
        if let trailing = window.trafficLightsTrailingEdge {
            model.titleLeadingInset = trailing + Theme.Window.titleGap
        }
        window.center()
    }

    /// Shows the window and starts looking for its emulator. `activate` brings it in front.
    func start(activate: Bool) {
        if activate {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        model.start()
        followShownAVD()
    }

    // MARK: Position per emulator

    /// Watches which AVD the window is about; each has its own remembered position.
    private func followShownAVD() {
        let shown = withObservationTracking {
            model.shownAVDName
        } onChange: { [weak self] in
            Task { @MainActor in self?.followShownAVD() }
        }
        guard shown != placedAVD else { return }
        placedAVD = shown
        onShownAVDChange(shown)
        guard let shown, let topLeft = model.settings.windowTopLeft(for: shown) else { return }
        isAdjustingFrame = true
        window.setFrameTopLeftPoint(topLeft)
        // Never restore to somewhere no screen shows any more.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { window.center() }
        isAdjustingFrame = false
    }

    private func rememberPosition() {
        guard let placedAVD, !isAdjustingFrame else { return }
        model.settings.setWindowTopLeft(CGPoint(x: window.frame.minX, y: window.frame.maxY), for: placedAVD)
    }

    func windowDidMove(_ notification: Notification) { rememberPosition() }

    // MARK: Commands

    @objc func runDeviceCommand(_ sender: NSMenuItem) {
        guard let command = sender.deviceCommand else { return }
        perform(command)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool { DeviceMenu.validate(item, model: model) }

    func perform(_ command: DeviceCommand) {
        switch command {
        case .openLink: showOpenLink(text: "")
        case .copyScreenshot: model.copyScreenshot()
        case .saveScreenshot: model.saveScreenshot()
        case .exportGIF: chooseRecordingToExport()
        case .appearance(let appearance): model.setAppearance(appearance)
        case .textSize(let size): model.setTextSize(size)
        case .locationNone: model.setCustomLocation(nil)
        case .locationCustom: showCustomLocation(latitude: nil, longitude: nil)
        case .tool(let tool): model.tools.toggle(tool)
        case .restart: restart()
        case .shutDown: shutDown()
        case .showHere(let avd): model.switchTo(avdName: avd)
        case .openInNewWindow(let avd): openInNewWindow(avd)
        case .showEmulatorsInFinder: NSWorkspace.shared.open(PaneModel.avdHome)
        }
    }

    // MARK: Sheets

    /// Open Link. `text` prefills the field (checks use it; the menu passes none).
    func showOpenLink(text: String) {
        guard model.status == .live, window.attachedSheet == nil else { return }
        model.tools.deactivate()
        openSheet = SheetPresenter.present(on: window) { close in
            OpenLinkSheet(model: model, close: close, text: text)
        }
    }

    func showCustomLocation(latitude: String?, longitude: String?) {
        guard model.status == .live, window.attachedSheet == nil else { return }
        let current = model.customLocation
        openSheet = SheetPresenter.present(on: window) { close in
            LocationSheet(
                model: model, close: close, latitude: latitude ?? current.map { String($0.latitude) } ?? "",
                longitude: longitude ?? current.map { String($0.longitude) } ?? "")
        }
    }

    /// Export Recording as GIF: offers the last recording, or any movie.
    private func chooseRecordingToExport() {
        guard window.attachedSheet == nil else { return }
        guard let last = model.settings.lastRecording else {
            chooseMovie()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Export the last recording as a GIF?"
        alert.informativeText = "\(last.lastPathComponent)\nThe GIF is saved next to it."
        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Choose Another…")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: self?.model.exportGIF(from: last)
            case .alertSecondButtonReturn: self?.chooseMovie()
            default: break
            }
        }
    }

    private func chooseMovie() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.quickTimeMovie, .mpeg4Movie, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = PaneModel.captureFolder
        panel.prompt = "Export"
        panel.message = "Choose a recording to export as a GIF."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.model.exportGIF(from: url)
        }
    }

    /// Restarting or shutting down an emulator Pane didn't start asks first.
    func restart() {
        guard model.emulator != nil else { return }
        if model.ownsEmulator {
            model.restartEmulator()
            return
        }
        SheetPresenter.confirm(
            on: window, message: "Restart \(model.title)?",
            detail: "Pane didn't start this emulator. Restarting it closes any apps running on it.",
            action: "Restart Emulator"
        ) { [weak self] in self?.model.restartEmulator() }
    }

    func shutDown() {
        guard model.emulator != nil else { return }
        if model.ownsEmulator {
            model.shutDownEmulator()
            return
        }
        SheetPresenter.confirm(
            on: window, message: "Shut down \(model.title)?",
            detail: "Pane didn't start this emulator. Shutting it down closes any apps running on it.",
            action: "Shut Down Emulator"
        ) { [weak self] in self?.model.shutDownEmulator() }
    }

    // MARK: Emulator switcher

    /// Opens the menu under the title's device name, or closes it when it is open.
    func showSwitcher() {
        if model.switcher != nil {
            model.switcher = nil
            return
        }
        guard window.attachedSheet == nil else { return }
        model.reloadAVDs()
        let running = EmulatorDiscovery.runningEmulators(in: PaneModel.registrationFolder).map(\.avdName)
        model.switcher = SwitcherEntry.entries(
            avds: model.avds, running: running, current: model.shownAVDName,
            shownElsewhere: Set(model.avds.map(\.name) + running).filter(model.isShownElsewhere))
    }

    // MARK: Window delegate

    func windowDidResignKey(_ notification: Notification) {
        #if DEBUG
            let staysOpen = UserDefaults.standard.bool(forKey: "PaneTreatAsKey")
        #else
            let staysOpen = false
        #endif
        if !staysOpen { model.switcher = nil }
        model.releaseAll()
        model.windowResignedKey()
    }

    /// Keys go to the emulator's screen whenever the window is key.
    func windowDidBecomeKey(_ notification: Notification) {
        window.makeFirstResponder(model.screenView)
        model.windowBecameKey()
        onBecameKey()
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
        rememberPosition()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        model.backingScaleChanged()
        model.displayChanged()
    }

    func windowDidChangeScreen(_ notification: Notification) { model.displayChanged() }

    func windowWillClose(_ notification: Notification) {
        rememberPosition()
        model.stopRecording()
        model.close()
        onClose()
    }

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
