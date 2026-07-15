import XCTest
@testable import TransformGeneratorCore

/// Headless, network-free regression tests for the deterministic workout-generation core.
///
/// These drive the procedural (fallback) planning path end to end — the SAME locked menu,
/// weekly set allocation, and validator the AI path uses — with zero Anthropic calls. They
/// are the automated net that was missing when the generator hard-failed on unreachable
/// priority direct-set targets (the "small muscle" DoS). A change that reintroduces that
/// class of bug now fails here instead of on the owner's iPhone.
///
/// The class is @MainActor to tolerate any actor isolation on the generator surface; every
/// method in the chain below is synchronous (throwing), so no awaits are required.
@MainActor
final class DeterministicGenerationTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Input builders

    /// A minimal-but-valid analysis result that drives the given priority muscles.
    /// Empty coaching prose is fine — the deterministic planner keys off `priorityMuscles`
    /// (and, when present, `structuredTrainingIntent`, which we intentionally leave nil here).
    private func analysis(priorities: [String]) -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: "Intermediate lifter, generalist base.",
            trainingAssessment: "",
            nutritionAssessment: "",
            recoveryRiskAssessment: "",
            adherenceAssessment: "",
            analysisLimitations: "",
            inputContext: nil,
            regionBreakdown: [],
            topLeverageChange: "",
            priorityMuscles: priorities,
            workoutRecommendations: [],
            dietRecommendations: [],
            posturalNotes: "",
            estimatedBodyFat: "",
            metabolicHealthNotes: "",
            psychologicalInsights: "",
            injuryRiskNotes: "",
            macroTargets: nil,
            structuredTrainingIntent: nil
        )
    }

    /// Runs the full deterministic chain and returns the validated Week 1 program.
    /// Throws if any locked-menu/allocation/validation stage produces a hard failure.
    private func generateWeekOne(priorities: [String]) throws -> WorkoutProgramResponse {
        let result = analysis(priorities: priorities)
        let intent = service.trainingIntentPlan(from: result)
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        let menus = service.preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: intent,
            weekNumber: 1,
            previousWeekDays: nil
        )
        return try service.validatedProceduralWeekOneProgram(
            from: result,
            trainingIntent: intent,
            blueprint: blueprint,
            exerciseMenus: menus
        )
    }

    // MARK: - Regression: the small-muscle hard-failure

    /// The exact failure class the feasibility fix targets. "Upper Chest" and "Lateral
    /// Deltoids" are small groups whose evidence direct-set target historically outran the
    /// achievable menu-locked ceiling, hard-failing the whole generator (AI path AND the
    /// shared-validator fallback). The deterministic path must now always produce a program.
    func testSmallMusclePrioritiesDoNotHardFail() throws {
        XCTAssertNoThrow(
            try generateWeekOne(priorities: ["Upper Chest", "Lateral Deltoids"]),
            "Small-muscle priorities must not hard-fail the procedural generator"
        )
    }

    // MARK: - Property sweep: no representative priority set hard-fails

    func testRepresentativePrioritiesNeverHardFail() throws {
        let priorityCombos: [[String]] = [
            [],
            ["Upper Chest"],
            ["Lateral Deltoids"],
            ["Rear Deltoids"],
            ["Upper Chest", "Lateral Deltoids", "Rear Deltoids"],
            ["Biceps", "Triceps"],
            ["Hamstrings", "Glutes"],
            ["Back", "Rear Deltoids"],
            ["Calves"],
        ]
        for combo in priorityCombos {
            XCTAssertNoThrow(
                try generateWeekOne(priorities: combo),
                "Priority set \(combo) hard-failed the procedural generator"
            )
        }
    }

    // MARK: - Structural invariants of a generated program

    func testGeneratedProgramIsStructurallyComplete() throws {
        let program = try generateWeekOne(priorities: ["Upper Chest", "Lateral Deltoids"])

        XCTAssertEqual(program.days.count, 7, "A week must describe all 7 calendar days")
        XCTAssertTrue(
            program.days.contains { !$0.isRestDay },
            "A week must contain at least one training day"
        )
        XCTAssertGreaterThan(program.daysPerWeek, 0, "daysPerWeek must be positive")
        XCTAssertFalse(program.programName.isEmpty, "Program must be named")

        // Every non-rest day should carry at least one exercise (no empty training days).
        for day in program.days where !day.isRestDay {
            XCTAssertFalse(
                day.exercises.isEmpty,
                "Training day '\(day.dayName)' has no exercises"
            )
        }
    }
}
