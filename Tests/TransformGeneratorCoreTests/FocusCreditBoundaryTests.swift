import XCTest
@testable import Transform

@MainActor
final class FocusCreditBoundaryTests: XCTestCase {
    private let service = ClaudeService.shared

    func testStableBroadAndNamedFocusControls() {
        let cases: [(String, String, String, ClaudeService.FocusStimulusKind)] = [
            ("Chest-Supported Row", "Upper Back", "Back", .prime),
            ("Lat Pulldown", "Lats", "Back", .prime),
            ("Cable Lateral Raise", "Lateral Deltoids", "Side Delts", .prime),
            ("Cable Face Pull", "Rear Deltoids", "Rear Deltoids", .secondary),
            ("Single-Arm Dumbbell Row", "Lats", "Lats", .secondary),
            ("Lat Pulldown", "Lats", "Lats", .prime),
            ("Cable Crunch", "Abs", "Core/Abs", .prime),
            ("Leg Press", "Quads", "Lateral Deltoids", .none)
        ]
        for (name, target, focus, expected) in cases {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target, focusArea: focus),
                expected, "\(name), focus \(focus)")
        }
    }

    // Explicit unresolved defects, not acceptance of the restored classifier.
    // Strict expected failures force removal/reassessment when a future fix lands.
    func testOpenHipThrustFocusCreditDisagreesWithExplicitMetadata() {
        let name = "Barbell Hip Thrust"
        let metadata = service.exerciseMetadata(forExerciseName: name, muscleTarget: "Glutes")
        XCTAssertEqual(metadata.primaryAreas, ["Glutes"])
        XCTAssertEqual(metadata.secondaryAreas, ["Hamstrings"])
        let exercise = WorkoutExerciseResponse(exerciseName: name, sets: 3, reps: "8-12",
            tempo: "", restSeconds: 0, notes: "", muscleTarget: "Glutes")
        XCTAssertEqual(service.directSetCredit(for: exercise, area: "Hamstrings"), 0)
        XCTAssertEqual(service.directSetCredit(for: exercise, area: "Glutes"), 3)
        XCTExpectFailure("OPEN: bilateral umbrella aliases promote secondary Hamstrings to prime; rejected fix f54f3b4 changed whole plans.") {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: "Glutes", focusArea: "Hamstrings"), .secondary)
        }
    }

    func testOpenHyphenatedPullApartSupportClassification() {
        XCTExpectFailure("OPEN: corrective-support name matching misses the hyphenated pull-apart form.") {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: "Band Pull-Apart", muscleTarget: "Shoulders", focusArea: "Shoulders"), .support)
        }
    }

    func testOpenFrontDeltoidAliasMustNotCreditRearDeltWork() {
        XCTExpectFailure("OPEN: Front Deltoids alias admits rear-delt work as prime.") {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: "Reverse Pec Deck", muscleTarget: "Rear Deltoids", focusArea: "Front Deltoids"), .none)
        }
    }
}
