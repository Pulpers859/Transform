import Foundation
import XCTest
@testable import Transform

/// Replays six consecutive 4-week blocks with the block counter taken from the real
/// `ExerciseHistoryAggregator`, in the order the app calls it:
///   * week 1 of a new block is planned while the previous block is still the active program
///     (`planningNewBlock: true`, as `WorkoutView.generateFirstWeek` passes);
///   * weeks 2-4 are planned after that block was archived.
/// Synthetic profile, procedural path only (no paid AI, which cannot change a locked menu anyway).
///
/// Asserts the two things the owner noticed (EvidenceProfile VAR-001 / CONT-001: hold a block
/// fixed, vary between blocks):
///   * consecutive blocks are never identical (measured before the fix: blocks 1 and 2 shared
///     all 29 of their week-2 exercise names);
///   * a block does not change its lineup between week 1 and week 2 beyond 2 exercise names
///     (measured before the fix: rotation landed there, e.g. 6 new names in block 5).
/// Writes the menus to TRANSFORM_BLOCK_ROTATION_OUTPUT when set.
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
        var blockWeekTwo: [[String]] = []
        var weekOneToTwoNew: [Int] = []
        // The app's programs: archived blocks plus the active one. Each trained block carries a
        // stamped session, which is what makes it archived rather than deleted.
        var programs: [WorkoutProgram] = []
        func trainedBlock() -> WorkoutProgram {
            let program = WorkoutProgram(programName: "Block", programSummary: "", splitType: "PPL",
                                         daysPerWeek: 5, focusAreas: "Chest")
            let day = WorkoutDay(dayNumber: 1, dayName: "Push", muscleGroups: "Chest")
            day.sessionStartedAt = Date()
            day.program = program
            program.days.append(day)
            return program
        }

        for block in 0..<6 {
            var previous: [WorkoutDayResponse]?
            var weekOneNames = Set<String>()
            report.append("== Block \(block + 1)")
            for weekNumber in 1...4 {
                let history: ClaudeService.ExerciseHistoryContext
                if weekNumber == 1 {
                    history = ExerciseHistoryAggregator.context(from: programs, planningNewBlock: true)
                    // What generateFirstWeek does once the week is saved.
                    programs.filter { !$0.isArchived }.forEach { $0.isArchived = true }
                    programs.append(trainedBlock())
                } else {
                    history = ExerciseHistoryAggregator.context(from: programs)
                }
                let index = history.mesocycleIndex
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
                if weekNumber == 1 { weekOneNames = Set(names) }
                if weekNumber == 2 {
                    blockWeekTwo.append(names)
                    weekOneToTwoNew.append(Set(names).subtracting(weekOneNames).count)
                }
                previous = days
            }
        }

        report.append("== Week 2 of each block versus the block before")
        for block in 1..<blockWeekTwo.count {
            let before = Set(blockWeekTwo[block - 1]), now = Set(blockWeekTwo[block])
            report.append(" block \(block + 1): \(now.subtracting(before).count) of \(now.count) exercise names new; "
                + "new: \(now.subtracting(before).sorted().joined(separator: ", "))")
        }
        let distinct = Set(blockWeekTwo.flatMap { $0 })
        report.append(" distinct exercise names across all six blocks' week 2: \(distinct.count)")

        report.append("== New exercise names between week 1 and week 2, per block: \(weekOneToTwoNew)")

        XCTAssertEqual(blockWeekTwo.count, 6)
        XCTAssertFalse(blockWeekTwo.contains { $0.isEmpty })
        if let path = ProcessInfo.processInfo.environment["TRANSFORM_BLOCK_ROTATION_OUTPUT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try report.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        for block in 1..<blockWeekTwo.count {
            XCTAssertFalse(Set(blockWeekTwo[block]).subtracting(blockWeekTwo[block - 1]).isEmpty,
                           "Block \(block + 1) repeats block \(block) exactly")
        }
        for (block, count) in weekOneToTwoNew.enumerated() {
            XCTAssertLessThanOrEqual(count, 2, "Block \(block + 1) changed \(count) exercises between week 1 and week 2")
        }
    }
}
