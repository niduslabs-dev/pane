import Foundation

/// What to do with files dropped on the device: an `.apk` is installed, anything else is copied
/// to the device's Download folder (and photos and videos are shown to the gallery).
public struct DropPlan: Sendable, Equatable {
    public enum Step: Sendable, Equatable {
        case install(URL)
        /// `isMedia`: scan it into the media store afterwards, so the gallery shows it.
        case copy(URL, isMedia: Bool)

        public var file: URL {
            switch self {
            case .install(let url), .copy(let url, _): url
            }
        }
    }

    /// The steps in drop order, apps first so a failed install is seen before long copies.
    public var steps: [Step]

    public static let downloadFolder = "/sdcard/Download"

    /// Folders are left out: `adb push` would copy a whole tree, which a drop shouldn't do by
    /// surprise.
    public init(files: [URL], isDirectory: (URL) -> Bool = DropPlan.isDirectory) {
        let usable = files.filter { $0.isFileURL && !isDirectory($0) }
        let apps = usable.filter(Self.isApp).map(Step.install)
        let others = usable.filter { !Self.isApp($0) }.map { Step.copy($0, isMedia: Self.isMedia($0)) }
        steps = apps + others
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// The label under the pointer while dragging over the window.
    public var hoverLabel: String {
        let installs = steps.contains { if case .install = $0 { true } else { false } }
        let copies = steps.contains { if case .copy = $0 { true } else { false } }
        if installs && copies { return "Install and copy to device" }
        return installs ? "Install app" : "Copy to device"
    }

    /// The status line while a step runs: "Installing Splito…", "Copying photo.jpg…".
    public static func progressText(for step: Step) -> String {
        switch step {
        case .install(let url): "Installing \(url.deletingPathExtension().lastPathComponent)…"
        case .copy(let url, _): "Copying \(url.lastPathComponent)…"
        }
    }

    /// The status line once every step worked.
    public var doneText: String {
        let installs = steps.count { if case .install = $0 { true } else { false } }
        let copies = steps.count - installs
        if installs > 0 && copies > 0 { return "Installed and copied." }
        if installs > 0 { return installs == 1 ? "Installed." : "Installed \(installs) apps." }
        return copies == 1 ? "Copied to Downloads." : "Copied \(copies) files to Downloads."
    }

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
}
