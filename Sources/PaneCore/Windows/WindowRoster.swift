import Foundation

/// One row of the emulator switcher: an AVD, whether it runs, and whether a window shows it.
public struct SwitcherEntry: Sendable, Equatable, Identifiable {
    public var name: String
    /// "Pixel 8 · Android 16", or empty when the AVD's config says neither.
    public var detail: String
    public var isRunning: Bool
    /// Shown in the window the menu belongs to (ticked).
    public var isCurrent: Bool
    /// Shown in another window; choosing it brings that window forward.
    public var isShownElsewhere: Bool

    public var id: String { name }

    /// Every AVD on disk by name, then any running emulator whose AVD isn't in the list.
    public static func entries(
        avds: [AvdInfo], running: [String], current: String?, shownElsewhere: Set<String>
    ) -> [SwitcherEntry] {
        let runningSet = Set(running)
        var entries = avds.map { avd in
            SwitcherEntry(
                name: avd.name, detail: avd.profile.summary, isRunning: runningSet.contains(avd.name),
                isCurrent: avd.name == current, isShownElsewhere: shownElsewhere.contains(avd.name))
        }
        let known = Set(avds.map(\.name))
        var seen = known
        for name in running where seen.insert(name).inserted {
            entries.append(
                SwitcherEntry(
                    name: name, detail: "", isRunning: true, isCurrent: name == current,
                    isShownElsewhere: shownElsewhere.contains(name)))
        }
        return entries
    }
}

/// Which emulator each Pane window shows. One window per emulator: asking for an AVD that a
/// window already shows brings that window forward instead of showing it twice.
public struct WindowRoster<WindowID: Hashable & Sendable>: Sendable {
    private var order: [WindowID] = []
    private var shown: [WindowID: String] = [:]

    public init() {}

    public var windows: [WindowID] { order }
    public var isEmpty: Bool { order.isEmpty }

    public mutating func add(_ window: WindowID, showing avd: String?) {
        if !order.contains(window) { order.append(window) }
        shown[window] = avd
    }

    public mutating func remove(_ window: WindowID) {
        order.removeAll { $0 == window }
        shown[window] = nil
    }

    /// Records what a window shows now (nil while it shows no AVD at all).
    public mutating func set(_ avd: String?, for window: WindowID) {
        guard order.contains(window) else { return }
        shown[window] = avd
    }

    public func avd(in window: WindowID) -> String? { shown[window] }

    /// The window showing an AVD, if any.
    public func window(showing avd: String) -> WindowID? {
        order.first { shown[$0] == avd }
    }

    /// The AVDs other windows show.
    public func avdsShown(except window: WindowID?) -> Set<String> {
        Set(order.filter { $0 != window }.compactMap { shown[$0] })
    }

    /// What a new window should show: the first running emulator without a window, else the
    /// first AVD without one, else nil (every emulator already has its window).
    public func avdForNewWindow(avds: [String], running: [String]) -> String? {
        let taken = avdsShown(except: nil)
        return running.first { !taken.contains($0) } ?? avds.first { !taken.contains($0) }
    }

    public enum Placement: Equatable, Sendable {
        /// A window already shows it: bring that one forward.
        case existing(WindowID)
        /// Show it in this window.
        case reuse(WindowID)
        case newWindow
    }

    /// Where an AVD asked for from outside (the emulator wrapper's attach request) should go:
    /// its own window if it has one, else a window with nothing running in it (`idle`), else a
    /// new window.
    public func placement(for avd: String, idle: [WindowID]) -> Placement {
        if let existing = window(showing: avd) { return .existing(existing) }
        if let free = order.first(where: { idle.contains($0) }) { return .reuse(free) }
        return .newWindow
    }
}
