import CoreGraphics
import Foundation
import PaneCore
import Testing

@testable import Pane

/// `PaneSettings` keeps each value under its own key and each emulator's values apart.
@MainActor
@Suite struct SettingsTests {
    private func scratch() -> (PaneSettings, UserDefaults, String) {
        let name = "pane-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (PaneSettings(defaults: defaults), defaults, name)
    }

    @Test func defaultsAndRoundTrips() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(settings.sharesClipboard)
        #expect(!settings.includesDeviceFrame)
        #expect(settings.selectedAVDName == nil)
        settings.sharesClipboard = false
        settings.includesDeviceFrame = true
        settings.selectedAVDName = "dev_android36"
        let reread = PaneSettings(defaults: defaults)
        #expect(!reread.sharesClipboard)
        #expect(reread.includesDeviceFrame)
        #expect(reread.selectedAVDName == "dev_android36")
    }

    @Test func perEmulatorValuesStayApart() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(settings.sizeMode(for: "a") == nil)
        settings.setSizeMode(.pixel, for: "a")
        settings.setWindowTopLeft(CGPoint(x: 40, y: 900), for: "a")
        settings.setLocation(DeviceLocation(latitude: 12.9716, longitude: 77.5946), for: "a")
        for index in 1...10 { settings.addRecentLink("https://a.b/\(index)", for: "a") }
        #expect(settings.sizeMode(for: "a") == .pixel)
        #expect(settings.windowTopLeft(for: "a") == CGPoint(x: 40, y: 900))
        #expect(settings.location(for: "a") == DeviceLocation(latitude: 12.9716, longitude: 77.5946))
        #expect(settings.recentLinks(for: "a").links.count == RecentLinks.limit)
        #expect(settings.recentLinks(for: "a").links.first == "https://a.b/10")
        #expect(settings.sizeMode(for: "b") == nil)
        #expect(settings.windowTopLeft(for: "b") == nil)
        #expect(settings.location(for: "b") == nil)
        #expect(settings.recentLinks(for: "b").links.isEmpty)
        settings.setSizeMode(nil, for: "a")
        settings.setLocation(nil, for: "a")
        #expect(settings.sizeMode(for: "a") == nil)
        #expect(settings.location(for: "a") == nil)
    }

    @Test func lastRecordingIsForgottenOnceTheFileIsGone() throws {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        let file = FileManager.default.temporaryDirectory.appending(path: "pane-last-\(UUID().uuidString).mov")
        try Data().write(to: file)
        settings.lastRecording = file
        #expect(settings.lastRecording?.lastPathComponent == file.lastPathComponent)
        try FileManager.default.removeItem(at: file)
        #expect(settings.lastRecording == nil)
    }

    /// Board 27: each AVD's last live shape, so a folded Fold opens folded.
    @Test func remembersEachAVDsLiveShape() {
        let (settings, defaults, name) = scratch()
        defer { defaults.removePersistentDomain(forName: name) }
        let folded = PixelSize(width: 1080, height: 2424)
        #expect(settings.liveScreenSize(for: "fold") == nil)
        settings.setLiveScreenSize(folded, for: "fold")
        #expect(PaneSettings(defaults: defaults).liveScreenSize(for: "fold") == folded)
        #expect(settings.liveScreenSize(for: "pixel") == nil)
        settings.setLiveScreenSize(nil, for: "fold")
        #expect(PaneSettings(defaults: defaults).liveScreenSize(for: "fold") == nil)
    }
}
