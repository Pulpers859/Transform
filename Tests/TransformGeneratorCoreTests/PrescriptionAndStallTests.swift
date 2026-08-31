import XCTest
@testable import Transform

/// Stress coverage for the three rules added so the app stops misreading its own history:
///
///  * a session records what it was PRESCRIBED, so "2 of 2, finished" is no longer
///    indistinguishable from "2 of 3, stopped early", and an absent prescription reads as
///    absent rather than as zero;
///  * a load that has failed the rep floor across repeated sessions earns `.reduceLoad`
///    instead of another round of "hold and build reps", which was the only sentence the
///    engine previously owned;
///  * every pre-existing verdict is byte-for-byte unchanged when no stall is present, since
///    the stall count defaults to zero for every caller that does not pass one.
@MainActor
final class PrescriptionAndStallTests: XCTestCase {

    private let service = ClaudeService.shared
    private let range = RepRange(low: 15, high: 20)

    private func set(_ n: Int, weight: Double, reps: Int, rir: Double? = nil) -> SetLogEntry {
        SetLogEntry(setNumber: n, weightLbs: weight, repsCompleted: reps, rir: rir)
    }

    private func session(_ daysAgo: Int, weight: Double, reps: [Int], key: String = "face pull") -> WorkoutPerformanceLogSnapshot {
        WorkoutPerformanceLogSnapshot(
            canonicalExerciseKey: key,
            loggedAt: Date(timeIntervalSince1970: 1_000_000 - Double(daysAgo) * 86_400),
            setLogs: reps.enumerated().map { set($0.offset + 1, weight: weight, reps: $0.element) }
        )
    }

    private func streak(_ snapshots: [WorkoutPerformanceLogSnapshot], weight: Double = 55, floor: Int = 15) -> Int {
        WorkoutProgressionEngine.belowFloorStreak(
            for: "face pull", from: snapshots, workingWeight: weight, repFloor: floor
        )
    }

    // MARK: - Recording what was prescribed

    func testAnUnrecordedPrescriptionReadsAsAbsentNotAsZero() {
        let log = ExercisePerformanceLog(exerciseName: "Cable Face Pull", weightLbs: 55, repsCompleted: 14)
        XCTAssertNil(log.recordedPrescribedSets,
                     "0 must not be mistaken for a real prescription — that calls every legacy session complete")
        XCTAssertNil(log.recordedRepRange)
    }

    func testARecordedPrescriptionIsReadBack() {
        let log = ExercisePerformanceLog(
            exerciseName: "Cable Face Pull", weightLbs: 55, repsCompleted: 14,
            prescribedSets: 2, prescribedReps: "15-20"
        )
        XCTAssertEqual(log.recordedPrescribedSets, 2)
        XCTAssertEqual(log.recordedRepRange, RepRange(low: 15, high: 20))
    }

    /// The distinction the screenshots could not show and the database could not answer.
    func testTwoOfTwoAndTwoOfThreeAreNowDifferentSessions() {
        let finished = ExercisePerformanceLog(exerciseName: "Cable Face Pull", weightLbs: 55, prescribedSets: 2)
        let cutShort = ExercisePerformanceLog(exerciseName: "Cable Face Pull", weightLbs: 55, prescribedSets: 3)
        let loggedSets = 2
        XCTAssertFalse(loggedSets < (finished.recordedPrescribedSets ?? 0), "2 of 2 is finished")
        XCTAssertTrue(loggedSets < (cutShort.recordedPrescribedSets ?? 0), "2 of 3 is not")
    }

    func testAnUnparseableRecordedRangeFallsBackRatherThanCrashing() {
        for junk in ["", "as many as possible", "AMRAP", "0"] {
            let log = ExercisePerformanceLog(exerciseName: "X", weightLbs: 10, prescribedReps: junk)
            XCTAssertNil(log.recordedRepRange, "'\(junk)' is not a rep range")
        }
    }

    func testASingleRepPrescriptionIsAValidRange() {
        let log = ExercisePerformanceLog(exerciseName: "X", weightLbs: 10, prescribedReps: "8")
        XCTAssertEqual(log.recordedRepRange, RepRange(low: 8, high: 8))
    }

    // MARK: - Stall detection

    func testTwoConsecutiveMissesAtTheSameLoadIsAStall() {
        XCTAssertEqual(streak([session(0, weight: 55, reps: [14, 12]), session(7, weight: 55, reps: [14, 13])]), 2)
    }

    func testOneMissAloneIsNotAStall() {
        XCTAssertEqual(streak([session(0, weight: 55, reps: [14, 12]), session(7, weight: 55, reps: [16, 15])]), 1,
                       "A session that reached the floor ends the streak — the load demonstrably works")
    }

    func testAMissAtADifferentLoadDoesNotExtendTheStreak() {
        XCTAssertEqual(streak([session(0, weight: 55, reps: [14, 12]), session(7, weight: 45, reps: [10, 9])]), 1,
                       "A different weight is a different experiment, not a continuation")
    }

    func testTheStreakCountsFromTheNewestSessionRegardlessOfArrayOrder() {
        let shuffled = [session(7, weight: 55, reps: [14, 13]), session(21, weight: 55, reps: [16, 16]), session(0, weight: 55, reps: [14, 12])]
        XCTAssertEqual(streak(shuffled), 2, "Ordering must come from loggedAt, never from array position")
    }

    func testAnInRangeNewestSessionMeansNoStreakAtAll() {
        XCTAssertEqual(streak([session(0, weight: 55, reps: [17, 16]), session(7, weight: 55, reps: [14, 12])]), 0)
    }

    func testEmptyAndForeignHistoryProduceNoStreak() {
        XCTAssertEqual(streak([]), 0)
        XCTAssertEqual(streak([session(0, weight: 55, reps: [14, 12], key: "lateral raise")]), 0,
                       "Another exercise's stall is not this one's")
    }

    func testNearIdenticalLoadsCountAsTheSameLoadButRealJumpsDoNot() {
        XCTAssertEqual(streak([session(0, weight: 55, reps: [14]), session(7, weight: 55.5, reps: [13])]), 2,
                       "Half a pound apart is the same working load")
        XCTAssertEqual(streak([session(0, weight: 55, reps: [14]), session(7, weight: 60, reps: [13])]), 1,
                       "Five pounds apart is not")
    }

    func testTheStreakIsBoundedByTheLookbackWindow() {
        let many = (0..<8).map { session($0 * 7, weight: 55, reps: [12, 12]) }
        XCTAssertEqual(
            WorkoutProgressionEngine.belowFloorStreak(
                for: "face pull", from: many, workingWeight: 55, repFloor: 15, lookback: 3
            ),
            3, "Never reports more sessions than it actually looked at"
        )
    }

    // MARK: - The reduce-load verdict

    private func decide(_ logs: [SetLogEntry], streak: Int, effort: WorkoutExerciseEffortSignal = .insufficientEvidence) throws -> WorkoutProgressionDecision {
        try XCTUnwrap(WorkoutProgressionEngine.evaluate(
            latestSetLogs: logs,
            summaryWeight: logs.first?.weightLbs,
            summaryReps: logs.first?.repsCompleted,
            repRange: range,
            effortSignal: effort,
            belowFloorStreak: streak
        ))
    }

    func testAStalledLoadIsReducedRatherThanHeldAgain() throws {
        let result = try decide([set(1, weight: 55, reps: 14), set(2, weight: 55, reps: 12)], streak: 2)
        XCTAssertEqual(result.kind, .reduceLoad)
        XCTAssertEqual(result.belowFloorStreak, 2)
    }

    func testTheFirstMissIsStillHeld() throws {
        let result = try decide([set(1, weight: 55, reps: 14), set(2, weight: 55, reps: 12)], streak: 1)
        XCTAssertEqual(result.kind, .holdBelowRange,
                       "One hard session proves nothing about the load")
    }

    func testAStreakCannotReduceALoadThatIsMeetingItsTarget() throws {
        let result = try decide([set(1, weight: 55, reps: 17), set(2, weight: 55, reps: 16)], streak: 3)
        XCTAssertEqual(result.kind, .addRepsInRange,
                       "Only a below-floor session can be a stall; the count alone must never demote a good one")
    }

    func testReduceLoadOutranksRecoveryProtection() throws {
        let result = try decide([set(1, weight: 55, reps: 14), set(2, weight: 55, reps: 12)],
                                streak: 2, effort: .protectRecovery)
        XCTAssertEqual(result.kind, .reduceLoad,
                       "Both say back off, but holding a load that is too heavy is not protection")
    }

    func testRecoveryProtectionIsUnchangedWhenThereIsNoStall() throws {
        let result = try decide([set(1, weight: 55, reps: 17), set(2, weight: 55, reps: 16)],
                                streak: 0, effort: .protectRecovery)
        XCTAssertEqual(result.kind, .holdForRecovery)
    }

    func testSummaryOnlyRecordsCanNeverReachReduceLoad() throws {
        let result = try XCTUnwrap(WorkoutProgressionEngine.evaluate(
            latestSetLogs: [], summaryWeight: 55, summaryReps: 12, repRange: range, belowFloorStreak: 5
        ))
        XCTAssertEqual(result.kind, .holdBelowRange, "A streak is a per-set property")
        XCTAssertEqual(result.belowFloorStreak, 0)
    }

    /// Every existing caller omits the new argument; none of them may change behaviour.
    func testOmittingTheStallArgumentReproducesTheOldVerdicts() throws {
        let below = try XCTUnwrap(WorkoutProgressionEngine.evaluate(
            latestSetLogs: [set(1, weight: 55, reps: 12)], summaryWeight: 55, summaryReps: 12, repRange: range))
        XCTAssertEqual(below.kind, .holdBelowRange)
        let maxed = try XCTUnwrap(WorkoutProgressionEngine.evaluate(
            latestSetLogs: [set(1, weight: 55, reps: 20)], summaryWeight: 55, summaryReps: 20, repRange: range))
        XCTAssertEqual(maxed.kind, .addLoad)
    }

    // MARK: - The load it recommends dropping to

    func testAStackLiftDropsOneUsableStackIncrement() {
        XCTAssertEqual(WorkoutProgressionEngine.reducedLoad(from: 55, exerciseName: "Cable Face Pull"), 50, accuracy: 0.001)
    }

    func testTheDropIsTheExactInverseOfTheStepThatCausedIt() {
        let up = WorkoutProgressionEngine.nextLoad(from: 50, exerciseName: "Cable Face Pull")
        XCTAssertEqual(up, 55, accuracy: 0.001)
        XCTAssertEqual(WorkoutProgressionEngine.reducedLoad(from: up, exerciseName: "Cable Face Pull"), 50, accuracy: 0.001,
                       "A stalled step must land back where it came from, not somewhere new")
    }

    func testAReducedLoadIsNeverZeroOrNegative() {
        for (weight, name) in [(5.0, "Dumbbell Curl"), (2.5, "Barbell Curl"), (10.0, "Cable Lateral Raise")] {
            let reduced = WorkoutProgressionEngine.reducedLoad(from: weight, exerciseName: name)
            XCTAssertGreaterThan(reduced, 0, "\(name) at \(weight) lb must not be told to drop to nothing")
            XCTAssertLessThanOrEqual(reduced, weight)
        }
    }

    func testBodyweightHasNoLoadToDrop() {
        XCTAssertEqual(WorkoutProgressionEngine.reducedLoad(from: 0, exerciseName: "Push-Up"), 0)
        XCTAssertEqual(WorkoutProgressionEngine.reducedLoad(from: 1, exerciseName: "Push-Up"), 0,
                       "The legacy 1 lb bodyweight stand-in is not a real load either")
    }

    func testHeavyLiftsDropByACappedAmount() {
        let reduced = WorkoutProgressionEngine.reducedLoad(from: 300, exerciseName: "Barbell Squat")
        XCTAssertEqual(reduced, 290, accuracy: 0.001, "Capped at 10 lb, not 5% of 300")
    }

    // MARK: - The generator must not contradict a reduce-load verdict

    func testTellingTheLifterToAddLoadContradictsAReduceVerdict() {
        XCTAssertNotNil(
            service.coachingCueConflict(notes: "Add weight this week and push the top set.", verdict: .reduceLoad),
            "The history says take weight off; an add-load cue beside it is the same hard contradiction as under a hold verdict"
        )
    }

    func testAHoldCueIsNotTreatedAsAContradictionOfAReduceVerdict() {
        XCTAssertNil(
            service.coachingCueConflict(notes: "Hold this load and keep the reps controlled.", verdict: .reduceLoad),
            "Holding is a near-miss of the right advice, not a contradiction; a false positive here burns a paid generation"
        )
    }

    func testExecutionOnlyCuesStayClean() {
        XCTAssertNil(service.coachingCueConflict(
            notes: "Pull the rope toward the forehead and rotate so the knuckles finish facing back.",
            verdict: .reduceLoad
        ))
    }
}
