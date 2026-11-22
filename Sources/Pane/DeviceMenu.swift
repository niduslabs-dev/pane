import AppKit
import Carbon.HIToolbox
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
    /// Fold or Unfold (⇧⌘F, board 28): to the fold posture, or back to Open from it.
    case fold
    /// One of a foldable's postures, from the Posture submenu.
    case posture(DevicePosture)
    case tool(PaneTool)
    case restart
    case shutDown
    /// The switcher's "Show in This Window" and "Open in New Window", by AVD name.
    case showHere(String)
    case openInNewWindow(String)
    case showEmulatorsInFinder
    /// Opens the emulator switcher under the title, as a click on the device name does: the
    /// keyboard's way in, since Tab in the window belongs to the device.
    case showSwitcher
    /// The no-emulator screen's emulators menu: show this AVD with Start ready (or attach).
    case chooseAVD(String)
    /// Opens the Settings window.
    case settings
}

extension DeviceCommand {
    /// Fold and the postures: shown only for a foldable.
    var isFoldGroup: Bool {
        switch self {
        case .fold, .posture: true
        default: false
        }
    }
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
                item("Default", .locationNone, target: target, action: action),
                item("Custom…", .locationCustom, target: target, action: action),
            ])
        return [appearance, textSize, location]
    }

    /// The fold group (board 28): Fold (⇧⌘F) and Posture with every posture. `validate` hides
    /// the postures this device doesn't have, and Fold on anything that isn't a foldable;
    /// `FoldGroupVisibility` hides the Posture item and the group's separator.
    static func foldItems(target: AnyObject, action: Selector) -> [NSMenuItem] {
        let fold = item(foldTitle, .fold, key: foldKey, modifiers: [.command, .shift], target: target, action: action)
        let posture = NSMenuItem(title: postureTitle, action: nil, keyEquivalent: "")
        posture.submenu = submenu(
            postureTitle,
            DevicePosture.allCases.map { item($0.menuBarTitle, .posture($0), target: target, action: action) })
        return [fold, posture]
    }

    static let foldTitle = "Fold"
    static let postureTitle = "Posture"
    /// ⇧⌘F: free in Pane and macOS (⌃⌘F is full screen, ⌘F is kept for a future Find).
    static let foldKey = "f"
    static let foldShortcut = "⇧⌘F"

    /// True for ⇧⌘F. The window keeps it when the menu bar doesn't take it (no foldable in
    /// front), so it does nothing and doesn't beep.
    static func isFoldShortcut(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == kVK_ANSI_F && modifiers.intersection([.command, .shift, .option, .control]) == [.command, .shift]
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
            item(switchEmulatorTitle, .showSwitcher, key: "e", target: target, action: action),
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

    /// Settings is the app delegate's (`showSettings:`), sent to it directly, so the row works
    /// in every state, with or without an emulator (board 7).
    static let settingsAction = Selector(("showSettings:"))

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
        let foldGroup = foldPanelItems(fold: model.fold, posture: model.posture, live: live)
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
                "location", "Location", [("Default", false, .locationNone), ("Custom…", true, .locationCustom)],
                current: hasLocation),
            .divider("d3"),
        ] + foldGroup + [
            action("restart", "Restart emulator", .restart, enabled: model.emulator != nil),
            action("shutdown", "Shut down emulator", .shutDown, enabled: model.emulator != nil),
            action("settings", "Settings…", .settings, shortcut: "⌘,", enabled: true),
        ]
    }

    /// More's fold group (board 28), under Location: Fold (Unfold at the fold posture) and
    /// Posture with only this device's postures, the current one ticked, then a divider. Before
    /// the first posture notification there's no tick and the item reads Fold. None for a
    /// device that isn't a foldable; dimmed with the other device rows when it isn't running.
    static func foldPanelItems(fold: FoldProfile?, posture: DevicePosture?, live: Bool) -> [PaneMenuItem] {
        guard let fold else { return [] }
        let current = live ? posture : nil
        return [
            PaneMenuItem(
                id: "fold", title: fold.foldTitle(current: current), shortcut: foldShortcut, isEnabled: live,
                command: .fold),
            PaneMenuItem(
                id: "posture", title: postureTitle, isEnabled: live,
                submenu: fold.postures.map { posture in
                    PaneMenuItem(
                        id: "posture.\(posture.rawValue)", title: posture.title, isChecked: posture == current,
                        command: .posture(posture))
                }),
            .divider("d4"),
        ]
    }

    /// The emulator switcher's panel (board 20): one row per emulator with its device glyph and
    /// status dot, this window's ticked on the selected fill, and Open in new window as a button
    /// on the highlighted row of an emulator with no window. No emulators: one disabled line.
    static func switcherPanelItems(entries: [SwitcherEntry]) -> [PaneMenuItem] {
        let rows =
            entries.isEmpty
            ? [PaneMenuItem(id: "none", title: noEmulatorsSetUp, isChecked: false, isEnabled: false)]
            : entries.map { entry in
                let line = entry.secondLine
                return PaneMenuItem(
                    id: "here." + entry.name, title: entry.name, detail: line.lead.isEmpty ? nil : line.lead,
                    detailTrail: line.trail.isEmpty ? nil : line.trail,
                    glyph: RowGlyph(kind: entry.kind, state: entry.state),
                    isSelected: entry.isCurrent,
                    rowButton: entry.opensInNewWindow
                        ? RowButton(
                            title: openInNewWindow, accessibilityLabel: "Open \(entry.name) in new window",
                            command: .openInNewWindow(entry.name))
                        : nil,
                    accessibilityText: entry.accessibilityText, isChecked: entry.isCurrent,
                    command: .showHere(entry.name))
            }
        return [.header("Show in this window")] + rows + [
            .divider("d1"),
            PaneMenuItem(
                id: "finder", title: "Show emulators in Finder", isChecked: false, command: .showEmulatorsInFinder),
        ]
    }

    /// The row the switcher opens on: this window's emulator.
    static func switcherInitialRow(_ items: [PaneMenuItem]) -> Int? {
        items.firstIndex { $0.isSelected }
    }

    static let openInNewWindow = "Open in new window"
    /// Device › Switch Emulator… (⌘E).
    static let switchEmulatorTitle = "Switch Emulator\u{2026}"
    /// The no-emulator screen's own words.
    static let noEmulatorsSetUp = "No emulators set up."

    /// The no-emulator screen's emulators menu (board 6): the same glyph and status dot as the
    /// switcher, in place of the Running tag.
    static func emulatorsPanelItems(entries: [SwitcherEntry]) -> [PaneMenuItem] {
        entries.map { entry in
            PaneMenuItem(
                id: "avd." + entry.name, title: entry.name, detail: entry.detail.isEmpty ? nil : entry.detail,
                glyph: RowGlyph(kind: entry.kind, state: entry.state), accessibilityText: entry.accessibilityText,
                command: .chooseAVD(entry.name))
        } + [
            .divider("d1"),
            PaneMenuItem(id: "finder", title: "Show emulators in Finder", command: .showEmulatorsInFinder),
        ]
    }

    /// The menu bar's fold group for the window in front: hidden unless it shows a foldable
    /// (and each posture unless the device has it), so ⇧⌘F does nothing elsewhere.
    static func validateFold(
        _ item: NSMenuItem, command: DeviceCommand, fold: FoldProfile?, posture: DevicePosture?, live: Bool
    ) -> Bool {
        let current = live ? posture : nil
        switch command {
        case .fold:
            item.isHidden = fold == nil
            item.title = fold?.foldTitle(current: current) ?? foldTitle
            return live && fold != nil
        case .posture(let value):
            let listed = fold?.postures.contains(value) ?? false
            item.isHidden = !listed
            item.state = listed && current == value ? .on : .off
            return live && listed
        default:
            return false
        }
    }

    /// Sets an item's tick from the window's state and says whether it can be chosen now.
    /// With no window, nothing can.
    static func validate(_ item: NSMenuItem, model: PaneModel?) -> Bool {
        guard let command = item.deviceCommand else { return true }
        guard let model else {
            item.state = .off
            if command.isFoldGroup { item.isHidden = true }
            return false
        }
        let live = model.status == .live
        switch command {
        case .fold, .posture:
            return validateFold(item, command: command, fold: model.fold, posture: model.posture, live: live)
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
        case .showSwitcher:
            // Enabled with no emulators too: the panel then says "No emulators set up."
            return true
        case .settings:
            return true
        }
    }
}
