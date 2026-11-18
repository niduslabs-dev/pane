import AppKit
import Sparkle

/// Runs Sparkle with Pane's own surfaces. Sparkle does the scheduled check, the download,
/// the EdDSA and code signature checks and the swap; this object turns its events into
/// `UpdateModel` changes, so none of Sparkle's windows ever appear.
///
/// Only release builds that carry a feed update (`UpdateDriver.shouldStart`). A debug build
/// has its own bundle ID and must never replace itself with a release build; it starts
/// Sparkle only when `-PaneUpdateFeed <url>` points it at a local test appcast.
@MainActor
final class UpdateDriver: NSObject, SPUUserDriver, SPUUpdaterDelegate, UpdateEngine {
    /// The debug-only launch argument naming a test appcast.
    static let feedOverrideKey = "PaneUpdateFeed"

    let model: UpdateModel
    private var updater: SPUUpdater?
    private let feedOverride: URL?

    init(model: UpdateModel, feedOverride: URL? = nil) {
        self.model = model
        self.feedOverride = feedOverride
        super.init()
    }

    /// Whether this copy of Pane updates itself: never a debug build (unless it was given a
    /// test feed), and only a bundle whose Info.plist names a feed and its public key.
    /// `scripts/build-app.sh` writes those only into Developer ID builds.
    static func shouldStart(isDebug: Bool, feedOverride: URL?, info: [String: Any]) -> Bool {
        if isDebug { return feedOverride != nil }
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return !feed.isEmpty && !key.isEmpty
    }

    /// Starts Sparkle's scheduler. A start failure (a bundle Sparkle can't update) is logged
    /// and leaves updates off.
    func start() {
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try updater.start()
        } catch {
            UpdateModel.log.error("Updater didn't start: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.updater = updater
        model.attach(self)
        if feedOverride != nil, !Self.skipsLaunchCheck { updater.checkForUpdatesInBackground() }
    }

    /// `-PaneUpdateNoLaunchCheck YES` (debug): a test feed doesn't get the background check at
    /// launch, so a check can start from Settings' row first (`update-e2e.sh`).
    private static var skipsLaunchCheck: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "PaneUpdateNoLaunchCheck")
        #else
            false
        #endif
    }

    // MARK: UpdateEngine

    var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? false }
    var lastUpdateCheckDate: Date? { updater?.lastUpdateCheckDate }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { updater?.updateCheckInterval ?? UpdateCheckInterval.daily.rawValue }
        set { updater?.updateCheckInterval = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set { updater?.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        guard let updater, updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? { feedOverride?.absoluteString }

    /// A download nobody watched is ready. Returning true keeps Sparkle from presenting it
    /// later itself; it still installs when Pane quits (Later), or at once through
    /// `immediateInstallHandler` (Restart to Update).
    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        UpdateModel.log.info("Update \(item.displayVersionString, privacy: .public) downloaded; installs on quit")
        model.readyOnQuit(Self.update(from: item), installNow: immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        model.cycleFinished(lastChecked: updater.lastUpdateCheckDate)
    }

    // MARK: SPUUserDriver

    /// Never shown: `SUEnableAutomaticChecks` is set in Info.plist, so this is only a fallback.
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { model.checkStarted() }

    func showUpdateFound(
        with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        // An information-only item has nothing to install; Pane has no surface for it.
        guard !appcastItem.isInformationOnlyUpdate else {
            UpdateModel.log.info(
                "Information-only update \(appcastItem.displayVersionString, privacy: .public) ignored")
            model.notFound()
            reply(.dismiss)
            return
        }
        model.found(Self.update(from: appcastItem), downloaded: state.stage != .notDownloaded) {
            reply(Self.choice($0))
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        model.notFound()
        model.cycleFinished(lastChecked: updater?.lastUpdateCheckDate ?? .now)
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        model.failed(error)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        model.downloadStarted(cancel: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        model.downloadExpects(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        model.downloadReceived(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        model.preparing(0)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        model.preparing(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        model.readyToInstall { reply(Self.choice($0)) }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void
    ) {
        model.installing()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        model.cycleEnded()
    }

    // MARK: Mapping

    private static func choice(_ reply: UpdateReply) -> SPUUserUpdateChoice {
        switch reply {
        case .install: .install
        case .dismiss: .dismiss
        }
    }

    static func update(from item: SUAppcastItem) -> AvailableUpdate {
        AvailableUpdate(
            version: item.displayVersionString,
            size: item.contentLength > 0 ? item.contentLength : nil,
            notes: ReleaseNotes.lines(from: item.itemDescription),
            releaseNotesURL: item.fullReleaseNotesURL ?? item.releaseNotesURL ?? item.infoURL)
    }
}
