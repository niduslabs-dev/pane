/// The turns asked for that the emulator hasn't shown yet, in the order they were asked.
///
/// Rotation is followed from the frames: a frame tagged with another orientation turns the
/// layout. While the emulator eases a turn it can tag frames with an orientation on the
/// way (180 to −90 passes 0), so while turns are waiting only an orientation that was asked
/// for is followed. Any of them is: a late frame for an earlier press is still a real turn,
/// and the frame for the latest one may follow it or never come on its own.
public struct RotationRequests: Equatable, Sendable {
    private static let quarterTurnsInACircle = 4

    /// Oldest first.
    public private(set) var waiting: [Int] = []

    public init() {}

    /// The orientation one more quarter turn asks for, counted from the last one asked for
    /// (or `current`), so each press turns once more. Records it as waiting.
    public mutating func ask(from current: Int) -> Int {
        let target = ((waiting.last ?? current) + 1) % Self.quarterTurnsInACircle
        waiting.append(target)
        return target
    }

    /// Whether a frame in `quadrants` should turn the layout.
    public func follows(_ quadrants: Int) -> Bool {
        waiting.isEmpty || waiting.contains(quadrants)
    }

    /// The emulator showed `quadrants`: it and every turn asked for before it are done.
    public mutating func shown(_ quadrants: Int) {
        guard let index = waiting.firstIndex(of: quadrants) else { return }
        waiting.removeFirst(index + 1)
    }

    /// Whether `target` still waits to be shown.
    public func isWaiting(for target: Int) -> Bool { waiting.contains(target) }

    /// Stops waiting for anything once the latest turn never showed, so any orientation is
    /// followed again. An earlier turn's give-up leaves a newer one waiting.
    public mutating func giveUp(on target: Int) {
        if waiting.last == target { waiting.removeAll() }
    }

    public mutating func reset() { waiting.removeAll() }
}
