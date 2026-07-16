import XCTest
@testable import Transform

/// Headless, network-free regression tests for the deterministic workout-generation core.
///
/// These drive the procedural (fallback) planning path end to end — the SAME locked menu,
/// weekly set allocation, and validator the AI path uses — with zero Anthropic calls.
///
/// IMPORTANT — two input paths exist and they behave very differently:
///  * STRUCTURED path: analysis carries a `structuredTrainingIntent` (2-3 balanced priorities
///    with day/exercise targets). This is what the AI produces in normal use, and what the
///    owner's real generations go through. These tests assert it works.
///  * LEGACY path: analysis carries only `priorityMuscles` strings (no structured intent).
///    `trainingIntentPlan(from:)` falls back to a weaker builder. The harness discovered this
///    path previously over-generated badly for concentrated priorities (up to 20 exercise
///    variations for one area). `testLegacyPriorityMusclesPathRobustness` keeps that exact
///    failure class covered.
///
/// The class is @MainActor to tolerate any actor isolation on the generator surface; every
/// method in the chain below is synchronous (throwing), so no awaits are required.
@MainActor
final class DeterministicGenerationTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Input builders

    private func priority(
        _ area: String,
        level: String = "High",
        dayTarget: Int = 2,
        exerciseTarget: Int = 3,
        styles: [String] = ["Push", "Upper"],
        patterns: [String] = [],
        volumeBias: String = "High",
        directWorkBias: String = "Direct emphasis"
    ) -> StructuredTrainingPriority {
        StructuredTrainingPriority(
            area: area,
            priorityLevel: level,
            rationale: "Test rationale for \(area).",
            weeklyDayTarget: dayTarget,
            weeklyExerciseTarget: exerciseTarget,
            preferredStyles: styles,
            preferredMovementPatterns: patterns,
            volumeBias: volumeBias,
            directWorkBias: directWorkBias
        )
    }

    /// A realistic analysis carrying a structured training intent — the path real app
    /// generations take.
    private func analysis(
        structured: StructuredTrainingIntent,
        priorityMuscles: [String]
    ) -> BodyAnalysisResult {
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
            priorityMuscles: priorityMuscles,
            workoutRecommendations: [],
            dietRecommendations: [],
            posturalNotes: "",
            estimatedBodyFat: "",
            metabolicHealthNotes: "",
            psychologicalInsights: "",
            injuryRiskNotes: "",
            macroTargets: nil,
            structuredTrainingIntent: structured
        )
    }

    /// A legacy analysis: priority muscles only, no structured intent.
    private func legacyAnalysis(priorities: [String]) -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: "Intermediate lifter, generalist base.",
            trainingAssessment: "", nutritionAssessment: "", recoveryRiskAssessment: "",
            adherenceAssessment: "", analysisLimitations: "", inputContext: nil,
            regionBreakdown: [], topLeverageChange: "",
            priorityMuscles: priorities,
            workoutRecommendations: [], dietRecommendations: [],
            posturalNotes: "", estimatedBodyFat: "", metabolicHealthNotes: "",
            psychologicalInsights: "", injuryRiskNotes: "", macroTargets: nil,
            structuredTrainingIntent: nil
        )
    }

    private func planningInputs(
        from result: BodyAnalysisResult
    ) -> (
        intent: ClaudeService.TrainingIntentPlan,
        blueprint: ClaudeService.ProgramBlueprint,
        menus: [[ClaudeService.PreSelectedExercise]]
    ) {
        let intent = service.trainingIntentPlan(from: result)
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        let menus = service.preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: intent,
            weekNumber: 1,
            previousWeekDays: nil
        )
        return (intent, blueprint, menus)
    }

    /// Runs the full deterministic chain and returns the validated Week 1 program plus the
    /// blueprint needed for invariant checks.
    private func generatePlannedWeekOne(
        from result: BodyAnalysisResult
    ) throws -> (program: WorkoutProgramResponse, blueprint: ClaudeService.ProgramBlueprint) {
        let inputs = planningInputs(from: result)
        let program = try service.validatedProceduralWeekOneProgram(
            from: result,
            trainingIntent: inputs.intent,
            blueprint: inputs.blueprint,
            exerciseMenus: inputs.menus
        )
        return (program, inputs.blueprint)
    }

    private func generateWeekOne(from result: BodyAnalysisResult) throws -> WorkoutProgramResponse {
        try generatePlannedWeekOne(from: result).program
    }

    private func variationDescription(_ violations: [ClaudeService.WeeklyVariationViolation]) -> String {
        violations.map {
            "\($0.area) / \($0.bucket): \($0.count) vs cap \($0.cap)"
        }.joined(separator: " | ")
    }

    private func planningDescription(
        blueprint: ClaudeService.ProgramBlueprint,
        menus: [[ClaudeService.PreSelectedExercise]]
    ) -> String {
        blueprint.dayPlans.enumerated().map { offset, plan in
            let menu = offset < menus.count ? menus[offset] : []
            let exercises = menu.map { "\($0.exerciseName) [\($0.prescribedSets)]" }
                .joined(separator: ", ")
            return "Day \(plan.dayIndex) \(plan.style) focus=\(plan.focusArea ?? "none") "
                + "count=\(menu.count): \(exercises)"
        }.joined(separator: " || ")
    }

    // MARK: - Regression: the reported small-muscle failure (structured-intent path)

    /// Faithful reproduction of the reported bug: a structured intent prioritizing two small,
    /// hard-to-load groups (Upper Chest + Lateral Deltoids) whose evidence direct-set targets
    /// historically outran the achievable menu ceiling and hard-failed the whole generator.
    /// This is the path real generations take. It must produce a program, not throw.
    func testUpperChestLateralDeltReproductionDoesNotHardFail() throws {
        let structured = StructuredTrainingIntent(
            splitRecommendation: "Upper / Lower",
            weeklyTrainingDays: 5,
            priorities: [
                priority("Upper Chest", patterns: ["incline press", "low incline fly"]),
                priority("Lateral Deltoids", patterns: ["lateral raise", "cable lateral raise"]),
            ],
            programmingNotes: ["Emphasize upper chest and side-delt width."]
        )
        let result = analysis(structured: structured, priorityMuscles: ["Upper Chest", "Lateral Deltoids"])
        XCTAssertNoThrow(
            try generateWeekOne(from: result),
            "Structured Upper Chest / Lateral Deltoids intent must not hard-fail the generator"
        )
    }

    /// Reproduces the 2026-07-15 on-device report: a five-day recomp plan with Upper Chest,
    /// Lateral Deltoids, and Core/Abs priorities produced a locked Lower menu with no direct
    /// hamstring movement, then accepted the resulting BASE-001 warning. The menu builder must
    /// own this floor before any AI call is made.
    func testPhoneValidatorReportKeepsBaselineHamstringCoverage() throws {
        let structured = StructuredTrainingIntent(
            splitRecommendation: "Upper/Lower with a dedicated push emphasis",
            weeklyTrainingDays: 5,
            priorities: [
                priority(
                    "Upper Chest",
                    level: "High",
                    dayTarget: 2,
                    exerciseTarget: 3,
                    styles: ["Push", "Upper"],
                    patterns: ["incline barbell press", "incline dumbbell press", "low incline fly", "upper chest", "clavicular", "incline press"]
                ),
                priority(
                    "Lateral Deltoids",
                    level: "High",
                    dayTarget: 3,
                    exerciseTarget: 3,
                    styles: ["Push", "Upper", "Arms"],
                    patterns: ["cable lateral raise", "dumbbell lateral raise", "lateral delt", "lateral raise"]
                ),
                priority(
                    "Core/Abs",
                    level: "Medium",
                    dayTarget: 2,
                    exerciseTarget: 2,
                    styles: ["Upper", "Lower"],
                    patterns: ["weighted cable crunch", "hanging leg raise", "oblique"],
                    volumeBias: "Moderate",
                    directWorkBias: "Maintenance"
                )
            ],
            programmingNotes: [
                "Keep total weekly volume recoverable given short sleep and a mild deficit.",
                "Hold lower-body volume at maintenance while protecting baseline coverage."
            ]
        )
        let result = BodyAnalysisResult(
            overallAssessment: "Body recomposition with visible abs; adequate lower-body mass.",
            trainingAssessment: "Prioritize upper chest and lateral deltoids while maintaining the lower body.",
            nutritionAssessment: "No nutrition logs were recorded during the deficit.",
            recoveryRiskAssessment: "Short sleep and shift work constrain recovery.",
            adherenceAssessment: "Nutrition adherence could not be verified.",
            analysisLimitations: "",
            inputContext: nil,
            regionBreakdown: [],
            topLeverageChange: "Sustain the mild deficit.",
            priorityMuscles: ["Upper Chest", "Lateral Deltoids", "Rectus Abdominis"],
            workoutRecommendations: [],
            dietRecommendations: [],
            posturalNotes: "",
            estimatedBodyFat: "19-21%",
            metabolicHealthNotes: "",
            psychologicalInsights: "",
            injuryRiskNotes: "",
            macroTargets: nil,
            structuredTrainingIntent: structured
        )

        let inputs = planningInputs(from: result)
        let hamstringAliases = service.normalizedGroupAliases(forSeed: "hamstrings")
        let hasDirectHamstringMenu = inputs.menus.joined().contains {
            service.exerciseDirectlyTargets(
                groupAliases: hamstringAliases,
                exerciseName: $0.exerciseName,
                muscleTarget: $0.muscleTarget
            )
        }

        XCTAssertTrue(
            hasDirectHamstringMenu,
            "Phone-shaped plan omitted direct hamstring coverage: "
                + planningDescription(blueprint: inputs.blueprint, menus: inputs.menus)
        )

        let program = try service.validatedProceduralWeekOneProgram(
            from: result,
            trainingIntent: inputs.intent,
            blueprint: inputs.blueprint,
            exerciseMenus: inputs.menus
        )
        let issues = service.validateProgramResponse(program, blueprint: inputs.blueprint)
        XCTAssertFalse(
            issues.contains { $0.contains("Muscle group 'Hamstrings' receives zero direct sets this week") },
            "Phone-shaped plan still reaches validation with zero hamstring sets: \(issues)"
        )
    }

    /// A handful of realistic structured intents across body regions must all generate.
    func testRealisticStructuredIntentsGenerate() throws {
        let cases: [(String, StructuredTrainingIntent)] = [
            ("back+rear delt", StructuredTrainingIntent(
                splitRecommendation: "Push / Pull / Legs",
                weeklyTrainingDays: 6,
                priorities: [
                    priority("Back", styles: ["Pull", "Upper"], patterns: ["row", "pulldown"]),
                    priority("Rear Deltoids", level: "Medium", dayTarget: 2, exerciseTarget: 2,
                             styles: ["Pull", "Upper"], patterns: ["reverse fly"]),
                ],
                programmingNotes: ["Back thickness focus."]
            )),
            ("arms", StructuredTrainingIntent(
                splitRecommendation: "Upper / Lower",
                weeklyTrainingDays: 5,
                priorities: [
                    priority("Biceps", styles: ["Pull", "Arms"], patterns: ["curl"]),
                    priority("Triceps", styles: ["Push", "Arms"], patterns: ["extension"]),
                ],
                programmingNotes: ["Arm hypertrophy block."]
            )),
            ("legs", StructuredTrainingIntent(
                splitRecommendation: "Upper / Lower",
                weeklyTrainingDays: 4,
                priorities: [
                    priority("Hamstrings", styles: ["Legs", "Lower"], patterns: ["hip hinge"]),
                    priority("Glutes", level: "Medium", styles: ["Legs", "Lower"], patterns: ["hip thrust"]),
                ],
                programmingNotes: ["Posterior-chain emphasis."]
            )),
        ]
        for (label, structured) in cases {
            let muscles = structured.priorities.map(\.area)
            XCTAssertNoThrow(
                try generateWeekOne(from: analysis(structured: structured, priorityMuscles: muscles)),
                "Realistic structured intent '\(label)' hard-failed the generator"
            )
        }
    }

    func testStructuredPlansRespectWeeklyVariationBudgets() throws {
        let cases: [(String, StructuredTrainingIntent)] = [
            ("broad back", StructuredTrainingIntent(
                splitRecommendation: "Push / Pull / Legs",
                weeklyTrainingDays: 6,
                priorities: [
                    priority("Back", styles: ["Pull", "Upper"], patterns: ["row", "pulldown"]),
                    priority("Rear Deltoids", level: "Medium", dayTarget: 2, exerciseTarget: 2,
                             styles: ["Pull", "Upper"], patterns: ["reverse fly"]),
                ],
                programmingNotes: ["Build lat width and upper-back thickness."]
            )),
            ("broad arms", StructuredTrainingIntent(
                splitRecommendation: "Upper / Lower",
                weeklyTrainingDays: 5,
                priorities: [
                    priority("Arms", styles: ["Arms", "Upper"], patterns: ["curl", "extension"]),
                ],
                programmingNotes: ["Repeatable arm specialization."]
            )),
        ]

        for (label, structured) in cases {
            let result = analysis(
                structured: structured,
                priorityMuscles: structured.priorities.map(\.area)
            )
            let generated = try generatePlannedWeekOne(from: result)
            let violations = service.weeklyVariationViolations(
                in: generated.program.days,
                blueprint: generated.blueprint
            )
            XCTAssertTrue(
                violations.isEmpty,
                "Structured intent '\(label)' exceeded weekly variation budgets: \(variationDescription(violations))"
            )
        }
    }

    func testBroadBackVariationBudgetIsSubregionAware() {
        let structured = StructuredTrainingIntent(
            splitRecommendation: "Push / Pull / Legs",
            weeklyTrainingDays: 6,
            priorities: [
                priority("Back", styles: ["Pull", "Upper"], patterns: ["row", "pulldown"]),
            ],
            programmingNotes: []
        )
        let result = analysis(structured: structured, priorityMuscles: ["Back"])
        let intent = service.trainingIntentPlan(from: result)
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)

        let balancedBack: [(name: String, target: String)] = [
            ("Pull-Up (Weighted or Assisted)", "Lats"),
            ("Lat Pulldown", "Lats"),
            ("Straight-Arm Pulldown", "Lats"),
            ("Single-Arm Dumbbell Row", "Lats"),
            ("Chest-Supported Row", "Upper Back"),
            ("Chest-Supported T-Bar Row", "Upper Back"),
            ("Wide-Grip Cable Row", "Upper Back"),
            ("Machine Row", "Mid Back"),
        ]
        XCTAssertTrue(
            service.weeklyVariationViolations(for: balancedBack, blueprint: blueprint).isEmpty,
            "Four lat and four upper/mid-back exercises should fit separate Back sub-region budgets"
        )

        let latHeavy = balancedBack + [(name: "Neutral-Grip Lat Pulldown", target: "Lats")]
        let violations = service.weeklyVariationViolations(for: latHeavy, blueprint: blueprint)
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.bucket, "Lat width")
        XCTAssertEqual(violations.first?.count, 5)
        XCTAssertEqual(violations.first?.cap, 4)
    }

    func testDirectSetCreditRequiresPrimaryMetadataMatch() {
        let genericPress = WorkoutExerciseResponse(
            exerciseName: "Dumbbell Bench Press",
            sets: 3,
            reps: "8-10",
            tempo: "",
            restSeconds: 90,
            notes: "",
            muscleTarget: "Chest"
        )
        let inclinePress = WorkoutExerciseResponse(
            exerciseName: "Incline Dumbbell Press",
            sets: 3,
            reps: "8-10",
            tempo: "",
            restSeconds: 90,
            notes: "",
            muscleTarget: "Upper Chest"
        )

        XCTAssertEqual(service.directSetCredit(for: genericPress, area: "Upper Chest"), 0)
        XCTAssertGreaterThan(service.weightedStimulusCredit(for: genericPress, area: "Upper Chest"), 0)
        XCTAssertEqual(service.directSetCredit(for: inclinePress, area: "Upper Chest"), 3)
    }

    func testAllocatedMenusMatchValidatorStimulusLedger() {
        let cases = [
            legacyAnalysis(priorities: ["Upper Chest"]),
            legacyAnalysis(priorities: ["Back", "Rear Deltoids"]),
            legacyAnalysis(priorities: ["Calves"]),
        ]

        for result in cases {
            let inputs = planningInputs(from: result)
            let issues = service.allocationLedgerConsistencyIssues(
                inputs.menus,
                blueprint: inputs.blueprint
            )
            XCTAssertTrue(
                issues.isEmpty,
                "Allocator and validator ledgers diverged: \(issues.joined(separator: " | "))"
            )
        }
    }

    // MARK: - Structural invariants of a generated program

    func testGeneratedProgramIsStructurallyComplete() throws {
        let structured = StructuredTrainingIntent(
            splitRecommendation: "Upper / Lower",
            weeklyTrainingDays: 5,
            priorities: [
                priority("Upper Chest", patterns: ["incline press"]),
                priority("Lateral Deltoids", patterns: ["lateral raise"]),
            ],
            programmingNotes: ["Upper-body emphasis."]
        )
        let result = analysis(structured: structured, priorityMuscles: ["Upper Chest", "Lateral Deltoids"])
        let inputs = planningInputs(from: result)
        print("BASELINE DEBUG structural: " + planningDescription(blueprint: inputs.blueprint, menus: inputs.menus))
        let program = try service.validatedProceduralWeekOneProgram(
            from: result,
            trainingIntent: inputs.intent,
            blueprint: inputs.blueprint,
            exerciseMenus: inputs.menus
        )

        XCTAssertEqual(program.days.count, 7, "A week must describe all 7 calendar days")
        XCTAssertTrue(program.days.contains { !$0.isRestDay }, "A week must contain a training day")
        XCTAssertGreaterThan(program.daysPerWeek, 0, "daysPerWeek must be positive")
        XCTAssertFalse(program.programName.isEmpty, "Program must be named")
        for day in program.days where !day.isRestDay {
            XCTAssertFalse(day.exercises.isEmpty, "Training day '\(day.dayName)' has no exercises")
        }
    }

    // MARK: - Regression: legacy priorityMuscles path over-generation

    /// These are the concentrated legacy combinations from the original failing CI sweep. They
    /// must generate and stay inside the same weekly variation policy as structured production
    /// inputs; a validator-clean result alone is not enough.
    func testLegacyPriorityMusclesPathRobustness() throws {
        let combinations = [
            ["Upper Chest"],
            ["Biceps", "Triceps"],
            ["Hamstrings", "Glutes"],
            ["Back", "Rear Deltoids"],
            ["Calves"],
        ]

        for combo in combinations {
            let result = legacyAnalysis(priorities: combo)
            let inputs = planningInputs(from: result)
            for (index, menu) in inputs.menus.enumerated()
                where !inputs.blueprint.dayPlans[index].isRestDay {
                XCTAssertGreaterThanOrEqual(
                    menu.count,
                    5,
                    "Legacy priority set \(combo) produced a short locked menu on day \(index + 1): "
                        + planningDescription(blueprint: inputs.blueprint, menus: inputs.menus)
                )
            }
            do {
                let program = try service.validatedProceduralWeekOneProgram(
                    from: result,
                    trainingIntent: inputs.intent,
                    blueprint: inputs.blueprint,
                    exerciseMenus: inputs.menus
                )
                let violations = service.weeklyVariationViolations(
                    in: program.days,
                    blueprint: inputs.blueprint
                )
                XCTAssertTrue(
                    violations.isEmpty,
                    "Legacy priority set \(combo) exceeded weekly variation budgets: \(variationDescription(violations))"
                )
            } catch {
                XCTFail(
                    "Legacy priority set \(combo) hard-failed: \(error). Planning snapshot: "
                        + planningDescription(blueprint: inputs.blueprint, menus: inputs.menus)
                )
            }
        }
    }
}
