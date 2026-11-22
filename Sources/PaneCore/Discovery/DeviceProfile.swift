import CoreGraphics
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
    /// Phone, tablet or foldable, from the config's keys (board 28): the switcher's glyph and
    /// where the frame's buttons go.
    public var kind: DeviceKind
    /// The hinge, for a foldable only: its postures and when the screen folds.
    public var fold: FoldProfile?

    public init(
        modelName: String? = nil, androidVersion: String? = nil, screenSize: PixelSize? = nil, density: Int? = nil,
        kind: DeviceKind = .phone, fold: FoldProfile? = nil
    ) {
        self.modelName = modelName
        self.androidVersion = androidVersion
        self.screenSize = screenSize
        self.density = density
        self.kind = kind
        self.fold = fold
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
        let density = values["hw.lcd.density"].flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        let fold = FoldProfile(config: values)
        let kind: DeviceKind
        if fold != nil {
            kind = .foldable
        } else if isTablet(tag: values["tag.id"], screenSize: size, density: density) {
            kind = .tablet
        } else {
            kind = .phone
        }
        return DeviceProfile(
            modelName: values["hw.device.name"].map(readableModelName),
            androidVersion: values["image.sysdir.1"].flatMap(apiLevel(fromSystemImagePath:)).map(androidRelease),
            screenSize: size, density: density, kind: kind, fold: fold
        )
    }

    /// System images for phones and tablets (`tag.id`). Automotive, Desktop, TV and Wear
    /// images stay phones whatever their screen.
    static let handheldTags: Set<String> = [
        "default", "google_apis", "google_apis_playstore", "google_atd", "aosp_atd",
    ]
    /// A screen whose short side is at least this many dp is a tablet's (Android's `sw600dp`).
    static let tabletShortSideDp: CGFloat = 600  // design-ok: Android's sw600dp, not a drawn size

    /// Pane's tablet rule (board 28): a phone or tablet image whose short side is 600 dp or more.
    static func isTablet(tag: String?, screenSize: PixelSize?, density: Int?) -> Bool {
        guard let tag, handheldTags.contains(tag), let screenSize, let density else { return false }
        let shortSide = CGFloat(min(screenSize.width, screenSize.height))
        return shortSide * ScreenSizing.baselineDensity / CGFloat(density) >= tabletShortSideDp
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
}

/// A foldable posture, by the number the emulator and `hw.sensor.posture_list` use.
public enum DevicePosture: Int, Sendable, Equatable, CaseIterable {
    case closed = 1
    case halfOpen = 2
    case open = 3
    case flipped = 4
    case tent = 5

    /// Sentence case, as More writes its rows.
    public var title: String {
        switch self {
        case .closed: "Closed"
        case .halfOpen: "Half-open"
        case .open: "Open"
        case .flipped: "Flipped"
        case .tent: "Tent"
        }
    }

    /// Title Case, as the menu bar writes its items.
    public var menuBarTitle: String {
        self == .halfOpen ? "Half-Open" : title
    }
}

/// A foldable's hinge as its `config.ini` describes it. Only devices Pane treats as foldables
/// have one: `hw.sensor.hinge = yes`, a hinge count above 0, a posture list that matches its
/// angle definitions (Android Studio's rule) and no `hw.resizable.configs` (the Resizable AVD).
public struct FoldProfile: Sendable, Equatable {
    /// The postures this device has, in the AVD's order.
    public var postures: [DevicePosture]
    /// The posture at which the screen switches to the outer one: Closed on a book fold,
    /// Flipped on a fold-out device.
    public var foldPosture: DevicePosture
    /// The outer screen in device pixels (`hw.displayRegion.0.1`), when the AVD gives one.
    public var outerScreenSize: PixelSize?
    /// `hw.sensor.hinge.type`: 0 splits top and bottom (a flip phone), 1 left and right (a book
    /// fold), 2 and 3 roll.
    public var hingeType: Int

    public init(
        postures: [DevicePosture], foldPosture: DevicePosture, outerScreenSize: PixelSize? = nil, hingeType: Int = 1
    ) {
        self.postures = postures
        self.foldPosture = foldPosture
        self.outerScreenSize = outerScreenSize
        self.hingeType = hingeType
    }

    /// Nil unless the keys describe a foldable.
    init?(config values: [String: String]) {
        guard values["hw.sensor.hinge"] == "yes", let count = values["hw.sensor.hinge.count"].flatMap(Int.init),
            count > 0, values["hw.resizable.configs"] == nil,
            let list = values["hw.sensor.posture_list"].map(Self.listItems), !list.isEmpty,
            let definitions = values["hw.sensor.hinge_angles_posture_definitions"].map(Self.listItems),
            definitions.count == list.count
        else { return nil }
        let postures = list.compactMap { Int($0).flatMap(DevicePosture.init(rawValue:)) }
        guard postures.count == list.count else { return nil }
        let foldAt = values["hw.sensor.hinge.fold_to_displayRegion.0.1_at_posture"].flatMap(Int.init)
            .flatMap(DevicePosture.init(rawValue:))
        var outer: PixelSize?
        if let width = values["hw.displayRegion.0.1.width"].flatMap(Int.init),
            let height = values["hw.displayRegion.0.1.height"].flatMap(Int.init), width > 0, height > 0
        {
            outer = PixelSize(width: width, height: height)
        }
        self.init(
            postures: postures, foldPosture: foldAt ?? .closed, outerScreenSize: outer,
            hingeType: values["hw.sensor.hinge.type"].flatMap(Int.init) ?? 1)
    }

    /// `1, 2, 3` or `0-30, 30-150` → the trimmed, non-empty items.
    private static func listItems(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The menu's Fold item: "Unfold" at the fold posture, "Fold" otherwise, including half open
    /// and before the first posture notification (`current` nil).
    public func foldTitle(current: DevicePosture?) -> String {
        current == foldPosture ? "Unfold" : "Fold"
    }

    /// Where the Fold item goes: Open from the fold posture, the fold posture from anywhere else.
    public func toggled(from current: DevicePosture?) -> DevicePosture {
        current == foldPosture ? .open : foldPosture
    }

    /// The pill's words when the emulator refuses a posture.
    public static let refusal = "Couldn't change the posture."
}
