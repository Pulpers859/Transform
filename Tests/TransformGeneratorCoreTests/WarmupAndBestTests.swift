import XCTest
import SwiftData
@testable import Transform

/// Review of 2026-11-21: warm-ups are stored apart from working sets so no working-set reader
/// can count them, and a set that beats the stored best is announced.
final class WarmupAndBestTests: XCTestCase {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    func testWarmupsAreInvisibleToWorkingSetReaders() throws {
        let ctx = try context()
        let log = ExercisePerformanceLog(exerciseName: "Barbell Bench Press", weightLbs: 0, workoutDayNumber: 1)
        log.warmupSetsJSON = ExercisePerformanceLog.encodeSetLogs([
            SetLogEntry(setNumber: 1, weightLbs: 95, repsCompleted: 8),
            SetLogEntry(setNumber: 2, weightLbs: 135, repsCompleted: 5)
        ])
        ctx.insert(log)
        XCTAssertEqual(log.decodedWarmupSets.map(\.weightLbs), [95, 135])
        XCTAssertTrue(log.decodedSetLogs.isEmpty)
        XCTAssertTrue(log.setLogsJSON.isEmpty)
        XCTAssertFalse(log.holdsLoggedWork)
        let snapshot = WorkoutPerformanceLogSnapshot(canonicalExerciseKey: log.canonicalExerciseKey,
                                                     loggedAt: log.loggedAt, setLogs: log.decodedSetLogs)
        XCTAssertTrue(WorkoutProgressionEngine.latestUsableSetLogs(for: log.canonicalExerciseKey, from: [snapshot]).isEmpty)
    }

    func testWorkingSetsAndWarmupsLiveSideBySide() throws {
        let ctx = try context()
        let log = ExercisePerformanceLog(exerciseName: "Barbell Bench Press", weightLbs: 185, repsCompleted: 8, workoutDayNumber: 1,
                                         setLogs: [SetLogEntry(setNumber: 1, weightLbs: 185, repsCompleted: 8)])
        log.warmupSetsJSON = ExercisePerformanceLog.encodeSetLogs([SetLogEntry(setNumber: 1, weightLbs: 135, repsCompleted: 5)])
        ctx.insert(log)
        XCTAssertEqual(log.decodedSetLogs.map(\.weightLbs), [185])
        XCTAssertEqual(log.decodedWarmupSets.map(\.weightLbs), [135])
    }

    func testANewLogHasNoWarmups() throws {
        let ctx = try context()
        let log = ExercisePerformanceLog(exerciseName: "Cable Curl", weightLbs: 40, repsCompleted: 12)
        ctx.insert(log)
        XCTAssertEqual(log.warmupSetsJSON, "")
        XCTAssertTrue(log.decodedWarmupSets.isEmpty)
    }

    // MARK: - New best

    private func record(_ weight: Double, _ reps: Int?) -> PersonalBestCheck.Record {
        PersonalBestCheck.Record(weightLbs: weight, reps: reps)
    }

    func testHeavierOrMoreRepsAtTheSameWeightIsANewBest() {
        XCTAssertTrue(PersonalBestCheck.isImprovement(record(185, 6), over: record(180, 8)))
        XCTAssertTrue(PersonalBestCheck.isImprovement(record(180, 9), over: record(180, 8)))
        XCTAssertTrue(PersonalBestCheck.isImprovement(record(0, 13), over: record(0, 12)))
    }

    func testNoBannerWithoutAnEarlierBestOrForATieOrLess() {
        XCTAssertFalse(PersonalBestCheck.isImprovement(record(185, 8), over: nil))
        XCTAssertFalse(PersonalBestCheck.isImprovement(record(180, 8), over: record(180, 8)))
        XCTAssertFalse(PersonalBestCheck.isImprovement(record(175, 12), over: record(180, 8)))
        XCTAssertFalse(PersonalBestCheck.isImprovement(nil, over: record(180, 8)))
    }

    func testBannerText() {
        XCTAssertEqual(PersonalBestCheck.text(record(185, 6), over: record(180, 8)), "New best: 185 lb × 6 (was 180 lb × 8)")
        XCTAssertEqual(PersonalBestCheck.text(record(0, 13), over: record(0, 12)), "New best: BW × 13 (was BW × 12)")
    }
}
