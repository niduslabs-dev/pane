import AppKit
import PaneCore

/// Pane's menu bar: the app menu, File, Edit and Device (the More menu's commands, for the window
/// in front, with the same shortcuts), and a Window menu with the iOS Simulator's sizes.
@MainActor
enum MainMenu {
    /// Each size's menu title and shortcut (Command and a digit, as in the Simulator).
    static let sizes: [(mode: ScreenSizeMode, title: String, key: String, help: String)] = [
        (.physical, "Physical Size", "1", "Show the device at the size of the real phone."),
        (.point, "Point Accurate", "2", "One Android dp per Mac point."),
        (.pixel, "Pixel Accurate", "3", "One device pixel per screen pixel."),
        (.fit, "Fit Screen", "4", "As large as fits on this screen."),
    ]

    static let checkForUpdatesTitle = "Check for Updates\u{2026}"

    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Pane")
        appMenu.addItem(
            withTitle: "About Pane", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        let checkForUpdates = NSMenuItem(
            title: checkForUpdatesTitle, action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdates.target = target
        appMenu.addItem(checkForUpdates)
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

        let command = #selector(AppDelegate.runDeviceCommand(_:))

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newWindow = NSMenuItem(
            title: "New Window", action: #selector(AppDelegate.newWindow(_:)), keyEquivalent: "n")
        newWindow.target = target
        newWindow.toolTip = "Opens a window for an emulator that doesn't have one."
        fileMenu.addItem(newWindow)
        fileMenu.addItem(.separator())
        for item in DeviceMenu.captureItems(target: target, action: command) where item.deviceCommand != .copyScreenshot
        {
            fileMenu.addItem(item)
        }
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // The standard items serve the sheets' text fields; Paste in the window pastes on the device.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        for item in DeviceMenu.captureItems(target: target, action: command) where item.deviceCommand == .copyScreenshot
        {
            editMenu.addItem(item)
        }
        editItem.submenu = editMenu
        main.addItem(editItem)

        let deviceItem = NSMenuItem()
        let deviceMenu = NSMenu(title: "Device")
        let groups = [
            DeviceMenu.deviceItems(target: target, action: command),
            DeviceMenu.toolItems(target: target, action: command),
            DeviceMenu.emulatorItems(target: target, action: command),
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { deviceMenu.addItem(.separator()) }
            for item in group { deviceMenu.addItem(item) }
        }
        deviceItem.submenu = deviceMenu
        main.addItem(deviceItem)

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
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }
}
