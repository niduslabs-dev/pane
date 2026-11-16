import AppKit
import Observation
import PaneCore

/// Everything Pane remembers between launches, in one place, so the menus today and a Settings
/// window later bind to the same values. Stored in the app's defaults; per-emulator values are
/// keyed by AVD name.
@MainActor
@Observable
final class PaneSettings {
    static let shared = PaneSettings(defaults: .standard)

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        sharesClipboard = defaults.object(forKey: Key.shareClipboard) as? Bool ?? true
        includesDeviceFrame = defaults.bool(forKey: Key.includeDeviceFrame)
        selectedAVDName = defaults.string(forKey: Key.selectedAVD)
    }

    /// Share Clipboard: text moves both ways while the window is key. On unless turned off.
    var sharesClipboard: Bool {
        didSet { defaults.set(sharesClipboard, forKey: Key.shareClipboard) }
    }

    /// Include Device Frame: saved and copied screenshots are drawn inside Pane's frame, on a
    /// transparent background.
    var includesDeviceFrame: Bool {
        didSet { defaults.set(includesDeviceFrame, forKey: Key.includeDeviceFrame) }
    }

    /// The AVD the first window shows and Start launches.
    var selectedAVDName: String? {
        didSet { defaults.set(selectedAVDName, forKey: Key.selectedAVD) }
    }

    // MARK: Per emulator

    /// The Window menu size last chosen for an AVD; nil after a manual resize or the first time.
    func sizeMode(for avd: String) -> ScreenSizeMode? {
        defaults.string(forKey: Key.sizeMode + avd).flatMap(ScreenSizeMode.init(rawValue:))
    }

    func setSizeMode(_ mode: ScreenSizeMode?, for avd: String) {
        defaults.set(mode?.rawValue, forKey: Key.sizeMode + avd)
    }

    /// Where an AVD's window last was: its top left corner in screen coordinates.
    func windowTopLeft(for avd: String) -> CGPoint? {
        guard let values = defaults.array(forKey: Key.windowTopLeft + avd) as? [Double], values.count == 2 else {
            return nil
        }
        return CGPoint(x: values[0], y: values[1])
    }

    func setWindowTopLeft(_ point: CGPoint, for avd: String) {
        defaults.set([Double(point.x), Double(point.y)], forKey: Key.windowTopLeft + avd)
    }

    /// The links opened on an AVD lately, newest first.
    func recentLinks(for avd: String) -> RecentLinks {
        RecentLinks(defaults.stringArray(forKey: Key.recentLinks + avd) ?? [])
    }

    func addRecentLink(_ link: String, for avd: String) {
        var recent = recentLinks(for: avd)
        recent.add(link)
        defaults.set(recent.links, forKey: Key.recentLinks + avd)
    }

    /// The custom location set for an AVD (Location ▸ Custom…), or nil for None.
    func location(for avd: String) -> DeviceLocation? {
        guard let values = defaults.array(forKey: Key.location + avd) as? [Double], values.count == 2 else {
            return nil
        }
        return DeviceLocation(latitude: values[0], longitude: values[1])
    }

    func setLocation(_ location: DeviceLocation?, for avd: String) {
        defaults.set(location.map { [$0.latitude, $0.longitude] }, forKey: Key.location + avd)
    }

    /// The last recording Pane saved, offered first by Export Recording as GIF. Nil once the
    /// file is gone.
    var lastRecording: URL? {
        get {
            guard let path = defaults.string(forKey: Key.lastRecording),
                FileManager.default.fileExists(atPath: path)
            else { return nil }
            return URL(filePath: path)
        }
        set { defaults.set(newValue?.path(percentEncoded: false), forKey: Key.lastRecording) }
    }

    private enum Key {
        static let shareClipboard = "shareClipboard"
        static let includeDeviceFrame = "includeDeviceFrame"
        static let selectedAVD = "selectedAVD"
        static let sizeMode = "sizeMode."
        static let windowTopLeft = "windowTopLeft."
        static let recentLinks = "recentLinks."
        static let location = "location."
        static let lastRecording = "lastRecording"
    }
}
