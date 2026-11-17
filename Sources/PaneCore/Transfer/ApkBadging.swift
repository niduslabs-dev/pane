import Foundation

/// What `aapt2 dump badging` says about an `.apk`: its package, version, label, icon and launcher
/// activity. Read while the file is dragged over the window, so the drag card can name the app.
public struct ApkBadging: Sendable, Equatable {
    public var packageName: String
    /// Android compares versions by this number, never by the name.
    public var versionCode: Int64
    /// What people read ("1.4.0"); may be empty.
    public var versionName: String
    /// The app's name; nil when the manifest has none.
    public var label: String?
    /// The icon's path inside the `.apk` at the highest density listed; nil when there is none.
    public var iconPath: String?
    /// The launcher activity's class name, for Open; nil for apps with no launcher entry.
    public var launchableActivity: String?

    public init(
        packageName: String, versionCode: Int64, versionName: String, label: String? = nil, iconPath: String? = nil,
        launchableActivity: String? = nil
    ) {
        self.packageName = packageName
        self.versionCode = versionCode
        self.versionName = versionName
        self.label = label
        self.iconPath = iconPath
        self.launchableActivity = launchableActivity
    }

    /// The icon is a bitmap Pane can draw. Adaptive and vector icons (`.xml`) are compiled XML,
    /// so the card shows the generic app tile for them.
    public var hasDrawableIcon: Bool {
        guard let iconPath else { return false }
        return ["png", "webp", "jpg", "jpeg"].contains((iconPath as NSString).pathExtension.lowercased())
    }

    /// Reads `aapt2 dump badging` output. Nil without a `package:` line with a name.
    public static func parse(_ output: String) -> ApkBadging? {
        var package: String?
        var code: Int64 = 0
        var name = ""
        var label: String?
        var applicationLabel: String?
        var icons: [(density: Int, path: String)] = []
        var applicationIcon: String?
        var activity: String?
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line.hasPrefix("package:") {
                package = value(of: "name", in: line)
                code = value(of: "versionCode", in: line).flatMap { Int64($0) } ?? 0
                name = value(of: "versionName", in: line) ?? ""
            } else if line.hasPrefix("application-label:") {
                label = quoted(after: "application-label:", in: line)
            } else if line.hasPrefix("application-icon-") {
                let density = line.dropFirst("application-icon-".count).prefix { $0.isNumber }
                if let density = Int(density), let path = quoted(after: "application-icon-\(density):", in: line) {
                    icons.append((density, path))
                }
            } else if line.hasPrefix("application:") {
                applicationLabel = value(of: "label", in: line)
                applicationIcon = value(of: "icon", in: line)
            } else if line.hasPrefix("launchable-activity:"), activity == nil {
                activity = value(of: "name", in: line)
            }
        }
        guard let package, !package.isEmpty else { return nil }
        // The highest density listed (65534 is aapt's "any density" entry, the same file or larger).
        let icon = icons.max { $0.density < $1.density }?.path ?? applicationIcon
        return ApkBadging(
            packageName: package, versionCode: code, versionName: name,
            label: (label ?? applicationLabel).flatMap { $0.isEmpty ? nil : $0 },
            iconPath: icon.flatMap { $0.isEmpty ? nil : $0 },
            launchableActivity: activity.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// `key='value'` inside one badging line.
    static func value(of key: String, in line: String) -> String? {
        guard let start = line.range(of: " \(key)='") ?? line.range(of: ":\(key)='") else { return nil }
        let rest = line[start.upperBound...]
        guard let end = rest.firstIndex(of: "'") else { return nil }
        return String(rest[..<end])
    }

    private static func quoted(after prefix: String, in line: String) -> String? {
        let rest = line.dropFirst(prefix.count)
        guard rest.first == "'", rest.count >= 2 else { return nil }
        let body = rest.dropFirst()
        guard let end = body.lastIndex(of: "'") else { return nil }
        return String(body[..<end])
    }
}

extension AndroidSDK {
    /// `aapt2` from the real SDK's newest build-tools (by version, not by name order), or nil
    /// when no build-tools folder has one.
    public static func aapt2Executable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        listFolder: (URL) -> [String] = { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? [] },
        isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) -> URL? {
        guard
            let emulator = emulatorExecutable(environment: environment, home: home, isExecutable: isExecutable)
        else { return nil }
        let buildTools = emulator.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "build-tools", directoryHint: .isDirectory)
        return
            listFolder(buildTools)
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { buildTools.appending(path: "\($0)/aapt2") }
            .first(where: isExecutable)
    }
}
