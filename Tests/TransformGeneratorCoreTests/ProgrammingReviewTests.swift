import XCTest
@testable import Transform

/// Programming changes from the 2026-11-21 review (owner approved), each from the
/// exercise-evidence consult:
///  * weeks 1-3 keep one set-and-rep prescription per role, so double progression can run
///    (a changing prescription made the card translate the load, and a 200 lb x 10 success
///    was told to start the next week at 195 lb);
///  * the deload halves sets and keeps the block's rep ranges;
///  * priority weekly direct-set bands rise one step without needing more exercise slots;
///  * a one-set change no longer re-derives the load;
///  * the effort check needs a full rep below target (RIR is misjudged by about one rep,
///    Halperin 2022) and only counts sessions of the current block.
@MainActor
final class ProgrammingReviewTests: XCTestCase {
    private let service = ClaudeService.shared
    private let roles = [("Barbell Bench Press", "Chest"), ("Machine Chest Press", "Chest"),
                         ("Cable Lateral Raise", "Lateral Deltoids"), ("Cable Crunch", "Abs")]

    // MARK: - Steady prescription within a block

    func testWeeksOneToThreeShareOneSetAndRepPrescription() {
        for (name, target) in roles {
            let sets = service.proceduralSets(for: 1, exerciseName: name, muscleTarget: target)
            let reps = service.proceduralRepRange(for: 1, exerciseName: name, muscleTarget: target)
            for week in 2...3 {
                XCTAssertEqual(service.proceduralSets(for: week, exerciseName: name, muscleTarget: target), sets, "\(name) week \(week)")
                XCTAssertEqual(service.proceduralRepRange(for: week, exerciseName: name, muscleTarget: target), reps, "\(name) week \(week)")
            }
        }
    }

    func testDeloadHalvesSetsAndKeepsTheBlockRepRanges() {
        for (name, target) in roles {
            XCTAssertEqual(service.proceduralSets(for: 4, exerciseName: name, muscleTarget: target), 2, name)
            XCTAssertEqual(service.proceduralRepRange(for: 4, exerciseName: name, muscleTarget: target),
                           service.proceduralRepRange(for: 1, exerciseName: name, muscleTarget: target), name)
        }
    }

    func testWeekThreeStillPushesEffort() {
        XCTAssertEqual(service.proceduralTargetRIR(for: 1), 2)
        XCTAssertEqual(service.proceduralTargetRIR(for: 3), 1)
        XCTAssertEqual(service.proceduralTargetRIR(for: 4), 3)
    }

    // MARK: - Priority volume

    func testPriorityBandsRiseOneStep() {
        let bands = service.evidenceProfile.directSetTargetsByPriority
        XCTAssertEqual(bands["High"], 10...14)
        XCTAssertEqual(bands["Medium"], 6...10)
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
}
