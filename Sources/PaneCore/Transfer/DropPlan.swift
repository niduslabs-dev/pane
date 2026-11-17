import Foundation

/// What a dropped file is: an `.apk` is installed, anything else is copied to the device's
/// Download folder (and photos and videos are shown to the gallery). Folders are left out:
/// `adb push` would copy a whole tree, which a drop shouldn't do by surprise.
public enum DropPlan {
    public static let downloadFolder = "/sdcard/Download"

    /// Where a copied file lands on the device.
    public static func devicePath(for file: URL) -> String {
        "\(downloadFolder)/\(file.lastPathComponent)"
    }

    static func isApp(_ url: URL) -> Bool { url.pathExtension.lowercased() == "apk" }

    static func isMedia(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

    private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "bmp", "avif", "dng",
        "mp4", "mov", "m4v", "webm", "mkv", "3gp",
    ]

    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// The file's size in bytes, or nil when it can't be read (a promise not on disk yet).
    public static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0.map(Int64.init) }
    }
}
