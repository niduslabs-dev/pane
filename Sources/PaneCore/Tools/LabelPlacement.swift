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

    /// Places a distance chip on its guide from `from` to `to`: beside the line at `gap` (under a
    /// level guide, right of an upright one), sliding only along the guide, from its middle
    /// toward each end, so it is always clear which distance a number belongs to. Each of
    /// `sizes` is tried in turn (the full label first, then shorter forms); a chip that fits
    /// nowhere along its guide clear of what is taken is not placed, and the caller hides it
    /// rather than move it off its guide. Returns the index of the size used and the frame.
    public mutating func placeOnGuide(from: CGPoint, to: CGPoint, sizes: [CGSize], gap: CGFloat)
        -> (size: Int, frame: CGRect)?
    {
        for (index, size) in sizes.enumerated() {
            for centre in Self.guidePositions(from: from, to: to, chip: size, gap: gap) {
                let frame = clamped(
                    CGRect(origin: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2), size: size))
                if overlapArea(of: frame) == 0 {
                    taken.append(frame)
                    return (index, frame)
                }
            }
        }
        return nil
    }

    /// A chip's centres on a guide: beside it at `gap`, at the guide's middle first, then a `gap`
    /// at a time toward each end, alternating, until the chip's edge reaches the end. On a guide
    /// shorter than the chip (a small inset beside the outline) the chip overhangs the end away
    /// from the view, still on the line and still touching its guide.
    public static func guidePositions(from: CGPoint, to: CGPoint, chip: CGSize, gap: CGFloat) -> [CGPoint] {
        let horizontal = abs(to.x - from.x) >= abs(to.y - from.y)
        let start = horizontal ? min(from.x, to.x) : min(from.y, to.y)
        let end = horizontal ? max(from.x, to.x) : max(from.y, to.y)
        let line = horizontal ? from.y : from.x
        let extent = horizontal ? chip.width : chip.height
        let side = line + (horizontal ? chip.height / 2 : chip.width / 2) + gap
        let middle = (start + end) / 2
        let reach = (end - start + extent) / 2
        var offsets: [CGFloat] = [0]
        if gap > 0 {
            var step = gap
            while step < reach {
                offsets += [step, -step]
                step += gap
            }
            if reach > 0 { offsets += [reach, -reach] }
        }
        return offsets.map { offset in
            horizontal ? CGPoint(x: middle + offset, y: side) : CGPoint(x: side, y: middle + offset)
        }
    }
}
