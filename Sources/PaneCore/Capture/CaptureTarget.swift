import Foundation

/// macOS's Save to for its own screenshots and recordings: the `target` keys in
/// `com.apple.screencapture`, read only, never written.
///
/// Newer macOS keeps separate `target-screenshot` and `target-screenrecording` keys beside the
/// older `target`, which older systems have alone. A missing or unknown value counts as unset.
public struct SystemCaptureTargets: Equatable, Sendable {
    public var target: String?
    public var screenshot: String?
    public var screenRecording: String?

    public init(target: String? = nil, screenshot: String? = nil, screenRecording: String? = nil) {
        self.target = target
        self.screenshot = screenshot
        self.screenRecording = screenRecording
    }

    /// The three keys as macOS has them now.
    public static func current() -> SystemCaptureTargets {
        func read(_ key: String) -> String? {
            CFPreferencesCopyAppValue(key as CFString, CaptureLocation.domain as CFString) as? String
        }
        return SystemCaptureTargets(
            target: read("target"), screenshot: read("target-screenshot"),
            screenRecording: read("target-screenrecording"))
    }
}

/// What a capture asked for: the toolbar's Screenshot button follows macOS's target, Save
/// Screenshot (⌘S) always writes a file, Copy Screenshot (⇧⌘C) always copies.
public enum CaptureAction: Sendable {
    case screenshotButton
    case saveScreenshot
    case copyScreenshot
    case recording
}

/// Where a capture ends up. A file goes to `CaptureLocation`'s folder.
public enum CaptureOutcome: Equatable, Sendable {
    case file
    case clipboard
    /// A temporary PNG opened in Preview.
    case preview

    /// Which outcome a capture gets.
    ///
    /// Only Save to's "Same as macOS screenshots" follows macOS's target: the Desktop or a chosen
    /// folder always means a file there. Screenshots follow `target-screenshot`, else `target`;
    /// recordings `target-screenrecording`, else `target`. `mail` and `messages` aren't supported
    /// yet and save a file, and a recording always does, since a movie can't go to the clipboard.
    public static func resolve(
        _ action: CaptureAction, destination: CaptureDestination, targets: SystemCaptureTargets
    ) -> CaptureOutcome {
        switch action {
        case .copyScreenshot: return .clipboard
        case .saveScreenshot, .recording: return .file
        case .screenshotButton:
            guard destination == .system else { return .file }
            let value = Target.parse(targets.screenshot) ?? Target.parse(targets.target) ?? .file
            switch value {
            case .clipboard: return .clipboard
            case .preview: return .preview
            case .file, .mail, .messages: return .file
            }
        }
    }

    /// macOS's target values.
    private enum Target: String {
        case file, clipboard, preview, mail, messages

        static func parse(_ value: String?) -> Target? {
            value.flatMap { Target(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
        }
    }
}
