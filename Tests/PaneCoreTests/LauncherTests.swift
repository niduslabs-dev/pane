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
        sleeper.waitUntilExit()
        #expect(stopped)
    }
}
