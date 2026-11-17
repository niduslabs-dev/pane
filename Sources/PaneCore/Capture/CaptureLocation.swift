import Foundation

/// Where screenshots and recordings go: wherever macOS saves its own screenshots.
///
/// macOS keeps that folder as `location` in the `com.apple.screencapture` domain (set from the
/// Screenshot app's Options). Pane follows it, and falls back to the Desktop when it is unset,
/// missing or not writable, as macOS itself does.
public enum CaptureLocation {
    /// macOS's screenshot preferences domain.
    public static let domain = "com.apple.screencapture"

    /// `location` from `com.apple.screencapture`, or nil when unset. Read only, never written.
    public static func configuredLocation() -> String? {
        CFPreferencesCopyAppValue("location" as CFString, domain as CFString) as? String
    }

    /// The folder for a configured `location` (a leading `~` is the home folder), or the Desktop.
    public static func folder(
        configured: String?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isWritableFolder: (URL) -> Bool = CaptureLocation.isWritableFolder
    ) -> URL {
        let desktop = home.appending(path: "Desktop", directoryHint: .isDirectory)
        guard let configured = configured?.trimmingCharacters(in: .whitespacesAndNewlines), !configured.isEmpty
        else { return desktop }
        let expanded: String
        if configured == "~" {
            expanded = home.path
        } else if configured.hasPrefix("~/") {
            expanded = home.path + "/" + configured.dropFirst(2)
        } else {
            expanded = configured
        }
        // A relative path means nothing to macOS either.
        guard expanded.hasPrefix("/") else { return desktop }
        let url = URL(filePath: expanded, directoryHint: .isDirectory)
        return isWritableFolder(url) ? url : desktop
    }

    /// The folder for the Save to setting. A chosen folder that is missing or not writable
    /// falls back to the Desktop, as macOS's own setting does.
    public static func folder(
        for destination: CaptureDestination, configured: String?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isWritableFolder: (URL) -> Bool = CaptureLocation.isWritableFolder
    ) -> URL {
        switch destination {
        case .system: folder(configured: configured, home: home, isWritableFolder: isWritableFolder)
        case .desktop: folder(configured: nil, home: home, isWritableFolder: isWritableFolder)
        case .folder(let path): folder(configured: path, home: home, isWritableFolder: isWritableFolder)
        }
    }

    public static func isWritableFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: url.path)
    }
}

/// Settings' Save to: where screenshots and recordings go.
public enum CaptureDestination: Equatable, Hashable, Sendable {
    /// Wherever macOS saves its own screenshots.
    case system
    case desktop
    /// A folder the user chose, as an absolute path.
    case folder(String)

    /// The two stored values: which kind, and the chosen folder's path. The path is kept when
    /// another kind is chosen, so the last folder can be offered again.
    public init(kind: String?, path: String?) {
        switch kind {
        case "desktop": self = .desktop
        case "folder": self = path.map(CaptureDestination.folder) ?? .system
        default: self = .system
        }
    }

    public var kind: String {
        switch self {
        case .system: "system"
        case .desktop: "desktop"
        case .folder: "folder"
        }
    }
}
