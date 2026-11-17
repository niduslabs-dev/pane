import Foundation
import Testing

@testable import PaneCore

@Suite struct AdbTests {
    private let adb = Adb(executable: URL(filePath: "/sdk/platform-tools/adb"), serial: "emulator-5554")

    @Test func serialComesFromTheConsolePort() {
        #expect(Adb.serial(consolePort: 5554) == "emulator-5554")
        #expect(Adb.serial(consolePort: nil) == nil)
        #expect(Adb.serial(consolePort: 0) == nil)
    }

    @Test func adbReasonsAreOneShortLine() {
        #expect(
            Adb.reason(
                from:
                    "Performing Streamed Install\nadb: failed to install a.apk: Failure [INSTALL_FAILED_OLDER_SDK: Requires newer sdk version #99]\n"
            ) == "INSTALL_FAILED_OLDER_SDK")
        #expect(
            Adb.reason(from: "adb: error: device 'emulator-5554' not found\n") == "device 'emulator-5554' not found")
        #expect(Adb.reason(from: "").isEmpty)
        #expect(Adb.reason(from: "adb: " + String(repeating: "x", count: 200)).count == Adb.maxReasonLength)
        #expect(!Adb.reason(from: "error: a \u{2014} b").contains("\u{2014}"))
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
