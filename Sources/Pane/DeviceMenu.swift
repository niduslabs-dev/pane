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
    /// The More menu, in the board's order.
    static func moreItems(target: AnyObject, action: Selector) -> [NSMenuItem] {
        captureItems(target: target, action: action) + [.separator()]
            + deviceItems(target: target, action: action) + [.separator()]
            + toolItems(target: target, action: action) + [.separator()]
            + emulatorItems(target: target, action: action)
    }

    static func captureItems(target: AnyObject, action: Selector) -> [NSMenuItem] {
        [
            item("Open Link…", .openLink, key: "l", target: target, action: action),
            item(
                "Copy Screenshot", .copyScreenshot, key: "c", modifiers: [.command, .control], target: target,
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
                "Pick Colour", .tool(.pickColour), key: "c", modifiers: [.command, .option], target: target,
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
        case .showHere, .openInNewWindow, .showEmulatorsInFinder:
            return true
        }
    }
}
