import Foundation
import XCTest
@testable import Transform

@MainActor
final class CrossDayTricepsTests: XCTestCase {
    private let service = ClaudeService.shared
    private var intent: ClaudeService.TrainingIntentPlan {
        .init(splitRecommendation: "Push / Lower / Upper / Pull / Arms", weeklyTrainingDays: 5,
            programmingNotes: [], priorities: [], topLeverageChange: "", posturalFocus: "",
            injuryRiskFocus: "", calibration: service.neutralCalibrationProfile())
    }

    // Complete guard-isolation calendar: exercise doses transcribed from the public synthetic
    // small-muscle W2 journey. Admission/locks are synthetic, not a private-history replay.
    private func fixture(week: Int = 2, risk: String = "", priority: String? = nil,
        history: ClaudeService.ExerciseHistoryContext? = nil,
        mutate: ((inout [[ClaudeService.PreSelectedExercise]], inout [Int], inout [Set<String>]) -> Void)? = nil
    ) -> ClaudeService.SubstitutionPlanningBaseline {
        func item(_ n: String, _ t: String, _ s: Int) -> ClaudeService.PreSelectedExercise {
            .init(exerciseName: n, muscleTarget: t,
                movementPattern: service.exerciseMetadata(forExerciseName: n, muscleTarget: t).movementPattern,
                role: service.proceduralExerciseRole(for: n, muscleTarget: t), prescribedSets: s)
        }
        var menus = [
            [item("Machine Chest Press", "Chest", 2), item("Machine Incline Press", "Upper Chest", 2),
             item("Dumbbell Bench Press", "Chest", 2), item("Dip (Assisted or Weighted)", "Triceps", 2),
             item("Cable Lateral Raise", "Lateral Deltoids", 3), item("Leaning Dumbbell Lateral Raise", "Lateral Deltoids", 3)],
            [item("Leg Press", "Quads", 4), item("Standing Calf Raise", "Calves", 4), item("Seated Calf Raise", "Calves", 3),
             item("Machine Leg Curl", "Hamstrings", 4), item("Cable Pull-Through", "Glutes", 4), item("Cable Crunch", "Abs", 3)],
            [],
            [item("Machine Shoulder Press", "Deltoids", 3), item("Behind-the-Back Cable Lateral Raise", "Lateral Deltoids", 3),
             item("Machine Lateral Raise", "Lateral Deltoids", 3), item("Reverse Pec Deck", "Rear Deltoids", 3),
             item("Dumbbell Rear Delt Fly", "Rear Deltoids", 2), item("Cable Triceps Pressdown", "Triceps", 2),
             item("Hanging Knee Raise", "Lower Abs", 3)],
            [item("Pull-Up (Weighted or Assisted)", "Lats", 3), item("Lat Pulldown", "Lats", 3),
             item("Chest-Supported Row", "Upper Back", 2), item("Seated Cable Row", "Mid Back", 2),
             item("Cable Face Pull", "Rear Deltoids", 2), item("EZ-Bar Curl", "Biceps", 4)],
            [item("Rope Triceps Pressdown", "Triceps", 2), item("Dip (Assisted or Weighted)", "Triceps", 2),
             item("Incline Dumbbell Curl", "Biceps", 3), item("Overhead Cable Triceps Extension", "Triceps", 2),
             item("Dumbbell Hammer Curl", "Brachialis", 3)], []
        ]
        var locks = [6, 6, 0, 5, 6, 5, 0]
        var retained = Array(repeating: Set<String>(), count: 7)
        retained[5].insert(ExerciseWeightEntry.canonicalLookupKey("Rope Triceps Pressdown"))
        mutate?(&menus, &locks, &retained)
        let areas = ["Lateral Deltoids", "Calves"] + (priority.map { [$0] } ?? [])
        let allocations: [ClaudeService.BlueprintPriorityAllocation] = areas.map { area in
            .init(area: area, priorityLevel: "Medium", rationale: "", targetFrequency: 1,
                targetExerciseSlots: 1, directSetTarget: area == "Lateral Deltoids" ? 12 : 10,
                weightedStimulusTarget: 12, maxPerSessionDirectSets: 12, maxFocusSessionDirectSets: 12,
                preferredStyles: [], preferredMovementPatterns: [], volumeBias: "Moderate", directWorkBias: "High")
        }
        let styles = ["Push", "Lower", "Rest", "Upper", "Pull", "Arms", "Rest"]
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "cross-day-guard-fixture",
            splitRecommendation: "Push / Lower / Upper / Pull / Arms", weeklyTrainingDays: 5,
            priorityAllocations: allocations, dayPlans: menus.indices.map { day in
                .init(dayIndex: day + 1, style: styles[day], focusArea: nil, supportAreas: [],
                    targetFatigueCap: 60, targetSessionMinutes: 75, targetPrioritySlots: 0,
                    emphasisPatterns: [], isRestDay: menus[day].isEmpty)
            }, topLeverageChange: "", posturalFocus: "", injuryRiskFocus: risk, programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        return .init(menus: menus, blueprint: blueprint, weekNumber: week, lockedPrefixCounts: locks,
            retainedKeysByDay: retained, exerciseHistory: history,
            selectionFocusIntents: Array(repeating: nil, count: 7), roleFloorAdmission: .admitted)
    }

    private func previous(week: Int = 2) -> [WorkoutDayResponse] {
        // No prior pressing; malformed and boundary-exposure controls are tested separately.
        (0..<7).map { .init(dayNumber: (week - 2) * 7 + $0 + 1, dayName: "Rest", muscleGroups: "",
            isRestDay: true, notes: "", exercises: []) }
    }
    private func trial(_ base: ClaudeService.SubstitutionPlanningBaseline, previous days: [WorkoutDayResponse]? = nil)
        -> ClaudeService.CrossDayTricepsTrial {
        service.proposeCrossDayTricepsConsolidation(base, source: 3, donor: 5, receiver: 5,
            trainingIntent: intent, previousWeekDays: days ?? previous(week: base.weekNumber))
    }
    private func reason(_ trial: ClaudeService.CrossDayTricepsTrial) -> String? {
        if case .refused(let reason) = trial { return reason }; return nil
    }

    func testExactTransferKeepsRetainedPrefixReceiverIdentityAndOrder() throws {
        for week in [2, 3] {
            let base = fixture(week: week)
            guard case .candidate(let result) = trial(base) else { return XCTFail("Expected bounded candidate") }
            XCTAssertEqual(result.menus.map(\.count), [6, 6, 0, 6, 6, 5, 0])
            XCTAssertEqual(result.menus[5].map(\.exerciseName), base.menus[5].map(\.exerciseName))
            XCTAssertEqual(result.menus[5].map(\.prescribedSets), [3, 2, 3, 3, 3])
            XCTAssertEqual(result.lockedPrefixCounts, base.lockedPrefixCounts)
            XCTAssertEqual(result.retainedKeysByDay, base.retainedKeysByDay)
            for day in [0, 1, 2, 4, 6] {
                XCTAssertEqual(result.menus[day].map(\.prescribedSets), base.menus[day].map(\.prescribedSets))
                XCTAssertEqual(result.menus[day].map(\.exerciseName), base.menus[day].map(\.exerciseName))
            }
            XCTAssertEqual(result.menus[3].map(\.exerciseName), base.menus[3].enumerated().filter { $0.offset != 5 }.map { $0.element.exerciseName })
        }
    }

    func testAlreadySixSlotUpperDayStillConsolidatesTricepsIntoArms() throws {
        let base = fixture { menus, _, _ in menus[3].removeLast() }
        XCTAssertEqual(base.menus[3].count, 6)
        guard case .candidate(let proposed) = trial(base) else {
            return XCTFail("The six-slot source must use the same bounded transfer")
        }
        XCTAssertEqual(proposed.menus[3].count, 5)
        XCTAssertEqual(proposed.menus[5].map(\.prescribedSets), [3, 2, 3, 3, 3])
        let final = service.finalizeSessionCapacity(base, trainingIntent: intent,
            baselineMessages: [], baselineReceipts: [], collectFunding: false,
            previousWeekDays: previous())
        XCTAssertTrue(final.decision.hasPrefix("adopted"), final.decision)
        XCTAssertEqual(final.plan.menus.map(\.count), [6, 6, 0, 5, 6, 5, 0])
    }

    func testProtectedAndRetainedDonorsRefuse() {
        XCTAssertEqual(reason(trial(fixture { _, locks, _ in locks[3] = 6 })), "protected or unsupported triceps donor")
        XCTAssertEqual(reason(trial(fixture { _, _, retained in
            retained[3].insert(ExerciseWeightEntry.canonicalLookupKey("Cable Triceps Pressdown"))
        })), "protected or unsupported triceps donor")
    }

    func testReceiverHistoryAndSymptomsRefuse() {
        let key = ExerciseWeightEntry.canonicalLookupKey("Rope Triceps Pressdown")
        for history in [ClaudeService.ExerciseHistoryContext(painExercises: [key], equipmentSkipExercises: [], priorMesocycleExercises: [], mesocycleIndex: 0),
                        .init(painExercises: [], equipmentSkipExercises: [key], priorMesocycleExercises: [], mesocycleIndex: 0)] {
            XCTAssertEqual(reason(trial(fixture(history: history))), "history or symptoms exclude triceps consolidation")
        }
        XCTAssertEqual(reason(trial(fixture(risk: "Elbow pain during triceps extensions"))), "history or symptoms exclude triceps consolidation")
    }

    func testPriorityInvolvementRefuses() {
        XCTAssertEqual(reason(trial(fixture(priority: "Triceps"))), "priority-involved triceps work is protected")
        // Arms aliases include Triceps; this also prevents broad priorities being bypassed.
        XCTAssertEqual(reason(trial(fixture(priority: "Arms"))), "priority-involved triceps work is protected")
    }

    func testMalformedPreviousCalendarRefuses() {
        XCTAssertEqual(reason(trial(fixture(), previous: [])), "invalid previous week")
        XCTAssertEqual(reason(trial(fixture(), previous: previous(week: 3))), "invalid previous week")
        var days = previous()
        days[6] = .init(dayNumber: 7, dayName: "Press", muscleGroups: "Chest", isRestDay: false, notes: "",
            exercises: [.init(exerciseName: "Machine Chest Press", sets: 2, reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: "Chest")])
        XCTAssertEqual(reason(trial(fixture(), previous: days)), "prior-week pressing interval refused")
    }

    func testAdjacentPressingOverlapRefuses() {
        let base = fixture { menus, _, _ in
            let old = menus[4][5]
            menus[4][5] = .init(exerciseName: "Machine Chest Press", muscleTarget: "Chest",
                movementPattern: "Horizontal Press", role: .secondary, prescribedSets: old.prescribedSets)
        }
        XCTAssertEqual(reason(trial(base)), "pressing overlap or cyclic spacing refused")
    }

    func testReceiverConcentrationAboveEightRefuses() {
        XCTAssertEqual(reason(trial(fixture { menus, _, _ in menus[5][1].prescribedSets = 3 })),
            "outside two-day eight-set triceps concentration boundary")
    }

    func testDeloadAndWrongReceiverDoseRefuse() {
        XCTAssertEqual(reason(trial(fixture(week: 4))), "outside bounded cross-day triceps context")
        XCTAssertEqual(reason(trial(fixture { menus, _, _ in menus[5][0].prescribedSets = 3 })),
            "requires two existing complementary two-set receivers")
    }

    func testRefusedFinalizerKeepsReportsAndDeliveryRejectsTampering() {
        let rejected = fixture(week: 4)
        let receipt = SetFundingObservation(dayIndex: 5, exerciseIndex: 0,
            exerciseName: "Rope Triceps Pressdown", muscleTarget: "Triceps", prescribedSets: 2, rejection: nil)
        let final = service.finalizeFirstCrossDayTricepsConsolidation(rejected, trainingIntent: intent,
            previousWeekDays: previous(week: 4), baselineMessages: ["sentinel"],
            baselineReceipts: [receipt], collectFunding: true)
        XCTAssertEqual(final.messages, ["sentinel"])
        XCTAssertEqual(final.receipts, [receipt])
        XCTAssertEqual(final.plan.menus[5].map(\.prescribedSets), rejected.menus[5].map(\.prescribedSets))

        let base = fixture()
        guard case .candidate(let proposed) = trial(base) else { return XCTFail("Expected proposal") }
        func output(_ plan: ClaudeService.SubstitutionPlanningBaseline, tamper: Bool = false,
            tamperRIR: Bool = false) -> WorkoutWeekResponse {
            .init(weekSummary: "", days: plan.menus.indices.map { day in
                .init(dayNumber: 8 + day, dayName: "Test", muscleGroups: "", isRestDay: plan.menus[day].isEmpty,
                    notes: "", exercises: plan.menus[day].enumerated().map { index, item in
                        .init(exerciseName: item.exerciseName,
                            sets: item.prescribedSets + (tamper && day == 5 && index == 0 ? 1 : 0),
                            reps: "8-12", tempo: "2-0-1-0", restSeconds: 90, notes: "", muscleTarget: item.muscleTarget,
                            targetRIR: tamperRIR && day == 5 && index == 0 ? 0 : nil)
                    })
            })
        }
        XCTAssertEqual(service.verifyCrossDayTricepsDelivery(original: output(base), candidate: output(proposed, tamper: true),
            baseline: base, proposed: proposed, previousWeekDays: previous()), "triceps delivery mismatch")
        XCTAssertEqual(service.verifyCrossDayTricepsDelivery(original: output(base), candidate: output(proposed, tamperRIR: true),
            baseline: base, proposed: proposed, previousWeekDays: previous()), "triceps delivery changed execution prescription")
        var altered = proposed.menus
        altered[5][0].prescribedSets += 1
        XCTAssertNotNil(service.verifyAccessoryRelocationAllocation(altered, admission: .admitted, proposed: proposed))
    }
}
