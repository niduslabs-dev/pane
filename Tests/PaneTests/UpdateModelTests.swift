import Foundation
import Testing

@testable import Pane

/// One release in a fake feed.
private struct FeedItem {
    let version: String
    let size: UInt64
    var notes = "<ul><li>Faster</li><li>Fixes &amp; polish</li></ul>"
}

/// Stands in for Sparkle: reads a fake feed and calls the model in the order `UpdateDriver`
/// does for Sparkle's user-driver and delegate callbacks. Each step that Sparkle spreads
/// over time is a method, so a test stops wherever it needs to look.
@MainActor
private final class FakeEngine: UpdateEngine {
    struct FeedDown: LocalizedError {
        var errorDescription: String? { "The feed couldn't be read." }
    }

    let model: UpdateModel
    let installed: String
    var feed: [FeedItem]
    var feedIsDown = false

    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates = true
    var updateCheckInterval: TimeInterval = UpdateCheckInterval.daily.rawValue
    var automaticallyDownloadsUpdates = true

    private(set) var userChecks = 0
    private(set) var replies: [UpdateReply] = []
    private(set) var installNowCalls = 0
    private(set) var cancelled = false
    /// The newest item is on disk: downloaded unseen and armed for quit, or unpacked after
    /// a download the user watched. Sparkle offers it again as already downloaded.
    private(set) var onDisk = false
    private var offered: FeedItem?

    init(model: UpdateModel, installed: String = "1.0", feed: [FeedItem] = []) {
        self.model = model
        self.installed = installed
        self.feed = feed
    }

    private var newest: FeedItem? {
        feed.max { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
            .flatMap { $0.version.compare(installed, options: .numeric) == .orderedDescending ? $0 : nil }
    }

    private func update(_ item: FeedItem) -> AvailableUpdate {
        AvailableUpdate(
            version: item.version, size: item.size, notes: ReleaseNotes.lines(from: item.notes),
            releaseNotesURL: URL(string: "https://github.com/niduslabs-dev/pane/releases/tag/v\(item.version)"))
    }

    private func record(_ reply: UpdateReply) {
        replies.append(reply)
    }

    private func finishCycle(at date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        lastUpdateCheckDate = date
        model.cycleFinished(lastChecked: date)
    }

    /// Check for Updates…: `showUserInitiatedUpdateCheck`, then found, not found or an error.
    func checkForUpdates() {
        userChecks += 1
        model.checkStarted()
        if feedIsDown {
            model.failed(FeedDown())
            finishCycle()
            model.cycleEnded()
            return
        }
        guard let item = newest else {
            model.notFound()
            finishCycle()
            model.cycleEnded()
            return
        }
        offered = item
        model.found(update(item), downloaded: onDisk) { [weak self] in self?.record($0) }
    }

    /// The scheduled check. Silent when nothing is newer or the feed is down; with automatic
    /// downloads on it downloads unseen and arms the install for quit.
    func scheduledCheck() {
        if feedIsDown {
            model.failed(FeedDown())
            model.cycleEnded()
            return
        }
        guard let item = newest else {
            finishCycle()
            return
        }
        offered = item
        if automaticallyDownloadsUpdates {
            onDisk = true
            model.readyOnQuit(update(item)) { [weak self] in self?.installNowCalls += 1 }
            finishCycle()
        } else {
            model.found(update(item), downloaded: false) { [weak self] in self?.record($0) }
        }
    }

    /// The download after an install reply, in `chunks` equal parts, then unpacking.
    func download(chunks: Int = 4, stopAfter: Int? = nil) {
        guard let offered else { return }
        model.downloadStarted { [weak self] in self?.cancelled = true }
        model.downloadExpects(offered.size)
        for _ in 0..<(stopAfter ?? chunks) {
            model.downloadReceived(offered.size / UInt64(chunks))
        }
    }

    func unpack() {
        model.preparing(0)
        model.preparing(0.5)
        model.preparing(1)
        onDisk = true
        model.readyToInstall { [weak self] in self?.record($0) }
    }

    func downloadFails() {
        model.failed(FeedDown())
        model.cycleEnded()
    }

    /// Unpacking or a signature check fails after the download.
    func verifyFails() {
        model.preparing(0)
        model.failed(FeedDown())
        model.cycleEnded()
    }
}

@MainActor
private final class RecordingSurface: UpdateSurface {
    private(set) var shown: [UpdatePresentation?] = []
    var current: UpdatePresentation? { shown.last ?? nil }

    func updatePresentationChanged(_ presentation: UpdatePresentation?) {
        shown.append(presentation)
    }
}

/// The update rules, driven through `UpdateModel` by a fake feed the way `UpdateDriver`
/// drives it from Sparkle's events.
@MainActor
@Suite struct UpdateModelTests {
    private let newer = FeedItem(version: "1.1", size: 4_000_000)

    private func make(feed: [FeedItem], automaticDownloads: Bool = true) -> (UpdateModel, FakeEngine, RecordingSurface)
    {
        let model = UpdateModel(currentVersion: "1.0")
        let engine = FakeEngine(model: model, feed: feed)
        engine.automaticallyDownloadsUpdates = automaticDownloads
        model.attach(engine)
        let surface = RecordingSurface()
        model.surface = surface
        return (model, engine, surface)
    }

    private var update: AvailableUpdate {
        AvailableUpdate(
            version: "1.1", size: 4_000_000, notes: ["Faster", "Fixes & polish"],
            releaseNotesURL: URL(string: "https://github.com/niduslabs-dev/pane/releases/tag/v1.1"))
    }

    // MARK: Check for Updates…

    @Test func demoStatesEnableCheckLikeARelease() {
        let model = UpdateModel(currentVersion: "1.0")
        model.demo(.upToDate, surface: false, lastChecked: .now)
        #expect(model.canCheck)
        model.demo(.failed(.check), surface: false, lastChecked: .now)
        #expect(model.canCheck)
        model.demo(.checking, surface: false, lastChecked: .now)
        #expect(!model.canCheck)
    }

    @Test func menuItemIsOffWithoutAnEngine() {
        let model = UpdateModel(currentVersion: "1.0")
        #expect(!model.isEnabled)
        #expect(!model.canCheck)
        model.perform(.check)
        #expect(model.phase == .idle)
    }

    @Test func userCheckWithNothingNewerSaysUpToDate() {
        let (model, engine, surface) = make(feed: [FeedItem(version: "1.0", size: 1)])
        model.perform(.check)
        #expect(engine.userChecks == 1)
        #expect(model.phase == .upToDate)
        // The result is the row's; the popup never shows it.
        #expect(surface.shown.allSatisfy { $0 == nil })
        #expect(model.lastChecked == engine.lastUpdateCheckDate)
        model.perform(.dismiss)
        #expect(model.phase == .idle)
    }

    @Test func userCheckShowsAnError() {
        let (model, engine, surface) = make(feed: [newer])
        engine.feedIsDown = true
        model.perform(.check)
        #expect(model.phase == .failed(.check))
        #expect(surface.shown.allSatisfy { $0 == nil })
        #expect(model.canCheck)
        model.perform(.dismiss)
        #expect(model.phase == .idle)
    }

    @Test func userCheckDownloadsWithProgressThenIsReady() {
        let (model, engine, surface) = make(feed: [FeedItem(version: "1.0", size: 1), newer])
        model.perform(.check)
        #expect(engine.replies == [.install])
        #expect(model.phase == .downloading(update, UpdateProgress(expected: 4_000_000)))
        #expect(!model.canCheck)

        engine.download(chunks: 4, stopAfter: 1)
        #expect(model.versionRow().percent == 25)
        engine.download(chunks: 4, stopAfter: 3)
        engine.unpack()
        #expect(model.phase == .ready(update))
        // A check by hand never raises the popup, not even for Ready.
        #expect(surface.shown.allSatisfy { $0 == nil })

        model.perform(.restart)
        #expect(engine.replies == [.install, .install])
        #expect(model.phase == .installing(update))
    }

    @Test func progressIsIndeterminateUntilALengthIsKnown() {
        var progress = UpdateProgress()
        #expect(progress.fraction == nil)
        progress.expected = 100
        progress.received = 250
        #expect(progress.fraction == 1)
        progress.stage = .preparing
        progress.preparing = 0.4
        #expect(progress.fraction == 0.4)
    }

    @Test func aDownloadTheUserWatchesCanBeCancelledAndCanFail() {
        let (model, engine, surface) = make(feed: [newer])
        model.perform(.check)
        engine.download(stopAfter: 1)
        model.perform(.cancelDownload)
        #expect(engine.cancelled)
        #expect(model.phase == .idle)
        #expect(surface.current == nil)

        model.perform(.check)
        engine.download(stopAfter: 2)
        engine.downloadFails()
        #expect(model.phase == .failed(.download(version: "1.1")))
        #expect(surface.shown.allSatisfy { $0 == nil })
    }

    // MARK: Pane's own checks

    @Test func scheduledCheckWithNothingNewerStaysSilent() {
        let (model, engine, surface) = make(feed: [])
        engine.scheduledCheck()
        #expect(model.phase == .idle)
        #expect(surface.shown.allSatisfy { $0 == nil })
        #expect(model.lastChecked != nil)
    }

    @Test func scheduledCheckFailureIsLoggedNotShown() {
        let (model, engine, surface) = make(feed: [newer])
        engine.feedIsDown = true
        engine.scheduledCheck()
        #expect(model.phase == .idle)
        #expect(surface.shown.allSatisfy { $0 == nil })
    }

    @Test func automaticDownloadIsSilentUntilReady() {
        let (model, engine, surface) = make(feed: [newer])
        engine.scheduledCheck()
        #expect(model.phase == .ready(update))
        #expect(surface.shown.compactMap(\.self) == [.ready(update)])

        model.perform(.restart)
        #expect(engine.installNowCalls == 1)
        #expect(model.phase == .installing(update))
    }

    @Test func withAutomaticDownloadsOffTheSurfaceAsksFirst() {
        let (model, engine, surface) = make(feed: [newer], automaticDownloads: false)
        #expect(!model.downloadsAutomatically)
        engine.scheduledCheck()
        #expect(surface.current == .available(update))
        #expect(engine.replies.isEmpty)

        model.perform(.download)
        #expect(engine.replies == [.install])
        #expect(surface.current == .downloading(update, fraction: 0))
        engine.download()
        engine.unpack()
        #expect(surface.current == .ready(update))
    }

    @Test func laterOnAvailableDismissesTheOffer() {
        let (model, engine, surface) = make(feed: [newer], automaticDownloads: false)
        engine.scheduledCheck()
        model.perform(.later)
        #expect(engine.replies == [.dismiss])
        #expect(surface.current == nil)
        #expect(model.phase == .available(update))
    }

    // MARK: Later

    @Test func laterKeepsTheUpdateForQuitAndTheMenuBringsItBack() {
        let (model, engine, surface) = make(feed: [newer])
        engine.scheduledCheck()
        model.perform(.later)
        #expect(surface.current == nil)
        #expect(model.phase == .ready(update))

        model.perform(.check)
        #expect(engine.userChecks == 0)
        #expect(surface.current == .ready(update))
    }

    @Test func restartAfterLaterAsksTheEngineAgainAndInstalls() {
        let (model, engine, _) = make(feed: [newer], automaticDownloads: false)
        engine.scheduledCheck()
        model.perform(.download)
        engine.download()
        engine.unpack()
        model.perform(.later)
        #expect(engine.replies == [.install, .dismiss])

        // The prompt is gone; Restart starts a check, and the update comes back as found.
        model.perform(.restart)
        #expect(engine.userChecks == 1)
        #expect(engine.replies == [.install, .dismiss, .install])
        #expect(model.phase == .installing(update))
    }

    @Test func aFailureNeverLosesADownloadedUpdate() {
        let (model, engine, _) = make(feed: [newer])
        engine.scheduledCheck()
        model.failed(FakeEngine.FeedDown())
        #expect(model.phase == .ready(update))
    }

    @Test func aSurfaceAttachedLateSeesWhatIsPending() {
        let (model, engine, _) = make(feed: [newer])
        engine.scheduledCheck()
        let late = RecordingSurface()
        model.surface = late
        #expect(late.shown == [.ready(update)])
    }

    // MARK: Settings

    @Test func settingsComeFromTheEngineAndGoBackToIt() {
        let model = UpdateModel(currentVersion: "1.0")
        let engine = FakeEngine(model: model)
        engine.automaticallyChecksForUpdates = false
        engine.updateCheckInterval = UpdateCheckInterval.weekly.rawValue
        model.attach(engine)
        #expect(model.isEnabled)
        #expect(!model.checksAutomatically)
        #expect(model.checkInterval == .weekly)

        model.checksAutomatically = true
        model.checkInterval = .daily
        model.downloadsAutomatically = false
        #expect(engine.automaticallyChecksForUpdates)
        #expect(engine.updateCheckInterval == 86_400)
        #expect(!engine.automaticallyDownloadsUpdates)
    }

    @Test func intervalsSnapToDailyOrWeekly() {
        #expect(UpdateCheckInterval(nearest: 3_600) == .daily)
        #expect(UpdateCheckInterval(nearest: 86_400) == .daily)
        #expect(UpdateCheckInterval(nearest: 500_000) == .weekly)
        #expect(UpdateCheckInterval(nearest: 2_000_000) == .weekly)
    }

    // MARK: Where updates run

    @Test func debugBuildsNeverUpdateWithoutATestFeed() {
        let info: [String: Any] = ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "key"]
        #expect(!UpdateDriver.shouldStart(isDebug: true, feedOverride: nil, info: info))
        #expect(
            UpdateDriver.shouldStart(isDebug: true, feedOverride: URL(string: "http://localhost:8000/a.xml"), info: [:])
        )
    }

    @Test func releaseBuildsUpdateOnlyWithAFeedAndAKey() {
        #expect(!UpdateDriver.shouldStart(isDebug: false, feedOverride: nil, info: [:]))
        #expect(
            !UpdateDriver.shouldStart(
                isDebug: false, feedOverride: nil, info: ["SUFeedURL": "https://example.com/appcast.xml"]))
        #expect(
            UpdateDriver.shouldStart(
                isDebug: false, feedOverride: nil,
                info: ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "key"]))
    }

    // MARK: Release notes

    @Test func releaseNotesComeFromTheFeedsList() {
        let html = "<ul>\n<li>One</li>\n<li>Two &amp; three</li>\n<li>Four</li>\n<li>Five</li>\n</ul>"
        #expect(ReleaseNotes.lines(from: html) == ["One", "Two & three", "Four", "Five"])
        #expect(ReleaseNotes.lines(from: html, limit: ReleaseNotes.popupLineLimit) == ["One", "Two & three", "Four"])
        #expect(ReleaseNotes.lines(from: "- First\n\n* Second") == ["First", "Second"])
        #expect(ReleaseNotes.lines(from: nil).isEmpty)
    }

    // MARK: The row and the popup (in-row update board)

    @Test func aCheckFromSettingsNeverRaisesThePopup() {
        let (model, engine, surface) = make(feed: [newer], automaticDownloads: false)
        model.settingsDidOpen()
        model.perform(.check)
        #expect(model.phase == .available(update))
        model.perform(.download)
        #expect(engine.replies == [.install])
        engine.download()
        engine.unpack()
        #expect(model.phase == .ready(update))
        #expect(surface.shown.allSatisfy { $0 == nil })
        #expect(model.versionRow().action == .restart)
        #expect(model.versionRow().actionEnabled)
    }

    @Test func checkForUpdatesFromTheMenuStaysQuietAfterSettingsCloses() {
        // The menu item opens Settings and checks; the result is still the row's after a close.
        let (model, engine, surface) = make(feed: [newer], automaticDownloads: false)
        model.perform(.check)
        #expect(model.phase == .available(update))
        #expect(surface.shown.allSatisfy { $0 == nil })
        model.settingsDidClose()
        #expect(engine.replies == [.dismiss])
        #expect(surface.shown.allSatisfy { $0 == nil })
    }

    @Test func openingSettingsClosesThePopupAndTheRowKeepsTheReply() {
        let (model, engine, surface) = make(feed: [newer], automaticDownloads: false)
        engine.scheduledCheck()
        #expect(surface.current == .available(update))
        model.settingsDidOpen()
        #expect(surface.current == nil)
        #expect(engine.replies.isEmpty)
        model.perform(.download)
        #expect(engine.replies == [.install])
        #expect(engine.userChecks == 0)
        engine.download()
        engine.unpack()
        #expect(surface.current == nil)
    }

    @Test func nothingRaisesThePopupWhileSettingsIsOpen() {
        let (model, engine, surface) = make(feed: [newer])
        model.settingsDidOpen()
        engine.scheduledCheck()
        #expect(model.phase == .ready(update))
        #expect(surface.shown.allSatisfy { $0 == nil })
        // Closing Settings doesn't bring it back: the row already showed it.
        model.settingsDidClose()
        #expect(surface.shown.allSatisfy { $0 == nil })
    }

    @Test func closingSettingsOnAReadyUpdateDefersItToQuit() {
        let (model, engine, _) = make(feed: [newer], automaticDownloads: false)
        model.settingsDidOpen()
        model.perform(.check)
        model.perform(.download)
        engine.download()
        engine.unpack()
        #expect(model.versionCaption() == "Version 1.1 is ready")
        model.settingsDidClose()
        #expect(engine.replies == [.install, .dismiss])
        #expect(model.versionCaption() == "1.1 installs when Pane quits")
    }

    @Test func laterSaysItInstallsOnQuit() {
        let (model, engine, _) = make(feed: [newer])
        engine.scheduledCheck()
        model.perform(.later)
        #expect(model.isDeferred)
        #expect(model.versionCaption() == "1.1 installs when Pane quits")
        #expect(model.versionRow().whatsNewVersion == "1.1")
    }

    @Test func restartAfterLaterOfflineKeepsTheUpdateAndSaysSo() {
        let (model, engine, _) = make(feed: [newer], automaticDownloads: false)
        engine.scheduledCheck()
        model.perform(.download)
        engine.download()
        engine.unpack()
        model.perform(.later)
        engine.feedIsDown = true
        model.perform(.restart)
        #expect(model.phase == .ready(update))
        #expect(model.versionCaption() == "Couldn't restart. It installs on quit.")
        #expect(model.versionRow().isError)
        #expect(model.versionRow().action == .restart)
        // Back online, Restart installs.
        engine.feedIsDown = false
        model.perform(.restart)
        #expect(model.phase == .installing(update))
        #expect(!model.restartFailed)
    }

    @Test func aFailedDownloadTriesAgainByCheckingThenDownloading() {
        let (model, engine, _) = make(feed: [newer], automaticDownloads: false)
        model.settingsDidOpen()
        model.perform(.check)
        model.perform(.download)
        engine.download(stopAfter: 1)
        engine.downloadFails()
        #expect(model.versionCaption() == "Couldn't download 1.1.")
        #expect(model.versionRow().action == .retry)
        #expect(model.versionRow().actionTitle == "Try again")

        model.perform(.retry)
        #expect(engine.userChecks == 2)
        #expect(engine.replies == [.install, .install])
        #expect(model.versionRow().action == .restart)
        #expect(!model.versionRow().actionEnabled)
    }

    @Test func aFailureWhilePreparingIsCouldntVerify() {
        let (model, engine, _) = make(feed: [newer])
        model.perform(.check)
        engine.download()
        engine.verifyFails()
        #expect(model.phase == .failed(.verify(version: "1.1")))
        #expect(model.versionCaption() == "Couldn't verify 1.1.")
        model.perform(.retry)
        #expect(model.phase == .downloading(update, UpdateProgress(expected: 4_000_000)))
    }

    @Test func aDownloadFromThePopupLetsThePopupFollowIt() {
        let (model, engine, surface) = make(feed: [newer], automaticDownloads: false)
        engine.scheduledCheck()
        model.perform(.download)
        engine.download(stopAfter: 2)
        #expect(surface.current == .downloading(update, fraction: 0.5))
        engine.downloadFails()
        // The popup goes; a failure shows only in the row.
        #expect(surface.current == nil)
        #expect(model.phase == .failed(.download(version: "1.1")))
    }

    // MARK: Updated to X

    @Test func updatedToShowsAfterAnUpdateUntilSettingsCloses() throws {
        let suite = "dev.niduslabs.pane.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = UpdateModel(currentVersion: "1.0.2")
        first.noteLaunch(defaults: defaults)
        #expect(first.updatedTo == nil)

        let same = UpdateModel(currentVersion: "1.0.2")
        same.noteLaunch(defaults: defaults)
        #expect(same.updatedTo == nil)

        let updated = UpdateModel(currentVersion: "1.0.3")
        updated.attach(FakeEngine(model: updated, installed: "1.0.3"))
        updated.noteLaunch(defaults: defaults)
        #expect(updated.updatedTo == "1.0.3")
        #expect(updated.versionCaption() == "Updated to 1.0.3")
        #expect(updated.versionRow().whatsNewVersion == "1.0.3")
        updated.settingsDidOpen()
        updated.settingsDidClose()
        #expect(updated.updatedTo == nil)
        #expect(updated.versionCaption() == "Not checked yet")
    }

    // MARK: What's new

    @Test func whatsNewListsThePendingUpdateThenTheBundledFile() {
        let (model, engine, _) = make(feed: [
            FeedItem(version: "1.1", size: 4_000_000, notes: "<ul><li>A</li><li>B</li><li>C</li><li>D</li></ul>")
        ])
        let bundled = ReleaseNotesFile.parse(
            "# Release notes\n\nIntro.\n\n## 1.2\n\n- Unreleased\n\n## 1.0\n\n- One\n- Two\n\n## 0.9\n\n- Zero\n")
        #expect(bundled.map(\.version) == ["1.2", "1.0", "0.9"])

        #expect(model.whatsNew(bundled: bundled).map(\.version) == ["1.0", "0.9"])
        #expect(model.whatsNew(bundled: bundled).first?.tag == "Installed")

        engine.scheduledCheck()
        let groups = model.whatsNew(bundled: bundled)
        #expect(groups.map(\.version) == ["1.1", "1.0", "0.9"])
        #expect(groups.first?.tag == "Ready to install")
        // Every line of the feed, not the popup's three.
        #expect(groups.first?.lines == ["A", "B", "C", "D"])
        #expect(model.whatsNew(bundled: []).count == 1)
    }

    @Test func whatsNewIsEmptyWithNoNotes() {
        let model = UpdateModel(currentVersion: "1.0")
        #expect(model.whatsNew(bundled: []).isEmpty)
    }

    @Test func theBundledFileIsPanesOwn() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../RELEASE_NOTES.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let groups = ReleaseNotesFile.parse(text)
        #expect(groups.contains { $0.version == "1.0.0" })
        // One line style: no full stop at the end of a line.
        for group in groups {
            for line in group.lines { #expect(!line.hasSuffix("."), "\(group.version): \(line)") }
        }
    }

}
