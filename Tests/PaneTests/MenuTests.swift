import AppKit
import Carbon.HIToolbox
import Foundation
import PaneCore
import Testing

@testable import Pane

/// The menu panel's keys: Up and Down move over rows that can be chosen, Return chooses, Right
/// opens a submenu, Left or Esc closes it, Esc closes the menu, a letter jumps to a row.
@MainActor
@Suite struct MenuTests {
    private func menu() -> PaneMenu {
        PaneMenu(
            label: "More", anchor: .more,
            items: [
                PaneMenuItem(id: "link", title: "Open link…", command: .openLink),
                PaneMenuItem(id: "copy", title: "Copy screenshot", isEnabled: false, command: .copyScreenshot),
                .divider("d1"),
                PaneMenuItem(id: "inspect", title: "Inspect layout", command: .tool(.inspect)),
                PaneMenuItem(
                    id: "appearance", title: "Appearance",
                    submenu: [
                        PaneMenuItem(id: "light", title: "Light", isChecked: true, command: .appearance(.light)),
                        PaneMenuItem(id: "dark", title: "Dark", isChecked: false, command: .appearance(.dark)),
                    ]),
                PaneMenuItem(id: "settings", title: "Settings…", command: .settings),
            ], width: 232, submenuWidth: 150)
    }

    @Test func arrowsSkipDividersAndDimmedRowsAndDoNotWrap() {
        let menu = menu()
        #expect(menu.highlighted == nil)
        #expect(menu.handleKey(code: kVK_DownArrow, characters: nil) == .handled)
        #expect(menu.highlighted == 0)
        _ = menu.handleKey(code: kVK_DownArrow, characters: nil)
        #expect(menu.highlighted == 3)
        _ = menu.handleKey(code: kVK_UpArrow, characters: nil)
        #expect(menu.highlighted == 0)
        _ = menu.handleKey(code: kVK_UpArrow, characters: nil)
        #expect(menu.highlighted == 0)
        _ = menu.handleKey(code: kVK_End, characters: nil)
        #expect(menu.highlighted == 5)
        _ = menu.handleKey(code: kVK_DownArrow, characters: nil)
        #expect(menu.highlighted == 5)
        // Up from nothing starts at the bottom.
        let fresh = self.menu()
        _ = fresh.handleKey(code: kVK_UpArrow, characters: nil)
        #expect(fresh.highlighted == 5)
    }

    @Test func returnChoosesAndEscCloses() {
        let menu = menu()
        #expect(menu.handleKey(code: kVK_Return, characters: nil) == .handled)
        _ = menu.handleKey(code: kVK_DownArrow, characters: nil)
        #expect(menu.handleKey(code: kVK_Return, characters: nil) == .choose(.openLink))
        #expect(menu.handleKey(code: kVK_Escape, characters: nil) == .close)
    }

    @Test func submenusOpenWithRightAndCloseWithLeftOrEsc() {
        let menu = menu()
        menu.highlighted = 4
        #expect(menu.handleKey(code: kVK_RightArrow, characters: nil) == .handled)
        #expect(menu.openSubmenu == 4)
        #expect(menu.submenuHighlighted == 0)
        _ = menu.handleKey(code: kVK_DownArrow, characters: nil)
        #expect(menu.submenuHighlighted == 1)
        #expect(menu.handleKey(code: kVK_Return, characters: nil) == .choose(.appearance(.dark)))
        // Esc closes the submenu first, then the menu.
        #expect(menu.handleKey(code: kVK_Escape, characters: nil) == .handled)
        #expect(menu.openSubmenu == nil)
        #expect(menu.handleKey(code: kVK_Escape, characters: nil) == .close)
        _ = menu.handleKey(code: kVK_Return, characters: nil)
        #expect(menu.openSubmenu == 4)
        _ = menu.handleKey(code: kVK_LeftArrow, characters: nil)
        #expect(menu.openSubmenu == nil)
        // Right on a plain row does nothing.
        menu.highlighted = 0
        #expect(menu.handleKey(code: kVK_RightArrow, characters: nil) == .handled)
        #expect(menu.openSubmenu == nil)
    }

    @Test func lettersJumpToTheNextMatchingRow() {
        let menu = menu()
        #expect(menu.handleKey(code: kVK_ANSI_I, characters: "i") == .handled)
        #expect(menu.highlighted == 3)
        _ = menu.handleKey(code: kVK_ANSI_S, characters: "s")
        #expect(menu.highlighted == 5)
        // The dimmed "Copy screenshot" is never landed on.
        #expect(menu.handleKey(code: kVK_ANSI_C, characters: "c") == .ignored)
        #expect(menu.highlighted == 5)
    }

    @Test func pointerHighlightsOpensSubmenusAndClicksChoose() {
        let menu = menu()
        menu.hover(1)
        #expect(menu.highlighted == nil)
        menu.hover(4)
        #expect(menu.openSubmenu == 4)
        menu.hoverSubmenu(1)
        #expect(menu.clickSubmenu(1) == .appearance(.dark))
        menu.hover(0)
        #expect(menu.openSubmenu == nil)
        #expect(menu.click(0) == .openLink)
        #expect(menu.click(1) == nil)
        #expect(menu.click(4) == nil)
        #expect(menu.openSubmenu == 4)
    }

    @Test func rowPositionsFollowTheTokens() {
        let menu = menu()
        #expect(menu.top(ofRow: 0) == 0)
        #expect(menu.top(ofRow: 1) == Theme.Menu.rowHeight + Theme.Menu.rowSpacing)
        let divider = Theme.Menu.dividerHeight + 2 * Theme.Menu.dividerMarginV
        #expect(menu.top(ofRow: 3) == 2 * Theme.Menu.rowHeight + divider + 3 * Theme.Menu.rowSpacing)
        #expect(
            menu.contentHeight == 5 * Theme.Menu.rowHeight + divider + 5 * Theme.Menu.rowSpacing + 2 * Theme.Menu.inset)
    }

    private func entries(_ names: [String], running: [String], current: String?, elsewhere: Set<String> = [])
        -> [SwitcherEntry]
    {
        SwitcherEntry.entries(
            avds: names.map {
                AvdInfo(
                    name: $0, directory: URL(filePath: "/" + $0),
                    profile: DeviceProfile(modelName: "Pixel 8", androidVersion: "Android 16"))
            }, running: running, current: current, shownElsewhere: elsewhere)
    }

    private func switcher(_ entries: [SwitcherEntry]) -> PaneMenu {
        let items = DeviceMenu.switcherPanelItems(entries: entries)
        return PaneMenu(
            label: "Emulators", anchor: .title, items: items, width: 262, submenuWidth: 242,
            highlighted: DeviceMenu.switcherInitialRow(items))
    }

    @Test func switcherRowsFollowBoard20() {
        let items = DeviceMenu.switcherPanelItems(
            entries: entries(["dev_android36", "pixel9_api35"], running: ["dev_android36"], current: "dev_android36"))
        #expect(
            items.map(\.title) == [
                "Show in this window", "dev_android36", "pixel9_api35", "", "Show emulators in Finder",
            ])
        // This window's row: ticked, the selected fill, no button, no Running tag.
        #expect(items[1].isChecked == true && items[1].isSelected && items[1].rowButton == nil && items[1].tag == nil)
        #expect(items[1].glyph == RowGlyph(kind: .phone, state: .running))
        #expect(items[1].detail == "Pixel 8" && items[1].detailTrail == " · Android 16")
        // Another emulator: the button replaces the old submenu.
        #expect(items[2].glyph == RowGlyph(kind: .phone, state: .stopped))
        #expect(
            items[2].rowButton
                == RowButton(
                    title: "Open in new window", accessibilityLabel: "Open pixel9_api35 in new window",
                    command: .openInNewWindow("pixel9_api35")))
        #expect(items.allSatisfy { $0.submenu == nil })
    }

    @Test func switcherWithNoEmulators() {
        let items = DeviceMenu.switcherPanelItems(entries: [])
        #expect(items.map(\.title) == ["Show in this window", "No emulators set up.", "", "Show emulators in Finder"])
        #expect(!items[1].isEnabled)
        #expect(switcher([]).highlighted == nil)
    }

    @Test func switcherOpensOnThisWindowsRowInEveryState() {
        // One emulator, and one that is starting: still this window's row.
        #expect(switcher(entries(["dev_android36"], running: [], current: "dev_android36")).highlighted == 1)
        let starting = SwitcherEntry.entries(
            avds: [
                AvdInfo(name: "a", directory: URL(filePath: "/a")), AvdInfo(name: "b", directory: URL(filePath: "/b")),
            ],
            running: ["b"], starting: ["b"], current: "b", shownElsewhere: [])
        #expect(switcher(starting).highlighted == 2)
    }

    @Test func switcherKeys() {
        let menu = switcher(
            entries(
                ["dev_android36", "pixel9_api35", "tablet_api36"], running: ["dev_android36"], current: "dev_android36",
                elsewhere: ["tablet_api36"]))
        #expect(menu.highlighted == 1)
        // Right does nothing on this window's row (no button).
        #expect(menu.handleKey(code: kVK_RightArrow, characters: nil) == .handled)
        #expect(!menu.isButtonFocused)
        // Command-Return on a row without a button does nothing.
        #expect(menu.handleKey(code: kVK_Return, characters: nil, command: true) == .handled)
        #expect(menu.handleKey(code: kVK_DownArrow, characters: nil) == .handled)
        #expect(menu.highlighted == 2)
        #expect(menu.handleKey(code: kVK_RightArrow, characters: nil) == .handled)
        #expect(menu.isButtonFocused)
        // Left goes back to the row; Esc does too, and only a second Esc closes.
        #expect(menu.handleKey(code: kVK_LeftArrow, characters: nil) == .handled)
        #expect(!menu.isButtonFocused)
        _ = menu.handleKey(code: kVK_RightArrow, characters: nil)
        #expect(menu.handleKey(code: kVK_Escape, characters: nil) == .handled)
        #expect(!menu.isButtonFocused)
        // Return or Space on the button opens a new window; on the row it shows it here.
        _ = menu.handleKey(code: kVK_RightArrow, characters: nil)
        #expect(menu.handleKey(code: kVK_Space, characters: " ") == .choose(.openInNewWindow("pixel9_api35")))
        menu.isButtonFocused = false
        #expect(menu.handleKey(code: kVK_Return, characters: nil) == .choose(.showHere("pixel9_api35")))
        #expect(
            menu.handleKey(code: kVK_Return, characters: nil, command: true)
                == .choose(.openInNewWindow("pixel9_api35")))
        // Down from the button moves the highlight and leaves the button.
        _ = menu.handleKey(code: kVK_RightArrow, characters: nil)
        #expect(menu.handleKey(code: kVK_DownArrow, characters: nil) == .handled)
        #expect(menu.highlighted == 3 && !menu.isButtonFocused)
        // The row shown in another window has no button.
        #expect(menu.handleKey(code: kVK_RightArrow, characters: nil) == .handled)
        #expect(!menu.isButtonFocused)
        // Tab has no stops inside the panel, and other Command keys go to the menu bar.
        #expect(menu.handleKey(code: kVK_Tab, characters: "\t") == .ignored)
        #expect(menu.handleKey(code: kVK_ANSI_S, characters: "s", command: true) == .ignored)
        #expect(menu.handleKey(code: kVK_Escape, characters: nil) == .close)
    }

    @Test func emulatorsMenuShowsTheDotNotTheRunningTag() {
        let items = DeviceMenu.emulatorsPanelItems(
            entries: entries(["dev_android36", "pixel9_api35"], running: ["dev_android36"], current: nil))
        #expect(items.allSatisfy { $0.tag == nil })
        #expect(items[0].glyph == RowGlyph(kind: .phone, state: .running))
        #expect(items[1].glyph == RowGlyph(kind: .phone, state: .stopped))
        #expect(items[0].command == .chooseAVD("dev_android36"))
    }

    // MARK: Device › Switch Emulator… (⌘E)

    /// A window controller on its own preferences, its switcher listing `entries`.
    private func controller(entries: [SwitcherEntry]) -> PaneWindowController {
        let defaults = UserDefaults(suiteName: "PaneMenuTests.\(UUID().uuidString)")!
        let controller = PaneWindowController(settings: PaneSettings(defaults: defaults))
        controller.switcherEntriesOverride = { entries }
        return controller
    }

    private func switchEmulatorItem(target: AnyObject) -> NSMenuItem? {
        DeviceMenu.emulatorItems(target: target, action: #selector(PaneWindowController.runDeviceCommand(_:)))
            .first { $0.deviceCommand == .showSwitcher }
    }

    @Test func switchEmulatorIsInTheDeviceMenuOnCommandE() throws {
        let items = DeviceMenu.emulatorItems(target: NSObject(), action: #selector(NSObject.description))
        let item = try #require(items.first)
        #expect(item.title == "Switch Emulator\u{2026}")
        #expect(item.keyEquivalent == "e")
        #expect(item.keyEquivalentModifierMask == [.command])
        #expect(item.deviceCommand == .showSwitcher)
        #expect(items.map(\.title) == ["Switch Emulator\u{2026}", "Restart Emulator", "Shut Down Emulator"])
    }

    @Test func commandEIsNotTakenByAnotherMenuItem() {
        let target = NSObject()
        let action = #selector(NSObject.description)
        let all =
            DeviceMenu.captureItems(target: target, action: action)
            + DeviceMenu.deviceItems(target: target, action: action)
            + DeviceMenu.toolItems(target: target, action: action)
            + DeviceMenu.emulatorItems(target: target, action: action)
        let commandE = all.filter { $0.keyEquivalent == "e" && $0.keyEquivalentModifierMask == [.command] }
        #expect(commandE.map(\.title) == ["Switch Emulator\u{2026}"])
    }

    @Test func switchEmulatorOpensTheSwitcherOnThisWindowsRow() throws {
        let controller = controller(
            entries: entries(["dev_android36", "pixel9_api35"], running: ["dev_android36"], current: "dev_android36"))
        let item = try #require(switchEmulatorItem(target: controller))
        #expect(controller.validateMenuItem(item))
        controller.runDeviceCommand(item)
        let menu = try #require(controller.model.menu)
        #expect(menu.anchor == .title)
        #expect(menu.highlighted == 1)
        #expect(menu.items[1].title == "dev_android36" && menu.items[1].isSelected)
        // Pressed again, as the trigger does, it closes the switcher.
        controller.runDeviceCommand(item)
        #expect(controller.model.menu == nil)
    }

    @Test func switchEmulatorStaysEnabledWithNoEmulators() throws {
        let controller = controller(entries: [])
        let item = try #require(switchEmulatorItem(target: controller))
        #expect(controller.validateMenuItem(item))
        controller.runDeviceCommand(item)
        let menu = try #require(controller.model.menu)
        #expect(menu.items.map(\.title).contains("No emulators set up."))
        // With no window to act on, the menu bar's item is dimmed like every device command.
        #expect(!DeviceMenu.validate(item, model: nil))
    }
}
