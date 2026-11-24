import XCTest
@testable import Transform

/// Council review of 2026-11-23 (owner-approved item 5; exercise-evidence consult picked
/// option (a), every exercise, one week only).
///
/// After two of three rated sessions flagged pain >= 3, a "Worse" session or effort 5, the
/// session card promised "Next week holds load steady so you can recover." Nothing behind it did:
/// the weight suggestion read only the exercise's own logged reps-in-reserve, so it could still
/// say "add load". The headroom line ("next week adds reps before load") described ordinary
/// double progression as if the ratings had caused it.
final class SessionRatingHoldTests: XCTestCase {
    private let pain = WorkoutSessionFeedbackSnapshot(effort: 3, stimulus: 3, jointPain: 3, performanceRawValue: "Same")
    private let easy = WorkoutSessionFeedbackSnapshot(effort: 2, stimulus: 4, jointPain: 0, performanceRawValue: "Better")
    private let ordinary = WorkoutSessionFeedbackSnapshot(effort: 4, stimulus: 3, jointPain: 1, performanceRawValue: "Same")

    /// Every working set at the top of 8-12: the reps alone earn "add load".
    private let topOfRange = (1...3).map { SetLogEntry(setNumber: $0, weightLbs: 100, repsCompleted: 12) }

    private func verdict(_ signal: WorkoutExerciseEffortSignal, sets: [SetLogEntry]? = nil, streak: Int = 0) -> ClaudeService.ProgressionVerdictKind? {
        WorkoutProgressionEngine.evaluate(
            latestSetLogs: sets ?? topOfRange,
            summaryWeight: 100,
            summaryReps: 12,
            repRange: RepRange(low: 8, high: 12),
            effortSignal: signal,
            belowFloorStreak: streak
        )?.kind
    }

    // 1. Ratings that flag recovery hold the weight even when the reps earned an increase.
    func testPainfulWeekHoldsNextWeeksWeights() {
        let ratings = WorkoutEffortGovernance.signal(
            governingWeek: 3,
            rated: [(week: 2, dayNumber: 8, feedback: pain), (week: 2, dayNumber: 9, feedback: pain)]
        )
        XCTAssertEqual(ratings, .protectRecovery)
        XCTAssertEqual(verdict(.neutral), .addLoad, "baseline: the reps earn an increase")
        let merged = WorkoutEffortGovernance.mergedEffortSignal(.neutral, sessionRatings: ratings)
        XCTAssertEqual(verdict(merged), .holdForRecovery)
    }

    // 2. A hold caused by the ratings says so; one caused by the logged reps keeps its reason.
    func testHoldReasonNamesItsCause() {
        XCTAssertEqual(WorkoutEffortGovernance.holdReason(repsSignal: .neutral, sessionRatings: .protectRecovery),
                       "your recent session ratings flagged pain or a tough week, so recover before adding")
        XCTAssertEqual(WorkoutEffortGovernance.holdReason(repsSignal: .protectRecovery, sessionRatings: .neutral),
                       "recent sets were close to failure, so recover before adding")
        XCTAssertEqual(WorkoutEffortGovernance.holdReason(repsSignal: .protectRecovery, sessionRatings: .protectRecovery),
                       "recent sets were close to failure, so recover before adding")
    }

    // 3. A load the lifter has twice failed to use still comes down: holding it is not recovery.
    func testRepeatedMissStillReducesTheLoadUnderAPainfulWeek() {
        let missed = (1...3).map { SetLogEntry(setNumber: $0, weightLbs: 100, repsCompleted: 6) }
        let merged = WorkoutEffortGovernance.mergedEffortSignal(.neutral, sessionRatings: .protectRecovery)
        XCTAssertEqual(verdict(merged, sets: missed, streak: 2), .reduceLoad)
    }

    // 4. One week only: week 2's ratings govern week 3, not week 4.
    func testAPainfulWeekDoesNotCarryTwoWeeksForward() {
        let rated = [(week: 2, dayNumber: 8, feedback: pain), (week: 2, dayNumber: 9, feedback: pain),
                     (week: 3, dayNumber: 15, feedback: ordinary), (week: 3, dayNumber: 16, feedback: ordinary)]
        XCTAssertEqual(WorkoutEffortGovernance.signal(governingWeek: 3, rated: rated), .protectRecovery)
        XCTAssertEqual(WorkoutEffortGovernance.signal(governingWeek: 4, rated: rated), .neutral)
    }

    // 5. Neutral or headroom ratings never change the verdict.
    func testNeutralAndHeadroomRatingsChangeNothing() {
        for reps in [WorkoutExerciseEffortSignal.neutral, .progressionHeadroom, .protectRecovery, .insufficientEvidence] {
            XCTAssertEqual(WorkoutEffortGovernance.mergedEffortSignal(reps, sessionRatings: .neutral), reps)
            XCTAssertEqual(WorkoutEffortGovernance.mergedEffortSignal(reps, sessionRatings: .progressionHeadroom), reps)
        }
        XCTAssertEqual(WorkoutEffortGovernance.signal(from: [easy, easy]), .progressionHeadroom)
    }

    // The card lines say only what the app does.
    func testCardLinesMatchWhatTheAppDoes() {
        XCTAssertEqual(WorkoutEffortGovernance.cardLine(for: .protectRecovery),
                       "Next week, your weight suggestions hold steady so you can recover.")
        XCTAssertEqual(WorkoutEffortGovernance.cardLine(for: .progressionHeadroom),
                       "Good week — keep building reps at your current weights, then add weight once every set reaches the top of its range.")
        XCTAssertNil(WorkoutEffortGovernance.cardLine(for: .neutral))
    }

    // MARK: - Follow-up review 2026-11-24

    /// The assisted cue held too: "use less help" becomes "hold this setting" in a protected week.
    func testAProtectedWeekHoldsTheAssistanceSetting() {
        let assisted = (1...3).map { SetLogEntry(setNumber: $0, weightLbs: 0, repsCompleted: 12, assistLbs: 40) }
        let range = RepRange(low: 8, high: 12)
        XCTAssertEqual(AssistedProgression.evaluate(sets: assisted, repRange: range)?.verdict, .lessAssistance)
        XCTAssertEqual(AssistedProgression.evaluate(sets: assisted, repRange: range, protectRecovery: true)?.verdict, .holdAssistance)
        // A setting twice missed still gets more help.
        let missed = (1...3).map { SetLogEntry(setNumber: $0, weightLbs: 0, repsCompleted: 5, assistLbs: 40) }
        XCTAssertEqual(AssistedProgression.evaluate(sets: missed, repRange: range, belowFloorStreak: 2, protectRecovery: true)?.verdict, .moreAssistance)
    }

    /// A rep-range change may translate the load; in a protected week it may not go UP.
    func testAProtectedWeekCapsAnUpwardTranslation() {
        XCTAssertEqual(WorkoutEffortGovernance.cappedTranslatedLoad(210, lastWorkingWeight: 200, sessionRatings: .protectRecovery), 200)
        XCTAssertEqual(WorkoutEffortGovernance.cappedTranslatedLoad(185, lastWorkingWeight: 200, sessionRatings: .protectRecovery), 185)
        XCTAssertEqual(WorkoutEffortGovernance.cappedTranslatedLoad(210, lastWorkingWeight: 200, sessionRatings: .neutral), 210)
    }

    /// No promise for a week the ratings cannot govern: the week before the deload (the deload
    /// says go lighter) and the deload week itself (a new block follows).
    func testCardLineOnlyWhereTheNextWeekIsAnOrdinaryWeek() {
        XCTAssertNotNil(WorkoutEffortGovernance.cardLine(for: .protectRecovery, ratedWeek: 1, blockWeeks: 4))
        XCTAssertNotNil(WorkoutEffortGovernance.cardLine(for: .protectRecovery, ratedWeek: 2, blockWeeks: 4))
        XCTAssertNil(WorkoutEffortGovernance.cardLine(for: .protectRecovery, ratedWeek: 3, blockWeeks: 4))
        XCTAssertNil(WorkoutEffortGovernance.cardLine(for: .progressionHeadroom, ratedWeek: 3, blockWeeks: 4))
        XCTAssertNil(WorkoutEffortGovernance.cardLine(for: .protectRecovery, ratedWeek: 4, blockWeeks: 4))
    }

    /// Exercise-evidence consult 2026-11-24, pick (c): effort 5 is what week 3 asks for, so
    /// effort alone does not hold weights. It still reaches the AI's instructions.
    func testHardSessionsAloneDoNotHoldWeights() {
        let hard = WorkoutSessionFeedbackSnapshot(effort: 5, stimulus: 4, jointPain: 1, performanceRawValue: "Same")
        let rated = [(week: 2, dayNumber: 8, feedback: hard), (week: 2, dayNumber: 9, feedback: hard)]
        XCTAssertEqual(WorkoutEffortGovernance.signal(from: [hard, hard]), .protectRecovery)
        XCTAssertNotEqual(WorkoutEffortGovernance.signal(governingWeek: 3, rated: rated), .protectRecovery)
        XCTAssertNil(WorkoutEffortGovernance.cardLine(for: WorkoutEffortGovernance.signal(governingWeek: 3, rated: rated),
                                                      ratedWeek: 2, blockWeeks: 4))
    }

    /// "Worse" twice holds, as pain does.
    func testTwoWorseSessionsHoldWeights() {
        let worse = WorkoutSessionFeedbackSnapshot(effort: 3, stimulus: 3, jointPain: 0, performanceRawValue: "Worse")
        let rated = [(week: 1, dayNumber: 1, feedback: worse), (week: 1, dayNumber: 2, feedback: worse)]
        XCTAssertEqual(WorkoutEffortGovernance.signal(governingWeek: 2, rated: rated), .protectRecovery)
    }

    // MARK: - Round 3: what the AI is told (exercise-evidence consult 2026-11-24)

    /// A hard week without pain must not tell the AI to hold loads the app is raising.
    func testAHardWeekWithoutPainDoesNotTellTheAIToHold() {
        let hard = WorkoutSessionFeedbackSnapshot(effort: 5, stimulus: 4, jointPain: 1, performanceRawValue: "Same")
        let text = WorkoutEffortGovernance.guidance(forWeek: [hard, hard])
        XCTAssertTrue(text.hasPrefix("Governance signal: hard sessions without pain or a performance drop."), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("hold load"), text)
    }

    /// A painful week keeps the protect text, without asking the AI to cut sets (which the
    /// menu-locked prompt forbids and which cost a second paid call).
    func testAPainfulWeekTellsTheAIThatTheAppIsHolding() {
        let text = WorkoutEffortGovernance.guidance(forWeek: [pain, pain])
        XCTAssertTrue(text.contains("The app is holding load progression this week"), text)
        XCTAssertFalse(text.contains("isolation set"), text)
    }

    /// A week with one painful session and one hard pain-free session does not hold loads, and
    /// the AI must not be told it was "without pain" (exercise-evidence consult, round 3 check).
    func testAMixedWeekIsNotDescribedAsPainFree() {
        let hard = WorkoutSessionFeedbackSnapshot(effort: 5, stimulus: 4, jointPain: 1, performanceRawValue: "Same")
        let text = WorkoutEffortGovernance.guidance(forWeek: [pain, hard])
        XCTAssertFalse(text.contains("without pain"), text)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("hold load"), text)
        XCTAssertTrue(text.contains("The app's load verdicts below stand"), text)
    }
}
