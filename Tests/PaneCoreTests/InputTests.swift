import Carbon.HIToolbox
import Foundation
import Testing

@testable import PaneCore

@Suite struct KeyMappingTests {
    @Test func namedKeysUseW3CNames() {
        #expect(KeyMapping.keyName(macKeyCode: UInt16(kVK_Delete)) == "Backspace")
        #expect(KeyMapping.keyName(macKeyCode: UInt16(kVK_ForwardDelete)) == "Delete")
        #expect(KeyMapping.keyName(macKeyCode: UInt16(kVK_Return)) == "Enter")
        #expect(KeyMapping.keyName(macKeyCode: UInt16(kVK_LeftArrow)) == "ArrowLeft")
        #expect(KeyMapping.keyName(macKeyCode: UInt16(kVK_Escape)) == "Escape")
        #expect(KeyMapping.keyName(macKeyCode: UInt16(kVK_ANSI_A)) == nil)
    }

    @Test func onlyPrintableTextIsTyped() {
        #expect(KeyMapping.typedText("a") == "a")
        #expect(KeyMapping.typedText("É") == "É")
        #expect(KeyMapping.typedText("\u{F702}") == nil)  // AppKit's left-arrow character
        #expect(KeyMapping.typedText("\u{1B}") == nil)
        #expect(KeyMapping.typedText("") == nil)
    }
}

@Suite struct CaptureFileNameTests {
    private let date = Date(timeIntervalSince1970: 1_779_000_000)
    private let utc = TimeZone(identifier: "UTC")!

    @Test func namedLikeMacScreenshots() {
        let name = CaptureFileName.name(prefix: "Pane", date: date, fileExtension: "png", timeZone: utc)
        #expect(name == "Pane 2026-05-17 at 06.40.00.png")
    }

    @Test func neverOverwrites() {
        let folder = URL(filePath: "/x", directoryHint: .isDirectory)
        let taken: Set<String> = ["/x/Pane 2026-05-17 at 06.40.00.png", "/x/Pane 2026-05-17 at 06.40.00 (2).png"]
        let url = CaptureFileName.unusedURL(
            in: folder, prefix: "Pane", date: date, fileExtension: "png", timeZone: utc,
            exists: { taken.contains($0.path) })
        #expect(url.lastPathComponent == "Pane 2026-05-17 at 06.40.00 (3).png")
    }
}

@Suite struct ScrollGestureTests {
    private let screen = CGRect(x: 0, y: 0, width: 315, height: 700)

    @Test func trackpadPhasesAreADrag() {
        var gesture = ScrollGesture()
        let start = CGPoint(x: 150, y: 400)
        #expect(
            gesture.handle(phase: .began, pointer: start, delta: CGVector(dx: 0, dy: -10), bounds: screen) == [
                .down(start), .move(CGPoint(x: 150, y: 390)),
            ])
        #expect(
            gesture.handle(phase: .changed, pointer: start, delta: CGVector(dx: 2, dy: -20), bounds: screen) == [
                .move(CGPoint(x: 152, y: 370))
            ])
        #expect(
            gesture.handle(phase: .ended, pointer: start, delta: .zero, bounds: screen) == [
                .up(CGPoint(x: 152, y: 370))
            ])
        #expect(gesture.finger == nil)
    }

    @Test func leavingTheScreenLiftsAtTheEdgeThenStartsAgain() {
        var gesture = ScrollGesture()
        let start = CGPoint(x: 150, y: 20)
        let lifted = gesture.handle(phase: .began, pointer: start, delta: CGVector(dx: 0, dy: -50), bounds: screen)
        #expect(lifted == [.down(start), .move(CGPoint(x: 150, y: 0)), .up(CGPoint(x: 150, y: 0))])
        let again = gesture.handle(phase: .changed, pointer: start, delta: CGVector(dx: 0, dy: -5), bounds: screen)
        #expect(again == [.down(start), .move(CGPoint(x: 150, y: 15))])
    }

    @Test func wheelLiftsOnlyWhenTold() {
        var gesture = ScrollGesture()
        let pointer = CGPoint(x: 100, y: 300)
        _ = gesture.handle(phase: .wheel, pointer: pointer, delta: CGVector(dx: 0, dy: 24), bounds: screen)
        #expect(
            gesture.handle(phase: .wheel, pointer: pointer, delta: CGVector(dx: 0, dy: 24), bounds: screen) == [
                .move(CGPoint(x: 100, y: 348))
            ])
        #expect(gesture.endWheel() == .up(CGPoint(x: 100, y: 348)))
        #expect(gesture.endWheel() == nil)
    }

    @Test func nothingStartsOutsideTheScreen() {
        var gesture = ScrollGesture()
        let actions = gesture.handle(
            phase: .began, pointer: CGPoint(x: -5, y: 10), delta: CGVector(dx: 0, dy: 5), bounds: screen)
        #expect(actions.isEmpty)
    }
}
