import AppKit
import PaneCore

/// Pane's menu bar: the app menu and a Window menu with the iOS Simulator's sizes.
@MainActor
enum MainMenu {
    /// Each size's menu title and shortcut (Command and a digit, as in the Simulator).
    static let sizes: [(mode: ScreenSizeMode, title: String, key: String, help: String)] = [
        (.physical, "Physical Size", "1", "Show the device at the size of the real phone."),
        (.point, "Point Accurate", "2", "One Android dp per Mac point."),
        (.pixel, "Pixel Accurate", "3", "One device pixel per screen pixel."),
        (.fit, "Fit Screen", "4", "As large as fits on this screen."),
    ]

    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Pane")
        appMenu.addItem(
            withTitle: "About Pane", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        let takeover = NSMenuItem(
            title: "Show All Emulators in Pane", action: #selector(AppDelegate.toggleTakeover(_:)), keyEquivalent: "")
        takeover.target = target
        takeover.toolTip =
            "Emulators started anywhere, like Expo or a terminal, open here without a window. Applies to new terminals."
        appMenu.addItem(takeover)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Pane", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Pane", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        for size in sizes {
            let item = NSMenuItem(
                title: size.title, action: #selector(AppDelegate.chooseSize(_:)), keyEquivalent: size.key)
            item.target = target
            item.representedObject = size.mode.rawValue
            item.toolTip = size.help
            windowMenu.addItem(item)
        }
        windowMenu.addItem(.separator())
        let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(AppDelegate.zoomIn(_:)), keyEquivalent: "+")
        zoomIn.target = target
        windowMenu.addItem(zoomIn)
        let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(AppDelegate.zoomOut(_:)), keyEquivalent: "-")
        zoomOut.target = target
        windowMenu.addItem(zoomOut)
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }
}
