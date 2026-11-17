import Foundation
import Testing

@testable import PaneCore

@Suite struct CaptureNoticeTests {
    private let desktop = URL(filePath: "/Users/someone/Desktop", directoryHint: .isDirectory)
    private let shots = URL(filePath: "/Users/someone/Pictures/Emulator shots", directoryHint: .isDirectory)

    @Test func aFileSaysWhichFolder() {
        #expect(CaptureNotice.screenshot(.file, folder: desktop)?.text == "Saved to Desktop.")
        #expect(CaptureNotice.screenshot(.file, folder: shots)?.text == "Saved to Emulator shots.")
    }

    @Test func onlyTheFolderNameTruncates() {
        let notice = CaptureNotice.saved(to: shots)
        #expect(notice.lead == "Saved to ")
        #expect(notice.name == "Emulator shots")
        #expect(notice.trail == ".")
    }

    @Test func clipboardSaysCopiedAndPreviewSaysNothing() {
        #expect(CaptureNotice.screenshot(.clipboard, folder: desktop) == .copied)
        #expect(CaptureNotice.copied.text == "Copied.")
        #expect(CaptureNotice.screenshot(.preview, folder: desktop) == nil)
    }

    @Test func eachShortcutKeepsItsOwnWords() {
        let clipboard = SystemCaptureTargets(target: "clipboard")
        let save = CaptureOutcome.resolve(.saveScreenshot, destination: .system, targets: clipboard)
        let copy = CaptureOutcome.resolve(
            .copyScreenshot, destination: .system, targets: SystemCaptureTargets(target: "file"))
        #expect(CaptureNotice.screenshot(save, folder: desktop)?.text == "Saved to Desktop.")
        #expect(CaptureNotice.screenshot(copy, folder: desktop)?.text == "Copied.")
    }

    @Test func recordingsAndFailures() {
        #expect(CaptureNotice.recordingSaved(to: desktop).text == "Recording saved to Desktop.")
        #expect(CaptureNotice.recordingSaved(to: shots).text == "Recording saved to Emulator shots.")
        #expect(CaptureNotice.screenshotFailed.text == "The screenshot didn't work.")
        #expect(CaptureNotice.recordingFailed.text == "Couldn't save the recording.")
    }

    @Test func noDashesInTheCopy() {
        let all: [CaptureNotice] = [
            .copied, .screenshotFailed, .recordingFailed, .saved(to: desktop), .recordingSaved(to: shots),
        ]
        for notice in all {
            #expect(!notice.text.contains("\u{2014}") && !notice.text.contains("\u{2013}"))
        }
    }

    @Test func aSecondPressWhileOneIsInFlightIsIgnored() {
        var gate = CaptureGate()
        let first = gate.begin()
        let second = gate.begin()
        #expect(first && !second)
        #expect(gate.isBusy)
        gate.finish()
        #expect(!gate.isBusy)
        let again = gate.begin()
        #expect(again)
    }
}
