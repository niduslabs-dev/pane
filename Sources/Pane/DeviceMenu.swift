import AppKit
import PaneCore

/// Everything the More menu, the menu bar and the emulator switcher can ask a window to do.
enum DeviceCommand: Equatable {
    case openLink
    case copyScreenshot
    case saveScreenshot
    case exportGIF
    case appearance(DeviceAppearance)
    case textSize(DeviceTextSize)
    case locationNone
    case locationCustom
    case tool(PaneTool)
    case restart
    case shutDown
    /// The switcher's "Show in This Window" and "Open in New Window", by AVD name.
    case showHere(String)
    case openInNewWindow(String)
    case showEmulatorsInFinder
    /// The no-emulator screen's emulators menu: show this AVD with Start ready (or attach).
    case chooseAVD(String)
    /// Opens the Settings window.
    case settings
}

/// Carries a `DeviceCommand` on a menu item.
final class DeviceCommandBox: NSObject {
    let command: DeviceCommand

    init(_ command: DeviceCommand) {
        self.command = command
    }
}

extension NSMenuItem {
    var deviceCommand: DeviceCommand? { (representedObject as? DeviceCommandBox)?.command }
}

/// Builds the device's menu items once for the More menu and once for the menu bar, with the
/// same titles and shortcuts. Ticks and dimming come from `validate`, each time a menu opens.
@MainActor
enum DeviceMenu {
    static func captureItems(target: AnyObject, action: Selector) -> [NSMenuItem] {
        [
            item("Open Link…", .openLink, key: "l", target: target, action: action),
            item(
                "Copy Screenshot", .copyScreenshot, key: "c", modifiers: [.command, .shift], target: target,
                action: action),
            item("Save Screenshot", .saveScreenshot, key: "s", target: target, action: action),
            item("Export Recording as GIF…", .exportGIF, target: target, action: action),
        ]
    }

    static func deviceItems(target: AnyObject, action: Selector) -> [NSMenuItem] {
        let appearance = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearance.submenu = submenu(
            "Appearance",
            DeviceAppearance.allCases.map { item($0.title, .appearance($0), target: target, action: action) })
        let textSize = NSMenuItem(title: "Text Size", action: nil, keyEquivalent: "")
        textSize.submenu = submenu(
            "Text Size", DeviceTextSize.allCases.map { item($0.title, .textSize($0), target: target, action: action) })
        let location = NSMenuItem(title: "Location", action: nil, keyEquivalent: "")
        location.submenu = submenu(
            "Location",
            [
                item("None", .locationNone, target: target, action: action),
                item("Custom…", .locationCustom, target: target, action: action),
            ])
        return [appearance, textSize, location]
    }

    static func toolItems(target: AnyObject, action: Selector) -> [NSMenuItem] {
        [
            item(
                "Inspect Layout", .tool(.inspect), key: "i", modifiers: [.command, .option], target: target,
                action: action),
            item("Measure", .tool(.measure), key: "m", modifiers: [.command, .option], target: target, action: action),
            item(
                "Pick Colour", .tool(.pickColour), key: "p", modifiers: [.command, .option], target: target,
                action: action),
        ]
    }

    static func emulatorItems(target: AnyObject, action: Selector) -> [NSMenuItem] {
        [
            item("Restart Emulator", .restart, target: target, action: action),
            item("Shut Down Emulator", .shutDown, target: target, action: action),
        ]
    }

    static func item(
        _ title: String, _ command: DeviceCommand, key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject, action: Selector, help: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        item.target = target
        item.representedObject = DeviceCommandBox(command)
        item.toolTip = help
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        for item in items { menu.addItem(item) }
        return menu
    }

    /// Settings is another object's (`showSettings:` on the responder chain); until something
    /// answers it, the row stays dimmed in place.
    static let settingsAction = Selector(("showSettings:"))
    static var settingsAvailable: Bool { NSApp.target(forAction: settingsAction) != nil }

    /// More's panel (board 7): quick actions only, in sentence case, with the menu bar's
    /// shortcuts. Device actions stay in place at 45% with no emulator; Settings still works.
    static func morePanelItems(model: PaneModel) -> [PaneMenuItem] {
        let live = model.status == .live
        func action(_ id: String, _ title: String, _ command: DeviceCommand, shortcut: String? = nil, enabled: Bool)
            -> PaneMenuItem
        {
            PaneMenuItem(id: id, title: title, shortcut: shortcut, isEnabled: enabled, command: command)
        }
        func choices<Value: Equatable>(
            _ id: String, _ title: String, _ values: [(String, Value, DeviceCommand)], current: Value?
        ) -> PaneMenuItem {
            PaneMenuItem(
                id: id, title: title, isEnabled: live,
                submenu: values.map { name, value, command in
                    PaneMenuItem(id: id + "." + name, title: name, isChecked: value == current, command: command)
                })
        }
        let hasLocation = model.customLocation != nil
        return [
            action("link", "Open link…", .openLink, shortcut: "⌘L", enabled: live),
            action("copy", "Copy screenshot", .copyScreenshot, shortcut: "⇧⌘C", enabled: live),
            .divider("d1"),
            action("inspect", "Inspect layout", .tool(.inspect), shortcut: "⌥⌘I", enabled: live),
            action("measure", "Measure", .tool(.measure), shortcut: "⌥⌘M", enabled: live),
            action("colour", "Pick colour", .tool(.pickColour), shortcut: "⌥⌘P", enabled: live),
            .divider("d2"),
            choices(
                "appearance", "Appearance", DeviceAppearance.allCases.map { ($0.title, $0, .appearance($0)) },
                current: model.deviceAppearance),
            choices(
                "text", "Text size", DeviceTextSize.allCases.map { ($0.title, $0, .textSize($0)) },
                current: model.deviceTextSize),
            choices(
                "location", "Location", [("None", false, .locationNone), ("Custom…", true, .locationCustom)],
                current: hasLocation),
            .divider("d3"),
            action("restart", "Restart emulator", .restart, enabled: model.emulator != nil),
            action("shutdown", "Shut down emulator", .shutDown, enabled: model.emulator != nil),
            action("settings", "Settings…", .settings, shortcut: "⌘,", enabled: settingsAvailable),
        ]
    }

    /// The emulator switcher's panel (board 13).
    static func switcherPanelItems(entries: [SwitcherEntry]) -> [PaneMenuItem] {
        func row(_ entry: SwitcherEntry, _ command: DeviceCommand, check: Bool?, prefix: String) -> PaneMenuItem {
            PaneMenuItem(
                id: prefix + entry.name, title: entry.name, detail: entry.detail.isEmpty ? nil : entry.detail,
                tag: entry.isRunning ? "Running" : nil, isChecked: check, command: command)
        }
        let others = entries.filter { !$0.isCurrent }
        return [.header("Show in this window")]
            + entries.map { row($0, .showHere($0.name), check: $0.isCurrent, prefix: "here.") }
            + [
                .divider("d1"),
                PaneMenuItem(
                    id: "new", title: "Open in new window", isChecked: false, isEnabled: !others.isEmpty,
                    submenu: others.isEmpty
                        ? nil : others.map { row($0, .openInNewWindow($0.name), check: nil, prefix: "new.") }),
                PaneMenuItem(
                    id: "finder", title: "Show emulators in Finder", isChecked: false, command: .showEmulatorsInFinder),
            ]
    }

    /// The no-emulator screen's emulators menu (board 6).
    static func emulatorsPanelItems(avds: [AvdInfo], running: Set<String>) -> [PaneMenuItem] {
        avds.map { avd in
            PaneMenuItem(
                id: "avd." + avd.name, title: avd.name, detail: avd.profile.summary.isEmpty ? nil : avd.profile.summary,
                tag: running.contains(avd.name) ? "Running" : nil, command: .chooseAVD(avd.name))
        } + [
            .divider("d1"),
            PaneMenuItem(id: "finder", title: "Show emulators in Finder", command: .showEmulatorsInFinder),
        ]
    }

    /// Sets an item's tick from the window's state and says whether it can be chosen now.
    /// With no window, nothing can.
    static func validate(_ item: NSMenuItem, model: PaneModel?) -> Bool {
        guard let command = item.deviceCommand else { return true }
        guard let model else {
            item.state = .off
            return false
        }
        let live = model.status == .live
        switch command {
        case .openLink, .copyScreenshot, .saveScreenshot:
            return live
        case .exportGIF:
            return model.exportTask == nil
        case .appearance(let appearance):
            item.state = live && model.deviceAppearance == appearance ? .on : .off
            return live
        case .textSize(let size):
            item.state = live && model.deviceTextSize == size ? .on : .off
            return live
        case .locationNone:
            item.state = live && model.customLocation == nil ? .on : .off
            return live
        case .locationCustom:
            item.state = live && model.customLocation != nil ? .on : .off
            return live
        case .tool(let tool):
            item.state = model.tools.active == tool ? .on : .off
            return live
        case .restart, .shutDown:
            return model.emulator != nil
        case .showHere, .openInNewWindow, .showEmulatorsInFinder, .chooseAVD:
            return true
        case .settings:
            return DeviceMenu.settingsAvailable
        }
    }
}
