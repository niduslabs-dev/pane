import AppKit
import Foundation
import Observation
import PaneCore
import PaneTakeover
import os

/// Settings' "Show all emulators in Pane" (boards 23 and 25).
///
/// On is the user's choice, saved with the SDK it applies to (`PaneSettings.takeoverSDKPath`),
/// never "the wrapper is there this second": an emulator update removes the wrapper until a
/// repair puts it back, and the switch stays on meanwhile, saying "Repairing…". Pane repairs on
/// launch and whenever the SDK folder changes while it runs; the launch agent covers the rest.
/// Turning it on or off dims the switch with "Changing…"; a failure puts it back and gives the
/// reason in the error colour.
@MainActor
@Observable
final class TakeoverSwitch {
    enum Phase: Equatable {
        case idle
        case changing
        /// The last change failed; the switch is back where it was.
        case failed(Failure)
    }

    enum Failure: Equatable {
        case takeover(EmulatorTakeover.Failure)
        /// The first launch after the shadow SDK version couldn't undo it; the reason, as a
        /// sentence, follows the caption.
        case migration(String)
    }

    /// What is wrong while the switch is on.
    enum Health: Equatable {
        case ok
        /// An update replaced the launcher; a repair is pending or running.
        case repairing
        /// The background item is turned off in System Settings.
        case repairsOff
        /// The saved SDK is gone.
        case sdkMissing
    }

    /// The one-time captions after a change, kept until Settings closes.
    enum Notice: Equatable {
        case none, turnedOn, turnedOff
    }

    /// What the row's caption says: plain text with an optional path in the middle (drawn
    /// monospaced, cut in the middle when long), and whether it is an error.
    struct Caption: Hashable {
        var before: String
        var path: URL?
        var after: String = ""
        var isError = false

        /// What VoiceOver reads: the path as words, never "tilde slash".
        var spoken: String { before + (path.map { FolderDisplay.plainPath($0) } ?? "") + after }
    }

    /// The work the switch does, injected so tests never touch a real SDK or launchd.
    struct Backend {
        /// The SDK to wrap when turned on (asks the login shell; slow).
        var resolveSDK: () async -> URL?
        /// The SDK the Off caption names, from Pane's own lookup (fast).
        var candidateSDK: () -> URL?
        var install: (URL) async throws(EmulatorTakeover.Failure) -> Void
        var uninstall: (URL?) async throws(EmulatorTakeover.Failure) -> Void
        /// Repairs the wrapper and refreshes the agent (launch, folder changes).
        var ensure: (URL) async throws(EmulatorTakeover.Failure) -> TakeoverRepair.Outcome
        var isWrapped: (URL) -> Bool
        var agentStatus: () -> EmulatorTakeover.AgentStatus
        var sdkExists: (URL) -> Bool
    }

    static let changingCaption = "Changing\u{2026}"
    static let noSDKCaption = "No Android SDK found."
    static let repairingCaption = "Repairing after an emulator update\u{2026}"
    static let repairsOffCaption = "Repairs after updates are off in System Settings."
    static let turnedOnCaption = "Done. Start an emulator from Expo or a terminal to try it."
    static let turnedOffCaption = "Off. Emulators open in their own window again."
    static let updateRunningCaption = "An emulator update is running. Try again shortly."
    static let helperBlockedCaption = "macOS blocked the repair helper."
    static let migrationCaption = "Couldn't remove the old shell setup."

    private(set) var phase = Phase.idle
    private(set) var health = Health.ok
    private(set) var notice = Notice.none
    /// The SDK the Off caption names, until it's turned on.
    private(set) var candidate: URL?
    /// The switch as drawn: on while a turn-on is changing, back off after a failure.
    private(set) var isOn: Bool

    /// Called with the saved SDK whenever it changes (turned on or off), so the app can watch it.
    @ObservationIgnored var onSDKChange: ((URL?) -> Void)?
    @ObservationIgnored private let settings: PaneSettings
    @ObservationIgnored private let backend: Backend
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var repairTask: Task<Void, Never>?
    @ObservationIgnored private var repairAgain = false
    @ObservationIgnored private let log = Logger(subsystem: "dev.niduslabs.pane", category: "takeover")

    init(settings: PaneSettings, backend: Backend) {
        self.settings = settings
        self.backend = backend
        isOn = settings.takeoverSDKPath != nil
        candidate = backend.candidateSDK()
    }

    /// The saved SDK, while on.
    var sdk: URL? {
        #if DEBUG
            if let demoSDK { return demoSDK }
        #endif
        return settings.takeoverSDKPath.map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Disabled in place: off, and no SDK to wrap.
    var hasNoSDK: Bool { !isOn && phase != .changing && candidate == nil }

    var showsOpenLoginItems: Bool { phase == .idle && notice == .none && isOn && health == .repairsOff }

    var caption: Caption {
        switch phase {
        case .changing: return Caption(before: Self.changingCaption)
        case .failed(let failure): return Self.caption(for: failure)
        case .idle: break
        }
        switch notice {
        case .turnedOn: return Caption(before: Self.turnedOnCaption)
        case .turnedOff: return Caption(before: Self.turnedOffCaption)
        case .none: break
        }
        if isOn, let sdk {
            switch health {
            case .sdkMissing: return Caption(before: "", path: sdk, after: " is missing.", isError: true)
            case .repairsOff: return Caption(before: Self.repairsOffCaption)
            case .repairing: return Caption(before: Self.repairingCaption)
            case .ok: return Caption(before: "Emulators started with ", path: sdk, after: " open here.")
            }
        }
        guard let candidate else { return Caption(before: Self.noSDKCaption) }
        return Caption(before: "Emulators started with ", path: candidate, after: " open here.")
    }

    static func caption(for failure: Failure) -> Caption {
        switch failure {
        case .migration(let reason):
            return Caption(before: reason.isEmpty ? migrationCaption : "\(migrationCaption) \(reason)", isError: true)
        case .takeover(let failure):
            switch failure {
            case .notWritable(let url), .foreignLauncher(let url):
                return Caption(before: "Couldn't write to ", path: url, after: ".", isError: true)
            case .updateRunning: return Caption(before: updateRunningCaption, isError: true)
            case .agentRefused: return Caption(before: helperBlockedCaption, isError: true)
            case .sdkMissing(let url): return Caption(before: "", path: url, after: " is missing.", isError: true)
            }
        }
    }

    /// System Settings › General › Login Items & Extensions, where the repair item is turned
    /// back on.
    static func openLoginItems() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Lifecycle

    /// Settings opened: forget an old failure and notice, and read the state again.
    func refresh() {
        guard phase != .changing else { return }
        if case .failed(.migration) = phase {
        } else {
            phase = .idle
        }
        notice = .none
        candidate = backend.candidateSDK()
        updateHealth()
    }

    /// Settings closed: the one-time captions are done.
    func settingsDidClose() {
        notice = .none
        if case .failed(.migration) = phase { phase = .idle }
    }

    /// On launch, with the switch on: repair now. Call `folderChanged()` on SDK folder events.
    func launched() {
        guard isOn else { return }
        updateHealth()
        repair()
    }

    /// The SDK folder changed (an update may have replaced the launcher).
    func folderChanged() {
        guard isOn, phase != .changing else { return }
        log.debug("SDK folder changed")
        updateHealth()
        repair()
    }

    private func updateHealth() {
        guard isOn, let sdk else {
            health = .ok
            return
        }
        if !backend.sdkExists(sdk) {
            health = .sdkMissing
        } else if backend.agentStatus() == .disabled {
            health = .repairsOff
        } else if !backend.isWrapped(sdk) {
            health = .repairing
        } else {
            health = .ok
        }
    }

    private func repair() {
        guard let sdk, backend.sdkExists(sdk) else { return }
        if repairTask != nil {
            repairAgain = true
            return
        }
        repairTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.repairAgain = false
                do throws(EmulatorTakeover.Failure) {
                    let outcome = try await self.backend.ensure(sdk)
                    self.log.info("Repair: \(String(describing: outcome), privacy: .public)")
                } catch {
                    self.log.error("Repair failed: \(String(describing: error), privacy: .public)")
                }
                self.updateHealth()
            } while self.repairAgain && self.isOn
            self.repairTask = nil
        }
    }

    // MARK: Changes

    /// The switch was flipped. Ignored while a change is running, and when there's no SDK.
    func set(_ on: Bool) {
        guard phase != .changing, on != isOn else { return }
        phase = .changing
        notice = .none
        isOn = on
        log.info("Takeover \(on ? "on" : "off", privacy: .public)")
        task = Task { [weak self] in
            guard let self else { return }
            do throws(EmulatorTakeover.Failure) {
                if on {
                    guard let sdk = await self.backend.resolveSDK() else {
                        throw .sdkMissing(self.candidate ?? URL(filePath: "/"))
                    }
                    try await self.backend.install(sdk)
                    self.settings.takeoverSDKPath = FolderDisplay.plainPath(sdk)
                    self.notice = .turnedOn
                    self.onSDKChange?(self.sdk)
                } else {
                    try await self.backend.uninstall(self.sdk)
                    self.settings.takeoverSDKPath = nil
                    self.onSDKChange?(nil)
                    self.candidate = self.backend.candidateSDK()
                    self.notice = .turnedOff
                }
                self.phase = .idle
            } catch {
                self.log.error("Takeover failed: \(String(describing: error), privacy: .public)")
                self.phase = .failed(.takeover(error))
            }
            self.isOn = self.settings.takeoverSDKPath != nil
            self.updateHealth()
        }
    }

    /// The first launch after the shadow SDK version: `uninstallOld` runs the old uninstall;
    /// when it worked and the old switch was on, the new one turns on. When it failed the new
    /// switch stays off and Settings shows why.
    func migrate(wasOn: Bool, uninstallOld: @escaping () async throws -> Void) {
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await uninstallOld()
            } catch {
                self.log.error("Couldn't remove the shadow SDK: \(String(describing: error), privacy: .public)")
                self.phase = .failed(.migration(""))
                return
            }
            self.log.info("Removed the shadow SDK")
            if wasOn {
                self.set(true)
                await self.task?.value
                self.notice = .none
            }
        }
    }

    /// Waits for a running change, for tests.
    func settle() async {
        while let running = task {
            await running.value
            if task == running { break }
        }
        await repairTask?.value
    }

    #if DEBUG
        /// `pane://check-takeover?state=`: shows a board 23 or 25 state without doing anything,
        /// for screenshots. `sdk` stands in for the saved or found SDK.
        func demo(_ state: String, sdk: URL) {
            task?.cancel()
            phase = .idle
            notice = .none
            health = .ok
            candidate = sdk
            isOn = true
            switch state {
            case "off": isOn = false
            case "changing": phase = .changing
            case "on", "custom": break
            case "repairing": health = .repairing
            case "repairsoff": health = .repairsOff
            case "missing": health = .sdkMissing
            case "failed-write":
                isOn = false
                phase = .failed(.takeover(.notWritable(sdk)))
            case "failed-update":
                isOn = false
                phase = .failed(.takeover(.updateRunning))
            case "failed-helper":
                isOn = false
                phase = .failed(.takeover(.agentRefused("")))
            case "migration":
                isOn = false
                phase = .failed(.migration(""))
            case "nosdk":
                isOn = false
                candidate = nil
            case "done": notice = .turnedOn
            case "offnotice":
                isOn = false
                notice = .turnedOff
            default: break
            }
            demoSDK = isOn ? sdk : nil
        }

        var demoSDK: URL?
    #endif
}
