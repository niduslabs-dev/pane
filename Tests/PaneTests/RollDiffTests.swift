import CoreGraphics
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

/// What a roll draws as one whole `Text` and what it draws a character at a time: only the
/// changed characters leave the whole text, so the unchanged ones keep their shape in
/// context (SF's raised colon between digits).
struct RollStageTests {
    /// A monospaced layout, `width` points a character.
    private func layout(_ text: String, width: CGFloat = 10) -> [GlyphProbe.Cluster] {
        text.enumerated().map { GlyphProbe.Cluster(text: String($1), x: CGFloat($0) * width) }
    }

    private func atRest(_ text: String) -> [RollGlyph] {
        layout(text).enumerated().map { RollGlyph(id: $0, text: $1.text, x: $1.x, index: $0, inBase: true) }
    }

    private func stage(_ old: String, _ new: String, reduceMotion: Bool = false) -> [RollGlyph] {
        var id = 100
        return RollGlyph.stage(
            leftover: [], from: atRest(old), to: layout(new), falling: false, reduceMotion: reduceMotion,
            newID: {
                id += 1
                return id
            })
    }

    @Test func aTickKeepsTheColonInTheWholeText() {
        let staged = stage("0:09", "0:10")
        let base = RollBase(text: "0:10", clusters: layout("0:10"), glyphs: staged)
        #expect(base.kept == [0: 0, 1: 0])
        let alone = staged.filter { !$0.inBase }
        #expect(alone.filter { $0.phase == .toLeave }.map(\.text) == ["0", "9"])
        #expect(alone.filter { $0.phase == .arriving }.map(\.text) == ["1", "0"])
    }

    @Test func aWiderTextSlidesTheColonInsideTheWholeText() {
        let staged = stage("9:59", "10:00")
        let base = RollBase(text: "10:00", clusters: layout("10:00"), glyphs: staged)
        // The colon starts at its old x, 10, one place left of its new one.
        #expect(base.kept == [2: -10])
        #expect(staged.filter(\.inBase).map(\.text) == [":"])
    }

    @Test func reduceMotionRollsAMovedCharacterInstead() {
        let staged = stage("9:59", "10:00", reduceMotion: true)
        let base = RollBase(text: "10:00", clusters: layout("10:00"), glyphs: staged)
        #expect(base.kept.isEmpty)
    }

    @Test func aChangeMidRollRollsFromTheTextInOrder() {
        // "9 MB" to "10 MB": the unchanged " MB" is staged before the arriving digits.
        let staged = stage("9 MB", "10 MB")
        let order = RollGlyph.onScreenText(staged).map(\.text)
        #expect(order == ["1", "0", " ", "M", "B"])
    }

    @Test func clustersMapBackFromUTF16Offsets() {
        let clusters = [
            GlyphProbe.Cluster(text: "fi", x: 0), GlyphProbe.Cluster(text: "👍", x: 10),
            GlyphProbe.Cluster(text: "1", x: 20),
        ]
        let starts = GlyphProbe.starts(of: clusters)
        #expect(starts == [0, 2, 4])
        #expect(GlyphProbe.cluster(at: 1, starts: starts) == 0)
        #expect(GlyphProbe.cluster(at: 3, starts: starts) == 1)
        #expect(GlyphProbe.cluster(at: 4, starts: starts) == 2)
        #expect(GlyphProbe.cluster(at: -1, starts: starts) == nil)
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
