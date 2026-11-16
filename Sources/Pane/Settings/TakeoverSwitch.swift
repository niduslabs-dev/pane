import Foundation
import Observation
import PaneCore
import os

/// Settings' "Show all emulators in Pane" switch. Turning it on or off runs the takeover
/// script, which edits the shell setup and takes a moment, so the switch dims and the caption
/// says "Changing…" meanwhile. If the script fails the switch goes back and the caption says so.
@MainActor
@Observable
final class TakeoverSwitch {
    enum State: Equatable {
        case idle
        case changing
        /// The last change failed; the switch is back where it was.
        case failed
    }

    static let caption = "Emulators started from Expo or a terminal open here."
    static let changingCaption = "Changing\u{2026}"
    static let failedCaption = "Couldn't change where emulators open."

    private(set) var isOn: Bool
    private(set) var state = State.idle

    @ObservationIgnored private let isInstalled: () -> Bool
    @ObservationIgnored private let run: (EmulatorTakeover.Action) async throws -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "dev.niduslabs.pane", category: "takeover")

    /// `isInstalled` reads the real state (the shadow SDK and the shell blocks); `run` installs
    /// or uninstalls.
    init(isInstalled: @escaping () -> Bool, run: @escaping (EmulatorTakeover.Action) async throws -> Void) {
        self.isInstalled = isInstalled
        self.run = run
        isOn = isInstalled()
    }

    var caption: String {
        switch state {
        case .idle: Self.caption
        case .changing: Self.changingCaption
        case .failed: Self.failedCaption
        }
    }

    /// Reads the real state again (it can change outside Pane) and forgets an old failure.
    /// Called each time Settings opens.
    func refresh() {
        guard state != .changing else { return }
        state = .idle
        isOn = isInstalled()
    }

    /// The switch was flipped. Ignored while a change is running.
    func set(_ on: Bool) {
        guard state != .changing, on != isOn else { return }
        state = .changing
        isOn = on
        log.info("Takeover \(on ? "install" : "uninstall", privacy: .public)")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(on ? .install : .uninstall)
                self.state = .idle
            } catch {
                self.log.error("Takeover failed: \(String(describing: error), privacy: .public)")
                self.state = .failed
            }
            self.isOn = self.isInstalled()
        }
    }

    /// Waits for a running change, for tests.
    func settle() async { await task?.value }
}
