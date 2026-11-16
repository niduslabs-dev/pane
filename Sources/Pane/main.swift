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
        model.onWindowContentSizeChange = { [weak window] size in window?.setContentSizeKeepingTop(size) }
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

    /// Snaps every resize to the device's shape: the largest frame that fits the proposed size.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let proposed = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        let available = sender.screen?.visibleFrame.size ?? proposed
        let height = model.screenHeight(fitting: proposed, available: available)
        let content = model.windowContentSize(screenHeight: height)
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
    }

    /// Follows the new size; a resize that skipped `windowWillResize` (zoom, Accessibility)
    /// is snapped to the device's shape here.
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? PaneWindow else { return }
        let content = window.contentRect(forFrameRect: window.frame).size
        let available = window.screen?.visibleFrame.size ?? content
        model.windowResized(screenHeight: model.screenHeight(fitting: content, available: available))
        let snapped = model.layout.windowContentSize
        if !window.inLiveResize, snapped != content { window.setContentSizeKeepingTop(snapped) }
    }

    func windowDidChangeBackingProperties(_ notification: Notification) { model.backingScaleChanged() }
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        title = "Pane"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        toolbar = NSToolbar(identifier: "pane.titlebar")
        toolbarStyle = .unified
        // Clear so the ink glass shows; `GlassBackgroundView` paints paper or ink otherwise.
        backgroundColor = .clear
        isOpaque = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false

        let hosting = FirstClickHostingView(rootView: PaneContentView(model: model))
        hosting.safeAreaRegions = []
        // The model sizes the window (`setContentSizeKeepingTop`); SwiftUI must not pin it.
        hosting.sizingOptions = []
        contentView = GlassBackgroundView(content: hosting)
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

    /// The title bar's real height, for checking it against the title row.
    var titleBarHeight: CGFloat { frame.height - contentLayoutRect.height }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

/// Lets the title row's tools and the screen's buttons act on the first click into an inactive
/// window, as the iOS Simulator's toolbar does, instead of that click only focusing the window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
