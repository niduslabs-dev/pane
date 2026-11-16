import CoreGraphics
import Foundation

/// Measure: a line dragged between two points, in device pixels.
public struct MeasuredLine: Sendable, Equatable {
    public var start: CGPoint
    public var end: CGPoint

    public init(start: CGPoint, end: CGPoint) {
        self.start = start
        self.end = end
    }

    public var lengthPixels: CGFloat { hypot(end.x - start.x, end.y - start.y) }

    /// "42 dp · 110 px".
    public func text(scale: DensityScale) -> String {
        "\(scale.wholeDp(lengthPixels)) dp · \(Int(lengthPixels.rounded())) px"
    }

    /// The drag's end after snapping: to a nearby view edge on each axis, then onto the
    /// horizontal or vertical through `start` when the line is within `axisDegrees` of it.
    /// `edgeDistance` is how near (in pixels) an edge must be to pull the point.
    /// `forceAxis` (Shift) locks the line to whichever of level and upright is nearer, at any
    /// angle.
    public static func snappedEnd(
        start: CGPoint, end: CGPoint, axisDegrees: CGFloat, edges: SnapEdges?, edgeDistance: CGFloat,
        forceAxis: Bool = false
    ) -> CGPoint {
        var point = edges?.snapped(end, within: edgeDistance) ?? end
        let dx = point.x - start.x
        let dy = point.y - start.y
        guard dx != 0 || dy != 0 else { return point }
        let degreesPerRadian = 180 / CGFloat.pi
        let angle = atan2(abs(dy), abs(dx)) * degreesPerRadian
        let rightAngle: CGFloat = 90
        if angle <= axisDegrees || (forceAxis && angle <= rightAngle / 2) {
            point.y = start.y
        } else if angle >= rightAngle - axisDegrees || forceAxis {
            point.x = start.x
        }
        return point
    }

    /// The view edges the end sits on after snapping: an x when it is on a left or right
    /// edge, a y when on a top or bottom one. Inspect draws a guide along each.
    public static func snappedEdges(of point: CGPoint, edges: SnapEdges?) -> (x: CGFloat?, y: CGFloat?) {
        guard let edges else { return (nil, nil) }
        return (edges.xs.contains(point.x) ? point.x : nil, edges.ys.contains(point.y) ? point.y : nil)
    }

    /// "110 px", for a device whose density isn't known.
    public var pixelText: String { "\(Int(lengthPixels.rounded())) px" }
}

/// The view edges a measurement can snap to: every distinct left and right (x) and top and
/// bottom (y) in the tree.
public struct SnapEdges: Sendable, Equatable {
    public var xs: [CGFloat]
    public var ys: [CGFloat]

    public init(frames: [CGRect]) {
        xs = Array(Set(frames.flatMap { [$0.minX, $0.maxX] })).sorted()
        ys = Array(Set(frames.flatMap { [$0.minY, $0.maxY] })).sorted()
    }

    /// `point` with each coordinate moved to the nearest edge within `distance`, if any.
    public func snapped(_ point: CGPoint, within distance: CGFloat) -> CGPoint {
        CGPoint(
            x: Self.nearest(to: point.x, in: xs, within: distance),
            y: Self.nearest(to: point.y, in: ys, within: distance))
    }

    private static func nearest(to value: CGFloat, in edges: [CGFloat], within distance: CGFloat) -> CGFloat {
        guard let best = edges.min(by: { abs($0 - value) < abs($1 - value) }), abs(best - value) <= distance else {
            return value
        }
        return best
    }
}
