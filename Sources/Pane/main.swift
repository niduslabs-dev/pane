import AppKit
import SwiftUI
import os

/// Creates the one Pane window and wires focus loss to releasing any held touch or key.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = PaneModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = PaneWindow(model: model)
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate()
        model.start()
        #if DEBUG
            // Shows whether mouse events reach the app at all, for scripted background checks.
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
                Logger(subsystem: "dev.niduslabs.pane", category: "events").debug(
                    "AppKit \(String(describing: event.type), privacy: .public) window \(event.windowNumber) at \(event.locationInWindow.x), \(event.locationInWindow.y)"
                )
                return event
            }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillResignActive(_ notification: Notification) { model.releaseAll() }
    func windowDidResignKey(_ notification: Notification) { model.releaseAll() }
    func applicationWillTerminate(_ notification: Notification) { model.releaseAll() }
}

/// A titled window whose title bar is the content (`titleBarMatchesContent`): full-size content
/// view, transparent title bar, no separator, background equal to the content's.
///
/// An empty unified toolbar makes the title bar as tall as the board's title row, so the system
/// centres the traffic lights in it. Its real height is read back after layout (`titleBarHeight`)
/// and should match `Theme.Window.titleRowHeight`; the device run checks this.
@MainActor
final class PaneWindow: NSWindow {
    init(model: PaneModel) {
        let size = model.layout.windowContentSize
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        title = "Pane"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        toolbar = NSToolbar(identifier: "pane.titlebar")
        toolbarStyle = .unified
        backgroundColor = Theme.Palette.surface
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: PaneContentView(model: model))
        hosting.safeAreaRegions = []
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting
    }

    /// The title bar's real height, for checking it against the title row.
    var titleBarHeight: CGFloat { frame.height - contentLayoutRect.height }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
