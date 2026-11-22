import CoreGraphics

/// The horizontal centre a reshape keeps (board 27), held across reshapes.
///
/// The window server rounds a window's frame to whole points, so a frame centred on its
/// rounded predecessor drifts by half a point on every reshape whose width changes by an odd
/// number. Pane remembers the centre it asked for and keeps using it while the window's
/// actual centre is within rounding of it; a centre further off means the user moved the
/// window, and that one is held instead.
public struct HeldCentre: Equatable, Sendable {
    /// How far rounding can move a frame's centre: half a point from the origin and half from
    /// the width.
    public static let roundingTolerance: CGFloat = 1

    private var asked: CGFloat?

    public init() {}

    /// The centre to keep for a window whose frame is now `frame`.
    public func centre(for frame: CGRect) -> CGFloat {
        guard let asked, abs(frame.midX - asked) <= Self.roundingTolerance else { return frame.midX }
        return asked
    }

    /// Records the centre a new frame was placed at.
    public mutating func placed(at centre: CGFloat) { asked = centre }
}
