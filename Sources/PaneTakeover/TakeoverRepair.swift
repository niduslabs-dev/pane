import Darwin
import Foundation

/// Puts Pane's wrapper in front of an SDK's emulator launcher, and takes it away again. One
/// routine for turning the setting on, for Pane's repair on launch and while it runs, and for
/// the launch agent's repair after an emulator update (`Pane Emulator --repair`).
///
/// An emulator update (sdkmanager or Android Studio, same installer) unpacks the new version
/// while `<sdk>/emulator/.installer` exists, renames `emulator` to `emulator.backup`, renames the
/// new folder in, writes its `package.xml` and deletes the backup: the wrapper goes with it.
/// So a repair:
/// - waits until no install is in flight (no `.installer`, no `emulator.backup`, a
///   `package.xml`) and the folder hasn't changed for `quiet`;
/// - holds a lock, so Pane and the agent never repair at the same time;
/// - does every step relative to one open handle on the folder (`linkat`, `openat`,
///   `renameat`), so a folder swapped out mid-repair takes the whole repair with it and the new
///   folder is never left half wrapped;
/// - hard-links `emulator` to `emulator-real`, then renames the wrapper over `emulator`, so
///   there is never a moment without a launcher;
/// - is a no-op when the folder already has the current wrapper.
public enum TakeoverRepair {
    public enum Outcome: Equatable, Sendable {
        /// The real launcher was moved aside and the wrapper put in.
        case wrapped
        /// An older or different wrapper of Pane's was replaced.
        case updated
        case alreadyWrapped
        /// `<sdk>/emulator` isn't there (an uninstall, or a wrong path).
        case noFolder
        /// An install was still in flight, or the folder kept changing, until the time ran out.
        case installInProgress
        /// Another repair holds the lock.
        case busy
        /// The launcher is a script that isn't Pane's: left alone.
        case foreignLauncher
        /// A file operation failed; `step` names it, `code` is its errno.
        case failed(step: String, code: Int32)
    }

    public struct Options: Sendable {
        /// How long the folder must stay unchanged before wrapping. Zero wraps at once.
        public var quiet: Duration
        /// How long to wait for an install to finish (and for the lock, when `waitsForLock`).
        public var timeout: Duration
        public var pollInterval: Duration
        public var lockFile: URL
        /// Pane waits for a running repair to finish; the agent leaves it to the one running.
        public var waitsForLock: Bool
        /// Called after `emulator-real` is linked and before the wrapper is renamed in; the
        /// swap-mid-repair test moves the folder here.
        public var afterLink: (@Sendable () -> Void)?

        public init(
            quiet: Duration, timeout: Duration, pollInterval: Duration, lockFile: URL, waitsForLock: Bool,
            afterLink: (@Sendable () -> Void)? = nil
        ) {
            self.quiet = quiet
            self.timeout = timeout
            self.pollInterval = pollInterval
            self.lockFile = lockFile
            self.waitsForLock = waitsForLock
            self.afterLink = afterLink
        }
    }

    /// The lock shared by every Pane copy and the agent for one user:
    /// `~/Library/Caches/dev.niduslabs.pane/takeover-repair.lock`. Kept out of the SDK.
    public static func defaultLockFile(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Caches/dev.niduslabs.pane/takeover-repair.lock")
    }

    /// What `<sdk>/emulator/emulator` is now.
    public enum LauncherState: Equatable, Sendable {
        case missing
        /// The real launcher, not wrapped.
        case real
        /// Pane's wrapper; `current` when it is exactly `script`.
        case wrapped(current: Bool)
        case foreign
    }

    public static func launcherState(sdk: URL, script: String) -> LauncherState {
        let launcher = sdk.appending(path: "emulator/\(TakeoverWrapper.launcherName)")
        guard let handle = try? FileHandle(forReadingFrom: launcher) else { return .missing }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: headLength)) ?? Data()
        if TakeoverWrapper.isWrapper(head) {
            let all = head + ((try? handle.readToEnd()) ?? Data())
            return .wrapped(current: all == Data(script.utf8))
        }
        return head.starts(with: Data("#!".utf8)) ? .foreign : .real
    }

    /// Whether an emulator install looks in flight right now.
    public static func installInFlight(sdk: URL) -> Bool {
        let files = FileManager.default
        let folder = sdk.appending(path: "emulator")
        return files.fileExists(atPath: folder.appending(path: ".installer").path)
            || files.fileExists(atPath: sdk.appending(path: "emulator.backup").path)
            || !files.fileExists(atPath: folder.appending(path: "package.xml").path)
    }

    /// Wraps `<sdk>/emulator/emulator` with `script` once the folder is quiet. Blocks (it
    /// sleeps while it waits), so call it off the main thread.
    public static func wrap(sdk: URL, script: String, options: Options) -> Outcome {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: options.timeout)
        let folder = sdk.appending(path: "emulator")
        guard exists(folder) else { return .noFolder }

        guard let lock = acquireLock(options.lockFile, waits: options.waitsForLock, until: deadline, options: options)
        else { return .busy }
        defer { close(lock) }

        guard waitUntilSettled(sdk: sdk, options: options, deadline: deadline) else {
            return exists(folder) ? .installInProgress : .noFolder
        }

        let directory = open(folder.path, O_RDONLY | O_DIRECTORY)
        guard directory >= 0 else { return exists(folder) ? .failed(step: "open", code: errno) : .noFolder }
        defer { close(directory) }

        let wanted = Data(script.utf8)
        guard let head = readAt(directory, TakeoverWrapper.launcherName, limit: headLength) else {
            return .failed(step: "read", code: errno)
        }
        if TakeoverWrapper.isWrapper(head) {
            guard let whole = readAt(directory, TakeoverWrapper.launcherName, limit: Int.max) else {
                return .failed(step: "read", code: errno)
            }
            if whole == wanted { return .alreadyWrapped }
            guard exists(folder.appending(path: TakeoverWrapper.realName)) else {
                return .failed(step: "find \(TakeoverWrapper.realName)", code: ENOENT)
            }
            if let failure = writeWrapper(wanted, into: directory) { return failure }
            return .updated
        }
        if head.starts(with: Data("#!".utf8)) { return .foreignLauncher }

        if unlinkat(directory, TakeoverWrapper.realName, 0) != 0, errno != ENOENT {
            return .failed(step: "unlink", code: errno)
        }
        guard linkat(directory, TakeoverWrapper.launcherName, directory, TakeoverWrapper.realName, 0) == 0 else {
            return .failed(step: "link", code: errno)
        }
        options.afterLink?()
        if let failure = writeWrapper(wanted, into: directory) { return failure }
        return .wrapped
    }

    public enum UnwrapOutcome: Equatable, Sendable {
        /// `emulator-real` is `emulator` again.
        case restored
        /// Nothing of Pane's was there.
        case nothingToDo
        case noFolder
        /// Pane's wrapper is there but `emulator-real` isn't (left as is).
        case realMissing
        case failed(step: String, code: Int32)
    }

    /// Puts the real launcher back: renames `emulator-real` over Pane's wrapper (one atomic
    /// step). Leaves a launcher that isn't Pane's alone.
    public static func unwrap(sdk: URL) -> UnwrapOutcome {
        let folder = sdk.appending(path: "emulator")
        let directory = open(folder.path, O_RDONLY | O_DIRECTORY)
        guard directory >= 0 else { return exists(folder) ? .failed(step: "open", code: errno) : .noFolder }
        defer { close(directory) }
        let head = readAt(directory, TakeoverWrapper.launcherName, limit: headLength) ?? Data()
        var real = stat()
        let hasReal = fstatat(directory, TakeoverWrapper.realName, &real, AT_SYMLINK_NOFOLLOW) == 0
        if TakeoverWrapper.isWrapper(head) {
            guard hasReal else { return .realMissing }
            guard renameat(directory, TakeoverWrapper.realName, directory, TakeoverWrapper.launcherName) == 0 else {
                return .failed(step: "rename", code: errno)
            }
            return .restored
        }
        var launcher = stat()
        if hasReal, fstatat(directory, TakeoverWrapper.launcherName, &launcher, AT_SYMLINK_NOFOLLOW) == 0,
            launcher.st_ino == real.st_ino
        {
            unlinkat(directory, TakeoverWrapper.realName, 0)
        }
        return .nothingToDo
    }

    // MARK: - Steps

    private static let headLength = 4096
    private static let tempName = ".emulator.pane-tmp"
    private static let executableMode: mode_t = 0o755

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Waits for the conditions in the type's comment. False when the deadline passed first or
    /// the folder went away.
    private static func waitUntilSettled(sdk: URL, options: Options, deadline: ContinuousClock.Instant) -> Bool {
        let clock = ContinuousClock()
        let folder = sdk.appending(path: "emulator")
        while true {
            guard exists(folder) else { return false }
            if !installInFlight(sdk: sdk) {
                if options.quiet == .zero { return true }
                let before = snapshot(folder)
                sleep(options.quiet)
                if !installInFlight(sdk: sdk), snapshot(folder) == before { return true }
            } else {
                sleep(options.pollInterval)
            }
            if clock.now >= deadline { return false }
        }
    }

    /// The folder's identity and top-level names with their sizes and change times.
    private static func snapshot(_ folder: URL) -> [String] {
        var info = stat()
        guard stat(folder.path, &info) == 0 else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let entries = names.sorted().map { name -> String in
            var entry = stat()
            lstat(folder.appending(path: name).path, &entry)
            return "\(name) \(entry.st_ino) \(entry.st_size) \(entry.st_ctimespec.tv_sec).\(entry.st_ctimespec.tv_nsec)"
        }
        return ["\(info.st_ino) \(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"] + entries
    }

    private static func sleep(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        let attosecondsPerMicrosecond: Int64 = 1_000_000_000_000
        let microsecondsPerSecond: Int64 = 1_000_000
        usleep(useconds_t(clamping: seconds * microsecondsPerSecond + attoseconds / attosecondsPerMicrosecond))
    }

    /// An exclusive `flock` on `url` (released when the process ends, so a crash never leaves
    /// it held). Nil when another repair holds it and `waits` is false, or past the deadline.
    private static func acquireLock(
        _ url: URL, waits: Bool, until deadline: ContinuousClock.Instant, options: Options
    ) -> Int32? {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ownerReadWrite: mode_t = 0o600
        let descriptor = open(url.path, O_RDWR | O_CREAT, ownerReadWrite)
        guard descriptor >= 0 else { return nil }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard waits, ContinuousClock().now < deadline else {
                close(descriptor)
                return nil
            }
            sleep(options.pollInterval)
        }
        return descriptor
    }

    /// Reads up to `limit` bytes of `name` in the folder `directory`, not following a symlink.
    private static func readAt(_ directory: Int32, _ name: String, limit: Int) -> Data? {
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW)
        guard file >= 0 else { return nil }
        defer { close(file) }
        var data = Data()
        let chunk = 65_536
        var buffer = [UInt8](repeating: 0, count: chunk)
        while data.count < limit {
            let count = read(file, &buffer, min(chunk, limit - data.count))
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    /// Writes the wrapper to a temporary file in the folder and renames it over `emulator`.
    private static func writeWrapper(_ data: Data, into directory: Int32) -> Outcome? {
        unlinkat(directory, tempName, 0)
        let file = openat(directory, tempName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, executableMode)
        guard file >= 0 else { return .failed(step: "create", code: errno) }
        let written = data.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
        let writeError = errno
        fchmod(file, executableMode)
        close(file)
        guard written == data.count else {
            unlinkat(directory, tempName, 0)
            return .failed(step: "write", code: writeError)
        }
        guard renameat(directory, tempName, directory, TakeoverWrapper.launcherName) == 0 else {
            let code = errno
            unlinkat(directory, tempName, 0)
            return .failed(step: "rename", code: code)
        }
        return nil
    }
}
