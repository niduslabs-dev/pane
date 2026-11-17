import Foundation

/// The version of a package already on the device, from `adb shell dumpsys package <name>`.
public struct InstalledPackage: Sendable, Equatable {
    public var versionCode: Int64
    public var versionName: String

    public init(versionCode: Int64, versionName: String) {
        self.versionCode = versionCode
        self.versionName = versionName
    }

    /// The arguments that ask the device about one package.
    public static func lookupArguments(packageName: String) -> [String] {
        ["shell", "dumpsys", "package", Adb.deviceShellQuoted(packageName)]
    }

    /// Reads `dumpsys package <name>`. Nil when the package isn't installed (dumpsys then
    /// prints no `versionCode=` line, or "Unable to find package"). The first block is the
    /// installed one; an updated system app lists its factory copy after it.
    public static func parse(_ output: String) -> InstalledPackage? {
        var code: Int64?
        var name: String?
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if code == nil, line.hasPrefix("versionCode=") {
                let digits = line.dropFirst("versionCode=".count).prefix { $0.isNumber }
                code = Int64(digits)
            } else if name == nil, line.hasPrefix("versionName=") {
                name = String(line.dropFirst("versionName=".count))
            }
            if code != nil, name != nil { break }
        }
        guard let code else { return nil }
        return InstalledPackage(versionCode: code, versionName: name ?? "")
    }
}

/// What installing an `.apk` does to the copy on the device. Android compares `versionCode`;
/// the names are only for people.
public enum VersionChange: Sendable, Equatable {
    /// Not on the device yet.
    case new
    /// Replaces an older copy (its version name).
    case update(from: String)
    /// The same version again.
    case reinstall
    /// Older than the copy on the device (its version name): Android refuses unless asked, and
    /// the app's saved data may not read back.
    case older(than: String)

    public init(installing apk: ApkBadging, over installed: InstalledPackage?) {
        guard let installed else {
            self = .new
            return
        }
        let name = Self.name(installed.versionName, code: installed.versionCode)
        if apk.versionCode > installed.versionCode {
            self = .update(from: name)
        } else if apk.versionCode < installed.versionCode {
            self = .older(than: name)
        } else {
            self = .reinstall
        }
    }

    public var isDowngrade: Bool {
        if case .older = self { true } else { false }
    }

    /// A version for people: the name, else the code.
    public static func name(_ versionName: String, code: Int64) -> String {
        versionName.isEmpty ? String(code) : versionName
    }
}
