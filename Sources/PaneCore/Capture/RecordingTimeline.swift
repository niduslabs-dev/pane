/// Where each frame of a recording goes on the movie's timeline, in microseconds from Start.
///
/// The emulator sends a frame only when its screen changes, so a recording of a still screen
/// gets no frames at all. The recorder therefore writes the frame on screen at Start as time 0
/// and the last frame again at Stop, so the movie always exists and is as long as the
/// recording. Frames in between keep the emulator's own times (wall-clock microseconds, the
/// clock of `Image.timestampUs`), measured from Start.
///
/// A frame made just before Start but arriving after it is newer than the one written at 0,
/// and any frame stamped no later than the one before it is still newer content (the stream
/// is in order), so such frames are placed one microsecond after the last one instead of being
/// dropped.
public struct RecordingTimeline: Equatable, Sendable {
    /// Start, in the frames' clock. Nil until Start is known: without one, the first frame
    /// written becomes Start.
    public private(set) var origin: UInt64?
    /// The time of the last frame written, from Start.
    public private(set) var lastWritten: Int64?

    /// The smallest step between two frames on the timeline.
    public static let step: Int64 = 1

    public init(origin: UInt64? = nil) {
        self.origin = origin
    }

    /// Where a frame stamped `timestamp` goes: its own time from Start, but never at or before
    /// the frame before it, and never before Start.
    public func time(forFrameAt timestamp: UInt64) -> Int64 {
        guard let origin else { return 0 }
        let own = Int64(bitPattern: timestamp &- origin)
        return max(own, lastWritten.map { $0 + Self.step } ?? 0)
    }

    /// Records that a frame stamped `timestamp` was written at `time`, setting Start from it
    /// when there was none.
    public mutating func wrote(at time: Int64, timestamp: UInt64) {
        if origin == nil { origin = timestamp &- UInt64(max(0, time)) }
        lastWritten = time
    }

    /// Where the movie ends for a Stop at `stop` (the frames' clock): the stop time, or just
    /// after the last frame when Stop came within one frame of it. Nil when nothing was written.
    public func end(stoppedAt stop: UInt64) -> Int64? {
        guard let lastWritten else { return nil }
        let own = origin.map { Int64(bitPattern: stop &- $0) } ?? lastWritten
        return max(own, lastWritten + Self.step)
    }
}
