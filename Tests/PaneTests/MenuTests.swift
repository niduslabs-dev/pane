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

    @Test func switcherRowsFollowTheBoard() {
        let entries = SwitcherEntry.entries(
            avds: [
                AvdInfo(
                    name: "dev_android36", directory: URL(filePath: "/a"),
                    profile: DeviceProfile(modelName: "Pixel 8", androidVersion: "Android 16"))
            ], running: ["dev_android36"], current: "dev_android36", shownElsewhere: [])
        let items = DeviceMenu.switcherPanelItems(entries: entries)
        #expect(
            items.map(\.title) == [
                "Show in this window", "dev_android36", "", "Open in new window", "Show emulators in Finder",
            ])
        #expect(items[1].isChecked == true)
        #expect(items[1].tag == "Running")
        #expect(items[1].detail == "Pixel 8 · Android 16")
        // With one emulator, Open in new window is dimmed in place.
        #expect(!items[3].isEnabled)
        #expect(items[3].submenu == nil)
    }
}
