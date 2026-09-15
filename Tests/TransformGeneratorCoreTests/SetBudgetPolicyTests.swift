import XCTest
@testable import Transform

@MainActor
final class SetBudgetPolicyTests: XCTestCase {
    private let service = ClaudeService.shared

    private func plan(target: Double? = nil, ordinary: Double = 10, focused: Double = 10,
                      focus: String? = nil, fatigue: Int = 48,
                      recovery: Bool = false, poorNutrition: Bool = false,
                      dayCount: Int = 1, priorityArea: String = "Core/Abs") -> ClaudeService.ProgramBlueprint {
        let neutral = service.neutralCalibrationProfile()
        let calibration = ClaudeService.ProgramCalibrationProfile(
            lowPerformanceDataQuality: neutral.lowPerformanceDataQuality,
            poorNutritionAdherence: poorNutrition, recoveryConstrained: recovery,
            recoveryTier: neutral.recoveryTier, recoveryAudit: neutral.recoveryAudit,
            recompositionGoal: neutral.recompositionGoal, weeklyVolumeScale: neutral.weeklyVolumeScale,
            reduceExerciseSlotComplexity: neutral.reduceExerciseSlotComplexity,
            defaultSessionTimeCapMinutes: neutral.defaultSessionTimeCapMinutes,
            sessionTimeCapsByStyle: neutral.sessionTimeCapsByStyle, programmingNotes: neutral.programmingNotes)
        let allocations: [ClaudeService.BlueprintPriorityAllocation] = target.map { value in
            [.init(area: priorityArea, priorityLevel: "Medium", rationale: "", targetFrequency: 1,
                targetExerciseSlots: 1, directSetTarget: value, weightedStimulusTarget: value,
                maxPerSessionDirectSets: ordinary, maxFocusSessionDirectSets: focused,
                preferredStyles: ["Upper"], preferredMovementPatterns: [], volumeBias: "Moderate", directWorkBias: "High")]
        } ?? []
        return .init(evidenceVersion: "test", splitRecommendation: "Upper", weeklyTrainingDays: dayCount,
            priorityAllocations: allocations, dayPlans: (1...dayCount).map { day in
                .init(dayIndex: day, style: "Upper", focusArea: focus, supportAreas: [],
                    targetFatigueCap: fatigue, targetSessionMinutes: 1, targetPrioritySlots: 1,
                    emphasisPatterns: [], isRestDay: false)
            }, topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: "(none)",
            programmingNotes: [], calibration: calibration)
    }

    private func slot(_ name: String, _ target: String) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
            movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
            role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: 1)
    }

    // Deliberately small allocator-only menus: these do not claim valid whole programs.
    // Their insufficient candidate pools exercise the retained legacy allocation path.
    private func run(_ exercises: [ClaudeService.PreSelectedExercise], _ blueprint: ClaudeService.ProgramBlueprint)
        -> (menu: [ClaudeService.PreSelectedExercise], observations: [SetFundingObservation]) {
        var observations: [SetFundingObservation] = []
        var callbackCount = 0
        let result = service.allocateWeeklySetPrescription([exercises], blueprint: blueprint, weekNumber: 1,
            setFundingReport: { observations = $0; callbackCount += 1 })
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(observations.count, exercises.count)
        return (result[0], observations)
    }

    func testSharedLimitsPreserveRecoveryNutritionAndBothWeeklyModes() {
        for (recovery, nutrition) in [(false, false), (true, false), (false, true), (true, true)] {
            let limits = service.setBudgetLimits(for: plan(target: 8, recovery: recovery, poorNutrition: nutrition))
            XCTAssertEqual(limits.maintenance, recovery || nutrition ? 8 : 10)
            XCTAssertEqual(WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight: recovery || nutrition), recovery || nutrition ? 2 : 3)
            XCTAssertEqual(limits.maintenanceFundingCeiling, recovery || nutrition ? 8.01 : 10.01, accuracy: 0.000001)
            XCTAssertEqual(limits.normalWeeklyPriority[0], 8.01, accuracy: 0.000001)
            XCTAssertEqual(limits.floorWeeklyPriority[0], recovery || nutrition ? 9.18 : 10.88, accuracy: 0.000001)
        }
        XCTAssertEqual(WorkoutSetBudgetPolicy.normalWeeklyPriorityCeiling(target: 7.5),
            7.51, accuracy: 0.000001)
    }

    func testSolverAndFundingTolerancesRemainDistinct() {
        let limits = service.setBudgetLimits(for: plan(target: 10, ordinary: 2.995))
        XCTAssertEqual(limits.sessionPriority[0][0], 2.995)
        XCTAssertLessThanOrEqual(3, limits.sessionFundingCeiling(day: 0, allocation: 0))
        let problem = WorkoutAppearancePlanner.Problem(protected: [true],
            upperBounds: [.init(name: "session", coefficients: [3], limit: limits.sessionPriority[0][0])],
            lowerBounds: [], removalOrder: [0])
        XCTAssertEqual(WorkoutAppearancePlanner.solve(problem), .infeasible(["session"]))
        let funded = run([slot("Cable Crunch", "Abs")], plan(target: 10, ordinary: 2.995))
        XCTAssertEqual(funded.menu[0].prescribedSets, 3, "Incremental gate accepts 3 under its separate tolerance")
        XCTAssertEqual(funded.observations[0].rejection?.kind, .sessionPriority)
    }

    func testActualGateReportsWeeklyTargetAndKeepsFloorAllowance() throws {
        let normal = run([slot("Cable Crunch", "Abs")], plan(target: 2.5))
        XCTAssertEqual(normal.menu[0].prescribedSets, 2)
        let refusal = try XCTUnwrap(normal.observations[0].rejection)
        XCTAssertEqual(refusal.kind, .weeklyPriority)
        XCTAssertEqual(refusal.subject, "Core/Abs")
        XCTAssertEqual(try XCTUnwrap(refusal.projected), 3)
        XCTAssertEqual(try XCTUnwrap(refusal.limit), 2.51, accuracy: 0.000001)

        let floorRepair = run([slot("Cable Crunch", "Abs")], plan(target: 1.5))
        XCTAssertEqual(floorRepair.menu[0].prescribedSets, 2, "Existing floor allowance can fund the second set above 1.51")
        XCTAssertGreaterThan(Double(floorRepair.menu[0].prescribedSets),
            service.setBudgetLimits(for: plan(target: 1.5)).normalWeeklyPriority[0])
    }

    func testActualGateUsesNormalizedFocusCapAndReportsRoleFirst() {
        let ordinary = run([slot("Cable Crunch", "Abs")], plan(target: 10, ordinary: 2, focused: 4))
        XCTAssertEqual(ordinary.menu[0].prescribedSets, 2)
        XCTAssertEqual(ordinary.observations[0].rejection?.kind, .sessionPriority)
        let focused = run([slot("Cable Crunch", "Abs")],
            plan(target: 10, ordinary: 2, focused: 4, focus: "CÓRE/ABS"))
        XCTAssertEqual(focused.menu[0].prescribedSets, 4)
        XCTAssertEqual(focused.observations[0].rejection?.kind, .role, "Role cap is checked before other limits")
        // Existing normalization folds case/accents, but does not trim whitespace.
        // This deliberately mismatched blueprint is synthetic: buildBlueprintDayPlans
        // copies focus.area from the same priority allocation, so incidental padding
        // on that allocation is shared by both strings. This pins extraction parity,
        // not a guarantee that arbitrary independently supplied labels are sanitized.
        let padded = run([slot("Cable Crunch", "Abs")],
            plan(target: 10, ordinary: 2, focused: 4, focus: "  CORE/ABS  "))
        XCTAssertEqual(padded.menu[0].prescribedSets, 2)
        XCTAssertEqual(padded.observations[0].rejection?.kind, .sessionPriority)
    }

    func testActualGateReportsSharedMaintenanceCeiling() throws {
        let exercises = ["EZ-Bar Curl", "Incline Dumbbell Curl", "Bayesian Cable Curl", "Dumbbell Hammer Curl"]
            .map { slot($0, $0 == "Dumbbell Hammer Curl" ? "Brachialis" : "Biceps") }
        for recovery in [false, true] {
            let result = run(exercises, plan(recovery: recovery))
            XCTAssertEqual(result.menu.reduce(0) { $0 + $1.prescribedSets }, recovery ? 8 : 10)
            let blocked = try XCTUnwrap(result.observations.first { $0.rejection?.kind == .maintenance })
            XCTAssertEqual(blocked.rejection?.subject, "Biceps")
            XCTAssertEqual(try XCTUnwrap(blocked.rejection?.projected), recovery ? 9 : 11)
            XCTAssertEqual(try XCTUnwrap(blocked.rejection?.limit), recovery ? 8.01 : 10.01, accuracy: 0.000001)
        }
    }

    func testActualGateReportsFatigueWithoutAddingAClockLimit() throws {
        let result = run([slot("Standing Calf Raise", "Calves")], plan(fatigue: 2))
        XCTAssertEqual(result.menu[0].prescribedSets, 2, "Two sets still fit despite the one-minute test session")
        let refusal = try XCTUnwrap(result.observations[0].rejection)
        XCTAssertEqual(refusal.kind, .fatigue)
        XCTAssertEqual(refusal.subject, "Day 1")
        XCTAssertEqual(try XCTUnwrap(refusal.projected), 3)
        XCTAssertEqual(try XCTUnwrap(refusal.limit), 2)
    }

    func testUnrelatedWeeklyOvershootDoesNotBlockMaintenanceFunding() {
        let blueprint = plan(target: 1.5)
        let exercises = [slot("Cable Crunch", "Abs"), slot("Standing Calf Raise", "Calves"),
            slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("Cable Lateral Raise", "Lateral Deltoids")]
        let reservation = service.reserveWeeklyAppearanceFloors([exercises], blueprint: blueprint, weekNumber: 1)
        guard case .admitted = reservation.outcome else { return XCTFail("Premise: floors must reserve before funding") }
        XCTAssertEqual(reservation.menus[0][0].prescribedSets, 2)
        XCTAssertGreaterThan(Double(reservation.menus[0][0].prescribedSets),
            service.setBudgetLimits(for: blueprint).normalWeeklyPriority[0])
        XCTAssertEqual(reservation.menus[0][1].prescribedSets, 2)
        var reports: [String] = []
        let result = service.allocateWeeklySetPrescription([exercises], blueprint: blueprint, weekNumber: 1,
            appearancePlanningReport: { reports.append($0) })
        XCTAssertTrue(reports.contains { $0.hasPrefix("reserved role floors") })
        XCTAssertEqual(result[0][0].prescribedSets, 2)
        XCTAssertEqual(result[0][1].prescribedSets, 3, "Calf funding occurs after core already starts above its normal target")
    }

    func testEmptyMenuStillReportsAnEmptyFinalObservation() {
        let result = run([], plan())
        XCTAssertTrue(result.menu.isEmpty)
        XCTAssertTrue(result.observations.isEmpty)
    }

    func testMinimumDoseCannotBypassFatigueAndReportsUnresolvedGroups() {
        let exercises = [slot("Cable Crunch", "Abs"), slot("Standing Calf Raise", "Calves"),
            slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("Cable Lateral Raise", "Lateral Deltoids")]
        for poorNutrition in [false, true] {
            let blueprint = plan(fatigue: 10, poorNutrition: poorNutrition)
            let reservation = service.reserveWeeklyAppearanceFloors([exercises], blueprint: blueprint, weekNumber: 1)
            guard case .admitted = reservation.outcome else { return XCTFail("Test requires admitted floors") }
            var reports: [String] = []
            let result = service.allocateWeeklySetPrescription([exercises], blueprint: blueprint, weekNumber: 1,
                appearancePlanningReport: { reports.append($0) })
            XCTAssertEqual(result[0].map(\.exerciseName), exercises.map(\.exerciseName))
            XCTAssertEqual(result[0].map(\.prescribedSets), [2, 2, 2, 2, 2])
            XCTAssertEqual(reports.contains { $0.hasPrefix("minimum dose unresolved: Calves;") }, !poorNutrition)
            XCTAssertTrue(reports.contains { $0.hasPrefix("minimum dose unresolved: Glutes;") },
                "No candidate cannot be silently represented as a funded minimum")
        }
    }

    func testCollectingReceiptsDoesNotChangeAllocation() {
        let exercises = [slot("Cable Crunch", "Abs"), slot("Standing Calf Raise", "Calves")]
        let blueprint = plan(target: 2.5)
        let observed = run(exercises, blueprint)
        let unobserved = service.allocateWeeklySetPrescription([exercises], blueprint: blueprint, weekNumber: 1)[0]
        XCTAssertEqual(observed.menu.map(\.exerciseName), unobserved.map(\.exerciseName))
        XCTAssertEqual(observed.menu.map(\.muscleTarget), unobserved.map(\.muscleTarget))
        XCTAssertEqual(observed.menu.map(\.prescribedSets), unobserved.map(\.prescribedSets))
        XCTAssertEqual(observed.menu.map(\.movementPattern), unobserved.map(\.movementPattern))
    }

    func testMinimumFirstCandidateCannotStealRequiredPrioritySets() {
        let exercises = [slot("Cable Crunch", "Abs"), slot("Standing Calf Raise", "Calves"),
            slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("Cable Lateral Raise", "Lateral Deltoids")]
        let blueprint = plan(target: 4, fatigue: 12)
        let baseline = service.allocateSetPrescriptionCandidate([exercises], blueprint: blueprint,
            weekNumber: 1, reserveMaintenanceMinimum: false)
        let provisional = service.allocateSetPrescriptionCandidate([exercises], blueprint: blueprint,
            weekNumber: 1, reserveMaintenanceMinimum: true)
        XCTAssertTrue(baseline.floorReserved)
        XCTAssertTrue(provisional.floorReserved)
        XCTAssertEqual(baseline.menus[0][0].prescribedSets, 4)
        XCTAssertEqual(provisional.menus[0][0].prescribedSets, 2,
            "Counterexample: unconditional minimum-first funding steals the priority dose")
        XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(provisional.menus,
            baseline: baseline.menus, blueprint: blueprint, weekNumber: 1))
        XCTAssertEqual(service.compareAllocatedDoseOnly(provisional.menus,
            baseline: baseline.menus, blueprint: blueprint, weekNumber: 1),
            .rejected(.weeklyPriority(area: "Core/Abs")))
        var reports: [String] = []
        var receipts: [SetFundingObservation] = []
        var receiptCount = 0
        let result = service.allocateWeeklySetPrescription([exercises], blueprint: blueprint, weekNumber: 1,
            appearancePlanningReport: { reports.append($0) },
            setFundingReport: { receipts = $0; receiptCount += 1 })
        XCTAssertEqual(result[0].map(\.prescribedSets), baseline.menus[0].map(\.prescribedSets))
        XCTAssertEqual(receiptCount, 1)
        XCTAssertEqual(receipts.map(\.prescribedSets), result[0].map(\.prescribedSets))
        XCTAssertTrue(reports.contains { $0.hasPrefix("minimum dose plan rejected:") })
    }

    private func dosed(_ name: String, _ target: String, _ sets: Int) -> ClaudeService.PreSelectedExercise {
        var value = slot(name, target)
        value.prescribedSets = sets
        return value
    }

    func testDoseSafetyAndMinimumImprovementAreSeparate() {
        let blueprint = plan()
        let baseline = [[dosed("Cable Crunch", "Abs", 2), dosed("Standing Calf Raise", "Calves", 2)]]
        XCTAssertEqual(service.compareAllocatedDoseOnly(baseline, baseline: baseline,
            blueprint: blueprint, weekNumber: 1), .dosePreserved(improvesMaintenanceMinimum: false))
        XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(baseline, baseline: baseline,
            blueprint: blueprint, weekNumber: 1))
        var improved = baseline
        improved[0][1].prescribedSets = 3
        XCTAssertEqual(service.compareAllocatedDoseOnly(improved, baseline: baseline,
            blueprint: blueprint, weekNumber: 1), .dosePreserved(improvesMaintenanceMinimum: true))
        XCTAssertTrue(service.minimumDoseCandidatePreservesPlan(improved, baseline: baseline,
            blueprint: blueprint, weekNumber: 1))

        // Dose preservation is NOT permission to replace or relabel an exercise.
        var replaced = improved
        replaced[0][1] = dosed("Seated Calf Raise", "Calves", 3)
        XCTAssertEqual(service.compareAllocatedDoseOnly(replaced, baseline: baseline,
            blueprint: blueprint, weekNumber: 1), .dosePreserved(improvesMaintenanceMinimum: true))
        XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(replaced, baseline: baseline,
            blueprint: blueprint, weekNumber: 1))
        let original = improved[0][1]
        for (pattern, role) in [("Changed pattern", original.role), (original.movementPattern, .anchor)] {
            var relabeled = improved
            relabeled[0][1] = .init(exerciseName: original.exerciseName, muscleTarget: original.muscleTarget,
                movementPattern: pattern, role: role, prescribedSets: original.prescribedSets)
            XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(relabeled, baseline: baseline,
                blueprint: blueprint, weekNumber: 1))
        }
    }

    func testDoseComparisonRejectsShapeAndRoleFloorBeforeImprovement() {
        let blueprint = plan()
        let baseline = [[dosed("Cable Crunch", "Abs", 2), dosed("Standing Calf Raise", "Calves", 2)]]
        XCTAssertEqual(service.compareAllocatedDoseOnly([], baseline: baseline,
            blueprint: blueprint, weekNumber: 1), .rejected(.calendarShape))
        XCTAssertEqual(service.compareAllocatedDoseOnly(baseline, baseline: baseline,
            blueprint: plan(dayCount: 2), weekNumber: 1), .rejected(.calendarShape))
        var candidate = baseline
        candidate[0][0].prescribedSets = 1
        candidate[0][1].prescribedSets = 3
        XCTAssertEqual(service.compareAllocatedDoseOnly(candidate, baseline: baseline,
            blueprint: blueprint, weekNumber: 1), .rejected(.roleDose(day: 0, exercise: 0)))
        candidate[0][0].prescribedSets = 2
        candidate[0][1].prescribedSets = 4
        XCTAssertEqual(service.compareAllocatedDoseOnly(candidate, baseline: baseline,
            blueprint: blueprint, weekNumber: 1), .rejected(.roleDose(day: 0, exercise: 1)))
    }

    func testDoseComparisonRejectsMovingPriorityDoseBetweenDays() {
        let blueprint = plan(target: 5, dayCount: 2)
        let baseline = [[dosed("Cable Crunch", "Abs", 3)], [dosed("Cable Crunch", "Abs", 2)]]
        let shifted = [[dosed("Cable Crunch", "Abs", 2)], [dosed("Cable Crunch", "Abs", 3)]]
        XCTAssertEqual(baseline.joined().reduce(0) { $0 + $1.prescribedSets },
                       shifted.joined().reduce(0) { $0 + $1.prescribedSets })
        XCTAssertEqual(service.compareAllocatedDoseOnly(shifted, baseline: baseline,
            blueprint: blueprint, weekNumber: 1), .rejected(.sessionPriority(day: 0, area: "Core/Abs")))
    }

    func testDoseComparisonPreservesNonPriorityVolumeBeyondItsMinimum() {
        let blueprint = plan()
        let baseline = [[dosed("Standing Calf Raise", "Calves", 3)], [dosed("Standing Calf Raise", "Calves", 3)]]
        let candidate = [[dosed("Standing Calf Raise", "Calves", 2)], [dosed("Standing Calf Raise", "Calves", 3)]]
        // Five still exceeds the normal maintenance floor, but loses a baseline set.
        XCTAssertEqual(service.compareAllocatedDoseOnly(candidate, baseline: baseline,
            blueprint: plan(dayCount: 2), weekNumber: 1), .rejected(.maintenanceLoss(group: "Calves")))
        XCTAssertEqual(WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight: blueprint.calibration.recoveryConstrained), 3)
    }

    func testDoseComparisonRejectsWeightedOnlyPriorityLossWithinADay() {
        let blueprint = plan(target: 10, dayCount: 2, priorityArea: "Lateral Deltoids")
        let baseline = [[dosed("Dumbbell Arnold Press", "Anterior Deltoids", 4)],
                        [dosed("Dumbbell Arnold Press", "Anterior Deltoids", 3)]]
        let shifted = [[dosed("Dumbbell Arnold Press", "Anterior Deltoids", 3)],
                       [dosed("Dumbbell Arnold Press", "Anterior Deltoids", 4)]]
        let unit = WorkoutExerciseResponse(exerciseName: "Dumbbell Arnold Press", sets: 1,
            reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: "Anterior Deltoids")
        let credit = service.stimulusCredit(for: unit, area: "Lateral Deltoids")
        XCTAssertEqual(credit.directSets, 0, "Must exercise the weighted-only branch")
        XCTAssertGreaterThan(credit.weightedStimulus, 0)
        XCTAssertEqual(service.compareAllocatedDoseOnly(baseline, baseline: baseline,
            blueprint: blueprint, weekNumber: 2), .dosePreserved(improvesMaintenanceMinimum: false))
        XCTAssertEqual(service.compareAllocatedDoseOnly(shifted, baseline: baseline,
            blueprint: blueprint, weekNumber: 2), .rejected(.sessionPriority(day: 0, area: "Lateral Deltoids")))
    }

    func testDoseComparisonRejectsFatigueAndMaintenanceCeiling() {
        let baseline = [[dosed("Standing Calf Raise", "Calves", 2)]]
        let candidate = [[dosed("Standing Calf Raise", "Calves", 3)]]
        XCTAssertEqual(service.compareAllocatedDoseOnly(candidate, baseline: baseline,
            blueprint: plan(fatigue: 2), weekNumber: 1), .rejected(.fatigue(day: 0)))
        let crowded = [[dosed("Standing Calf Raise", "Calves", 3),
                        dosed("Seated Calf Raise", "Calves", 3),
                        dosed("Single-Leg Standing Calf Raise", "Calves", 3)]]
        XCTAssertEqual(service.compareAllocatedDoseOnly(crowded, baseline: baseline,
            blueprint: plan(recovery: true), weekNumber: 1), .rejected(.maintenanceCeiling(group: "Calves")))
    }

    func testDoseComparisonCanMeasureDifferentAppearanceCountsWithoutAuthorizingThem() {
        let blueprint = plan()
        let baseline = [[dosed("Standing Calf Raise", "Calves", 3)]]
        let candidate = [[dosed("Standing Calf Raise", "Calves", 2), dosed("Seated Calf Raise", "Calves", 2)]]
        XCTAssertEqual(service.compareAllocatedDoseOnly(candidate, baseline: baseline,
            blueprint: blueprint, weekNumber: 1), .dosePreserved(improvesMaintenanceMinimum: false))
        XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(candidate, baseline: baseline,
            blueprint: blueprint, weekNumber: 1))
    }
}
