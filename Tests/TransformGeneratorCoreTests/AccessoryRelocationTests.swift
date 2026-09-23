import Foundation
import XCTest
@testable import Transform

@MainActor
final class AccessoryRelocationTests: XCTestCase {
    private let service = ClaudeService.shared

    private var intent: ClaudeService.TrainingIntentPlan {
        .init(splitRecommendation: "Upper / Lower", weeklyTrainingDays: 4, programmingNotes: [],
            priorities: [], topLeverageChange: "", posturalFocus: "", injuryRiskFocus: "",
            calibration: service.neutralCalibrationProfile())
    }

    // Guard isolation from a complete synthetic calendar. This is not a replay
    // of private history; the sequential journey tests prove live integration.
    private func fixture(week: Int = 1, risk: String = "",
        history: ClaudeService.ExerciseHistoryContext? = nil,
        retained: Bool = false, locked: Int = 0) -> ClaudeService.SubstitutionPlanningBaseline {
        func item(_ name: String, _ target: String, _ sets: Int) -> ClaudeService.PreSelectedExercise {
            .init(exerciseName: name, muscleTarget: target,
                movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
                role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: sets)
        }
        let menus = [
            [item("Incline Dumbbell Press", "Upper Chest", 3), item("Machine Chest Press", "Chest", 2),
             item("Cable Lateral Raise", "Lateral Deltoids", 3), item("Leaning Dumbbell Lateral Raise", "Lateral Deltoids", 3),
             item("Rope Triceps Pressdown", "Triceps", 3)],
            [item("Leg Press", "Quads", 2), item("Dumbbell Walking Lunge", "Quads/Glutes", 3),
             item("Machine Leg Extension", "Quads", 2), item("Machine Leg Curl", "Hamstrings", 3),
             item("Standing Calf Raise", "Calves", 3), item("Cable Crunch", "Abs", 3)],
            [],
            [item("Incline Barbell Press", "Upper Chest", 3), item("Chest-Supported Row", "Upper Back", 3),
             item("Cable Fly", "Chest", 2), item("Reverse Pec Deck", "Rear Deltoids", 2),
             item("Dumbbell Rear Delt Fly", "Rear Deltoids", 2), item("Cable Triceps Pressdown", "Triceps", 3),
             item("Hanging Knee Raise", "Lower Abs", 3)],
            [],
            [item("Pull-Up (Weighted or Assisted)", "Lats", 3), item("Lat Pulldown", "Lats", 2),
             item("Seated Cable Row", "Mid Back", 2), item("EZ-Bar Curl", "Biceps", 3),
             item("Incline Dumbbell Curl", "Biceps", 3)],
            []
        ]
        let styles = ["Push", "Lower", "Rest", "Upper", "Rest", "Pull", "Rest"]
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "accessory-guard-fixture",
            splitRecommendation: "Upper / Lower", weeklyTrainingDays: 4, priorityAllocations: [],
            dayPlans: menus.indices.map { day in
                .init(dayIndex: day + 1, style: styles[day], focusArea: nil, supportAreas: [],
                    targetFatigueCap: 48, targetSessionMinutes: 70, targetPrioritySlots: 0,
                    emphasisPatterns: [], isRestDay: menus[day].isEmpty)
            }, topLeverageChange: "", posturalFocus: "", injuryRiskFocus: risk, programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        var locks = Array(repeating: 0, count: 7)
        locks[3] = locked
        var retainedKeys = Array(repeating: Set<String>(), count: 7)
        if retained { retainedKeys[3].insert(ExerciseWeightEntry.canonicalLookupKey("Reverse Pec Deck")) }
        return .init(menus: menus, blueprint: blueprint, weekNumber: week, lockedPrefixCounts: locks,
            retainedKeysByDay: retainedKeys, exerciseHistory: history, selectionFocusIntents: Array(repeating: nil, count: 7),
            roleFloorAdmission: .admitted)
    }

    private func trial(_ plan: ClaudeService.SubstitutionPlanningBaseline, slot: Int = 3,
        previous: [WorkoutDayResponse]? = nil) -> ClaudeService.AccessoryRelocationTrial {
        service.proposeAccessoryRelocation(plan, source: 3, slot: slot, receiver: 5,
            trainingIntent: intent, previousWeekDays: previous)
    }

    private func candidate(_ trial: ClaudeService.AccessoryRelocationTrial,
        file: StaticString = #filePath, line: UInt = #line) throws -> ClaudeService.SubstitutionPlanningBaseline {
        guard case .candidate(let plan) = trial else {
            XCTFail("Expected eligible trial, got \(trial)", file: file, line: line)
            throw NSError(domain: "AccessoryRelocationTests", code: 1)
        }
        return plan
    }

    private func refusal(_ result: ClaudeService.AccessoryRelocationTrial) -> String? {
        if case .refused(let reason) = result { return reason }
        return nil
    }

    private func output(_ plan: ClaudeService.SubstitutionPlanningBaseline) -> WorkoutWeekResponse {
        let start = (plan.weekNumber - 1) * 7 + 1
        return service.buildProceduralWeek(weekNumber: plan.weekNumber, dayStart: start, dayEnd: start + 6,
            splitType: "Upper / Lower", programName: "Test", trainingIntent: intent,
            blueprint: plan.blueprint, previousWeekDays: nil, exerciseMenus: plan.menus)
    }

    private func changedDay(_ day: WorkoutDayResponse, number: Int? = nil, rest: Bool? = nil,
        firstSets: Int? = nil, firstTarget: String? = nil) -> WorkoutDayResponse {
        var exercises = day.exercises
        if let old = exercises.first, firstSets != nil || firstTarget != nil {
            exercises[0] = .init(exerciseName: old.exerciseName, sets: firstSets ?? old.sets,
                reps: old.reps, tempo: old.tempo, restSeconds: old.restSeconds, notes: old.notes,
                muscleTarget: firstTarget ?? old.muscleTarget, targetRIR: old.targetRIR, coachingSource: old.coachingSource)
        }
        return .init(dayNumber: number ?? day.dayNumber, dayName: day.dayName, muscleGroups: day.muscleGroups,
            isRestDay: rest ?? day.isRestDay, notes: day.notes, exercises: exercises)
    }

    private func changedOutput(_ value: WorkoutWeekResponse, day: Int, rest: Bool? = nil,
        firstSets: Int? = nil, firstTarget: String? = nil) -> WorkoutWeekResponse {
        var days = value.days
        days[day] = changedDay(days[day], rest: rest, firstSets: firstSets, firstTarget: firstTarget)
        return .init(weekSummary: value.weekSummary, days: days)
    }

    func testSameExerciseAndDoseMoveWithoutChangingOtherSlots() throws {
        let base = fixture(), moved = try candidate(trial(fixture()))
        XCTAssertEqual(moved.menus.map(\.count), [5, 6, 0, 6, 0, 6, 0])
        XCTAssertEqual(moved.roleFloorAdmission, .unassessed)
        XCTAssertEqual(moved.menus[5].last?.exerciseName, "Reverse Pec Deck")
        XCTAssertEqual(moved.menus[5].last?.prescribedSets, 2)
        XCTAssertEqual(moved.blueprint, base.blueprint)
        XCTAssertEqual(moved.menus[3].map(\.exerciseName), base.menus[3].filter { $0.exerciseName != "Reverse Pec Deck" }.map(\.exerciseName))
        XCTAssertEqual(refusal(trial(base, slot: 4)), "absent from receiver catalog")
        XCTAssertNil(service.verifyAccessoryRelocationDelivery(original: output(base), candidate: output(moved),
            baseline: base, proposed: moved, previousWeekDays: nil))
    }

    func testProtectionSymptomsHistoryAndUnsupportedWeeksRefuse() {
        XCTAssertEqual(refusal(trial(fixture(retained: true))), "protected source")
        XCTAssertEqual(refusal(trial(fixture(locked: 4))), "protected source")
        XCTAssertEqual(refusal(trial(fixture(risk: "Shoulder pain during rear delt fly"))),
            "history or reported symptoms exclude relocation")
        let key = ExerciseWeightEntry.canonicalLookupKey("Reverse Pec Deck")
        for history in [ClaudeService.ExerciseHistoryContext(painExercises: [key], equipmentSkipExercises: [],
                            priorMesocycleExercises: [], mesocycleIndex: 0),
                        .init(painExercises: [], equipmentSkipExercises: [key], priorMesocycleExercises: [], mesocycleIndex: 0)] {
            XCTAssertEqual(refusal(trial(fixture(history: history))), "history or reported symptoms exclude relocation")
        }
        XCTAssertNotNil(refusal(trial(fixture(week: 4))))
        XCTAssertEqual(refusal(trial(fixture(week: 2))), "invalid previous week")
        XCTAssertEqual(refusal(trial(fixture(), previous: output(fixture()).days)), "invalid previous week")
    }

    func testAllocationAndDeliveryCannotHideChangedSetsTargetsOrRestDays() throws {
        let base = fixture(), moved = try candidate(trial(base))
        XCTAssertNil(service.verifyAccessoryRelocationAllocation(moved.menus, admission: .admitted, proposed: moved))
        XCTAssertNotNil(service.verifyAccessoryRelocationAllocation(moved.menus, admission: .unassessed, proposed: moved))
        var changed = moved.menus
        changed[5][0].prescribedSets += 1
        XCTAssertNotNil(service.verifyAccessoryRelocationAllocation(changed, admission: .admitted, proposed: moved))
        var wrong = changedOutput(output(moved), day: 5, firstSets: 4)
        XCTAssertEqual(service.verifyAccessoryRelocationDelivery(original: output(base), candidate: wrong,
            baseline: base, proposed: moved, previousWeekDays: nil), "delivery mismatch")
        wrong = changedOutput(output(moved), day: 5, firstTarget: "Rear Deltoids")
        XCTAssertEqual(service.verifyAccessoryRelocationDelivery(original: output(base), candidate: wrong,
            baseline: base, proposed: moved, previousWeekDays: nil), "delivery mismatch")
        wrong = changedOutput(output(moved), day: 5, rest: true)
        XCTAssertEqual(service.verifyAccessoryRelocationDelivery(original: output(base), candidate: wrong,
            baseline: base, proposed: moved, previousWeekDays: nil), "delivery mismatch")
        var days = output(moved).days
        var exercises = days[5].exercises
        let old = exercises[0]
        exercises[0] = .init(exerciseName: old.exerciseName, sets: old.sets, reps: old.reps,
            tempo: old.tempo, restSeconds: old.restSeconds, notes: old.notes, muscleTarget: old.muscleTarget,
            targetRIR: 0, coachingSource: old.coachingSource)
        let day = days[5]
        days[5] = .init(dayNumber: day.dayNumber, dayName: day.dayName, muscleGroups: day.muscleGroups,
            isRestDay: day.isRestDay, notes: day.notes, exercises: exercises)
        XCTAssertEqual(service.verifyAccessoryRelocationDelivery(original: output(base),
            candidate: .init(weekSummary: "Test", days: days), baseline: base, proposed: moved,
            previousWeekDays: nil), "delivery changed execution prescription")
    }

    func testPreviousWeekCalendarAndUnsupportedContextCannotBeAssumed() throws {
        let prior = output(fixture()).days
        _ = try candidate(trial(fixture(week: 2), previous: prior))
        var wrong = prior
        wrong[0] = changedDay(wrong[0], number: 8)
        XCTAssertEqual(refusal(trial(fixture(week: 2), previous: wrong)), "invalid previous week")
        wrong = prior
        wrong[0] = changedDay(wrong[0], rest: true)
        XCTAssertEqual(refusal(trial(fixture(week: 2), previous: wrong)), "invalid previous week")
        wrong = prior
        wrong[0] = changedDay(wrong[0], firstSets: 0)
        XCTAssertEqual(refusal(trial(fixture(week: 2), previous: wrong)), "invalid previous week")
    }

    private func recalendar(_ base: ClaudeService.SubstitutionPlanningBaseline, _ order: [Int],
        priorities: [ClaudeService.BlueprintPriorityAllocation]? = nil) -> ClaudeService.SubstitutionPlanningBaseline {
        let old = base.blueprint
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: old.evidenceVersion,
            splitRecommendation: old.splitRecommendation, weeklyTrainingDays: old.weeklyTrainingDays,
            priorityAllocations: priorities ?? old.priorityAllocations, dayPlans: order.indices.map { index in
                let day = old.dayPlans[order[index]]
                return .init(dayIndex: index + 1, style: day.style, focusArea: day.focusArea,
                    supportAreas: day.supportAreas, targetFatigueCap: day.targetFatigueCap,
                    targetSessionMinutes: day.targetSessionMinutes, targetPrioritySlots: day.targetPrioritySlots,
                    emphasisPatterns: day.emphasisPatterns, isRestDay: day.isRestDay)
            }, topLeverageChange: old.topLeverageChange, posturalFocus: old.posturalFocus,
            injuryRiskFocus: old.injuryRiskFocus, programmingNotes: old.programmingNotes, calibration: old.calibration)
        return .init(menus: order.map { base.menus[$0] }, blueprint: blueprint, weekNumber: base.weekNumber,
            lockedPrefixCounts: order.map { base.lockedPrefixCounts[$0] },
            retainedKeysByDay: order.map { base.retainedKeysByDay[$0] }, exerciseHistory: base.exerciseHistory,
            selectionFocusIntents: order.map { base.selectionFocusIntents[$0] }, roleFloorAdmission: base.roleFloorAdmission)
    }

    func testAdjacentCyclicAndPriorBoundaryPlacementsRefuse() throws {
        _ = try candidate(trial(fixture()))
        let adjacent = recalendar(fixture(), [0, 1, 2, 3, 5, 4, 6])
        XCTAssertEqual(refusal(service.proposeAccessoryRelocation(adjacent, source: 3, slot: 3, receiver: 4,
            trainingIntent: intent, previousWeekDays: nil)), "outside bounded one-to-two regional frequency trial")
        let cyclic = recalendar(fixture(), [3, 1, 2, 0, 4, 6, 5])
        XCTAssertEqual(refusal(service.proposeAccessoryRelocation(cyclic, source: 0, slot: 3, receiver: 6,
            trainingIntent: intent, previousWeekDays: nil)), "outside bounded one-to-two regional frequency trial")
        let earlier = recalendar(fixture(week: 2), [5, 1, 2, 3, 4, 0, 6])
        XCTAssertEqual(refusal(service.proposeAccessoryRelocation(earlier, source: 3, slot: 3, receiver: 0,
            trainingIntent: intent, previousWeekDays: output(fixture()).days)), "earlier exposure across prior-week boundary")
    }

    func testBothDirectAndWeightedPriorityWorkRemainProtected() {
        for area in ["Rear Deltoids", "Upper Back"] {
            let priority = ClaudeService.BlueprintPriorityAllocation(area: area, priorityLevel: "High", rationale: "Test",
                targetFrequency: 2, targetExerciseSlots: 2, directSetTarget: 4, weightedStimulusTarget: 4,
                maxPerSessionDirectSets: 4, maxFocusSessionDirectSets: 4, preferredStyles: ["Upper", "Pull"],
                preferredMovementPatterns: [], volumeBias: "High", directWorkBias: "Direct emphasis")
            let protected = recalendar(fixture(), Array(0..<7), priorities: [priority])
            XCTAssertEqual(refusal(trial(protected)), "priority work is not movable", area)
        }
    }

    func testRefusalKeepsBaselineMessagesAndFunding() {
        let base = fixture(retained: true)
        let marker = SetFundingObservation(dayIndex: 0, exerciseIndex: 0, exerciseName: "marker",
            muscleTarget: "marker", prescribedSets: 2, rejection: nil)
        let result = service.finalizeFirstAccessoryRelocation(base, trainingIntent: intent, previousWeekDays: nil,
            baselineMessages: ["marker"], baselineReceipts: [marker], collectFunding: true)
        XCTAssertFalse(result.decision.hasPrefix("adopted"))
        XCTAssertEqual(result.plan.menus.map { $0.map(\.exerciseName) }, base.menus.map { $0.map(\.exerciseName) })
        XCTAssertEqual(result.plan.menus.map { $0.map(\.prescribedSets) }, base.menus.map { $0.map(\.prescribedSets) })
        XCTAssertEqual(result.messages, ["marker"])
        XCTAssertEqual(result.receipts, [marker])
    }
}
