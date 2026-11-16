import Foundation

/// Where screenshots and recordings go: wherever macOS saves its own screenshots.
///
/// macOS keeps that folder as `location` in the `com.apple.screencapture` domain (set from the
/// Screenshot app's Options). Pane follows it, and falls back to the Desktop when it is unset,
/// missing or not writable, as macOS itself does.
public enum CaptureLocation {
    /// `location` from `com.apple.screencapture`, or nil when unset. Read only, never written.
    public static func configuredLocation() -> String? {
        CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
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

    public static func isWritableFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: url.path)
    }
}
