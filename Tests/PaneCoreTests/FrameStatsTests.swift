import Testing

@testable import PaneCore

@Suite struct FrameStatsTests {
    @Test func summarisesRateDropsAndLatencyPerInterval() {
        var stats = FrameStats(intervalSeconds: 1)
        let start: UInt64 = 1_000_000_000
        #expect(stats.record(sequence: 1, emulatorTimestamp: start - 10_000, arrival: start) == nil)
        #expect(stats.record(sequence: 2, emulatorTimestamp: start + 490_000, arrival: start + 500_000) == nil)
        // Sequence 3 and 4 never arrived.
        let summary = stats.record(sequence: 5, emulatorTimestamp: start + 970_000, arrival: start + 1_000_000)
        #expect(summary?.frames == 3)
        #expect(summary?.dropped == 2)
        #expect(summary?.framesPerSecond == 3)
        #expect(summary?.meanLatencyMilliseconds == 50.0 / 3)
        #expect(summary?.maxLatencyMilliseconds == 30)
    }

    @Test func startsAFreshWindowAfterEachSummary() {
        var stats = FrameStats(intervalSeconds: 1)
        _ = stats.record(sequence: 1, emulatorTimestamp: 0, arrival: 0)
        #expect(stats.record(sequence: 2, emulatorTimestamp: 1_000_000, arrival: 1_000_000)?.frames == 2)
        #expect(stats.record(sequence: 3, emulatorTimestamp: 1_500_000, arrival: 1_500_000) == nil)
    }
}
