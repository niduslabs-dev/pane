import AppKit
import Carbon.HIToolbox
import Observation
import PaneCore
import SwiftUI

/// One row of a Pane menu panel.
struct PaneMenuItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case action
        /// A small label over a group of rows ("Show in this window").
        case header
        case divider
    }

    var id: String
    var kind: Kind = .action
    var title = ""
    /// A second line under the title (an emulator's model and Android version).
    var detail: String?
    /// Shown at the row's right in the menu-bar style ("⌥⌘I"). The menu bar item handles the keys.
    var shortcut: String?
    /// A small outlined tag at the row's right ("Running").
    var tag: String?
    /// Ticked or not; nil leaves the row without a tick slot.
    var isChecked: Bool?
    var isEnabled = true
    var command: DeviceCommand?
    var submenu: [PaneMenuItem]?

    var isChoosable: Bool { kind == .action && isEnabled }

    var height: CGFloat {
        switch kind {
        case .action: detail == nil ? Theme.Menu.rowHeight : Theme.Menu.tallRowHeight
        case .header: Theme.Menu.headerHeight
        case .divider: Theme.Menu.dividerHeight + 2 * Theme.Menu.dividerMarginV
        }
    }

    static func divider(_ id: String) -> PaneMenuItem { PaneMenuItem(id: id, kind: .divider) }
    static func header(_ title: String) -> PaneMenuItem {
        PaneMenuItem(id: "header." + title, kind: .header, title: title)
    }
}

/// An open menu panel: its rows, where it hangs, and which row the pointer or the keys are on.
/// Up and Down move, Return or Space chooses, Right opens a submenu, Left or Esc closes it, Esc
/// closes the menu, and typing a letter jumps to the next row that starts with it.
@MainActor
@Observable
final class PaneMenu {
    enum Anchor: Equatable {
        /// Under More, right edges aligned.
        case more
        /// Under the title's device name, left edges aligned.
        case title
        /// Centred under a point in the window (the "Choose another emulator" link).
        case below(CGPoint)
    }

    let label: String
    let anchor: Anchor
    let items: [PaneMenuItem]
    let width: CGFloat
    let submenuWidth: CGFloat
    /// The highlighted row, by index, or nil (opened with the pointer, nothing is until it
    /// reaches a row).
    var highlighted: Int?
    /// The row whose submenu is open, and the highlighted row inside it.
    var openSubmenu: Int?
    var submenuHighlighted: Int?

    init(label: String, anchor: Anchor, items: [PaneMenuItem], width: CGFloat, submenuWidth: CGFloat) {
        self.label = label
        self.anchor = anchor
        self.items = items
        self.width = width
        self.submenuWidth = submenuWidth
    }

    enum KeyResult: Equatable {
        /// Not a menu key: nothing happened (but the key still doesn't reach the device).
        case ignored
        case handled
        case close
        case choose(DeviceCommand)
    }

    var submenuItems: [PaneMenuItem] { openSubmenu.flatMap { items[$0].submenu } ?? [] }

    /// From the top of the panel's rows to the top of a row.
    func top(ofRow index: Int) -> CGFloat {
        items.prefix(index).reduce(0) { $0 + $1.height + Theme.Menu.rowSpacing }
    }

    var contentHeight: CGFloat { Self.height(of: items) }

    static func height(of items: [PaneMenuItem]) -> CGFloat {
        items.reduce(0) { $0 + $1.height } + CGFloat(max(items.count - 1, 0)) * Theme.Menu.rowSpacing
            + 2 * Theme.Menu.inset
    }

    /// The pointer came over a row (or left the panel: nil). A row with a submenu opens it.
    func hover(_ index: Int?) {
        guard let index else { return }
        guard items[index].isChoosable else { return }
        highlighted = index
        if items[index].submenu != nil {
            if openSubmenu != index {
                openSubmenu = index
                submenuHighlighted = nil
            }
        } else {
            openSubmenu = nil
            submenuHighlighted = nil
        }
    }

    func hoverSubmenu(_ index: Int?) {
        guard let index, submenuItems.indices.contains(index), submenuItems[index].isChoosable else { return }
        submenuHighlighted = index
    }

    /// The command for a clicked row, or nil when the click opened a submenu or hit nothing.
    func click(_ index: Int) -> DeviceCommand? {
        guard items[index].isChoosable else { return nil }
        if items[index].submenu != nil {
            openSubmenu = openSubmenu == index ? nil : index
            highlighted = index
            submenuHighlighted = nil
            return nil
        }
        return items[index].command
    }

    func clickSubmenu(_ index: Int) -> DeviceCommand? {
        guard submenuItems.indices.contains(index), submenuItems[index].isChoosable else { return nil }
        return submenuItems[index].command
    }

    func handleKey(code: Int, characters: String?) -> KeyResult {
        if openSubmenu != nil {
            switch code {
            case kVK_DownArrow: submenuHighlighted = Self.next(from: submenuHighlighted, in: submenuItems, by: 1)
            case kVK_UpArrow: submenuHighlighted = Self.next(from: submenuHighlighted, in: submenuItems, by: -1)
            case kVK_LeftArrow, kVK_Escape:
                openSubmenu = nil
                submenuHighlighted = nil
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
                guard let index = submenuHighlighted, let command = clickSubmenu(index) else { return .handled }
                return .choose(command)
            default: return .ignored
            }
            return .handled
        }
        switch code {
        case kVK_DownArrow: highlighted = Self.next(from: highlighted, in: items, by: 1)
        case kVK_UpArrow: highlighted = Self.next(from: highlighted, in: items, by: -1)
        case kVK_Home: highlighted = Self.next(from: nil, in: items, by: 1)
        case kVK_End: highlighted = Self.next(from: nil, in: items, by: -1)
        case kVK_Escape: return .close
        case kVK_RightArrow, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            guard let index = highlighted, items[index].isChoosable else { return .handled }
            if items[index].submenu != nil {
                openSubmenu = index
                submenuHighlighted = Self.next(from: nil, in: submenuItems, by: 1)
                return .handled
            }
            if code == kVK_RightArrow { return .handled }
            return items[index].command.map(KeyResult.choose) ?? .handled
        default:
            guard let letter = characters?.lowercased().first, letter.isLetter || letter.isNumber else {
                return .ignored
            }
            let count = items.count
            let start = (highlighted ?? -1) + 1
            for offset in 0..<count {
                let index = (start + offset) % count
                if items[index].isChoosable, items[index].title.lowercased().first == letter {
                    highlighted = index
                    return .handled
                }
            }
            return .ignored
        }
        return .handled
    }

    /// The next row that can be chosen, without wrapping; from nil, the first (or the last
    /// going up).
    static func next(from current: Int?, in items: [PaneMenuItem], by step: Int) -> Int? {
        var index = current.map { $0 + step } ?? (step > 0 ? 0 : items.count - 1)
        while items.indices.contains(index) {
            if items[index].isChoosable { return index }
            index += step
        }
        return current
    }
}

/// The open menu over the window: the panel, its submenu, and a clear layer that closes it on
/// a click anywhere else.
struct PaneMenuLayer: View {
    let model: PaneModel
    let menu: PaneMenu

    var body: some View {
        let size = model.layout.windowContentSize
        let origin = panelOrigin(in: size)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.closeMenu() }
                .accessibilityHidden(true)
            PaneMenuPanel(
                label: menu.label, items: menu.items, highlighted: menu.highlighted, openRow: menu.openSubmenu,
                hover: { menu.hover($0) },
                click: { index in if let command = menu.click(index) { model.choose(command) } }
            )
            .frame(width: menu.width)
            .offset(x: origin.x, y: origin.y)
            if let row = menu.openSubmenu, let items = menu.items[row].submenu {
                let subOrigin = submenuOrigin(row: row, itemCount: items, panel: origin, in: size)
                PaneMenuPanel(
                    label: menu.items[row].title, items: items, highlighted: menu.submenuHighlighted, openRow: nil,
                    hover: { menu.hoverSubmenu($0) },
                    click: { index in if let command = menu.clickSubmenu(index) { model.choose(command) } }
                )
                .frame(width: menu.submenuWidth)
                .offset(x: subOrigin.x, y: subOrigin.y)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func panelOrigin(in size: CGSize) -> CGPoint {
        let margin = Theme.Menu.edgeMargin
        let point: CGPoint
        switch menu.anchor {
        case .more:
            point = CGPoint(x: size.width - Theme.Menu.moreTrailing - menu.width, y: Theme.Menu.moreTop)
        case .title:
            point = CGPoint(x: model.titleLeadingInset - Theme.TitleButton.paddingH, y: Theme.Menu.switcherTop)
        case .below(let anchor):
            point = CGPoint(x: anchor.x - menu.width / 2, y: anchor.y)
        }
        return CGPoint(
            x: min(max(point.x, margin), max(margin, size.width - menu.width - margin)),
            y: min(point.y, max(Theme.Window.titleRowHeight, size.height - menu.contentHeight - margin)))
    }

    /// More's submenus open to the left of the menu, level with their row; the switcher's
    /// opens over the menu, right of its edge and under its row (board 13).
    private func submenuOrigin(row: Int, itemCount items: [PaneMenuItem], panel: CGPoint, in size: CGSize) -> CGPoint {
        let margin = Theme.Menu.edgeMargin
        let rowTop = panel.y + Theme.Menu.inset + menu.top(ofRow: row)
        var point: CGPoint
        if menu.anchor == .more {
            point = CGPoint(x: panel.x - Theme.Menu.submenuGap - menu.submenuWidth, y: rowTop - Theme.Menu.inset)
        } else {
            point = CGPoint(
                x: panel.x + Theme.Menu.switcherSubmenuShift,
                y: rowTop + menu.items[row].height + Theme.Menu.switcherSubmenuDrop)
        }
        point.x = min(max(point.x, margin), max(margin, size.width - menu.submenuWidth - margin))
        point.y = min(point.y, max(margin, size.height - PaneMenu.height(of: items) - margin))
        return point
    }
}

/// A menu panel as on the kit board: a raised surface with a hairline, rows 32 pt tall (44 with
/// a second line), the moss highlight under the pointer or the keys, ticks, shortcuts, tags
/// and submenu chevrons.
/// `surfaceMenu` under a menu or the inspect card. These sit inside Pane's window, over the
/// device, so dark's 96% ink sits on a within-window blur (`.hudWindow`): the device's own text
/// never shows through sharp. Solid under Reduce Transparency or Increase Contrast. Light is
/// solid white already.
struct MenuSurface<S: Shape>: View {
    let shape: S
    var fill = Theme.Palette.menuPanel
    var solidFill = Theme.Palette.menuPanelSolid
    /// The inspect card is ink in both modes, so it blurs in light too.
    var blursInLight = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let blurs = (colorScheme == .dark || blursInLight) && !reduceTransparency && contrast != .increased
        ZStack {
            if blurs { WithinWindowBlur() }
            shape.fill(Color(nsColor: blurs ? fill : solidFill))
        }
        .compositingGroup()
        .clipShape(shape)
    }
}

/// Blurs what is under it in the same window (the device's frames) with the menu material.
private struct WithinWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct PaneMenuPanel: View {
    let label: String
    let items: [PaneMenuItem]
    let highlighted: Int?
    let openRow: Int?
    let hover: (Int?) -> Void
    let click: (Int) -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let hairline = Kit.hairlineWidth(Theme.Menu.hairline, contrast: contrast)
        VStack(alignment: .leading, spacing: Theme.Menu.rowSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                switch item.kind {
                case .header:
                    Text(item.title)
                        .font(Theme.Typeface.menuHeader)
                        .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                        .padding(.horizontal, Theme.Menu.rowPaddingH)
                        .padding(.bottom, Theme.Menu.headerBottomPadding)
                        .frame(height: item.height, alignment: .bottomLeading)
                        .accessibilityAddTraits(.isHeader)
                case .divider:
                    Rectangle()
                        .fill(Color(nsColor: Theme.Palette.menuPanelHairline))
                        .frame(height: Kit.hairlineWidth(Theme.Menu.dividerHeight, contrast: contrast))
                        .padding(.horizontal, Theme.Menu.rowPaddingH)
                        .padding(.vertical, Theme.Menu.dividerMarginV)
                        .accessibilityHidden(true)
                case .action:
                    PaneMenuRow(
                        item: item, isHighlighted: highlighted == index || openRow == index,
                        hover: { hover($0 ? index : nil) }, click: { click(index) })
                }
            }
        }
        .padding(Theme.Menu.inset)
        .background(
            MenuSurface(shape: RoundedRectangle(cornerRadius: Theme.Menu.radius, style: .continuous))
                .shadow(
                    color: .black.opacity(Theme.Menu.shadowOpacity), radius: Theme.Menu.shadowRadius,
                    y: Theme.Menu.shadowY)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Menu.radius, style: .continuous)
                .strokeBorder(Color(nsColor: Theme.Palette.menuPanelHairline), lineWidth: hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label) menu")
    }
}

private struct PaneMenuRow: View {
    let item: PaneMenuItem
    let isHighlighted: Bool
    let hover: (Bool) -> Void
    let click: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: click) {
            HStack(spacing: Theme.Menu.rowGap) {
                if let isChecked = item.isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: Theme.Menu.checkSize, weight: .bold))
                        .foregroundStyle(Color(nsColor: Theme.Palette.menuCheck))
                        .frame(width: Theme.Menu.checkSlot)
                        .opacity(isChecked ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: Theme.Menu.lineSpacing) {
                    Text(item.title)
                        .font(Theme.Typeface.menuRow)
                        .foregroundStyle(Color(nsColor: Theme.Palette.text))
                    if let detail = item.detail {
                        Text(detail)
                            .font(Theme.Typeface.menuDetail)
                            .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                    }
                }
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer(minLength: 0)
                if let tag = item.tag {
                    Text(tag)
                        .font(Theme.Typeface.menuTag)
                        .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                        .padding(.horizontal, Theme.Menu.tagPaddingH)
                        .padding(.vertical, Theme.Menu.tagPaddingV)
                        .overlay(
                            Capsule().strokeBorder(
                                Color(nsColor: Theme.Palette.menuPanelHairline),
                                lineWidth: Kit.hairlineWidth(Theme.Menu.hairline, contrast: contrast)))
                }
                if let shortcut = item.shortcut {
                    Text(shortcut)
                        .font(Theme.Typeface.menuShortcut)
                        .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                }
                if item.submenu != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: Theme.Menu.chevronSize, weight: .semibold))
                        .foregroundStyle(Color(nsColor: Theme.Palette.textSecondary))
                }
            }
            .padding(.horizontal, Theme.Menu.rowPaddingH)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: item.height)
            .background(
                RoundedRectangle(cornerRadius: Theme.Menu.rowRadius, style: .continuous)
                    .fill(Color(nsColor: Theme.Palette.menuHighlight).opacity(isHighlighted && item.isEnabled ? 1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plainRow)
        .disabled(!item.isEnabled)
        .onHover(perform: hover)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(item.isChecked == true ? "checked" : "")
        .accessibilityAddTraits(item.isChecked == true ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(item.submenu == nil ? "" : "Opens a submenu.")
    }

    /// "dev_android36, Pixel 8 · Android 16, Running".
    private var accessibilityText: String {
        [item.title, item.detail, item.tag].compactMap { $0 }.joined(separator: ", ")
    }
}
