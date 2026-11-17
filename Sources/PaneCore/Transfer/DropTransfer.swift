import Foundation

/// The adb calls behind a drop, as argument arrays for `Adb.run(_:timeout:)` (which adds
/// `-s <serial>`). An `.apk` is pushed to a temporary path first and then installed with
/// `pm install`, so the push gives a real progress bar; copies go straight to Downloads. Every
/// path that goes through `adb shell` is quoted for the device's shell.
public enum DropTransfer {
    /// Where an `.apk` waits on the device between the push and the install.
    public static func stagingPath(token: String) -> String { "/data/local/tmp/pane-drop-\(token).apk" }

    public static func pushArguments(_ file: URL, to devicePath: String) -> [String] {
        ["push", file.path(percentEncoded: false), devicePath]
    }

    /// The size of a file on the device so far, polled while it is pushed.
    public static func sizeArguments(devicePath: String) -> [String] {
        ["shell", "stat -c %s \(Adb.deviceShellQuoted(devicePath)) 2>/dev/null"]
    }

    /// `-r` replaces an installed copy, keeping its data; `-t` allows test-only builds (Android
    /// Studio's run builds); `-d` allows an older version, only once the downgrade was confirmed.
    public static func installArguments(devicePath: String, allowDowngrade: Bool) -> [String] {
        ["shell", "pm install -r -t\(allowDowngrade ? " -d" : "") \(Adb.deviceShellQuoted(devicePath))"]
    }

    public static func removeArguments(devicePath: String) -> [String] {
        ["shell", "rm -f \(Adb.deviceShellQuoted(devicePath))"]
    }

    /// Indexes a copied file in the media store, so the gallery shows it.
    public static func mediaScanArguments(devicePath: String) -> [String] {
        ["shell", "content call --uri content://media --method scan_file --arg \(Adb.deviceShellQuoted(devicePath))"]
    }

    /// `pm install` worked: it prints "Success" and nothing that starts with "Failure".
    public static func installSucceeded(status: Int32, output: String) -> Bool {
        status == 0 && output.contains("Success") && !output.contains("Failure")
    }

    /// Parses `stat -c %s`; nil before the file exists.
    public static func parseSize(_ output: String) -> Int64? {
        Int64(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// A drop that didn't work, in words anyone can read: a title naming the file, one sentence of
/// why and what to do next when Pane knows it, and adb's own code behind Details.
public struct DropFailure: Error, Sendable, Equatable {
    /// "Couldn't install Splito."
    public var title: String
    /// "The copy on the device was signed with a different key. Uninstall it there, then drop
    /// the file again." Nil when Pane has no words for adb's reason.
    public var body: String?
    /// adb's own line ("INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package … do not match"),
    /// shown behind Details; nil when adb gave none.
    public var code: String?

    public init(title: String, body: String? = nil, code: String? = nil) {
        self.title = title
        self.body = body
        self.code = code
    }

    /// The short reason a row in a several-file list shows: the body's first sentence, else
    /// "Failed".
    public var rowReason: String {
        guard let body, let end = body.firstIndex(of: ".") else { return body ?? "Didn't work." }
        return String(body[...end])
    }

    /// An install that failed, from what adb printed.
    public static func install(_ name: String, output: String) -> DropFailure {
        let reason = Adb.reason(from: output)
        let body: String? =
            if reason.hasPrefix("INSTALL_PARSE_FAILED") || reason.hasPrefix("INSTALL_FAILED_INVALID_APK") {
                "This file isn't an Android app, or it's damaged."
            } else {
                switch reason {
                case "INSTALL_FAILED_UPDATE_INCOMPATIBLE":
                    "The copy on the device was signed with a different key. Uninstall it there, then drop the file again."
                case "INSTALL_FAILED_VERSION_DOWNGRADE":
                    "The device has a newer version. Android won't go back to this one."
                case "INSTALL_FAILED_OLDER_SDK": "It needs a newer Android than this emulator's."
                case "INSTALL_FAILED_DEPRECATED_SDK_VERSION": "It's built for an Android too old for this emulator."
                case "INSTALL_FAILED_INSUFFICIENT_STORAGE": "The emulator is out of space."
                case "INSTALL_FAILED_NO_MATCHING_ABIS": "Not built for this emulator's processor."
                case "INSTALL_FAILED_DUPLICATE_PERMISSION", "INSTALL_FAILED_CONFLICTING_PROVIDER":
                    "Another app on the device already claims what this one needs."
                default: nil
                }
            }
        return DropFailure(title: "Couldn't install \(name).", body: body, code: Adb.detail(from: output))
    }

    /// A copy (or an `.apk`'s push) that failed, from what adb printed.
    public static func copy(_ name: String, output: String, isApp: Bool = false) -> DropFailure {
        let body: String? =
            output.localizedCaseInsensitiveContains("No space left") ? "The emulator is out of space." : nil
        return DropFailure(
            title: isApp ? "Couldn't install \(name)." : "Couldn't copy \(name).", body: body,
            code: Adb.detail(from: output))
    }

    /// adb itself didn't run or didn't answer.
    public static func adbDidNotRun(_ name: String, isApp: Bool, reason: String) -> DropFailure {
        DropFailure(
            title: isApp ? "Couldn't install \(name)." : "Couldn't copy \(name).",
            body: "adb didn't answer. Check that the emulator is still running.", code: reason.isEmpty ? nil : reason)
    }
}

/// What Open and Show start on the device after a drop.
public enum DeviceIntent: Sendable, Equatable {
    /// Open: the app's launcher activity. `activity` comes from aapt; without it, the device is
    /// asked which activity launches the package.
    case openApp(package: String, activity: String?)
    /// Show: the Files app at Downloads, where copies land.
    case showDownloads

    /// What a finished item offers: Open for an installed app with a package name, Show for a
    /// copied file, nothing otherwise.
    public static func after(_ item: DropJob.Item) -> DeviceIntent? {
        switch item.state {
        case .installed:
            guard let badging = item.badging else { return nil }
            return .openApp(package: badging.packageName, activity: badging.launchableActivity)
        case .copied: return .showDownloads
        default: return nil
        }
    }

    /// The `am start` call; nil for an app whose launcher activity must be asked for first
    /// (`resolveArguments`).
    public var arguments: [String]? {
        switch self {
        case .openApp(let package, let activity?):
            return Self.startArguments(component: "\(package)/\(activity)")
        case .openApp: return nil
        case .showDownloads: return ["shell", "am start -a android.intent.action.VIEW_DOWNLOADS"]
        }
    }

    /// Asks the device for a package's launcher activity (`cmd package resolve-activity`).
    public static func resolveArguments(package: String) -> [String] {
        [
            "shell",
            "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER \(Adb.deviceShellQuoted(package))",
        ]
    }

    /// The component on `resolve-activity --brief`'s last line ("pkg/.Main"), or nil when none
    /// resolves.
    public static func parseResolved(_ output: String) -> String? {
        let last = output.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let last, last.contains("/"), !last.contains(" ") else { return nil }
        return last
    }

    /// `am start -n` for a component `parseResolved` gave.
    public static func startArguments(component: String) -> [String] {
        ["shell", "am start -n \(Adb.deviceShellQuoted(component))"]
    }

    /// `am start` prints "Error: …" and still exits 0 when nothing could be started.
    public static func started(status: Int32, output: String) -> Bool {
        status == 0 && !output.contains("Error:")
    }
}
