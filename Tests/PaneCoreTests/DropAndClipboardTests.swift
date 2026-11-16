import Foundation
import Testing

@testable import PaneCore

@Suite struct DropPlanTests {
    private func plan(_ paths: [String], folders: Set<String> = []) -> DropPlan {
        DropPlan(files: paths.map { URL(filePath: $0) }, isDirectory: { folders.contains($0.path) })
    }

    @Test func anApkIsInstalledAndTheRestCopied() {
        let plan = plan(["/d/notes.txt", "/d/Splito.APK", "/d/photo.JPG", "/d/clip.mov"])
        #expect(
            plan.steps == [
                .install(URL(filePath: "/d/Splito.APK")),
                .copy(URL(filePath: "/d/notes.txt"), isMedia: false),
                .copy(URL(filePath: "/d/photo.JPG"), isMedia: true),
                .copy(URL(filePath: "/d/clip.mov"), isMedia: true),
            ])
        #expect(plan.hoverLabel == "Install and copy to device")
        #expect(plan.doneText == "Installed and copied.")
    }

    @Test func severalApksInstallInDropOrder() {
        let plan = plan(["/d/b.apk", "/d/a.apk"])
        #expect(plan.steps == [.install(URL(filePath: "/d/b.apk")), .install(URL(filePath: "/d/a.apk"))])
        #expect(plan.hoverLabel == "Install app")
        #expect(plan.doneText == "Installed 2 apps.")
    }

    @Test func labelsAndStatusLines() {
        #expect(plan(["/d/Splito.apk"]).hoverLabel == "Install app")
        #expect(plan(["/d/Splito.apk"]).doneText == "Installed.")
        #expect(plan(["/d/a.txt"]).hoverLabel == "Copy to device")
        #expect(plan(["/d/a.txt"]).doneText == "Copied to Downloads.")
        #expect(plan(["/d/a.txt", "/d/b.txt"]).doneText == "Copied 2 files to Downloads.")
        #expect(DropPlan.progressText(for: .install(URL(filePath: "/d/Splito.apk"))) == "Installing Splito…")
        #expect(
            DropPlan.progressText(for: .copy(URL(filePath: "/d/my photo.jpg"), isMedia: true))
                == "Copying my photo.jpg…")
    }

    @Test func foldersAndNonFilesAreLeftOut() {
        #expect(plan(["/d/folder", "/d/a.txt"], folders: ["/d/folder"]).steps.count == 1)
        #expect(plan(["/d/folder"], folders: ["/d/folder"]).isEmpty)
        #expect(DropPlan(files: [URL(string: "https://example.com/a.apk")!], isDirectory: { _ in false }).isEmpty)
    }
}

@Suite struct AdbTests {
    private let adb = Adb(executable: URL(filePath: "/sdk/platform-tools/adb"), serial: "emulator-5554")

    @Test func serialComesFromTheConsolePort() {
        #expect(Adb.serial(consolePort: 5554) == "emulator-5554")
        #expect(Adb.serial(consolePort: nil) == nil)
        #expect(Adb.serial(consolePort: 0) == nil)
    }

    @Test func argumentsArePassedWhole() {
        #expect(
            adb.arguments(for: .install(URL(filePath: "/d/My App.apk")))
                == ["-s", "emulator-5554", "install", "-r", "/d/My App.apk"])
        #expect(
            adb.arguments(for: .copy(URL(filePath: "/d/my photo.jpg"), isMedia: true))
                == ["-s", "emulator-5554", "push", "/d/my photo.jpg", "/sdcard/Download/my photo.jpg"])
    }

    @Test func theMediaScanQuotesThePathForTheDeviceShell() {
        #expect(
            Adb.deviceShellQuoted("/sdcard/Download/it's; rm -rf x.jpg") == "'/sdcard/Download/it'\\''s; rm -rf x.jpg'")
        #expect(
            adb.mediaScanArguments(devicePath: "/sdcard/Download/a b.jpg").last
                == "content call --uri content://media --method scan_file --arg '/sdcard/Download/a b.jpg'")
    }

    @Test func errorsAreOneShortLine() {
        let install = DropPlan.Step.install(URL(filePath: "/d/a.apk"))
        let copy = DropPlan.Step.copy(URL(filePath: "/d/a.txt"), isMedia: false)
        #expect(
            Adb.shortError(
                from:
                    "Performing Streamed Install\nadb: failed to install a.apk: Failure [INSTALL_FAILED_OLDER_SDK: Requires newer sdk version #99]\n",
                step: install) == "Install failed: INSTALL_FAILED_OLDER_SDK")
        #expect(
            Adb.shortError(from: "adb: error: device 'emulator-5554' not found\n", step: copy)
                == "Copy failed: device 'emulator-5554' not found")
        #expect(Adb.shortError(from: "", step: copy) == "Copy failed.")
        let long = Adb.shortError(from: "adb: " + String(repeating: "x", count: 200), step: copy)
        #expect(long.count == "Copy failed: ".count + Adb.maxReasonLength)
        #expect(!Adb.shortError(from: "error: a \u{2014} b", step: copy).contains("\u{2014}"))
    }

    @Test func adbComesFromTheRealSdk() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        let env = ["ANDROID_HOME": "/Users/someone/Library/Android/pane-sdk"]
        #expect(
            AndroidSDK.adbExecutable(environment: env, home: home, isExecutable: { _ in true })?.path
                == "/Users/someone/Library/Android/sdk/platform-tools/adb")
    }
}

@Suite struct ClipboardSyncTests {
    @Test func macTextGoesToTheDeviceOnlyWhileKey() {
        var sync = ClipboardSync()
        #expect(sync.macChanged(to: "secret", isKey: false, isEnabled: true) == nil)
        #expect(sync.macChanged(to: "hello", isKey: true, isEnabled: true) == .setDevice("hello"))
        #expect(sync.macChanged(to: "hello", isKey: true, isEnabled: true) == nil)
        #expect(sync.macChanged(to: nil, isKey: true, isEnabled: true) == nil)
        #expect(sync.macChanged(to: "", isKey: true, isEnabled: true) == nil)
    }

    @Test func offMeansNothingMoves() {
        var sync = ClipboardSync()
        #expect(sync.macChanged(to: "a", isKey: true, isEnabled: false) == nil)
        #expect(sync.pasteRequested(macText: "a", isEnabled: false) == nil)
        #expect(sync.deviceChanged(to: "b", isKey: true, isEnabled: false) == nil)
    }

    @Test func whatTheDeviceHeldAtConnectIsNotAChange() {
        var sync = ClipboardSync()
        sync.deviceBaseline("old device text")
        #expect(sync.deviceChanged(to: "old device text", isKey: true, isEnabled: true) == nil)
        #expect(sync.deviceChanged(to: "copied on device", isKey: true, isEnabled: true) == .setMac("copied on device"))
        #expect(sync.deviceChanged(to: "copied on device", isKey: true, isEnabled: true) == nil)
    }

    /// The stream sends nothing first when the device's clipboard is empty, so the first
    /// message is then a real copy.
    @Test func theFirstCopyOnAnEmptyDeviceClipboardCounts() {
        var sync = ClipboardSync()
        sync.deviceBaseline("")
        #expect(sync.deviceChanged(to: "first copy", isKey: true, isEnabled: true) == .setMac("first copy"))
    }

    @Test func deviceTextReachesTheMacOnlyWhileKey() {
        var sync = ClipboardSync()
        sync.deviceBaseline("")
        #expect(sync.deviceChanged(to: "while away", isKey: false, isEnabled: true) == nil)
        // Not replayed later: only a new change counts.
        #expect(sync.deviceChanged(to: "while away", isKey: true, isEnabled: true) == nil)
        #expect(sync.deviceChanged(to: "now", isKey: true, isEnabled: true) == .setMac("now"))
    }

    @Test func aCopyIsNotBouncedBack() {
        var sync = ClipboardSync()
        sync.deviceBaseline("")
        #expect(sync.macChanged(to: "from mac", isKey: true, isEnabled: true) == .setDevice("from mac"))
        #expect(sync.deviceChanged(to: "from mac", isKey: true, isEnabled: true) == nil)
        #expect(sync.deviceChanged(to: "from device", isKey: true, isEnabled: true) == .setMac("from device"))
        #expect(sync.macChanged(to: "from device", isKey: true, isEnabled: true) == nil)
    }

    @Test func pasteSendsTheMacTextUnlessTheDeviceHasIt() {
        var sync = ClipboardSync()
        #expect(
            sync.pasteRequested(macText: "copied before Pane was key", isEnabled: true)
                == .setDevice("copied before Pane was key"))
        #expect(sync.pasteRequested(macText: "copied before Pane was key", isEnabled: true) == nil)
        #expect(sync.pasteRequested(macText: nil, isEnabled: true) == nil)
    }

    @Test func aNewConnectionStartsOver() {
        var sync = ClipboardSync()
        sync.deviceBaseline("a")
        sync.reset()
        sync.deviceBaseline("b")
        #expect(sync.deviceChanged(to: "b", isKey: true, isEnabled: true) == nil)
    }
}
