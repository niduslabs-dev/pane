import Foundation

/// The device's light or dark theme (`cmd uimode night`).
public enum DeviceAppearance: String, Sendable, CaseIterable {
    case light
    case dark

    public var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var setArguments: [String] { ["shell", "cmd", "uimode", "night", self == .dark ? "yes" : "no"] }

    public static let getArguments = ["shell", "cmd", "uimode", "night"]

    /// Reads "Night mode: yes". Auto and custom schedules, or anything else, read as nil.
    public static func parse(_ output: String) -> DeviceAppearance? {
        guard let colon = output.lastIndex(of: ":") else { return nil }
        switch output[output.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines) {
        case "yes": return .dark
        case "no": return .light
        default: return nil
        }
    }
}

/// The device's text size (`settings put system font_scale`), at the steps Android's own
/// Settings offers.
public enum DeviceTextSize: String, Sendable, CaseIterable {
    case small
    case standard
    case large
    case largest

    public var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .largest: "Largest"
        }
    }

    public var scale: Double {
        switch self {
        case .small: 0.85
        case .standard: 1.0
        case .large: 1.15
        case .largest: 1.3
        }
    }

    public var setArguments: [String] {
        ["shell", "settings", "put", "system", "font_scale", String(format: "%.2f", scale)]
    }

    public static let getArguments = ["shell", "settings", "get", "system", "font_scale"]

    /// The step for what `settings get` printed; "null" (never set) is Default, and a scale
    /// that is none of the steps is nil.
    public static func parse(_ output: String) -> DeviceTextSize? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "null" || text.isEmpty { return .standard }
        guard let value = Double(text) else { return nil }
        let tolerance = 0.005
        return allCases.first { abs($0.scale - value) < tolerance }
    }
}

/// A place for the device's GPS, in degrees.
public struct DeviceLocation: Sendable, Equatable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public static let latitudeRange = -90.0...90.0
    public static let longitudeRange = -180.0...180.0

    /// What the emulator reports until a location is set: Google's campus.
    public static let emulatorDefault = DeviceLocation(latitude: 37.421998, longitude: -122.084)

    /// A location from the two typed fields, or nil when either isn't a number in range. A
    /// comma is taken as the decimal mark too.
    public init?(latitudeText: String, longitudeText: String) {
        func number(_ text: String) -> Double? {
            Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        guard let latitude = number(latitudeText), let longitude = number(longitudeText),
            Self.latitudeRange.contains(latitude), Self.longitudeRange.contains(longitude)
        else { return nil }
        self.init(latitude: latitude, longitude: longitude)
    }

    /// "12.9716, 77.5946", for the menu.
    public var summary: String { String(format: "%.4f, %.4f", latitude, longitude) }
}
