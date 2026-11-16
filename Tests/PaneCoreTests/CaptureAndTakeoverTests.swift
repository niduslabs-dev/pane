import Foundation
import Testing

@testable import PaneCore

@Suite struct CaptureLocationTests {
    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    private func folder(_ configured: String?, writable: Set<String> = []) -> String {
        CaptureLocation.folder(configured: configured, home: home, isWritableFolder: { writable.contains($0.path) })
            .path(percentEncoded: false)
    }

    @Test func usesTheScreenshotFolderWithTildeExpanded() {
        #expect(
            folder("~/Pictures/Shots", writable: ["/Users/someone/Pictures/Shots"]) == "/Users/someone/Pictures/Shots/")
        #expect(folder("/Volumes/Work/Shots", writable: ["/Volumes/Work/Shots"]) == "/Volumes/Work/Shots/")
        #expect(folder("~", writable: ["/Users/someone"]) == "/Users/someone/")
    }

    @Test func fallsBackToTheDesktop() {
        #expect(folder(nil) == "/Users/someone/Desktop/")
        #expect(folder("  ") == "/Users/someone/Desktop/")
        #expect(folder("~/Gone") == "/Users/someone/Desktop/")
        #expect(folder("relative/path", writable: ["relative/path"]) == "/Users/someone/Desktop/")
    }

    @Test func saveToChoosesBetweenMacOSTheDesktopAndAFolder() {
        func folder(_ destination: CaptureDestination, writable: Set<String>) -> String {
            CaptureLocation.folder(
                for: destination, configured: "~/Pictures/Shots", home: home,
                isWritableFolder: { writable.contains($0.path) }
            ).path(percentEncoded: false)
        }
        let all: Set<String> = ["/Users/someone/Pictures/Shots", "/Users/someone/Pane"]
        #expect(folder(.system, writable: all) == "/Users/someone/Pictures/Shots/")
        #expect(folder(.desktop, writable: all) == "/Users/someone/Desktop/")
        #expect(folder(.folder("/Users/someone/Pane"), writable: all) == "/Users/someone/Pane/")
        // A chosen folder that has gone falls back to the Desktop.
        #expect(folder(.folder("/Users/someone/Pane"), writable: []) == "/Users/someone/Desktop/")
    }

    @Test func saveToIsStoredAsAKindAndAPath() {
        #expect(CaptureDestination(kind: nil, path: nil) == .system)
        #expect(CaptureDestination(kind: "desktop", path: "/a") == .desktop)
        #expect(CaptureDestination(kind: "folder", path: "/a") == .folder("/a"))
        #expect(CaptureDestination(kind: "folder", path: nil) == .system)
        #expect(CaptureDestination.folder("/a").kind == "folder")
    }

    @Test func checksARealFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pane-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(CaptureLocation.isWritableFolder(dir))
        let file = dir.appending(path: "file")
        try Data().write(to: file)
        #expect(!CaptureLocation.isWritableFolder(file))
    }
}

@Suite struct AttachRequestTests {
    @Test func readsTheURL() {
        #expect(AttachRequest.avdName(from: URL(string: "pane://attach?avd=dev_android36")!) == "dev_android36")
        #expect(
            AttachRequest.avdName(from: URL(string: "pane://attach?avd=Pixel_9.Pro-API_36")!) == "Pixel_9.Pro-API_36")
        #expect(AttachRequest.avdName(from: URL(string: "pane://other?avd=x")!) == nil)
        #expect(AttachRequest.avdName(from: URL(string: "https://attach?avd=x")!) == nil)
        #expect(AttachRequest.avdName(from: URL(string: "pane://attach")!) == nil)
        #expect(AttachRequest.avdName(from: URL(string: "pane://attach?avd=a%20b")!) == nil)
        #expect(AttachRequest.avdName(from: URL(string: "pane://attach?avd=../x%2Fy")!) == nil)
    }

    @Test func readsTheLaunchArgument() {
        #expect(AttachRequest.avdName(fromArguments: ["/x/Pane", "--attach", "dev_android36"]) == "dev_android36")
        #expect(AttachRequest.avdName(fromArguments: ["/x/Pane", "--attach"]) == nil)
        #expect(AttachRequest.avdName(fromArguments: ["/x/Pane", "-PaneNoAutoAttach", "YES"]) == nil)
    }
}

@Suite struct EmulatorTakeoverTests {
    @Test func shadowSdkPathHasNoSpaces() {
        let shadow = EmulatorTakeover.shadowSDK(home: URL(filePath: "/Users/someone", directoryHint: .isDirectory))
        #expect(shadow.path(percentEncoded: false) == "/Users/someone/Library/Android/pane-sdk/")
    }

    @Test func installedNeedsTheShadowAndEveryBlock() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "pane-takeover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let shadow = EmulatorTakeover.shadowSDK(home: home)
        try FileManager.default.createDirectory(
            at: shadow.appending(path: "emulator"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: home.appending(path: ".config/fish"), withIntermediateDirectories: true)
        #expect(!EmulatorTakeover.isInstalled(home: home))
        try "real_sdk=/x\n".write(to: shadow.appending(path: ".pane-takeover"), atomically: true, encoding: .utf8)
        let wrapper = shadow.appending(path: "emulator/emulator")
        try "#!/bin/sh\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let configs = EmulatorTakeover.shellConfigs(home: home)
        for config in configs.dropLast() {
            try "x\n\(EmulatorTakeover.beginMark)\n".write(to: config, atomically: true, encoding: .utf8)
        }
        #expect(!EmulatorTakeover.isInstalled(home: home))
        try "\(EmulatorTakeover.beginMark)\n".write(to: configs.last!, atomically: true, encoding: .utf8)
        #expect(EmulatorTakeover.isInstalled(home: home))
    }
}
