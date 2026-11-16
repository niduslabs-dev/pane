import Foundation
import Testing

@testable import PaneCore

@Suite struct DiscoveryTests {
    private let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    private var running: URL { fixtures.appending(path: "running") }
    private let fixtureToken = "fixture-token-not-a-secret"

    @Test func registrationFolderIsUnderTheCachesFolder() {
        let home = URL(filePath: "/Users/test", directoryHint: .isDirectory)
        #expect(
            EmulatorDiscovery.registrationDirectory(home: home).path
                == "/Users/test/Library/Caches/TemporaryItems/avd/running")
    }

    @Test func parsesTheRealFileShape() throws {
        let text = try String(contentsOf: running.appending(path: "pid_54866.ini"), encoding: .utf8)
        let emulator = try EmulatorDiscovery.parse(fileName: "pid_54866.ini", contents: text)
        #expect(emulator.pid == 54866)
        #expect(emulator.grpcPort == 8554)
        #expect(emulator.avdName == "dev_android36")
        #expect(emulator.emulatorVersion == "37.2.13.0")
        #expect(emulator.consolePort == 5554)
        #expect(emulator.avdDirectory?.path == "/Users/test/.android/avd/dev_android36.avd")
        #expect(emulator.token.bearerHeaderValue == "Bearer \(fixtureToken)")
    }

    @Test func tokenNeverAppearsInText() throws {
        let text = try String(contentsOf: running.appending(path: "pid_54866.ini"), encoding: .utf8)
        let emulator = try EmulatorDiscovery.parse(fileName: "pid_54866.ini", contents: text)
        let renderings = [
            "\(emulator)", String(describing: emulator), String(reflecting: emulator), "\(emulator.token)",
            String(reflecting: emulator.token), "\(Mirror(reflecting: emulator).children.map { $0.value })",
        ]
        for rendering in renderings {
            #expect(!rendering.contains(fixtureToken))
        }
    }

    @Test func listsOnlyLiveEmulatorsWithAPort() {
        let found = EmulatorDiscovery.runningEmulators(in: running, isAlive: { $0 != 70001 })
        #expect(found.map(\.pid) == [54866])
    }

    @Test func staleFilesAreSkipped() {
        let found = EmulatorDiscovery.runningEmulators(in: running, isAlive: { _ in false })
        #expect(found.isEmpty)
    }

    @Test func missingFolderFindsNothing() {
        let found = EmulatorDiscovery.runningEmulators(in: fixtures.appending(path: "absent"), isAlive: { _ in true })
        #expect(found.isEmpty)
    }

    @Test(arguments: [
        ("pid_1.ini", Int32(1)), ("pid_54866.ini", 54866), ("pid_.ini", nil), ("pid_12a.ini", nil),
        ("pid_12.ini.bak", nil), ("54866", nil), ("notes.ini", nil), ("pid_١٢.ini", nil),
    ])
    func fileNames(name: String, pid: Int32?) {
        #expect(EmulatorDiscovery.pid(fromFileName: name) == pid)
    }

    @Test func missingKeysAreReported() {
        #expect(throws: DiscoveryError.missingKey("grpc.port")) {
            try EmulatorDiscovery.parse(fileName: "pid_1.ini", contents: "avd.name=a\ngrpc.token=t\n")
        }
        #expect(throws: DiscoveryError.missingKey("grpc.token")) {
            try EmulatorDiscovery.parse(fileName: "pid_1.ini", contents: "avd.name=a\ngrpc.port=8554\n")
        }
        #expect(throws: DiscoveryError.missingKey("avd.name")) {
            try EmulatorDiscovery.parse(fileName: "pid_1.ini", contents: "grpc.port=8554\ngrpc.token=t\n")
        }
        #expect(throws: DiscoveryError.notARegistrationFile("x.ini")) {
            try EmulatorDiscovery.parse(fileName: "x.ini", contents: "")
        }
    }

    @Test(arguments: ["0", "65536", "-1", "port", ""])
    func badPortsAreRejected(port: String) {
        #expect(throws: DiscoveryError.invalidValue(key: "grpc.port")) {
            try EmulatorDiscovery.parse(
                fileName: "pid_1.ini", contents: "avd.name=a\ngrpc.token=t\ngrpc.port=\(port)\n")
        }
    }

    @Test func valuesKeepEqualsSignsAndTrimSpaces() {
        let values = IniParser.parse(" a = b=c \n# comment\n=novalue\nnoequals\nempty=\r\n")
        #expect(values == ["a": "b=c", "empty": ""])
    }

    @Test func deviceProfileFromConfigIni() throws {
        let profile = DeviceProfile.load(avdDirectory: fixtures.appending(path: "avd"))
        #expect(profile.modelName == "Pixel 8")
        #expect(profile.androidVersion == "Android 16")
        #expect(profile.screenSize == PixelSize(width: 1080, height: 2400))
        #expect(profile.density == 420)
        #expect(profile.summary == "Pixel 8 · Android 16")
    }

    @Test func deviceProfileFallbacks() {
        #expect(DeviceProfile.load(avdDirectory: fixtures.appending(path: "absent")) == DeviceProfile())
        #expect(DeviceProfile.androidRelease(apiLevel: 40) == "API 40")
        #expect(DeviceProfile.apiLevel(fromSystemImagePath: "system-images/android-35/google_apis/") == 35)
        #expect(DeviceProfile.apiLevel(fromSystemImagePath: "weird/path") == nil)
        #expect(DeviceProfile.readableModelName("pixel_8_pro") == "Pixel 8 Pro")
        let profile = DeviceProfile.parse(configIni: "hw.lcd.width=0\nhw.lcd.height=2400\n")
        #expect(profile.screenSize == nil)
        #expect(profile.summary.isEmpty)
    }
}
