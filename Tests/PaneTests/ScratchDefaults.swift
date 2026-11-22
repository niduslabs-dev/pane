import Foundation

/// Throwaway `UserDefaults` suites for tests, kept out of `~/Library/Preferences`.
///
/// A suite named by a plain name lives in `~/Library/Preferences`, and its plist outlives
/// `removePersistentDomain(forName:)`, so every run used to leave a file per suite there
/// (about 400 by 2026-11-22). A suite named by an absolute path is stored at that path, so
/// these live in the user's temporary folder instead, which macOS clears on its own.
enum ScratchDefaults {
    /// The folder every test suite is written to.
    static let folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appending(path: "pane-tests", directoryHint: .isDirectory)

    /// A new, empty suite for `prefix`.
    static func make(_ prefix: String) -> UserDefaults { named(prefix).defaults }

    /// The same, with the suite's name for tests that empty it themselves.
    static func named(_ prefix: String) -> (defaults: UserDefaults, name: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = folder.appending(path: "\(prefix)-\(UUID().uuidString)").path
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("Couldn't open the test suite \(name).")
        }
        return (defaults, name)
    }
}
