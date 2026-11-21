import XCTest
@testable import Transform

/// Programming changes from the 2026-11-21 review (owner approved), from the
/// exercise-evidence consult and the first green attempt's CI evidence:
///  * rep ranges stay the block's own in every week and sets step by at most one, so double
///    progression can run (a changing prescription made the card translate the load, and a
///    200 lb x 10 success was told to start the next week at 195 lb);
///  * the deload keeps the block's rep ranges, with fewer sets than week 3;
///  * the High weekly direct-set band rises one step (Medium's raise was backed out);
///  * a one-set change no longer re-derives the load;
///  * the effort check needs a full rep below target (RIR is misjudged by about one rep,
///    Halperin 2022) and only counts sessions of the current block.
@MainActor
final class ProgrammingReviewTests: XCTestCase {
    private let service = ClaudeService.shared
    private let roles = [("Barbell Bench Press", "Chest"), ("Machine Chest Press", "Chest"),
                         ("Cable Lateral Raise", "Lateral Deltoids"), ("Cable Crunch", "Abs")]

    // MARK: - Steady prescription within a block

    func testRepRangesHoldAcrossTheBlockAndSetsStepByAtMostOne() {
        for (name, target) in roles {
            let reps = service.proceduralRepRange(for: 1, exerciseName: name, muscleTarget: target)
            for week in 2...3 {
                XCTAssertEqual(service.proceduralRepRange(for: week, exerciseName: name, muscleTarget: target), reps, "\(name) week \(week)")
                let before = service.proceduralSets(for: week - 1, exerciseName: name, muscleTarget: target)
                let now = service.proceduralSets(for: week, exerciseName: name, muscleTarget: target)
                XCTAssertTrue((0...1).contains(now - before), "\(name) week \(week): \(before) -> \(now)")
                XCTAssertFalse(try WorkoutLoadTranslation.shouldTranslate(
                    previousRange: XCTUnwrap(RepRange.parse(reps)), currentRange: XCTUnwrap(RepRange.parse(reps)),
                    previousSets: before, currentSets: now), "\(name) week \(week) would re-derive the load")
            }
        }
    }

    func testDeloadKeepsTheBlockRepRangesWithFewerSets() {
        for (name, target) in roles {
            XCTAssertLessThan(service.proceduralSets(for: 4, exerciseName: name, muscleTarget: target),
                              service.proceduralSets(for: 3, exerciseName: name, muscleTarget: target), name)
            XCTAssertEqual(service.proceduralRepRange(for: 4, exerciseName: name, muscleTarget: target),
                           service.proceduralRepRange(for: 1, exerciseName: name, muscleTarget: target), name)
        }
    }

    /// Audit 2026-11-21 (M1): a 2-set anchor fell below the validator's anchor floor, which
    /// would show the owner "add a set or two yourself" on every deload day.
    func testDeloadDefaultsDoNotFallBelowTheValidatorsRoleFloor() {
        for (name, target) in roles + [("Back Squat", "Quads")] {
            XCTAssertGreaterThanOrEqual(
                service.proceduralSets(for: 4, exerciseName: name, muscleTarget: target),
                service.minimumSetFloor(forExerciseName: name, muscleTarget: target), name)
        }
    }

    func testWeekThreeStillPushesEffort() {
        XCTAssertEqual(service.proceduralTargetRIR(for: 1), 2)
        XCTAssertEqual(service.proceduralTargetRIR(for: 3), 1)
        XCTAssertEqual(service.proceduralTargetRIR(for: 4), 3)
    }

    // MARK: - Priority volume

    func testHighPriorityBandRisesOneStep() {
        let bands = service.evidenceProfile.directSetTargetsByPriority
        XCTAssertEqual(bands["High"], 10...14)
        // Raising Medium to 6-10 left a Medium Calves priority short in the user-journey
        // simulation (run 44921308872); backed out until the menu-sizing fix (MAINT-001).
        XCTAssertEqual(bands["Medium"], 5...8)
        XCTAssertEqual(bands["Low"], 3...5)
    }

    // MARK: - Load translation

    func testAOneSetChangeDoesNotReDeriveTheLoad() throws {
        let range = try XCTUnwrap(RepRange.parse("6-10"))
        XCTAssertFalse(WorkoutLoadTranslation.shouldTranslate(previousRange: range, currentRange: range, previousSets: 4, currentSets: 5))
        XCTAssertFalse(WorkoutLoadTranslation.shouldTranslate(previousRange: range, currentRange: range, previousSets: 5, currentSets: 4))
        XCTAssertFalse(WorkoutLoadTranslation.shouldTranslate(previousRange: range, currentRange: range, previousSets: nil, currentSets: 4))
    }

    func testBigSetChangesAndRangeChangesStillTranslate() throws {
        let range = try XCTUnwrap(RepRange.parse("12-15"))
        let other = try XCTUnwrap(RepRange.parse("8-12"))
        XCTAssertTrue(WorkoutLoadTranslation.shouldTranslate(previousRange: range, currentRange: range, previousSets: 2, currentSets: 4))
        XCTAssertTrue(WorkoutLoadTranslation.shouldTranslate(previousRange: other, currentRange: range, previousSets: 3, currentSets: 3))
    }

    // MARK: - Effort check

    private func session(day: Int, at time: TimeInterval, rir: Double, target: Int) -> WorkoutPerformanceLogSnapshot {
        WorkoutPerformanceLogSnapshot(
            canonicalExerciseKey: "barbell-row",
            loggedAt: Date(timeIntervalSince1970: time),
            setLogs: [SetLogEntry(setNumber: 1, weightLbs: 100, repsCompleted: 10, rir: rir),
                      SetLogEntry(setNumber: 2, weightLbs: 100, repsCompleted: 10, rir: rir)],
            prescribedTargetRIR: target,
            workoutDayNumber: day)
    }

    func testHalfARepBelowTargetIsWithinEstimationError() {
        XCTAssertEqual(WorkoutProgressionEngine.effortSignal(
            for: "barbell-row", from: [session(day: 2, at: 100, rir: 1.5, target: 2), session(day: 9, at: 200, rir: 1.5, target: 2)]),
            .neutral)
    }

    func testAFullRepBelowTargetTwiceStillProtectsRecovery() {
        XCTAssertEqual(WorkoutProgressionEngine.effortSignal(
            for: "barbell-row", from: [session(day: 2, at: 100, rir: 1, target: 2), session(day: 9, at: 200, rir: 1, target: 2)]),
            .protectRecovery)
    }

    func testTheLastBlocksHardSessionsDoNotCountInTheNextBlock() {
        // Week 3 of the old block (days 15, 16) ran a rep below target; week 1 of the new
        // block (day 2) is on target. The deload between them cleared that fatigue.
        let history = [session(day: 15, at: 100, rir: 0, target: 1),
                       session(day: 16, at: 200, rir: 0, target: 1),
                       session(day: 2, at: 900, rir: 2, target: 2)]
        XCTAssertEqual(WorkoutProgressionEngine.effortSignal(for: "barbell-row", from: history), .insufficientEvidence)
    }

    /// Audit 2026-11-21 (M3): before any new-block session exists, the newest history is the
    /// old block's week 3 (the deload is dropped by `progressionHistory`). The week being
    /// trained or generated has to start the block, or the old block still counts.
    func testFirstSessionAfterTheDeloadIgnoresTheOldBlock() {
        let history = WorkoutProgressionEngine.progressionHistory([
            session(day: 15, at: 100, rir: 0, target: 1), session(day: 16, at: 200, rir: 0, target: 1),
            session(day: 22, at: 300, rir: 3, target: 3)])
        XCTAssertEqual(WorkoutProgressionEngine.effortSignal(for: "barbell-row", from: history, currentWeek: 1),
                       .insufficientEvidence)
        // Generating week 4 of the SAME block still sees weeks 1-3.
        XCTAssertEqual(WorkoutProgressionEngine.effortSignal(for: "barbell-row", from: history, currentWeek: 4),
                       .protectRecovery)
    }
}
