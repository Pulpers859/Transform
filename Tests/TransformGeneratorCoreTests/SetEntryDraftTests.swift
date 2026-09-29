import XCTest
@testable import Transform

final class SetEntryDraftTests: XCTestCase {
    func testDisplayedValidResultsReachSaveWithIdenticalNormalization() {
        for padding in ["", " ", "\n", "\r\n", "\t"] {
            var draft = SetEntryDraft()
            draft.weight = padding + "150" + padding
            draft.reps = padding + "12" + padding
            draft.rir = padding + "2" + padding
            XCTAssertTrue(draft.canLog)
            var calls = 0
            XCTAssertTrue(draft.save { weight, reps, rir in
                calls += 1
                XCTAssertEqual(weight, 150)
                XCTAssertEqual(reps, 12)
                XCTAssertEqual(rir, 2)
                return true
            })
            XCTAssertEqual(calls, 1)
        }
    }
    func testSwitchingAwayFromAnEditKeepsSavedResultVisible() {
        XCTAssertEqual(SetEntryDraft.rowState(hasSavedSet: true, isActive: false, isEditing: true), .saved)
        XCTAssertEqual(SetEntryDraft.rowState(hasSavedSet: true, isActive: true, isEditing: true), .entry)
        XCTAssertEqual(SetEntryDraft.rowState(hasSavedSet: true, isActive: true, isEditing: false), .saved)
        XCTAssertEqual(SetEntryDraft.rowState(hasSavedSet: false, isActive: true, isEditing: false), .entry)
        XCTAssertEqual(SetEntryDraft.rowState(hasSavedSet: false, isActive: false, isEditing: false), .idle)
    }

    func testSuggestedLoadNeverInventsRepsOrEffort() {
        for weight: Double? in [nil, 0, 1, 2.5, 30, 200, .nan, .infinity, -5] {
            let draft = SetEntryDraft(suggestedWeight: weight)
            XCTAssertEqual(draft.reps, "")
            XCTAssertEqual(draft.rir, "")
            XCTAssertFalse(draft.canLog)
        }
    }

    func testInvalidResultsNeverReachStorage() {
        for weight in ["", "0", "-1", "nan", "inf", "1e999", "abc"] {
            var draft = SetEntryDraft()
            draft.weight = weight
            draft.reps = "12"
            XCTAssertFalse(draft.save { _, _, _ in XCTFail("Invalid load saved"); return true })
        }
        for reps in ["", "0", "-1", "12.5", "abc", "99999999999999999999999"] {
            var draft = SetEntryDraft(suggestedWeight: 30)
            draft.reps = reps
            XCTAssertFalse(draft.save { _, _, _ in XCTFail("Invalid reps saved"); return true })
        }
        for rir in ["-1", "7", "nan", "inf", "abc"] {
            var draft = SetEntryDraft(suggestedWeight: 30)
            draft.reps = "12"
            draft.rir = rir
            XCTAssertFalse(draft.canLog)
        }
    }

    func testFailurePreservesDraftAndSuccessClearsIt() {
        var draft = SetEntryDraft(suggestedWeight: 30)
        draft.reps = "11"
        draft.rir = "2"
        let before = draft
        XCTAssertFalse(draft.save { _, _, _ in false })
        XCTAssertEqual(draft, before)
        XCTAssertTrue(draft.save { load, reps, rir in
            XCTAssertEqual(load, 30)
            XCTAssertEqual(reps, 11)
            XCTAssertEqual(rir, 2)
            return true
        })
        XCTAssertEqual(draft, SetEntryDraft())
        XCTAssertFalse(draft.save { _, _, _ in XCTFail("Saved twice without new results"); return true })
    }

    func testBodyweightAndLocaleParsingRequireActualReps() {
        var draft = SetEntryDraft()
        draft.weight = " bw "
        XCTAssertFalse(draft.canLog)
        draft.reps = " 12 "
        XCTAssertEqual(draft.parsedWeight, 0)
        XCTAssertTrue(draft.canLog)
        draft.weight = "32,5"
        draft.rir = "2,5"
        XCTAssertEqual(draft.parsedWeight, 32.5)
        XCTAssertEqual(draft.parsedRIR, 2.5)
    }

    func testDraftsAreIndependentAndRetriesDoNotLoseResults() {
        var drafts: [Int: SetEntryDraft] = [:]
        for set in 1...100 {
            drafts[set] = SetEntryDraft(suggestedWeight: Double(set * 5))
            XCTAssertFalse(drafts[set]!.canLog)
            drafts[set]!.reps = String(set % 20 + 1)
        }
        for set in 1...100 {
            let before = drafts[set]!
            for _ in 0..<10 {
                XCTAssertFalse(drafts[set]!.save { _, _, _ in false })
                XCTAssertEqual(drafts[set], before)
            }
            XCTAssertTrue(drafts[set]!.save { load, reps, _ in
                load == Double(set * 5) && reps == set % 20 + 1
            })
        }
        XCTAssertTrue(drafts.values.allSatisfy { $0 == SetEntryDraft() })
    }
}
