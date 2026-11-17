import Foundation

/// What the AVD's `config.ini` says about the device: its model, Android version and screen.
public struct DeviceProfile: Sendable, Equatable {
    /// A readable model name from `hw.device.name` (`pixel_8` becomes `Pixel 8`).
    public var modelName: String?
    /// The Android release for the system image's API level, for example `Android 16`.
    public var androidVersion: String?
    /// The screen in device pixels (`hw.lcd.width` × `hw.lcd.height`), portrait.
    public var screenSize: PixelSize?
    /// The screen's density in dpi (`hw.lcd.density`), for Point Accurate and Physical Size.
    public var density: Int?
    /// Phone, tablet or foldable, from `hw.device.name` (the switcher's row glyph).
    public var kind: DeviceKind

    public init(
        modelName: String? = nil, androidVersion: String? = nil, screenSize: PixelSize? = nil, density: Int? = nil,
        kind: DeviceKind = .phone
    ) {
        self.modelName = modelName
        self.androidVersion = androidVersion
        self.screenSize = screenSize
        self.density = density
        self.kind = kind
    }

    /// The window's second title line: model and Android version, joined by a middle dot.
    public var summary: String {
        [modelName, androidVersion].compactMap { $0 }.joined(separator: " · ")
    }

    /// Reads `config.ini` from an AVD folder; a missing or unreadable file gives an empty profile.
    public static func load(avdDirectory: URL) -> DeviceProfile {
        guard let text = try? String(contentsOf: avdDirectory.appending(path: "config.ini"), encoding: .utf8) else {
            return DeviceProfile()
        }
        return parse(configIni: text)
    }

    public static func parse(configIni text: String) -> DeviceProfile {
        let values = IniParser.parse(text)
        var size: PixelSize?
        if let width = values["hw.lcd.width"].flatMap(Int.init), let height = values["hw.lcd.height"].flatMap(Int.init),
            width > 0, height > 0
        {
            size = PixelSize(width: width, height: height)
        }
        return DeviceProfile(
            modelName: values["hw.device.name"].map(readableModelName),
            androidVersion: values["image.sysdir.1"].flatMap(apiLevel(fromSystemImagePath:)).map(androidRelease),
            screenSize: size,
            density: values["hw.lcd.density"].flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil },
            kind: values["hw.device.name"].map(DeviceKind.init(deviceName:)) ?? .phone
        )
    }

    /// `pixel_8_pro` → `Pixel 8 Pro`.
    static func readableModelName(_ id: String) -> String {
        id.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The API level in a path like `system-images/android-36.1/google_apis/arm64-v8a/`.
    static func apiLevel(fromSystemImagePath path: String) -> Int? {
        for component in path.split(separator: "/") where component.hasPrefix("android-") {
            let level = component.dropFirst("android-".count).prefix { $0.isNumber }
            if let value = Int(level) { return value }
        }
        return nil
    }

    /// The marketing release for an API level; unknown levels read `API <n>`.
    static func androidRelease(apiLevel: Int) -> String {
        let releases = [36: "16", 35: "15", 34: "14", 33: "13", 32: "12L", 31: "12", 30: "11", 29: "10"]
        return releases[apiLevel].map { "Android \($0)" } ?? "API \(apiLevel)"
    }
}

/// The shape of device an AVD stands for, as the emulator switcher draws it (board 20).
public enum DeviceKind: String, Sendable, Equatable, CaseIterable {
    case phone
    case tablet
    case foldable

    /// From an AVD's `hw.device.name`: a name with "tablet" is a tablet, one with "fold" a
    /// foldable (`pixel_9_pro_fold`), anything else a phone.
    public init(deviceName: String) {
        let name = deviceName.lowercased()
        if name.contains("tablet") {
            self = .tablet
        } else if name.contains("fold") {
            self = .foldable
        } else {
            self = .phone
        }
    }
}
