import Foundation
import Testing

@testable import Pane

/// What the update surfaces say and when the popup shows (canvas board 15).
@MainActor
@Suite struct UpdateSurfaceTests {
    private struct FeedDown: Error {}

    private let update = AvailableUpdate(
        version: "1.1", size: 6_000_000, notes: ["One"], releaseNotesURL: URL(string: "https://example.com/notes"))
    private let locale = Locale(identifier: "en_GB")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// 17 November 2026, 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_916_800)

    private func caption(_ model: UpdateModel) -> String {
        model.versionCaption(now: now, locale: locale, calendar: calendar)
    }

    @Test func versionRowFollowsACheckByHand() {
        let model = UpdateModel(currentVersion: "1.0")
        #expect(caption(model) == "This build doesn't update itself.")
        model.checkStarted()
        #expect(caption(model) == "Checking for updates\u{2026}")
        #expect(model.isChecking)
        model.cycleFinished(lastChecked: now)
        model.notFound()
        #expect(caption(model) == "Up to date \u{00B7} checked just now")
        #expect(!model.hasFailed)
    }

    @Test func aFailedCheckSaysSoInTheCaption() {
        let model = UpdateModel(currentVersion: "1.0")
        model.demo(.idle, surface: false, lastChecked: nil)
        model.checkStarted()
        model.failed(FeedDown())
        #expect(caption(model) == "Couldn't check for updates.")
        #expect(model.hasFailed)
        // Closing Settings clears it.
        model.perform(.dismiss)
        #expect(!model.hasFailed)
    }

    @Test func versionRowWhileAnUpdateDownloadsAndWaits() {
        let model = UpdateModel(currentVersion: "1.0")
        model.cycleFinished(lastChecked: now.addingTimeInterval(-10_080))
        model.checkStarted()
        model.found(update, downloaded: false) { _ in }
        #expect(caption(model) == "Downloading 1.1")
        #expect(model.versionRow().percent == 0)
        model.downloadExpects(6_000_000)
        model.downloadReceived(2_520_000)
        #expect(model.versionRow().line == "Downloading 1.1 \u{00B7} 42%")
        model.preparing(0.5)
        #expect(caption(model) == "Preparing 1.1\u{2026}")
        #expect(model.versionRow().spinner)
        #expect(model.versionRow().percent == nil)
        model.readyToInstall { _ in }
        #expect(caption(model) == "Version 1.1 is ready")
        #expect(model.isReady)
    }

    @Test func theDownloadsLengthIsUnknownAtFirst() {
        let model = UpdateModel(currentVersion: "1.0")
        model.checkStarted()
        model.found(
            AvailableUpdate(version: "1.1", size: nil, notes: [], releaseNotesURL: nil), downloaded: false
        ) { _ in }
        #expect(caption(model) == "Downloading 1.1\u{2026}")
        #expect(model.versionRow().percent == nil)
        #expect(model.versionRow().action == .restart)
        #expect(!model.versionRow().actionEnabled)
    }

    @Test func everyRowStateHasItsButton() {
        let model = UpdateModel(currentVersion: "1.0.2")
        var row = model.versionRow(now: now, locale: locale, calendar: calendar)
        #expect(row.caption == "This build doesn't update itself.")
        #expect(!row.showsWhatsNew)
        #expect(!row.actionEnabled)

        model.demo(.idle, surface: false, lastChecked: nil)
        row = model.versionRow(now: now, locale: locale, calendar: calendar)
        #expect(row.caption == "Not checked yet")
        #expect(row.title == "Version 1.0.2")
        #expect(row.actionTitle == "Check for updates")
        #expect(row.showsWhatsNew)
        #expect(row.whatsNewAccessibilityLabel == "What's new in Pane 1.0.2")

        model.demo(.available(update), surface: false, lastChecked: nil)
        row = model.versionRow()
        #expect(row.caption == "Version 1.1 is available")
        #expect(row.actionTitle == "Download")
        #expect(row.actionAccessibilityLabel == "Download Pane 1.1")
        #expect(!row.actionIsPrimary)

        model.demo(.ready(update), surface: false, lastChecked: nil)
        row = model.versionRow()
        #expect(row.actionIsPrimary)
        #expect(row.actionAccessibilityLabel == "Restart to update to Pane 1.1")
        #expect(row.whatsNewAccessibilityLabel == "What's new in Pane 1.1")

        model.demo(.installing(update), surface: false, lastChecked: nil)
        row = model.versionRow()
        #expect(row.caption == "Installing 1.1\u{2026}")
        #expect(row.spinner)
        #expect(!row.actionEnabled)

        model.demo(.checking, surface: false, lastChecked: nil)
        row = model.versionRow()
        #expect(row.spinner)
        #expect(!row.actionEnabled)
    }

    @Test func checkedPhraseNamesTheDay() {
        func phrase(_ secondsAgo: TimeInterval) -> String {
            UpdateModel.checkedPhrase(
                now.addingTimeInterval(-secondsAgo), now: now, locale: locale, calendar: calendar)
        }
        #expect(phrase(30) == "just now")
        #expect(phrase(3 * 3600).hasPrefix("today at "))
        #expect(phrase(3 * 3600).hasSuffix("9:00"))
        #expect(phrase(18 * 3600) == "yesterday at 18:00")
        #expect(phrase(5 * 86_400) == "on 12 Nov")
    }

    @Test func popupCopyWhenAutomaticInstallsAreOff() {
        let model = UpdateModel(currentVersion: "1.0")
        model.downloadsAutomatically = false
        model.found(update, downloaded: false) { _ in }
        #expect(model.popupTitle == "Pane 1.1 is available")
        #expect(model.sizeDetail == "6 MB")
        #expect(model.barFraction(ceiling: 0.9) == nil)
        model.perform(.download)
        #expect(model.popupTitle == "Downloading Pane 1.1")
        model.downloadExpects(6_000_000)
        model.downloadReceived(2_100_000)
        #expect(model.sizeDetail == "2.1 of 6 MB")
        #expect(abs((model.barFraction(ceiling: 0.9) ?? 0) - 0.315) < 0.0001)
        // Fully downloaded but not verified yet: the bar holds at the ceiling.
        model.downloadReceived(3_900_000)
        #expect(model.barFraction(ceiling: 0.9) == 0.9)
        model.preparing(0.5)
        #expect(model.barFraction(ceiling: 0.9) == 0.9)
        #expect(model.sizeDetail == "6 MB")
        model.readyToInstall { _ in }
        #expect(model.popupTitle == "Pane 1.1 is ready")
        #expect(model.sizeDetail == "6 MB, downloaded")
        #expect(model.barFraction(ceiling: 0.9) == nil)
    }

    @Test func sizesReadAsMegabytes() {
        #expect(UpdateModel.megabytes(6_000_000) == "6 MB")
        #expect(UpdateModel.megabytes(6_400_000) == "6 MB")
        #expect(UpdateModel.megabytes(400_000) == "0.4 MB")
    }

    @Test func thePopupShowsReadyAndAvailableAndFollowsItsOwnDownload() {
        #expect(UpdatePopupController.shows(.ready(update), whilePresented: false))
        #expect(UpdatePopupController.shows(.available(update), whilePresented: false))
        // A download started by Check for Updates stays in Settings until it is ready.
        #expect(!UpdatePopupController.shows(.downloading(update, fraction: 0.3), whilePresented: false))
        #expect(UpdatePopupController.shows(.downloading(update, fraction: 0.3), whilePresented: true))
        // Results of a check by hand belong to the Version row.
        #expect(!UpdatePopupController.shows(.upToDate(version: "1.0"), whilePresented: true))
        #expect(!UpdatePopupController.shows(.error(.check), whilePresented: true))
        #expect(!UpdatePopupController.shows(nil, whilePresented: true))
    }

    @Test func installUpdatesAutomaticallyIsTheDownloadSetting() {
        let model = UpdateModel(currentVersion: "1.0")
        #expect(model.installsAutomatically)
        model.installsAutomatically = false
        #expect(!model.downloadsAutomatically)
    }
}
