import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import PaneCore

private func solid(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@Suite struct GifExporterTests {
    @Test func frameTimesAndSizes() {
        #expect(GifExporter.frameTimes(duration: 1, framesPerSecond: 10).count == 10)
        #expect(GifExporter.frameTimes(duration: 0.25, framesPerSecond: 10) == [0, 0.1, 0.2])
        #expect(GifExporter.frameTimes(duration: 0, framesPerSecond: 10) == [0])
        #expect(
            GifExporter.fittedSize(CGSize(width: 1080, height: 2400), maxSide: 480) == CGSize(width: 216, height: 480))
        #expect(
            GifExporter.fittedSize(CGSize(width: 2400, height: 1080), maxSide: 480) == CGSize(width: 480, height: 216))
        #expect(
            GifExporter.fittedSize(CGSize(width: 200, height: 100), maxSide: 480) == CGSize(width: 200, height: 100))
    }

    @Test func exportsARecordingAsALoopingGif() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pane-gif-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appending(path: "in.mov")
        let recorder = FrameRecorder(url: movie, size: PixelSize(width: 160, height: 320))
        let start: UInt64 = 1_000_000
        for index in 0..<6 {
            await recorder.append(
                solid(width: 160, height: 320, red: CGFloat(index) / 5, green: 0, blue: 0),
                timestampMicroseconds: start + UInt64(index) * 200_000)
            try await Task.sleep(for: .milliseconds(20))
        }
        try await recorder.finish()

        let gif = folder.appending(path: "out.gif")
        let frames = try await GifExporter.export(
            movie: movie, to: gif, options: GifExporter.Options(maxSide: 80, framesPerSecond: 10))
        // One second of movie at 10 frames a second.
        #expect(frames == 10)
        let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 10)
        let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(first.width == 40)
        #expect(first.height == 80)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double == 0.1)
        let file = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        #expect((file?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int == 0)
    }

    @Test func aFileWithNoVideoFails() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pane-not-a-movie-\(UUID().uuidString).mov")
        try Data("nope".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: (any Error).self) {
            try await GifExporter.export(
                movie: url, to: url.appendingPathExtension("gif"),
                options: GifExporter.Options(maxSide: 80, framesPerSecond: 10))
        }
    }
}

@Suite struct FramedScreenshotTests {
    private let spec = FrameSpec(
        screenHeight: 700, referenceScreenHeight: 700, bezel: 10, bodyRadius: 46, screenRadius: 36,
        buttons: [FrameButtonSpec(button: .power, offset: 150, length: 56)],
        buttonDepth: 3, buttonHitDepth: 14, buttonHitOutset: 4, titleRowHeight: 52, contentInset: 24, bottomInset: 54)

    private var style: FrameStyle {
        let grey = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        return FrameStyle(
            body: grey, edge: grey, innerEdge: grey, button: grey, buttonEdge: grey, edgeWidth: 1,
            innerEdgeInset: 3, innerEdgeWidth: 0.5, buttonEdgeWidth: 0.75, buttonCornerRadius: 2)
    }

    @Test func layoutIsTheScreenshotPlusBezelAndButtons() {
        let layout = FramedScreenshot.layout(
            spec: spec, screenshotSize: PixelSize(width: 630, height: 1400), quadrants: 0)
        // Twice the reference size: 20 px of bezel, 6 px of button on each side, no chrome.
        #expect(layout.screenRect == CGRect(x: 26, y: 20, width: 630, height: 1400))
        #expect(layout.windowContentSize == CGSize(width: 682, height: 1440))
        let turned = FramedScreenshot.layout(
            spec: spec, screenshotSize: PixelSize(width: 1400, height: 630), quadrants: 1)
        #expect(turned.screenRect.size == CGSize(width: 1400, height: 630))
        // Turned, the buttons are on one long side only.
        #expect(turned.windowContentSize == CGSize(width: 1440, height: 676))
    }

    @Test func drawsTheScreenshotInsideTheFrameOnATransparentBackground() throws {
        let shot = solid(width: 630, height: 1400, red: 1, green: 0, blue: 0)
        let framed = try #require(FramedScreenshot.render(screenshot: shot, spec: spec, quadrants: 0, style: style))
        #expect(framed.width == 682)
        #expect(framed.height == 1440)
        let png = try #require(FramedScreenshot.png(from: framed))
        let decoded = try #require(FramedScreenshot.image(fromPNG: png))
        let context = CGContext(
            data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8,
            bytesPerRow: decoded.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = (y * decoded.width + x) * 4
            return (0..<4).map { bytes[offset + $0] }
        }
        // The corner outside the rounded body is clear, the bezel is the body's grey, the
        // middle of the screen is the screenshot, and nothing is drawn over the camera's place:
        // the emulator's own screenshot holds the cutout.
        #expect(pixel(1, 1)[3] == 0)
        #expect(pixel(341, 10)[3] == 255)
        #expect(pixel(341, 10)[0] < 40)
        #expect(pixel(341, 720) == [255, 0, 0, 255])
        #expect(pixel(341, 55) == [255, 0, 0, 255])
    }
}

@Suite struct WindowRosterTests {
    private let avds = [
        AvdInfo(
            name: "dev_android36", directory: URL(filePath: "/a"),
            profile: DeviceProfile(modelName: "Pixel 8", androidVersion: "Android 16")),
        AvdInfo(
            name: "pixel9_api35", directory: URL(filePath: "/b"),
            profile: DeviceProfile(modelName: "Pixel 9 Pro", androidVersion: "Android 15")),
        AvdInfo(name: "tablet_api36", directory: URL(filePath: "/c")),
    ]

    @Test func switcherEntries() {
        let entries = SwitcherEntry.entries(
            avds: avds, running: ["pixel9_api35", "elsewhere"], current: "dev_android36",
            shownElsewhere: ["pixel9_api35"])
        #expect(entries.map(\.name) == ["dev_android36", "pixel9_api35", "tablet_api36", "elsewhere"])
        #expect(entries[0].isCurrent && !entries[0].isRunning)
        #expect(entries[0].detail == "Pixel 8 · Android 16")
        #expect(entries[1].isRunning && entries[1].isShownElsewhere && !entries[1].isCurrent)
        #expect(entries[2].detail.isEmpty && !entries[2].isRunning)
        // A running emulator whose AVD isn't on disk still gets a row.
        #expect(entries[3].isRunning)
    }

    @Test func switcherEntryStatesAndSecondLine() {
        let entries = SwitcherEntry.entries(
            avds: avds, running: ["dev_android36", "pixel9_api35"], starting: ["pixel9_api35"],
            current: "dev_android36", shownElsewhere: [])
        #expect(entries.map(\.state) == [.running, .starting, .stopped])
        // The model truncates first; the Android version, or Starting, is kept whole.
        #expect(entries[0].secondLine == ("Pixel 8", " · Android 16"))
        #expect(entries[1].secondLine == ("Pixel 9 Pro", " · Starting"))
        #expect(entries[2].secondLine == ("", ""))
        #expect(!entries[0].opensInNewWindow && entries[1].opensInNewWindow)
        #expect(entries[1].accessibilityText == "pixel9_api35, Pixel 9 Pro, Android 15, starting")

        let elsewhere = SwitcherEntry.entries(
            avds: avds, running: ["pixel9_api35"], current: "dev_android36", shownElsewhere: ["pixel9_api35"])
        #expect(elsewhere[1].secondLine == ("In another window", " · Android 15"))
        #expect(!elsewhere[1].opensInNewWindow)
        // VoiceOver still reads the model.
        #expect(elsewhere[1].accessibilityText == "pixel9_api35, Pixel 9 Pro, Android 15, in another window, running")
    }

    @Test func deviceKindIsNotReadFromTheName() {
        // Board 28: the kind comes from the config's keys; a name alone says nothing.
        #expect(DeviceProfile.parse(configIni: "hw.device.name=pixel_tablet\n").kind == .phone)
        #expect(DeviceProfile.parse(configIni: "hw.device.name=pixel_9_pro_fold\n").kind == .phone)
        #expect(DeviceProfile.parse(configIni: "").kind == .phone)
    }

    @Test func oneWindowPerEmulator() {
        var roster = WindowRoster<Int>()
        #expect(roster.isEmpty)
        roster.add(1, showing: "dev_android36")
        roster.add(2, showing: nil)
        #expect(roster.window(showing: "dev_android36") == 1)
        #expect(roster.window(showing: "pixel9_api35") == nil)
        #expect(roster.avdsShown(except: 1).isEmpty)
        #expect(roster.avdsShown(except: 2) == ["dev_android36"])
        roster.set("pixel9_api35", for: 2)
        #expect(roster.avd(in: 2) == "pixel9_api35")
        roster.set("x", for: 99)
        #expect(roster.windows == [1, 2])
        roster.remove(1)
        #expect(roster.window(showing: "dev_android36") == nil)
        #expect(roster.windows == [2])
    }

    @Test func newWindowsTakeAnEmulatorWithoutAWindow() {
        var roster = WindowRoster<Int>()
        roster.add(1, showing: "dev_android36")
        let names = avds.map(\.name)
        // A running one first, then any AVD, then nothing left.
        #expect(roster.avdForNewWindow(avds: names, running: ["dev_android36", "tablet_api36"]) == "tablet_api36")
        #expect(roster.avdForNewWindow(avds: names, running: ["dev_android36"]) == "pixel9_api35")
        #expect(roster.avdForNewWindow(avds: ["dev_android36"], running: ["dev_android36"]) == nil)
    }

    @Test func attachRequestsFindTheirWindow() {
        var roster = WindowRoster<Int>()
        roster.add(1, showing: "dev_android36")
        roster.add(2, showing: "pixel9_api35")
        #expect(roster.placement(for: "pixel9_api35", idle: [1]) == .existing(2))
        #expect(roster.placement(for: "tablet_api36", idle: [2]) == .reuse(2))
        #expect(roster.placement(for: "tablet_api36", idle: []) == .newWindow)
    }
}
