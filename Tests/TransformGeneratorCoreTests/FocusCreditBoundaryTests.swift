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

    func testHipThrustFocusCreditRespectsExplicitMetadata() {
        let name = "Barbell Hip Thrust"
        let metadata = service.exerciseMetadata(forExerciseName: name, muscleTarget: "Glutes")
        XCTAssertEqual(metadata.primaryAreas, ["Glutes"])
        XCTAssertEqual(metadata.secondaryAreas, ["Hamstrings"])
        let exercise = WorkoutExerciseResponse(exerciseName: name, sets: 3, reps: "8-12",
            tempo: "", restSeconds: 0, notes: "", muscleTarget: "Glutes")
        XCTAssertEqual(service.directSetCredit(for: exercise, area: "Hamstrings"), 0)
        XCTAssertEqual(service.directSetCredit(for: exercise, area: "Glutes"), 3)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: "Glutes", focusArea: "Hamstrings"), .secondary)
    }

    func testNamedLowerFocusDoesNotBridgeThroughUmbrellaAliases() {
        let cases: [(String, String, [ClaudeService.FocusStimulusKind])] = [
            ("Barbell Hip Thrust", "Glutes", [.prime, .secondary, .none]),
            ("Single-Leg Hip Thrust", "Glutes", [.prime, .secondary, .none]),
            ("Seated Leg Curl", "Hamstrings", [.none, .prime, .none]),
            ("Machine Leg Extension", "Quads", [.none, .none, .prime]),
            ("Barbell Romanian Deadlift", "Hamstrings", [.secondary, .prime, .none]),
            ("Leg Press", "Quads", [.secondary, .none, .prime]),
            ("Dumbbell Bulgarian Split Squat", "Quads/Glutes", [.prime, .none, .prime]),
            // Explicit composite primary metadata retains its existing direct-credit meaning.
            ("Trap Bar Deadlift", "Quads", [.prime, .prime, .prime])
        ]
        for (name, target, expected) in cases {
            for (index, focus) in ["Glutes", "Hamstrings", "Quads"].enumerated() {
                XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target,
                    focusArea: focus), expected[index], "\(name), focus \(focus)")
            }
        }
    }

    func testLowerFocusVariantsRetainQuerySideAliasContract() {
        for focus in ["Hamstring", "Hamstrings", "Hamstring development"] {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: "Barbell Hip Thrust",
                muscleTarget: "Glutes", focusArea: focus), .secondary, focus)
        }
        for focus in ["Glute", "Glutes", "Glute development"] {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: "Seated Leg Curl",
                muscleTarget: "Hamstrings", focusArea: focus), .none, focus)
        }
        for focus in ["Quad", "Quads", "Quadriceps development"] {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: "Barbell Hip Thrust",
                muscleTarget: "Glutes", focusArea: focus), .none, focus)
        }
        // These are existing query aliases, not newly introduced composite-union semantics.
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Dumbbell Bulgarian Split Squat",
            muscleTarget: "Quads/Glutes", focusArea: "Quads/Glutes"), .prime)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Trap Bar Deadlift",
            muscleTarget: "Quads", focusArea: "Posterior Chain"), .prime)
    }

    func testPunctuationVariantsOfPullApartRemainSupportOnlyForRelatedFocus() {
        for name in ["Band Pull-Apart", "Band Pull Apart", "Band Pull–Apart"] {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: "Shoulders", focusArea: "Shoulders"), .support)
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: "Shoulders", focusArea: "Quads"), .none)
        }
    }

    func testFrontAndAnteriorDeltoidFocusUseRegionalMetadata() {
        for focus in ["Front Deltoids", "Anterior Deltoids"] {
            for (name, target) in [("Reverse Pec Deck", "Rear Deltoids"), ("Cable Lateral Raise", "Lateral Deltoids")] {
                XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target, focusArea: focus), .none)
                XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target, focusArea: "Shoulders"), .prime)
            }
            XCTAssertEqual(service.focusStimulusKind(exerciseName: "Seated Dumbbell Shoulder Press",
                muscleTarget: "Anterior Deltoids", focusArea: focus), .prime)
            XCTAssertEqual(service.focusStimulusKind(exerciseName: "Incline Dumbbell Press",
                muscleTarget: "Upper Chest", focusArea: focus), .secondary)
        }
    }

    func testOtherCorrectiveKeywordsRetainRelatedSupportAndUnrelatedRefusal() {
        for name in ["Cable Y Raise", "Cable Y-Raise", "Trap 3 Raise", "Trap-3 Raise",
                     "Dumbbell Scaption", "Cable External Rotation", "Cable External-Rotation",
                     "Wall Slide", "Wall-Slide"] {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name,
                muscleTarget: "Shoulders", focusArea: "Shoulders"), .support, name)
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name,
                muscleTarget: "Shoulders", focusArea: "Quads"), .none, name)
        }
    }

    func testRegionalCorrectionPreservesExistingNamedCompositePrecedence() {
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Incline Dumbbell Press",
            muscleTarget: "Upper Chest", focusArea: "Upper Chest / Front Deltoids"), .prime)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Cable Face Pull",
            muscleTarget: "Rear Deltoids", focusArea: "Rear Deltoids / Front Deltoids"), .secondary)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Cable Face Pull",
            muscleTarget: "Rear Deltoids", focusArea: "Rear Deltoids / Hamstrings"), .secondary)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Incline Dumbbell Press",
            muscleTarget: "Upper Chest", focusArea: "Upper Chest / Glutes"), .prime)
    }
}
