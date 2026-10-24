import Foundation
import XCTest
@testable import Transform

/// Measures how much the exercise menu changes across consecutive 4-week blocks, replaying the
/// block counter the app really passes (`ExerciseHistoryAggregator.context`):
///   * week 1 of a new block is planned while the previous block is still active, so it sees
///     `mesocycleIndex = max(0, block - 1)`;
///   * weeks 2-4 are planned after that block was archived, so they see `mesocycleIndex = block`.
/// Synthetic profile, procedural path only (no paid AI, which cannot change a locked menu anyway).
/// Diagnostic evidence for the owner's "same exercises for months" report; it asserts only that
/// the replay ran, and writes the menus to TRANSFORM_BLOCK_ROTATION_OUTPUT when set.
@MainActor
final class BlockRotationEvidenceTests: XCTestCase {
    private let service = ClaudeService.shared

    private func priority(_ area: String, level: String = "High", days: Int, slots: Int = 3,
                          styles: [String], patterns: [String]) -> StructuredTrainingPriority {
        .init(area: area, priorityLevel: level, rationale: "Synthetic priority.",
            weeklyDayTarget: days, weeklyExerciseTarget: slots, preferredStyles: styles,
            preferredMovementPatterns: patterns, volumeBias: level == "High" ? "High" : "Moderate",
            directWorkBias: level == "High" ? "Direct emphasis" : "Maintenance")
    }

    func testSixConsecutiveBlocksRecordWhatChanges() throws {
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
        let intent = service.trainingIntentPlan(from: analysis)

        var report: [String] = []
        var archivedExercises = Set<String>()
        var blockWeekTwo: [[String]] = []

        for block in 0..<6 {
            var previous: [WorkoutDayResponse]?
            var blockExercises = Set<String>()
            report.append("== Block \(block + 1)")
            for weekNumber in 1...4 {
                let index = weekNumber == 1 ? max(0, block - 1) : block
                let history = ClaudeService.ExerciseHistoryContext(
                    painExercises: [], equipmentSkipExercises: [],
                    priorMesocycleExercises: archivedExercises, mesocycleIndex: index)
                let planned = service.preSelectedExercisePlan(
                    for: service.programBlueprint(for: intent, weekNumber: weekNumber),
                    trainingIntent: intent, weekNumber: weekNumber,
                    previousWeekDays: previous, exerciseHistory: history)
                let days: [WorkoutDayResponse]
                if weekNumber == 1 {
                    days = try service.validatedProceduralWeekOneProgram(
                        from: analysis, trainingIntent: intent,
                        blueprint: planned.blueprint, exerciseMenus: planned.menus).days
                } else {
                    days = try service.validatedProceduralWeek(
                        weekNumber: weekNumber, dayStart: ((weekNumber - 1) * 7) + 1,
                        dayEnd: weekNumber * 7, splitType: intent.splitRecommendation,
                        programName: "Rotation", trainingIntent: intent,
                        blueprint: planned.blueprint, previousWeekDays: previous,
                        exerciseMenus: planned.menus).days
                }
                report.append(" week \(weekNumber) (mesocycleIndex \(index))")
                for (dayIndex, menu) in planned.menus.enumerated() where !menu.isEmpty {
                    report.append("   d\(dayIndex + 1): " + menu.map(\.exerciseName).joined(separator: ", "))
                }
                let names = planned.menus.flatMap { $0.map(\.exerciseName) }
                blockExercises.formUnion(names.map(ExerciseWeightEntry.canonicalLookupKey))
                if weekNumber == 2 { blockWeekTwo.append(names) }
                previous = days
            }
            archivedExercises.formUnion(blockExercises)
        }

        report.append("== Week 2 of each block versus the block before")
        for block in 1..<blockWeekTwo.count {
            let before = Set(blockWeekTwo[block - 1]), now = Set(blockWeekTwo[block])
            report.append(" block \(block + 1): \(now.subtracting(before).count) of \(now.count) exercise names new; "
                + "new: \(now.subtracting(before).sorted().joined(separator: ", "))")
        }
        let distinct = Set(blockWeekTwo.flatMap { $0 })
        report.append(" distinct exercise names across all six blocks' week 2: \(distinct.count)")

        XCTAssertEqual(blockWeekTwo.count, 6)
        XCTAssertFalse(blockWeekTwo.contains { $0.isEmpty })
        if let path = ProcessInfo.processInfo.environment["TRANSFORM_BLOCK_ROTATION_OUTPUT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
