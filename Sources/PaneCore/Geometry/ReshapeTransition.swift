/// The reshape's steps when the device's screen changes shape: a fold, an unfold or a turn
/// (board 27).
///
/// It starts with the last frame veiled (blurred and dimmed) while the window morphs and the
/// stream restarts. The new stream's first frame waits under the veil until the morph has
/// settled; a frame that comes after the morph keeps the veil up until it arrives. Then the
/// veil clears, and only once it has cleared does the screen take clicks again. A new shape
/// during any step starts over from where the window is (one restart, the latest shape).
///
/// Under Reduce Motion there is no morph: the window takes its new size at once, so the morph
/// counts as settled from the start and the frame crossfades in as soon as it arrives.
public struct ReshapeTransition: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Waiting for the new frame, the morph's end, or both.
        case reshaping(frameIn: Bool, settled: Bool)
        /// The new frame is on screen and the veil is clearing.
        case clearing
    }

    /// How the veil clears: the blur and dim ease out, or (Reduce Motion) the new frame
    /// crossfades over the veiled one.
    public enum Clear: Equatable, Sendable {
        case unveil
        case crossfade
    }

    public private(set) var phase: Phase = .idle
    public private(set) var clear: Clear = .unveil

    public init() {}

    /// Clicks reach the device only when no reshape is under way.
    public var acceptsInput: Bool { phase == .idle }

    /// True while the screen shows the old frame under the veil: new frames are held back.
    public var holdsFrames: Bool {
        if case .reshaping = phase { return true }
        return false
    }

    /// A new shape: the veil goes up (or stays up) and the transition waits for a frame of the
    /// new shape and for the morph.
    public mutating func begin(reduceMotion: Bool) {
        clear = reduceMotion ? .crossfade : .unveil
        phase = .reshaping(frameIn: false, settled: reduceMotion)
    }

    /// A frame of the new shape arrived. True when the veil should clear now.
    @discardableResult
    public mutating func frameArrived() -> Bool {
        guard case .reshaping(_, let settled) = phase else { return false }
        phase = settled ? .clearing : .reshaping(frameIn: true, settled: false)
        return settled
    }

    /// The morph settled. True when the veil should clear now.
    @discardableResult
    public mutating func morphSettled() -> Bool {
        guard case .reshaping(let frameIn, _) = phase else { return false }
        phase = frameIn ? .clearing : .reshaping(frameIn: false, settled: true)
        return frameIn
    }

    /// The veil has cleared: clicks work again.
    public mutating func cleared() {
        guard phase == .clearing else { return }
        phase = .idle
    }

    /// The connection ended: nothing to wait for.
    public mutating func reset() { phase = .idle }
}
