import XCTest
@testable import Transform

@MainActor
final class FocusCreditBoundaryTests: XCTestCase {
    private let service = ClaudeService.shared

    func testChestCreditRequiresDeclaredChestInvolvementNotNameKeywords() {
        // Keep selection ranking separate from numerical stimulus accounting. A global
        // classifier correction regressed four complete beginner weeks at 53f360e.
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Reverse Pec Deck",
            muscleTarget: "Rear Deltoids", focusArea: "Chest"), .support)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Dumbbell Rear Delt Fly",
            muscleTarget: "Rear Deltoids", focusArea: "Chest"), .support)
        let unrelated = [("Reverse Pec Deck", "Rear Deltoids"),
            ("Dumbbell Rear Delt Fly", "Rear Deltoids"), ("Cable Rear Delt Fly", "Rear Deltoids"),
            ("Chest-Supported Row", "Upper Back"), ("Chest-Supported Rear Delt Row", "Rear Deltoids"),
            ("Prone Incline Dumbbell Rear Delt Raise", "Rear Deltoids"),
            ("Chest-Supported Cable Y Raise", "Shoulders"), ("Low Incline Cable Y Raise", "Shoulders")]
        for (name, target) in unrelated {
            let exercise = WorkoutExerciseResponse(exerciseName: name, sets: 3, reps: "8-12",
                tempo: "", restSeconds: 0, notes: "", muscleTarget: target)
            for focus in ["Chest", "Pecs", "Pectoral", "Pectorals", "Pectoralis major", "Upper Chest", "Clavicular"] {
                let credit = service.stimulusCredit(for: exercise, area: focus)
                XCTAssertEqual(credit.directSets, 0, "\(name), \(focus)")
                XCTAssertEqual(credit.weightedStimulus, 0, "\(name), \(focus)")
            }
        }
        for (name, target) in [("Cable Fly", "Chest"), ("Machine Chest Press", "Chest"),
                               ("Incline Dumbbell Press", "Upper Chest"), ("Pec Deck", "Chest")] {
            let exercise = WorkoutExerciseResponse(exerciseName: name, sets: 3, reps: "8-12",
                tempo: "", restSeconds: 0, notes: "", muscleTarget: target)
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target,
                focusArea: "Chest"), .prime)
            XCTAssertEqual(service.stimulusCredit(for: exercise, area: "Chest").weightedStimulus, 3)
        }
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Cable Fly", muscleTarget: "Chest",
            focusArea: "Upper Chest"), .secondary)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Incline Dumbbell Press", muscleTarget: "Upper Chest",
            focusArea: "Upper Chest"), .prime)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Dumbbell Rear Delt Fly", muscleTarget: "Rear Deltoids",
            focusArea: "Rear Deltoids"), .prime)
        for (name, target) in [("Close-Grip Barbell Bench Press", "Triceps"), ("Landmine Press", "Anterior Deltoids")] {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target,
                focusArea: "Chest"), .secondary, name)
            let exercise = WorkoutExerciseResponse(exerciseName: name, sets: 3, reps: "8-12",
                tempo: "", restSeconds: 0, notes: "", muscleTarget: target)
            XCTAssertEqual(service.stimulusCredit(for: exercise, area: "Chest").weightedStimulus, 2.1, accuracy: 0.000001)
        }
    }

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
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Single-Arm Dumbbell Row",
            muscleTarget: "Lats", focusArea: "Lats specialization"), .secondary)
        XCTAssertEqual(service.focusStimulusKind(exerciseName: "Lat Pulldown",
            muscleTarget: "Lats", focusArea: "Pecs / Lats"), .prime)
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
