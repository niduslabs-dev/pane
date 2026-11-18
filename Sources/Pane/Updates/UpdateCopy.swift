import Foundation

// What the update surfaces say (canvas board 15). Kept apart from the views so tests pin it.

/// The Settings Version row in one state (the in-row update board): the title, the second
/// line, the action and What's new. A value, so tests pin every state's words.
struct VersionRowState: Equatable {
    enum Action: Equatable {
        case check, download, restart, retry

        /// What pressing it asks the model to do.
        var updateAction: UpdateAction {
            switch self {
            case .check: .check
            case .download: .download
            case .restart: .restart
            case .retry: .retry
            }
        }
    }

    /// "Version 1.0.2".
    var title: String
    /// The second line without the percentage: "Downloading 1.0.3", "Version 1.0.3 is ready".
    var caption: String
    /// The download's percentage, shown after the caption as " · 42%" and rolled.
    var percent: Int?
    /// The kit's mini spinner leads the line (checking, preparing, installing).
    var spinner = false
    /// The line is a failure, in the error colour.
    var isError = false
    var action: Action
    /// False dims the action in place.
    var actionEnabled: Bool
    /// What's new shows (every build that updates itself).
    var showsWhatsNew: Bool
    /// The version What's new names for VoiceOver.
    var whatsNewVersion: String
    /// The update the action is about, for its VoiceOver name.
    var pendingVersion: String?

    var actionTitle: String {
        switch action {
        case .check: "Check for updates"
        case .download: "Download"
        case .restart: "Restart to update"
        case .retry: "Try again"
        }
    }

    /// The action's VoiceOver name: what it does, with the version.
    var actionAccessibilityLabel: String {
        switch (action, pendingVersion) {
        case (.download, let version?): "Download Pane \(version)"
        case (.restart, let version?): "Restart to update to Pane \(version)"
        default: actionTitle
        }
    }

    var whatsNewAccessibilityLabel: String { "What's new in Pane \(whatsNewVersion)" }

    /// The moss primary capsule (Restart to update), else the small secondary.
    var actionIsPrimary: Bool { action == .restart }

    /// The whole line as drawn: " · 42%" after the caption while downloading.
    var line: String { caption + (percent.map { " \u{00B7} \($0)%" } ?? "") }
}

extension UpdateModel {
    /// A downloaded update waits for a restart.
    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// The Version row's caption shows a spinner.
    var isChecking: Bool { phase == .checking }

    /// The Version row's caption is a failure (drawn in the error colour).
    var hasFailed: Bool {
        if case .failed = phase { return true }
        return restartFailed && isReady
    }

    /// The Version row in the current state. `locale` and `calendar` are parameters so tests
    /// pin the clock format.
    func versionRow(now: Date = .now, locale: Locale = .current, calendar: Calendar = .current) -> VersionRowState {
        let pending = update?.version
        let ready =
            isReady
            || {
                if case .installing = phase { return true }
                return false
            }()
        var row = VersionRowState(
            title: "Version \(currentVersion)",
            caption: versionCaption(now: now, locale: locale, calendar: calendar),
            action: .check, actionEnabled: canCheck, showsWhatsNew: isEnabled,
            whatsNewVersion: ready ? (pending ?? currentVersion) : currentVersion, pendingVersion: pending)
        switch phase {
        case .checking:
            row.spinner = true
        case .available:
            row.action = .download
            row.actionEnabled = true
        case .downloading(_, let progress):
            row.action = .restart
            row.actionEnabled = false
            if progress.stage == .preparing {
                row.spinner = true
            } else if let fraction = progress.fraction {
                row.percent = Int((fraction * 100).rounded(.down))
            }
        case .ready:
            row.action = .restart
            row.actionEnabled = true
            row.isError = restartFailed
        case .installing:
            row.action = .restart
            row.actionEnabled = false
            row.spinner = true
        case .failed:
            row.action = .retry
            row.actionEnabled = isEnabled
            row.isError = true
        case .idle, .upToDate:
            break
        }
        return row
    }

    /// The second line under "Version x" in Settings, without the download's percentage:
    /// "Up to date · checked today at 09:12", "Checking for updates…", "Version 1.1 is ready",
    /// and so on.
    func versionCaption(now: Date = .now, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let checked =
            lastChecked.map {
                " \u{00B7} checked " + Self.checkedPhrase($0, now: now, locale: locale, calendar: calendar)
            } ?? ""
        switch phase {
        case .checking: return "Checking for updates\u{2026}"
        case .installing(let update):
            return update.map { "Installing \($0.version)\u{2026}" } ?? "Installing\u{2026}"
        case .downloading(let update, let progress):
            if progress.stage == .preparing { return "Preparing \(update.version)\u{2026}" }
            return progress.fraction == nil ? "Downloading \(update.version)\u{2026}" : "Downloading \(update.version)"
        case .ready(let update):
            if restartFailed { return "Couldn't restart. It installs on quit." }
            if isDeferred { return "\(update.version) installs when Pane quits" }
            return "Version \(update.version) is ready"
        case .available(let update): return "Version \(update.version) is available"
        case .failed(.check): return "Couldn't check for updates."
        case .failed(.download(let version)): return "Couldn't download \(version)."
        case .failed(.verify(let version)): return "Couldn't verify \(version)."
        case .upToDate: return "Up to date" + (checked.isEmpty ? "" : " \u{00B7} checked just now")
        case .idle:
            guard isEnabled else { return "This build doesn't update itself." }
            if let updatedTo { return "Updated to \(updatedTo)" }
            return lastChecked == nil ? "Not checked yet" : "Up to date" + checked
        }
    }

    /// "just now", "today at 09:12", "yesterday at 18:40" or "on 12 Nov".
    static func checkedPhrase(_ date: Date, now: Date, locale: Locale, calendar: Calendar) -> String {
        if now.timeIntervalSince(date) < justNow, date <= now { return "just now" }
        var calendar = calendar
        calendar.locale = locale
        let time = date.formatted(
            Date.FormatStyle(
                date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "yesterday at \(time)"
        }
        let day = date.formatted(
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
        return "on \(day)"
    }

    /// A check this recent reads "just now".
    static let justNow: TimeInterval = 60

    /// The popup's title: "Pane 1.1 is ready", "Pane 1.1 is available" before the download,
    /// "Downloading Pane 1.1" during it.
    var popupTitle: String {
        switch phase {
        case .available(let update): "Pane \(update.version) is available"
        case .downloading(let update, _): "Downloading Pane \(update.version)"
        case .ready(let update): "Pane \(update.version) is ready"
        case .idle, .checking, .installing, .upToDate, .failed: "Pane"
        }
    }

    /// The part after the version step: "6 MB", "6 MB, downloaded" or "2.1 of 6 MB".
    var sizeDetail: String? {
        switch phase {
        case .available(let update):
            return update.size.map(Self.megabytes)
        case .downloading(let update, let progress):
            guard let total = progress.expected ?? update.size, total > 0 else { return nil }
            guard progress.stage == .downloading else { return Self.megabytes(total) }
            return
                "\(Self.megabyteFigure(min(progress.received, total), wholeAbove: total)) of \(Self.megabytes(total))"
        case .ready(let update):
            return ([update.size.map(Self.megabytes), "downloaded"] as [String?]).compactMap(\.self)
                .joined(separator: ", ")
        case .idle, .checking, .installing, .upToDate, .failed:
            return nil
        }
    }

    /// The popup's progress bar: the download's share, held under `ceiling` until the update
    /// is verified, so the bar never looks finished while Restart to Update is still off.
    /// Nil when there is no bar.
    func barFraction(ceiling: Double) -> Double? {
        guard case .downloading(_, let progress) = phase else { return nil }
        switch progress.stage {
        case .downloading: return min(progress.fraction ?? 0, 1) * ceiling
        case .preparing: return ceiling
        }
    }

    private static let bytesPerMegabyte = 1_000_000.0

    /// "6 MB", or "0.4 MB" under one.
    static func megabytes(_ bytes: UInt64) -> String { megabyteFigure(bytes, wholeAbove: bytes) + " MB" }

    /// The figure alone. Whole megabytes read as "6"; a part of a larger download keeps one
    /// decimal ("2.1 of 6 MB") so it visibly moves.
    private static func megabyteFigure(_ bytes: UInt64, wholeAbove total: UInt64) -> String {
        let value = Double(bytes) / bytesPerMegabyte
        let isPart = bytes < total
        if !isPart, value >= 1 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    /// "Install updates automatically": Sparkle's automatic download, which installs on quit.
    var installsAutomatically: Bool {
        get { downloadsAutomatically }
        set { downloadsAutomatically = newValue }
    }
}
