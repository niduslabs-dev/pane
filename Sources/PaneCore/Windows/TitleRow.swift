/// The title row's two lines: the emulator's name over its model and Android version.
///
/// A window with nothing running is still about one emulator, the one Start would launch, so
/// it names that one; only a Mac with no emulators set up reads "Pane".
public struct TitleRow: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// Nothing running: the Start screen.
        case noEmulator
        /// An emulator is coming up.
        case starting
        /// Connecting, booting or live.
        case connected
        /// A running emulator that can't be reached.
        case failed
    }

    public var title: String
    public var meta: String

    public static let appName = "Pane"
    public static let genericMeta = "Android emulator"
    public static let failedMeta = "Not connected"

    /// - Parameters:
    ///   - emulatorName: the AVD of the emulator the window is connected (or connecting) to.
    ///   - startingName: the AVD being started.
    ///   - selected: the AVD Start would launch.
    ///   - profile: the profile of the emulator on screen or starting.
    public init(
        state: State, emulatorName: String?, startingName: String?, selected: AvdInfo?, profile: DeviceProfile
    ) {
        func metaLine(_ profile: DeviceProfile?) -> String {
            guard let summary = profile?.summary, !summary.isEmpty else { return Self.genericMeta }
            return summary
        }
        switch state {
        case .noEmulator:
            title = selected?.name ?? Self.appName
            meta = metaLine(selected?.profile)
        case .starting:
            title = startingName ?? selected?.name ?? Self.appName
            meta = metaLine(profile)
        case .connected:
            title = emulatorName ?? Self.appName
            meta = metaLine(profile)
        case .failed:
            title = emulatorName ?? Self.appName
            meta = Self.failedMeta
        }
    }
}
