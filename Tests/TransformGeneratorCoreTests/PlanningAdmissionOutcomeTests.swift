import XCTest
@testable import Transform

@MainActor
final class PlanningAdmissionOutcomeTests: XCTestCase {
    private let service = ClaudeService.shared

    private func slot(_ name: String, _ target: String) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
              movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
              role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: 1)
    }

    // The same overfull Arms / late Push fixture used by JointAppearancePlanningTests.
    private func fixture() -> (ClaudeService.ProgramBlueprint, [[ClaudeService.PreSelectedExercise]]) {
        let allocation = ClaudeService.BlueprintPriorityAllocation(area: "Triceps", priorityLevel: "High",
            rationale: "", targetFrequency: 2, targetExerciseSlots: 3, directSetTarget: 12,
            weightedStimulusTarget: 12, maxPerSessionDirectSets: 6, maxFocusSessionDirectSets: 8,
            preferredStyles: ["Arms", "Push"], preferredMovementPatterns: [], volumeBias: "Moderate", directWorkBias: "High")
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "test", splitRecommendation: "Arms / Push",
            weeklyTrainingDays: 2, priorityAllocations: [allocation], dayPlans: [
                .init(dayIndex: 1, style: "Arms", focusArea: "Biceps", supportAreas: ["Triceps"],
                    targetFatigueCap: 34, targetSessionMinutes: 75, targetPrioritySlots: 2, emphasisPatterns: [], isRestDay: false),
                .init(dayIndex: 2, style: "Push", focusArea: "Triceps", supportAreas: [],
                    targetFatigueCap: 48, targetSessionMinutes: 75, targetPrioritySlots: 2, emphasisPatterns: [], isRestDay: false)
            ], topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: "(none)", programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        return (blueprint, [
            [slot("EZ-Bar Curl", "Biceps"), slot("Incline Dumbbell Curl", "Biceps"),
             slot("Rope Triceps Pressdown", "Triceps"), slot("Overhead Cable Triceps Extension", "Triceps"),
             slot("EZ-Bar Skull Crusher", "Triceps"), slot("V-Bar Pressdown", "Triceps")],
            [slot("Incline Dumbbell Press", "Upper Chest"), slot("Rope Triceps Pressdown", "Triceps"),
             slot("Overhead Cable Triceps Extension", "Triceps"), slot("Cable Lateral Raise", "Lateral Deltoids"),
             slot("Cable Pallof Press", "Obliques")]
        ])
    }

    private func observedOutcome(week: Int = 1, locks: [Int] = [], maximumStates: Int = 512,
                                 file: StaticString = #filePath, line: UInt = #line) -> ClaudeService.RoleFloorAdmission? {
        let (blueprint, menus) = fixture()
        var outcomes: [ClaudeService.RoleFloorAdmission] = []
        let observed = service.allocateWeeklySetPrescription(menus, blueprint: blueprint, weekNumber: week,
            lockedPrefixCounts: locks, maximumAppearanceStates: maximumStates,
            roleFloorAdmissionReport: { outcomes.append($0) })
        let unobserved = service.allocateWeeklySetPrescription(menus, blueprint: blueprint, weekNumber: week,
            lockedPrefixCounts: locks, maximumAppearanceStates: maximumStates)
        XCTAssertEqual(outcomes.count, 1, "Publish only the chosen allocation's outcome", file: file, line: line)
        XCTAssertEqual(observed.map { $0.map(\.exerciseName) }, unobserved.map { $0.map(\.exerciseName) }, file: file, line: line)
        XCTAssertEqual(observed.map { $0.map(\.muscleTarget) }, unobserved.map { $0.map(\.muscleTarget) }, file: file, line: line)
        XCTAssertEqual(observed.map { $0.map(\.movementPattern) }, unobserved.map { $0.map(\.movementPattern) }, file: file, line: line)
        XCTAssertEqual(observed.map { $0.map(\.role) }, unobserved.map { $0.map(\.role) }, file: file, line: line)
        XCTAssertEqual(observed.map { $0.map(\.prescribedSets) }, unobserved.map { $0.map(\.prescribedSets) }, file: file, line: line)
        return outcomes.first
    }

    func testSearchExhaustionRemainsDistinctFromCandidatePoolInfeasibility() {
        guard case .searchLimit(let reasons)? = observedOutcome(maximumStates: 1) else {
            return XCTFail("The initial overfull pool needs exploration, not an infeasibility verdict")
        }
        XCTAssertFalse(reasons.isEmpty)
        XCTAssertEqual(observedOutcome(), .admitted,
            "The same pool is admissible when the bounded search can explore it")
    }

    func testFullyProtectedConflictRemainsInfeasibleThroughAllocation() {
        guard case .infeasible(let reasons)? = observedOutcome(locks: [6, 5]) else {
            return XCTFail("No appearance can be removed from the protected over-budget pool")
        }
        XCTAssertFalse(reasons.isEmpty)
    }

    func testSuccessfulReservationPublishesAdmittedExactlyOnce() {
        XCTAssertEqual(observedOutcome(), .admitted)
    }

    func testNonpositiveSearchBudgetsDoNotClaimInfeasibility() {
        for budget in [-1, 0] {
            guard case .searchLimit(let reasons)? = observedOutcome(maximumStates: budget) else {
                XCTFail("An unsearched pool is not proven infeasible (budget \(budget))")
                continue
            }
            XCTAssertFalse(reasons.isEmpty)
        }
    }

    func testDeloadIsNotMisreportedAsAnAdmittedLoadingWeek() {
        XCTAssertEqual(observedOutcome(week: MesocyclePhase.deloadWeek, locks: [6, 5], maximumStates: 1), .deloadPolicy)
    }
}
