import Foundation

// What the update surfaces say (canvas board 15). Kept apart from the views so tests pin it.

extension UpdateModel {
    /// A downloaded update waits for a restart: Settings shows its banner.
    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// The Version row shows a spinner beside its caption.
    var isChecking: Bool { phase == .checking }

    /// The Version row's caption is a failure (drawn in the error colour).
    var hasFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// The caption under "Version x" in Settings: "Up to date · checked today at 09:12",
    /// "1.1 downloaded · checked today at 09:12", "Checking…", and so on. `locale` and
    /// `calendar` are parameters so tests pin the clock format.
    func versionCaption(now: Date = .now, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let checked =
            lastChecked.map {
                " \u{00B7} checked " + Self.checkedPhrase($0, now: now, locale: locale, calendar: calendar)
            } ?? ""
        switch phase {
        case .checking: return "Checking\u{2026}"
        case .installing: return "Installing\u{2026}"
        case .downloading(let update, _): return "Downloading \(update.version)\u{2026}"
        case .ready(let update): return "\(update.version) downloaded" + checked
        case .available(let update): return "\(update.version) available" + checked
        case .failed: return "Couldn't check. Try again later."
        case .upToDate: return "Up to date" + (checked.isEmpty ? "" : " \u{00B7} checked just now")
        case .idle:
            guard isEnabled else { return "This build doesn't update itself." }
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
