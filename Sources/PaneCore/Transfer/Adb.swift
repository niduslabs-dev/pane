import Foundation

/// Runs `adb` against one emulator. Always the real SDK's adb, through `Process` with each
/// argument passed as it is (no local shell).
public struct Adb: Sendable {
    public var executable: URL
    /// `emulator-<console port>`, the serial adb gives an emulator.
    public var serial: String

    public init(executable: URL, serial: String) {
        self.executable = executable
        self.serial = serial
    }

    /// Nil when the emulator's registration has no console port or no adb is found.
    public init?(emulator: RunningEmulator) {
        guard let serial = Self.serial(consolePort: emulator.consolePort), let executable = AndroidSDK.adbExecutable()
        else { return nil }
        self.init(executable: executable, serial: serial)
    }

    public static func serial(consolePort: Int?) -> String? {
        guard let port = consolePort, (1...Int(UInt16.max)).contains(port) else { return nil }
        return "emulator-\(port)"
    }

    public struct Failure: Error, Equatable {
        /// One plain sentence for the status line ("Couldn't install. This file isn't an
        /// Android app.").
        public var message: String
        /// adb's own reason ("INSTALL_PARSE_FAILED_NOT_APK"), shown behind Details. Nil when
        /// adb gave none.
        public var detail: String?

        public init(message: String, detail: String? = nil) {
            self.message = message
            self.detail = detail
        }
    }

    /// Single-quotes a string for the device's shell.
    public static func deviceShellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// adb's reason, cut to one short line: the code inside "Failure [...]" for an install
    /// ("INSTALL_FAILED_OLDER_SDK"), else adb's last line without its "adb: error:" lead.
    /// Empty when adb printed nothing.
    public static func reason(from output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var reason = ""
        if let failure = lines.last(where: { $0.contains("Failure [") }),
            let open = failure.range(of: "Failure ["), let close = failure[open.upperBound...].firstIndex(of: "]")
        {
            // "INSTALL_FAILED_X: long explanation" keeps only the code.
            reason = String(failure[open.upperBound..<close].prefix { $0 != ":" })
        } else if let last = lines.last(where: { !$0.isEmpty }) {
            reason = last
            for lead in ["adb: error: ", "adb: ", "error: "] where reason.hasPrefix(lead) {
                reason = String(reason.dropFirst(lead.count))
            }
        }
        reason = reason.replacingOccurrences(of: "\u{2014}", with: "-")
        if reason.count > maxReasonLength { reason = reason.prefix(maxReasonLength - 1) + "…" }
        return reason
    }

    static let maxReasonLength = 48

    /// adb's whole failure for Details: everything inside "Failure [...]" for an install, else
    /// adb's last line without its "adb: error:" lead, cut at `maxDetailLength`. Nil when adb
    /// printed nothing.
    public static func detail(from output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var detail: String
        if let failure = lines.last(where: { $0.contains("Failure [") }),
            let open = failure.range(of: "Failure ["), let close = failure.lastIndex(of: "]"),
            open.upperBound <= close
        {
            detail = String(failure[open.upperBound..<close])
        } else if let error = lines.first(where: { $0.contains("Error: ") }),
            let start = error.range(of: "Error: ")
        {
            // pm's exception dump: the "Error: …" message, not the stack under it.
            detail = String(error[start.upperBound...])
        } else if let last = lines.last(where: { !$0.isEmpty }) {
            detail = last
            for lead in ["adb: error: ", "adb: ", "error: "] where detail.hasPrefix(lead) {
                detail = String(detail.dropFirst(lead.count))
            }
        } else {
            return nil
        }
        detail = detail.replacingOccurrences(of: "\u{2014}", with: "-")
        if detail.count > maxDetailLength { detail = detail.prefix(maxDetailLength - 1) + "…" }
        return detail
    }

    static let maxDetailLength = 300

    /// What one adb call printed (standard output and error together) and its exit status.
    public struct Output: Sendable, Equatable {
        public var status: Int32
        public var text: String

        public init(status: Int32, text: String) {
            self.status = status
            self.text = text
        }
    }

    /// The full argument list for a call against this emulator: `-s <serial>`, then `arguments`.
    public func targeted(_ arguments: [String]) -> [String] { ["-s", serial] + arguments }

    /// Runs adb against this emulator with `arguments` exactly as given (never a local shell)
    /// and returns what it printed. A call still running after `timeout` is stopped and throws
    /// `Failure`. Remember that `adb shell` joins its arguments for the device's own shell:
    /// quote anything user-typed with `deviceShellQuoted`.
    public func run(_ arguments: [String], timeout: Duration = Adb.defaultTimeout) async throws -> Output {
        do {
            let result = try await Self.runProcess(executable, targeted(arguments), timeout: timeout)
            return Output(status: result.status, text: String(decoding: result.data, as: UTF8.self))
        } catch is ProcessTimeout {
            throw Failure(message: "adb took too long.")
        }
    }

    /// A tool call that ran past its timeout and was stopped.
    public struct ProcessTimeout: Error, Equatable {}

    /// Runs any local tool (aapt2, unzip) with `arguments` exactly as given, never through a
    /// shell, and returns its exit status and everything it printed (standard output and error
    /// together). Throws `ProcessTimeout` after stopping a call still running at `timeout`.
    public static func runProcess(
        _ executable: URL, _ arguments: [String], timeout: Duration
    ) async throws -> (status: Int32, data: Data) {
        try await withThrowingTaskGroup(of: (status: Int32, data: Data)?.self) { group in
            let process = Process()
            group.addTask { try await Self.run(executable, arguments, process: process) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let output = first else {
                if process.isRunning { process.terminate() }
                throw ProcessTimeout()
            }
            return output
        }
    }

    /// How long a general adb call may run before it is stopped.
    public static let defaultTimeout: Duration = .seconds(20)

    /// The last line adb printed that says something, without its "adb: error:" lead-ins, cut
    /// to one short line. Empty when adb printed nothing.
    public static func shortReason(from output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard var reason = lines.last(where: { !$0.isEmpty }) else { return "" }
        for lead in ["adb: error: ", "adb: ", "error: ", "Error: ", "ERROR: "] where reason.hasPrefix(lead) {
            reason = String(reason.dropFirst(lead.count))
        }
        reason = reason.replacingOccurrences(of: "\u{2014}", with: "-")
        if reason.count > maxReasonLength { reason = reason.prefix(maxReasonLength - 1) + "…" }
        return reason
    }

    private static func run(
        _ executable: URL, _ arguments: [String], process: Process = Process()
    ) async throws -> (status: Int32, data: Data) {
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        // Read while it runs: adb's push progress can fill the pipe.
        async let output = readToEnd(pipe.fileHandleForReading)
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
        return (status, await output)
    }

    /// Reads `handle` until every writer has closed it, on a Dispatch thread. The read blocks
    /// for as long as the tool runs, and on a Swift concurrency thread it can take the last one
    /// the cooperative pool has (one per core): then the timeout that would stop the tool never
    /// runs, and nothing else async in the process does either.
    static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }
}
