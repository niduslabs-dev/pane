import Darwin
import Foundation

/// Finds running emulators from the registration files each one writes at startup.
///
/// On macOS the emulator writes `~/Library/Caches/TemporaryItems/avd/running/pid_<pid>.ini`
/// (the path Android Studio's `RunningEmulatorCatalog` reads). Files can outlive a crashed
/// emulator, so each PID is checked for liveness.
public enum EmulatorDiscovery {
    /// The registration folder under a home directory.
    public static func registrationDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Caches/TemporaryItems/avd/running", directoryHint: .isDirectory)
    }

    /// Every live emulator in `directory`, sorted by PID. Unreadable or malformed files are skipped.
    public static func runningEmulators(
        in directory: URL = registrationDirectory(),
        isAlive: (Int32) -> Bool = processIsAlive
    ) -> [RunningEmulator] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name -> RunningEmulator? in
            guard pid(fromFileName: name) != nil else { return nil }
            guard let text = try? String(contentsOf: directory.appending(path: name), encoding: .utf8),
                let emulator = try? parse(fileName: name, contents: text),
                isAlive(emulator.pid)
            else { return nil }
            return emulator
        }
        .sorted { $0.pid < $1.pid }
    }

    /// The PID in a `pid_<digits>.ini` file name, or nil for any other name.
    public static func pid(fromFileName name: String) -> Int32? {
        guard name.hasPrefix("pid_"), name.hasSuffix(".ini") else { return nil }
        let digits = name.dropFirst("pid_".count).dropLast(".ini".count)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return Int32(digits)
    }

    /// Parses one registration file. `grpc.port`, `grpc.token` and a name are required.
    public static func parse(fileName: String, contents: String) throws(DiscoveryError) -> RunningEmulator {
        guard let pid = pid(fromFileName: fileName) else { throw .notARegistrationFile(fileName) }
        let values = IniParser.parse(contents)

        guard let portText = values["grpc.port"] else { throw .missingKey("grpc.port") }
        guard let port = Int(portText), (1...Int(UInt16.max)).contains(port) else {
            throw .invalidValue(key: "grpc.port")
        }
        guard let token = values["grpc.token"] else { throw .missingKey("grpc.token") }
        guard !token.isEmpty else { throw .invalidValue(key: "grpc.token") }
        guard let name = values["avd.name"] ?? values["avd.id"], !name.isEmpty else {
            throw .missingKey("avd.name")
        }

        return RunningEmulator(
            pid: pid,
            grpcPort: port,
            token: GRPCToken(token),
            avdName: name,
            avdDirectory: values["avd.dir"].map { URL(filePath: $0, directoryHint: .isDirectory) },
            emulatorVersion: values["emulator.version"],
            consolePort: values["port.serial"].flatMap { Int($0) }
        )
    }

    /// True when a process with this PID exists (signal 0 probes without sending anything).
    public static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}

/// The emulator's `key=value` format: one pair per line, no sections, no quoting rules
/// beyond keeping the value verbatim. Used for registration files and AVD `config.ini`.
enum IniParser {
    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else {
                continue
            }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            values[key] = value
        }
        return values
    }
}
