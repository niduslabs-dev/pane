import Foundation

/// The emulator's gRPC bearer token, read from its discovery file.
///
/// Every textual form is redacted, so the token can't reach a log, a crash report or test
/// output by accident. Only `bearerHeaderValue` exposes it, for the `authorization` header.
public struct GRPCToken: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    /// The `authorization` metadata value the emulator expects.
    public var bearerHeaderValue: String { "Bearer \(value)" }

    public var isEmpty: Bool { value.isEmpty }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "GRPCToken(<redacted>)" }
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// One running emulator, as described by its `pid_<pid>.ini` registration file.
public struct RunningEmulator: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var grpcPort: Int
    public var token: GRPCToken
    /// The AVD's name (`avd.name`), shown as the window title.
    public var avdName: String
    /// The AVD folder (`avd.dir`), holding `config.ini` with the device profile.
    public var avdDirectory: URL?
    /// `emulator.version`, for example `37.2.13.0`.
    public var emulatorVersion: String?
    /// The console port (`port.serial`); `adb` names the emulator `emulator-<port>`.
    public var consolePort: Int?

    public var id: Int32 { pid }

    public init(
        pid: Int32, grpcPort: Int, token: GRPCToken, avdName: String, avdDirectory: URL? = nil,
        emulatorVersion: String? = nil, consolePort: Int? = nil
    ) {
        self.pid = pid
        self.grpcPort = grpcPort
        self.token = token
        self.avdName = avdName
        self.avdDirectory = avdDirectory
        self.emulatorVersion = emulatorVersion
        self.consolePort = consolePort
    }
}

/// Why a registration file couldn't be used.
public enum DiscoveryError: Error, Equatable, Sendable {
    case notARegistrationFile(String)
    case missingKey(String)
    case invalidValue(key: String)
}
