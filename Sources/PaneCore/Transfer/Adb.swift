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
        /// One short line for the status line.
        public var message: String
    }

    public func arguments(for step: DropPlan.Step) -> [String] {
        switch step {
        case .install(let url): ["-s", serial, "install", "-r", url.path(percentEncoded: false)]
        case .copy(let url, _): ["-s", serial, "push", url.path(percentEncoded: false), DropPlan.devicePath(for: url)]
        }
    }

    /// Asks the media store to index a pushed file, so the gallery shows it. `adb shell` joins
    /// its arguments into one command line for the device's shell, so the path is quoted for it.
    public func mediaScanArguments(devicePath: String) -> [String] {
        [
            "-s", serial, "shell",
            "content call --uri content://media --method scan_file --arg \(Self.deviceShellQuoted(devicePath))",
        ]
    }

    /// Single-quotes a string for the device's shell.
    public static func deviceShellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs one step (and the media scan after a media copy). Throws `Failure` with adb's
    /// reason in one line.
    public func run(_ step: DropPlan.Step) async throws {
        let result = try await Self.run(executable, arguments(for: step))
        // `adb install` can print "Failure [...]" yet exit 0 on old versions; check both.
        if result.status != 0 || result.output.contains("Failure [") {
            throw Failure(message: Self.shortError(from: result.output, step: step))
        }
        if case .copy(let url, true) = step {
            // Best effort: the file is on the device either way.
            _ = try? await Self.run(executable, mediaScanArguments(devicePath: DropPlan.devicePath(for: url)))
        }
    }

    /// adb's reason, cut to one short line: "Install failed: INSTALL_FAILED_OLDER_SDK".
    public static func shortError(from output: String, step: DropPlan.Step) -> String {
        let prefix =
            switch step {
            case .install: "Install failed"
            case .copy: "Copy failed"
            }
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
        guard !reason.isEmpty else { return "\(prefix)." }
        if reason.count > maxReasonLength { reason = reason.prefix(maxReasonLength - 1) + "…" }
        return "\(prefix): \(reason)"
    }

    static let maxReasonLength = 48

    private static func run(_ executable: URL, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        // Read while it runs: adb's push progress can fill the pipe.
        let reader = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }
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
        return (status, String(decoding: await reader.value, as: UTF8.self))
    }
}
