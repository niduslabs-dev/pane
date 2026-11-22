import CoreGraphics
import Testing

@testable import PaneCore

/// Board 27: a reshape keeps the window's centre, and rounding never walks it away.
@Suite struct HeldCentreTests {
    /// The window server's rounding of a placed frame.
    private func rounded(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX.rounded(.down), y: frame.minY, width: frame.width.rounded(), height: frame.height)
    }

    /// Places a frame of `width` centred as `held` says, as `PaneWindow.frameKeepingTop` does.
    private func reshape(_ frame: CGRect, to width: CGFloat, held: inout HeldCentre) -> CGRect {
        let centre = held.centre(for: frame)
        held.placed(at: centre)
        return rounded(CGRect(x: centre - width / 2, y: frame.minY, width: width, height: frame.height))
    }

    @Test func foldsAndUnfoldsKeepTheCentre() {
        var held = HeldCentre()
        var frame = CGRect(x: 312, y: 100, width: 868, height: 900)
        let start = frame.midX
        for _ in 0..<20 {
            frame = reshape(frame, to: 443, held: &held)
            frame = reshape(frame, to: 868, held: &held)
        }
        #expect(frame.midX == start)
    }

    @Test func withoutTheHeldCentreRoundingDrifts() {
        var frame = CGRect(x: 312, y: 100, width: 868, height: 900)
        let start = frame.midX
        for _ in 0..<4 {
            frame = rounded(CGRect(x: frame.midX - 443 / 2, y: frame.minY, width: 443, height: frame.height))
            frame = rounded(CGRect(x: frame.midX - 868 / 2, y: frame.minY, width: 868, height: frame.height))
        }
        #expect(frame.midX < start)
    }

    @Test func aWindowTheUserMovedKeepsItsNewCentre() {
        var held = HeldCentre()
        held.placed(at: 745.5)
        #expect(held.centre(for: CGRect(x: 524, y: 0, width: 443, height: 10)) == 745.5)
        let moved = CGRect(x: 600, y: 0, width: 443, height: 10)
        #expect(held.centre(for: moved) == moved.midX)
    }

    @Test func aFirstReshapeUsesTheWindowsCentre() {
        let frame = CGRect(x: 10, y: 0, width: 101, height: 10)
        #expect(HeldCentre().centre(for: frame) == frame.midX)
    }
}
