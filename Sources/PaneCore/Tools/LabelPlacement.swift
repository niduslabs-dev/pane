import CoreGraphics

/// Places a tool's labels (the inspect card, distance chips) so that none covers another, the
/// outline or a chip already placed. Each label offers its places in order of preference; the
/// first one that is clear wins, else the one that overlaps least. Every place is first moved
/// inside `bounds`.
public struct LabelPlacement {
    public let bounds: CGRect
    /// The clear space kept between labels and around what they avoid.
    public let spacing: CGFloat
    /// What every label avoids: the outline, the size chip and every label placed so far.
    public private(set) var taken: [CGRect]

    public init(bounds: CGRect, spacing: CGFloat, avoiding: [CGRect]) {
        self.bounds = bounds
        self.spacing = spacing
        taken = avoiding
    }

    /// Places a label of `size` at the first clear centre of `candidates`, records it so later
    /// labels avoid it, and returns its frame.
    public mutating func place(size: CGSize, candidates: [CGPoint]) -> CGRect {
        precondition(!candidates.isEmpty, "A label needs at least one place.")
        var best: CGRect?
        var bestOverlap = CGFloat.infinity
        for centre in candidates {
            let frame = clamped(
                CGRect(origin: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2), size: size))
            let overlap = overlapArea(of: frame)
            if overlap == 0 {
                best = frame
                break
            }
            if overlap < bestOverlap {
                bestOverlap = overlap
                best = frame
            }
        }
        let frame = best ?? .zero
        taken.append(frame)
        return frame
    }

    private func overlapArea(of frame: CGRect) -> CGFloat {
        let padded = frame.insetBy(dx: -spacing, dy: -spacing)
        return taken.reduce(0) { total, rect in
            let shared = padded.intersection(rect)
            return shared.isNull ? total : total + shared.width * shared.height
        }
    }

    private func clamped(_ frame: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
        frame.origin.y = min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
        return frame
    }

    /// Places for a distance chip along a guide from `from` to `to`: beside its middle first
    /// (under a level guide, right of an upright one), then the other side, then nearer each
    /// end on both sides.
    public static func guideCandidates(from: CGPoint, to: CGPoint, chip: CGSize, gap: CGFloat) -> [CGPoint] {
        let horizontal = abs(to.x - from.x) >= abs(to.y - from.y)
        let side = horizontal ? chip.height / 2 + gap : chip.width / 2 + gap
        var points: [CGPoint] = []
        for fraction in [0.5, 0.25, 0.75] {
            let point = CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
            for sign in [1.0, -1.0] {
                points.append(
                    horizontal
                        ? CGPoint(x: point.x, y: point.y + sign * side)
                        : CGPoint(x: point.x + sign * side, y: point.y))
            }
        }
        return points
    }
}
