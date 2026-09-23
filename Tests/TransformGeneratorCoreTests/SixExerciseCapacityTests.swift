import Foundation
import XCTest
@testable import Transform

/// Diagnostic trials only: six-slot reservation is not adopted into live generation.
@MainActor
final class SixExerciseCapacityTests: XCTestCase {
    private let service = ClaudeService.shared

    private func slot(_ name: String, _ target: String) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
            movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
            role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: 1)
    }

    func testOptionalCapacityUsesTheSharedReservationAndRespectsProtectedSlots() {
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "capacity-control", splitRecommendation: "Upper",
            weeklyTrainingDays: 1, priorityAllocations: [], dayPlans: [
                .init(dayIndex: 1, style: "Upper", focusArea: nil, supportAreas: [], targetFatigueCap: 48,
                    targetSessionMinutes: 75, targetPrioritySlots: 0, emphasisPatterns: [], isRestDay: false)
            ], topLeverageChange: "", posturalFocus: "", injuryRiskFocus: "", programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        let menus = [[slot("EZ-Bar Curl", "Biceps"), slot("Incline Dumbbell Curl", "Biceps"),
            slot("Rope Triceps Pressdown", "Triceps"), slot("Machine Chest Press", "Chest"),
            slot("Seated Cable Row", "Mid Back"), slot("Cable Lateral Raise", "Lateral Deltoids"),
            slot("Cable Crunch", "Abs")]]
        let normal = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1)
        guard case .admitted = normal.outcome else { return XCTFail("Control must fit other budgets: \(normal.outcome)") }
        XCTAssertEqual(normal.menus[0].count, 7)
        let limited = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1,
            maximumExercisesPerDay: 6)
        guard case .admitted = limited.outcome else { return XCTFail("Redundant unprotected curl can fit: \(limited.outcome)") }
        XCTAssertEqual(limited.menus[0].count, 6)
        XCTAssertEqual(limited.menus[0].first?.exerciseName, menus[0].first?.exerciseName)
        XCTAssertEqual(Set(limited.menus[0].map(\.muscleTarget)), Set(menus[0].map(\.muscleTarget)))
        let protected = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1,
            lockedPrefixCounts: [7], maximumExercisesPerDay: 6)
        guard case .infeasible(let conflicts) = protected.outcome else {
            return XCTFail("Seven protected slots cannot fit six: \(protected.outcome)")
        }
        XCTAssertTrue(conflicts.contains("Day 1 exercise ceiling"))
        XCTAssertEqual(protected.menus[0].map(\.exerciseName), menus[0].map(\.exerciseName))
        let exhausted = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1,
            maximumStates: 0, maximumExercisesPerDay: 6)
        guard case .searchLimit = exhausted.outcome else { return XCTFail("No search is not infeasibility") }
        let belowFloor = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1,
            maximumExercisesPerDay: 4)
        guard case .infeasible = belowFloor.outcome else { return XCTFail("Ceiling cannot override floor five") }
    }

    // Exact synthetic persona definitions from UserJourneySimulationTests. Kept local so this
    // bounded diagnostic does not change the existing journey harness or its evidence schema.
    private struct Persona {
        let name: String
        let days: Int
        let priorities: [(area: String, level: String, styles: [String])]
        let injuryNotes: String
        let posturalNotes: String
    }
    private var personas: [Persona] { [
        .init(name: "Six-day push/pull/legs, back focus, no injuries", days: 6,
            priorities: [("Back", "High", ["Pull", "Upper"]), ("Rear Deltoids", "Medium", ["Pull", "Upper"])],
            injuryNotes: "", posturalNotes: "Mild forward head posture."),
        .init(name: "Four-day beginner with a shoulder that hurts overhead", days: 4,
            priorities: [("Chest", "High", ["Push", "Upper"]), ("Quads", "Medium", ["Legs", "Lower"])],
            injuryNotes: "Right shoulder pain with overhead pressing. No pain on rows.", posturalNotes: "Rounded shoulders."),
        .init(name: "Five-day lifter reporting lumbar-extension pain", days: 5,
            priorities: [("Hamstrings", "High", ["Legs", "Lower"]), ("Lats", "Medium", ["Pull", "Upper"])],
            injuryNotes: "Lower back pain with lumbar extension.", posturalNotes: "Anterior pelvic tilt."),
        .init(name: "Compound priority area, small muscles", days: 5,
            priorities: [("Lateral Deltoids", "High", ["Push", "Upper"]), ("Calves", "Medium", ["Legs", "Lower"])],
            injuryNotes: "", posturalNotes: ""),
        .init(name: "Arms specialisation on four days", days: 4,
            priorities: [("Biceps", "High", ["Pull", "Arms"]), ("Triceps", "High", ["Push", "Arms"])],
            injuryNotes: "Occasional elbow discomfort on skull crushers.", posturalNotes: "")
    ] }
    private func analysis(for persona: Persona) -> BodyAnalysisResult {
        let structured = StructuredTrainingIntent(
            splitRecommendation: persona.days >= 6 ? "Push / Pull / Legs" : "Upper / Lower",
            weeklyTrainingDays: persona.days, priorities: persona.priorities.map { entry in
                StructuredTrainingPriority(area: entry.area, priorityLevel: entry.level,
                    rationale: "Simulation rationale for \(entry.area).", weeklyDayTarget: entry.level == "High" ? 2 : 1,
                    weeklyExerciseTarget: entry.level == "High" ? 3 : 2, preferredStyles: entry.styles,
                    preferredMovementPatterns: [], volumeBias: entry.level == "High" ? "High" : "Moderate",
                    directWorkBias: "Direct emphasis")
            }, programmingNotes: ["Simulation persona: \(persona.name)."])
        return BodyAnalysisResult(overallAssessment: "Simulated athlete.", trainingAssessment: "", nutritionAssessment: "",
            recoveryRiskAssessment: "", adherenceAssessment: "", analysisLimitations: "", inputContext: nil,
            regionBreakdown: [], topLeverageChange: "", priorityMuscles: persona.priorities.map(\.area),
            workoutRecommendations: [], dietRecommendations: [], posturalNotes: persona.posturalNotes,
            estimatedBodyFat: "", metabolicHealthNotes: "", psychologicalInsights: "", injuryRiskNotes: persona.injuryNotes,
            macroTargets: nil, structuredTrainingIntent: structured)
    }

    func testTraceFiveCompleteWeekOnePlansWithOptionalSixSlotReservation() throws {
        var report = ["SIX_SLOT_DIAGNOSTIC: five synthetic Week 1 plans; no adoption, no device proof.",
            "Reservation proves role-floor subset feasibility only; fresh allocation/dose comparison is reported separately."]
        var processed = 0
        var expectedCrowded = 0
        for persona in personas {
            let intent = service.trainingIntentPlan(from: analysis(for: persona))
            let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
            var phases: [(String, [[ClaudeService.PreSelectedExercise]])] = []
            var baseline: ClaudeService.SubstitutionPlanningBaseline?
            let delivered = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent, weekNumber: 1,
                previousWeekDays: nil, exerciseHistory: nil,
                menuPlanningTrace: { phases.append(($0, $1)) }, rowPlanningReport: { baseline = $0; _ = $1 })
            let funded = try XCTUnwrap(baseline)
            let effectiveBlueprint = funded.blueprint
            let candidate = try XCTUnwrap(phases.first { $0.0 == "sessionOrder" }).1
            let saved = signature(delivered.menus)
            XCTAssertEqual(candidate.count, 7)
            processed += 1
            let crowded = candidate.contains { $0.count > 6 }
            if crowded { expectedCrowded += 1 }
            XCTAssertTrue(crowded, "The historical Week 1 candidate must exercise the over-six diagnostic: \(persona.name)")
            report.append("PERSONA \(persona.name)")
            report.append("BASELINE admission=\(funded.roleFloorAdmission) counts=\(funded.menus.map(\.count))")
            for day in candidate.indices where !effectiveBlueprint.dayPlans[day].isRestDay {
                let first = phases.indices.first { phases[$0].1[day].count > 6 }
                let transition = first.map { $0 == 0 ? phases[$0].0 : "\(phases[$0 - 1].0)->\(phases[$0].0)" } ?? "none"
                report.append("DAY \(day + 1) style=\(effectiveBlueprint.dayPlans[day].style) firstOverSix=\(transition) phaseCounts=\(phases.map { "\($0.0):\($0.1[day].count)" }.joined(separator: ","))")
            }
            report.append("CANDIDATE \(signature(candidate))")
            let result = service.reserveWeeklyAppearanceFloors(candidate, blueprint: effectiveBlueprint, weekNumber: 1,
                lockedPrefixCounts: funded.lockedPrefixCounts, maximumExercisesPerDay: 6)
            report.append("RESERVATION outcome=\(result.outcome) counts=\(result.menus.map(\.count))")
            if case .admitted = result.outcome {
                XCTAssertTrue(result.menus.indices.allSatisfy {
                    effectiveBlueprint.dayPlans[$0].isRestDay ? result.menus[$0].isEmpty : (5...6).contains(result.menus[$0].count)
                })
                var admission: ClaudeService.RoleFloorAdmission = .unassessed
                let allocated = service.allocateWeeklySetPrescription(result.menus, blueprint: effectiveBlueprint, weekNumber: 1,
                    lockedPrefixCounts: funded.lockedPrefixCounts, roleFloorAdmissionReport: { admission = $0 },
                    publishConflictLogs: false)
                let dose = service.compareAllocatedDoseOnly(allocated, baseline: funded.menus, blueprint: effectiveBlueprint, weekNumber: 1)
                report.append("FRESH_ALLOCATION admission=\(admission) counts=\(allocated.map(\.count)) dose=\(dose)")
                report.append("FUNDED_BASELINE \(signature(funded.menus))")
                report.append("FUNDED_CANDIDATE \(signature(allocated))")
            } else {
                XCTAssertEqual(signature(result.menus), signature(candidate), "Refused reservation must retain the candidate")
            }
            XCTAssertEqual(signature(delivered.menus), saved, "Diagnostics never mutate the actual delivered plan")
        }
        XCTAssertEqual(processed, 5)
        XCTAssertEqual(expectedCrowded, 5, "All five historical Week 1 profiles must exercise the capacity problem")
        report.append("SUMMARY processed=\(processed) expectedCrowded=\(expectedCrowded)")
        let output = report.joined(separator: "\n")
        print(output)
        if let path = ProcessInfo.processInfo.environment["TRANSFORM_SIX_SLOT_REPORT_OUTPUT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func signature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
        menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role.rawValue)|\($0.prescribedSets)" } }
    }
}
