import XCTest
@testable import Transform

/// Both operations here sit on the most expensive path in the app. A false positive in
/// `containsPhrase` is a HARD generation failure that discards every paid AI candidate for the
/// week and skips the correction pass; a bad sentence split shows the lifter a load that is not
/// the one written, and blinds the validator's contradiction check to any decimal weight.
final class CoachingProseTests: XCTestCase {

    // MARK: - Whole-phrase matching

    /// The two real regressions: a banned fragment that is the PREFIX of an innocent word.
    /// Both sentences are exactly the ROM/control phrasing the system prompt asks for.
    func testBannedFragmentDoesNotFireOnALongerWord() {
        XCTAssertFalse(
            CoachingProse.containsPhrase("brace hard and increase total time under tension", "increase to"),
            #""increase to" must not match "increase total""#
        )
        XCTAssertFalse(
            CoachingProse.containsPhrase("stop when you clearly feel the chest lengthen", "when you clear"),
            #""when you clear" must not match "when you clearly""#
        )
    }

    func testBannedFragmentStillFiresOnTheRealPhrase() {
        XCTAssertTrue(CoachingProse.containsPhrase("increase to 70 lb once reps are smooth", "increase to"))
        XCTAssertTrue(CoachingProse.containsPhrase("when you clear 12 reps, stop", "when you clear"))
        XCTAssertTrue(CoachingProse.containsPhrase("add load next session", "add load"))
    }

    /// Tightening the match must not quietly stop banning ordinary inflections.
    func testTrailingPluralStillCounts() {
        XCTAssertTrue(CoachingProse.containsPhrase("hit your progression targets", "progression target"))
        XCTAssertTrue(CoachingProse.containsPhrase("add loads gradually", "add load"))
    }

    /// A plural allowance must not become a licence to match any longer word.
    func testPluralAllowanceDoesNotOpenTheDoorAgain() {
        XCTAssertFalse(CoachingProse.containsPhrase("add loadsomething weird", "add load"))
    }

    func testPhraseAtStringBoundariesIsMatched() {
        XCTAssertTrue(CoachingProse.containsPhrase("add load", "add load"))
        XCTAssertTrue(CoachingProse.containsPhrase("add load.", "add load"))
    }

    /// A first, unbounded occurrence must not hide a later, properly bounded one.
    func testLaterBoundedOccurrenceIsFoundAfterAnUnboundedOne() {
        XCTAssertTrue(
            CoachingProse.containsPhrase("increase total time, then increase to 70 lb", "increase to"),
            "Scanning must continue past a rejected match"
        )
    }

    func testEmptyPhraseNeverMatches() {
        XCTAssertFalse(CoachingProse.containsPhrase("anything at all", ""))
    }

    func testContainsAnyPhraseMirrorsTheSingleCase() {
        let fragments = ["add load", "increase to"]
        XCTAssertFalse(CoachingProse.containsAnyPhrase("increase total time under tension", fragments))
        XCTAssertTrue(CoachingProse.containsAnyPhrase("increase to 70 lb", fragments))
    }

    // MARK: - Sentence splitting

    /// The shipping bug: the card rendered "Work at 22." — half a pound under the written load.
    func testDecimalLoadDoesNotSplitTheSentence() {
        let sentences = CoachingProse.sentences(in: "Work at 22.5 lb and go heavier when it feels easy.")
        XCTAssertEqual(sentences.count, 1, "A decimal load must not end a sentence: \(sentences)")
        XCTAssertTrue(sentences[0].contains("22.5"))
    }

    func testRealSentenceBoundariesStillSplit() {
        let sentences = CoachingProse.sentences(in: "Keep ribs stacked. Brace hard! Ready?")
        XCTAssertEqual(sentences, ["Keep ribs stacked.", "Brace hard!", "Ready?"])
    }

    func testDecimalAndRealBoundaryTogether() {
        let sentences = CoachingProse.sentences(in: "Load 47.5 lb. Control the eccentric.")
        XCTAssertEqual(sentences, ["Load 47.5 lb.", "Control the eccentric."])
    }

    func testWhitespaceIsCollapsedAcrossLines() {
        XCTAssertEqual(CoachingProse.sentences(in: "Brace\n  hard."), ["Brace hard."])
    }

    func testEmptyAndWhitespaceOnlyInputProduceNoSentences() {
        XCTAssertTrue(CoachingProse.sentences(in: "").isEmpty)
        XCTAssertTrue(CoachingProse.sentences(in: "   \n ").isEmpty)
    }

    /// A trailing terminator must not manufacture an empty trailing sentence.
    func testNoEmptyTrailingSentence() {
        XCTAssertEqual(CoachingProse.sentences(in: "Brace hard."), ["Brace hard."])
    }
}
