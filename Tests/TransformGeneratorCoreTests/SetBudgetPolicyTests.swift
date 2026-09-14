import XCTest
@testable import Transform

@MainActor
final class SetBudgetPolicyTests: XCTestCase {
    private let service = ClaudeService.shared

    private func plan(target: Double? = nil, ordinary: Double = 10, focused: Double = 10,
                      focus: String? = nil, fatigue: Int = 48,
                      recovery: Bool = false, poorNutrition: Bool = false) -> ClaudeService.ProgramBlueprint {
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
            [.init(area: "Core/Abs", priorityLevel: "Medium", rationale: "", targetFrequency: 1,
                targetExerciseSlots: 1, directSetTarget: value, weightedStimulusTarget: value,
                maxPerSessionDirectSets: ordinary, maxFocusSessionDirectSets: focused,
                preferredStyles: ["Upper"], preferredMovementPatterns: [], volumeBias: "Moderate", directWorkBias: "High")]
        } ?? []
        return .init(evidenceVersion: "test", splitRecommendation: "Upper", weeklyTrainingDays: 1,
            priorityAllocations: allocations, dayPlans: [
                .init(dayIndex: 1, style: "Upper", focusArea: focus, supportAreas: [],
                    targetFatigueCap: fatigue, targetSessionMinutes: 1, targetPrioritySlots: 1,
                    emphasisPatterns: [], isRestDay: false)
            ], topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: "(none)",
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
}
