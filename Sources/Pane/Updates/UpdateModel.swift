import Foundation
import Observation
import os

/// A newer Pane found in the feed, reduced to what Pane's surfaces show.
struct AvailableUpdate: Equatable, Sendable {
    /// The version people see ("1.1"), the feed item's display version.
    let version: String
    /// The download's size in bytes, when the feed gives one.
    let size: UInt64?
    /// Every line of the item's description. The popup shows the first
    /// `ReleaseNotes.popupLineLimit`; What's new shows them all.
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
    /// Try again after a failure the Version row shows: checks again, and downloads again
    /// when the download or its checks failed.
    case retry
}

/// What failed, for the Version row's error line.
enum UpdateFailure: Equatable, Sendable {
    /// A check the user started.
    case check
    /// A download the user started or watched.
    case download(version: String)
    /// Sparkle couldn't unpack the download, or a signature didn't match.
    case verify(version: String)
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
    case error(UpdateFailure)
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
/// `UpdateDriver` feeds it Sparkle's events; the surfaces send the user's choices back
/// through `perform(_:)`.
///
/// Rules (the in-row update board, 2026-11-18):
/// - Settings' Version row shows every state. The popup (`surface`) is only for what Pane's
///   own background check finds while Settings is closed: an update that waits for Download
///   or is ready. It follows a download started from its own Download button.
/// - A check the user starts (the row's button, or Check for Updates…, which opens Settings)
///   never raises the popup: the row shows every step, including Ready.
/// - Opening Settings closes the popup and keeps Sparkle's pending reply for the row; nothing
///   raises the popup while Settings is open. Closing Settings answers a reply still pending
///   as Later would, so Sparkle isn't left waiting.
/// - Later hides the popup and keeps the update: it installs when Pane quits.
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
        /// The engine is quitting Pane to install `update` (nil when the engine started it
        /// on its own).
        case installing(AvailableUpdate?)
        /// A check the user started found nothing newer.
        case upToDate
        /// A check or download the user started failed.
        case failed(UpdateFailure)
    }

    /// The running version ("1.0").
    let currentVersion: String
    private(set) var phase = Phase.idle {
        didSet { publish() }
    }
    /// The popup is wanted for the current phase. False after Later, while Settings is
    /// open, and for anything the user started from Settings.
    private(set) var wantsSurface = false {
        didSet { publish() }
    }
    private(set) var lastChecked: Date?
    /// Later was pressed on a ready update (or Settings closed on one): it installs on quit,
    /// and the row says so.
    private(set) var isDeferred = false
    /// Restart to update, after Later, couldn't reach the feed. The update still installs
    /// on quit.
    private(set) var restartFailed = false
    /// The Settings window is open: the popup stays down and the row shows everything.
    private(set) var isSettingsOpen = false
    /// The version this launch updated to, until Settings has been open once ("Updated to X").
    private(set) var updatedTo: String?
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
    /// Download or Try again was pressed with no prompt to answer: the next offer of this
    /// update is answered with install straight away.
    @ObservationIgnored private var downloadRequested = false
    /// The running cycle began with Check for Updates…, so it reports back.
    @ObservationIgnored private var userInitiated = false
    @ObservationIgnored private var published: UpdatePresentation?
    #if DEBUG
        /// Holds `pane://check-update`'s stand-in engine (`engine` is weak).
        @ObservationIgnored private var demoEngine: DemoUpdateEngine?
    #endif

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
        case .installing(let update): update
        case .idle, .checking, .upToDate, .failed: nil
        }
    }

    /// Whether the row's action is the moss Restart to update (dimmed while it can't run yet).
    var offersRestart: Bool {
        switch phase {
        case .downloading, .ready, .installing: true
        case .idle, .checking, .available, .upToDate, .failed: false
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

    /// What the popup shows now.
    var presentation: UpdatePresentation? {
        guard wantsSurface, !isSettingsOpen else { return nil }
        switch phase {
        case .idle, .checking, .installing: return nil
        case .available(let update): return .available(update)
        case .downloading(let update, let progress): return .downloading(update, fraction: progress.fraction)
        case .ready(let update): return .ready(update)
        case .upToDate: return .upToDate(version: currentVersion)
        case .failed(let failure): return .error(failure)
        }
    }

    /// Raises the popup for something Pane's own check found, unless the user is in
    /// Settings or started the cycle there.
    private func offerInPopup() {
        if !userInitiated, !isSettingsOpen { wantsSurface = true }
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
                // Already downloaded: there is nothing newer to ask the feed for.
                if !isSettingsOpen { wantsSurface = true }
                return
            }
            engine?.checkForUpdates()
        case .download:
            guard case .available(let update) = phase, let reply = takeReply() else {
                requestDownload()
                return
            }
            // From the popup's own Download the popup follows the download; from the row
            // it stays in the row.
            phase = .downloading(update, UpdateProgress(expected: update.size))
            if wantsSurface { userInitiated = true }
            reply(.install)
        case .retry:
            switch phase {
            case .failed(.download), .failed(.verify): requestDownload()
            case .failed(.check): engine?.checkForUpdates()
            case .ready: perform(.restart)
            case .idle, .checking, .available, .downloading, .installing, .upToDate: break
            }
        case .cancelDownload:
            guard case .downloading = phase else { return }
            let cancel = cancelDownload
            cancelDownload = nil
            wantsSurface = false
            phase = .idle
            cancel?()
        case .restart:
            guard let update else { return }
            wantsSurface = false
            restartFailed = false
            if let installNow {
                phase = .installing(update)
                installNow()
            } else if let reply = takeReply() {
                phase = .installing(update)
                reply(.install)
            } else {
                // After Later the prompt was answered; a new check brings the pending update
                // back as a prompt, answered with install (`found`). A failed check puts the
                // row back on Ready with the failure (`failed`).
                restartRequested = true
                phase = .installing(update)
                engine?.checkForUpdates()
            }
        case .later:
            wantsSurface = false
            if case .ready = phase { isDeferred = true }
            takeReply()?(.dismiss)
        case .dismiss:
            wantsSurface = false
            switch phase {
            case .upToDate, .failed: phase = .idle
            case .idle, .checking, .available, .downloading, .ready, .installing: break
            }
        }
    }

    /// Download or Try again with no prompt open: check again and take the offer.
    private func requestDownload() {
        guard let engine, engine.canCheckForUpdates else { return }
        downloadRequested = true
        engine.checkForUpdates()
    }

    // MARK: Settings

    /// Settings opened: the popup closes and the row takes over, with any pending reply.
    func settingsDidOpen() {
        isSettingsOpen = true
        wantsSurface = false
        publish()
    }

    /// Settings closed. A result nobody is looking at any more ("Up to date", a failure) is
    /// cleared, "Updated to X" has been seen, and a prompt still waiting is answered as Later
    /// would, so Sparkle isn't left holding it: a ready update installs on quit.
    func settingsDidClose() {
        isSettingsOpen = false
        updatedTo = nil
        restartFailed = false
        perform(.dismiss)
        if pendingReply != nil {
            if case .ready = phase { isDeferred = true }
            takeReply()?(.dismiss)
        }
    }

    // MARK: Updated to X

    /// The key under which the last version that ran is kept.
    static let lastRunVersionKey = "PaneLastRunVersion"

    /// Records this launch's version, and notes "Updated to X" when the last launch ran an
    /// older one. A first launch (nothing stored) is not an update.
    func noteLaunch(defaults: UserDefaults = .standard) {
        let last = defaults.string(forKey: Self.lastRunVersionKey)
        defaults.set(currentVersion, forKey: Self.lastRunVersionKey)
        guard let last, last.compare(currentVersion, options: .numeric) == .orderedAscending else { return }
        updatedTo = currentVersion
    }

    func openReleaseNotes() {
        if let url = update?.releaseNotesURL { openURL(url) }
    }

    // MARK: The engine's events (`UpdateDriver`)

    /// The user started a check.
    func checkStarted() {
        userInitiated = true
        switch phase {
        case .idle, .upToDate, .failed, .available:
            wantsSurface = false
            phase = .checking
        case .checking, .downloading, .ready, .installing: break
        }
    }

    /// The engine found `update`. `downloaded` is true when it's already on disk (downloaded
    /// unseen, or armed to install on quit).
    func found(_ update: AvailableUpdate, downloaded: Bool, reply: @escaping (UpdateReply) -> Void) {
        if downloaded {
            if restartRequested {
                restartRequested = false
                phase = .installing(update)
                reply(.install)
                return
            }
            downloadRequested = false
            pendingReply = reply
            phase = .ready(update)
            offerInPopup()
        } else if downloadsAutomatically || downloadRequested {
            // A check the user started downloads straight away, as Pane's own check would
            // have, and the row shows its progress because they are waiting for it.
            downloadRequested = false
            restartRequested = false
            phase = .downloading(update, UpdateProgress(expected: update.size))
            reply(.install)
        } else {
            pendingReply = reply
            phase = .available(update)
            offerInPopup()
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
            phase = .installing(update)
            reply(.install)
            return
        }
        pendingReply = reply
        isDeferred = false
        // The popup stays up only when it followed the download from its own button.
        phase = .ready(update)
    }

    /// A download nobody watched finished and installs on quit; `installNow` installs and
    /// reopens Pane at once.
    func readyOnQuit(_ update: AvailableUpdate, installNow: @escaping () -> Void) {
        self.installNow = installNow
        isDeferred = false
        phase = .ready(update)
        offerInPopup()
    }

    /// A check found nothing newer.
    func notFound() {
        downloadRequested = false
        if restartRequested, case .installing(let update?) = phase {
            restartRequested = false
            restartFailed = true
            phase = .ready(update)
            return
        }
        restartRequested = false
        guard case .checking = phase else { return }
        phase = .upToDate
    }

    /// The engine is installing (Pane is about to quit).
    func installing() {
        wantsSurface = false
        phase = .installing(update)
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

    /// The failure the row shows for what was running when `failed` came.
    private var failureHere: UpdateFailure? {
        switch phase {
        case .checking: return .check
        case .available(let update): return .download(version: update.version)
        case .downloading(let update, let progress):
            return progress.stage == .preparing ? .verify(version: update.version) : .download(version: update.version)
        case .failed(let failure): return failure
        case .idle, .upToDate: return .check
        case .ready, .installing: return nil
        }
    }

    /// Any failure. Shown in the row only when the user started the check or is watching the
    /// download; otherwise logged, and the next scheduled check retries. A downloaded update
    /// stays: Restart after Later that couldn't reach the feed says so and keeps it.
    func failed(_ error: any Error) {
        Self.log.error("Update failed: \(error.localizedDescription, privacy: .public)")
        let watched = userInitiated || wantsSurface || downloadRequested
        let failure = failureHere
        pendingReply = nil
        cancelDownload = nil
        defer {
            restartRequested = false
            downloadRequested = false
        }
        if restartRequested, case .installing(let update?) = phase {
            restartFailed = true
            phase = .ready(update)
            return
        }
        if case .ready = phase { return }
        wantsSurface = false
        if watched, let failure {
            phase = .failed(failure)
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
        func demo(_ phase: Phase, surface: Bool, lastChecked: Date?, enabled: Bool = true) {
            isEnabled = enabled
            if demoEngine == nil {
                let stand = DemoUpdateEngine()
                demoEngine = stand
                engine = stand
            }
            self.lastChecked = lastChecked
            self.phase = phase
            wantsSurface = surface
        }

        /// The flags the demo states need besides the phase.
        func demoFlags(deferred: Bool = false, restartFailed: Bool = false, updatedTo: String? = nil) {
            isDeferred = deferred
            self.restartFailed = restartFailed
            self.updatedTo = updatedTo
        }
    #endif
}

#if DEBUG
    /// Stands in for Sparkle under `pane://check-update`, so the Version row shows what a
    /// release build shows: Check for Updates enabled after a result and off only while a check
    /// or a download runs. It never checks.
    @MainActor
    final class DemoUpdateEngine: UpdateEngine {
        var canCheckForUpdates = true
        var lastUpdateCheckDate: Date?
        var automaticallyChecksForUpdates = true
        var updateCheckInterval = UpdateCheckInterval.daily.rawValue
        var automaticallyDownloadsUpdates = false
        func checkForUpdates() {}
    }
#endif

/// Release-note lines for a surface from a feed item's description, which is HTML (a `<ul>`
/// from the release workflow) or plain lines.
enum ReleaseNotes {
    /// The popup shows this many; What's new shows every line.
    static let popupLineLimit = 3

    /// The list items, or else the non-empty lines (at most `limit`), with tags and list
    /// markers removed and the common entities decoded.
    static func lines(from description: String?, limit: Int = .max) -> [String] {
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
