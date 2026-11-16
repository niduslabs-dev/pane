import Darwin
import Foundation

/// Starts an AVD headless and stops emulators by PID.
///
/// Pane is how a headless emulator is seen, so it runs with no window, audio or boot
/// animation, and never saves a snapshot on exit (a cold boot each time, as Jatin runs it).
/// The binary runs through `Process`, never a shell.
public enum EmulatorLauncher {
    public static func arguments(avdName: String) -> [String] {
        ["-avd", avdName, "-no-window", "-no-audio", "-no-boot-anim", "-no-snapshot-save"]
    }

    /// Launches the emulator and returns its process. Output is discarded; the emulator writes
    /// its registration file once its gRPC endpoint is up.
    public static func launch(executable: URL, avdName: String) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments(avdName: avdName)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
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
