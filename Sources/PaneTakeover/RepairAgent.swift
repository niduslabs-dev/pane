import Foundation

/// The launch agent that repairs the wrapper when Pane isn't running: launchd starts
/// `Pane Emulator --repair <sdk> --bundle-id <id>` whenever `<sdk>/emulator` changes (an emulator
/// update replaces it), and the helper runs `TakeoverRepair.wrap` and exits.
///
/// It is a plist in `~/Library/LaunchAgents` with the SDK's real path, not an `SMAppService`
/// agent: a bundled plist is fixed at build time, and the SDK can be anywhere. `WatchPaths`
/// keeps firing after the folder is replaced, but must name the real folder, not a symlink.
public enum RepairAgent {
    public static let repairFlag = "--repair"
    public static let bundleIDFlag = "--bundle-id"

    /// One agent per Pane bundle ID, so a check copy's agent is never the release copy's.
    public static func label(bundleID: String) -> String { "\(bundleID).takeover-repair" }

    public static func plistURL(bundleID: String, agentsFolder: URL) -> URL {
        agentsFolder.appending(path: "\(label(bundleID: bundleID)).plist")
    }

    /// The agent's plist. `AssociatedBundleIdentifiers` makes macOS name Pane in its
    /// Background Items Added notice and in Login Items & Extensions.
    public static func plist(bundleID: String, helperExecutable: URL, sdk: URL, log: URL) throws -> Data {
        let sdkPath = sdk.standardizedFileURL.path(percentEncoded: false)
        let trimmed = sdkPath.count > 1 && sdkPath.hasSuffix("/") ? String(sdkPath.dropLast()) : sdkPath
        let dictionary: [String: Any] = [
            "Label": label(bundleID: bundleID),
            "ProgramArguments": [
                helperExecutable.path(percentEncoded: false), repairFlag, trimmed, bundleIDFlag, bundleID,
            ],
            "WatchPaths": [trimmed + "/emulator"],
            "AssociatedBundleIdentifiers": [bundleID],
            "ProcessType": "Background",
            "StandardOutPath": log.path(percentEncoded: false),
            "StandardErrorPath": log.path(percentEncoded: false),
        ]
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    /// `--repair <sdk> --bundle-id <id>` from a helper's arguments (without the program name).
    public static func parse(_ arguments: [String]) -> (sdk: URL, bundleID: String)? {
        guard arguments.count == 4, arguments[0] == repairFlag, arguments[2] == bundleIDFlag,
            arguments[1].hasPrefix("/"), !arguments[3].isEmpty,
            arguments[3].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return (URL(filePath: arguments[1], directoryHint: .isDirectory), arguments[3])
    }

    /// The repair's timings: 2 s of quiet (measured: the installer writes `package.xml` about
    /// 35 ms after the swap and nothing after), and up to 10 minutes for a slow download.
    public static func agentOptions(lockFile: URL) -> TakeoverRepair.Options {
        TakeoverRepair.Options(
            quiet: .seconds(2), timeout: .seconds(600), pollInterval: .milliseconds(500),  // design-ok: engine timing
            lockFile: lockFile, waitsForLock: false)
    }
}
