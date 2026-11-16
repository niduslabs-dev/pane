import Foundation

/// One Android Virtual Device on disk: `~/.android/avd/<name>.ini` pointing at its folder.
public struct AvdInfo: Sendable, Equatable, Identifiable {
    /// The AVD's name, which `emulator -avd` takes (the `.ini` file's base name).
    public var name: String
    public var directory: URL
    public var profile: DeviceProfile

    public var id: String { name }

    public init(name: String, directory: URL, profile: DeviceProfile = DeviceProfile()) {
        self.name = name
        self.directory = directory
        self.profile = profile
    }

    /// The no-emulator screen's second line: name, model and Android version.
    public var summary: String {
        ([name] + [profile.modelName, profile.androidVersion].compactMap { $0 }).joined(separator: " · ")
    }
}

/// Lists the AVDs the SDK's AVD Manager created, as the emulator itself finds them.
public enum AvdCatalog {
    /// `ANDROID_AVD_HOME`, else `~/.android/avd`. Apps opened from Finder get launchd's
    /// environment, so the home fallback is the usual path.
    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let custom = environment["ANDROID_AVD_HOME"], !custom.isEmpty {
            return URL(filePath: custom, directoryHint: .isDirectory)
        }
        return home.appending(path: ".android/avd", directoryHint: .isDirectory)
    }

    /// Every AVD whose `<name>.ini` names an existing folder, sorted by name. A relative
    /// `path.rel` is used when `path` is missing.
    public static func list(in directory: URL = directory()) -> [AvdInfo] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { file -> AvdInfo? in
            guard file.hasSuffix(".ini"), !file.hasPrefix(".") else { return nil }
            let name = String(file.dropLast(".ini".count))
            guard !name.isEmpty,
                let text = try? String(contentsOf: directory.appending(path: file), encoding: .utf8)
            else { return nil }
            let values = IniParser.parse(text)
            let folder: URL
            if let path = values["path"], !path.isEmpty {
                folder = URL(filePath: path, directoryHint: .isDirectory)
            } else if let relative = values["path.rel"], !relative.isEmpty {
                folder = directory.deletingLastPathComponent().appending(path: relative, directoryHint: .isDirectory)
            } else {
                return nil
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue
            else { return nil }
            return AvdInfo(name: name, directory: folder, profile: DeviceProfile.load(avdDirectory: folder))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Finds the Android SDK and its emulator binary.
public enum AndroidSDK {
    /// `ANDROID_HOME`, then `ANDROID_SDK_ROOT`, then `~/Library/Android/sdk` (Android Studio's
    /// default on a Mac); the first that holds an emulator wins. Pane's own shadow SDK
    /// (`EmulatorTakeover`) is skipped: its launcher is the wrapper, which would ask Pane to
    /// attach to an emulator Pane is already starting.
    public static func emulatorExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) -> URL? {
        let shadow = EmulatorTakeover.shadowSDK(home: home).standardizedFileURL.path(percentEncoded: false)
        let roots =
            [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"]]
            .compactMap { $0 }.filter { !$0.isEmpty }.map { URL(filePath: $0, directoryHint: .isDirectory) }
            + [home.appending(path: "Library/Android/sdk", directoryHint: .isDirectory)]
        return
            roots
            .filter { $0.standardizedFileURL.path(percentEncoded: false) != shadow }
            .map { $0.appending(path: "emulator/emulator") }.first(where: isExecutable)
    }

    /// The real SDK's `adb`, found the same way (never through the shadow SDK).
    public static func adbExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutable: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) -> URL? {
        emulatorExecutable(
            environment: environment, home: home,
            isExecutable: { isExecutable(adb(besideEmulator: $0)) }
        ).map(adb(besideEmulator:))
    }

    private static func adb(besideEmulator emulator: URL) -> URL {
        emulator.deletingLastPathComponent().deletingLastPathComponent().appending(path: "platform-tools/adb")
    }
}
