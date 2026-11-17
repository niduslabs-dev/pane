import Foundation

/// Whether an emulator runs, as the switcher's status dot says it.
public enum EmulatorRunState: Sendable, Equatable {
    case stopped
    /// Launched or booting: registered or not, Android isn't up yet.
    case starting
    case running
}

/// One row of the emulator switcher (board 20): an AVD, its device, whether it runs, and
/// whether a window shows it.
public struct SwitcherEntry: Sendable, Equatable, Identifiable {
    public var name: String
    /// "Pixel 8", or empty when the AVD's config doesn't say.
    public var model: String
    /// "Android 16", or empty when the AVD's config doesn't say.
    public var androidVersion: String
    public var kind: DeviceKind
    public var state: EmulatorRunState
    /// Shown in the window the menu belongs to (ticked, with the selected fill).
    public var isCurrent: Bool
    /// Shown in another window; choosing it brings that window forward.
    public var isShownElsewhere: Bool

    public var id: String { name }
    public var isRunning: Bool { state != .stopped }

    public init(
        name: String, model: String = "", androidVersion: String = "", kind: DeviceKind = .phone,
        state: EmulatorRunState = .stopped, isCurrent: Bool = false, isShownElsewhere: Bool = false
    ) {
        self.name = name
        self.model = model
        self.androidVersion = androidVersion
        self.kind = kind
        self.state = state
        self.isCurrent = isCurrent
        self.isShownElsewhere = isShownElsewhere
    }

    /// "Pixel 8 · Android 16", for VoiceOver and the emulators menu.
    public var detail: String {
        [model, androidVersion].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The row's second line in two parts: `lead` truncates first, `trail` (" · Android 16" or
    /// " · Starting") always shows whole. "In another window" takes the model's place for an
    /// emulator another window shows, "Starting" the Android version's while it comes up.
    public var secondLine: (lead: String, trail: String) {
        let lead = isShownElsewhere ? Self.inAnotherWindow : model
        let version = state == .starting ? Self.starting : androidVersion
        if lead.isEmpty || version.isEmpty { return (lead + version, "") }
        return (lead, " · " + version)
    }

    /// Only an emulator with no window of its own gets "Open in new window": this window's
    /// is already here, and another window's comes forward when chosen.
    public var opensInNewWindow: Bool { !isCurrent && !isShownElsewhere }

    /// What VoiceOver reads: "pixel9_api35, Pixel 9 Pro, Android 15, running". The model is
    /// read even where the row shows "In another window".
    public var accessibilityText: String {
        let status =
            switch state {
            case .running: "running"
            case .starting: "starting"
            case .stopped: "stopped"
            }
        var parts = [name, model, androidVersion].filter { !$0.isEmpty }
        if isShownElsewhere { parts.append(Self.inAnotherWindow.lowercased()) }
        parts.append(status)
        return parts.joined(separator: ", ")
    }

    public static let inAnotherWindow = "In another window"
    public static let starting = "Starting"

    /// Every AVD on disk by name, then any running emulator whose AVD isn't in the list.
    /// `starting` names AVDs a Pane window is launching or waiting on to boot.
    public static func entries(
        avds: [AvdInfo], running: [String], starting: Set<String> = [], current: String?,
        shownElsewhere: Set<String>
    ) -> [SwitcherEntry] {
        let runningSet = Set(running)
        func state(_ name: String) -> EmulatorRunState {
            if starting.contains(name) { return .starting }
            return runningSet.contains(name) ? .running : .stopped
        }
        var entries = avds.map { avd in
            SwitcherEntry(
                name: avd.name, model: avd.profile.modelName ?? "", androidVersion: avd.profile.androidVersion ?? "",
                kind: avd.profile.kind, state: state(avd.name), isCurrent: avd.name == current,
                isShownElsewhere: shownElsewhere.contains(avd.name))
        }
        var seen = Set(avds.map(\.name))
        for name in running where seen.insert(name).inserted {
            entries.append(
                SwitcherEntry(
                    name: name, state: state(name), isCurrent: name == current,
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
