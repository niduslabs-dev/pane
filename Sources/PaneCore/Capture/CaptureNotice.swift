import Foundation

/// The notice pill's words after a capture: where a screenshot or recording went, or that it
/// didn't work (board 18, "Screenshot feedback", and board 19, "Record transition").
///
/// A folder name can be long, so the pill truncates only the name, in the middle, and keeps
/// "Saved to" and the full stop: `lead`, then `name`, then `trail`.
public struct CaptureNotice: Equatable, Sendable {
    public var lead: String
    /// The part that may be truncated in the middle; empty when there is none.
    public var name: String
    public var trail: String

    public init(_ text: String) {
        lead = text
        name = ""
        trail = ""
    }

    public init(lead: String, name: String, trail: String) {
        self.lead = lead
        self.name = name
        self.trail = trail
    }

    /// The whole line, as VoiceOver reads it and logs show it.
    public var text: String { lead + name + trail }

    public static let copied = CaptureNotice("Copied.")
    public static let screenshotFailed = CaptureNotice("The screenshot didn't work.")
    public static let recordingFailed = CaptureNotice("Couldn't save the recording.")

    /// "Saved to Desktop." or "Saved to <folder>.".
    public static func saved(to folder: URL) -> CaptureNotice {
        CaptureNotice(lead: "Saved to ", name: folderName(folder), trail: ".")
    }

    /// "Recording saved to Desktop." or "Recording saved to <folder>.".
    public static func recordingSaved(to folder: URL) -> CaptureNotice {
        CaptureNotice(lead: "Recording saved to ", name: folderName(folder), trail: ".")
    }

    /// What a finished screenshot says: nil for Preview, which comes forward with the image
    /// and needs no pill.
    public static func screenshot(_ outcome: CaptureOutcome, folder: URL) -> CaptureNotice? {
        switch outcome {
        case .file: saved(to: folder)
        case .clipboard: copied
        case .preview: nil
        }
    }

    /// The folder as Finder names it: "Desktop" for the Desktop, else its last component.
    static func folderName(_ folder: URL) -> String {
        let name = folder.standardizedFileURL.lastPathComponent
        return name.isEmpty || name == "/" ? folder.path(percentEncoded: false) : name
    }
}

/// One screenshot at a time: a press while one is in flight is ignored, so a second click
/// can't queue a second capture or restart the pill.
public struct CaptureGate: Equatable, Sendable {
    public private(set) var isBusy = false

    public init() {}

    /// True when the capture may start; it then holds the gate until `finish()`.
    public mutating func begin() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    public mutating func finish() {
        isBusy = false
    }
}
