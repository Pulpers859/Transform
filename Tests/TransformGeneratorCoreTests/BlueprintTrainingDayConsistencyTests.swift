import XCTest
@testable import Transform

/// The blueprint must describe the week it actually built.
///
/// `ProgramBlueprint.weeklyTrainingDays` is not a display field. `validateWeekResponse`
/// compares the generated week's training-day count against it, and the resulting
/// "Blueprint calls for N training days, but the generated week has M." is listed in
/// `lockedMenuHardFailurePatterns` — so under menu lock it is a hard failure, the correction
/// pass is skipped entirely, and every paid parallel candidate is discarded for the
/// procedural week.
///
/// The regression: `programBlueprint` reported the REQUESTED day count while `dayPlans` was
/// built from `defaultRestPattern`, which for six days on a deload week returns two rest days
/// rather than one. Six requested, five built, guaranteed hard failure — every deload week,
/// for every six-day lifter. Nothing in the validator is deload-aware, so nothing caught it.
@MainActor
final class BlueprintTrainingDayConsistencyTests: XCTestCase {

    private let service = ClaudeService.shared

    private func plan(weeklyTrainingDays: Int) -> ClaudeService.TrainingIntentPlan {
        ClaudeService.TrainingIntentPlan(
            splitRecommendation: "Push / Pull / Legs",
            weeklyTrainingDays: weeklyTrainingDays,
            programmingNotes: [],
            priorities: [
                ClaudeService.MusclePriorityIntent(
                    area: "Back",
                    priorityLevel: "High",
                    rank: 0,
                    rationale: "",
                    weeklyDayTarget: 2,
                    weeklyExerciseTarget: 3,
                    weeklyDirectSetTarget: 10,
                    weeklyStimulusTarget: 10,
                    preferredStyles: ["Pull", "Upper"],
                    preferredMovementPatterns: [],
                    coverageKeywords: [],
                    accessoryCatalog: [],
                    volumeBias: "Moderate",
                    directWorkBias: "Direct emphasis"
                )
            ],
            topLeverageChange: "(not provided)",
            posturalFocus: "(none)",
            injuryRiskFocus: "(none)",
            calibration: service.neutralCalibrationProfile()
        )
    }

    /// The invariant, swept across every day count and every week of the mesocycle. Written as
    /// a sweep rather than a single deload case on purpose: the bug was one cell of this table,
    /// and a test that only checked that cell would not notice the next rest pattern to drift.
    func testBlueprintTrainingDayCountMatchesItsOwnDayPlans() {
        for requestedDays in 4...6 {
            for weekNumber in 1...4 {
                let blueprint = service.programBlueprint(
                    for: plan(weeklyTrainingDays: requestedDays),
                    weekNumber: weekNumber
                )
                let builtTrainingDays = blueprint.dayPlans.filter { !$0.isRestDay }.count

                XCTAssertEqual(
                    blueprint.dayPlans.count,
                    7,
                    "A week is always 7 days (requested \(requestedDays), week \(weekNumber))"
                )
                XCTAssertEqual(
                    blueprint.weeklyTrainingDays,
                    builtTrainingDays,
                    "Blueprint claims \(blueprint.weeklyTrainingDays) training days but built "
                        + "\(builtTrainingDays) (requested \(requestedDays), week \(weekNumber)). "
                        + "validateWeekResponse compares against this number and the mismatch is "
                        + "a locked-menu hard failure."
                )
            }
        }
    }

    /// The specific cell that was broken, named so the failure message says what happened
    /// rather than just which index of a sweep tripped.
    func testSixDayDeloadWeekDoesNotContradictItself() {
        let blueprint = service.programBlueprint(
            for: plan(weeklyTrainingDays: 6),
            weekNumber: MesocyclePhase.deloadWeek
        )
        let builtTrainingDays = blueprint.dayPlans.filter { !$0.isRestDay }.count

        XCTAssertEqual(
            builtTrainingDays,
            5,
            "Premise: the deload rest pattern for six days deliberately gives back a session"
        )
        XCTAssertEqual(
            blueprint.weeklyTrainingDays,
            5,
            "The blueprint must report the deload week it built, not the six days that were asked for"
        )
    }

    /// The extra deload rest day is a prescription, not a bug — this pins that the fix changed
    /// only what the blueprint SAYS, never what it programs.
    func testTheDeloadStillGivesBackASessionForASixDayLifter() {
        let normal = service.programBlueprint(for: plan(weeklyTrainingDays: 6), weekNumber: 1)
        let deload = service.programBlueprint(for: plan(weeklyTrainingDays: 6), weekNumber: MesocyclePhase.deloadWeek)

        XCTAssertEqual(normal.dayPlans.filter { !$0.isRestDay }.count, 6)
        XCTAssertEqual(deload.dayPlans.filter { !$0.isRestDay }.count, 5)
    }
}
