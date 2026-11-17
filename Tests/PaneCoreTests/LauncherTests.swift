import Foundation
import Testing

@testable import PaneCore

@Suite struct AvdCatalogTests {
    /// A scratch `~/.android/avd`: one good AVD, one whose folder is missing, one stray file.
    private func makeAvdHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "pane-avd-\(UUID().uuidString)")
        let avdHome = root.appending(path: "avd")
        let good = avdHome.appending(path: "dev_android36.avd")
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try "hw.device.name=pixel_8\nimage.sysdir.1=system-images/android-36.1/google_apis/arm64-v8a/\n"
            .write(to: good.appending(path: "config.ini"), atomically: true, encoding: .utf8)
        try "path=\(good.path)\n".write(
            to: avdHome.appending(path: "dev_android36.ini"), atomically: true, encoding: .utf8)
        try "path=\(avdHome.path)/gone.avd\n".write(
            to: avdHome.appending(path: "gone.ini"), atomically: true, encoding: .utf8)
        try "x".write(to: avdHome.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        return avdHome
    }

    @Test func listsAvdsWhoseFolderExists() throws {
        let home = try makeAvdHome()
        defer { try? FileManager.default.removeItem(at: home.deletingLastPathComponent()) }
        let avds = AvdCatalog.list(in: home)
        #expect(avds.map(\.name) == ["dev_android36"])
        #expect(avds.first?.summary == "dev_android36 · Pixel 8 · Android 16")
    }

    @Test func avdHomeHonoursTheEnvironment() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        #expect(AvdCatalog.directory(environment: [:], home: home).path == "/Users/someone/.android/avd")
        #expect(AvdCatalog.directory(environment: ["ANDROID_AVD_HOME": "/x/avd"], home: home).path == "/x/avd")
    }
}

@Suite struct AndroidSDKTests {
    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    @Test func prefersAndroidHomeThenSdkRootThenTheDefault() {
        let all: Set<String> = [
            "/a/emulator/emulator", "/b/emulator/emulator", "/Users/someone/Library/Android/sdk/emulator/emulator",
        ]
        let exists: (URL) -> Bool = { all.contains($0.path) }
        let env = ["ANDROID_HOME": "/a", "ANDROID_SDK_ROOT": "/b"]
        #expect(
            AndroidSDK.emulatorExecutable(environment: env, home: home, isExecutable: exists)?.path
                == "/a/emulator/emulator")
        #expect(
            AndroidSDK.emulatorExecutable(environment: ["ANDROID_SDK_ROOT": "/b"], home: home, isExecutable: exists)?
                .path == "/b/emulator/emulator")
        #expect(
            AndroidSDK.emulatorExecutable(environment: [:], home: home, isExecutable: exists)?.path
                == "/Users/someone/Library/Android/sdk/emulator/emulator")
    }

    @Test func skipsRootsWithoutAnEmulator() {
        let exists: (URL) -> Bool = { $0.path == "/b/emulator/emulator" }
        let env = ["ANDROID_HOME": "/a", "ANDROID_SDK_ROOT": "/b"]
        #expect(
            AndroidSDK.emulatorExecutable(environment: env, home: home, isExecutable: exists)?.path
                == "/b/emulator/emulator")
        #expect(AndroidSDK.emulatorExecutable(environment: [:], home: home, isExecutable: { _ in false }) == nil)
    }

    /// Pane starts emulators from the real SDK even when the shell points at its shadow SDK.
    @Test func skipsPanesShadowSdk() {
        let exists: (URL) -> Bool = { _ in true }
        let env = ["ANDROID_HOME": "/Users/someone/Library/Android/pane-sdk/"]
        #expect(
            AndroidSDK.emulatorExecutable(environment: env, home: home, isExecutable: exists)?.path
                == "/Users/someone/Library/Android/sdk/emulator/emulator")
    }
}

@Suite struct EmulatorLauncherTests {
    @Test func startsHeadlessWithoutSavingASnapshot() {
        #expect(
            EmulatorLauncher.arguments(avdName: "dev_android36") == [
                "-avd", "dev_android36", "-no-window", "-no-audio", "-no-boot-anim", "-no-snapshot-save",
            ])
    }

    @Test func soundCanBeLeftOn() {
        #expect(
            EmulatorLauncher.arguments(avdName: "dev_android36", withoutSound: false) == [
                "-avd", "dev_android36", "-no-window", "-no-boot-anim", "-no-snapshot-save",
            ])
    }

    @Test func readsOurOwnParent() {
        #expect(EmulatorLauncher.parentPID(of: getpid()) == getppid())
    }

    @Test func stoppingAGoneProcessSucceedsAtOnce() async {
        let stopped = await EmulatorLauncher.stop(
            pid: Int32.max, gracePeriod: .seconds(1), killWait: .seconds(1), pollInterval: .milliseconds(10))
        #expect(stopped)
    }

    @Test func stopsAChildItStarted() async throws {
        let sleeper = Process()
        sleeper.executableURL = URL(filePath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        let stopped = await EmulatorLauncher.stop(
            pid: sleeper.processIdentifier, gracePeriod: .seconds(2), killWait: .seconds(1),
            pollInterval: .milliseconds(20))
        await waitForExit(sleeper)
        #expect(stopped)
    }

    @Test func outputLogIsNamedForTheAvd() {
        let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)
        #expect(
            EmulatorLauncher.outputLog(avdName: "dev_android36", home: home).path
                == "/Users/someone/Library/Logs/Pane/emulator-dev_android36.log")
        #expect(
            EmulatorLauncher.outputLog(avdName: "../my avd", home: home).lastPathComponent == "emulator-.._my_avd.log")
        #expect(
            EmulatorLauncher.previousOutputLog(for: URL(filePath: "/logs/emulator-a.log")).path
                == "/logs/emulator-a.previous.log")
    }

    /// The launcher's output lands in the log, and the launch before it is kept beside it.
    @Test func keepsThisLaunchsOutputAndTheLastOnes() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pane-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = folder.appending(path: "Logs/emulator-test.log")
        let echo = URL(filePath: "/bin/echo")
        for name in ["first", "second"] {
            let launched = try await EmulatorLauncher.launch(
                executable: echo, avdName: name, outputLog: log, helper: nil)
            if let process = launched.process { await waitForExit(process) }
        }
        let current = try String(contentsOf: log, encoding: .utf8)
        let previous = try String(contentsOf: EmulatorLauncher.previousOutputLog(for: log), encoding: .utf8)
        #expect(current.hasPrefix("-avd second "))
        #expect(previous.hasPrefix("-avd first "))
        let mode = try FileManager.default.attributesOfItem(atPath: log.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    /// Without the helper (`swift run`), the emulator is Pane's child and the PID is the child's.
    @Test func fallsBackToAChildWithoutTheHelper() async throws {
        let launched = try await EmulatorLauncher.launch(
            executable: URL(filePath: "/bin/sleep"), avdName: "a", outputLog: nil, helper: nil)
        #expect(launched.process?.processIdentifier == launched.pid)
        #expect(launched.isAlive)
        #expect(launched.exitStatus == nil)
        // `sleep` rejects the emulator's arguments and exits with an error.
        if let process = launched.process { await waitForExit(process) }
        #expect(!launched.isAlive)
        #expect(launched.exitStatus == 1)
    }

    @Test func opensTheHelperInTheBackgroundAsANewInstance() {
        let arguments = EmulatorLauncher.helperOpenArguments(
            helper: URL(filePath: "/Applications/Pane.app/Contents/Helpers/Pane Emulator.app"),
            pidFile: URL(filePath: "/tmp/x.pid"), outputLog: URL(filePath: "/logs/emulator-a.log"),
            executable: URL(filePath: "/sdk/emulator/emulator"), arguments: ["-avd", "a", "-no-window"],
            environment: ["ANDROID_AVD_HOME": "/avds", "ANDROID_HOME": "", "PATH": "/bin", "HOME": "/Users/x"])
        #expect(
            arguments == [
                "-g", "-n", "--env", "ANDROID_AVD_HOME=/avds",
                "/Applications/Pane.app/Contents/Helpers/Pane Emulator.app", "--args",
                "/tmp/x.pid", "/logs/emulator-a.log", "/sdk/emulator/emulator", "-avd", "a", "-no-window",
            ])
    }

    /// No log (it couldn't be made) is an empty argument, which the helper reads as /dev/null.
    @Test func passesAnEmptyLogWhenThereIsNone() {
        let arguments = EmulatorLauncher.helperOpenArguments(
            helper: URL(filePath: "/h.app"), pidFile: URL(filePath: "/p"), outputLog: nil,
            executable: URL(filePath: "/e"), arguments: ["-avd", "a"], environment: [:])
        #expect(arguments == ["-g", "-n", "/h.app", "--args", "/p", "", "/e", "-avd", "a"])
    }

    @Test func findsTheHelperOnlyWhenTheBundleHasIt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pane-bundle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appending(path: "Pane.app")
        try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
        let bundle = try #require(Bundle(url: app))
        #expect(EmulatorLauncher.helperURL(in: bundle) == nil)
        try FileManager.default.createDirectory(
            at: app.appending(path: EmulatorLauncher.helperPath), withIntermediateDirectories: true)
        #expect(EmulatorLauncher.helperURL(in: bundle)?.lastPathComponent == "Pane Emulator.app")
    }

    /// The PID handoff: the helper's file can turn up a moment after `open` returns.
    @Test func readsThePIDTheHelperWritesLater() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "pane-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let writer = Task {
            try await Task.sleep(for: .milliseconds(150))
            try "4242\n".write(to: file, atomically: true, encoding: .utf8)
        }
        let pid = await EmulatorLauncher.readPID(from: file, within: .seconds(5), pollInterval: .milliseconds(10))
        try await writer.value
        #expect(pid == 4242)
    }

    @Test func givesUpWhenNoPIDComes() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "pane-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let brief: Duration = .milliseconds(100)
        let poll: Duration = .milliseconds(10)
        #expect(await EmulatorLauncher.readPID(from: file, within: brief, pollInterval: poll) == nil)
        try "not a pid".write(to: file, atomically: true, encoding: .utf8)
        #expect(await EmulatorLauncher.readPID(from: file, within: brief, pollInterval: poll) == nil)
    }
}

/// Waits for `process` to end without blocking a Swift concurrency thread, as
/// `waitUntilExit()` would: on a machine with few cores, blocked threads starve the other
/// tests running in parallel.
private func waitForExit(_ process: Process) async {
    while process.isRunning { try? await Task.sleep(for: exitPollInterval) }
}

private let exitPollInterval: Duration = .milliseconds(10)
