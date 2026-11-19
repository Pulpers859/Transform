import XCTest
import SwiftData
@testable import Transform

/// Assisted pull-ups, chin-ups and dips (owner request, 2026-11-19): the machine's number is
/// HELP, more = easier, so progress means using less of it. Past bodyweight logs stay as they
/// are (owner decision) and are never graded as assisted.
final class AssistedProgressionTests: XCTestCase {
    private let range = RepRange(low: 8, high: 12)

    private func set(_ number: Int, assist: Double?, reps: Int) -> SetLogEntry {
        SetLogEntry(setNumber: number, weightLbs: 0, repsCompleted: reps, assistLbs: assist)
    }

    // MARK: - Storage

    /// Every set stored before this existed has no assistance key and must load unchanged.
    func testOlderSetsDecodeWithoutAssistanceAndNewOnesRoundTrip() throws {
        let legacy = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","setNumber":1,"weightLbs":0,"repsCompleted":10,"notes":""}]"#
        let old = try JSONDecoder().decode([SetLogEntry].self, from: Data(legacy.utf8))
        XCTAssertNil(old.first?.assistLbs)
        XCTAssertEqual(old.first?.weightLbs, 0)

        let stored = [set(1, assist: 40, reps: 10)]
        let reloaded = try JSONDecoder().decode([SetLogEntry].self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(reloaded.first?.assistLbs, 40)
        XCTAssertEqual(reloaded.first?.weightLbs, 0)
    }

    func testAssistedSetsNeverReadAsPlainBodyweight() {
        XCTAssertEqual(formatSetLoad(set(1, assist: 40, reps: 10)), "40 lb assist")
        XCTAssertEqual(formatSetLoad(set(1, assist: nil, reps: 10)), "BW")
        XCTAssertEqual(formatSetLoad(SetLogEntry(setNumber: 1, weightLbs: 135, repsCompleted: 8)), "135 lb")
    }

    // MARK: - Which exercises offer the switch

    func testOnlyThePullUpChinUpAndDipFamilyOffersAssistance() {
        for name in ["Pull-Up (Weighted or Assisted)", "Dip (Assisted or Weighted)", "Chin-Up", "Machine Dip"] {
            XCTAssertTrue(AssistedProgression.supportsAssistance(name), name)
        }
        for name in ["Lat Pulldown", "Neutral-Grip Lat Pulldown", "Cable Face Pull", "Hanging Leg Raise", "Barbell Row"] {
            XCTAssertFalse(AssistedProgression.supportsAssistance(name), name)
        }
    }

    // MARK: - Progress is less help

    func testEverySetAtTheTopOfTheRangeEarnsLessHelp() throws {
        let decision = try XCTUnwrap(AssistedProgression.evaluate(
            sets: [set(1, assist: 40, reps: 12), set(2, assist: 40, reps: 12), set(3, assist: 40, reps: 13)],
            repRange: range))
        XCTAssertEqual(decision.verdict, .lessAssistance)
        XCTAssertEqual(decision.assistLbs, 40)
        let cue = AssistedProgression.cue(for: decision, repRange: range)
        XCTAssertTrue(cue.contains("one setting lighter than 40 lb"), cue)
        XCTAssertFalse(cue.lowercased().contains("add load"), cue)
    }

    /// The working setting is the one used for the most sets; a tie goes to the least help.
    func testWorkingSettingIsTheMostUsedSettingWithTiesToLeastHelp() throws {
        let decision = try XCTUnwrap(AssistedProgression.evaluate(
            sets: [set(1, assist: 40, reps: 12), set(2, assist: 30, reps: 9), set(3, assist: 30, reps: 8)],
            repRange: range))
        XCTAssertEqual(decision.assistLbs, 30)
        XCTAssertEqual(decision.workingSetCount, 2)
        XCTAssertEqual(decision.verdict, .buildReps)
        let tie = try XCTUnwrap(AssistedProgression.workingSets([set(1, assist: 40, reps: 12), set(2, assist: 30, reps: 9)]))
        XCTAssertEqual(tie.assist, 30, "A tie goes to the harder setting")
    }

    /// Independent audit: one hard attempt at a lighter setting must not become the graded
    /// setting, the next session's prefill, or the stall anchor.
    func testOneAttemptAtALighterSettingDoesNotTakeOverTheGrade() throws {
        let sets = [set(1, assist: 10, reps: 2), set(2, assist: 40, reps: 10),
                    set(3, assist: 40, reps: 10), set(4, assist: 40, reps: 10)]
        let decision = try XCTUnwrap(AssistedProgression.evaluate(sets: sets, repRange: range))
        XCTAssertEqual(decision.assistLbs, 40)
        XCTAssertEqual(decision.verdict, .buildReps)
        XCTAssertEqual(AssistedProgression.suggestedAssist(from: sets), 40)
    }

    func testSetsUnderTheRangeHoldThenAskForMoreHelp() throws {
        let sets = [set(1, assist: 40, reps: 6), set(2, assist: 40, reps: 9)]
        let first = try XCTUnwrap(AssistedProgression.evaluate(sets: sets, repRange: range, belowFloorStreak: 1))
        XCTAssertEqual(first.verdict, .holdAssistance)
        XCTAssertEqual(first.belowFloorSetCount, 1)
        let repeated = try XCTUnwrap(AssistedProgression.evaluate(sets: sets, repRange: range, belowFloorStreak: 2))
        XCTAssertEqual(repeated.verdict, .moreAssistance)
        let moreHelp = AssistedProgression.cue(for: repeated, repRange: range)
        XCTAssertTrue(moreHelp.contains("one setting heavier (more help) than 40 lb"), moreHelp)
    }

    func testStallStreakCountsOnlyConsecutiveSessionsAtTheSameSetting() {
        let key = ExerciseWeightEntry.canonicalLookupKey("Pull-Up (Weighted or Assisted)")
        let now = Date()
        func session(_ daysAgo: Double, assist: Double, reps: [Int]) -> WorkoutPerformanceLogSnapshot {
            WorkoutPerformanceLogSnapshot(
                canonicalExerciseKey: key,
                loggedAt: now.addingTimeInterval(-daysAgo * 86_400),
                setLogs: reps.enumerated().map { set($0.offset + 1, assist: assist, reps: $0.element) })
        }
        let history = [session(0, assist: 40, reps: [7, 6]), session(3, assist: 40, reps: [7, 7]),
                       session(6, assist: 50, reps: [6, 6])]
        XCTAssertEqual(AssistedProgression.belowFloorStreak(for: key, from: history, assistLbs: 40, repFloor: 8), 2,
                       "A session at a different setting ends the streak")
    }

    /// Owner decision: past BW logs stay as they are. A session with no assistance recorded is
    /// never graded as assisted, so the bodyweight coaching for it is unchanged.
    func testPlainBodyweightSessionsAreNotGradedAsAssisted() {
        XCTAssertNil(AssistedProgression.evaluate(sets: [set(1, assist: nil, reps: 10)], repRange: range))
        XCTAssertNil(AssistedProgression.suggestedAssist(from: [set(1, assist: nil, reps: 10)]))
    }

    // MARK: - Entering and editing assisted sets

    func testAssistedDraftSavesZeroLoadWithItsHelp() {
        var draft = SetEntryDraft(suggestedAssist: 40)
        XCTAssertEqual(draft.weight, "40")
        draft.reps = "10"
        XCTAssertTrue(draft.canLog)
        var saved: (Double, Int, Double?, Double?)?
        XCTAssertTrue(draft.save(assisted: { saved = ($0, $1, $2, $3); return true }))
        XCTAssertEqual(saved?.0, 0)
        XCTAssertEqual(saved?.1, 10)
        XCTAssertEqual(saved?.3, 40)
    }

    /// The three-value save has nowhere to put the help; it must refuse rather than store the
    /// set as plain bodyweight.
    func testOldSavePathRefusesAnAssistedDraft() {
        var draft = SetEntryDraft(suggestedAssist: 40)
        draft.reps = "10"
        XCTAssertFalse(draft.save { _, _, _ in XCTFail("Assisted set saved without its help"); return true })
    }

    func testAssistedDraftNeedsRealHelp() {
        for help in ["", "0", "BW", "-5", "abc"] {
            var draft = SetEntryDraft(suggestedAssist: 40)
            draft.weight = help
            draft.reps = "10"
            XCTAssertFalse(draft.canLog, help)
        }
    }

    /// The edit sheets rewrite the whole session; an assisted set must keep its help unless
    /// a real added load is typed.
    func testEditSheetsKeepAssistanceUnlessALoadIsTyped() {
        let kept = SessionSetSheetRules.evaluate([
            SessionSetSheetRules.Row(setNumber: 1, weightText: "BW", repsText: "10", rirText: "", assistLbs: 40),
        ])
        XCTAssertEqual(kept.sets.first?.assistLbs, 40)
        XCTAssertEqual(kept.sets.first?.weightLbs, 0)
        let weighted = SessionSetSheetRules.evaluate([
            SessionSetSheetRules.Row(setNumber: 1, weightText: "25", repsText: "8", rirText: "", assistLbs: 40),
        ])
        XCTAssertNil(weighted.sets.first?.assistLbs, "A set with added load is not assisted")
        XCTAssertEqual(weighted.sets.first?.weightLbs, 25)
    }

    // MARK: - The Last/Best summary ignores assisted sets (independent audit, 2026-11-19)

    /// 12 reps with 40 lb of help must never replace a real unassisted best: an all-assisted
    /// session does not shape the summary, and a mixed one only through its unassisted sets.
    @MainActor
    func testAssistedSetsNeverShapeTheWeightSummary() throws {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let allAssisted = ExercisePerformanceLog(exerciseName: "Chin-Up", weightLbs: 0, repsCompleted: 12,
            workoutDayNumber: 1, setLogs: [set(1, assist: 40, reps: 12), set(2, assist: 40, reps: 12)])
        let mixed = ExercisePerformanceLog(exerciseName: "Chin-Up", weightLbs: 0, repsCompleted: 12,
            workoutDayNumber: 1, setLogs: [set(1, assist: nil, reps: 6), set(2, assist: 40, reps: 12)])
        let plainBodyweight = ExercisePerformanceLog(exerciseName: "Chin-Up", weightLbs: 0, repsCompleted: 8,
            workoutDayNumber: 1, setLogs: [set(1, assist: nil, reps: 8)])
        for log in [allAssisted, mixed, plainBodyweight] { context.insert(log) }

        XCTAssertFalse(allAssisted.countsTowardSummary)
        XCTAssertTrue(allAssisted.holdsLoggedWork, "It is still real work, listed in history")
        XCTAssertTrue(mixed.countsTowardSummary)
        XCTAssertEqual(mixed.summarySetLogs.map(\.repsCompleted), [6])
        XCTAssertTrue(plainBodyweight.countsTowardSummary)
        XCTAssertEqual(plainBodyweight.summarySetLogs.count, 1)
    }
}
