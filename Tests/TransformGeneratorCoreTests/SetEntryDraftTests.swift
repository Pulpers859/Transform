import XCTest
import SwiftData
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

    /// A missing RIR is asked for once, then the set may be logged without it; a set that
    /// cannot be logged, or already has RIR, is never held back by the ask.
    func testFirstLogTapWithoutRIRAsksForItOnce() {
        var draft = SetEntryDraft()
        draft.weight = "150"
        draft.reps = "10"
        XCTAssertTrue(draft.shouldAskForRIR(alreadyAsked: false))
        XCTAssertFalse(draft.shouldAskForRIR(alreadyAsked: true))
        draft.rir = " 2 "
        XCTAssertFalse(draft.shouldAskForRIR(alreadyAsked: false))
        draft.rir = ""
        draft.reps = ""
        XCTAssertFalse(draft.shouldAskForRIR(alreadyAsked: false))
    }

    // MARK: - Whole-session sheets (card Edit sheet, history Edit Log sheet)

    private typealias Row = SessionSetSheetRules.Row

    /// Owner path, bug audit 2026-11-17 F1: Dip set 1 logged inline as BW, set 2 at 25 lb.
    /// Opening Edit to fix a rep count and saving deleted set 1 from history.
    func testSessionSheetKeepsBodyweightSetsWhenSaving() {
        let rows = [
            Row(setNumber: 1, weightText: SessionSetSheetRules.weightText(for: 0), repsText: "10", rirText: ""),
            Row(setNumber: 2, weightText: SessionSetSheetRules.weightText(for: 25), repsText: "8", rirText: "2"),
        ]
        let outcome = SessionSetSheetRules.evaluate(rows)
        XCTAssertTrue(outcome.canSave)
        XCTAssertEqual(outcome.sets.map(\.setNumber), [1, 2], "No logged set may disappear on save")
        XCTAssertEqual(outcome.sets.map(\.weightLbs), [0, 25])
        XCTAssertEqual(outcome.sets.map(\.repsCompleted), [10, 8])
        XCTAssertEqual(outcome.sets.map(\.rir), [nil, 2])
    }

    /// A session logged entirely at bodyweight (Hanging Leg Raise) could not be saved at all,
    /// and the sheet's number keypad cannot type "BW", so 0 must work too.
    func testSessionSheetCanSaveAnAllBodyweightSessionTypedAsZeroOrBW() {
        for text in ["0", "BW", "bw", " 0 ", "0,0"] {
            let outcome = SessionSetSheetRules.evaluate([
                Row(setNumber: 1, weightText: text, repsText: "12", rirText: ""),
                Row(setNumber: 2, weightText: text, repsText: "11", rirText: ""),
            ])
            XCTAssertTrue(outcome.canSave, text)
            XCTAssertEqual(outcome.sets.map(\.weightLbs), [0, 0], text)
        }
    }

    /// A row the sheet cannot read must block the save and be named, never be dropped: the
    /// save rewrites the whole session, so a dropped row is a deleted set.
    func testSessionSheetBlocksRatherThanDropsAnUnreadableRow() {
        let unreadable: [Row] = [
            Row(setNumber: 2, weightText: "abc", repsText: "8", rirText: ""),
            Row(setNumber: 2, weightText: "-5", repsText: "8", rirText: ""),
            Row(setNumber: 2, weightText: "", repsText: "8", rirText: ""),
            Row(setNumber: 2, weightText: "40", repsText: "eight", rirText: ""),
            Row(setNumber: 2, weightText: "40", repsText: "-1", rirText: ""),
            Row(setNumber: 2, weightText: "40", repsText: "8", rirText: "9"),
        ]
        for bad in unreadable {
            let outcome = SessionSetSheetRules.evaluate([
                Row(setNumber: 1, weightText: "40", repsText: "10", rirText: ""), bad,
            ])
            XCTAssertFalse(outcome.canSave, "\(bad)")
            XCTAssertEqual(outcome.unreadableSetNumbers, [2], "\(bad)")
            XCTAssertTrue(SessionSetSheetRules.blockingMessage(for: outcome)?.contains("Set 2") == true, "\(bad)")
        }
        // A row with nothing in it holds nothing to lose and does not block.
        let withBlank = SessionSetSheetRules.evaluate([
            Row(setNumber: 1, weightText: "40", repsText: "10", rirText: ""),
            Row(setNumber: 2, weightText: " ", repsText: "", rirText: ""),
        ])
        XCTAssertTrue(withBlank.canSave)
        XCTAssertEqual(withBlank.sets.map(\.setNumber), [1])
        XCTAssertNil(SessionSetSheetRules.blockingMessage(for: withBlank))
        // A 0-rep set is how both sheets stored blank reps; such a session must still save.
        let storedZeroReps = SessionSetSheetRules.evaluate([
            Row(setNumber: 1, weightText: "40", repsText: "0", rirText: ""),
        ])
        XCTAssertTrue(storedZeroReps.canSave)
        XCTAssertEqual(storedZeroReps.sets.map(\.repsCompleted), [0])
    }

    /// The legacy "1 lb" bodyweight stand-in is reinterpreted, never rewritten: showing it as BW
    /// would turn it into 0 on the next save.
    func testLegacyOneLbStandInIsShownAsItsNumber() {
        XCTAssertEqual(SessionSetSheetRules.weightText(for: 1), "1")
        XCTAssertEqual(SessionSetSheetRules.weight(from: SessionSetSheetRules.weightText(for: 1)), 1)
        XCTAssertEqual(SessionSetSheetRules.weight(from: SessionSetSheetRules.weightText(for: 0)), 0)
        XCTAssertEqual(SessionSetSheetRules.weight(from: SessionSetSheetRules.weightText(for: 102.5)), 102.5)
    }

    /// Editing or deleting one session of a bodyweight-only exercise rebuilt its summary from
    /// logs above 0 lb only, found none, and deleted the exercise's last/best summary.
    @MainActor
    func testBodyweightSessionCountsAsLoggedWorkForTheSummaryRebuild() throws {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let bodyweight = ExercisePerformanceLog(exerciseName: "Hanging Leg Raise", weightLbs: 0, repsCompleted: 12,
            workoutDayNumber: 1, setLogs: [SetLogEntry(setNumber: 1, weightLbs: 0, repsCompleted: 12)])
        let legacyBodyweight = ExercisePerformanceLog(exerciseName: "Hanging Leg Raise", weightLbs: 0, repsCompleted: 10)
        let emptyShell = ExercisePerformanceLog(exerciseName: "Hanging Leg Raise", weightLbs: 0, workoutDayNumber: 1)
        let loaded = ExercisePerformanceLog(exerciseName: "Dip (Assisted or Weighted)", weightLbs: 25, repsCompleted: 8,
            workoutDayNumber: 1, setLogs: [SetLogEntry(setNumber: 1, weightLbs: 25, repsCompleted: 8)])
        for log in [bodyweight, legacyBodyweight, emptyShell, loaded] { context.insert(log) }
        XCTAssertTrue(bodyweight.holdsLoggedWork)
        XCTAssertTrue(legacyBodyweight.holdsLoggedWork)
        XCTAssertTrue(loaded.holdsLoggedWork)
        XCTAssertFalse(emptyShell.holdsLoggedWork, "A log with no reps anywhere records no work")
    }
}
