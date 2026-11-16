import Foundation
import PaneCore
import Testing

@testable import Pane

/// The Settings window's own state: the takeover switch, Save to and the sound setting.
@MainActor
@Suite struct SettingsWindowTests {
    private struct Refused: Error {}

    /// A stand-in for the takeover script and the state it leaves on disk.
    @MainActor
    private final class FakeTakeover {
        var installed = false
        var fails = false
        var actions: [EmulatorTakeover.Action] = []
        /// Holds a run open until resumed, so the changing state can be looked at.
        var gate: CheckedContinuation<Void, Never>?
        var holds = false

        func run(_ action: EmulatorTakeover.Action) async throws {
            actions.append(action)
            if holds { await withCheckedContinuation { gate = $0 } }
            if fails { throw Refused() }
            installed = action == .install
        }
    }

    private func makeSwitch(_ fake: FakeTakeover) -> TakeoverSwitch {
        TakeoverSwitch(isInstalled: { fake.installed }, run: { try await fake.run($0) })
    }

    @Test func turningOnRunsInstallAndShowsChangingMeanwhile() async {
        let fake = FakeTakeover()
        fake.holds = true
        let toggle = makeSwitch(fake)
        #expect(!toggle.isOn)
        #expect(toggle.caption == "Emulators started from Expo or a terminal open here.")
        toggle.set(true)
        #expect(toggle.isOn)
        #expect(toggle.state == .changing)
        #expect(toggle.caption == "Changing\u{2026}")
        // A second flip while the script runs is ignored.
        toggle.set(false)
        while fake.gate == nil { await Task.yield() }
        fake.gate?.resume()
        await toggle.settle()
        #expect(fake.actions == [.install])
        #expect(toggle.isOn)
        #expect(toggle.state == .idle)
    }

    @Test func failurePutsTheSwitchBackAndSaysSo() async {
        let fake = FakeTakeover()
        fake.fails = true
        let toggle = makeSwitch(fake)
        toggle.set(true)
        await toggle.settle()
        #expect(!toggle.isOn)
        #expect(toggle.state == .failed)
        #expect(toggle.caption == "Couldn't change where emulators open.")
        // Opening Settings again forgets the old failure.
        toggle.refresh()
        #expect(toggle.state == .idle)
    }

    @Test func turningOffRunsUninstall() async {
        let fake = FakeTakeover()
        fake.installed = true
        let toggle = makeSwitch(fake)
        #expect(toggle.isOn)
        toggle.set(false)
        await toggle.settle()
        #expect(fake.actions == [.uninstall])
        #expect(!toggle.isOn)
    }

    @Test func refreshFollowsAChangeMadeOutsidePane() {
        let fake = FakeTakeover()
        let toggle = makeSwitch(fake)
        fake.installed = true
        toggle.refresh()
        #expect(toggle.isOn)
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
