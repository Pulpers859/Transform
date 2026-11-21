import XCTest
@testable import Transform

/// Review of 2026-11-21: logging a set needed reps and RIR typed every time and the row closed
/// after each save. "Same as set N" and opening the next row cut that down; reps still come
/// only from an explicit lifter action.
final class FasterLoggingTests: XCTestCase {
    private func set(_ n: Int, _ weight: Double, _ reps: Int, rir: Double? = nil, assist: Double? = nil) -> SetLogEntry {
        SetLogEntry(setNumber: n, weightLbs: weight, repsCompleted: reps, rir: rir, assistLbs: assist)
    }

    func testRepeatSourceIsTheNearestEarlierSet() {
        let logged = [set(1, 135, 10, rir: 2), set(2, 140, 9, rir: 1)]
        XCTAssertEqual(SetEntryDraft.repeatSource(for: 3, in: logged)?.setNumber, 2)
        XCTAssertEqual(SetEntryDraft.repeatSource(for: 2, in: [set(1, 135, 10), set(3, 145, 8)])?.setNumber, 1)
    }

    func testRepeatSourceFallsBackToALaterSetAndNeverItself() {
        XCTAssertEqual(SetEntryDraft.repeatSource(for: 1, in: [set(1, 100, 8), set(3, 135, 10)])?.setNumber, 3)
        XCTAssertNil(SetEntryDraft.repeatSource(for: 1, in: [set(1, 100, 8)]))
        XCTAssertNil(SetEntryDraft.repeatSource(for: 1, in: []))
    }

    /// Load and reps are copied; RIR is not (audit 2026-11-21), so the RIR ask still fires and
    /// the lifter gives this set's own effort.
    func testRepeatingCopiesLoadAndRepsButNotRIR() {
        var draft = SetEntryDraft.repeating(set(1, 22.25, 12, rir: 1.5))
        XCTAssertEqual([draft.weight, draft.reps, draft.rir], ["22.25", "12", ""])
        XCTAssertTrue(draft.shouldAskForRIR(alreadyAsked: false))
        draft.rir = "1"
        var stored: (Double, Int, Double?)?
        XCTAssertTrue(draft.save(using: { stored = ($0, $1, $2); return true }))
        XCTAssertEqual(stored?.0, 22.25)
        XCTAssertEqual(stored?.1, 12)
        XCTAssertEqual(stored?.2, 1)
    }

    func testRepeatingAnAssistedSetStaysAssisted() {
        var draft = SetEntryDraft.repeating(set(1, 0, 8, rir: 2, assist: 40))
        XCTAssertTrue(draft.isAssisted)
        var assist: Double??
        XCTAssertTrue(draft.save(assisted: { _, _, _, help in assist = help; return true }))
        XCTAssertEqual(assist, .some(40))
    }

    func testRepeatingABodyweightSetStaysBodyweight() {
        let draft = SetEntryDraft.repeating(set(1, 0, 15))
        XCTAssertEqual(draft.parsedWeight, 0)
        XCTAssertEqual(draft.rir, "")
        // No RIR on the source: the RIR ask still applies before a save.
        XCTAssertTrue(draft.shouldAskForRIR(alreadyAsked: false))
    }

    func testNextRowIsTheFirstUnloggedAfterTheOneJustSaved() {
        XCTAssertEqual(SetEntryDraft.nextSetToOpen(after: 1, loggedSetNumbers: [1], programmedCount: 4), 2)
        XCTAssertEqual(SetEntryDraft.nextSetToOpen(after: 3, loggedSetNumbers: [1, 3], programmedCount: 4), 4)
        XCTAssertEqual(SetEntryDraft.nextSetToOpen(after: 4, loggedSetNumbers: [1, 3, 4], programmedCount: 4), 2)
        XCTAssertNil(SetEntryDraft.nextSetToOpen(after: 4, loggedSetNumbers: [1, 2, 3, 4], programmedCount: 4))
    }
}
