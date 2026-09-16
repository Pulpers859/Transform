import Foundation
import XCTest
@testable import Transform

/// Synthetic shape replay only: no owner analysis, photos, logs, dates or history.
/// Findings are diagnostic evidence, not assertions that historical defects should persist.
@MainActor
final class OwnerPlanningReplayTests: XCTestCase {
    private let service = ClaudeService.shared

    private func priority(_ area: String, level: String = "High", days: Int,
                          slots: Int = 3, styles: [String], patterns: [String]) -> StructuredTrainingPriority {
        .init(area: area, priorityLevel: level, rationale: "Synthetic priority.",
            weeklyDayTarget: days, weeklyExerciseTarget: slots, preferredStyles: styles,
            preferredMovementPatterns: patterns, volumeBias: level == "High" ? "High" : "Moderate",
            directWorkBias: level == "High" ? "Direct emphasis" : "Maintenance")
    }

    func testSyntheticFiveDayConstrainedPlanningReplay() throws {
        let structured = StructuredTrainingIntent(
            splitRecommendation: "Upper/Lower or Push/Pull/Legs over 5 days", weeklyTrainingDays: 5,
            priorities: [
                priority("Upper Chest", days: 2, styles: ["Push", "Upper"],
                    patterns: ["incline barbell press", "incline dumbbell press", "low-to-high cable fly", "clavicular", "incline press"]),
                priority("Lateral Deltoids", days: 3, styles: ["Push", "Upper", "Arms"],
                    patterns: ["cable lateral raise", "dumbbell lateral raise", "lateral delt", "lateral raise"]),
                priority("Core/Abs", level: "Medium", days: 2, slots: 2, styles: ["Upper", "Legs"],
                    patterns: ["cable crunch", "hanging or lying leg raise", "abdominal", "oblique", "serratus", "crunch"])
            ], programmingNotes: ["Keep specialization volume recoverable."])
        let analysis = BodyAnalysisResult(
            overallAssessment: "Synthetic body recomposition profile.", trainingAssessment: "",
            nutritionAssessment: "No nutrition logs were recorded.",
            recoveryRiskAssessment: "Variable sleep from shift-work includes some nights under 5 hours.",
            adherenceAssessment: "", analysisLimitations: "", inputContext: nil, regionBreakdown: [],
            topLeverageChange: "", priorityMuscles: ["Upper Chest", "Lateral Deltoids", "Rectus Abdominis"],
            workoutRecommendations: [], dietRecommendations: [], posturalNotes: "", estimatedBodyFat: "",
            metabolicHealthNotes: "", psychologicalInsights: "",
            injuryRiskNotes: "Shoulder pain during neutral-grip overhead pressing.", macroTargets: nil,
            structuredTrainingIntent: structured)
        // Do not read or mutate shared UserDefaults; inject missing measured sleep explicitly.
        let calibration = service.calibrationProfile(from: analysis,
            recoveryDecision: SleepRecoveryPolicy.decision(from: nil))
        XCTAssertEqual(calibration.recoveryTier, .constrained)
        XCTAssertTrue(calibration.recoveryAudit.contains("no fresh sleep logs"))
        let base = ClaudeService.TrainingIntentPlan(
            splitRecommendation: structured.splitRecommendation, weeklyTrainingDays: structured.weeklyTrainingDays,
            programmingNotes: structured.programmingNotes,
            priorities: service.mergedPriorityIntents(structured.priorities.enumerated().map {
                service.musclePriorityIntent(from: $0.element, rank: $0.offset, analysis: analysis)
            }), topLeverageChange: "(not provided)", posturalFocus: "(none)",
            injuryRiskFocus: service.resolvedInjuryRiskFocus(from: analysis),
            calibration: service.neutralCalibrationProfile())
        let intent = service.calibratedTrainingIntentPlan(base, using: calibration)
        let initialBlueprint = service.programBlueprint(for: intent, weekNumber: 1)
        var baseline: ClaudeService.SubstitutionPlanningBaseline?
        var pressdown: ClaudeService.PressdownFinalization?
        var preCore: ClaudeService.SubstitutionPlanningBaseline?
        var core: ClaudeService.CoreRelocationFinalization?
        var diagnostics: [String] = []
        var callbackCounts = [0, 0]
        let delivered = service.preSelectedExercisePlan(for: initialBlueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: nil,
            appearancePlanningReport: { diagnostics.append($0) },
            pressdownPlanningReport: { baseline = $0; pressdown = $1; callbackCounts[0] += 1 },
            corePlanningReport: { preCore = $0; core = $1; callbackCounts[1] += 1 })
        XCTAssertEqual(callbackCounts, [1, 1])
        let original = try XCTUnwrap(baseline)
        let pressdownResult = try XCTUnwrap(pressdown)
        let coreInput = try XCTUnwrap(preCore)
        let coreResult = try XCTUnwrap(core)
        XCTAssertEqual(snapshot(coreInput.menus), snapshot(pressdownResult.plan.menus))
        XCTAssertEqual(snapshot(delivered.menus), snapshot(coreResult.plan.menus))
        XCTAssertEqual(delivered.blueprint, coreResult.plan.blueprint)
        let program = try service.validatedProceduralWeekOneProgram(from: analysis, trainingIntent: intent,
            blueprint: delivered.blueprint, exerciseMenus: delivered.menus)
        let findings = service.validateProgramResponse(program, blueprint: delivered.blueprint,
            expectedExerciseMenus: delivered.menus)
        XCTAssertEqual(program.days.count, 7)
        XCTAssertEqual(program.days.filter { !$0.isRestDay }.count, 5)
        XCTAssertEqual(program.days.count, delivered.menus.count)
        for (day, menu) in zip(program.days, delivered.menus) {
            XCTAssertEqual(day.exercises.map(\.exerciseName), menu.map(\.exerciseName))
            XCTAssertEqual(day.exercises.map(\.sets), menu.map(\.prescribedSets))
            XCTAssertTrue(day.exercises.allSatisfy { $0.sets > 0 })
            XCTAssertTrue(day.isRestDay ? day.exercises.isEmpty : !day.exercises.isEmpty)
        }
        let evidence = ReplayEvidence(analysis: analysis,
            initialBlueprint: BlueprintEvidence(initialBlueprint), blueprint: BlueprintEvidence(delivered.blueprint),
            baselineMenus: snapshot(original.menus), postPressdownMenus: snapshot(pressdownResult.plan.menus),
            menus: snapshot(delivered.menus), days: program.days, validatorFindings: findings,
            baselineAdmission: String(describing: original.roleFloorAdmission),
            pressdownDecision: String(describing: pressdownResult.decision),
            coreDecision: String(describing: coreResult.decision), diagnostics: diagnostics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(evidence)
        // Check the export schema even when no artifact destination was requested.
        _ = try JSONDecoder().decode(ReplayEvidence.self, from: data)
        if let path = ProcessInfo.processInfo.environment["TRANSFORM_OWNER_REPLAY_OUTPUT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    private func snapshot(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[MenuEvidence]] {
        menus.map { $0.map { MenuEvidence(exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget,
            movementPattern: $0.movementPattern, role: $0.role.rawValue, prescribedSets: $0.prescribedSets) } }
    }

    private struct MenuEvidence: Codable, Equatable {
        let exerciseName: String
        let muscleTarget: String
        let movementPattern: String
        let role: String
        let prescribedSets: Int
    }

    private struct ReplayEvidence: Codable {
        var schemaVersion = 1
        var scope = "Synthetic network-free procedural replay; no private history, live AI, or iPhone/UI validation."
        let analysis: BodyAnalysisResult
        let initialBlueprint: BlueprintEvidence
        let blueprint: BlueprintEvidence
        let baselineMenus: [[MenuEvidence]]
        let postPressdownMenus: [[MenuEvidence]]
        let menus: [[MenuEvidence]]
        let days: [WorkoutDayResponse]
        let validatorFindings: [String]
        let baselineAdmission: String
        let pressdownDecision: String
        let coreDecision: String
        let diagnostics: [String]
    }

    private struct BlueprintEvidence: Codable {
        let evidenceVersion: String
        let splitRecommendation: String
        let weeklyTrainingDays: Int
        let priorityAllocations: [PriorityEvidence]
        let dayPlans: [DayEvidence]
        let topLeverageChange: String
        let posturalFocus: String
        let injuryRiskFocus: String
        let programmingNotes: [String]
        let calibration: CalibrationEvidence
        init(_ value: ClaudeService.ProgramBlueprint) {
            evidenceVersion = value.evidenceVersion; splitRecommendation = value.splitRecommendation
            weeklyTrainingDays = value.weeklyTrainingDays
            priorityAllocations = value.priorityAllocations.map(PriorityEvidence.init)
            dayPlans = value.dayPlans.map(DayEvidence.init)
            topLeverageChange = value.topLeverageChange; posturalFocus = value.posturalFocus
            injuryRiskFocus = value.injuryRiskFocus; programmingNotes = value.programmingNotes
            calibration = CalibrationEvidence(value.calibration)
        }
    }

    private struct PriorityEvidence: Codable {
        let area: String, priorityLevel: String, rationale: String
        let targetFrequency: Int, targetExerciseSlots: Int
        let directSetTarget: Double, weightedStimulusTarget: Double
        let maxPerSessionDirectSets: Double, maxFocusSessionDirectSets: Double
        let preferredStyles: [String], preferredMovementPatterns: [String]
        let volumeBias: String, directWorkBias: String
        init(_ value: ClaudeService.BlueprintPriorityAllocation) {
            area = value.area; priorityLevel = value.priorityLevel; rationale = value.rationale
            targetFrequency = value.targetFrequency; targetExerciseSlots = value.targetExerciseSlots
            directSetTarget = value.directSetTarget; weightedStimulusTarget = value.weightedStimulusTarget
            maxPerSessionDirectSets = value.maxPerSessionDirectSets; maxFocusSessionDirectSets = value.maxFocusSessionDirectSets
            preferredStyles = value.preferredStyles; preferredMovementPatterns = value.preferredMovementPatterns
            volumeBias = value.volumeBias; directWorkBias = value.directWorkBias
        }
    }

    private struct DayEvidence: Codable {
        let dayIndex: Int
        let style: String, focusArea: String?
        let supportAreas: [String]
        let targetFatigueCap: Int, targetSessionMinutes: Int, targetPrioritySlots: Int
        let emphasisPatterns: [String]
        let isRestDay: Bool
        init(_ value: ClaudeService.BlueprintDayPlan) {
            dayIndex = value.dayIndex; style = value.style; focusArea = value.focusArea
            supportAreas = value.supportAreas; targetFatigueCap = value.targetFatigueCap
            targetSessionMinutes = value.targetSessionMinutes; targetPrioritySlots = value.targetPrioritySlots
            emphasisPatterns = value.emphasisPatterns; isRestDay = value.isRestDay
        }
    }

    private struct CalibrationEvidence: Codable {
        let lowPerformanceDataQuality: Bool, poorNutritionAdherence: Bool, recoveryConstrained: Bool
        let recoveryTier: String, recoveryAudit: String
        let recompositionGoal: Bool
        let weeklyVolumeScale: Double
        let reduceExerciseSlotComplexity: Bool
        let defaultSessionTimeCapMinutes: Int
        let sessionTimeCapsByStyle: [String: Int]
        let programmingNotes: [String]
        init(_ value: ClaudeService.ProgramCalibrationProfile) {
            lowPerformanceDataQuality = value.lowPerformanceDataQuality; poorNutritionAdherence = value.poorNutritionAdherence
            recoveryConstrained = value.recoveryConstrained; recoveryTier = String(describing: value.recoveryTier)
            recoveryAudit = value.recoveryAudit; recompositionGoal = value.recompositionGoal
            weeklyVolumeScale = value.weeklyVolumeScale; reduceExerciseSlotComplexity = value.reduceExerciseSlotComplexity
            defaultSessionTimeCapMinutes = value.defaultSessionTimeCapMinutes
            sessionTimeCapsByStyle = value.sessionTimeCapsByStyle; programmingNotes = value.programmingNotes
        }
    }
}
