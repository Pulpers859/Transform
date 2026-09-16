import XCTest
@testable import Transform

@MainActor
final class BarbellIncrementTests: XCTestCase {
    func testBilateralBarsUseFivePoundTotalStepsIncludingLegacyNames() {
        for name in ["Incline Barbell Press", "Incline Barbell Bench Press", "Barbell Row",
                     "Barbell Hip Thrust", "EZ-Bar Curl", "Trap Bar Deadlift", "Back Squat",
                     "Front Squat", "BB Bench Press", "Romanian Deadlift", "Skull Crusher",
                     "Incline Smith Machine Press", "Smith Machine Bench Press"] {
            XCTAssertEqual(WorkoutProgressionEngine.incrementLbs(forExerciseName: name), 5, name)
            XCTAssertEqual(WorkoutProgressionEngine.nextLoad(from: 100, exerciseName: name), 105, name)
            XCTAssertEqual(WorkoutProgressionEngine.reducedLoad(from: 105, exerciseName: name), 95, name)
        }
    }

    func testCableAddOnsAndOneEndedBarsAreNotChangedToBilateralSteps() {
        for name in ["Cable Face Pull", "Cable Fly", "Machine Chest Press", "V-Bar Pressdown",
                     "Landmine Press", "Chest-Supported T-Bar Row", "Hanging Knee Raise"] {
            XCTAssertEqual(WorkoutProgressionEngine.incrementLbs(forExerciseName: name), 2.5, name)
            XCTAssertEqual(WorkoutProgressionEngine.nextLoad(from: 100, exerciseName: name), 102.5, name)
        }
        XCTAssertEqual(WorkoutProgressionEngine.incrementLbs(forExerciseName: "Dumbbell Curl"), 5)
        XCTAssertEqual(WorkoutProgressionEngine.incrementLbs(forExerciseName: "Incline DB Press"), 5)
        XCTAssertEqual(WorkoutProgressionEngine.incrementLbs(forExerciseName: "Barbell Row", override: 10), 10)
        XCTAssertEqual(WorkoutProgressionEngine.incrementLbs(forExerciseName: "Barbell Row", override: -1), 5)
    }

    func testSmallOrLegacyLoadsNeverIncreaseOnAReduceRecommendation() {
        for weight in [2.5, 5.0, 7.5, 10.0, 102.5] {
            XCTAssertLessThanOrEqual(
                WorkoutProgressionEngine.reducedLoad(from: weight, exerciseName: "Barbell Curl"), weight)
        }
        XCTAssertEqual(WorkoutProgressionEngine.nextLoad(from: 0, exerciseName: "Barbell Curl"), 5)
        XCTAssertEqual(WorkoutProgressionEngine.nextLoad(from: 0, exerciseName: "Push-Up"), 2.5)
    }

    func testRepRangeTranslationUsesTheSameBarbellStep() throws {
        let result = try XCTUnwrap(WorkoutLoadTranslation.translate(
            reference: .init(loadLbs: 100, repsAchieved: 10, reserveReps: 1, hitPrescribedCeiling: false),
            target: .init(sets: 3, repFloor: 12, targetRIR: 1),
            incrementLbs: WorkoutProgressionEngine.incrementLbs(forExerciseName: "Incline Barbell Bench Press")
        ))
        XCTAssertEqual(result.recommendedLoadLbs.truncatingRemainder(dividingBy: 5), 0)
        XCTAssertLessThan(result.recommendedLoadLbs, 100)
    }

    func testPromptDoesNotCallAnUnchangedLoadAReduction() {
        for weight in [2.5, 5.0] {
            let cue = WorkoutProgressionEngine.reductionPromptCue(
                from: weight, exerciseName: "Barbell Curl", formatLoad: { String($0) })
            XCTAssertEqual(cue, "no smaller load step is available; cue an easier variation rather than claiming the same load is a reduction")
            XCTAssertFalse(cue.contains("REDUCING LOAD"))
        }
        XCTAssertEqual(WorkoutProgressionEngine.reductionPromptCue(
            from: 105, exerciseName: "Barbell Row", formatLoad: { String($0) }),
            "cue REDUCING LOAD to 95.0 lb")
    }
}
