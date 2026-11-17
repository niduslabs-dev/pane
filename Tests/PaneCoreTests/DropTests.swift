import Foundation
import Testing

@testable import PaneCore

private func fixture(_ path: String) throws -> String {
    let folder = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    return try String(contentsOf: folder.appending(path: path), encoding: .utf8)
}

@Suite struct ApkBadgingTests {
    @Test func readsAnAppWithABitmapIconAndALauncher() throws {
        let badging = try #require(ApkBadging.parse(try fixture("badging/png-icon.txt")))
        #expect(badging.packageName == "dev.niduslabs.pane.droptest")
        #expect(badging.versionCode == 120)
        #expect(badging.versionName == "1.2.0")
        #expect(badging.label == "Pane Test")
        #expect(badging.iconPath == "res/mipmap-xxxhdpi-v4/ic_launcher.png")
        #expect(badging.hasDrawableIcon)
        #expect(badging.launchableActivity == "android.app.Activity")
    }

    @Test func anAdaptiveIconIsNotDrawn() throws {
        let badging = try #require(ApkBadging.parse(try fixture("badging/splito-adaptive-icon.txt")))
        #expect(badging.packageName == "dev.niduslabs.splito")
        #expect(badging.versionCode == 1_203_008)
        #expect(badging.versionName == "0.12.3+8")
        #expect(badging.label == "Splito")
        #expect(badging.iconPath == "res/mipmap-anydpi-v26/ic_launcher.xml")
        #expect(!badging.hasDrawableIcon)
        #expect(badging.launchableActivity == "dev.niduslabs.splito.MainActivity")
    }

    @Test func anAppWithNoIconOrLauncher() throws {
        let badging = try #require(ApkBadging.parse(try fixture("badging/no-icon-no-launcher.txt")))
        #expect(badging.label == "Agent Device Test IME")
        #expect(badging.iconPath == nil)
        #expect(!badging.hasDrawableIcon)
        #expect(badging.launchableActivity == nil)
    }

    @Test func nothingUsableIsNil() {
        #expect(ApkBadging.parse("") == nil)
        #expect(ApkBadging.parse("out/broken.apk: error: failed opening zip: Invalid file.") == nil)
        #expect(ApkBadging.parse("package: name='' versionCode='1'") == nil)
    }

    @Test func labelsWithQuotesAndHighestDensity() throws {
        let text = """
            package: name='a.b' versionCode='7' versionName=''
            application-label:'Tom's App'
            application-icon-160:'res/a.png'
            application-icon-480:'res/c.webp'
            application-icon-320:'res/b.png'
            """
        let badging = try #require(ApkBadging.parse(text))
        #expect(badging.label == "Tom's App")
        #expect(badging.iconPath == "res/c.webp")
        #expect(badging.versionName.isEmpty)
    }

    @Test func aapt2IsTheNewestBuildTools() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        let found = AndroidSDK.aapt2Executable(
            environment: [:], home: home, listFolder: { _ in ["9.0.0", "37.0.0", "36.1.0", "README"] },
            isExecutable: { !$0.path.contains("README") })
        #expect(found?.path == "/Users/someone/Library/Android/sdk/build-tools/37.0.0/aapt2")
        #expect(
            AndroidSDK.aapt2Executable(
                environment: [:], home: home, listFolder: { _ in [] }, isExecutable: { _ in true }) == nil)
    }
}

@Suite struct VersionTests {
    private let apk = ApkBadging(packageName: "a.b", versionCode: 140, versionName: "1.4.0")

    @Test func installedVersionComesFromDumpsys() throws {
        #expect(
            InstalledPackage.parse(try fixture("dumpsys/installed.txt"))
                == InstalledPackage(versionCode: 1_203_008, versionName: "0.12.3+8"))
        #expect(InstalledPackage.parse(try fixture("dumpsys/missing.txt")) == nil)
        #expect(InstalledPackage.lookupArguments(packageName: "a.b") == ["shell", "dumpsys", "package", "'a.b'"])
    }

    @Test func androidComparesVersionCodesNotNames() {
        #expect(VersionChange(installing: apk, over: nil) == .new)
        #expect(
            VersionChange(installing: apk, over: InstalledPackage(versionCode: 132, versionName: "1.3.2"))
                == .update(from: "1.3.2"))
        #expect(
            VersionChange(installing: apk, over: InstalledPackage(versionCode: 150, versionName: "1.5.0"))
                == .older(than: "1.5.0"))
        #expect(
            VersionChange(installing: apk, over: InstalledPackage(versionCode: 140, versionName: "whatever"))
                == .reinstall)
        // A higher name with a lower code is still older to Android.
        #expect(
            VersionChange(installing: apk, over: InstalledPackage(versionCode: 141, versionName: "1.0.0"))
                == .older(than: "1.0.0"))
        #expect(
            VersionChange(installing: apk, over: InstalledPackage(versionCode: 9, versionName: ""))
                == .update(from: "9"))
        #expect(VersionChange.older(than: "1").isDowngrade)
        #expect(!VersionChange.update(from: "1").isDowngrade)
    }
}

@Suite struct DragCardTests {
    private let apkURL = URL(filePath: "/d/splito-1.4.0.apk")
    private let splito = ApkBadging(
        packageName: "dev.niduslabs.splito", versionCode: 140, versionName: "1.4.0", label: "Splito",
        iconPath: "res/icon.png")
    private func size(_ bytes: Int64) -> String { "\(bytes / 1_000_000) MB" }

    private func card(_ items: [DraggedItem], emulator: String? = "dev_android36") -> DragCard? {
        DragCard(items: items, emulator: emulator, sizeText: size)
    }

    @Test func theFirstFrameComesFromTheFileAlone() throws {
        let card = try #require(card([DraggedItem(url: apkURL, size: 61_000_000)]))
        #expect(card.source == "dev_android36")
        #expect(card.header == "splito-1.4.0.apk · 61 MB")
        #expect(card.title == "splito-1.4.0.apk")
        #expect(card.version == nil)
        #expect(card.media == .glyph(.app))
        #expect(card.chip == "Install")
        #expect(card.tone == .neutral)
        #expect(!card.isRefused)
    }

    @Test func aapptAndTheDeviceFillIn() throws {
        var item = DraggedItem(url: apkURL, size: 61_000_000, badging: splito)
        var card = try #require(card([item]))
        #expect(card.title == "Splito")
        #expect(card.version == "1.4.0")
        #expect(card.media == .appIcon(apk: apkURL, path: "res/icon.png"))
        #expect(card.chip == "Install")
        item.change = .new
        #expect(self.card([item])?.chip == "Install")
        item.change = .update(from: "1.3.2")
        card = try #require(self.card([item]))
        #expect(card.chip == "Update from 1.3.2")
        #expect(card.tone == .neutral)
        #expect(card.announcement == "Splito 1.4.0. Update from 1.3.2.")
        item.change = .older(than: "1.5.0")
        card = try #require(self.card([item]))
        #expect(card.chip == "Older than 1.5.0")
        #expect(card.tone == .warning)
        item.change = .reinstall
        #expect(self.card([item])?.chip == "Reinstall")
    }

    @Test func adaptiveIconsGetTheGenericTile() {
        var badging = splito
        badging.iconPath = "res/mipmap-anydpi-v26/ic_launcher.xml"
        #expect(card([DraggedItem(url: apkURL, badging: badging)])?.media == .glyph(.app))
    }

    @Test func otherFilesAreCopied() throws {
        let card = try #require(card([DraggedItem(url: URL(filePath: "/d/IMG_2041.jpg"), size: 2_400_000)]))
        #expect(card.chip == "Copy to Downloads")
        #expect(card.media == .glyph(.photo))
        #expect(card.title == "IMG_2041.jpg")
        #expect(card.version == "2 MB")
        #expect(self.card([DraggedItem(url: URL(filePath: "/d/notes.pdf"))])?.media == .glyph(.file))
    }

    @Test func severalItemsAreCounted() throws {
        let card = try #require(
            card([
                DraggedItem(url: apkURL, badging: splito),
                DraggedItem(url: URL(filePath: "/d/linea-2.1.0.apk")),
                DraggedItem(url: URL(filePath: "/d/IMG_2041.jpg")),
            ]))
        #expect(card.chip == "2 apps, 1 file")
        #expect(card.header == "3 items")
        #expect(card.media == .stack(apps: 2, files: 1))
        #expect(card.title == "Splito and 2 more")
        #expect(DragCard.names(["Splito", "IMG_2041.jpg"]) == "Splito and IMG_2041.jpg")
        #expect(DragCard.counts(apps: 1, files: 0) == "1 app")
        #expect(DragCard.counts(apps: 0, files: 3) == "3 files")
    }

    @Test func foldersAndNoEmulatorAreRefused() throws {
        let folder = try #require(card([DraggedItem(url: URL(filePath: "/d/screenshots"), isDirectory: true)]))
        #expect(folder.isRefused)
        #expect(folder.chip == "No folders")
        #expect(!folder.titleIsStatus)
        #expect(folder.title == "screenshots")
        #expect(folder.media == .glyph(.folder))
        // A folder next to files is left out; the files still drop.
        let mixed = try #require(
            card([
                DraggedItem(url: URL(filePath: "/d/screenshots"), isDirectory: true), DraggedItem(url: apkURL),
            ]))
        #expect(!mixed.isRefused)
        #expect(mixed.chip == "Install")
        let none = try #require(card([DraggedItem(url: apkURL)], emulator: nil))
        #expect(none.isRefused)
        #expect(none.source == "Pane")
        #expect(none.header == "splito-1.4.0.apk")
        #expect(none.title == "No emulator running")
        #expect(none.chip == "Start an emulator first")
        #expect(none.titleIsStatus)
        #expect(card([DraggedItem(url: URL(string: "https://example.com/a.apk")!)]) == nil)
        #expect(card([]) == nil)
    }
}

@Suite struct DropJobTests {
    private func item(_ id: Int, _ path: String) -> DraggedItem { DraggedItem(url: URL(filePath: path)) }

    @Test func appsRunFirstInDropOrderThenFiles() {
        let job = DropJob(dragged: [
            item(0, "/d/notes.txt"), item(1, "/d/b.apk"), item(2, "/d/photo.JPG"), item(3, "/d/a.APK"),
            DraggedItem(url: URL(filePath: "/d/folder"), isDirectory: true),
        ])
        #expect(job.items.map(\.file.lastPathComponent) == ["b.apk", "a.APK", "notes.txt", "photo.JPG"])
        #expect(job.items.map(\.kind) == [.app, .app, .file(isMedia: false), .file(isMedia: true)])
        #expect(job.nextWaiting == 0)
    }

    @Test func aQuestionHoldsTheQueueAndAFailureDoesNot() {
        var job = DropJob(dragged: [item(0, "/d/a.apk"), item(1, "/d/b.apk"), item(2, "/d/c.txt")])
        job.items[0].state = .failed(DropFailure(title: "Couldn't install a."))
        #expect(job.nextWaiting == 1)
        job.items[1].state = .asking
        #expect(job.nextWaiting == nil)
        #expect(job.asking?.file.lastPathComponent == "b.apk")
        job.items[1].state = .skipped
        #expect(job.nextWaiting == 2)
        job.items[2].state = .copied
        #expect(job.isFinished)
        #expect(job.failures.count == 1)
    }

    @Test func titlesCountWhatWorked() {
        var job = DropJob(dragged: [
            item(0, "/d/a.apk"), item(1, "/d/b.apk"), item(2, "/d/c.jpg"), item(3, "/d/d.pdf"),
        ])
        #expect(job.title == "Installing 2 apps and copying 2 files")
        job.items[0].state = .installed
        job.items[1].state = .failed(DropFailure(title: "x"))
        job.items[2].state = .copied
        job.items[3].state = .copied
        #expect(job.title == "Installed 1 app and copied 2 files")
        #expect(job.lastInstalled?.file.lastPathComponent == "a.apk")
        #expect(DropJob(dragged: [item(0, "/d/c.jpg"), item(1, "/d/d.pdf")]).title == "Copying 2 files")
        var failed = DropJob(dragged: [item(0, "/d/a.apk")])
        failed.items[0].state = .failed(DropFailure(title: "x"))
        #expect(failed.title == "Nothing was installed")
    }

    @Test func bytesAreWrittenInTheTotalsUnit() {
        #expect(DropJob.progressText(sent: 38_000_000, total: 61_000_000) == "38 of 61 MB")
        #expect(DropJob.progressText(sent: 700_000, total: 61_000_000) == "0.7 of 61 MB")
        #expect(DropJob.progressText(sent: 90_000_000, total: 61_000_000) == "61 of 61 MB")
    }

    @Test func progressHoldsUnderTheCeiling() {
        var job = DropJob(dragged: [item(0, "/d/a.apk"), item(1, "/d/b.txt")])
        #expect(job.fraction(ceiling: 0.9) == 0)
        job.items[0].state = .sending(sent: 50, total: 100)
        #expect(job.fraction(ceiling: 0.9) == 0.225)
        job.items[0].state = .installing
        job.items[1].state = .sending(sent: 100, total: 100)
        #expect(job.fraction(ceiling: 0.9) == 0.9)
        job.items[0].state = .installed
        job.items[1].state = .copied
        #expect(job.fraction(ceiling: 0.9) == 1)
    }
}

@Suite struct DropDismissalTests {
    private let clock = ContinuousClock()
    private let afterDone = Duration.seconds(6)

    private func finished(_ state: DropJob.Item.State) -> DropJob {
        var job = DropJob(dragged: [DraggedItem(url: URL(filePath: "/d/a.apk"))])
        job.items[0].state = state
        return job
    }

    @Test func aFinishedCardClosesSixSecondsAfterItsLastResult() {
        let done = clock.now
        let job = finished(.installed)
        #expect(
            DropDismissal.decide(job: job, finishedAt: done, now: done, isHovered: false, afterDone: afterDone)
                == .wait(.seconds(6)))
        #expect(
            DropDismissal.decide(
                job: job, finishedAt: done, now: done.advanced(by: .seconds(4)), isHovered: false, afterDone: afterDone)
                == .wait(.seconds(2)))
        #expect(
            DropDismissal.decide(
                job: job, finishedAt: done, now: done.advanced(by: .seconds(6)), isHovered: false, afterDone: afterDone)
                == .close)
    }

    @Test func thePointerPausesIt() {
        let done = clock.now
        let later = done.advanced(by: .seconds(9))
        #expect(
            DropDismissal.decide(
                job: finished(.copied), finishedAt: done, now: later, isHovered: true, afterDone: afterDone) == .stay)
        #expect(
            DropDismissal.decide(
                job: finished(.copied), finishedAt: done, now: later, isHovered: false, afterDone: afterDone) == .close)
    }

    @Test func questionsFailuresAndWorkStay() {
        let done = clock.now
        let later = done.advanced(by: .seconds(60))
        for state: DropJob.Item.State in [.asking, .installing, .waiting, .failed(DropFailure(title: "x"))] {
            #expect(
                DropDismissal.decide(
                    job: finished(state), finishedAt: done, now: later, isHovered: false, afterDone: afterDone) == .stay
            )
        }
        #expect(
            DropDismissal.decide(
                job: finished(.installed), finishedAt: nil, now: later, isHovered: false, afterDone: afterDone) == .stay
        )
    }
}

@Suite struct DropTransferTests {
    @Test func installIsPushThenPmInstall() {
        let path = DropTransfer.stagingPath(token: "1A2B")
        #expect(path == "/data/local/tmp/pane-drop-1A2B.apk")
        #expect(
            DropTransfer.pushArguments(URL(filePath: "/d/My App.apk"), to: path)
                == ["push", "/d/My App.apk", "/data/local/tmp/pane-drop-1A2B.apk"])
        #expect(
            DropTransfer.installArguments(devicePath: path, allowDowngrade: false)
                == ["shell", "pm install -r -t '/data/local/tmp/pane-drop-1A2B.apk'"])
        #expect(
            DropTransfer.installArguments(devicePath: path, allowDowngrade: true)
                == ["shell", "pm install -r -t -d '/data/local/tmp/pane-drop-1A2B.apk'"])
        #expect(
            DropTransfer.removeArguments(devicePath: path) == ["shell", "rm -f '/data/local/tmp/pane-drop-1A2B.apk'"])
        #expect(
            DropTransfer.sizeArguments(devicePath: "/sdcard/Download/it's.jpg")
                == ["shell", "stat -c %s '/sdcard/Download/it'\\''s.jpg' 2>/dev/null"])
        #expect(
            DropTransfer.mediaScanArguments(devicePath: "/sdcard/Download/a b.jpg").last
                == "content call --uri content://media --method scan_file --arg '/sdcard/Download/a b.jpg'")
        #expect(DropPlan.devicePath(for: URL(filePath: "/d/a b.jpg")) == "/sdcard/Download/a b.jpg")
    }

    @Test func installResultsAndSizes() {
        #expect(DropTransfer.installSucceeded(status: 0, output: "Success\n"))
        #expect(!DropTransfer.installSucceeded(status: 0, output: "Failure [INSTALL_FAILED_X: y]\n"))
        #expect(!DropTransfer.installSucceeded(status: 1, output: "Success"))
        #expect(DropTransfer.parseSize("1234\n") == 1234)
        #expect(DropTransfer.parseSize("") == nil)
    }

    @Test func errorsAreAPlainSentenceWithAdbsLineBehindDetails() {
        let signed = DropFailure.install(
            "Splito",
            output:
                "Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package dev.niduslabs.splito signatures do not match newer version; ignoring!]\n"
        )
        #expect(signed.title == "Couldn't install Splito.")
        #expect(
            signed.body
                == "The copy on the device was signed with a different key. Uninstall it there, then drop the file again."
        )
        #expect(
            signed.code
                == "INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package dev.niduslabs.splito signatures do not match newer version; ignoring!"
        )
        #expect(signed.rowReason == "The copy on the device was signed with a different key.")
        #expect(
            DropFailure.install("a", output: "Failure [INSTALL_PARSE_FAILED_NOT_APK: Failed to parse]").body
                == "This file isn't an Android app, or it's damaged.")
        #expect(
            DropFailure.install("a", output: "Failure [INSTALL_FAILED_NO_MATCHING_ABIS: x]").rowReason
                == "Not built for this emulator's processor.")
        #expect(
            DropFailure.install("a", output: "Failure [INSTALL_FAILED_OLDER_SDK: x]").body
                == "It needs a newer Android than this emulator's.")
        #expect(
            DropFailure.install("a", output: "Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]").body
                == "The emulator is out of space.")
        // A code Pane has no words for: the title alone, adb's line behind Details, never the code up front.
        let unknown = DropFailure.install("a", output: "Failure [INSTALL_FAILED_SOMETHING_NEW: z]")
        #expect(unknown.body == nil)
        #expect(unknown.code == "INSTALL_FAILED_SOMETHING_NEW: z")
        #expect(unknown.rowReason == "Didn't work.")
        let parse = DropFailure.install(
            "broken.apk",
            output: """

                Exception occurred while executing 'install':
                java.lang.IllegalArgumentException: Error: Failed to parse APK file: /data/local/tmp/p.apk: Failed to parse /data/local/tmp/p.apk
                \tat com.android.server.pm.PackageManagerShellCommand.setParamsSize(PackageManagerShellCommand.java:707)
                \t... 12 more
                """)
        #expect(parse.body == "This file isn't an Android app, or it's damaged.")
        #expect(parse.code == "Failed to parse APK file: /data/local/tmp/p.apk: Failed to parse /data/local/tmp/p.apk")
        let copy = DropFailure.copy("a.jpg", output: "adb: error: failed to copy 'a.jpg': No space left on device\n")
        #expect(copy.title == "Couldn't copy a.jpg.")
        #expect(copy.body == "The emulator is out of space.")
        #expect(copy.code == "failed to copy 'a.jpg': No space left on device")
        #expect(DropFailure.copy("a.apk", output: "", isApp: true) == DropFailure(title: "Couldn't install a.apk."))
    }
}

@Suite struct DeviceIntentTests {
    private func item(_ state: DropJob.Item.State, badging: ApkBadging? = nil, path: String = "/d/a.apk")
        -> DropJob.Item
    {
        var job = DropJob(dragged: [DraggedItem(url: URL(filePath: path), badging: badging)])
        job.items[0].state = state
        return job.items[0]
    }

    @Test func installedAppsOpenAndCopiesShowDownloads() {
        let badging = ApkBadging(
            packageName: "a.b", versionCode: 1, versionName: "1", launchableActivity: "a.b.MainActivity")
        #expect(
            DeviceIntent.after(item(.installed, badging: badging))
                == .openApp(package: "a.b", activity: "a.b.MainActivity"))
        #expect(DeviceIntent.after(item(.copied, path: "/d/a.jpg")) == .showDownloads)
        #expect(DeviceIntent.after(item(.installed)) == nil)
        #expect(DeviceIntent.after(item(.failed(DropFailure(title: "x")), badging: badging)) == nil)
        #expect(DeviceIntent.after(item(.skipped, badging: badging)) == nil)
    }

    @Test func theCallsTheyMake() {
        #expect(
            DeviceIntent.openApp(package: "a.b", activity: "a.b.Main").arguments
                == ["shell", "am start -n 'a.b/a.b.Main'"])
        #expect(DeviceIntent.openApp(package: "a.b", activity: nil).arguments == nil)
        #expect(
            DeviceIntent.showDownloads.arguments == ["shell", "am start -a android.intent.action.VIEW_DOWNLOADS"])
        #expect(
            DeviceIntent.parseResolved("priority=0 preferredOrder=0\na.b/.MainActivity\n") == "a.b/.MainActivity")
        #expect(DeviceIntent.parseResolved("No activity found\n") == nil)
        #expect(DeviceIntent.started(status: 0, output: "Starting: Intent { cmp=a.b/.M }"))
        #expect(!DeviceIntent.started(status: 0, output: "Error: Activity class {a.b/x} does not exist."))
    }
}
