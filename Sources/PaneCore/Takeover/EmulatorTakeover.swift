import Darwin
import Foundation
import PaneTakeover
import ServiceManagement

/// "Show all emulators in Pane": every emulator launched from the SDK Pane wraps runs headless
/// and shows in Pane. Turning it on puts `TakeoverWrapper` in front of `<sdk>/emulator/emulator`
/// (`TakeoverRepair`) and loads `RepairAgent`, which puts the wrapper back after emulator
/// updates. Off restores the real launcher and removes the agent.
///
/// Whether it is on is the user's choice, stored by the app with the SDK it applies to; this
/// type does the work and reads the state on disk.
public enum EmulatorTakeover {
    /// Where things live. Checks point every path at scratch folders (`init(environment:)`).
    public struct Setup: Sendable {
        public var bundleID: String
        /// The helper's executable, which the agent runs (`Pane Emulator.app/Contents/MacOS`).
        public var helperExecutable: URL?
        /// `~/Library/LaunchAgents`, or `PANE_LAUNCH_AGENTS`.
        public var agentsFolder: URL
        public var lockFile: URL
        /// The agent's output: `~/Library/Logs/Pane/takeover-repair.log`.
        public var agentLog: URL

        public init(bundleID: String, helperExecutable: URL?, agentsFolder: URL, lockFile: URL, agentLog: URL) {
            self.bundleID = bundleID
            self.helperExecutable = helperExecutable
            self.agentsFolder = agentsFolder
            self.lockFile = lockFile
            self.agentLog = agentLog
        }

        /// The real paths, with `PANE_LAUNCH_AGENTS` standing in for `~/Library/LaunchAgents`
        /// in checks.
        public init(
            bundleID: String, helperExecutable: URL?,
            environment: [String: String] = ProcessInfo.processInfo.environment,
            home: URL = FileManager.default.homeDirectoryForCurrentUser
        ) {
            let agents =
                environment["PANE_LAUNCH_AGENTS"].flatMap {
                    $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory)
                }
                ?? home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
            self.init(
                bundleID: bundleID, helperExecutable: helperExecutable, agentsFolder: agents,
                lockFile: TakeoverRepair.defaultLockFile(home: home),
                agentLog: home.appending(path: "Library/Logs/Pane/takeover-repair.log"))
        }

        public var plistURL: URL { RepairAgent.plistURL(bundleID: bundleID, agentsFolder: agentsFolder) }
        public var label: String { RepairAgent.label(bundleID: bundleID) }
        public var script: String { TakeoverWrapper.script(bundleID: bundleID) }
    }

    /// Why turning it on or off failed. Each has its own caption in Settings.
    public enum Failure: Error, Equatable, Sendable {
        /// The SDK's emulator folder couldn't be written (permissions, a read-only volume).
        case notWritable(URL)
        /// An emulator install is running in the SDK: try again once it's done.
        case updateRunning
        /// launchd refused the repair agent, or the bundle has no helper to run.
        case agentRefused(String)
        /// The SDK (or its emulator folder) is gone.
        case sdkMissing(URL)
        /// The launcher is someone else's script; Pane leaves it alone.
        case foreignLauncher(URL)
    }

    // MARK: - Finding the SDK

    /// The SDK to wrap when the switch turns on, as a real path (symlinks resolved, since
    /// launchd can't watch through one). `PANE_REAL_SDK` first (checks); then the login shell's
    /// `ANDROID_HOME` or `ANDROID_SDK_ROOT` (Pane opened from the Dock or by the wrapper has
    /// launchd's environment, not the shell's); then Pane's own lookup (`AndroidSDK`).
    public static func resolveSDK(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        shellTimeout: Duration
    ) async -> URL? {
        if let override = environment["PANE_REAL_SDK"], !override.isEmpty {
            return sdkRoot(URL(filePath: override, directoryHint: .isDirectory))
        }
        var lookup = environment
        if let shell = environment["SHELL"], shell.hasPrefix("/") {
            let shellValues = await loginShellAndroidVariables(shell: URL(filePath: shell), timeout: shellTimeout)
            for (name, value) in shellValues where !value.isEmpty { lookup[name] = value }
        }
        return AndroidSDK.emulatorExecutable(environment: lookup, home: home)
            .map { $0.deletingLastPathComponent().deletingLastPathComponent() }
            .flatMap(sdkRoot)
    }

    /// The SDK at `url` with symlinks resolved, when it has an emulator folder.
    public static func sdkRoot(_ url: URL) -> URL? {
        guard let real = realpath(url.path, nil) else { return nil }
        defer { free(real) }
        let resolved = URL(filePath: String(cString: real), directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(
                atPath: resolved.appending(path: "emulator").path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return resolved
    }

    static let shellBegin = "<<pane:"
    static let shellEnd = ":pane>>"

    /// `ANDROID_HOME` and `ANDROID_SDK_ROOT` as the user's login shell sets them, printed
    /// between markers so a greeting or a config's output can't be mistaken for them.
    static func loginShellAndroidVariables(shell: URL, timeout: Duration) async -> [String: String] {
        let names = ["ANDROID_HOME", "ANDROID_SDK_ROOT"]
        let command = names.map { "printf '\(shellBegin)%s\(shellEnd)' \"$\($0)\"" }.joined(separator: "; ")
        guard let result = try? await Adb.runProcess(shell, ["-l", "-i", "-c", command], timeout: timeout),
            result.status == 0
        else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: zip(names, shellValues(in: String(decoding: result.data, as: UTF8.self))))
    }

    /// The values between the markers, in order.
    static func shellValues(in output: String) -> [String] {
        output.components(separatedBy: shellBegin).dropFirst().compactMap { part in
            part.range(of: shellEnd).map { String(part[..<$0.lowerBound]) }
        }
    }

    // MARK: - On and off

    /// How long turning it on waits for a repair already running, and its folder checks.
    static func installOptions(_ lockFile: URL) -> TakeoverRepair.Options {
        TakeoverRepair.Options(
            quiet: .zero, timeout: .seconds(5), pollInterval: .milliseconds(100),  // design-ok: engine timing
            lockFile: lockFile, waitsForLock: true)
    }

    /// Wraps the launcher, then writes and loads the agent. Wrapping comes first, so the agent's
    /// first run (launchd starts it once on load) finds it already done.
    public static func install(sdk: URL, setup: Setup) async throws(Failure) {
        let outcome = await Task.detached {
            TakeoverRepair.wrap(sdk: sdk, script: setup.script, options: installOptions(setup.lockFile))
        }.value
        try check(outcome, sdk: sdk)
        try await installAgent(sdk: sdk, setup: setup)
    }

    /// Unloads and removes the agent, then puts the real launcher back.
    public static func uninstall(sdk: URL?, setup: Setup) async throws(Failure) {
        await bootout(setup: setup)
        try? FileManager.default.removeItem(at: setup.plistURL)
        guard let sdk else { return }
        switch TakeoverRepair.unwrap(sdk: sdk) {
        case .restored, .nothingToDo, .noFolder, .realMissing: return
        case .failed: throw .notWritable(sdk.appending(path: "emulator"))
        }
    }

    /// On launch, with the switch on: rewrites the agent if it changed (Pane moved, another
    /// SDK) and repairs the wrapper, waiting out an install in flight like the agent does.
    /// Returns what the repair did, for the log.
    @discardableResult
    public static func ensure(sdk: URL, setup: Setup) async throws(Failure) -> TakeoverRepair.Outcome {
        try await installAgent(sdk: sdk, setup: setup)
        let outcome = await Task.detached {
            TakeoverRepair.wrap(
                sdk: sdk, script: setup.script, options: RepairAgent.agentOptions(lockFile: setup.lockFile))
        }.value
        if outcome != .busy { try check(outcome, sdk: sdk) }
        return outcome
    }

    private static func check(_ outcome: TakeoverRepair.Outcome, sdk: URL) throws(Failure) {
        switch outcome {
        case .wrapped, .updated, .alreadyWrapped: return
        case .noFolder: throw .sdkMissing(sdk)
        case .installInProgress, .busy: throw .updateRunning
        case .foreignLauncher: throw .foreignLauncher(sdk.appending(path: "emulator/emulator"))
        case .failed: throw .notWritable(sdk.appending(path: "emulator"))
        }
    }

    /// Writes the plist when its contents changed (an unchanged file isn't touched, so macOS
    /// has nothing new to announce) and loads it when it isn't loaded.
    static func installAgent(sdk: URL, setup: Setup) async throws(Failure) {
        guard let helper = setup.helperExecutable else { throw .agentRefused("no helper in the bundle") }
        let data: Data
        do {
            data = try RepairAgent.plist(
                bundleID: setup.bundleID, helperExecutable: helper, sdk: sdk, log: setup.agentLog)
        } catch {
            throw .agentRefused(String(describing: error))
        }
        let files = FileManager.default
        let changed = (try? Data(contentsOf: setup.plistURL)) != data
        if changed {
            do {
                try files.createDirectory(at: setup.agentsFolder, withIntermediateDirectories: true)
                try files.createDirectory(
                    at: setup.agentLog.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: setup.plistURL, options: .atomic)
            } catch {
                throw .agentRefused("couldn't write \(setup.plistURL.path): \(error)")
            }
            await bootout(setup: setup)
        } else if await isLoaded(setup: setup) {
            return
        }
        let result = try? await launchctl(["bootstrap", domain, setup.plistURL.path(percentEncoded: false)])
        guard let result, result.status == 0 else {
            throw .agentRefused(result.map { String(decoding: $0.data, as: UTF8.self) } ?? "launchctl didn't answer")
        }
    }

    /// Whether launchd has the agent loaded.
    public static func isLoaded(setup: Setup) async -> Bool {
        (try? await launchctl(["print", "\(domain)/\(setup.label)"]))?.status == 0
    }

    static func bootout(setup: Setup) async {
        _ = try? await launchctl(["bootout", "\(domain)/\(setup.label)"])
    }

    private static var domain: String { "gui/\(getuid())" }

    private static let launchctlTimeout: Duration = .seconds(10)  // design-ok: engine timing, not a UI value

    private static func launchctl(_ arguments: [String]) async throws -> (status: Int32, data: Data) {
        try await Adb.runProcess(URL(filePath: "/bin/launchctl"), arguments, timeout: launchctlTimeout)
    }

    // MARK: - State

    /// The agent as macOS sees it.
    public enum AgentStatus: Equatable, Sendable {
        /// The plist isn't there.
        case missing
        case present
        /// Turned off in System Settings › Login Items & Extensions: repairs don't run.
        case disabled
    }

    /// `SMAppService.statusForLegacyPlist(at:)` says `.requiresApproval` for a legacy agent the
    /// user turned off (it says `.enabled` for one that's on, and `.notRegistered` for a plist
    /// Background Task Management doesn't track, such as a check's scratch folder).
    public static func agentStatus(setup: Setup) -> AgentStatus {
        guard FileManager.default.fileExists(atPath: setup.plistURL.path) else { return .missing }
        return SMAppService.statusForLegacyPlist(at: setup.plistURL) == .requiresApproval ? .disabled : .present
    }

    // MARK: - The old shadow SDK (1.0.x)

    public static let beginMark = "# >>> pane emulator takeover >>>"

    /// The old shadow SDK (`PANE_SHADOW_SDK` in checks). `AndroidSDK` still skips it.
    public static func shadowSDK(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment["PANE_SHADOW_SDK"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return home.appending(path: "Library/Android/pane-sdk", directoryHint: .isDirectory)
    }

    /// The shell configs the old version edited (`PANE_FISH_CONFIG`, `PANE_ZSH_CONFIGS` in checks).
    public static func shellConfigs(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let fish =
            environment["PANE_FISH_CONFIG"].flatMap { $0.isEmpty ? nil : URL(filePath: $0) }
            ?? home.appending(path: ".config/fish/config.fish")
        let zsh =
            environment["PANE_ZSH_CONFIGS"].map { $0.split(separator: " ").map { URL(filePath: String($0)) } }
            ?? [".zprofile", ".zshrc"].map { home.appending(path: $0) }
        return [fish] + zsh
    }

    /// What the old version left on this Mac.
    public enum LegacyState: Equatable, Sendable {
        case none
        /// Some of it (a block in a shell config, or the shadow SDK alone): remove it, but the
        /// old switch wasn't fully on.
        case partial
        /// The shadow SDK and every block: the old switch was on.
        case on
    }

    public static func legacyState(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> LegacyState {
        let shadow = shadowSDK(environment: environment, home: home)
        let hasShadow = FileManager.default.fileExists(atPath: shadow.appending(path: ".pane-takeover").path)
        let blocks = shellConfigs(environment: environment, home: home).map { url in
            (try? String(contentsOf: url, encoding: .utf8))?.contains(beginMark) ?? false
        }
        if hasShadow && blocks.allSatisfy({ $0 }) { return .on }
        return hasShadow || blocks.contains(true) ? .partial : .none
    }

    public struct LegacyFailure: Error, CustomStringConvertible {
        public var status: Int32
        public var output: String
        public var description: String { "emulator-takeover.sh uninstall exited \(status): \(output)" }
    }

    /// Runs the old uninstall (`scripts/emulator-takeover.sh`, bundled; it backs up each shell
    /// config before taking its block out) with `/bin/sh`, arguments passed as they are.
    public static func runLegacyUninstall(script: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [script.path, "uninstall"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        async let data = Adb.readToEnd(pipe.fileHandleForReading)
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                try? pipe.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }
        let output = String(decoding: await data, as: UTF8.self)
        guard status == 0 else { throw LegacyFailure(status: status, output: output) }
        return output
    }
}

/// A request to show an AVD, from the emulator wrapper: `pane://attach?avd=<name>` (reaches a
/// running Pane) or `--attach <name>` on launch.
public enum AttachRequest {
    public static let scheme = "pane"

    public static func avdName(from url: URL) -> String? {
        guard url.scheme == scheme, url.host() == "attach",
            let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "avd" })?.value
        else { return nil }
        return valid(name)
    }

    public static func avdName(fromArguments arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--attach"), arguments.indices.contains(index + 1) else {
            return nil
        }
        return valid(arguments[index + 1])
    }

    /// AVD names are letters, digits, `.`, `_` and `-` (the AVD Manager's rule).
    private static func valid(_ name: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !name.isEmpty, name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return name
    }
}

/// Calls back (debounced by the caller) when entries of the SDK's root folder change: an
/// emulator update renames `emulator` away and a new one in, so Pane repairs while it runs.
/// A kqueue vnode source on the root, like `RegistrationWatcher`.
public final class SDKFolderWatcher: @unchecked Sendable {
    // Unchecked: `source` is only touched from `queue`.
    private let queue = DispatchQueue(label: "dev.niduslabs.pane.sdk-watcher")
    private var source: (any DispatchSourceFileSystemObject)?
    private let onChange: @Sendable () -> Void

    public init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }

    deinit { source?.cancel() }

    /// Watches `sdk` (the root) and its `emulator` folder's parent entry. False when it can't
    /// be opened.
    @discardableResult
    public func start(sdk: URL) -> Bool {
        queue.sync {
            source?.cancel()
            source = nil
            let descriptor = open(sdk.path, O_EVTONLY)
            guard descriptor >= 0 else { return false }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: queue)
            let onChange = onChange
            source.setEventHandler { onChange() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.source = source
            return true
        }
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
        }
    }
}
