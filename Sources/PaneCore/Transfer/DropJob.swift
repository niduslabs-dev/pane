import Foundation

/// The files of one drop and where each one is: the card after the drop (the canvas's
/// "Option A · Card on the device screen") reads everything it shows from here. Apps run first,
/// in drop order, then the other files, in drop order; one failure doesn't stop the rest.
public struct DropJob: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable, Equatable {
            case app
            /// `isMedia`: scanned into the media store after the copy, so the gallery shows it.
            case file(isMedia: Bool)
        }

        public enum State: Sendable, Equatable {
            case waiting
            /// Older than the device's copy: waits for an answer before anything is sent.
            case asking
            /// The file is on its way to the device; `sent` of `total` bytes (total nil when
            /// the size is unknown).
            case sending(sent: Int64, total: Int64?)
            /// Pushed; `pm install` is running, which reports no progress.
            case installing
            case installed
            case copied
            /// Older than the device's copy and the answer was Cancel.
            case skipped
            case failed(DropFailure)
        }

        public var id: Int
        public var file: URL
        public var kind: Kind
        public var size: Int64?
        public var badging: ApkBadging?
        public var change: VersionChange?
        public var state: State = .waiting

        public init(
            id: Int, file: URL, kind: Kind, size: Int64? = nil, badging: ApkBadging? = nil,
            change: VersionChange? = nil
        ) {
            self.id = id
            self.file = file
            self.kind = kind
            self.size = size
            self.badging = badging
            self.change = change
        }

        public var isApp: Bool { kind == .app }

        /// The app's name once read, else the file's name.
        public var name: String {
            badging?.label ?? badging?.packageName ?? file.lastPathComponent
        }

        public var isFinished: Bool {
            switch state {
            case .installed, .copied, .skipped, .failed: true
            case .waiting, .asking, .sending, .installing: false
            }
        }

        public var failure: DropFailure? {
            if case .failed(let failure) = state { failure } else { nil }
        }
    }

    public var items: [Item]

    /// `items` in the order they run: apps first, then everything else, each in drop order.
    public init(items: [Item]) {
        self.items = items.filter(\.isApp) + items.filter { !$0.isApp }
    }

    /// The drop's files (folders and non-files are left out, as in `DropPlan`), with what the
    /// drag already read about each.
    public init(dragged: [DraggedItem]) {
        let usable = dragged.filter(\.isUsable)
        self.init(
            items: usable.enumerated().map { index, item in
                Item(
                    id: index, file: item.url,
                    kind: item.isApp ? .app : .file(isMedia: DropPlan.isMedia(item.url)),
                    size: item.size, badging: item.badging, change: item.change)
            })
    }

    public var isEmpty: Bool { items.isEmpty }
    public var isFinished: Bool { items.allSatisfy(\.isFinished) }
    /// The next item to run, nil when none waits (or one is asking).
    public var nextWaiting: Int? {
        guard !items.contains(where: { $0.state == .asking }) else { return nil }
        return items.firstIndex { $0.state == .waiting }
    }

    public var asking: Item? { items.first { $0.state == .asking } }
    public var failures: [Item] { items.filter { $0.failure != nil } }

    /// The newest installed app (Return opens it).
    public var lastInstalled: Item? { items.last { $0.state == .installed } }

    /// Overall progress for the bar in a several-file card: finished items count whole, the one
    /// being sent counts by its bytes. Never reaches 1 before everything is done.
    public func fraction(ceiling: Double) -> Double {
        guard !items.isEmpty else { return 0 }
        if isFinished { return 1 }
        let done = items.reduce(0.0) { sum, item in
            switch item.state {
            case .installed, .copied, .skipped, .failed: sum + 1
            case .sending(let sent, let total?) where total > 0: sum + Double(sent) / Double(total) * ceiling
            case .installing: sum + ceiling
            default: sum
            }
        }
        return min(done / Double(items.count), ceiling)
    }

    /// The several-file card's title: "Installing 2 apps and copying 2 files", then
    /// "Installed 1 app and copied 2 files" (counting what worked).
    public var title: String {
        let apps = items.count(where: \.isApp)
        let files = items.count - apps
        guard isFinished else {
            return Self.joined(
                apps > 0 ? "Installing \(Self.count(apps, "app"))" : nil,
                files > 0 ? "copying \(Self.count(files, "file"))" : nil)
        }
        let installed = items.count { $0.state == .installed }
        let copied = items.count { $0.state == .copied }
        if installed == 0 && copied == 0 {
            return items.count == 1 ? "Nothing was installed" : "Nothing was installed or copied"
        }
        return Self.joined(
            installed > 0 ? "Installed \(Self.count(installed, "app"))" : nil,
            copied > 0 ? "copied \(Self.count(copied, "file"))" : nil)
    }

    /// "38 of 61 MB": what has reached the device, in the total's unit.
    public static func progressText(sent: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let totalText = formatter.string(fromByteCount: total)
        let units: [(ByteCountFormatter.Units, String)] = [(.useGB, " GB"), (.useMB, " MB"), (.useKB, " KB")]
        for (unit, suffix) in units where totalText.hasSuffix(suffix) {
            formatter.allowedUnits = unit
            formatter.includesUnit = false
            return "\(formatter.string(fromByteCount: min(sent, total))) of \(totalText)"
        }
        return "\(formatter.string(fromByteCount: min(sent, total))) of \(totalText)"
    }

    private static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }

    private static func joined(_ first: String?, _ second: String?) -> String {
        switch (first, second) {
        case (let a?, let b?): "\(a) and \(b)"
        case (let a?, nil): a
        case (nil, let b?): b.prefix(1).uppercased() + b.dropFirst()
        case (nil, nil): ""
        }
    }
}

/// When the card after a drop closes (`dismissible`): a finished drop closes itself
/// `afterDone` after its last result, but not while the pointer is over the card; a question or
/// a failure stays until dismissed.
public enum DropDismissal: Sendable, Equatable {
    /// Keep the card: still working, asking, or something failed.
    case stay
    /// Check again after this long.
    case wait(Duration)
    case close

    public static func decide(
        job: DropJob, finishedAt: ContinuousClock.Instant?, now: ContinuousClock.Instant, isHovered: Bool,
        afterDone: Duration
    ) -> DropDismissal {
        guard job.isFinished, job.failures.isEmpty, let finishedAt else { return .stay }
        let elapsed = finishedAt.duration(to: now)
        if elapsed < afterDone { return .wait(afterDone - elapsed) }
        // Under the pointer the card waits for it to leave; leaving closes it.
        return isHovered ? .stay : .close
    }
}
