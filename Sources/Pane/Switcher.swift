import PaneCore
import SwiftUI

/// The open emulator switcher: the menu under the title's device name, and a clear layer that
/// closes it on a click anywhere else in the window.
struct SwitcherLayer: View {
    let model: PaneModel
    let entries: [SwitcherEntry]
    @State private var showsNewWindowList = false

    var body: some View {
        let width = model.layout.windowContentSize.width
        let menuWidth = min(Theme.AvdMenu.width, width - 2 * Theme.Switcher.edgeMargin)
        let x = min(model.titleLeadingInset, width - menuWidth - Theme.Switcher.edgeMargin)
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.switcher = nil }
            SwitcherMenu(
                entries: entries, showsNewWindowList: $showsNewWindowList,
                run: { command in
                    model.switcher = nil
                    model.onCommand(command)
                }
            )
            .frame(width: menuWidth)
            .offset(x: x, y: Theme.Window.titleRowHeight - Theme.Switcher.topOverlap)
        }
        .frame(width: width, height: model.layout.windowContentSize.height, alignment: .topLeading)
        .onExitCommand { model.switcher = nil }
    }
}

/// The switcher's menu: "Show in This Window" with every emulator (a tick on this window's, a
/// Running tag on any that is up), "Open in New Window" with its own list, and Show Emulators
/// in Finder.
struct SwitcherMenu: View {
    let entries: [SwitcherEntry]
    @Binding var showsNewWindowList: Bool
    let run: (DeviceCommand) -> Void

    private var others: [SwitcherEntry] { entries.filter { !$0.isCurrent } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.AvdMenu.rowSpacing) {
            SwitcherHeader(text: "Show in This Window")
            ForEach(entries) { entry in
                SwitcherRow(entry: entry, showsCheck: true) { run(.showHere(entry.name)) }
            }
            SwitcherDivider()
            MenuRowButton(label: "Open in New Window", action: { showsNewWindowList.toggle() }) { highlighted in
                HStack(spacing: Theme.AvdMenu.tagGap) {
                    Color.clear.frame(width: Theme.Switcher.checkSlot, height: 1)
                    Text("Open in New Window")
                        .font(Theme.Typeface.menuRow)
                        .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenTitle))
                    Spacer(minLength: 0)
                    Image(systemName: showsNewWindowList ? "chevron.down" : "chevron.right")
                        .font(.system(size: Theme.Switcher.chevronSize, weight: .semibold))
                        .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenMeta))
                        .accessibilityHidden(true)
                }
            }
            .disabled(others.isEmpty)
            .opacity(others.isEmpty ? Theme.Capsule.disabledOpacity : 1)
            // The list opens in place under its row.
            if showsNewWindowList {
                ForEach(others) { entry in
                    SwitcherRow(entry: entry, showsCheck: false, indent: Theme.Switcher.checkSlot) {
                        run(.openInNewWindow(entry.name))
                    }
                }
            }
            SwitcherDivider()
            MenuRowButton(label: "Show Emulators in Finder", action: { run(.showEmulatorsInFinder) }) { highlighted in
                HStack(spacing: Theme.AvdMenu.tagGap) {
                    Color.clear.frame(width: Theme.Switcher.checkSlot, height: 1)
                    Text("Show Emulators in Finder")
                        .font(Theme.Typeface.menuRow)
                        .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenTitle))
                }
            }
        }
        .switcherSurface(label: "Emulators")
    }
}

private struct SwitcherHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Typeface.menuTag)
            .foregroundStyle(Color(nsColor: Theme.Palette.screenMeta))
            .padding(.horizontal, Theme.AvdMenu.rowPaddingH)
            .padding(.vertical, Theme.Switcher.headerPaddingV)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SwitcherDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: Theme.Palette.menuDivider))
            .frame(height: Theme.AvdMenu.dividerHeight)
            .padding(.horizontal, Theme.AvdMenu.rowPaddingH)
            .padding(.vertical, Theme.AvdMenu.dividerPaddingV)
    }
}

/// One emulator: a tick when this window shows it, its name over model and Android version,
/// and a Running tag.
private struct SwitcherRow: View {
    let entry: SwitcherEntry
    let showsCheck: Bool
    var indent: CGFloat = 0
    let action: () -> Void

    var body: some View {
        MenuRowButton(label: accessibilityText, action: action) { highlighted in
            HStack(spacing: Theme.AvdMenu.tagGap) {
                if indent > 0 { Color.clear.frame(width: indent, height: 1) }
                if showsCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: Theme.Switcher.checkSize, weight: .bold))
                        .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenLink))
                        .frame(width: Theme.Switcher.checkSlot)
                        .opacity(entry.isCurrent ? 1 : 0)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Theme.AvdMenu.lineSpacing) {
                    Text(entry.name)
                        .font(Theme.Typeface.menuRow)
                        .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenTitle))
                    Text(entry.detail.isEmpty ? (entry.isRunning ? "Running" : "Not running") : entry.detail)
                        .font(Theme.Typeface.menuDetail)
                        .foregroundStyle(
                            highlighted
                                ? Color.white.opacity(Theme.AvdMenu.highlightedDetailOpacity)
                                : Color(nsColor: Theme.Palette.screenMeta))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if entry.isRunning {
                    Text("Running")
                        .font(Theme.Typeface.menuTag)
                        .foregroundStyle(highlighted ? Color.white : Color(nsColor: Theme.Palette.screenMeta))
                        .padding(.horizontal, Theme.AvdMenu.tagPaddingH)
                        .padding(.vertical, Theme.AvdMenu.tagPaddingV)
                        .overlay(
                            Capsule().strokeBorder(
                                highlighted
                                    ? Color.white.opacity(Theme.AvdMenu.highlightedTagStrokeOpacity)
                                    : Color(nsColor: Theme.Palette.menuHairline),
                                lineWidth: Theme.AvdMenu.hairline))
                }
            }
        }
    }

    /// "dev_android36, Pixel 8 · Android 16, running, shown in this window".
    private var accessibilityText: String {
        ((showsCheck ? [] : ["Open in new window"]) + [entry.name] + (entry.detail.isEmpty ? [] : [entry.detail])
            + (entry.isRunning ? ["running"] : ["not running"])
            + (showsCheck && entry.isCurrent ? ["shown in this window"] : []))
            .joined(separator: ", ")
    }
}

extension View {
    /// The menu surface the emulators menu uses (`Theme.AvdMenu`).
    fileprivate func switcherSurface(label: String) -> some View {
        padding(Theme.AvdMenu.inset)
            .frame(width: Theme.AvdMenu.width, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.AvdMenu.radius, style: .continuous)
                    .fill(Color(nsColor: Theme.Palette.menuSurface))
                    .shadow(
                        color: .black.opacity(Theme.AvdMenu.shadowOpacity), radius: Theme.AvdMenu.shadowRadius,
                        y: Theme.AvdMenu.shadowY)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.AvdMenu.radius, style: .continuous)
                    .strokeBorder(Color(nsColor: Theme.Palette.menuHairline), lineWidth: Theme.AvdMenu.hairline)
            )
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }
}
