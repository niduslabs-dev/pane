import Darwin
import Foundation

/// Starts an AVD headless and stops emulators by PID.
///
/// Pane is how a headless emulator is seen, so it runs with no window or boot animation,
/// without sound unless Settings says otherwise, and never saves a snapshot on exit (a cold boot each time, as Jatin runs it).
/// The binary runs through `Process`, never a shell.
public enum EmulatorLauncher {
    public static func arguments(avdName: String, withoutSound: Bool = true) -> [String] {
        ["-avd", avdName, "-no-window"] + (withoutSound ? ["-no-audio"] : []) + ["-no-boot-anim", "-no-snapshot-save"]
    }

    /// Launches the emulator and returns its process. The emulator writes its registration
    /// file once its gRPC endpoint is up.
    ///
    /// Its output goes to `outputLog` (the previous launch's is kept beside it), or nowhere
    /// when that is nil or can't be written. The emulator's last lines are the only place a
    /// crash in its graphics code says why (a Metal assertion is printed, not put in the crash
    /// report), so Pane keeps them.
    public static func launch(
        executable: URL, avdName: String, withoutSound: Bool = true, outputLog: URL? = nil
    ) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments(avdName: avdName, withoutSound: withoutSound)
        process.standardInput = FileHandle.nullDevice
        let output = outputLog.flatMap(openOutputLog(at:)) ?? FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        return process
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
        let files = FileManager.default
        do {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if files.fileExists(atPath: url.path) {
                let previous = previousOutputLog(for: url)
                try? files.removeItem(at: previous)
                try files.moveItem(at: url, to: previous)
            }
            let ownerReadWrite = 0o600
            guard
                files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: ownerReadWrite])
            else { return nil }
            return try FileHandle(forWritingTo: url)
        } catch {
            return nil
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
