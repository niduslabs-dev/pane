import Foundation

/// One item being dragged over the window, with whatever has been read about it so far.
public struct DraggedItem: Sendable, Equatable {
    public var url: URL
    public var isDirectory: Bool
    /// The file's size in bytes; nil when unknown (a file promise not on disk yet).
    public var size: Int64?
    /// What aapt read from an `.apk`; nil before it answers or when it can't.
    public var badging: ApkBadging?
    /// What installing it would do to the device's copy; nil until the device answers.
    public var change: VersionChange?

    public init(
        url: URL, isDirectory: Bool = false, size: Int64? = nil, badging: ApkBadging? = nil,
        change: VersionChange? = nil
    ) {
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.badging = badging
        self.change = change
    }

    public var isApp: Bool { !isDirectory && DropPlan.isApp(url) }
    public var isUsable: Bool { url.isFileURL && !isDirectory }
}

/// The card on the device screen while files are dragged over the window (the canvas's
/// "Option A · Drag card, refined", variant 1): a header with the emulator and the file, the
/// app's icon, "Name version" as the title, and a chip that says what letting go does. The
/// first frame comes from the file alone; aapt and the device fill in the rest.
public struct DragCard: Sendable, Equatable {
    public enum Media: Sendable, Equatable {
        /// The icon inside this `.apk`, at this path in the archive.
        case appIcon(apk: URL, path: String)
        case glyph(Glyph)
        /// Several items: the card draws two kinds of tile, overlapped.
        case stack(apps: Int, files: Int)
    }

    public enum Glyph: Sendable, Equatable {
        case app, photo, file, folder, refused
    }

    public enum Tone: Sendable, Equatable {
        case neutral
        /// An older build than the device's. Colour carries risk only.
        case warning
    }

    /// Bold in the header: the emulator's name, or "Pane" when there is none.
    public var source: String
    /// The rest of the header: "splito-1.4.0.apk · 61 MB", "3 items".
    public var header: String
    public var media: Media
    public var title: String
    /// Drawn in secondary after the title ("1.4.0"); nil when there is none.
    public var version: String?
    public var chip: String
    public var tone: Tone
    /// The drop is refused: no dim, no outline, the not-allowed pointer, and the card sits at
    /// the top of the screen.
    public var isRefused: Bool

    /// What VoiceOver says when the card appears or changes: "Splito 1.4.0. Update from 1.3.2."
    public var announcement: String {
        let name = version.map { "\(title) \($0)" } ?? title
        return "\(name). \(chip)."
    }

    /// The card for `items` dragged over a window showing `emulator` (its AVD name), or over
    /// one with no live emulator (nil). Nil when the drag holds nothing to show.
    public init?(items: [DraggedItem], emulator: String?, sizeText: (Int64) -> String = DragCard.sizeText) {
        let fileItems = items.filter { $0.url.isFileURL }
        guard let first = fileItems.first else { return nil }
        let usable = fileItems.filter(\.isUsable)
        tone = .neutral
        version = nil
        guard let emulator else {
            source = "Pane"
            header = fileItems.count == 1 ? first.url.lastPathComponent : Self.itemCount(fileItems.count)
            media = .glyph(.refused)
            title = "No emulator running"
            chip = "Start an emulator first"
            isRefused = true
            return
        }
        source = emulator
        isRefused = false
        if usable.isEmpty {
            header = fileItems.count == 1 ? first.url.lastPathComponent : Self.itemCount(fileItems.count)
            media = .glyph(.folder)
            title = fileItems.count == 1 ? first.url.lastPathComponent : "\(fileItems.count) folders"
            chip = "No folders"
            isRefused = true
            return
        }
        if usable.count > 1 {
            let apps = usable.count(where: \.isApp)
            header = Self.itemCount(usable.count)
            media = .stack(apps: apps, files: usable.count - apps)
            title = Self.names(usable.map(Self.shortName))
            chip = Self.counts(apps: apps, files: usable.count - apps)
            return
        }
        let item = usable[0]
        let name = item.url.lastPathComponent
        header = item.size.map { "\(name) · \(sizeText($0))" } ?? name
        guard item.isApp else {
            media = .glyph(DropPlan.isMedia(item.url) ? .photo : .file)
            title = name
            version = item.size.map(sizeText)
            chip = "Copy to Downloads"
            return
        }
        guard let badging = item.badging else {
            media = .glyph(.app)
            title = name
            chip = "Install"
            return
        }
        media =
            badging.hasDrawableIcon ? .appIcon(apk: item.url, path: badging.iconPath ?? "") : .glyph(.app)
        title = badging.label ?? badging.packageName
        version = badging.versionName.isEmpty ? nil : badging.versionName
        switch item.change {
        case .none, .new: chip = "Install"
        case .update(let from): chip = "Update from \(from)"
        case .reinstall: chip = "Reinstall"
        case .older(let than):
            chip = "Older than \(than)"
            tone = .warning
        }
    }

    /// "3 items".
    static func itemCount(_ count: Int) -> String { count == 1 ? "1 item" : "\(count) items" }

    /// "2 apps, 1 file", "1 app", "3 files".
    static func counts(apps: Int, files: Int) -> String {
        let parts = [
            apps > 0 ? (apps == 1 ? "1 app" : "\(apps) apps") : nil,
            files > 0 ? (files == 1 ? "1 file" : "\(files) files") : nil,
        ]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    /// "Splito and IMG_2041.jpg", "Splito and 2 more": the first item by name, so a long list
    /// still fits on the title line.
    static func names(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        switch names.count {
        case 1: return first
        case 2: return "\(first) and \(names[1])"
        default: return "\(first) and \(names.count - 1) more"
        }
    }

    /// An app by its label once read, else the file's name.
    static func shortName(_ item: DraggedItem) -> String {
        item.badging?.label ?? item.url.lastPathComponent
    }

    /// "61 MB", as Finder writes sizes.
    public static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
