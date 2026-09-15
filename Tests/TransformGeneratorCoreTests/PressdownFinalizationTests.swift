import XCTest
@testable import Transform

@MainActor
final class PressdownFinalizationTests: XCTestCase {
    private let service = ClaudeService.shared

    private func slot(_ name: String, _ target: String) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
            movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
            role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: 2)
    }

    private var focus: ClaudeService.MusclePriorityIntent {
        .init(area: "Biceps", priorityLevel: "High", rank: 0, rationale: "test", weeklyDayTarget: 1,
            weeklyExerciseTarget: 1, weeklyDirectSetTarget: 2, weeklyStimulusTarget: 2,
            preferredStyles: ["Arms"], preferredMovementPatterns: [], coverageKeywords: [],
            accessoryCatalog: [], volumeBias: "Moderate", directWorkBias: "High")
    }

    private func intent(focused: Bool = false) -> ClaudeService.TrainingIntentPlan {
        .init(splitRecommendation: "Arms", weeklyTrainingDays: 1, programmingNotes: [],
            priorities: focused ? [focus] : [], topLeverageChange: "", posturalFocus: "(none)",
            injuryRiskFocus: "(none)", calibration: service.neutralCalibrationProfile())
    }

    // Synthetic guard isolation only: an asserted admitted status is not actual reservation
    // evidence, and these three-slot inputs are not complete useful workouts.
    private func baseline(status: ClaudeService.RoleFloorAdmission = .admitted,
                          focused: Bool = false, redundant: Bool = true) -> ClaudeService.SubstitutionPlanningBaseline {
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "test", splitRecommendation: "Arms",
            weeklyTrainingDays: 1, priorityAllocations: [], dayPlans: [
                .init(dayIndex: 1, style: "Arms", focusArea: focused ? "Biceps" : nil, supportAreas: [],
                    targetFatigueCap: 48, targetSessionMinutes: 75, targetPrioritySlots: 1,
                    emphasisPatterns: [], isRestDay: false)
            ], topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: "(none)",
            programmingNotes: [], calibration: service.neutralCalibrationProfile())
        let menus = [[slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
                      slot(redundant ? "V-Bar Pressdown" : "Cable Kickback", "Triceps")]]
        return .init(menus: menus, blueprint: blueprint, weekNumber: 1, lockedPrefixCounts: [0],
            retainedKeysByDay: [[]], exerciseHistory: nil, selectionFocusIntents: [focused ? focus : nil],
            roleFloorAdmission: status)
    }

    private func proposal(_ baseline: ClaudeService.SubstitutionPlanningBaseline) -> [[ClaudeService.PreSelectedExercise]] {
        var result = baseline.menus
        result[0][2] = slot("Cable Kickback", "Triceps")
        return result
    }

    private var nonadmitted: [ClaudeService.RoleFloorAdmission] {
        [.unassessed, .deloadPolicy, .infeasible(["protected budget"]), .searchLimit(["budget"])]
    }

    func testAdmittedQualifiedStableOrderPassesFinalVerification() {
        let base = baseline(), candidate = proposal(baseline())
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(candidate, plannedBaseline: base),
            .qualified(day: 0, excessBefore: 1, excessAfter: 0))
        XCTAssertEqual(service.verifyFinalPressdownReplacement(candidate, admission: .admitted,
            baseline: base, trainingIntent: intent()), .adopted(day: 0, excessBefore: 1, excessAfter: 0))
    }

    func testEveryNonadmittedBaselineAndFinalStatusIsRejected() {
        for status in nonadmitted {
            let base = baseline(status: status)
            XCTAssertEqual(service.verifyFinalPressdownReplacement(proposal(base), admission: .admitted,
                baseline: base, trainingIntent: intent()), .baselineNotAdmitted(status))
            let admitted = baseline()
            XCTAssertEqual(service.verifyFinalPressdownReplacement(proposal(admitted), admission: status,
                baseline: admitted, trainingIntent: intent()), .finalNotAdmitted(status))
        }
    }

    func testFreshAllocationCannotChangeDosesOrRemoveAppearances() {
        let base = baseline()
        var candidate = proposal(base)
        candidate[0][0].prescribedSets += 1
        XCTAssertEqual(service.verifyFinalPressdownReplacement(candidate, admission: .admitted,
            baseline: base, trainingIntent: intent()), .finalVerification(.rejected(.eligibility(.changeScope))))
        candidate = proposal(base)
        candidate[0].removeLast()
        XCTAssertEqual(service.verifyFinalPressdownReplacement(candidate, admission: .admitted,
            baseline: base, trainingIntent: intent()), .finalVerification(.rejected(.eligibility(.shape))))
    }

    func testRealFocusOrderingChangeRejectsOtherwiseQualifiedCandidate() {
        let original = baseline(focused: true)
        var menus = original.menus
        menus[0].swapAt(0, 1)
        let base = ClaudeService.SubstitutionPlanningBaseline(menus: menus, blueprint: original.blueprint,
            weekNumber: original.weekNumber, lockedPrefixCounts: [0], retainedKeysByDay: [[]],
            exerciseHistory: nil, selectionFocusIntents: [focus], roleFloorAdmission: .admitted)
        let candidate = proposal(base)
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(candidate, plannedBaseline: base),
            .qualified(day: 0, excessBefore: 1, excessAfter: 0), "Isolate ordering, not another refusal")
        let arranged = service.reorderedMenusForSessionFlow(candidate, blueprint: base.blueprint,
            trainingIntent: intent(focused: true), lockedPrefixCounts: [0])
        XCTAssertNotEqual(arranged[0].map(\.exerciseName), candidate[0].map(\.exerciseName))
        XCTAssertEqual(arranged[0].first?.exerciseName, "EZ-Bar Curl")
        XCTAssertEqual(service.verifyFinalPressdownReplacement(candidate, admission: .admitted,
            baseline: base, trainingIntent: intent(focused: true)), .orderChange)
    }

    func testUnchangedFinalizationPreservesOriginalMenusMessagesAndReceipts() {
        let messages = ["original allocation diagnostic"]
        let receipts = [SetFundingObservation(dayIndex: 0, exerciseIndex: 0, exerciseName: "EZ-Bar Curl",
            muscleTarget: "Biceps", prescribedSets: 2, rejection: nil)]
        for status in nonadmitted + [.admitted] {
            let base = baseline(status: status, redundant: status != .admitted)
            for collectFunding in [false, true] {
                let result = service.finalizePressdownReduction(base, trainingIntent: intent(),
                    baselineMessages: messages, baselineReceipts: receipts, collectFunding: collectFunding)
                XCTAssertEqual(result.decision, status == .admitted ? .search(.noRedundancy) : .baselineNotAdmitted(status))
                XCTAssertEqual(result.plan.menus.map { $0.map(\.exerciseName) }, base.menus.map { $0.map(\.exerciseName) })
                XCTAssertEqual(result.plan.menus.map { $0.map(\.muscleTarget) }, base.menus.map { $0.map(\.muscleTarget) })
                XCTAssertEqual(result.plan.menus.map { $0.map(\.movementPattern) }, base.menus.map { $0.map(\.movementPattern) })
                XCTAssertEqual(result.plan.menus.map { $0.map(\.role) }, base.menus.map { $0.map(\.role) })
                XCTAssertEqual(result.plan.menus.map { $0.map(\.prescribedSets) }, base.menus.map { $0.map(\.prescribedSets) })
                XCTAssertEqual(result.plan.roleFloorAdmission, base.roleFloorAdmission)
                XCTAssertEqual(result.messages, messages)
                XCTAssertEqual(result.receipts, receipts)
            }
        }
    }

    func testSpeculativeReallocationFailureRestoresOriginalDiagnostics() {
        let base = baseline()
        let messages = ["original chosen report"]
        let receipts = [SetFundingObservation(dayIndex: 0, exerciseIndex: 0,
            exerciseName: "EZ-Bar Curl", muscleTarget: "Biceps", prescribedSets: 2,
            rejection: .init(kind: .role, subject: "original role", projected: 3, limit: 2))]
        let search = service.searchPressdownReduction(in: base)
        guard case .proposed = search.outcome else { return XCTFail("Must reach a speculative allocation") }
        guard case .adopted = service.verifyFinalPressdownReplacement(search.proposedMenus,
            admission: .admitted, baseline: base, trainingIntent: intent()) else {
            return XCTFail("Preliminary checks must pass before testing actual reallocation refusal")
        }
        for collect in [false, true] {
            let result = service.finalizePressdownReduction(base, trainingIntent: intent(),
                baselineMessages: messages, baselineReceipts: receipts, collectFunding: collect)
            guard case .finalNotAdmitted(.infeasible) = result.decision else {
                XCTFail("Actual three-slot reservation violates the five-exercise floor: \(result.decision)")
                continue
            }
            XCTAssertEqual(result.messages, messages)
            XCTAssertEqual(result.receipts, receipts)
            XCTAssertEqual(result.plan.roleFloorAdmission, base.roleFloorAdmission)
            XCTAssertEqual(result.plan.menus.map { $0.map(\.exerciseName) }, base.menus.map { $0.map(\.exerciseName) })
            XCTAssertEqual(result.plan.menus.map { $0.map(\.prescribedSets) }, base.menus.map { $0.map(\.prescribedSets) })
            XCTAssertFalse(result.messages.contains { $0.contains("CONFLICT") })
        }
    }
}
