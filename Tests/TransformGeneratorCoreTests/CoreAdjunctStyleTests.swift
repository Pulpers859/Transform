import Foundation
import XCTest
@testable import Transform

@MainActor
final class CoreAdjunctStyleTests: XCTestCase {
    private let service = ClaudeService.shared

    private func exercise(_ name: String, _ target: String) -> WorkoutExerciseResponse {
        .init(exerciseName: name, sets: 3, reps: "10-12", tempo: "2-0-1-0",
              restSeconds: 75, notes: "", muscleTarget: target)
    }

    private func supports(_ style: String, _ exercises: [WorkoutExerciseResponse]) -> Bool {
        service.dayClearlySupportsExpectedStyle(style, day: .init(dayNumber: 1,
            dayName: style, muscleGroups: "", isRestDay: false, notes: "", exercises: exercises))
    }

    private var upper: [WorkoutExerciseResponse] {
        [exercise("Machine Chest Press", "Chest"), exercise("Machine Shoulder Press", "Deltoids"),
         exercise("Lat Pulldown", "Lats"), exercise("Chest-Supported Row", "Upper Back")]
    }

    private var pull: [WorkoutExerciseResponse] {
        [exercise("Lat Pulldown", "Lats"), exercise("Chest-Supported Row", "Upper Back"),
         exercise("Seated Cable Row", "Mid Back"), exercise("Reverse Pec Deck", "Rear Deltoids")]
    }

    private var arms: [WorkoutExerciseResponse] {
        [exercise("EZ-Bar Curl", "Biceps"), exercise("Incline Dumbbell Curl", "Biceps"),
         exercise("Rope Triceps Pressdown", "Triceps"),
         exercise("Overhead Cable Triceps Extension", "Triceps")]
    }

    func testUpperThemeAllowsTrustedDirectCoreAdjunct() {
        XCTAssertTrue(supports("Upper", upper + [exercise("Hanging Knee Raise", "Lower Abs")]))
    }

    func testPullThemeAllowsPallofWithoutCountingItAsAnotherPush() {
        XCTAssertTrue(supports("Pull", pull + [exercise("Cable Pallof Press", "Obliques")]))
    }

    func testArmsThemeAllowsFourArmMovementsLateralAndCore() {
        XCTAssertTrue(supports("Arms", arms + [exercise("Machine Lateral Raise", "Lateral Deltoids"),
            exercise("Cable Pallof Press", "Obliques")]))
    }

    func testActualSquatCannotBecomeNeutralByClaimingAbsTarget() {
        XCTAssertFalse(supports("Upper", upper + [exercise("Back Squat", "Abs")]))
    }

    func testActualBenchStillCountsAgainstPullTheme() {
        XCTAssertEqual(pull.filter { service.exerciseMatchesDayStyle($0, style: "Push") }.count, 1)
        XCTAssertFalse(supports("Pull", pull + [exercise("Dumbbell Bench Press", "Chest"),
            exercise("Cable Pallof Press", "Obliques")]))
    }

    func testInsufficientArmThemeCannotBeRescuedByCore() {
        XCTAssertFalse(supports("Arms", Array(arms.prefix(2)) + [
            exercise("Machine Lateral Raise", "Lateral Deltoids"),
            exercise("Machine Chest Press", "Chest"), exercise("Cable Pallof Press", "Obliques")]))
    }

    func testCoreOnlyDaysDoNotAcquireUpperPullOrArmsThemes() {
        let core = [exercise("Cable Crunch", "Abs"), exercise("Hanging Knee Raise", "Lower Abs"),
                    exercise("Cable Pallof Press", "Obliques")]
        for style in ["Upper", "Pull", "Arms"] {
            XCTAssertFalse(supports(style, core), style)
        }
    }

    func testTwoNonCoreOffThemeMovementsRemainVisible() {
        XCTAssertFalse(supports("Pull", pull + [exercise("Machine Chest Press", "Chest"),
            exercise("Machine Shoulder Press", "Deltoids"), exercise("Cable Pallof Press", "Obliques")]))
    }

    func testCarriesAndUnknownAbsLabelsAreNotNeutralAdjuncts() {
        for name in ["Dumbbell Farmer's Walk", "Farmer's Walk", "Dumbbell Suitcase Carry",
                     "Suitcase Carries", "Uncatalogued Core Drill"] {
            XCTAssertFalse(supports("Upper", upper + [exercise(name, "Abs")]), name)
        }
    }

    func testNoCoreThemeThresholdsStayUnchanged() {
        XCTAssertTrue(supports("Upper", upper))
        XCTAssertFalse(supports("Upper", Array(upper.prefix(3))))
        XCTAssertTrue(supports("Pull", pull))
        XCTAssertFalse(supports("Pull", Array(pull.prefix(2))))
        XCTAssertTrue(supports("Arms", arms + [exercise("Machine Lateral Raise", "Lateral Deltoids")]))
        XCTAssertFalse(supports("Arms", Array(arms.prefix(3)) + [
            exercise("Machine Lateral Raise", "Lateral Deltoids"),
            exercise("Machine Chest Press", "Chest"), exercise("Machine Shoulder Press", "Deltoids")]))
    }

    func testThemeExemptionDoesNotRewriteUnderlyingExerciseStyleMatching() {
        XCTAssertTrue(service.exerciseMatchesDayStyle(exercise("Hanging Knee Raise", "Lower Abs"), style: "Lower"))
        XCTAssertTrue(service.exerciseMatchesDayStyle(exercise("Cable Pallof Press", "Obliques"), style: "Push"))
    }

    func testTrustedAliasesShareCoreAdjunctBehaviorWithoutRenamingTheExercise() {
        for name in ["Pallof Press", "Cable Pallof Press", "Hanging Leg Raises", "Dead Bugs"] {
            let core = exercise(name, "Abs")
            XCTAssertTrue(supports("Upper", upper + [core]), name)
            XCTAssertEqual(core.exerciseName, name)
        }
    }

    func testPushAndLowerClassificationStayOutsideThisCorrection() {
        let core = exercise("Cable Crunch", "Abs")
        let pushes = [exercise("Machine Chest Press", "Chest"),
                      exercise("Machine Shoulder Press", "Deltoids"),
                      exercise("Rope Triceps Pressdown", "Triceps")]
        let legs = [exercise("Back Squat", "Quads"), exercise("Seated Leg Curl", "Hamstrings"),
                    exercise("Standing Calf Raise", "Calves")]
        XCTAssertTrue(supports("Push", pushes + [core]))
        XCTAssertFalse(supports("Push", Array(pushes.prefix(2)) + [core]))
        XCTAssertTrue(supports("Lower", legs + [core]))
        XCTAssertTrue(supports("Lower", Array(legs.prefix(2)) + [core]))
    }

    func testThemeCheckLeavesAllSlotsDoseAndFatigueIntact() throws {
        let lifts = arms + [exercise("Machine Lateral Raise", "Lateral Deltoids"),
                            exercise("Cable Pallof Press", "Obliques")]
        let day = WorkoutDayResponse(dayNumber: 1, dayName: "Arms", muscleGroups: "",
            isRestDay: false, notes: "", exercises: lifts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(day)
        let fatigue = service.estimatedDayFatigue(for: day.exercises)
        XCTAssertTrue(service.dayClearlySupportsExpectedStyle("Arms", day: day))
        XCTAssertEqual(try encoder.encode(day), before)
        XCTAssertEqual(day.exercises.count, 6)
        XCTAssertEqual(day.exercises.reduce(0) { $0 + $1.sets }, 18)
        XCTAssertEqual(service.estimatedDayFatigue(for: day.exercises), fatigue)
        XCTAssertGreaterThan(fatigue, service.estimatedDayFatigue(for: Array(lifts.dropLast())))
    }

    func testMismatchedDayLabelCanBeResolvedBySubstantiveUpperWorkWithCore() {
        let day = WorkoutDayResponse(dayNumber: 1, dayName: "Lower", muscleGroups: "Abs",
            isRestDay: false, notes: "", exercises: upper + [exercise("Hanging Knee Raise", "Lower Abs")])
        XCTAssertFalse(service.shouldFlagStyleMismatch(expectedStyle: "Upper", actualStyle: "Lower", day: day))
    }
}
