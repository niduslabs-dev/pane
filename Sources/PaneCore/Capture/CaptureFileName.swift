import Foundation

/// File names for screenshots and recordings, in the style macOS uses for its own
/// ("Screenshot 2026-11-17 at 00.46.20.png"), never overwriting an existing file.
public enum CaptureFileName {
    public static func name(prefix: String, date: Date, fileExtension: String, timeZone: TimeZone = .current) -> String
    {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).\(fileExtension)"
    }

    /// A URL in `folder` that doesn't exist yet: the plain name, then "… (2)", "… (3)".
    public static func unusedURL(
        in folder: URL, prefix: String, date: Date, fileExtension: String, timeZone: TimeZone = .current,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let base = name(prefix: prefix, date: date, fileExtension: fileExtension, timeZone: timeZone)
        var url = folder.appending(path: base)
        var copy = 2
        while exists(url) {
            let stem = String(base.dropLast(fileExtension.count + 1))
            url = folder.appending(path: "\(stem) (\(copy)).\(fileExtension)")
            copy += 1
        }
        return url
    }
}
