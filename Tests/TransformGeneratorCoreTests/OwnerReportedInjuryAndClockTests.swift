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
        sets: Int = 3
    ) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: name,
            sets: sets,
            reps: "10-12",
            tempo: "2-0-1-1",
            restSeconds: 90,
            notes: "",
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

    /// The trap inside the fallback above, pinned because I built it and then nearly shipped it.
    ///
    /// `shoulderFamilyPhrases` gives the "Shoulder" catch-all pattern the phrases "shoulder" and
    /// "delt". Those belong there — a movement whose pattern IS "Shoulder" should be reached by a
    /// report naming the shoulder — but they must NOT count as "the report named a movement",
    /// because `hasShoulderRisk` already requires the report to name the joint. Every report that
    /// reaches this code contains one of them. Left in the union, the specificity check would
    /// always say "specific", the general fallback would never fire, and the fail-open hole would
    /// still be open behind a fix that read as though it had closed it.
    func testNamingOnlyTheJointDoesNotCountAsNamingAMovement() {
        XCTAssertFalse(
            service.reportNamesAnyMovement(
                service.normalizedPriorityText("Left shoulder and delt pain, worse in the evening.")
            ),
            "Naming the joint is not naming a movement — this is what triggers the general fallback"
        )
        XCTAssertTrue(
            service.reportNamesAnyMovement(
                service.normalizedPriorityText("Left shoulder pain when I overhead press.")
            )
        )
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
                    // Injected through `calibrationProfile`'s parameter seam rather than left to
                    // read stored state. `RecoveryModulationTests` records why: `swift test
                    // --parallel` runs classes in separate processes sharing one defaults plist,
                    // so a test that reads stored recovery state can be flipped mid-run by a
                    // sibling that writes it. These assertions are differential, so a flip would
                    // not fail them — it would make them stop measuring, which is worse.
                    calibration: service.calibrationProfile(
                        from: blankAnalysis(),
                        recoveryDecision: RecoveryDecision(tier: .ready, audit: "injected for test")
                    ),
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
        // A guard rather than a change detector: this delta was the same before the change, and
        // is here so narrowing the penalty cannot quietly become removing it.
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
                plan: plan(sessionMinutes: 1, fatigueCap: 99)
            ),
            "A session clock must never refuse a movement again"
        )

        // Fatigue still refuses. A guard rather than a change detector — the fatigue check ran
        // first before this change too — and it is the half that must survive: the recovery budget
        // is the one that describes the lifter rather than his calendar.
        XCTAssertFalse(
            service.seededDayFitsItsBudgets(
                adding: candidate,
                to: menu,
                plan: plan(sessionMinutes: 600, fatigueCap: 1)
            ),
            "Day fatigue must still be able to refuse a movement"
        )
    }

    // MARK: - 3. Joint-stress and substitution rules stay off unflagged movements

    /// The rule that could still tell him to "drop a redundant pressing slot" on a day containing
    /// dips. It reads like a neutral load budget, but its shoulder charge is built from
    /// `metadata.shoulderRisk` — a hardcoded name list that gives a dip a 4 — so it was his
    /// complaint arriving through a rule that never read his complaint.
    func testShoulderLoadIsOnlyCountedForMovementsTheReportReaches() {
        let pressingDay = day([
            exercise("Dip (Assisted or Weighted)", "Triceps", sets: 5),
            exercise("Dip (Assisted or Weighted)", "Chest", sets: 5),
            exercise("Machine Chest Press", "Chest", sets: 5),
            exercise("Dumbbell Bench Press", "Chest", sets: 5)
        ])

        XCTAssertTrue(
            service.validateJointStressBudget(
                on: pressingDay,
                injuryRiskFocus: ownersReport
            ).allSatisfy { !$0.contains("shoulder joint stress") },
            "A report naming only overhead pressing must not accumulate shoulder load from dips"
        )
        XCTAssertEqual(
            service.sessionJointStress(for: pressingDay, injuryRiskFocus: ownersReport).shoulder,
            0,
            accuracy: 0.001,
            "Nothing on this day is a movement he flagged, so the shoulder budget must read zero"
        )

        // The rule is gated, not gutted: a day of the movement he DID name still accumulates.
        let overheadDay = day([
            exercise("Barbell Overhead Press", "Anterior Deltoids", sets: 5),
            exercise("Seated Dumbbell Shoulder Press", "Anterior Deltoids", sets: 5),
            exercise("Machine Shoulder Press", "Anterior Deltoids", sets: 5),
            exercise("Dumbbell Shoulder Press", "Anterior Deltoids", sets: 5)
        ])
        XCTAssertGreaterThan(
            service.sessionJointStress(for: overheadDay, injuryRiskFocus: ownersReport).shoulder,
            0,
            "Overhead pressing is what his report names, so it must still be counted"
        )

        // Joints he has said nothing about are untouched by this change — elbow load still
        // accumulates from curl and extension work regardless of any report.
        let armDay = day([
            exercise("EZ-Bar Curl", "Biceps", sets: 5),
            exercise("Rope Triceps Pressdown", "Triceps", sets: 5)
        ])
        XCTAssertGreaterThan(
            service.sessionJointStress(for: armDay, injuryRiskFocus: "No injuries reported.").elbow,
            0,
            "Only the shoulder charge is evidence-bound; the other three joints are unchanged"
        )
    }

    /// The same principle on the substitution path: swapping in a movement the name list dislikes
    /// is only a shoulder finding if his report reaches that movement.
    func testASubstitutionIsOnlyAShoulderFindingForAMovementHeFlagged() {
        func issues(replacing original: String, _ originalTarget: String,
                    with replacement: String, _ replacementTarget: String,
                    report: String) -> [String] {
            let from = exercise(original, originalTarget)
            let to = exercise(replacement, replacementTarget)
            return service.validateSubstituteQuality(
                original: from,
                replacement: to,
                originalMeta: service.exerciseMetadata(for: from),
                replacementMeta: service.exerciseMetadata(for: to),
                dayNumber: 2,
                injuryRiskFocus: report
            )
        }

        XCTAssertTrue(
            issues(
                replacing: "Machine Chest Press", "Chest",
                with: "Dip (Assisted or Weighted)", "Chest",
                report: ownersReport
            ).allSatisfy { !$0.contains("increases shoulder risk") },
            "He has not flagged dips, so swapping one in is not a shoulder finding"
        )
        XCTAssertTrue(
            issues(
                replacing: "Machine Chest Press", "Chest",
                with: "Barbell Overhead Press", "Anterior Deltoids",
                report: ownersReport
            ).contains { $0.contains("increases shoulder risk") },
            "He HAS flagged overhead pressing, so swapping one in still is"
        )
    }

    // MARK: - 4. A report that names no movement must not switch caution off

    /// The hole a third audit found, and the most dangerous shape this whole mechanism can take.
    ///
    /// `hasShoulderRisk`'s first arm matches pure diagnoses — "shoulder impingement", "rotator
    /// cuff", "labral", "ac joint", "internal rotation", "upper crossed", "shoulder health" —
    /// none of which contains a movement word. Narrowing caution to named movements therefore
    /// returned false for EVERY exercise in the catalogue on exactly those reports, switching off
    /// all five gated rules at once. A shoulder rule failing silently is the one direction that is
    /// not acceptable, and `InjuryTimeAndSessionBudgetTests` lists five such reports as ones that
    /// must register.
    ///
    /// The rule is specificity, not doing less: be specific when he was specific, general when he
    /// was not.
    func testADiagnosisThatNamesNoMovementKeepsCautionOnEverything() {
        let diagnosisOnly = [
            "Shoulder impingement noted on the left side.",
            "Internally rotated shoulders with upper crossed posture.",
            "Shoulder health is a priority this block.",
            "Left shoulder aches through the day."
        ]

        for report in diagnosisOnly {
            XCTAssertTrue(
                service.hasShoulderRisk(injuryRiskFocus: report),
                "Premise: this report must register as a shoulder problem at all — \(report)"
            )
            XCTAssertTrue(
                service.reportedShoulderPainImplicates(
                    exerciseName: "Dip (Assisted or Weighted)",
                    muscleTarget: "Triceps",
                    injuryRiskFocus: report
                ),
                "A report naming no movement must leave caution ON, not silently off — \(report)"
            )
            XCTAssertTrue(
                service.reportedShoulderPainImplicates(
                    exerciseName: "Seated Dumbbell Shoulder Press",
                    muscleTarget: "Anterior Deltoids",
                    injuryRiskFocus: report
                ),
                "\(report)"
            )
        }

        // And the narrowing still works the moment he names one. This is the pair that matters:
        // same joint, same severity, different specificity, different outcome for the dip.
        XCTAssertFalse(
            service.reportedShoulderPainImplicates(
                exerciseName: "Dip (Assisted or Weighted)",
                muscleTarget: "Triceps",
                injuryRiskFocus: ownersReport
            )
        )
    }

    /// Two audits found families missing from the table, both in the same direction — a real
    /// complaint reaching nothing. These are the ones a lifter is most likely to name.
    func testAReportReachesTheMovementFamiliesALifterWouldActuallyName() {
        let cases: [(report: String, exercise: String, target: String)] = [
            ("Shoulder pain on the landmine press.", "Landmine Press", "Anterior Deltoids"),
            ("Shoulder pain during face pulls.", "Cable Face Pull", "Rear Deltoids"),
            ("Shoulder pain on lateral raises.", "Cable Lateral Raise", "Lateral Deltoids"),
            ("Shoulder pain on incline pressing.", "Incline Barbell Press", "Upper Chest"),
            ("Shoulder pain when I bench press.", "Dumbbell Bench Press", "Chest"),
            ("Shoulder pain on pulldowns.", "Lat Pulldown", "Lats")
        ]

        for item in cases {
            XCTAssertTrue(
                service.reportedShoulderPainImplicates(
                    exerciseName: item.exercise,
                    muscleTarget: item.target,
                    injuryRiskFocus: item.report
                ),
                "\(item.report) must reach \(item.exercise)"
            )
        }

        // Each of those reports names ONE family, so the narrowing is real rather than everything
        // falling through to the general case.
        XCTAssertFalse(
            service.reportedShoulderPainImplicates(
                exerciseName: "Dip (Assisted or Weighted)",
                muscleTarget: "Triceps",
                injuryRiskFocus: "Shoulder pain on the landmine press."
            ),
            "A report naming the landmine press must not reach a dip"
        )
    }
}
