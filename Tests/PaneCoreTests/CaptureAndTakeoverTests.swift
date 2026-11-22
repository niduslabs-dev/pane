import Darwin
import Foundation
import PaneTakeover
import Testing

@testable import PaneCore

@Suite struct CaptureLocationTests {
    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    private func folder(_ configured: String?, writable: Set<String> = []) -> String {
        CaptureLocation.folder(configured: configured, home: home, isWritableFolder: { writable.contains($0.path) })
            .path(percentEncoded: false)
    }

    @Test func usesTheScreenshotFolderWithTildeExpanded() {
        #expect(
            folder("~/Pictures/Shots", writable: ["/Users/someone/Pictures/Shots"]) == "/Users/someone/Pictures/Shots/")
        #expect(folder("/Volumes/Work/Shots", writable: ["/Volumes/Work/Shots"]) == "/Volumes/Work/Shots/")
        #expect(folder("~", writable: ["/Users/someone"]) == "/Users/someone/")
    }

    @Test func fallsBackToTheDesktop() {
        #expect(folder(nil) == "/Users/someone/Desktop/")
        #expect(folder("  ") == "/Users/someone/Desktop/")
        #expect(folder("~/Gone") == "/Users/someone/Desktop/")
        #expect(folder("relative/path", writable: ["relative/path"]) == "/Users/someone/Desktop/")
    }

    @Test func saveToChoosesBetweenMacOSTheDesktopAndAFolder() {
        func folder(_ destination: CaptureDestination, writable: Set<String>) -> String {
            CaptureLocation.folder(
                for: destination, configured: "~/Pictures/Shots", home: home,
                isWritableFolder: { writable.contains($0.path) }
            ).path(percentEncoded: false)
        }
        let all: Set<String> = ["/Users/someone/Pictures/Shots", "/Users/someone/Pane"]
        #expect(folder(.system, writable: all) == "/Users/someone/Pictures/Shots/")
        #expect(folder(.desktop, writable: all) == "/Users/someone/Desktop/")
        #expect(folder(.folder("/Users/someone/Pane"), writable: all) == "/Users/someone/Pane/")
        // A chosen folder that has gone falls back to the Desktop.
        #expect(folder(.folder("/Users/someone/Pane"), writable: []) == "/Users/someone/Desktop/")
    }

    @Test func saveToIsStoredAsAKindAndAPath() {
        #expect(CaptureDestination(kind: nil, path: nil) == .system)
        #expect(CaptureDestination(kind: "desktop", path: "/a") == .desktop)
        #expect(CaptureDestination(kind: "folder", path: "/a") == .folder("/a"))
        #expect(CaptureDestination(kind: "folder", path: nil) == .system)
        #expect(CaptureDestination.folder("/a").kind == "folder")
    }

    @Test func checksARealFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pane-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(CaptureLocation.isWritableFolder(dir))
        let file = dir.appending(path: "file")
        try Data().write(to: file)
        #expect(!CaptureLocation.isWritableFolder(file))
    }
}

@Suite struct AttachRequestTests {
    @Test func readsTheURL() {
        #expect(AttachRequest.avdName(from: URL(string: "pane://attach?avd=dev_android36")!) == "dev_android36")
        #expect(
            AttachRequest.avdName(from: URL(string: "pane://attach?avd=Pixel_9.Pro-API_36")!) == "Pixel_9.Pro-API_36")
        #expect(AttachRequest.avdName(from: URL(string: "pane://other?avd=x")!) == nil)
        #expect(AttachRequest.avdName(from: URL(string: "https://attach?avd=x")!) == nil)
        #expect(AttachRequest.avdName(from: URL(string: "pane://attach")!) == nil)
        #expect(AttachRequest.avdName(from: URL(string: "pane://attach?avd=a%20b")!) == nil)
        #expect(AttachRequest.avdName(from: URL(string: "pane://attach?avd=../x%2Fy")!) == nil)
    }

    @Test func readsTheLaunchArgument() {
        #expect(AttachRequest.avdName(fromArguments: ["/x/Pane", "--attach", "dev_android36"]) == "dev_android36")
        #expect(AttachRequest.avdName(fromArguments: ["/x/Pane", "--attach"]) == nil)
        #expect(AttachRequest.avdName(fromArguments: ["/x/Pane", "-PaneNoAutoAttach", "YES"]) == nil)
    }
}

@Suite struct EmulatorTakeoverTests {
    @Test func shadowSdkPathHasNoSpaces() {
        let shadow = EmulatorTakeover.shadowSDK(
            environment: [:], home: URL(filePath: "/Users/someone", directoryHint: .isDirectory))
        #expect(shadow.path(percentEncoded: false) == "/Users/someone/Library/Android/pane-sdk/")
    }

    @Test func legacyStateNeedsTheShadowAndEveryBlockForOn() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "pane-takeover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let shadow = EmulatorTakeover.shadowSDK(environment: [:], home: home)
        try FileManager.default.createDirectory(at: shadow, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appending(path: ".config/fish"), withIntermediateDirectories: true)
        #expect(EmulatorTakeover.legacyState(environment: [:], home: home) == .none)
        let configs = EmulatorTakeover.shellConfigs(environment: [:], home: home)
        try "x\n\(EmulatorTakeover.beginMark)\n".write(to: configs[0], atomically: true, encoding: .utf8)
        #expect(EmulatorTakeover.legacyState(environment: [:], home: home) == .partial)
        try "real_sdk=/x\n".write(to: shadow.appending(path: ".pane-takeover"), atomically: true, encoding: .utf8)
        for config in configs.dropFirst() {
            try "\(EmulatorTakeover.beginMark)\n".write(to: config, atomically: true, encoding: .utf8)
        }
        #expect(EmulatorTakeover.legacyState(environment: [:], home: home) == .on)
    }

    @Test func shellValuesAreReadBetweenMarkers() {
        let output = "Welcome to fish\n<<pane:/Users/x/sdk:pane>><<pane::pane>>"
        #expect(EmulatorTakeover.shellValues(in: output) == ["/Users/x/sdk", ""])
    }

    @Test func agentPlistWatchesTheSdksEmulatorFolderAndNamesPane() throws {
        let data = try RepairAgent.plist(
            bundleID: "dev.niduslabs.pane", helperExecutable: URL(filePath: "/Applications/Pane.app/h"),
            sdk: URL(filePath: "/Users/x/sdk/", directoryHint: .isDirectory), log: URL(filePath: "/tmp/l.log"))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == "dev.niduslabs.pane.takeover-repair")
        #expect(plist["WatchPaths"] as? [String] == ["/Users/x/sdk/emulator"])
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == ["dev.niduslabs.pane"])
        let arguments = try #require(plist["ProgramArguments"] as? [String])
        #expect(
            arguments == ["/Applications/Pane.app/h", "--repair", "/Users/x/sdk", "--bundle-id", "dev.niduslabs.pane"])
        let parsed = try #require(RepairAgent.parse(Array(arguments.dropFirst())))
        #expect(parsed.bundleID == "dev.niduslabs.pane")
        #expect(RepairAgent.parse(["--repair", "relative", "--bundle-id", "x"]) == nil)
        #expect(RepairAgent.parse(["--repair", "/a", "--bundle-id", "x'; rm"]) == nil)
    }

    @Test func panesOwnLaunchesSkipTheWrapper() {
        let launcher = URL(filePath: "/sdk/emulator/emulator")
        #expect(
            AndroidSDK.launchable(emulator: launcher, isExecutable: { _ in true }).lastPathComponent == "emulator-real")
        #expect(AndroidSDK.launchable(emulator: launcher, isExecutable: { _ in false }) == launcher)
    }
}

/// The wrapper and its repair, on scratch SDKs only (never `~/Library/Android/sdk`).
@Suite struct TakeoverRepairTests {
    private let script = TakeoverWrapper.script(bundleID: "dev.niduslabs.pane.test")
    private let binary = Data([0xCF, 0xFA, 0xED, 0xFE, 1, 2, 3])

    /// A scratch SDK with an installed emulator: a fake binary launcher and `package.xml`.
    private func makeSDK() throws -> URL {
        let sdk = FileManager.default.temporaryDirectory.appending(
            path: "pane-repair-\(UUID().uuidString)", directoryHint: .isDirectory)
        let folder = sdk.appending(path: "emulator")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try binary.write(to: folder.appending(path: "emulator"))
        try Data("<x/>".utf8).write(to: folder.appending(path: "package.xml"))
        return sdk
    }

    private func options(_ sdk: URL, quiet: Duration = .zero, timeout: Duration = .milliseconds(300))
        -> TakeoverRepair.Options
    {
        TakeoverRepair.Options(
            quiet: quiet, timeout: timeout, pollInterval: .milliseconds(20),
            lockFile: sdk.deletingLastPathComponent().appending(path: "\(sdk.lastPathComponent).lock"),
            waitsForLock: true)
    }

    private func read(_ sdk: URL, _ name: String) -> Data? {
        try? Data(contentsOf: sdk.appending(path: "emulator/\(name)"))
    }

    @Test func wrapsOnceAndUnwrapsBackToTheRealLauncher() throws {
        let sdk = try makeSDK()
        defer { try? FileManager.default.removeItem(at: sdk) }
        #expect(TakeoverRepair.launcherState(sdk: sdk, script: script) == .real)
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: options(sdk)) == .wrapped)
        #expect(read(sdk, "emulator") == Data(script.utf8))
        #expect(read(sdk, "emulator-real") == binary)
        #expect(FileManager.default.isExecutableFile(atPath: sdk.appending(path: "emulator/emulator").path))
        #expect(TakeoverRepair.launcherState(sdk: sdk, script: script) == .wrapped(current: true))
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: options(sdk)) == .alreadyWrapped)
        let other = TakeoverWrapper.script(bundleID: "dev.niduslabs.pane.other")
        #expect(TakeoverRepair.wrap(sdk: sdk, script: other, options: options(sdk)) == .updated)
        #expect(read(sdk, "emulator-real") == binary)
        #expect(TakeoverRepair.unwrap(sdk: sdk) == .restored)
        #expect(read(sdk, "emulator") == binary)
        #expect(read(sdk, "emulator-real") == nil)
        #expect(TakeoverRepair.unwrap(sdk: sdk) == .nothingToDo)
    }

    @Test func leavesSomeoneElsesScriptAlone() throws {
        let sdk = try makeSDK()
        defer { try? FileManager.default.removeItem(at: sdk) }
        try Data("#!/bin/sh\nexec other\n".utf8).write(to: sdk.appending(path: "emulator/emulator"))
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: options(sdk)) == .foreignLauncher)
        #expect(TakeoverRepair.unwrap(sdk: sdk) == .nothingToDo)
    }

    @Test func waitsOutAnInstallInFlight() throws {
        let sdk = try makeSDK()
        defer { try? FileManager.default.removeItem(at: sdk) }
        let installer = sdk.appending(path: "emulator/.installer")
        try FileManager.default.createDirectory(at: installer, withIntermediateDirectories: true)
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: options(sdk)) == .installInProgress)
        try FileManager.default.removeItem(at: installer)
        try FileManager.default.createDirectory(
            at: sdk.appending(path: "emulator.backup"), withIntermediateDirectories: true)
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: options(sdk)) == .installInProgress)
        try FileManager.default.removeItem(at: sdk.appending(path: "emulator.backup"))
        try FileManager.default.removeItem(at: sdk.appending(path: "emulator/package.xml"))
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: options(sdk)) == .installInProgress)
        try Data("<x/>".utf8).write(to: sdk.appending(path: "emulator/package.xml"))
        #expect(
            TakeoverRepair.wrap(
                sdk: sdk, script: script, options: options(sdk, quiet: .milliseconds(50), timeout: .seconds(2)))
                == .wrapped)
    }

    @Test func noFolderMeansNothingToRepair() throws {
        let sdk = try makeSDK()
        defer { try? FileManager.default.removeItem(at: sdk) }
        try FileManager.default.removeItem(at: sdk.appending(path: "emulator"))
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: options(sdk)) == .noFolder)
        #expect(TakeoverRepair.unwrap(sdk: sdk) == .noFolder)
    }

    @Test func anotherRepairHoldingTheLockIsLeftToFinish() throws {
        let sdk = try makeSDK()
        defer { try? FileManager.default.removeItem(at: sdk) }
        var agent = options(sdk)
        agent.waitsForLock = false
        let held = open(agent.lockFile.path, O_RDWR | O_CREAT, 0o600)
        defer {
            close(held)
            unlink(agent.lockFile.path)
        }
        #expect(flock(held, LOCK_EX | LOCK_NB) == 0)
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: agent) == .busy)
        #expect(TakeoverRepair.launcherState(sdk: sdk, script: script) == .real)
    }

    /// An update swaps the folder between the link and the rename: the whole repair stays in
    /// the old folder, and the new one keeps its real launcher untouched.
    @Test func aSwapMidRepairNeverHalfWrapsTheNewFolder() throws {
        let sdk = try makeSDK()
        defer { try? FileManager.default.removeItem(at: sdk) }
        let newBinary = Data([0xCF, 0xFA, 0xED, 0xFE, 9, 9])
        var swapping = options(sdk)
        swapping.afterLink = {
            let files = FileManager.default
            try? files.moveItem(at: sdk.appending(path: "emulator"), to: sdk.appending(path: "emulator.old"))
            try? files.createDirectory(at: sdk.appending(path: "emulator"), withIntermediateDirectories: true)
            try? newBinary.write(to: sdk.appending(path: "emulator/emulator"))
        }
        #expect(TakeoverRepair.wrap(sdk: sdk, script: script, options: swapping) == .wrapped)
        #expect(read(sdk, "emulator") == newBinary)
        #expect(read(sdk, "emulator-real") == nil)
        let old = try Data(contentsOf: sdk.appending(path: "emulator.old/emulator"))
        #expect(old == Data(script.utf8))
    }
}

/// The wrapper's argument handling, run under `/bin/sh` with a stub `emulator-real` that prints
/// its arguments and a stub `open` on PATH that records the call.
@Suite struct TakeoverWrapperTests {
    private func run(_ arguments: [String], openFails: Bool = false, environment extra: [String: String] = [:]) throws
        -> (argv: String, opened: String)
    {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "pane-wrapper-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "sdk/emulator")
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let opened = root.appending(path: "opened")
        let files: [(URL, String)] = [
            (folder.appending(path: "emulator"), TakeoverWrapper.script(bundleID: "dev.niduslabs.pane.test")),
            (folder.appending(path: "emulator-real"), "#!/bin/sh\nprintf '%s|' \"$@\"\n"),
            (
                bin.appending(path: "open"),
                "#!/bin/sh\nprintf '%s ' \"$@\" > '\(opened.path)'\nexit \(openFails ? 1 : 0)\n"
            ),
        ]
        for (url, text) in files {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let process = Process()
        process.executableURL = folder.appending(path: "emulator")
        process.arguments = arguments
        process.environment = ["PATH": "\(bin.path):/usr/bin:/bin"].merging(extra) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let argv = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (argv, (try? String(contentsOf: opened, encoding: .utf8)) ?? "")
    }

    @Test func anAvdLaunchOpensPaneAndRunsHeadless() throws {
        let result = try run(["@Pixel_9"])
        #expect(result.argv == "@Pixel_9|-no-window|")
        #expect(result.opened == "-g -b dev.niduslabs.pane.test pane://attach?avd=Pixel_9 --args --attach Pixel_9 ")
        #expect(try run(["-avd", "X", "-qemu", "-m", "2048"]).argv == "-avd|X|-no-window|-qemu|-m|2048|")
    }

    @Test func headlessStudioInfoAndOptOutPassThroughWithoutOpeningPane() throws {
        for arguments in [
            ["-avd", "X", "-no-window"], ["-avd", "X", "-qt-hide-window", "-grpc-use-token"], ["-list-avds"],
            ["-version"],
        ] {
            let result = try run(arguments)
            #expect(result.argv == arguments.map { $0 + "|" }.joined())
            #expect(result.opened.isEmpty)
        }
        let optOut = try run(["@X"], environment: ["PANE_TAKEOVER": "0"])
        #expect(optOut.argv == "@X|")
        #expect(optOut.opened.isEmpty)
    }

    @Test func withoutPaneTheEmulatorKeepsItsWindow() throws {
        #expect(try run(["@X"], openFails: true).argv == "@X|")
    }
}

@Suite struct CaptureOutcomeTests {
    private func outcome(
        _ action: CaptureAction = .screenshotButton, _ destination: CaptureDestination = .system,
        target: String? = nil, screenshot: String? = nil, recording: String? = nil
    ) -> CaptureOutcome {
        CaptureOutcome.resolve(
            action, destination: destination,
            targets: SystemCaptureTargets(target: target, screenshot: screenshot, screenRecording: recording))
    }

    @Test func theScreenshotButtonFollowsEveryTargetValue() {
        #expect(outcome(screenshot: "file") == .file)
        #expect(outcome(screenshot: "clipboard") == .clipboard)
        #expect(outcome(screenshot: "preview") == .preview)
        // Not supported yet: a file, not a half-made message.
        #expect(outcome(screenshot: "mail") == .file)
        #expect(outcome(screenshot: "messages") == .file)
        #expect(outcome(screenshot: " Clipboard ") == .clipboard)
    }

    @Test func screenshotsFallBackToTargetThenFile() {
        #expect(outcome(target: "clipboard") == .clipboard)
        #expect(outcome(target: "clipboard", screenshot: "file") == .file)
        #expect(outcome(target: "preview", screenshot: "nonsense") == .preview)
        #expect(outcome(target: "nonsense") == .file)
        #expect(outcome() == .file)
        // The recording key never steers screenshots.
        #expect(outcome(recording: "clipboard") == .file)
    }

    @Test func anExplicitSaveToAlwaysWritesAFile() {
        for destination in [CaptureDestination.desktop, .folder("/Users/someone/Pane")] {
            #expect(outcome(.screenshotButton, destination, target: "clipboard", screenshot: "clipboard") == .file)
            #expect(outcome(.screenshotButton, destination, screenshot: "preview") == .file)
        }
    }

    @Test func saveAlwaysWritesAndCopyAlwaysCopies() {
        for destination in [CaptureDestination.system, .desktop, .folder("/x")] {
            #expect(outcome(.saveScreenshot, destination, target: "clipboard", screenshot: "clipboard") == .file)
            #expect(outcome(.copyScreenshot, destination, target: "file", screenshot: "file") == .clipboard)
        }
    }

    @Test func recordingsAlwaysWriteAFile() {
        #expect(outcome(.recording, recording: "file") == .file)
        #expect(outcome(.recording, recording: "clipboard") == .file)
        #expect(outcome(.recording, target: "clipboard") == .file)
        #expect(outcome(.recording, target: "preview", recording: "preview") == .file)
        #expect(outcome(.recording, .desktop, recording: "clipboard") == .file)
    }
}
