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
}
