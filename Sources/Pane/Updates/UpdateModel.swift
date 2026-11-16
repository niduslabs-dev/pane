import Foundation
import Observation
import os

/// A newer Pane found in the feed, reduced to what Pane's surfaces show.
struct AvailableUpdate: Equatable, Sendable {
    /// The version people see ("1.1"), the feed item's display version.
    let version: String
    /// The download's size in bytes, when the feed gives one.
    let size: UInt64?
    /// Up to `ReleaseNotes.lineLimit` lines from the item's description.
    let notes: [String]
    /// Where Release notes goes: the GitHub release page.
    let releaseNotesURL: URL?
}

/// How far a download the user can see has come.
struct UpdateProgress: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case downloading
        /// Unpacking and checking the download.
        case preparing
    }

    var stage = Stage.downloading
    var received: UInt64 = 0
    /// The download's length once the server says it; the feed's size until then.
    var expected: UInt64?
    /// Sparkle's own 0–1 figure while unpacking.
    var preparing: Double = 0

    /// 0–1 for a progress bar, or nil while the length isn't known (show it indeterminate).
    var fraction: Double? {
        switch stage {
        case .preparing: return min(max(preparing, 0), 1)
        case .downloading:
            guard let expected, expected > 0 else { return nil }
            return min(Double(received) / Double(expected), 1)
        }
    }
}

/// What the user can do on an update surface or in the menu.
enum UpdateAction: Equatable, Sendable {
    /// Check for Updates… in the app menu.
    case check
    /// Download, shown when updates don't download by themselves.
    case download
    /// Stop a download the user is watching.
    case cancelDownload
    /// Restart to Update: install now and reopen Pane.
    case restart
    /// Later: hide the surface. A downloaded update installs the next time Pane quits.
    case later
    /// Close "up to date" or an error.
    case dismiss
}

/// How the engine wants an answer to a prompt, kept until the user picks one. Mirrors
/// `SPUUserUpdateChoice`, so the model stays testable without Sparkle.
enum UpdateReply: Equatable, Sendable {
    case install
    case dismiss
}

/// How often Pane looks for an update by itself.
enum UpdateCheckInterval: TimeInterval, CaseIterable, Sendable {
    case daily = 86_400
    case weekly = 604_800

    /// The case closest to a stored number of seconds (Sparkle keeps a plain interval).
    init(nearest seconds: TimeInterval) {
        let midpoint = (Self.daily.rawValue + Self.weekly.rawValue) / 2
        self = seconds < midpoint ? .daily : .weekly
    }
}

/// What an update surface shows. One at a time; nil means nothing is shown.
enum UpdatePresentation: Equatable, Sendable {
    /// A newer version is out and waits for Download.
    case available(AvailableUpdate)
    /// `fraction` is 0–1, or nil while the length isn't known.
    case downloading(AvailableUpdate, fraction: Double?)
    /// Downloaded and checked: Restart to Update, or Later.
    case ready(AvailableUpdate)
    /// A check the user started found nothing newer than `version`.
    case upToDate(version: String)
    /// A check or download the user started failed.
    case error(message: String)
}

/// The UI's side of updates. The approved design implements this; the model calls it with
/// every change, and the surface sends the user's choice back through
/// `UpdateModel.perform(_:)`. Until one is attached nothing is shown.
@MainActor
protocol UpdateSurface: AnyObject {
    /// `presentation` is what to show now; nil hides the surface.
    func updatePresentationChanged(_ presentation: UpdatePresentation?)
}

/// What the model needs from whatever finds and installs updates: Sparkle in the app
/// (`UpdateDriver`), a scripted feed in tests.
@MainActor
protocol UpdateEngine: AnyObject {
    /// False while a check or an install is already running.
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var updateCheckInterval: TimeInterval { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    /// A check the user asked for. The engine answers through the model's event methods.
    func checkForUpdates()
}

/// The state behind every update surface and the Check for Updates… menu item.
/// `UpdateDriver` feeds it Sparkle's events; the surface sends the user's choices back
/// through `perform(_:)`.
///
/// Rules:
/// - A check Pane makes by itself stays silent until there is something to decide: with
///   automatic downloads on, the update downloads unseen and the surface says it is ready;
///   off, the surface offers Download.
/// - A check the user starts always answers: progress while it downloads, "up to date", or
///   the error.
/// - Later hides the surface and keeps the update: it installs when Pane quits.
/// - Failures of Pane's own checks are logged, never shown. The next scheduled check retries.
@MainActor
@Observable
final class UpdateModel {
    enum Phase: Equatable {
        /// Nothing pending.
        case idle
        /// A check the user started is running.
        case checking
        /// A newer version is out but not downloaded.
        case available(AvailableUpdate)
        case downloading(AvailableUpdate, UpdateProgress)
        /// Downloaded and verified: installs on quit, or now with Restart to Update.
        case ready(AvailableUpdate)
        /// The engine is quitting Pane to install.
        case installing
        /// A check the user started found nothing newer.
        case upToDate
        /// A check or download the user started failed.
        case failed(message: String)
    }

    /// The running version ("1.0").
    let currentVersion: String
    private(set) var phase = Phase.idle {
        didSet { publish() }
    }
    /// The surface is wanted for the current phase. False after Later, and during anything
    /// Pane does by itself.
    private(set) var wantsSurface = false {
        didSet { publish() }
    }
    private(set) var lastChecked: Date?
    /// False when no engine runs (debug builds, builds without a feed): Check for Updates…
    /// is disabled.
    private(set) var isEnabled = false

    /// "Check for updates automatically".
    var checksAutomatically = true {
        didSet {
            guard checksAutomatically != oldValue else { return }
            engine?.automaticallyChecksForUpdates = checksAutomatically
        }
    }
    var checkInterval = UpdateCheckInterval.daily {
        didSet {
            guard checkInterval != oldValue else { return }
            engine?.updateCheckInterval = checkInterval.rawValue
        }
    }
    /// "Download updates automatically".
    var downloadsAutomatically = true {
        didSet {
            guard downloadsAutomatically != oldValue else { return }
            engine?.automaticallyDownloadsUpdates = downloadsAutomatically
        }
    }

    /// The UI. Setting it shows whatever is already pending.
    @ObservationIgnored weak var surface: (any UpdateSurface)? {
        didSet {
            published = nil
            surface?.updatePresentationChanged(presentation)
            published = presentation
        }
    }
    /// Opens a URL (Release notes); `NSWorkspace` in the app.
    @ObservationIgnored var openURL: (URL) -> Void = { _ in }

    @ObservationIgnored private weak var engine: (any UpdateEngine)?
    /// Answers the engine's open prompt (update found, ready to install), if one is waiting.
    @ObservationIgnored private var pendingReply: ((UpdateReply) -> Void)?
    /// The engine's install-now handler for an update it downloaded unseen. Can be called
    /// more than once.
    @ObservationIgnored private var installNow: (() -> Void)?
    @ObservationIgnored private var cancelDownload: (() -> Void)?
    /// Restart to Update was pressed with nothing to call: the next prompt for this update
    /// is answered with install straight away.
    @ObservationIgnored private var restartRequested = false
    /// The running cycle began with Check for Updates…, so it reports back.
    @ObservationIgnored private var userInitiated = false
    @ObservationIgnored private var published: UpdatePresentation?

    init(currentVersion: String) {
        self.currentVersion = currentVersion
    }

    /// Connects a started engine and takes over its stored settings.
    func attach(_ engine: any UpdateEngine) {
        self.engine = engine
        isEnabled = true
        checksAutomatically = engine.automaticallyChecksForUpdates
        checkInterval = UpdateCheckInterval(nearest: engine.updateCheckInterval)
        downloadsAutomatically = engine.automaticallyDownloadsUpdates
        lastChecked = engine.lastUpdateCheckDate
    }

    /// The update the surfaces describe, whatever its phase.
    var update: AvailableUpdate? {
        switch phase {
        case .available(let update), .downloading(let update, _), .ready(let update): update
        case .idle, .checking, .installing, .upToDate, .failed: nil
        }
    }

    /// Check for Updates… is enabled.
    var canCheck: Bool {
        guard isEnabled, let engine else { return false }
        switch phase {
        case .checking, .downloading, .installing: return false
        case .idle, .available, .ready, .upToDate, .failed: return engine.canCheckForUpdates
        }
    }

    /// What the surface shows now.
    var presentation: UpdatePresentation? {
        guard wantsSurface else { return nil }
        switch phase {
        case .idle, .checking, .installing: return nil
        case .available(let update): return .available(update)
        case .downloading(let update, let progress): return .downloading(update, fraction: progress.fraction)
        case .ready(let update): return .ready(update)
        case .upToDate: return .upToDate(version: currentVersion)
        case .failed(let message): return .error(message: message)
        }
    }

    private func publish() {
        let next = presentation
        guard next != published else { return }
        published = next
        surface?.updatePresentationChanged(next)
    }

    // MARK: User actions

    func perform(_ action: UpdateAction) {
        switch action {
        case .check:
            guard canCheck else { return }
            if case .ready = phase {
                // Already downloaded: show it again instead of asking the feed.
                wantsSurface = true
                return
            }
            engine?.checkForUpdates()
        case .download:
            guard case .available(let update) = phase, let reply = takeReply() else {
                engine?.checkForUpdates()
                return
            }
            userInitiated = true
            phase = .downloading(update, UpdateProgress(expected: update.size))
            wantsSurface = true
            reply(.install)
        case .cancelDownload:
            guard case .downloading = phase else { return }
            let cancel = cancelDownload
            cancelDownload = nil
            wantsSurface = false
            phase = .idle
            cancel?()
        case .restart:
            wantsSurface = false
            if let installNow {
                phase = .installing
                installNow()
            } else if let reply = takeReply() {
                phase = .installing
                reply(.install)
            } else {
                // After Later the prompt was answered; a new check brings the pending update
                // back as a prompt, answered with install (`found`).
                restartRequested = true
                engine?.checkForUpdates()
            }
        case .later:
            wantsSurface = false
            takeReply()?(.dismiss)
        case .dismiss:
            wantsSurface = false
            switch phase {
            case .upToDate, .failed: phase = .idle
            case .idle, .checking, .available, .downloading, .ready, .installing: break
            }
        }
    }

    func openReleaseNotes() {
        if let url = update?.releaseNotesURL { openURL(url) }
    }

    // MARK: The engine's events (`UpdateDriver`)

    /// The user started a check.
    func checkStarted() {
        userInitiated = true
        switch phase {
        case .idle, .upToDate, .failed:
            wantsSurface = false
            phase = .checking
        case .checking, .available, .downloading, .ready, .installing: break
        }
    }

    /// The engine found `update`. `downloaded` is true when it's already on disk (downloaded
    /// unseen, or armed to install on quit).
    func found(_ update: AvailableUpdate, downloaded: Bool, reply: @escaping (UpdateReply) -> Void) {
        if downloaded {
            if restartRequested {
                restartRequested = false
                phase = .installing
                reply(.install)
                return
            }
            pendingReply = reply
            phase = .ready(update)
            wantsSurface = true
        } else if downloadsAutomatically {
            // A check the user started downloads straight away, as Pane's own check would
            // have, and shows its progress because they are waiting for it.
            phase = .downloading(update, UpdateProgress(expected: update.size))
            wantsSurface = userInitiated
            reply(.install)
        } else {
            pendingReply = reply
            phase = .available(update)
            wantsSurface = true
        }
    }

    /// The download began; `cancel` stops it.
    func downloadStarted(cancel: @escaping () -> Void) {
        cancelDownload = cancel
    }

    /// The server gave the download's length.
    func downloadExpects(_ length: UInt64) {
        guard length > 0 else { return }
        updateProgress { $0.expected = length }
    }

    func downloadReceived(_ length: UInt64) {
        updateProgress { $0.received += length }
    }

    /// Downloaded; the engine is unpacking and checking it. It can't be cancelled now.
    func preparing(_ fraction: Double) {
        cancelDownload = nil
        updateProgress {
            $0.stage = .preparing
            $0.preparing = fraction
        }
    }

    private func updateProgress(_ change: (inout UpdateProgress) -> Void) {
        guard case .downloading(let update, var progress) = phase else { return }
        change(&progress)
        phase = .downloading(update, progress)
    }

    /// The engine downloaded and unpacked the update the user chose to download.
    func readyToInstall(reply: @escaping (UpdateReply) -> Void) {
        cancelDownload = nil
        guard let update else {
            reply(.dismiss)
            return
        }
        if restartRequested {
            restartRequested = false
            phase = .installing
            reply(.install)
            return
        }
        pendingReply = reply
        phase = .ready(update)
        wantsSurface = true
    }

    /// A download nobody watched finished and installs on quit; `installNow` installs and
    /// reopens Pane at once.
    func readyOnQuit(_ update: AvailableUpdate, installNow: @escaping () -> Void) {
        self.installNow = installNow
        phase = .ready(update)
        wantsSurface = true
    }

    /// A check found nothing newer.
    func notFound() {
        restartRequested = false
        guard case .checking = phase else { return }
        phase = .upToDate
        wantsSurface = userInitiated
    }

    /// The engine is installing (Pane is about to quit).
    func installing() {
        wantsSurface = false
        phase = .installing
    }

    /// The engine finished a cycle, with or without an update.
    func cycleFinished(lastChecked: Date?) {
        self.lastChecked = lastChecked ?? self.lastChecked
    }

    /// The engine stopped the current cycle. A downloaded update still installs on quit, so
    /// it stays; anything in flight is dropped.
    func cycleEnded() {
        pendingReply = nil
        cancelDownload = nil
        userInitiated = false
        switch phase {
        case .ready, .available, .installing, .upToDate, .failed: break
        case .idle, .checking, .downloading: phase = .idle
        }
    }

    /// Any failure. Shown only when the user started the check or is watching the download;
    /// otherwise logged, and the next scheduled check retries. A downloaded update stays.
    func failed(_ error: any Error) {
        Self.log.error("Update failed: \(error.localizedDescription, privacy: .public)")
        restartRequested = false
        pendingReply = nil
        cancelDownload = nil
        if case .ready = phase { return }
        if userInitiated || wantsSurface {
            phase = .failed(message: error.localizedDescription)
            wantsSurface = true
        } else {
            phase = .idle
        }
    }

    @discardableResult
    private func takeReply() -> ((UpdateReply) -> Void)? {
        defer { pendingReply = nil }
        return pendingReply
    }

    static let log = Logger(subsystem: "dev.niduslabs.pane", category: "updates")

    #if DEBUG
        /// Sets a state directly, for screenshots of the surfaces (`pane://check-update`).
        func demo(_ phase: Phase, surface: Bool, lastChecked: Date?) {
            isEnabled = true
            self.lastChecked = lastChecked
            self.phase = phase
            wantsSurface = surface
        }
    #endif
}

/// Release-note lines for a surface from a feed item's description, which is HTML (a `<ul>`
/// from the release workflow) or plain lines.
enum ReleaseNotes {
    static let lineLimit = 3

    /// The first `limit` list items, or else the first non-empty lines, with tags and list
    /// markers removed and the common entities decoded.
    static func lines(from description: String?, limit: Int = lineLimit) -> [String] {
        guard let description, !description.isEmpty else { return [] }
        let items = matches(of: #"<li[^>]*>(.*?)</li>"#, in: description)
        let raw: [String]
        if items.isEmpty {
            let breaks = description.replacingOccurrences(
                of: #"<\s*(br|/p|/div|/h[1-6])\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            raw = breaks.components(separatedBy: .newlines)
        } else {
            raw = items
        }
        let cleaned = raw.map(clean).filter { !$0.isEmpty }
        return Array(cleaned.prefix(limit))
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func clean(_ line: String) -> String {
        var text = line.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, character) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
            ("&amp;", "&"),
        ] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let marker = text.first, "-*\u{2022}".contains(marker) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
