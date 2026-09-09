import Foundation
import XCTest
@testable import Transform

/// Two owner decisions, made after reading his own generated week, pinned so nothing drifts back.
///
/// 1. SHOULDER CAUTION IS EVIDENCE-BOUND. "dips don't bother it. Don't attack exercises that I
///    don't mark or talk about hurting." One sentence about shoulder pain used to switch on a
///    blanket penalty driven by a hardcoded keyword list, and a separate validator rule flagged
///    shoulder-intensive pressing on an Arms day without reading the analysis at all. Between them
///    a Dip lost 34 points of selection score and drew a finding, for a lifter whose report names
///    only overhead pressing. Caution now applies per movement, and only where his own words
///    reach it.
///
/// 2. THE SESSION CLOCK NO LONGER CUTS TRAINING. "the 'clock' limit isn't because the workouts are
///    too long. It is because I don't schedule my time effectively for working out." Four gates
///    used the time estimate to refuse a set, refuse a movement, trim sets, or delete a movement
///    outright, and a fifth turned it into a correction-worthy finding that spent real money on a
///    repair call. Day FATIGUE is the budget now — the one that describes his body.
@MainActor
final class OwnerReportedInjuryAndClockTests: XCTestCase {

    private let service = ClaudeService.shared

    /// The owner's actual analysis text, verbatim from the 2026-09-08 Week 1 bundle.
    private let ownersReport = """
    Left anterior shoulder pain during neutral-grip overhead pressing is the key flag: this \
    pattern warrants modifying pressing angle, reducing overhead range temporarily, and \
    monitoring rather than pushing through.
    """

    /// Copied from `InjuryTimeAndSessionBudgetTests`, which constructs the same type. Written out
    /// rather than recalled: this initialiser has 19 labels and typing one from memory is how two
    /// earlier tests in this repo broke the build.
    private func blankAnalysis() -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: "", trainingAssessment: "", nutritionAssessment: "",
            recoveryRiskAssessment: "", adherenceAssessment: "", analysisLimitations: "",
            inputContext: nil, regionBreakdown: [], topLeverageChange: "",
            priorityMuscles: [], workoutRecommendations: [], dietRecommendations: [],
            posturalNotes: "", estimatedBodyFat: "", metabolicHealthNotes: "",
            psychologicalInsights: "", injuryRiskNotes: "", macroTargets: nil,
            structuredTrainingIntent: nil
        )
    }

    private func exercise(
        _ name: String,
        _ target: String,
        sets: Int = 3,
        notes: String = ""
    ) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: name,
            sets: sets,
            reps: "10-12",
            tempo: "2-0-1-1",
            restSeconds: 90,
            notes: notes,
            muscleTarget: target
        )
    }

    private func day(_ exercises: [WorkoutExerciseResponse]) -> WorkoutDayResponse {
        WorkoutDayResponse(
            dayNumber: 5,
            dayName: "Arms",
            muscleGroups: "Arms",
            isRestDay: false,
            notes: "",
            exercises: exercises
        )
    }

    // MARK: - 1. Caution reaches only what the lifter reported

    /// The whole decision in one predicate. His report names overhead pressing and nothing else,
    /// so an overhead press is implicated and a dip is not.
    func testOnlyMovementsTheReportNamesAreImplicated() {
        XCTAssertTrue(
            service.reportedShoulderPainImplicates(
                exerciseName: "Seated Dumbbell Shoulder Press",
                muscleTarget: "Anterior Deltoids",
                injuryRiskFocus: ownersReport
            ),
            "The report names overhead pressing, so a vertical press must stay implicated"
        )
        XCTAssertFalse(
            service.reportedShoulderPainImplicates(
                exerciseName: "Dip (Assisted or Weighted)",
                muscleTarget: "Triceps",
                injuryRiskFocus: ownersReport
            ),
            "The report never mentions dips; nothing may penalise one on his behalf"
        )
        XCTAssertFalse(
            service.reportedShoulderPainImplicates(
                exerciseName: "Cable Lateral Raise",
                muscleTarget: "Lateral Deltoids",
                injuryRiskFocus: ownersReport
            )
        )

        // Naming a movement directly still reaches it — the rule is about evidence, not about
        // exempting dips specifically.
        XCTAssertTrue(
            service.reportedShoulderPainImplicates(
                exerciseName: "Dip (Assisted or Weighted)",
                muscleTarget: "Triceps",
                injuryRiskFocus: "Anterior shoulder pain on dips."
            )
        )

        // Every shoulder-relevant movement pattern in the catalogue must be reachable by name or
        // by family, or a real complaint lands on a movement nothing will act on. Incline pressing
        // is the one that matters most here: it is the owner's top priority's whole pattern.
        XCTAssertTrue(
            service.reportedShoulderPainImplicates(
                exerciseName: "Incline Barbell Press",
                muscleTarget: "Upper Chest",
                injuryRiskFocus: "Anterior shoulder pain on incline pressing."
            ),
            "A report naming incline pressing must reach an incline press"
        )
        XCTAssertFalse(
            service.reportedShoulderPainImplicates(
                exerciseName: "Incline Barbell Press",
                muscleTarget: "Upper Chest",
                injuryRiskFocus: ownersReport
            ),
            "His report names overhead pressing only, so incline pressing stays untouched"
        )

        // A blank name must not become a wildcard. `containsAny` is a substring test and
        // `"anything".contains("")` is true, so an unfiltered empty keyword would implicate every
        // movement against every report.
        XCTAssertFalse(
            service.reportedShoulderPainImplicates(
                exerciseName: "",
                muscleTarget: "",
                injuryRiskFocus: ownersReport
            ),
            "An empty exercise name must never match a report"
        )

        // No reported shoulder problem at all means nothing is implicated.
        XCTAssertFalse(
            service.reportedShoulderPainImplicates(
                exerciseName: "Seated Dumbbell Shoulder Press",
                muscleTarget: "Anterior Deltoids",
                injuryRiskFocus: "Left knee pain during deep squatting."
            )
        )
    }

    /// The finding the owner actually received on Day 5 of his week, and must not receive again.
    func testAnArmsDayDipIsNotFlaggedForAShoulderHeNeverTiedToIt() {
        let issues = service.validateArmsDayShoulderStress(
            on: day([
                exercise("Machine Lateral Raise", "Lateral Deltoids", sets: 2),
                exercise("Dip (Assisted or Weighted)", "Triceps", sets: 2)
            ]),
            expectedStyle: "Arms",
            focusArea: "Lateral Deltoids",
            injuryRiskFocus: ownersReport
        )

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    /// The rule is gated, not gutted. A movement his report DOES reach is still flagged on the
    /// same day, with the same wording.
    func testAnArmsDayOverheadPressIsStillFlagged() {
        let issues = service.validateArmsDayShoulderStress(
            on: day([
                exercise("Machine Lateral Raise", "Lateral Deltoids", sets: 2),
                exercise("Seated Dumbbell Shoulder Press", "Anterior Deltoids", sets: 2)
            ]),
            expectedStyle: "Arms",
            focusArea: "Lateral Deltoids",
            injuryRiskFocus: ownersReport
        )

        XCTAssertEqual(issues.count, 1, "\(issues)")
        XCTAssertTrue(issues[0].contains("Seated Dumbbell Shoulder Press"), issues[0])
    }

    /// Selection scoring, the half that was doing the quiet damage. A dip must score the same
    /// whether or not the analysis mentions a shoulder; an overhead press must not.
    func testShoulderCautionDoesNotMoveAnUnreportedMovementDownTheCatalogue() {
        func score(_ name: String, _ target: String, report: String) -> Int {
            service.exerciseSelectionScore(
                exerciseName: name,
                muscleTarget: target,
                focusIntent: nil,
                selectionContext: ClaudeService.ExerciseSelectionContext(
                    calibration: service.calibrationProfile(from: blankAnalysis()),
                    injuryRiskFocus: report,
                    style: "Arms"
                )
            )
        }

        let quiet = "No injuries reported."
        XCTAssertEqual(
            score("Dip (Assisted or Weighted)", "Triceps", report: ownersReport),
            score("Dip (Assisted or Weighted)", "Triceps", report: quiet),
            "A shoulder report that never mentions dips must not change how a dip is ranked"
        )
        XCTAssertLessThan(
            score("Seated Dumbbell Shoulder Press", "Anterior Deltoids", report: ownersReport),
            score("Seated Dumbbell Shoulder Press", "Anterior Deltoids", report: quiet),
            "A movement the report DOES name must still be ranked down"
        )
    }

    // MARK: - 2. The clock does not refuse work

    /// `seededDayFitsItsBudgets` is the gate that decides whether a session can take another
    /// movement. It used to refuse on projected minutes; now only day fatigue can refuse.
    func testADayWithNoClockLeftStillAcceptsAMovement() {
        let menu = ["Back Squat", "Barbell Romanian Deadlift", "Leg Press"].map { name -> ClaudeService.PreSelectedExercise in
            let target = name == "Barbell Romanian Deadlift" ? "Hamstrings" : "Quads"
            return ClaudeService.PreSelectedExercise(
                exerciseName: name,
                muscleTarget: target,
                movementPattern: service.exerciseMetadata(
                    forExerciseName: name,
                    muscleTarget: target
                ).movementPattern,
                role: service.proceduralExerciseRole(for: name, muscleTarget: target),
                prescribedSets: 1
            )
        }
        let candidate = (name: "Barbell Hip Thrust", target: "Glutes")

        func plan(sessionMinutes: Int, fatigueCap: Int) -> ClaudeService.BlueprintDayPlan {
            ClaudeService.BlueprintDayPlan(
                dayIndex: 3,
                style: "Lower",
                focusArea: nil,
                supportAreas: [],
                targetFatigueCap: fatigueCap,
                targetSessionMinutes: sessionMinutes,
                targetPrioritySlots: 1,
                emphasisPatterns: [],
                isRestDay: false
            )
        }

        // A budget of one minute cannot possibly hold four lower-body movements. It no longer
        // matters: the clock is not a gate.
        XCTAssertTrue(
            service.seededDayFitsItsBudgets(
                adding: candidate,
                to: menu,
                plan: plan(sessionMinutes: 1, fatigueCap: 99),
                weekNumber: 1
            ),
            "A session clock must never refuse a movement again"
        )

        // Fatigue still refuses, and that is the point — the recovery budget is the one that
        // describes the lifter rather than his calendar.
        XCTAssertFalse(
            service.seededDayFitsItsBudgets(
                adding: candidate,
                to: menu,
                plan: plan(sessionMinutes: 600, fatigueCap: 1),
                weekNumber: 1
            ),
            "Day fatigue must still be able to refuse a movement"
        )
    }

    /// The estimate itself survives as a measurement and must keep working — it is only its use
    /// as a limit that was removed. A longer day still costs more projected minutes.
    func testTheSessionEstimateStillMeasuresEvenThoughNothingEnforcesIt() {
        let short = day([exercise("Back Squat", "Quads", sets: 3)])
        let long = day([
            exercise("Back Squat", "Quads", sets: 5),
            exercise("Barbell Romanian Deadlift", "Hamstrings", sets: 5),
            exercise("Leg Press", "Quads", sets: 5)
        ])

        XCTAssertGreaterThan(
            service.estimatedSessionMinutes(for: long),
            service.estimatedSessionMinutes(for: short)
        )
    }
}
