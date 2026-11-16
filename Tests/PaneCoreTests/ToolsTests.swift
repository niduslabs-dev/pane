import CoreGraphics
import Foundation
import Testing

@testable import PaneCore

private func fixtureDump() throws -> String {
    let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let url = fixtures.appending(path: "layout/settings.xml")
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct LayoutTreeTests {
    @Test func parsesTheDumpAndIgnoresTextAroundIt() throws {
        let tree = try LayoutTree.parse(try fixtureDump())
        #expect(tree.roots.count == 1)
        #expect(tree.roots[0].frame == CGRect(x: 0, y: 0, width: 1080, height: 2400))
        #expect(tree.frames.count == 28)
    }

    @Test func boundsBecomeFrames() {
        #expect(LayoutTree.frame(fromBounds: "[126,132][1080,321]") == CGRect(x: 126, y: 132, width: 954, height: 189))
        #expect(LayoutTree.frame(fromBounds: "[0,0][10]") == nil)
        #expect(LayoutTree.frame(fromBounds: "[10,10][0,0]") == nil)
        #expect(LayoutTree.frame(fromBounds: "") == nil)
    }

    @Test func hitTestFindsTheDeepestView() throws {
        let tree = try LayoutTree.parse(try fixtureDump())
        let title = try #require(tree.node(at: CGPoint(x: 500, y: 1100)))
        #expect(title.text == "No recent search results")
        #expect(title.shortClassName == "TextView")
        #expect(title.resourceID == "android:id/title")
        #expect(title.frame == CGRect(x: 283, y: 1070, width: 514, height: 68))

        let back = try #require(tree.node(at: CGPoint(x: 60, y: 200)))
        #expect(back.shortClassName == "ImageButton")
        #expect(back.label == "Back")

        // The icon sits inside an ImageView inside a FrameLayout: the innermost wins.
        #expect(tree.node(at: CGPoint(x: 500, y: 800))?.resourceID == "android:id/icon")
        // Inside the outer image but outside the icon.
        #expect(tree.node(at: CGPoint(x: 340, y: 600))?.shortClassName == "ImageView")
        // The far edge belongs to the next pixel, which is off the screen.
        #expect(tree.node(at: CGPoint(x: 1080, y: 100)) == nil)
        #expect(tree.node(at: CGPoint(x: -1, y: 100)) == nil)
    }

    @Test func hitAlsoGivesTheParentsFrame() throws {
        let tree = try LayoutTree.parse(try fixtureDump())
        let icon = try #require(tree.hit(at: CGPoint(x: 500, y: 800)))
        #expect(icon.node.resourceID == "android:id/icon")
        #expect(icon.parentFrame == CGRect(x: 330, y: 587, width: 420, height: 420))
        let inside = EdgeDistances(frame: icon.node.frame, parent: try #require(icon.parentFrame))
        #expect(inside.left == 115)
        #expect(inside.top == 115)
        #expect(inside.right == 116)
        #expect(inside.bottom == 116)
        // A root view has no parent: the screen stands in.
        let root = LayoutTree(roots: [LayoutNode(frame: CGRect(x: 0, y: 0, width: 10, height: 10))])
        #expect(root.hit(at: CGPoint(x: 5, y: 5))?.parentFrame == nil)
        #expect(tree.hit(at: CGPoint(x: -5, y: 5)) == nil)
        // A view that sticks out of its parent reads 0 on that side.
        let out = EdgeDistances(
            frame: CGRect(x: -5, y: 0, width: 20, height: 5), parent: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(out.left == 0)
        #expect(out.right == 0)
        #expect(out.bottom == 5)
    }

    @Test func laterSiblingsAreOnTopAndChildrenMayLeaveTheirParent() {
        let under = LayoutNode(className: "a.Under", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let over = LayoutNode(className: "a.Over", frame: CGRect(x: 50, y: 0, width: 100, height: 100))
        let stray = LayoutNode(className: "a.Stray", frame: CGRect(x: 300, y: 300, width: 10, height: 10))
        let parent = LayoutNode(
            className: "a.Parent", frame: CGRect(x: 200, y: 0, width: 10, height: 10), children: [stray])
        let tree = LayoutTree(roots: [under, over, parent])
        #expect(tree.node(at: CGPoint(x: 75, y: 50))?.shortClassName == "Over")
        #expect(tree.node(at: CGPoint(x: 25, y: 50))?.shortClassName == "Under")
        #expect(tree.node(at: CGPoint(x: 305, y: 305))?.shortClassName == "Stray")
    }

    @Test func errorsAreNamed() {
        #expect(throws: LayoutTree.ParseError.noHierarchy("could not get idle state.")) {
            try LayoutTree.parse("ERROR: could not get idle state.\n")
        }
        #expect(throws: LayoutTree.ParseError.malformed) {
            try LayoutTree.parse("<hierarchy><node bounds=\"[0,0][1,1]\"></hierarchy>")
        }
    }

    @Test func nodesWithoutBoundsAreDroppedWithTheirChildren() throws {
        let tree = try LayoutTree.parse(
            "<hierarchy><node class=\"a\"><node class=\"b\" bounds=\"[0,0][5,5]\"/></node>"
                + "<node class=\"x.y.Z$Inner\" bounds=\"[0,0][9,9]\"/></hierarchy>")
        #expect(tree.roots.count == 1)
        #expect(tree.roots[0].shortClassName == "Inner")
        #expect(tree.roots[0].label == nil)
    }
}

@Suite struct DensityTests {
    @Test func pixelsToDp() {
        let pixel8 = DensityScale(density: 420)
        #expect(pixel8.dp(420) == 160)
        #expect(pixel8.wholeDp(996) == 379)
        #expect(pixel8.wholeDp(182) == 69)
        #expect(pixel8.wholeDp(42) == 16)
        #expect(DensityScale(density: 160).dp(100) == 100)
        // A zero density from a broken config never divides by zero.
        #expect(DensityScale(density: 0).dp(1) == 160)
    }

    @Test func labels() {
        let scale = DensityScale(density: 420)
        #expect(scale.sizeText(CGSize(width: 996, height: 182)) == "379 × 69 dp")
        #expect(scale.frameText(CGRect(x: 42, y: 722, width: 996, height: 182)) == "x 16, y 275, 379 × 69 dp")
        #expect(DensityScale.pixelText(CGSize(width: 996, height: 182)) == "996 × 182 px")
    }

    @Test func edgeDistances() {
        let edges = EdgeDistances(
            frame: CGRect(x: 42, y: 722, width: 996, height: 182), screen: CGSize(width: 1080, height: 2400))
        #expect(edges.left == 42)
        #expect(edges.right == 42)
        #expect(edges.top == 722)
        #expect(edges.bottom == 1496)
        #expect(edges.nearestHorizontal.side == .left)
        #expect(edges.nearestVertical.side == .top)
        let low = EdgeDistances(
            frame: CGRect(x: 600, y: 2000, width: 400, height: 300), screen: CGSize(width: 1080, height: 2400))
        #expect(low.nearestHorizontal.side == .right)
        #expect(low.nearestHorizontal.distance == 80)
        #expect(low.nearestVertical.side == .bottom)
        #expect(low.nearestVertical.distance == 100)
    }

    @Test func screenScaleMapsBothWays() {
        let scale = ScreenScale(
            viewSize: CGSize(width: 315, height: 700), deviceSize: PixelSize(width: 1080, height: 2400), quadrants: 0)
        #expect(scale.pixels(CGPoint(x: 315, y: 700)) == CGPoint(x: 1080, y: 2400))
        let rect = scale.view(CGRect(x: 0, y: 1200, width: 540, height: 1200))
        #expect(abs(rect.width - 157.5) < 0.001)
        #expect(abs(rect.minY - 350) < 0.001)
        // Turned a quarter, the screen is as wide as the device is tall.
        let turned = ScreenScale(
            viewSize: CGSize(width: 700, height: 315), deviceSize: PixelSize(width: 1080, height: 2400), quadrants: 1)
        #expect(turned.pixelSize == CGSize(width: 2400, height: 1080))
        #expect(ScreenScale(viewSize: .zero, pixelSize: .zero).pixels(CGPoint(x: 1, y: 1)) == .zero)
    }
}

@Suite struct MeasurementTests {
    @Test func lengthAndLabel() {
        let line = MeasuredLine(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 66, y: 88))
        #expect(line.lengthPixels == 110)
        #expect(line.text(scale: DensityScale(density: 420)) == "42 dp · 110 px")
    }

    @Test func snapsToTheAxisWithinAFewDegrees() {
        let start = CGPoint(x: 100, y: 100)
        // About 2.9 degrees off horizontal: snaps.
        #expect(
            MeasuredLine.snappedEnd(
                start: start, end: CGPoint(x: 300, y: 110), axisDegrees: 4, edges: nil, edgeDistance: 0)
                == CGPoint(x: 300, y: 100))
        // About 2.9 degrees off vertical, upwards: snaps.
        #expect(
            MeasuredLine.snappedEnd(
                start: start, end: CGPoint(x: 90, y: -100), axisDegrees: 4, edges: nil, edgeDistance: 0)
                == CGPoint(x: 100, y: -100))
        // About 11 degrees: left alone.
        #expect(
            MeasuredLine.snappedEnd(
                start: start, end: CGPoint(x: 300, y: 140), axisDegrees: 4, edges: nil, edgeDistance: 0)
                == CGPoint(x: 300, y: 140))
        // No drag yet.
        #expect(MeasuredLine.snappedEnd(start: start, end: start, axisDegrees: 4, edges: nil, edgeDistance: 0) == start)
    }

    @Test func shiftForcesTheNearerAxis() {
        let start = CGPoint(x: 100, y: 100)
        #expect(
            MeasuredLine.snappedEnd(
                start: start, end: CGPoint(x: 300, y: 180), axisDegrees: 8, edges: nil, edgeDistance: 0,
                forceAxis: true) == CGPoint(x: 300, y: 100))
        #expect(
            MeasuredLine.snappedEnd(
                start: start, end: CGPoint(x: 180, y: 300), axisDegrees: 8, edges: nil, edgeDistance: 0,
                forceAxis: true) == CGPoint(x: 100, y: 300))
        // Eight degrees is the board's lock: about 7 degrees snaps, about 11 doesn't.
        #expect(
            MeasuredLine.snappedEnd(
                start: start, end: CGPoint(x: 300, y: 125), axisDegrees: 8, edges: nil, edgeDistance: 0)
                == CGPoint(x: 300, y: 100))
        #expect(MeasuredLine(start: .zero, end: CGPoint(x: 66, y: 88)).pixelText == "110 px")
    }

    @Test func namesTheEdgesAnEndSitsOn() {
        let edges = SnapEdges(frames: [CGRect(x: 42, y: 722, width: 996, height: 182)])
        let on = MeasuredLine.snappedEdges(of: CGPoint(x: 1038, y: 300), edges: edges)
        #expect(on.x == 1038)
        #expect(on.y == nil)
        #expect(MeasuredLine.snappedEdges(of: CGPoint(x: 50, y: 50), edges: edges) == (nil, nil))
        #expect(MeasuredLine.snappedEdges(of: CGPoint(x: 42, y: 722), edges: nil) == (nil, nil))
    }

    @Test func snapsToViewEdges() {
        let edges = SnapEdges(frames: [
            CGRect(x: 42, y: 722, width: 996, height: 182), CGRect(x: 42, y: 100, width: 200, height: 50),
        ])
        #expect(edges.xs == [42, 242, 1038])
        #expect(edges.ys == [100, 150, 722, 904])
        #expect(edges.snapped(CGPoint(x: 45, y: 500), within: 6) == CGPoint(x: 42, y: 500))
        #expect(edges.snapped(CGPoint(x: 1033, y: 909), within: 6) == CGPoint(x: 1038, y: 904))
        #expect(edges.snapped(CGPoint(x: 60, y: 500), within: 6) == CGPoint(x: 60, y: 500))
        // Edge first, then axis: the end lands on the edge and the line stays level.
        #expect(
            MeasuredLine.snappedEnd(
                start: CGPoint(x: 42, y: 300), end: CGPoint(x: 1035, y: 305), axisDegrees: 4, edges: edges,
                edgeDistance: 6) == CGPoint(x: 1038, y: 300))
    }
}

@Suite struct ColourPickTests {
    private func grid() -> PixelGrid {
        // 3 × 2: red, green, blue / black, white, #1A1B22.
        let bytes: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255,
            0, 0, 0, 255, 255, 255, 255, 255, 0x1A, 0x1B, 0x22, 255,
        ]
        return PixelGrid(size: PixelSize(width: 3, height: 2), pixels: Data(bytes))!
    }

    @Test func hex() {
        #expect(PickedColour(red: 0x1A, green: 0x1B, blue: 0x22).hex == "#1A1B22")
        #expect(PickedColour(red: 0x1A, green: 0x1B, blue: 0x22).rgb == "rgb(26, 27, 34)")
        #expect(PickedColour(red: 0, green: 0, blue: 0).hex == "#000000")
        #expect(PickedColour(red: 255, green: 255, blue: 255).hex == "#FFFFFF")
    }

    @Test func readsPixelsAndClampsAtTheEdges() {
        let grid = grid()
        #expect(grid.colour(x: 0, y: 0).hex == "#FF0000")
        #expect(grid.colour(x: 2, y: 1).hex == "#1A1B22")
        #expect(grid.colour(x: 9, y: 9).hex == "#1A1B22")
        #expect(grid.colour(x: -3, y: 0).hex == "#FF0000")
    }

    @Test func mapsViewPointsToPixels() {
        let grid = grid()
        let view = CGSize(width: 300, height: 200)
        #expect(grid.pixel(at: CGPoint(x: 0, y: 0), viewSize: view) == (0, 0))
        #expect(grid.pixel(at: CGPoint(x: 150, y: 150), viewSize: view) == (1, 1))
        #expect(grid.pixel(at: CGPoint(x: 299.9, y: 99.9), viewSize: view) == (2, 0))
        #expect(grid.pixel(at: CGPoint(x: 300, y: 200), viewSize: view) == (2, 1))
    }

    @Test func loupeNeighbourhoodRepeatsEdgePixels() {
        let around = grid().neighbourhood(x: 0, y: 0, radius: 1)
        #expect(around.count == 3)
        #expect(around.allSatisfy { $0.count == 3 })
        #expect(around[1][1].hex == "#FF0000")
        #expect(around[0][0].hex == "#FF0000")
        #expect(around[1][2].hex == "#00FF00")
        #expect(around[2][1].hex == "#000000")
    }

    @Test func rejectsShortBuffersAndReadsImages() {
        #expect(PixelGrid(size: PixelSize(width: 4, height: 4), pixels: Data(count: 10)) == nil)
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let grid = PixelGrid(image: context.makeImage()!)
        #expect(grid?.colour(x: 2, y: 2).hex == "#FF0000")
    }
}

@Suite struct DeviceLinkTests {
    @Test func acceptsWebAndAppLinks() throws {
        #expect(
            try DeviceLink.validated("  https://splito.niduslabs.dev/join/8F3K2 \n")
                == "https://splito.niduslabs.dev/join/8F3K2")
        #expect(try DeviceLink.validated("splito://group/weekend-trip") == "splito://group/weekend-trip")
        #expect(try DeviceLink.validated("mailto:hello@niduslabs.dev") == "mailto:hello@niduslabs.dev")
    }

    @Test func rejectsEmptyControlCharactersAndNoScheme() {
        #expect(throws: DeviceLink.Problem.empty) { try DeviceLink.validated("   ") }
        #expect(throws: DeviceLink.Problem.controlCharacters) { try DeviceLink.validated("https://a.b/\nreboot") }
        #expect(throws: DeviceLink.Problem.controlCharacters) { try DeviceLink.validated("https://a.b/\u{1B}[0m") }
        #expect(throws: DeviceLink.Problem.controlCharacters) { try DeviceLink.validated("https://a.b/\u{0}") }
        #expect(throws: DeviceLink.Problem.noScheme) { try DeviceLink.validated("splito.niduslabs.dev") }
        #expect(throws: DeviceLink.Problem.noScheme) { try DeviceLink.validated("://x") }
        #expect(throws: DeviceLink.Problem.noScheme) { try DeviceLink.validated("1http://x") }
        #expect(throws: DeviceLink.Problem.noScheme) { try DeviceLink.validated("a b://x") }
    }

    @Test func buildsAnArgumentArrayQuotedForTheDeviceShell() {
        #expect(
            DeviceLink.arguments(for: "https://a.b/?x=1&y=$(reboot);'z'") == [
                "shell", "am", "start", "-a", "android.intent.action.VIEW", "-d",
                "'https://a.b/?x=1&y=$(reboot);'\\''z'\\'''",
            ])
        let adb = Adb(executable: URL(filePath: "/sdk/platform-tools/adb"), serial: "emulator-5554")
        #expect(adb.targeted(["shell", "true"]) == ["-s", "emulator-5554", "shell", "true"])
    }

    @Test func readsAmStartFailures() {
        #expect(
            DeviceLink.failure(in: Adb.Output(status: 0, text: "Starting: Intent { act=android.intent.action.VIEW }\n"))
                == nil)
        let unresolved = """
            Starting: Intent { act=android.intent.action.VIEW dat=nosuchscheme://x/... }
            Error: Activity not started, unable to resolve Intent { act=android.intent.action.VIEW dat=nosuchscheme://x/... flg=0x10000000 }
            """
        #expect(
            DeviceLink.failure(in: Adb.Output(status: 1, text: unresolved)) == "Nothing on the device opens this link.")
        // `am` can report an error and still exit 0.
        #expect(
            DeviceLink.failure(in: Adb.Output(status: 0, text: unresolved)) == "Nothing on the device opens this link.")
        #expect(
            DeviceLink.failure(in: Adb.Output(status: 1, text: "adb: device 'emulator-5554' not found\n"))
                == "device 'emulator-5554' not found")
        #expect(DeviceLink.failure(in: Adb.Output(status: 1, text: "")) == "The link didn't open.")
        let long = DeviceLink.failure(in: Adb.Output(status: 1, text: "Error: " + String(repeating: "x", count: 200)))
        #expect(long?.count == 48)
    }

    @Test func recentKeepsTheLastFiveNewestFirst() {
        var recent = RecentLinks()
        for index in 1...10 { recent.add("https://a.b/\(index)") }
        #expect(recent.links.count == 5)
        #expect(recent.links.first == "https://a.b/10")
        #expect(recent.links.last == "https://a.b/6")
        recent.add("https://a.b/7")
        #expect(recent.links.count == 5)
        #expect(recent.links.prefix(2) == ["https://a.b/7", "https://a.b/10"])
        #expect(RecentLinks((1...20).map(String.init)).links.count == 5)
    }
}

@Suite struct DeviceSettingsTests {
    @Test func appearance() {
        #expect(DeviceAppearance.parse("Night mode: yes\n") == .dark)
        #expect(DeviceAppearance.parse("Night mode: no\n") == .light)
        #expect(DeviceAppearance.parse("Night mode: auto\n") == nil)
        #expect(DeviceAppearance.parse("") == nil)
        #expect(DeviceAppearance.dark.setArguments == ["shell", "cmd", "uimode", "night", "yes"])
        #expect(DeviceAppearance.light.setArguments == ["shell", "cmd", "uimode", "night", "no"])
    }

    @Test func textSize() {
        #expect(DeviceTextSize.parse("1.0\n") == .standard)
        #expect(DeviceTextSize.parse("null\n") == .standard)
        #expect(DeviceTextSize.parse("0.85") == .small)
        #expect(DeviceTextSize.parse("1.15") == .large)
        #expect(DeviceTextSize.parse("1.3") == .largest)
        #expect(DeviceTextSize.parse("2.0") == nil)
        #expect(DeviceTextSize.parse("junk") == nil)
        #expect(DeviceTextSize.largest.setArguments == ["shell", "settings", "put", "system", "font_scale", "1.30"])
        #expect(DeviceTextSize.allCases.map(\.title) == ["Small", "Default", "Large", "Largest"])
    }

    @Test func location() {
        #expect(
            DeviceLocation(latitudeText: " 12.9716", longitudeText: "77,5946")
                == DeviceLocation(latitude: 12.9716, longitude: 77.5946))
        #expect(DeviceLocation(latitudeText: "91", longitudeText: "0") == nil)
        #expect(DeviceLocation(latitudeText: "0", longitudeText: "-180.5") == nil)
        #expect(DeviceLocation(latitudeText: "", longitudeText: "1") == nil)
        #expect(DeviceLocation(latitudeText: "north", longitudeText: "1") == nil)
        #expect(DeviceLocation(latitude: 12.9716, longitude: 77.5946).summary == "12.9716, 77.5946")
    }

    @Test func adbRunReturnsOutputAndStopsSlowCalls() async throws {
        let echo = Adb(executable: URL(filePath: "/bin/echo"), serial: "emulator-5554")
        let output = try await echo.run(["shell", "a b", "$HOME"])
        // Arguments arrive as given: no shell expanded or split them.
        #expect(output == Adb.Output(status: 0, text: "-s emulator-5554 shell a b $HOME\n"))
        // `caffeinate -s -d` waits for ever, standing in for an adb call that never returns.
        let slow = Adb(executable: URL(filePath: "/usr/bin/caffeinate"), serial: "-d")
        await #expect(throws: Adb.Failure(message: "adb took too long.")) {
            try await slow.run([], timeout: .milliseconds(300))
        }
        #expect(Adb.shortReason(from: "adb: error: failed to stat\n\n") == "failed to stat")
        #expect(Adb.shortReason(from: "") == "")
    }
}

@Suite struct TitleRowTests {
    private let pixel = AvdInfo(
        name: "dev_android36", directory: URL(filePath: "/avd/dev_android36.avd"),
        profile: DeviceProfile(modelName: "Pixel 8", androidVersion: "Android 16"))

    @Test func startScreenNamesTheChosenEmulator() {
        let row = TitleRow(
            state: .noEmulator, emulatorName: nil, startingName: nil, selected: pixel, profile: DeviceProfile())
        #expect(row.title == "dev_android36")
        #expect(row.meta == "Pixel 8 · Android 16")
    }

    @Test func startScreenWithNoEmulatorsSetUpSaysPane() {
        let row = TitleRow(
            state: .noEmulator, emulatorName: nil, startingName: nil, selected: nil, profile: DeviceProfile())
        #expect(row.meta == "Android emulator")
        #expect(row.title == "Pane")
    }

    @Test func aChosenEmulatorWithNoProfileKeepsTheGenericLine() {
        let bare = AvdInfo(name: "tablet", directory: URL(filePath: "/avd/tablet.avd"))
        let row = TitleRow(
            state: .noEmulator, emulatorName: nil, startingName: nil, selected: bare, profile: DeviceProfile())
        #expect(row.title == "tablet")
        #expect(row.meta == "Android emulator")
    }

    @Test func aRunningEmulatorWinsOverTheChosenOne() {
        let row = TitleRow(
            state: .connected, emulatorName: "other", startingName: nil, selected: pixel,
            profile: DeviceProfile(modelName: "Pixel 9", androidVersion: "Android 15"))
        #expect(row.title == "other")
        #expect(row.meta == "Pixel 9 · Android 15")
    }

    @Test func startingAndFailed() {
        let starting = TitleRow(
            state: .starting, emulatorName: nil, startingName: "booting", selected: pixel, profile: pixel.profile)
        #expect(starting.title == "booting")
        let failed = TitleRow(
            state: .failed, emulatorName: "dev_android36", startingName: nil, selected: pixel, profile: pixel.profile)
        #expect(failed.title == "dev_android36")
        #expect(failed.meta == "Not connected")
    }
}
