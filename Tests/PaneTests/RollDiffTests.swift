import Testing

@testable import Pane

/// Which characters of a rolling number stay and which roll, and their stagger slots.
struct RollDiffTests {
    private func diff(_ old: String, _ new: String) -> RollDiff {
        RollDiff(from: old.map(String.init), to: new.map(String.init))
    }

    @Test func sameLengthRollsOnlyTheChangedDigits() {
        let roll = diff("25.2 of 84", "52.1 of 84")
        #expect(roll.entering == [0: 0, 1: 1, 3: 2])
        #expect(roll.leaving == [0: 0, 1: 1, 3: 2])
        #expect(roll.kept[2] == 2)
        #expect(roll.kept[9] == 9)
        #expect(roll.slots == 3)
    }

    @Test func appendedTextArrivesWithWhitespaceTakingNoSlot() {
        let roll = diff("Version 2.4.1", "Version 2.4.1 · 84 MB")
        #expect(roll.leaving.isEmpty)
        #expect(roll.entering.count == 8)
        #expect(roll.slots == 5)
        #expect(roll.entering[13] == 0)
        #expect(roll.entering[14] == 0)
        #expect(roll.entering[20] == 4)
    }

    @Test func aNewPlacePairsFromTheRight() {
        let roll = diff("9%", "10%")
        #expect(roll.kept == [2: 1])
        #expect(roll.leaving == [0: 1])
        #expect(roll.entering == [0: 0, 1: 1])
        #expect(roll.slots == 2)
    }

    @Test func noChangeKeepsEverything() {
        let roll = diff("62%", "62%")
        #expect(roll.kept.count == 3)
        #expect(roll.slots == 0)
    }
}

/// The recording time's roll: only the seconds that changed move.
struct RecordingTimeRollTests {
    @Test func aTickRollsOnlyTheLastDigit() {
        let roll = RollDiff(from: "0:09".map(String.init), to: "0:10".map(String.init))
        #expect(roll.kept[0] == 0 && roll.kept[1] == 1)
        #expect(roll.slots == 2)
        let next = RollDiff(from: "0:10".map(String.init), to: "0:11".map(String.init))
        #expect(next.slots == 1)
        #expect(next.entering == [3: 0])
    }

    @Test func elapsedFormat() {
        #expect(RecordButton.elapsed(7) == "0:07")
        #expect(RecordButton.elapsed(72) == "1:12")
        #expect(RecordButton.elapsed(720) == "12:00")
    }
}
