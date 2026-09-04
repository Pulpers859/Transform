import Foundation
import XCTest
@testable import Transform

/// The owner ran a real generation whose "Training Intent" block promised numbers ("3 days",
/// "6 direct sets") that the "Blueprint" block, printed a few lines below it, silently overrode
/// — nothing reconciled the two. He read "3 days" for Lateral Deltoids while the plan that
/// actually got built delivered 2 exposures, and read "2 days, 6 sets" for Core/Abs while the
/// plan delivered 1 exposure and 5 sets.
///
/// `trainingIntentContext(from:blueprint:)` now keeps the intent's asked-for number (so the
/// record of what was requested survives calibration, per the doc comment on
/// `styleFeasibleAllocations`) and appends what the week will actually deliver, in-line, only
/// where the two disagree. See the doc comment on `trainingIntentContext` in
/// `WorkoutGeneratorService+TrainingIntentBlueprint.swift` for why that disagreement can only
/// come from the style-feasibility clamp, never a recovery-modulation trim.
@MainActor
final class IntentBlueprintReconciliationTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Builders

    private func intent(
        area: String,
        priorityLevel: String = "High",
        rank: Int = 0,
        weeklyDayTarget: Int,
        weeklyExerciseTarget: Int,
        weeklyDirectSetTarget: Double,
        weeklyStimulusTarget: Double,
        preferredStyles: [String] = ["Upper"]
    ) -> ClaudeService.MusclePriorityIntent {
        ClaudeService.MusclePriorityIntent(
            area: area,
            priorityLevel: priorityLevel,
            rank: rank,
            rationale: "",
            weeklyDayTarget: weeklyDayTarget,
            weeklyExerciseTarget: weeklyExerciseTarget,
            weeklyDirectSetTarget: weeklyDirectSetTarget,
            weeklyStimulusTarget: weeklyStimulusTarget,
            preferredStyles: preferredStyles,
            preferredMovementPatterns: [],
            coverageKeywords: [],
            accessoryCatalog: [],
            volumeBias: "Moderate",
            directWorkBias: "Direct emphasis"
        )
    }

    private func allocation(
        area: String,
        priorityLevel: String = "High",
        targetFrequency: Int,
        targetExerciseSlots: Int,
        directSetTarget: Double,
        weightedStimulusTarget: Double,
        preferredStyles: [String] = ["Upper"]
    ) -> ClaudeService.BlueprintPriorityAllocation {
        ClaudeService.BlueprintPriorityAllocation(
            area: area,
            priorityLevel: priorityLevel,
            rationale: "",
            targetFrequency: targetFrequency,
            targetExerciseSlots: targetExerciseSlots,
            directSetTarget: directSetTarget,
            weightedStimulusTarget: weightedStimulusTarget,
            maxPerSessionDirectSets: 4,
            maxFocusSessionDirectSets: 8,
            preferredStyles: preferredStyles,
            preferredMovementPatterns: [],
            volumeBias: "Moderate",
            directWorkBias: "Direct emphasis"
        )
    }

    private func plan(priorities: [ClaudeService.MusclePriorityIntent]) -> ClaudeService.TrainingIntentPlan {
        ClaudeService.TrainingIntentPlan(
            splitRecommendation: "Adaptive Hypertrophy Split",
            weeklyTrainingDays: 5,
            programmingNotes: [],
            priorities: priorities,
            topLeverageChange: "(not provided)",
            posturalFocus: "(none)",
            injuryRiskFocus: "(none)",
            calibration: service.neutralCalibrationProfile()
        )
    }

    private func blueprint(allocations: [ClaudeService.BlueprintPriorityAllocation]) -> ClaudeService.ProgramBlueprint {
        ClaudeService.ProgramBlueprint(
            evidenceVersion: "test",
            splitRecommendation: "Adaptive Hypertrophy Split",
            weeklyTrainingDays: 5,
            priorityAllocations: allocations,
            dayPlans: [],
            topLeverageChange: "(not provided)",
            posturalFocus: "(none)",
            injuryRiskFocus: "(none)",
            programmingNotes: [],
            calibration: service.neutralCalibrationProfile()
        )
    }

    // MARK: - Agreement: no new noise on the common path

    func testAgreementRendersUnchanged() {
        let text = service.reconciledWeeklyTargetsText(
            intent: intent(
                area: "Triceps",
                weeklyDayTarget: 3,
                weeklyExerciseTarget: 3,
                weeklyDirectSetTarget: 10,
                weeklyStimulusTarget: 11
            ),
            allocation: allocation(
                area: "Triceps",
                targetFrequency: 3,
                targetExerciseSlots: 3,
                directSetTarget: 10,
                weightedStimulusTarget: 11
            )
        )

        XCTAssertEqual(text, "3 days, 3 targeted exercises, 10 direct sets, 11 weighted stimulus")
        XCTAssertFalse(text.contains("trimmed"), "Agreement must not add reconciliation noise: \(text)")
    }

    // MARK: - A frequency clamp that does not force a set/stimulus recut: Lateral Deltoids

    func testFrequencyClampRendersBothNumbers() {
        let text = service.reconciledWeeklyTargetsText(
            intent: intent(
                area: "Lateral Deltoids",
                weeklyDayTarget: 3,
                weeklyExerciseTarget: 3,
                weeklyDirectSetTarget: 10,
                weeklyStimulusTarget: 11
            ),
            allocation: allocation(
                area: "Lateral Deltoids",
                targetFrequency: 2,
                targetExerciseSlots: 3,
                directSetTarget: 10,
                weightedStimulusTarget: 11
            )
        )

        XCTAssertEqual(
            text,
            "3 days (trimmed to 2 by the chosen split), 3 targeted exercises, 10 direct sets, 11 weighted stimulus"
        )
    }

    // MARK: - A frequency clamp that also forces a set/stimulus recut: Core/Abs

    func testSetTargetTrimRendersBothNumbers() {
        let text = service.reconciledWeeklyTargetsText(
            intent: intent(
                area: "Core/Abs",
                priorityLevel: "Medium",
                weeklyDayTarget: 2,
                weeklyExerciseTarget: 2,
                weeklyDirectSetTarget: 6,
                weeklyStimulusTarget: 8.5
            ),
            allocation: allocation(
                area: "Core/Abs",
                priorityLevel: "Medium",
                targetFrequency: 1,
                targetExerciseSlots: 2,
                directSetTarget: 5,
                weightedStimulusTarget: 7.1
            )
        )

        XCTAssertEqual(
            text,
            "2 days (trimmed to 1 by the chosen split), 2 targeted exercises, 6 direct sets (trimmed to 5 by the chosen split), 8.5 weighted stimulus (trimmed to 7.1 by the chosen split)"
        )
    }

    // MARK: - The exact reported defect, rendered end-to-end through the real block builder

    func testTheReportedDefectRendersAReadableReconciliation() {
        let lateralDeltoids = intent(
            area: "Lateral Deltoids",
            rank: 1,
            weeklyDayTarget: 3,
            weeklyExerciseTarget: 3,
            weeklyDirectSetTarget: 10,
            weeklyStimulusTarget: 11
        )
        let coreAbs = intent(
            area: "Core/Abs",
            priorityLevel: "Medium",
            rank: 2,
            weeklyDayTarget: 2,
            weeklyExerciseTarget: 2,
            weeklyDirectSetTarget: 6,
            weeklyStimulusTarget: 8.5
        )

        let lateralDeltoidsAllocation = allocation(
            area: "Lateral Deltoids",
            targetFrequency: 2,
            targetExerciseSlots: 3,
            directSetTarget: 10,
            weightedStimulusTarget: 11
        )
        let coreAbsAllocation = allocation(
            area: "Core/Abs",
            priorityLevel: "Medium",
            targetFrequency: 1,
            targetExerciseSlots: 2,
            directSetTarget: 5,
            weightedStimulusTarget: 7.1
        )

        let text = service.trainingIntentContext(
            from: plan(priorities: [lateralDeltoids, coreAbs]),
            blueprint: blueprint(allocations: [lateralDeltoidsAllocation, coreAbsAllocation])
        )

        // A non-programmer reading this line should see both what was asked for and what the
        // week will really deliver, without needing to cross-reference the Blueprint block below.
        XCTAssertTrue(
            text.contains(
                "weekly_targets: 3 days (trimmed to 2 by the chosen split), 3 targeted exercises, 10 direct sets, 11 weighted stimulus"
            ),
            "Lateral Deltoids must show both the asked-for 3 days and the delivered 2: \(text)"
        )
        XCTAssertTrue(
            text.contains(
                "weekly_targets: 2 days (trimmed to 1 by the chosen split), 2 targeted exercises, 6 direct sets (trimmed to 5 by the chosen split), 8.5 weighted stimulus (trimmed to 7.1 by the chosen split)"
            ),
            "Core/Abs must show the asked-for and delivered days, sets, and stimulus together: \(text)"
        )
    }

    // MARK: - No matching allocation: render the asked-for numbers rather than guess

    func testMissingAllocationRendersAskedForNumbersOnly() {
        let text = service.reconciledWeeklyTargetsText(
            intent: intent(
                area: "Calves",
                weeklyDayTarget: 2,
                weeklyExerciseTarget: 2,
                weeklyDirectSetTarget: 6,
                weeklyStimulusTarget: 7
            ),
            allocation: nil
        )

        XCTAssertEqual(text, "2 days, 2 targeted exercises, 6 direct sets, 7 weighted stimulus")
    }
}
