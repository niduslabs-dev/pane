import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

// The Nidus select (SelectMenu board): a paper control that opens its own menu in a
// borderless child panel, right edges aligned under the select. It replaces `NSMenu`, which
// is translucent, wider than the control, left-aligned and generic.
//
// The panel never becomes key, so keyboard focus stays on the select the whole time and
// is there again when the menu closes. While the menu is open, a local event monitor sends
// the keys to it, and clicks outside it close it.

/// One choice in a `NidusSelect`.
struct SelectOption<Value: Hashable> {
    let value: Value
    /// Shown in the select and in the menu.
    let label: String
    /// What VoiceOver reads for this choice. For a folder, the label and its full path.
    let accessibilityLabel: String
    var icon: NSImage?
    /// Paths use the monospaced system font; ordinary words the body font.
    var monospaced = false
    /// Further names typeahead matches, besides the label.
    var keywords: [String] = []

    /// The non-generic part the menu draws.
    var row: SelectMenuRow {
        SelectMenuRow(
            label: label, accessibilityLabel: accessibilityLabel, icon: icon, monospaced: monospaced,
            names: SelectMenuRow.typeaheadNames(label: label, keywords: keywords))
    }
}

/// A menu row as the menu draws and reads it.
struct SelectMenuRow {
    let label: String
    let accessibilityLabel: String
    let icon: NSImage?
    let monospaced: Bool
    /// Lowercased names typeahead matches against.
    let names: [String]

    /// The label, the label without a leading `/` or `~/` (so "a" finds "/Applications"),
    /// and the keywords, lowercased.
    static func typeaheadNames(label: String, keywords: [String]) -> [String] {
        var names = [label]
        for prefix in ["~/", "/"] where label.hasPrefix(prefix) {
            names.append(String(label.dropFirst(prefix.count)))
            break
        }
        names += keywords
        return names.map { $0.lowercased() }
    }
}

// MARK: - Keys and the menu's state

/// The keys a select and its menu answer to.
enum SelectKey: Equatable {
    case up
    case down
    case home
    case end
    case confirm
    case space
    case escape
    case tab
    /// Printable text, for typeahead.
    case text(String)

    /// The key for a key-down event, or nil for one the select leaves alone (shortcuts with
    /// Command or Control, function keys).
    init?(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) {
        if !modifiers.intersection([.command, .control]).isEmpty { return nil }
        switch Int(keyCode) {
        case kVK_UpArrow: self = .up
        case kVK_DownArrow: self = .down
        case kVK_Home, kVK_PageUp: self = .home
        case kVK_End, kVK_PageDown: self = .end
        case kVK_Return, kVK_ANSI_KeypadEnter: self = .confirm
        case kVK_Space: self = .space
        case kVK_Escape: self = .escape
        case kVK_Tab: self = .tab
        default:
            guard let characters, !characters.isEmpty,
                characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                characters.unicodeScalars.allSatisfy({ $0.value < 0xF700 || $0.value > 0xF8FF })
            else { return nil }
            self = .text(characters)
        }
    }

    /// Whether this key opens a closed select: Space, Return and the arrows, as a native
    /// pop-up button does.
    var opensSelect: Bool { [.space, .confirm, .down, .up].contains(self) }
}

/// The open menu's state: which row is highlighted, and typeahead. Pure, so the keyboard
/// rules are unit tested.
struct SelectMenuState: Equatable {
    /// What a key did.
    enum Outcome: Equatable {
        /// Nothing changed; the key is still swallowed while the menu is open.
        case ignored
        case highlighted(Int)
        case choose(Int)
        case close
        /// Close, and let the key go on to the window (Tab moves focus on).
        case closeAndPass
    }

    let names: [[String]]
    let selected: Int?
    private(set) var highlighted: Int?
    private var typed = ""
    private var lastTyped: TimeInterval = -.infinity

    /// Opened from the keyboard, the selected row starts highlighted, so Return keeps it.
    /// Opened with the pointer, nothing is until the pointer reaches a row.
    init(names: [[String]], selected: Int?, highlightsSelected: Bool = true) {
        self.names = names
        self.selected = selected.flatMap { names.indices.contains($0) ? $0 : nil }
        highlighted = highlightsSelected ? self.selected : nil
    }

    /// The pointer moved onto a row, or off them all (nil).
    mutating func hover(_ index: Int?) {
        highlighted = index.flatMap { names.indices.contains($0) ? $0 : nil }
    }

    mutating func handle(_ key: SelectKey, at time: TimeInterval) -> Outcome {
        guard !names.isEmpty else { return key == .tab ? .closeAndPass : .close }
        switch key {
        case .down: return move(to: highlighted.map { min($0 + 1, names.count - 1) } ?? selected ?? 0)
        case .up: return move(to: highlighted.map { max($0 - 1, 0) } ?? selected ?? names.count - 1)
        case .home: return move(to: 0)
        case .end: return move(to: names.count - 1)
        case .confirm: return highlighted.map { .choose($0) } ?? .close
        case .space:
            // Mid-word, a space is part of the name being typed.
            if !typed.isEmpty, time - lastTyped <= Kit.Select.typeaheadWindow {
                return type(" ", at: time)
            }
            return highlighted.map { .choose($0) } ?? .close
        case .escape: return .close
        case .tab: return .closeAndPass
        case .text(let text): return type(text, at: time)
        }
    }

    private mutating func move(to index: Int) -> Outcome {
        typed = ""
        highlighted = index
        return .highlighted(index)
    }

    /// Adds to the typed search (it starts over after a pause) and highlights the first row
    /// from the current one whose name starts with it. A single letter starts after the
    /// current row, so pressing it again steps through the rows that share it.
    private mutating func type(_ text: String, at time: TimeInterval) -> Outcome {
        if time - lastTyped > Kit.Select.typeaheadWindow { typed = "" }
        lastTyped = time
        typed += text.lowercased()
        let start = highlighted.map { typed.count == 1 ? $0 + 1 : $0 } ?? 0
        for step in 0..<names.count {
            let index = (start + step) % names.count
            if names[index].contains(where: { $0.hasPrefix(typed) }) {
                highlighted = index
                return .highlighted(index)
            }
        }
        return .ignored
    }
}

// MARK: - Folders

/// How a folder shows in a select: its path with the home folder as `~`, and its Finder icon.
enum FolderDisplay {
    /// "/Applications", "~/Applications": the home folder becomes `~`, and there's no
    /// trailing slash.
    static func path(_ url: URL, home: URL) -> String {
        let path = plainPath(url)
        let homePath = plainPath(home)
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    /// The full path, without a trailing slash.
    static func plainPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The folder whose Finder icon stands for `url`: the folder itself; for an
    /// Applications folder that doesn't exist yet (~/Applications on a new Mac), the
    /// system's Applications folder; otherwise nil, for a generic folder icon.
    static func iconPath(for url: URL, exists: (String) -> Bool) -> String? {
        let path = plainPath(url)
        if exists(path) { return path }
        if url.lastPathComponent == systemApplications.lastPathComponent, exists(systemApplications.path) {
            return systemApplications.path
        }
        return nil
    }

    private static let systemApplications = URL(filePath: "/Applications", directoryHint: .isDirectory)

    /// The Finder icon for `url` (see `iconPath`). Read once per folder.
    @MainActor
    static func icon(for url: URL) -> NSImage {
        let key = plainPath(url)
        if let cached = icons[key] { return cached }
        let icon =
            iconPath(for: url) { FileManager.default.fileExists(atPath: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .folder)
        icons[key] = icon
        return icon
    }

    @MainActor private static var icons: [String: NSImage] = [:]
}

// MARK: - The select

/// The kit's select: paper, radius 8, 28 tall and at least 144 wide, showing the chosen
/// option's icon and label. Opens its menu (`SelectMenuController`) on a press, or with
/// Space, Return or an arrow when focused; Tab reaches it even with macOS Keyboard
/// navigation off. VoiceOver reads it as a button named `label` whose value is the choice.
struct NidusSelect<Value: Hashable>: View {
    let label: String
    let selection: Value
    let options: [SelectOption<Value>]
    let onSelect: (Value) -> Void

    init(
        label: String, selection: Value, options: [SelectOption<Value>], onSelect: @escaping (Value) -> Void
    ) {
        self.label = label
        self.selection = selection
        self.options = options
        self.onSelect = onSelect
    }

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var anchor = ViewAnchor()
    @State private var menu = SelectMenuHandle()
    @State private var isHovered = false
    @State private var isPressing = false

    private var current: SelectOption<Value>? { options.first { $0.value == selection } }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.Select.cornerRadius, style: .continuous)
        HStack(spacing: Kit.Select.spacing) {
            if let current {
                SelectValueLabel(row: current.row, iconSpacing: Kit.Select.iconSpacing)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: Kit.Select.chevron, weight: .bold))
                .foregroundStyle(Kit.Colour.secondaryText)
        }
        .padding(.leading, Kit.Select.leading)
        .padding(.trailing, Kit.Select.trailing)
        .frame(minWidth: Kit.Select.minWidth, minHeight: Kit.Select.height, maxHeight: Kit.Select.height)
        .fixedSize()
        .background {
            shape.fill(Kit.Colour.paper)
                .overlay { shape.fill(Color.black.opacity(isHovered ? Kit.Button.hoverShade : 0)) }
        }
        .overlay { Hairline(shape: shape, width: Kit.Button.hairline) }
        .overlay {
            // Only in the tree while the menu is open, like `FocusRing`, so the select's
            // accessibility frame stays the select's own.
            if menu.isOpen {
                shape.inset(by: -Kit.Select.openRing / 2)
                    .stroke(Kit.Colour.openRing, lineWidth: Kit.Select.openRing)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .background(AnchorView(anchor: anchor))
        .contentShape(shape)
        .gesture(press, including: isEnabled ? .all : .none)
        .onHover { hovering in withAnimation(Kit.Motion.hover) { isHovered = hovering && isEnabled } }
        .modifier(FocusRing(isFocused: isFocused, shape: shape))
        .nidusFocusable($isFocused, enabled: isEnabled) { open(byKeyboard: true) }
        .onKeyPress(keys: [.return, .downArrow, .upArrow]) { _ in
            guard isEnabled, !menu.isOpen else { return .ignored }
            open(byKeyboard: true)
            return .handled
        }
        .opacity(isEnabled ? 1 : Kit.Control.disabledOpacity)
        .animation(Kit.Motion.enable, value: isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(current?.accessibilityLabel ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the choices.")
        .accessibilityAction { open(byKeyboard: true) }
        .onChange(of: isEnabled) { _, enabled in if !enabled { menu.close() } }
        .onDisappear { menu.close() }
        #if DEBUG
            .onAppear { SelectDemo.openers[label] = { open(byKeyboard: $0) } }
        #endif
    }

    /// Opens on mouse down, like a native pop-up button.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressing else { return }
                isPressing = true
                open(byKeyboard: false)
            }
            .onEnded { _ in isPressing = false }
    }

    @discardableResult
    private func open(byKeyboard: Bool) -> SelectMenuController? {
        guard isEnabled, !menu.isOpen, let view = anchor.view, view.window != nil else { return nil }
        let options = options
        let onSelect = onSelect
        return menu.open(
            from: view, label: label, rows: options.map(\.row),
            selected: options.firstIndex { $0.value == selection }, byKeyboard: byKeyboard
        ) { onSelect(options[$0].value) }
    }
}

/// An option's icon and label, in the closed select and in a menu row.
private struct SelectValueLabel: View {
    let row: SelectMenuRow
    let iconSpacing: CGFloat

    var body: some View {
        HStack(spacing: iconSpacing) {
            if let icon = row.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Kit.Select.icon, height: Kit.Select.icon)
            }
            Text(row.label)
                .font(.system(size: Kit.Select.fontSize, design: row.monospaced ? .monospaced : .default))
                .foregroundStyle(Kit.Colour.bodyText)
                .singleLineLabel()
        }
    }
}

/// The select's open menu, if any, for SwiftUI to observe (the open ring).
@MainActor
@Observable
final class SelectMenuHandle {
    private(set) var isOpen = false
    @ObservationIgnored private var controller: SelectMenuController?

    func open(
        from view: NSView, label: String, rows: [SelectMenuRow], selected: Int?, byKeyboard: Bool,
        onChoose: @escaping (Int) -> Void
    ) -> SelectMenuController? {
        let controller = SelectMenuController(
            anchor: view, label: label, rows: rows, selected: selected, byKeyboard: byKeyboard,
            onChoose: onChoose
        ) { [weak self] in
            self?.isOpen = false
            self?.controller = nil
        }
        guard controller.show() else { return nil }
        self.controller = controller
        isOpen = true
        return controller
    }

    func close() { controller?.close() }
}

/// Holds the AppKit view behind a SwiftUI control, to place a menu against it.
@MainActor
final class ViewAnchor {
    weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
    let anchor: ViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

#if DEBUG
    /// Opens a select by its label (`pane://check-select?label=…`), so screenshots never need a click.
    @MainActor
    enum SelectDemo {
        /// By label; the argument says whether to open as from the keyboard.
        static var openers: [String: (Bool) -> SelectMenuController?] = [:]
    }
#endif

// MARK: - The menu

/// What the menu draws: its rows and state. Observed by the SwiftUI content.
@MainActor
@Observable
final class SelectMenuModel {
    let label: String
    let rows: [SelectMenuRow]
    var state: SelectMenuState

    init(label: String, rows: [SelectMenuRow], selected: Int?, byKeyboard: Bool) {
        self.label = label
        self.rows = rows
        state = SelectMenuState(names: rows.map(\.names), selected: selected, highlightsSelected: byKeyboard)
    }
}

/// One open menu: the child panel, its monitors, and what closes it (a click outside,
/// Esc, a choice, the window losing key or closing, Pane deactivating).
@MainActor
final class SelectMenuController {
    let model: SelectMenuModel
    private let panel = SelectMenuPanel()
    private let menuView: SelectMenuView
    private weak var anchor: NSView?
    private weak var parent: NSWindow?
    private let onChoose: (Int) -> Void
    private let onClose: () -> Void
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var isOpen = false

    init(
        anchor: NSView, label: String, rows: [SelectMenuRow], selected: Int?, byKeyboard: Bool,
        onChoose: @escaping (Int) -> Void, onClose: @escaping () -> Void
    ) {
        self.anchor = anchor
        self.onChoose = onChoose
        self.onClose = onClose
        model = SelectMenuModel(label: label, rows: rows, selected: selected, byKeyboard: byKeyboard)
        menuView = SelectMenuView(model: model, minWidth: anchor.bounds.width)
        menuView.controller = self
        panel.contentView = menuView
    }

    /// The panel's window number, for `screencapture -l`.
    var windowNumber: Int { panel.windowNumber }
    /// The menu's frame and the select's, in screen points (bottom-left origin).
    var menuFrame: NSRect { panel.frame }
    var selectFrame: NSRect { anchorRect ?? .zero }

    private var anchorRect: NSRect? {
        guard let anchor, let window = anchor.window else { return nil }
        return window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    }

    /// Places the panel under the select (above it when the screen ends first), right
    /// edges aligned, and shows it as a child of the select's window.
    func show() -> Bool {
        guard let parent = anchor?.window, anchorRect != nil else { return false }
        self.parent = parent
        panel.appearance = parent.effectiveAppearance
        place()
        parent.addChildWindow(panel, ordered: .above)
        // The shadow follows the drawn shape, which exists only after the first display.
        panel.display()
        panel.invalidateShadow()
        DispatchQueue.main.async { [panel] in panel.invalidateShadow() }
        isOpen = true
        startMonitoring(parent)
        NSAccessibility.post(element: menuView, notification: .created)
        return true
    }

    /// Under the select, right edges aligned; above it when the screen ends first. A child
    /// window moves with its parent, so this runs again only when the parent's layout can
    /// have moved the select (a resize).
    private func place() {
        guard let parent, let rect = anchorRect else { return }
        let size = menuView.fittingSize
        let width = max(size.width.rounded(.up), rect.width)
        let height = size.height.rounded(.up)
        var origin = NSPoint(x: rect.maxX - width, y: rect.minY - Kit.Select.menuGap - height)
        if let visible = (parent.screen ?? NSScreen.main)?.visibleFrame {
            if origin.y < visible.minY { origin.y = rect.maxY + Kit.Select.menuGap }
            origin.x = max(origin.x, visible.minX)
        }
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        onClose()
    }

    func choose(_ index: Int) {
        guard model.rows.indices.contains(index) else { return }
        close()
        onChoose(index)
    }

    func hover(_ index: Int?) {
        guard model.state.highlighted != index else { return }
        model.state.hover(index)
    }

    /// Applies a key; returns whether to swallow the event.
    @discardableResult
    func handle(_ key: SelectKey, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        switch model.state.handle(key, at: time) {
        case .ignored:
            return true
        case .highlighted(let index):
            NSAccessibility.post(
                element: menuView, notification: .announcementRequested,
                userInfo: [
                    .announcement: model.rows[index].accessibilityLabel,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
            return true
        case .choose(let index):
            choose(index)
            return true
        case .close:
            close()
            return true
        case .closeAndPass:
            close()
            return false
        }
    }

    private func startMonitoring(_ parent: NSWindow) {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: clicks.union(.scrollWheel),
            handler: { event in
                let (window, isScroll) = (event.windowNumber, event.type == .scrollWheel)
                let swallow = MainActor.assumeIsolated { self.localClick(window: window, isScroll: isScroll) }
                return swallow ? nil : event
            })
        {
            monitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: clicks,
            handler: { _ in
                MainActor.assumeIsolated { self.close() }
            })
        {
            monitors.append(global)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { event in
                let key = SelectKey(
                    keyCode: event.keyCode, characters: event.characters, modifiers: event.modifierFlags)
                let time = event.timestamp
                let swallow = MainActor.assumeIsolated { self.localKey(key, at: time) }
                return swallow ? nil : event
            })
        {
            monitors.append(keys)
        }
        let center = NotificationCenter.default
        let closing: [(NSNotification.Name, Any?)] = [
            (NSWindow.didResignKeyNotification, parent), (NSWindow.willCloseNotification, parent),
            (NSApplication.didResignActiveNotification, NSApp),
        ]
        observers.append(
            center.addObserver(forName: NSWindow.didResizeNotification, object: parent, queue: .main) { _ in
                MainActor.assumeIsolated { self.place() }
            })
        for (name, object) in closing {
            observers.append(
                center.addObserver(forName: name, object: object, queue: .main) { _ in
                    MainActor.assumeIsolated { self.close() }
                })
        }
    }

    /// A click (or scroll) outside the menu closes it and is swallowed, as with a native
    /// menu, so a click back on the select doesn't open it again.
    private func localClick(window: Int, isScroll: Bool) -> Bool {
        guard isOpen, window != panel.windowNumber else { return false }
        close()
        return !isScroll
    }

    /// Returns whether to swallow the key. A shortcut closes the menu and goes on.
    private func localKey(_ key: SelectKey?, at time: TimeInterval) -> Bool {
        guard isOpen else { return false }
        guard let key else {
            close()
            return false
        }
        return handle(key, at: time)
    }
}

/// The borderless panel the menu lives in. It never becomes key or main, so focus stays
/// on the select and Pane isn't activated by it.
private final class SelectMenuPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The menu's AppKit view: draws the SwiftUI content, tracks the pointer over the rows
/// (in any window state, as the popup is never key) and is the VoiceOver list.
private final class SelectMenuView: NSView {
    weak var controller: SelectMenuController?
    private let model: SelectMenuModel
    private let hosting: NSHostingView<SelectMenuContent>
    private var pressed: Int?
    private lazy var elements: [SelectOptionElement] = model.rows.indices.map { index in
        SelectOptionElement(
            label: model.rows[index].accessibilityLabel, frame: rowFrame(index),
            selected: model.state.selected == index, parent: self
        ) { [weak self] in self?.controller?.choose(index) }
    }

    init(model: SelectMenuModel, minWidth: CGFloat) {
        self.model = model
        hosting = NSHostingView(rootView: SelectMenuContent(model: model, minWidth: minWidth))
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        wantsLayer = true
        layer?.cornerRadius = Kit.Select.menuRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used from a nib") }

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { hosting.fittingSize }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    /// Row `index`'s frame: rows are a fixed height, stacked inside the padding.
    func rowFrame(_ index: Int) -> NSRect {
        let pad = Kit.Select.menuPadding
        return NSRect(
            x: pad, y: pad + CGFloat(index) * (Kit.Select.rowHeight + Kit.Select.rowGap),
            width: bounds.width - 2 * pad, height: Kit.Select.rowHeight)
    }

    private func row(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return model.rows.indices.first { rowFrame($0).contains(point) }
    }

    override func mouseMoved(with event: NSEvent) { controller?.hover(row(at: event)) }
    override func mouseEntered(with event: NSEvent) { controller?.hover(row(at: event)) }
    override func mouseExited(with event: NSEvent) { controller?.hover(nil) }
    override func mouseDragged(with event: NSEvent) { controller?.hover(row(at: event)) }
    override func mouseDown(with event: NSEvent) { pressed = row(at: event) }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        if let index = row(at: event), index == pressed { controller?.choose(index) }
    }

    // MARK: Accessibility: a list of options

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .list }
    override func accessibilityRoleDescription() -> String? { "list box" }
    override func accessibilityLabel() -> String? { model.label }
    override func accessibilityChildren() -> [Any]? { elements }
    override func accessibilityVisibleChildren() -> [Any]? { elements }
    override func accessibilityOrientation() -> NSAccessibilityOrientation { .vertical }
    override func accessibilitySelectedChildren() -> [Any]? {
        elements.filter { $0.isAccessibilitySelected() }
    }
}

/// One option in the VoiceOver list: its label (with the full path), its selected state,
/// and press to choose it. Made once the panel has its size, which doesn't change while
/// it's open, so it holds plain values.
private final class SelectOptionElement: NSAccessibilityElement {
    private let label: String
    private let frame: NSRect
    private let selected: Bool
    private let press: @MainActor @Sendable () -> Void

    init(label: String, frame: NSRect, selected: Bool, parent: NSView, press: @escaping @MainActor @Sendable () -> Void)
    {
        self.label = label
        self.frame = frame
        self.selected = selected
        self.press = press
        super.init()
        setAccessibilityParent(parent)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityRoleDescription() -> String? { "option" }
    override func accessibilityLabel() -> String? { label }
    override func accessibilityValue() -> Any? { label }
    override func isAccessibilitySelected() -> Bool { selected }
    override func isAccessibilityEnabled() -> Bool { true }
    override func accessibilityFrameInParentSpace() -> NSRect { frame }

    override func accessibilityPerformPress() -> Bool {
        let press = press
        MainActor.assumeIsolated { press() }
        return true
    }
}

/// The menu as drawn: the surface, the hairline and the rows.
private struct SelectMenuContent: View {
    let model: SelectMenuModel
    let minWidth: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Kit.Select.menuRadius, style: .continuous)
        VStack(spacing: Kit.Select.rowGap) {
            ForEach(model.rows.indices, id: \.self) { index in
                SelectMenuRowView(
                    row: model.rows[index], isSelected: model.state.selected == index,
                    isHighlighted: model.state.highlighted == index)
            }
        }
        .frame(minWidth: max(minWidth - 2 * Kit.Select.menuPadding, 0))
        .padding(Kit.Select.menuPadding)
        .fixedSize()
        .background(SelectMenuSurface())
        .clipShape(shape)
        .overlay { Hairline(shape: shape, width: Kit.Select.menuHairline) }
        .accessibilityHidden(true)
        .displayOptions()
    }
}

private struct SelectMenuRowView: View {
    let row: SelectMenuRow
    let isSelected: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: Kit.Select.rowIconSpacing) {
            SelectValueLabel(row: row, iconSpacing: Kit.Select.rowIconSpacing)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.system(size: Kit.Select.checkSize, weight: Kit.Select.checkWeight))
                .foregroundStyle(Kit.Colour.focusRing)
                .frame(width: Kit.Select.check)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, Kit.Select.rowPadding)
        .frame(maxWidth: .infinity, minHeight: Kit.Select.rowHeight, maxHeight: Kit.Select.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: Kit.Select.rowRadius, style: .continuous)
                .fill(isHighlighted ? Kit.Colour.highlight : .clear)
        }
    }
}

/// Solid white in light. Ink glass in dark: the tint at 96% over a behind-window blur, and
/// solid under Reduce Transparency or Increase Contrast.
private struct SelectMenuSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let solid = reduceTransparency || contrast == .increased
        ZStack {
            if colorScheme == .dark && !solid { BehindWindowBlur() }
            solid ? Kit.Colour.menuSurfaceSolid : Kit.Colour.menuSurface
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
