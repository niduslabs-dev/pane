import Foundation

/// "Show All Emulators in Pane": every emulator launch, from any tool, runs headless and shows
/// in Pane. `scripts/emulator-takeover.sh` (bundled in the app) does the work: a shadow Android
/// SDK whose `emulator` launcher is a wrapper, and a marked block in the shell configs pointing
/// `ANDROID_HOME` at it. This type reads its state and runs the script.
public enum EmulatorTakeover {
    public static let beginMark = "# >>> pane emulator takeover >>>"

    /// The shadow SDK, next to the real one (no spaces: the NDK's tools break on them).
    public static func shadowSDK(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Android/pane-sdk", directoryHint: .isDirectory)
    }

    /// The shell configs the script edits (see the script for why these).
    public static func shellConfigs(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [".config/fish/config.fish", ".zprofile", ".zshrc"].map { home.appending(path: $0) }
    }

    /// On when the shadow SDK is Pane's and every shell config has the block.
    public static func isInstalled(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let shadow = shadowSDK(home: home)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: shadow.appending(path: ".pane-takeover").path),
            fileManager.isExecutableFile(atPath: shadow.appending(path: "emulator/emulator").path)
        else { return false }
        return shellConfigs(home: home).allSatisfy { url in
            (try? String(contentsOf: url, encoding: .utf8))?.contains(beginMark) ?? false
        }
    }

    public enum Action: String, Sendable {
        case install
        case uninstall
    }

    public struct Failure: Error, CustomStringConvertible {
        public var status: Int32
        public var output: String
        public var description: String { "emulator-takeover.sh exited \(status): \(output)" }
    }

    /// Runs the script with `/bin/sh` through `Process` (arguments passed as they are, never
    /// through a shell command line) and returns its output.
    public static func run(_ action: Action, script: URL, app: URL) async throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments =
            [script.path, action.rawValue] + (action == .install ? ["--app", app.path] : [])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard status == 0 else { throw Failure(status: status, output: output) }
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
