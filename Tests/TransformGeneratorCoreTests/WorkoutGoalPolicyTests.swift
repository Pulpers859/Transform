import Foundation
import XCTest
@testable import Transform

@MainActor
final class WorkoutGoalPolicyTests: XCTestCase {
    private let service = ClaudeService.shared

    private func profile(_ goal: String, policy: WorkoutGoalPolicy?) -> AnalysisProfileSnapshot {
        AnalysisProfileSnapshot(age: "", sex: "", build: "", height: "", currentWeight: "",
            occupation: "", trainingFrequency: "5 days/week", trainingAge: "",
            equipmentAccess: "Full gym", averageSleep: "", painHistory: "",
            activityLevel: "", primaryGoal: goal, lifestyleConstraints: "", workoutGoalPolicy: policy)
    }

    private func analysis(_ profile: AnalysisProfileSnapshot) -> BodyAnalysisResult {
        BodyAnalysisResult(overallAssessment: "Avoid a deficit while building muscle.",
            trainingAssessment: "", nutritionAssessment: "", recoveryRiskAssessment: "",
            adherenceAssessment: "", analysisLimitations: "",
            inputContext: AnalysisInputContext(profile: profile, checkIn: nil, progress: nil),
            regionBreakdown: [], topLeverageChange: "", priorityMuscles: ["Chest"],
            workoutRecommendations: [], dietRecommendations: [], posturalNotes: "",
            estimatedBodyFat: "", metabolicHealthNotes: "", psychologicalInsights: "",
            injuryRiskNotes: "", macroTargets: nil, structuredTrainingIntent: nil)
    }

    func testCaptureUsesExplicitCategoryNotIncidentalWords() {
        XCTAssertEqual(WorkoutGoalPolicy.capture(primaryGoal: "Muscle gain — avoid a deficit")?.mode, .muscleGain)
        XCTAssertEqual(WorkoutGoalPolicy.capture(primaryGoal: "Fat loss — retain muscle")?.mode, .fatLoss)
        for value in ["Body recomposition", "Strength", "General health and fitness", "", "Avoid fat loss", "Build muscle without cutting"] {
            XCTAssertNil(WorkoutGoalPolicy.capture(primaryGoal: value), value)
        }
        let client = AnalysisClientProfile(age: "", sex: "", build: "", height: "", currentWeight: "",
            occupation: "", trainingFrequency: "", trainingAge: "", equipmentAccess: "",
            averageSleep: "", painHistory: "", activityLevel: "", primaryGoal: "Fat loss",
            lifestyleConstraints: "")
        XCTAssertEqual(client.snapshot.workoutGoalPolicy?.mode, .fatLoss, "Shipping profile capture must attach policy")
    }

    func testSavedPolicyRoundTripLegacyAndUnknownVersion() throws {
        let saved = profile("Fat loss", policy: .init(mode: .fatLoss))
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(try JSONDecoder().decode(AnalysisProfileSnapshot.self, from: data).workoutGoalPolicy, saved.workoutGoalPolicy)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "workoutGoalPolicy")
        let legacy = try JSONDecoder().decode(AnalysisProfileSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.workoutGoalPolicy, "Old saved fat-loss text must not silently activate new policy")
        object["workoutGoalPolicy"] = ["version": "future_v99", "modeID": "fat_loss"]
        let unknown = try JSONDecoder().decode(AnalysisProfileSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(unknown.workoutGoalPolicy?.mode)
        XCTAssertEqual(unknown.workoutGoalPolicy?.setPhaseWeek(3), 3)
        XCTAssertTrue(unknown.workoutGoalPolicy?.auditDescription.contains("unsupported") == true)
        XCTAssertEqual(unknown.workoutGoalPolicy?.nutritionGuidance, "")
        let malformedValues: [Any] = ["bad", 42, ["version": true], ["modeID": "fat_loss"]]
        for malformed in malformedValues {
            object["workoutGoalPolicy"] = malformed
            let decoded = try JSONDecoder().decode(AnalysisProfileSnapshot.self,
                from: JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(decoded.primaryGoal, saved.primaryGoal)
            XCTAssertNil(decoded.workoutGoalPolicy?.mode)
        }
    }

    func testSavedGoalDoesNotRewriteExistingCalibration() throws {
        let gain = service.calibrationProfile(from: analysis(profile("Muscle gain", policy: .init(mode: .muscleGain))),
            recoveryDecision: SleepRecoveryPolicy.decision(from: nil))
        let loss = service.calibrationProfile(from: analysis(profile("Fat loss", policy: .init(mode: .fatLoss))),
            recoveryDecision: SleepRecoveryPolicy.decision(from: nil))
        XCTAssertTrue(gain.recompositionGoal)
        XCTAssertTrue(loss.recompositionGoal)
        XCTAssertEqual(gain.weeklyVolumeScale, loss.weeklyVolumeScale)
        XCTAssertEqual(gain.recoveryTier, loss.recoveryTier)
        let legacy = service.calibrationProfile(from: analysis(profile("Muscle gain", policy: nil)),
            recoveryDecision: SleepRecoveryPolicy.decision(from: nil))
        XCTAssertTrue(legacy.recompositionGoal, "Legacy analysis keyword behavior is intentionally unchanged")
        XCTAssertEqual(gain.weeklyVolumeScale, legacy.weeklyVolumeScale)
        XCTAssertEqual(gain.reduceExerciseSlotComplexity, legacy.reduceExerciseSlotComplexity)
        XCTAssertEqual(gain.goalPolicy?.mode, .muscleGain)
        XCTAssertEqual(loss.goalPolicy?.mode, .fatLoss)
        let source = analysis(profile("Fat loss", policy: .init(mode: .fatLoss)))
        let restored = try JSONDecoder().decode(BodyAnalysisResult.self, from: JSONEncoder().encode(source))
        let restoredIntent = service.trainingIntentPlan(from: restored)
        let blueprint = service.programBlueprint(for: restoredIntent, weekNumber: 2)
        XCTAssertEqual(blueprint.calibration.goalPolicy?.mode, .fatLoss)
        let prompt = service.nextWeekUserPrompt(weekNumber: 2, dayStart: 8, dayEnd: 14,
            previousWeekReference: "", analysisContext: "", exerciseMenuContext: "",
            goalPolicy: blueprint.calibration.goalPolicy)
        XCTAssertTrue(prompt.contains("Muscle retention during a fat-loss goal"))
        XCTAssertFalse(prompt.contains("Volume accumulation"))
    }

    func testSetAllowancesChangeOnlyInLoadingWeeksAndDoNotChangeReps() {
        let gain = WorkoutGoalPolicy(mode: .muscleGain), loss = WorkoutGoalPolicy(mode: .fatLoss)
        for (name, target) in [("Barbell Bench Press", "Chest"), ("Machine Chest Press", "Chest"),
                               ("Cable Lateral Raise", "Lateral Deltoids"), ("Cable Crunch", "Abs")] {
            let base = service.proceduralSets(for: 1, exerciseName: name, muscleTarget: target)
            for week in 1...4 {
                let normal = service.proceduralSets(for: week, exerciseName: name, muscleTarget: target)
                XCTAssertEqual(service.proceduralSets(for: week, exerciseName: name, muscleTarget: target, goalPolicy: gain), normal)
                XCTAssertEqual(service.proceduralSets(for: week, exerciseName: name, muscleTarget: target, goalPolicy: loss),
                    (2...3).contains(week) ? base : normal)
            }
        }
        XCTAssertEqual(service.proceduralSets(for: 2, exerciseName: "Cable Lateral Raise", muscleTarget: "Lateral Deltoids", goalPolicy: gain), 4)
        XCTAssertEqual(service.proceduralSets(for: 2, exerciseName: "Cable Lateral Raise", muscleTarget: "Lateral Deltoids", goalPolicy: loss), 3)
        XCTAssertFalse(service.phaseGuidance(for: 2, goalPolicy: loss).contains("Volume accumulation"))
        XCTAssertEqual(service.phaseGuidance(for: 4, goalPolicy: loss), service.phaseGuidance(for: 4))
    }

    private func intent(_ mode: WorkoutGoalPolicy.Mode) -> ClaudeService.TrainingIntentPlan {
        let base = service.fallbackTrainingIntentPlan(from: ["Chest", "Lateral Deltoids"])
        var calibration = service.neutralCalibrationProfile()
        calibration.goalPolicy = .init(mode: mode)
        return .init(splitRecommendation: "Upper/Lower", weeklyTrainingDays: 5,
            programmingNotes: [calibration.goalPolicy!.coachingGuidance], priorities: base.priorities,
            topLeverageChange: base.topLeverageChange, posturalFocus: base.posturalFocus,
            injuryRiskFocus: base.injuryRiskFocus, calibration: calibration)
    }

    // A deliberately small allocator fixture isolates optional non-priority funding.
    // It is not presented as a complete workout or a six-exercise feasibility test.
    func testAllocatorActuallyUsesGoalForNonPrioritySets() throws {
        let metadata = try XCTUnwrap(service.exerciseMetadataCatalog[service.normalizeExerciseName("Standing Calf Raise")])
        var delivered: [Int] = []
        for mode in [WorkoutGoalPolicy.Mode.muscleGain, .fatLoss] {
            let plan = intent(mode)
            let blueprint = service.programBlueprint(for: plan, weekNumber: 2)
            let day = try XCTUnwrap(blueprint.dayPlans.firstIndex { !$0.isRestDay && ["Lower", "Legs"].contains($0.style) })
            var menus = Array(repeating: [ClaudeService.PreSelectedExercise](), count: 7)
            menus[day] = [.init(exerciseName: metadata.canonicalName, muscleTarget: "Calves",
                movementPattern: metadata.movementPattern,
                role: service.proceduralExerciseRole(for: metadata.canonicalName, muscleTarget: "Calves"), prescribedSets: 1)]
            let funded = service.allocateSetPrescriptionCandidate(menus, blueprint: blueprint,
                weekNumber: 2, reserveMaintenanceMinimum: false, publishConflictLogs: false)
            delivered.append(try XCTUnwrap(funded.menus[day].first).prescribedSets)
        }
        XCTAssertEqual(delivered, [4, 3], "Removing goal propagation from the allocator must fail this test")
    }

    func testMatchedGoalsUseSameStartingTargetsAndLockedMenuInFallback() throws {
        let gain = intent(.muscleGain), loss = intent(.fatLoss)
        XCTAssertEqual(gain.priorities.map(\.weeklyDirectSetTarget), loss.priorities.map(\.weeklyDirectSetTarget))
        for plan in [gain, loss] {
            let blueprint = service.programBlueprint(for: plan, weekNumber: 2)
            let selected = service.preSelectedExercisePlan(for: blueprint, trainingIntent: plan,
                weekNumber: 2, previousWeekDays: nil, exerciseHistory: nil)
            try service.requireSixExerciseMenu(selected.menus, blueprint: selected.blueprint)
            let week = service.buildProceduralWeek(weekNumber: 2, dayStart: 8, dayEnd: 14,
                splitType: "Upper/Lower", programName: "Goal test", trainingIntent: plan,
                blueprint: selected.blueprint, previousWeekDays: nil, exerciseMenus: selected.menus)
            let accounting = service.weeklyExerciseAccounting(for: selected.menus, blueprint: selected.blueprint)
            for day in week.days.indices {
                XCTAssertEqual(week.days[day].exercises.map(\.exerciseName), selected.menus[day].map(\.exerciseName))
                XCTAssertEqual(week.days[day].exercises.map(\.sets), selected.menus[day].map(\.prescribedSets))
                XCTAssertLessThanOrEqual(service.estimatedDayFatigue(for: week.days[day].exercises), selected.blueprint.dayPlans[day].targetFatigueCap)
                for index in selected.menus[day].indices {
                    let item = selected.menus[day][index], cost = accounting.exercises[day][index]
                    let prime = selected.blueprint.priorityAllocations.indices.contains {
                        cost.unitDirect[$0] > 0 && cost.qualityScore[$0] == 30
                    }
                    let ceiling = max(prime ? 4 : 0, service.proceduralSets(for: 2, exerciseName: item.exerciseName,
                        muscleTarget: item.muscleTarget, goalPolicy: plan.calibration.goalPolicy))
                    XCTAssertLessThanOrEqual(item.prescribedSets, ceiling)
                }
                for exercise in week.days[day].exercises {
                    XCTAssertEqual(exercise.reps, service.proceduralRepRange(for: 2,
                        exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget))
                }
            }
            let issues = service.validateWeekResponse(week, dayStart: 8, dayEnd: 14, previousWeekDays: nil,
                blueprint: selected.blueprint, expectedExerciseMenus: selected.menus)
            XCTAssertFalse(issues.contains { $0.contains("did not follow the Pre-Selected") }, issues.joined(separator: " | "))
            if plan.calibration.goalPolicy?.mode == .fatLoss {
                let implicitMenu = try service.validatedProceduralWeek(weekNumber: 2, dayStart: 8, dayEnd: 14,
                    splitType: "Upper/Lower", programName: "Goal test", trainingIntent: plan,
                    blueprint: blueprint, previousWeekDays: nil)
                XCTAssertEqual(implicitMenu.days.map { $0.exercises.map(\.exerciseName) }, week.days.map { $0.exercises.map(\.exerciseName) })
                XCTAssertEqual(implicitMenu.days.map { $0.exercises.map(\.sets) }, week.days.map { $0.exercises.map(\.sets) })
            }
            print("GOAL REPLAY \(plan.calibration.goalPolicy!.auditDescription): sets=\(week.days.map { $0.exercises.reduce(0) { $0 + $1.sets } }); validator=\(issues)")
        }
    }
}
