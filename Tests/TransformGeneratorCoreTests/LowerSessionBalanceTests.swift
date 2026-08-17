import Foundation
import XCTest
@testable import Transform

/// The live Week 1 that motivated this file: the deterministic menu builder produced a Legs day
/// of Trap Bar Deadlift / Bulgarian Split Squat / Nordic Curl / Barbell Hip Thrust / Single-Leg
/// Hip Thrust — five posterior-chain movements and no knee-dominant quad anchor. The validator
/// correctly flagged it, but the menu was already locked, so nothing downstream could act on the
/// finding: two paid AI candidates and a paid correction pass all scored 5 on the identical
/// issue and were all discarded.
@MainActor
final class LowerSessionBalanceTests: XCTestCase {

    private let service = ClaudeService.shared

    private func plan(
        style: String = "Legs",
        focusArea: String? = "Core/Abs",
        supportAreas: [String] = []
    ) -> ClaudeService.BlueprintDayPlan {
        ClaudeService.BlueprintDayPlan(
            dayIndex: 1,
            style: style,
            focusArea: focusArea,
            supportAreas: supportAreas,
            targetFatigueCap: 22,
            targetSessionMinutes: 70,
            targetPrioritySlots: 1,
            emphasisPatterns: [],
            isRestDay: false
        )
    }

    private func menu(_ entries: [(String, String)]) -> [ClaudeService.PreSelectedExercise] {
        entries.map { name, target in
            ClaudeService.PreSelectedExercise(
                exerciseName: name,
                muscleTarget: target,
                movementPattern: service.exerciseMetadata(
                    forExerciseName: name,
                    muscleTarget: target
                ).movementPattern,
                role: service.proceduralExerciseRole(for: name, muscleTarget: target),
                prescribedSets: 2
            )
        }
    }

    private let reportedDay: [(String, String)] = [
        ("Hanging Knee Raise", "Lower Abs"),
        ("Trap Bar Deadlift", "Posterior Chain"),
        ("Dumbbell Bulgarian Split Squat", "Quads/Glutes"),
        ("Nordic Hamstring Curl", "Hamstrings"),
        ("Barbell Hip Thrust", "Glutes"),
        ("Single-Leg Hip Thrust", "Glutes")
    ]

    // MARK: - The rule

    /// Establishes the premise the rest of this file rests on, through the real validator.
    func testTheReportedLegsDayIsFlaggedForHavingNoKneeDominantAnchor() {
        let issues = service.lowerSessionBalanceIssues(
            in: menu(reportedDay),
            dayOffset: 1,
            plan: plan()
        )

        XCTAssertTrue(
            issues.contains { $0.contains("reads as a broad lower-body session") },
            "The reported Legs day no longer reproduces the finding: \(issues)"
        )
    }

    /// The projection the menu-level repair drives itself from must agree with what the
    /// validator says about the same day. If these two ever disagree the repair would be
    /// chasing a finding the validator does not actually raise, or missing one it does.
    func testTheMenuProjectionMatchesTheValidatorOnTheSameDay() {
        let exercises = reportedDay.map { name, target in
            WorkoutExerciseResponse(
                exerciseName: name,
                sets: 2,
                reps: "8-12",
                tempo: "",
                restSeconds: 105,
                notes: "",
                muscleTarget: target
            )
        }
        let day = WorkoutDayResponse(
            dayNumber: 2,
            dayName: "Legs",
            muscleGroups: "",
            isRestDay: false,
            notes: "",
            exercises: exercises
        )

        XCTAssertEqual(
            service.lowerSessionBalanceIssues(in: menu(reportedDay), dayOffset: 1, plan: plan()),
            service.validateLowerSessionBalance(on: day, expectedStyle: "Lower", focusArea: "Core/Abs")
        )
    }

    /// Swapping the redundant second hip thrust for a knee-dominant movement is the repair the
    /// menu-level pass performs. It must actually clear the finding — otherwise the pass would
    /// churn the menu without buying anything.
    func testTradingTheRedundantHipThrustForAKneeDominantSlotClearsTheFinding() {
        var repaired = reportedDay
        repaired[5] = ("Machine Leg Extension", "Quads")

        let issues = service.lowerSessionBalanceIssues(
            in: menu(repaired),
            dayOffset: 1,
            plan: plan()
        )

        XCTAssertEqual(issues, [], "A knee-dominant anchor did not settle the day: \(issues)")
    }

    /// The pass is scoped to broad lower-body days. A day the analysis deliberately biased
    /// toward the posterior chain is not a defect and must not be "repaired".
    func testAnExplicitlyPosteriorFocusedDayIsNotFlagged() {
        XCTAssertEqual(
            service.lowerSessionBalanceIssues(
                in: menu(reportedDay),
                dayOffset: 1,
                plan: plan(focusArea: "Glutes")
            ),
            []
        )
    }

    /// Both the validator and the repair must read "knee-dominant anchor" from the same list.
    /// A drift between them, on a locked menu, is an unfixable finding.
    func testTheAnchorPatternsAreTheOnesTheValidatorCountsOn() {
        XCTAssertEqual(service.kneeDominantAnchorPatterns, ["Squat", "Press", "Extension"])
    }

    // MARK: - Disposition

    /// The money finding. Exercise selection is locked by the time this issue is raised, so as a
    /// correction-worthy issue it burns a correction pass and then discards every paid candidate
    /// for a defect none of them were allowed to fix.
    func testTheLowerBalanceFindingIsAWarningWhenTheMenuIsLocked() {
        let issue = "Day 2 reads as a broad lower-body session, but it leans too heavily on "
            + "glute/posterior-chain patterns without a clear knee-dominant quad anchor. "
            + "Add or swap in a clearer squat/press/extension slot."

        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .acceptableWarning)
        XCTAssertTrue(service.shouldAcceptAIOutput(despite: [issue], menuLocked: true))
    }

    /// When the menu is NOT locked the AI can genuinely fix this by choosing a different
    /// movement, so it stays worth a correction pass. The demotion must not leak into that path.
    func testTheSameFindingStillEarnsACorrectionPassWhenSelectionIsFree() {
        let issue = "Day 2 reads as a broad lower-body session, but it leans too heavily on "
            + "glute/posterior-chain patterns without a clear knee-dominant quad anchor. "
            + "Add or swap in a clearer squat/press/extension slot."

        XCTAssertEqual(service.validationDisposition(for: issue), .correctionPass)
    }

    /// A demoted finding reaches the user's banner, so it needs real copy rather than the
    /// unclassified fallback.
    func testTheDemotedFindingHasPlainLanguageCopy() {
        let issue = "Day 2 reads as a broad lower-body session, but it leans too heavily on "
            + "glute/posterior-chain patterns without a clear knee-dominant quad anchor."

        let notices = WorkoutValidatorNotice.notices(from: [issue])

        XCTAssertEqual(notices.count, 1)
        XCTAssertFalse(notices.first?.headline.isEmpty ?? true)
        XCTAssertTrue(
            notices.first?.headline.contains("planned emphasis") ?? false,
            "Demoted finding fell through to the unclassified copy: \(notices)"
        )
    }

    // MARK: - Warm-up ramp target

    /// A day whose focus is Core/Abs legitimately opens with the core movement, and the warm-up
    /// used to tell the lifter to take "2-3 progressive ramp sets into Hanging Knee Raise" — a
    /// bodyweight movement with nothing to ramp.
    func testTheWarmupRampsIntoTheFirstLoadedLiftNotTheOpener() {
        let exercises = reportedDay.map { name, target in
            WorkoutExerciseResponse(
                exerciseName: name,
                sets: 2,
                reps: "8-12",
                tempo: "",
                restSeconds: 105,
                notes: "",
                muscleTarget: target
            )
        }

        XCTAssertEqual(service.rampSetTarget(in: exercises), "Trap Bar Deadlift")

        let cue = service.enrichedWarmupCue(style: "Legs", exercises: exercises, blueprint: nil)
        XCTAssertTrue(cue.contains("ramp sets into Trap Bar Deadlift"), cue)
        XCTAssertFalse(cue.contains("ramp sets into Hanging Knee Raise"), cue)
    }

    /// A session carrying only accessory and core work has nothing to ramp into, and the caller
    /// keeps its own wording rather than being handed a misleading name.
    func testASessionWithNothingToRampReturnsNoTarget() {
        let exercises = [("Cable Crunch", "Abs"), ("Cable Lateral Raise", "Lateral Deltoids")]
            .map { name, target in
                WorkoutExerciseResponse(
                    exerciseName: name,
                    sets: 2,
                    reps: "12-15",
                    tempo: "",
                    restSeconds: 60,
                    notes: "",
                    muscleTarget: target
                )
            }

        XCTAssertNil(service.rampSetTarget(in: exercises))
    }
}
