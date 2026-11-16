import Foundation

/// Frame rate, dropped frames (gaps in `Image.seq`) and latency (arrival time minus the
/// emulator's `timestampUs`, both wall-clock microseconds), summarised once per interval.
public struct FrameStats: Sendable {
    public struct Summary: Sendable, Equatable {
        public var frames: Int
        public var dropped: Int
        public var framesPerSecond: Double
        public var meanLatencyMilliseconds: Double
        public var maxLatencyMilliseconds: Double
    }

    private let intervalMicroseconds: UInt64
    private var windowStart: UInt64?
    private var lastSequence: UInt32?
    private var frames = 0
    private var dropped = 0
    private var latencySum: Double = 0
    private var latencyMax: Double = 0

    public init(intervalSeconds: Double) {
        intervalMicroseconds = UInt64(intervalSeconds * 1_000_000)
    }

    /// Wall-clock now in microseconds, the clock `timestampUs` uses.
    public static func nowMicroseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000_000)
    }

    /// Records one frame; returns a summary when the interval has passed.
    public mutating func record(
        sequence: UInt32, emulatorTimestamp: UInt64, arrival: UInt64 = nowMicroseconds()
    ) -> Summary? {
        if let last = lastSequence, sequence > last + 1 { dropped += Int(sequence - last - 1) }
        lastSequence = sequence
        let microsecondsPerMillisecond = 1000.0
        let latency = Double(Int64(bitPattern: arrival &- emulatorTimestamp)) / microsecondsPerMillisecond
        frames += 1
        latencySum += latency
        latencyMax = max(latencyMax, latency)
        let start = windowStart ?? arrival
        windowStart = start
        let elapsed = arrival - start
        guard elapsed >= intervalMicroseconds else { return nil }
        let summary = Summary(
            frames: frames, dropped: dropped, framesPerSecond: Double(frames) / (Double(elapsed) / 1_000_000),
            meanLatencyMilliseconds: latencySum / Double(frames), maxLatencyMilliseconds: latencyMax)
        windowStart = arrival
        frames = 0
        dropped = 0
        latencySum = 0
        latencyMax = 0
        return summary
    }
}
