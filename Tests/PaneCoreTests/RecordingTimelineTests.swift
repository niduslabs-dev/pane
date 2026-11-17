import Testing

@testable import PaneCore

@Suite struct RecordingTimelineTests {
    private let start: UInt64 = 1_700_000_000_000_000

    @Test func framesKeepTheirTimesFromStart() {
        var timeline = RecordingTimeline(origin: start)
        // The frame on screen at Start is written at 0.
        timeline.wrote(at: 0, timestamp: start - 4_000_000)
        #expect(timeline.time(forFrameAt: start + 250_000) == 250_000)
        timeline.wrote(at: 250_000, timestamp: start + 250_000)
        #expect(timeline.lastWritten == 250_000)
    }

    @Test func aFrameMadeBeforeStartGoesJustAfterTheFirst() {
        var timeline = RecordingTimeline(origin: start)
        timeline.wrote(at: 0, timestamp: start - 4_000_000)
        // Made 5 ms before Start, arriving after it: newer than the frame at 0.
        #expect(timeline.time(forFrameAt: start - 5_000) == RecordingTimeline.step)
    }

    @Test func aFrameStampedNoLaterThanTheLastGoesJustAfterIt() {
        var timeline = RecordingTimeline(origin: start)
        timeline.wrote(at: 900, timestamp: start + 900)
        #expect(timeline.time(forFrameAt: start + 900) == 900 + RecordingTimeline.step)
        #expect(timeline.time(forFrameAt: start + 100) == 900 + RecordingTimeline.step)
    }

    @Test func nothingWrittenYetStartsAtZero() {
        #expect(RecordingTimeline(origin: start).time(forFrameAt: start - 1) == 0)
    }

    @Test func withoutStartTheFirstFrameIsStart() {
        var timeline = RecordingTimeline()
        #expect(timeline.time(forFrameAt: start) == 0)
        timeline.wrote(at: 0, timestamp: start)
        #expect(timeline.origin == start)
        #expect(timeline.time(forFrameAt: start + 16_000) == 16_000)
    }

    @Test func endsAtStop() {
        var timeline = RecordingTimeline(origin: start)
        #expect(timeline.end(stoppedAt: start + 5_000_000) == nil)
        timeline.wrote(at: 0, timestamp: start)
        #expect(timeline.end(stoppedAt: start + 5_000_000) == 5_000_000)
    }

    @Test func stopWithinOneFrameOfTheLastEndsJustAfterIt() {
        var timeline = RecordingTimeline(origin: start)
        timeline.wrote(at: 0, timestamp: start)
        #expect(timeline.end(stoppedAt: start) == RecordingTimeline.step)
        timeline.wrote(at: 40_000, timestamp: start + 40_000)
        #expect(timeline.end(stoppedAt: start + 39_000) == 40_000 + RecordingTimeline.step)
    }
}
