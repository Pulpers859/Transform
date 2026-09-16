import XCTest
@testable import Transform

@MainActor
final class FocusCreditBoundaryTests: XCTestCase {
    private let service = ClaudeService.shared

    func testExplicitPrimaryAndSecondaryMembershipDoesNotBridgeThroughUmbrellaAreas() {
        let cases: [(String, String, String, ClaudeService.FocusStimulusKind)] = [
            ("Barbell Hip Thrust", "Glutes", "Hamstrings", .secondary),
            ("Single-Leg Hip Thrust", "Glutes", "Hamstrings", .secondary),
            ("Barbell Hip Thrust", "Glutes", "Glutes", .prime),
            ("Single-Leg Hip Thrust", "Glutes", "Glutes", .prime),
            ("Barbell Hip Thrust", "Glutes", "Quads", .none),
            ("Machine Leg Extension", "Quads", "Glutes", .none),
            ("Leg Press", "Quads", "Glutes", .secondary),
            ("Uncatalogued Glute Movement", "Glutes", "Hamstrings", .secondary),
            ("Barbell Romanian Deadlift", "Hamstrings", "Hamstrings", .prime),
            ("Nordic Hamstring Curl", "Hamstrings", "Hamstrings", .prime),
            ("Barbell Romanian Deadlift", "Hamstrings", "Glutes", .secondary),
            ("Dumbbell Bulgarian Split Squat", "Quads/Glutes", "Quads", .prime),
            ("Dumbbell Bulgarian Split Squat", "Quads/Glutes", "Glutes", .prime),
            ("Dumbbell Bulgarian Split Squat", "Quads/Glutes", "Quads/Glutes", .prime)
        ]
        for (name, target, focus, expected) in cases {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target, focusArea: focus),
                expected, "\(name) targeting \(target), focus \(focus)")
        }
        for name in ["Barbell Hip Thrust", "Single-Leg Hip Thrust"] {
            let metadata = service.exerciseMetadata(forExerciseName: name, muscleTarget: "Glutes")
            XCTAssertEqual(metadata.primaryAreas, ["Glutes"])
            XCTAssertEqual(metadata.secondaryAreas, ["Hamstrings"])
            let exercise = WorkoutExerciseResponse(exerciseName: name, sets: 3, reps: "8-12",
                tempo: "", restSeconds: 0, notes: "", muscleTarget: "Glutes")
            XCTAssertEqual(service.directSetCredit(for: exercise, area: "Hamstrings"), 0)
            XCTAssertEqual(service.directSetCredit(for: exercise, area: "Glutes"), 3)
        }
    }

    func testBroadQueriesRegionalAliasesAndNamedOverridesRemainDistinct() {
        let cases: [(String, String, String, ClaudeService.FocusStimulusKind)] = [
            ("Chest-Supported Row", "Upper Back", "Back", .prime),
            ("Lat Pulldown", "Lats", "Back", .prime),
            ("Flat Barbell Bench Press", "Chest", "Chest", .prime),
            ("Incline Dumbbell Press", "Upper Chest", "Chest", .prime),
            ("Cable Lateral Raise", "Lateral Deltoids", "Shoulders", .prime),
            ("Reverse Pec Deck", "Rear Deltoids", "Shoulders", .prime),
            ("Cable Lateral Raise", "Lateral Deltoids", "Side Delts", .prime),
            ("Reverse Pec Deck", "Rear Deltoids", "Posterior Deltoids", .prime),
            ("Machine Shoulder Press", "Anterior Deltoids", "Front Deltoids", .prime),
            ("Machine Shoulder Press", "Anterior Deltoids", "Anterior Deltoids", .prime),
            ("Incline Dumbbell Press", "Upper Chest", "Clavicular Chest", .prime),
            ("Cable Face Pull", "Rear Deltoids", "Rear Deltoids", .secondary),
            ("Machine Chest Press", "Chest", "Upper Chest", .secondary),
            ("Machine Chest Press", "Chest", "Clavicular", .secondary),
            ("Machine Dip", "Triceps", "Upper Chest", .secondary),
            ("Single-Arm Dumbbell Row", "Lats", "Lats", .secondary),
            ("Lat Pulldown", "Lats", "Lats", .prime),
            ("EZ-Bar Curl", "Biceps", "Arms", .prime),
            ("Cable Crunch", "Abs", "Core/Abs", .prime),
            ("Dumbbell Farmer's Walk", "Anterior Core", "Core/Abs", .support),
            ("Band Pull-Apart", "Shoulders", "Shoulders", .support),
            ("Leg Press", "Quads", "Lateral Deltoids", .none),
            ("Machine Leg Extension", "Quads", "Upper Chest", .none),
            ("Reverse Pec Deck", "Rear Deltoids", "Anterior Deltoids", .none),
            ("Cable Lateral Raise", "Lateral Deltoids", "Anterior Deltoids", .none),
            ("Reverse Pec Deck", "Rear Deltoids", "Front Deltoids", .none),
            ("Uncatalogued Chest Movement", "Chest", "Upper Chest", .none),
            ("Cable Lateral Raise", "Lateral Deltoids", "Hamstrings", .none)
        ]
        for (name, target, focus, expected) in cases {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target, focusArea: focus),
                expected, "\(name) targeting \(target), focus \(focus)")
        }
    }

    // Counterexamples to a two-line raw-membership change: broad requests
    // need directional query expansion without widening explicit metadata membership.
    // These expectations require the focus-local directional query resolver.
    func testCompositeAndPosteriorChainQueriesRetainExplicitComponentCoverage() {
        for (name, target, focus) in [
            ("Leg Press", "Quads", "Quads/Glutes"),
            ("Leg Press", "Quads", "Glutes / Quads"),
            ("Barbell Hip Thrust", "Glutes", "Quads/Glutes"),
            ("Barbell Hip Thrust", "Glutes", "Posterior Chain"),
            ("Nordic Hamstring Curl", "Hamstrings", "Posterior Chain"),
            ("Nordic Hamstring Curl", "Hamstrings", "Posterior-Chain"),
            ("Dumbbell Bulgarian Split Squat", "Quads/Glutes", "Posterior Chain")
        ] {
            XCTAssertEqual(service.focusStimulusKind(exerciseName: name, muscleTarget: target, focusArea: focus),
                .prime, "Broad focus \(focus) should include explicitly primary component \(target)")
        }
    }
}
