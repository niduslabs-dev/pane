import Darwin
import Foundation

/// An emulator Pane started: its PID, which is the PID it registers with.
public struct LaunchedEmulator {
    public let pid: Int32
    /// The process, when Pane started it itself (no helper in the bundle); nil through the helper.
    let process: Process?

    /// Whether it is still running.
    public var isAlive: Bool { process?.isRunning ?? EmulatorDiscovery.processIsAlive(pid) }

    /// Its exit status once it has ended, when Pane started it itself. Through the helper the
    /// emulator isn't Pane's child, so no status comes back; its log says why it ended.
    public var exitStatus: Int32? {
        guard let process, !process.isRunning else { return nil }
        return process.terminationStatus
    }
}

/// Starts an AVD headless and stops emulators by PID.
///
/// Pane is how a headless emulator is seen, so it runs with no window or boot animation,
/// without sound unless Settings says otherwise, and never saves a snapshot on exit (a cold boot each time, as Jatin runs it).
/// The binary never runs through a shell.
public enum EmulatorLauncher {
    public static func arguments(avdName: String, withoutSound: Bool = true) -> [String] {
        ["-avd", avdName, "-no-window"] + (withoutSound ? ["-no-audio"] : []) + ["-no-boot-anim", "-no-snapshot-save"]
    }

    /// Why a launch through the helper failed.
    public enum LaunchError: Error, Equatable {
        /// `/usr/bin/open` refused the helper; `output` is what it printed.
        case openFailed(status: Int32, output: String)
        /// The helper started but never said its PID.
        case noPID
    }

    /// Where the helper sits inside Pane.app (`scripts/build-app.sh` puts it there).
    public static let helperPath = "Contents/Helpers/Pane Emulator.app"

    /// The helper in `bundle`, or nil when it isn't there (`swift run`, tests), in which case
    /// `launch` starts the emulator itself.
    public static func helperURL(in bundle: Bundle = .main) -> URL? {
        let url = bundle.bundleURL.appending(path: helperPath, directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return nil }
        return url
    }

    /// The Android variables the emulator reads. An app started through LaunchServices gets
    /// launchd's environment, not Pane's, so these are passed on with `open --env`.
    static let forwardedEnvironment = [
        "ANDROID_AVD_HOME", "ANDROID_EMULATOR_HOME", "ANDROID_HOME", "ANDROID_SDK_ROOT", "ANDROID_USER_HOME",
    ]

    /// `/usr/bin/open`'s arguments for starting the emulator through the helper: in the
    /// background (`-g`), always a new instance (`-n`, one per emulator), then the helper's own
    /// arguments (`<pid-file> <log or empty> <executable> <emulator arguments…>`).
    public static func helperOpenArguments(
        helper: URL, pidFile: URL, outputLog: URL?, executable: URL, arguments: [String],
        environment: [String: String]
    ) -> [String] {
        let passed = forwardedEnvironment.compactMap { name in
            environment[name].flatMap { $0.isEmpty ? nil : ["--env", "\(name)=\($0)"] }
        }
        let helperArguments = [pidFile.path, outputLog?.path ?? "", executable.path] + arguments
        return ["-g", "-n"] + passed.flatMap { $0 } + [helper.path, "--args"] + helperArguments
    }

    /// How long a launch through the helper may take (the app's values: `Theme.Timing.helperLaunch`).
    public struct HelperTimings: Sendable {
        /// How long `open` may take to start the helper.
        public var openTimeout: Duration
        /// How long the helper may take to write its PID once `open` returns.
        public var pidTimeout: Duration
        public var pidPollInterval: Duration

        public init(openTimeout: Duration, pidTimeout: Duration, pidPollInterval: Duration) {
            self.openTimeout = openTimeout
            self.pidTimeout = pidTimeout
            self.pidPollInterval = pidPollInterval
        }
    }

    /// The helper to launch through: where it is (`helperURL(in:)`) and how long it may take.
    public struct Helper: Sendable {
        public var url: URL
        public var timings: HelperTimings

        public init(url: URL, timings: HelperTimings) {
            self.url = url
            self.timings = timings
        }
    }

    /// Launches the emulator and returns its PID. The emulator writes its registration file
    /// once its gRPC endpoint is up.
    ///
    /// With `helper` (Pane.app's "Pane Emulator"), it goes through LaunchServices: `/usr/bin/open`
    /// starts the helper, which writes its PID to a file and `exec`s the emulator. LaunchServices
    /// starts every app in its own process coalition, so the emulator isn't in Pane's. Started
    /// from Pane's own process (`Process`, `posix_spawn`, even with `setsid`), it would be, and on
    /// macOS 27 it then keeps Pane's app record alive after Pane quits: the Dock shows Pane as
    /// "Running in Background" and Background Task Management records "Pane - background
    /// tasks". `NSWorkspace.openApplication` isn't used because it records Pane as the helper's
    /// parent, which has the same effect; `open` doesn't (observed on macOS 27, not documented).
    /// launchd jobs (`launchctl bootstrap`, `SMJobSubmit`) stay tied to the app too. Evidence:
    /// `.claude/research/emulator-detach.md`.
    ///
    /// Without `helper` (a `swift run` build), it starts the emulator as Pane's child.
    ///
    /// Its output goes to `outputLog` (the previous launch's is kept beside it), or nowhere
    /// when that is nil or can't be written. The emulator's last lines are the only place a
    /// crash in its graphics code says why (a Metal assertion is printed, not put in the crash
    /// report), so Pane keeps them.
    public static func launch(
        executable: URL, avdName: String, withoutSound: Bool = true, outputLog: URL? = nil, helper: Helper?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> LaunchedEmulator {
        let arguments = arguments(avdName: avdName, withoutSound: withoutSound)
        guard let helper else {
            return try launchDirectly(executable: executable, arguments: arguments, outputLog: outputLog)
        }
        let log = outputLog.flatMap { prepareOutputLog(at: $0) ? $0 : nil }
        let pidFile = FileManager.default.temporaryDirectory.appending(path: "pane-emulator-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let openArguments = helperOpenArguments(
            helper: helper.url, pidFile: pidFile, outputLog: log, executable: executable, arguments: arguments,
            environment: environment)
        let result = try await Adb.runProcess(
            URL(filePath: "/usr/bin/open"), openArguments, timeout: helper.timings.openTimeout)
        guard result.status == 0 else {
            throw LaunchError.openFailed(status: result.status, output: String(decoding: result.data, as: UTF8.self))
        }
        guard
            let pid = await readPID(
                from: pidFile, within: helper.timings.pidTimeout, pollInterval: helper.timings.pidPollInterval)
        else {
            throw LaunchError.noPID
        }
        return LaunchedEmulator(pid: pid, process: nil)
    }

    /// Today's path for builds without the helper: the emulator as Pane's child.
    static func launchDirectly(executable: URL, arguments: [String], outputLog: URL?) throws -> LaunchedEmulator {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = outputLog.flatMap(openOutputLog(at:)) ?? FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        return LaunchedEmulator(pid: process.processIdentifier, process: process)
    }

    /// Waits for the helper's PID file and reads it. Nil when none with a valid PID turns up
    /// within `limit`. The helper writes it through a rename, so a file that is there is whole.
    static func readPID(from url: URL, within limit: Duration, pollInterval: Duration) async -> Int32? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: limit)
        repeat {
            if let text = try? String(contentsOf: url, encoding: .utf8),
                let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0
            {
                return pid
            }
            try? await Task.sleep(for: pollInterval)
        } while clock.now < deadline && !Task.isCancelled
        return nil
    }

    /// Where a launch's output is kept: `~/Library/Logs/Pane/emulator-<avd>.log`. Characters
    /// that can't be in a file name become `_`.
    public static func outputLog(
        avdName: String, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let safe = String(avdName.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "_" })
        return home.appending(path: "Library/Logs/Pane/emulator-\(safe).log")
    }

    /// The log that `url` held before the launch that is writing it now.
    public static func previousOutputLog(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("previous.log")
    }

    /// Moves the last launch's log aside and opens an empty one, readable by the user only.
    /// Nil when the folder or the file can't be made.
    static func openOutputLog(at url: URL) -> FileHandle? {
        guard prepareOutputLog(at: url) else { return nil }
        return try? FileHandle(forWritingTo: url)
    }

    /// Moves the last launch's log aside and creates an empty one, readable by the user only.
    /// False when the folder or the file can't be made.
    static func prepareOutputLog(at url: URL) -> Bool {
        let files = FileManager.default
        do {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if files.fileExists(atPath: url.path) {
                let previous = previousOutputLog(for: url)
                try? files.removeItem(at: previous)
                try files.moveItem(at: url, to: previous)
            }
            let ownerReadWrite = 0o600
            return files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: ownerReadWrite])
        } catch {
            return false
        }
    }

    /// Asks a process to quit (SIGTERM), then kills it (SIGKILL) if it is still alive after
    /// `gracePeriod`. Returns once it is gone or `gracePeriod + killWait` has passed.
    public static func stop(
        pid: Int32, gracePeriod: Duration, killWait: Duration, pollInterval: Duration
    ) async -> Bool {
        guard pid > 0, EmulatorDiscovery.processIsAlive(pid) else { return true }
        kill(pid, SIGTERM)
        if await waitForExit(pid: pid, within: gracePeriod, pollInterval: pollInterval) { return true }
        kill(pid, SIGKILL)
        return await waitForExit(pid: pid, within: killWait, pollInterval: pollInterval)
    }

    private static func waitForExit(pid: Int32, within limit: Duration, pollInterval: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: limit)
        while clock.now < deadline {
            if !EmulatorDiscovery.processIsAlive(pid) { return true }
            try? await Task.sleep(for: pollInterval)
        }
        return !EmulatorDiscovery.processIsAlive(pid)
    }

    /// A process's parent PID, or nil when it can't be read. The `emulator` launcher may run the
    /// engine as its child, so "started by Pane" checks the registered PID and its parent.
    public static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
