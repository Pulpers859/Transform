import Foundation
import XCTest
@testable import Transform

@MainActor
final class ExactFundedDoseTests: XCTestCase {
    private let service = ClaudeService.shared

    private func item(_ name: String, _ target: String, _ sets: Int) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
            movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
            role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: sets)
    }

    private var menus: [[ClaudeService.PreSelectedExercise]] {
        let day = [item("Rope Triceps Pressdown", "Triceps", 2),
            item("Overhead Cable Triceps Extension", "Triceps", 2),
            item("Seated Calf Raise", "Calves", 2), item("Machine Leg Extension", "Quads", 2),
            item("Cable Crunch", "Abs", 2)]
        return [day, [], [], day, [], [], []]
    }

    // Synthetic quantitative fixture, not a claim of sensible session style or admission history.
    private func baseline(_ menus: [[ClaudeService.PreSelectedExercise]], week: Int = 1,
        admission: ClaudeService.RoleFloorAdmission = .admitted, fatigue: Int = 60,
        priorityTarget: Double? = nil) -> ClaudeService.SubstitutionPlanningBaseline {
        let allocations: [ClaudeService.BlueprintPriorityAllocation] = priorityTarget.map { target in
            [.init(area: "Triceps", priorityLevel: "High", rationale: "", targetFrequency: 2,
                targetExerciseSlots: 2, directSetTarget: target, weightedStimulusTarget: target,
                maxPerSessionDirectSets: 8, maxFocusSessionDirectSets: 8, preferredStyles: [],
                preferredMovementPatterns: [], volumeBias: "High", directWorkBias: "High")]
        } ?? []
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "exact-dose-fixture",
            splitRecommendation: "Upper / Lower", weeklyTrainingDays: 2,
            priorityAllocations: allocations, dayPlans: (0..<7).map { day in
                .init(dayIndex: day + 1, style: day == 0 || day == 3 ? "Upper" : "Rest",
                    focusArea: nil, supportAreas: [], targetFatigueCap: day == 0 || day == 3 ? fatigue : 0,
                    targetSessionMinutes: 60, targetPrioritySlots: 0, emphasisPatterns: [],
                    isRestDay: day != 0 && day != 3)
            }, topLeverageChange: "", posturalFocus: "", injuryRiskFocus: "", programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        return .init(menus: menus, blueprint: blueprint, weekNumber: week,
            lockedPrefixCounts: Array(repeating: 0, count: 7),
            retainedKeysByDay: Array(repeating: Set<String>(), count: 7), exerciseHistory: nil,
            selectionFocusIntents: Array(repeating: nil, count: 7), roleFloorAdmission: admission)
    }

    private func signature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
        menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
    }

    func testExactProposalPreservesItsOwnSetsWithoutMutatingEitherInput() {
        var original = menus
        original[0][1].prescribedSets = 3
        original[3][0].prescribedSets = 3
        var candidate = original
        candidate[0][0].prescribedSets = 3
        candidate[0][1].prescribedSets = 2
        candidate[3][0].prescribedSets = 2
        candidate[3][1].prescribedSets = 3
        let base = baseline(original)
        let before = signature(candidate), old = signature(base.menus)
        XCTAssertEqual(service.verifyExactFundedDose(candidate, baseline: base), .verified)
        XCTAssertEqual(signature(candidate), before)
        XCTAssertEqual(signature(base.menus), old)
    }

    func testRoleFloorAndCeilingAreNotBypassed() {
        for sets in [1, 4] {
            var candidate = menus
            candidate[0][0].prescribedSets = sets
            XCTAssertEqual(service.verifyExactFundedDose(candidate, baseline: baseline(menus)),
                .refused(.dose(.roleDose(day: 0, exercise: 0))))
        }
    }

    func testFatigueAndMaintenanceCeilingsAreNotBypassed() {
        XCTAssertEqual(service.verifyExactFundedDose(menus, baseline: baseline(menus, fatigue: 1)),
            .refused(.dose(.fatigue(day: 0))))
        var candidate = menus
        for day in [0, 3] {
            candidate[day][0].prescribedSets = 3
            candidate[day][1].prescribedSets = 3
        }
        XCTAssertEqual(service.verifyExactFundedDose(candidate, baseline: baseline(menus)),
            .refused(.dose(.maintenanceCeiling(group: "Triceps"))))
    }

    func testDailyPriorityLossRefusesDespiteEqualWeeklyTotals() {
        var original = menus
        original[0][0].prescribedSets = 3
        var candidate = original
        candidate[0][0].prescribedSets = 2
        candidate[3][0].prescribedSets = 3
        XCTAssertEqual(service.verifyExactFundedDose(candidate, baseline: baseline(original, priorityTarget: 9)),
            .refused(.dose(.sessionPriority(day: 0, area: "Triceps"))))
    }

    func testInheritedWeeklyOverageFailsAbsoluteCeiling() {
        let base = baseline(menus, priorityTarget: 7)
        XCTAssertEqual(service.compareAllocatedDoseOnly(menus, baseline: menus, blueprint: base.blueprint, weekNumber: 1),
            .dosePreserved(improvesMaintenanceMinimum: false), "Control: the old comparator grandfathers the eight-set baseline")
        XCTAssertEqual(service.verifyExactFundedDose(menus, baseline: base),
            .refused(.weeklyPriorityCeiling(area: "Triceps")))
    }

    func testUpperChestLossCannotHideInsideBroadChestPreservation() {
        var original = menus
        for day in [0, 3] {
            original[day][0] = item("Machine Incline Press", "Upper Chest", 3)
            original[day][1] = item("Cable Fly", "Chest", 2)
        }
        var candidate = original
        candidate[0][0].prescribedSets = 2
        candidate[0][1].prescribedSets = 3
        let base = baseline(original)
        XCTAssertEqual(service.compareAllocatedDoseOnly(candidate, baseline: original, blueprint: base.blueprint, weekNumber: 1),
            .dosePreserved(improvesMaintenanceMinimum: false), "Control: broad Chest remains ten sets")
        XCTAssertEqual(service.verifyExactFundedDose(candidate, baseline: base),
            .refused(.primaryRegionLoss(region: "upper chest", baselineSets: 6, candidateSets: 5)))
    }

    func testUnknownNameCannotUseFallbackMetadataAsRegionEvidence() {
        var candidate = menus
        candidate[0][0] = item("Uncatalogued Triceps Drill", "Triceps", 2)
        XCTAssertEqual(service.verifyExactFundedDose(candidate, baseline: baseline(menus)),
            .refused(.unknownExercise(day: 0, exercise: 0)))
    }

    func testRestShapeSevenSlotsAndNonpositiveSetsRefuse() {
        var restWork = menus
        restWork[1] = [item("Cable Crunch", "Abs", 2)]
        var sevenSlots = menus
        sevenSlots[0] += [item("Cable Fly", "Chest", 2), item("Machine Leg Curl", "Hamstrings", 2)]
        var zero = menus
        zero[0][0].prescribedSets = 0
        for candidate in [restWork, sevenSlots, zero, Array(menus.dropLast())] {
            XCTAssertEqual(service.verifyExactFundedDose(candidate, baseline: baseline(menus)), .refused(.invalidContext))
        }
        XCTAssertEqual(service.verifyExactFundedDose(menus, baseline: baseline(zero)), .refused(.invalidContext))
    }

    func testDeloadAndUnadmittedBaselineRefuse() {
        XCTAssertEqual(service.verifyExactFundedDose(menus, baseline: baseline(menus, week: 4)), .refused(.unsupportedWeek))
        XCTAssertEqual(service.verifyExactFundedDose(menus, baseline: baseline(menus, admission: .unassessed)),
            .refused(.baselineNotAdmitted))
    }

    func testIntMaxCandidateCountRefusesBeforeArithmetic() {
        var candidate = menus
        candidate[0][0] = item("Machine Incline Press", "Upper Chest", Int.max)
        XCTAssertEqual(service.verifyExactFundedDose(candidate, baseline: baseline(menus)),
            .refused(.invalidContext))
    }

    func testIntMaxBaselineCountRefusesBeforeArithmetic() {
        var original = menus
        original[0][0] = item("Machine Incline Press", "Upper Chest", Int.max)
        XCTAssertEqual(service.verifyExactFundedDose(menus, baseline: baseline(original)),
            .refused(.invalidContext))
    }

    func testNegativeCountsRefuseInEitherInput() {
        for sets in [-1, Int.min] {
            var malformed = menus
            malformed[0][0] = item("Machine Incline Press", "Upper Chest", sets)
            XCTAssertEqual(service.verifyExactFundedDose(malformed, baseline: baseline(menus)),
                .refused(.invalidContext), "Candidate sets=\(sets)")
            XCTAssertEqual(service.verifyExactFundedDose(menus, baseline: baseline(malformed)),
                .refused(.invalidContext), "Baseline sets=\(sets)")
        }
    }

    func testValidFourSetSecondaryDoseStillPassesInWeekTwo() {
        var plan = menus
        for day in [0, 3] {
            plan[day][0] = item("Machine Incline Press", "Upper Chest", 4)
        }
        XCTAssertEqual(service.proceduralSets(for: 2, exerciseName: "Machine Incline Press",
            muscleTarget: "Upper Chest"), 4, "Control: this is the existing phase ceiling")
        XCTAssertEqual(service.verifyExactFundedDose(plan, baseline: baseline(plan, week: 2)), .verified)
    }
}
