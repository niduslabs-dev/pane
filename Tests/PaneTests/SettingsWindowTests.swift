import Foundation
import PaneCore
import PaneTakeover
import Testing

@testable import Pane

/// The Settings window's own state: the takeover switch, Save to and the sound setting.
@MainActor
@Suite struct SettingsWindowTests {
    /// A stand-in for the takeover's disk and launchd work.
    @MainActor
    private final class FakeTakeover {
        var wrapped = false
        var failure: EmulatorTakeover.Failure?
        var actions: [String] = []
        var agent = EmulatorTakeover.AgentStatus.present
        var exists = true
        var found: URL? = URL(filePath: "/Users/me/Library/Android/sdk", directoryHint: .isDirectory)
        /// Holds a change open until resumed, so the changing state can be looked at.
        var gate: CheckedContinuation<Void, Never>?
        var holds = false

        func step(_ name: String) async throws(EmulatorTakeover.Failure) {
            actions.append(name)
            if holds { await withCheckedContinuation { gate = $0 } }
            if let failure { throw failure }
        }

        var backend: TakeoverSwitch.Backend {
            TakeoverSwitch.Backend(
                resolveSDK: { self.found }, candidateSDK: { self.found },
                install: { _ throws(EmulatorTakeover.Failure) in
                    try await self.step("install")
                    self.wrapped = true
                },
                uninstall: { _ throws(EmulatorTakeover.Failure) in
                    try await self.step("uninstall")
                    self.wrapped = false
                },
                ensure: { _ throws(EmulatorTakeover.Failure) in
                    try await self.step("ensure")
                    self.wrapped = true
                    return .wrapped
                },
                isWrapped: { _ in self.wrapped }, agentStatus: { self.agent }, sdkExists: { _ in self.exists })
        }
    }

    private func makeSettings() -> PaneSettings {
        let name = "pane-takeover-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PaneSettings(defaults: defaults)
    }

    private func text(_ caption: TakeoverSwitch.Caption) -> String { caption.spoken }

    @Test func turningOnSavesTheSdkAndShowsChangingThenDone() async {
        let fake = FakeTakeover()
        fake.holds = true
        let settings = makeSettings()
        let toggle = TakeoverSwitch(settings: settings, backend: fake.backend)
        #expect(!toggle.isOn)
        #expect(text(toggle.caption) == "Emulators started with /Users/me/Library/Android/sdk open here.")
        toggle.set(true)
        #expect(toggle.isOn)
        #expect(toggle.phase == .changing)
        #expect(text(toggle.caption) == "Changing\u{2026}")
        // A second flip while it runs is ignored.
        toggle.set(false)
        while fake.gate == nil { await Task.yield() }
        fake.gate?.resume()
        await toggle.settle()
        #expect(fake.actions == ["install"])
        #expect(toggle.isOn)
        #expect(settings.takeoverSDKPath == "/Users/me/Library/Android/sdk")
        #expect(text(toggle.caption) == TakeoverSwitch.turnedOnCaption)
        toggle.settingsDidClose()
        #expect(text(toggle.caption) == "Emulators started with /Users/me/Library/Android/sdk open here.")
    }

    @Test func eachFailureHasItsOwnCaptionAndPutsTheSwitchBack() async {
        let cases: [(EmulatorTakeover.Failure, String, Bool)] = [
            (.notWritable(URL(filePath: "/s/emulator")), "Couldn't write to /s/emulator.", true),
            (.updateRunning, TakeoverSwitch.updateRunningCaption, true),
            (.agentRefused("x"), TakeoverSwitch.helperBlockedCaption, true),
        ]
        for (failure, caption, isError) in cases {
            let fake = FakeTakeover()
            fake.failure = failure
            let toggle = TakeoverSwitch(settings: makeSettings(), backend: fake.backend)
            toggle.set(true)
            await toggle.settle()
            #expect(!toggle.isOn)
            #expect(text(toggle.caption) == caption)
            #expect(toggle.caption.isError == isError)
            toggle.refresh()
            #expect(toggle.phase == .idle)
        }
    }

    @Test func turningOffRestoresAndSaysOff() async {
        let fake = FakeTakeover()
        fake.wrapped = true
        let settings = makeSettings()
        settings.takeoverSDKPath = "/Users/me/Library/Android/sdk"
        let toggle = TakeoverSwitch(settings: settings, backend: fake.backend)
        #expect(toggle.isOn)
        toggle.set(false)
        await toggle.settle()
        #expect(fake.actions == ["uninstall"])
        #expect(!toggle.isOn)
        #expect(settings.takeoverSDKPath == nil)
        #expect(text(toggle.caption) == TakeoverSwitch.turnedOffCaption)
    }

    /// On is the user's choice: an update removing the wrapper never turns the switch off.
    @Test func staysOnWhileRepairingAndSaysWhatsWrong() async {
        let fake = FakeTakeover()
        let settings = makeSettings()
        settings.takeoverSDKPath = "/Users/me/Library/Android/sdk"
        let toggle = TakeoverSwitch(settings: settings, backend: fake.backend)
        fake.holds = true
        toggle.folderChanged()
        #expect(toggle.isOn)
        #expect(text(toggle.caption) == TakeoverSwitch.repairingCaption)
        while fake.gate == nil { await Task.yield() }
        fake.gate?.resume()
        await toggle.settle()
        #expect(toggle.health == .ok)
        fake.holds = false
        fake.agent = .disabled
        toggle.refresh()
        #expect(toggle.isOn)
        #expect(text(toggle.caption) == TakeoverSwitch.repairsOffCaption)
        #expect(toggle.showsOpenLoginItems)
        #expect(!toggle.caption.isError)
        fake.exists = false
        toggle.refresh()
        #expect(toggle.isOn)
        #expect(text(toggle.caption) == "/Users/me/Library/Android/sdk is missing.")
        #expect(toggle.caption.isError)
    }

    @Test func noSdkDisablesTheSwitch() {
        let fake = FakeTakeover()
        fake.found = nil
        let toggle = TakeoverSwitch(settings: makeSettings(), backend: fake.backend)
        #expect(toggle.hasNoSDK)
        #expect(text(toggle.caption) == TakeoverSwitch.noSDKCaption)
    }

    @Test func migrationTurnsTheNewSwitchOnOrShowsWhyNot() async {
        let fake = FakeTakeover()
        let toggle = TakeoverSwitch(settings: makeSettings(), backend: fake.backend)
        toggle.migrate(wasOn: true) {}
        await toggle.settle()
        #expect(toggle.isOn)
        #expect(fake.actions == ["install"])

        struct Refused: Error {}
        let failing = TakeoverSwitch(settings: makeSettings(), backend: FakeTakeover().backend)
        failing.migrate(wasOn: true) { throw Refused() }
        await failing.settle()
        #expect(!failing.isOn)
        #expect(text(failing.caption) == TakeoverSwitch.migrationCaption)
        // It stays for the next time Settings opens, then goes once Settings closes.
        failing.refresh()
        #expect(text(failing.caption) == TakeoverSwitch.migrationCaption)
        failing.settingsDidClose()
        #expect(failing.phase == .idle)
    }

    @Test func soundAndSaveToRoundTrip() {
        let name = "pane-settings-window-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = PaneSettings(defaults: defaults)
        #expect(settings.startsWithoutSound)
        #expect(settings.captureDestination == .system)
        #expect(settings.captureFolderPath == nil)
        settings.startsWithoutSound = false
        settings.captureDestination = .folder("/Users/me/Pictures/Pane")
        var reread = PaneSettings(defaults: defaults)
        #expect(!reread.startsWithoutSound)
        #expect(reread.captureDestination == .folder("/Users/me/Pictures/Pane"))
        // Choosing the Desktop keeps the folder on offer.
        reread.captureDestination = .desktop
        reread = PaneSettings(defaults: defaults)
        #expect(reread.captureDestination == .desktop)
        #expect(reread.captureFolderPath == "/Users/me/Pictures/Pane")
    }

    @Test func saveToOffersTheLastFolderAndThePicker() {
        let home = URL(filePath: "/Users/me")
        #expect(
            SaveChoice.options(lastFolder: nil, home: home).map(\.label) == [
                "Same as macOS screenshots", "Desktop", "Choose folder\u{2026}",
            ])
        let options = SaveChoice.options(lastFolder: "/Users/me/Pictures/Pane", home: home)
        #expect(
            options.map(\.label) == [
                "Same as macOS screenshots", "Desktop", "~/Pictures/Pane", "Choose folder\u{2026}",
            ])
        #expect(options[2].value == SaveChoice(.folder("/Users/me/Pictures/Pane")))
        #expect(options[2].monospaced)
        #expect(options[3].value.destination == nil)
    }
}
