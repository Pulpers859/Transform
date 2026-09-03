import Foundation
import XCTest
@testable import Transform

/// Three defects found by auditing a real Week 1 bundle whose validator reported exactly one
/// finding ("Triceps falls below the maintenance weekly volume floor"). All three were owned by
/// the deterministic planner, and the single finding the owner actually saw was the downstream
/// symptom of the first two rather than a problem in its own right.
///
///  1. `styleFeasibleAllocations` compared CANONICAL day styles against RAW preferred styles, so
///     "Legs" never matched a "Lower" day. Core/Abs was clamped from 2 exposures to 1 and recut
///     from 6 direct sets to 5 — which is why Day 5's Cable Crunch shipped at ONE set, below the
///     `.core` two-set floor, with no budget left to lift it.
///  2. `enforceHorizontalPullCoverage`'s trade path never checked
///     `maintenanceSlotBudgetsAreFeasible`, so seating a row could push the back group to four
///     distinct movements. That predicate is whole-week and all-groups, so the breach disabled
///     `enforceMaintenanceExposureBreadth` for EVERY muscle — which is what left Triceps on one
///     slot and 2 weekly sets.
///  3. `validateBackPatternBalance` tested only for the PRESENCE of a row, so a week with six
///     overhead-pulling sets and one 2-set row read clean.
@MainActor
final class BackBalanceAndStyleCanonicalTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Fixtures

    private struct Fixture: Decodable {
        let analysis: BodyAnalysisResult
    }

    private func fixtureBlueprint(weekNumber: Int = 1) throws -> ClaudeService.ProgramBlueprint {
        guard let url = Bundle.module.url(forResource: "five-maintenance-errors", withExtension: "json") else {
            XCTFail("Bundled generator regression fixture is missing")
            throw CocoaError(.fileNoSuchFile)
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let intent = service.trainingIntentPlan(from: fixture.analysis)
        return service.programBlueprint(for: intent, weekNumber: weekNumber)
    }

    private func fixtureIntent() throws -> ClaudeService.TrainingIntentPlan {
        guard let url = Bundle.module.url(forResource: "five-maintenance-errors", withExtension: "json") else {
            XCTFail("Bundled generator regression fixture is missing")
            throw CocoaError(.fileNoSuchFile)
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        return service.trainingIntentPlan(from: fixture.analysis)
    }

    private func exercise(_ name: String, _ target: String, sets: Int) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: name,
            sets: sets,
            reps: "10-12",
            tempo: "2-0-1-1",
            restSeconds: 90,
            notes: "Cue.",
            muscleTarget: target
        )
    }

    /// One training day carrying every exercise, which is all `validateBackPatternBalance` needs —
    /// it flattens the week before counting.
    private func week(_ exercises: [WorkoutExerciseResponse]) -> [WorkoutDayResponse] {
        (1...7).map { dayNumber in
            WorkoutDayResponse(
                dayNumber: dayNumber,
                dayName: dayNumber == 1 ? "Training" : "Rest",
                muscleGroups: "",
                isRestDay: dayNumber != 1,
                notes: "",
                exercises: dayNumber == 1 ? exercises : []
            )
        }
    }

    private func slot(_ name: String, _ target: String) -> ClaudeService.PreSelectedExercise {
        ClaudeService.PreSelectedExercise(
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

    private func allocation(
        area: String,
        targetFrequency: Int,
        directSetTarget: Double,
        weightedStimulusTarget: Double,
        preferredStyles: [String]
    ) -> ClaudeService.BlueprintPriorityAllocation {
        ClaudeService.BlueprintPriorityAllocation(
            area: area,
            priorityLevel: "Medium",
            rationale: "",
            targetFrequency: targetFrequency,
            targetExerciseSlots: 2,
            directSetTarget: directSetTarget,
            weightedStimulusTarget: weightedStimulusTarget,
            maxPerSessionDirectSets: 3,
            maxFocusSessionDirectSets: 5,
            preferredStyles: preferredStyles,
            preferredMovementPatterns: [],
            volumeBias: "Moderate",
            directWorkBias: "Maintenance"
        )
    }

    private func dayPlan(_ index: Int, style: String, isRestDay: Bool = false) -> ClaudeService.BlueprintDayPlan {
        ClaudeService.BlueprintDayPlan(
            dayIndex: index,
            style: style,
            focusArea: nil,
            supportAreas: [],
            targetFatigueCap: 20,
            targetSessionMinutes: 70,
            targetPrioritySlots: 1,
            emphasisPatterns: [],
            isRestDay: isRestDay
        )
    }

    // MARK: - 1. "Legs" and "Lower" are one style on BOTH sides of the comparison

    /// The defect verbatim. `canonicalTrainingStyle` folds "Legs" into "Lower", and the day-plan
    /// side was folded while the allocation's `preferredStyles` was not — so an allocation whose
    /// styles read `["Upper", "Legs"]` (the literal spelling `sanitizedPreferredStyles` keeps when
    /// it falls back to the Core/Abs catalogue list `["Legs", "Lower", "Upper"]`) saw ZERO of the
    /// week's lower-body days.
    func testAlLegsPreferredStyleMatchesALowerDay() {
        let plans = [
            dayPlan(0, style: "Upper"),
            dayPlan(1, style: "Legs"),
            dayPlan(2, style: "Rest", isRestDay: true),
            dayPlan(3, style: "Push"),
            dayPlan(4, style: "Lower"),
            dayPlan(5, style: "Pull"),
            dayPlan(6, style: "Rest", isRestDay: true)
        ]
        // Three compatible days (Upper, Legs->Lower, Lower) against a target frequency of 2, so
        // the clamp must not fire at all and the allocation must come back untouched.
        let core = allocation(
            area: "Core/Abs",
            targetFrequency: 2,
            directSetTarget: 6,
            weightedStimulusTarget: 8.5,
            preferredStyles: ["Upper", "Legs"]
        )

        let result = service.styleFeasibleAllocations([core], dayPlans: plans)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(
            result[0].targetFrequency,
            2,
            "Legs and Lower are the same canonical style; three compatible days must not clamp to one"
        )
        XCTAssertEqual(
            result[0].directSetTarget,
            6,
            accuracy: 0.001,
            "An unclamped allocation must keep its direct-set target — this is the 6->5 cut that stranded Day 5's crunch at one set"
        )
        XCTAssertEqual(result[0].weightedStimulusTarget, 8.5, accuracy: 0.001)
    }

    /// The clamp must still fire when a priority genuinely has fewer compatible days than its
    /// target frequency — the fix widens the match, it does not disable the rule.
    func testAGenuinelyInfeasibleFrequencyIsStillClamped() {
        let plans = [
            dayPlan(0, style: "Upper"),
            dayPlan(1, style: "Lower"),
            dayPlan(2, style: "Lower"),
            dayPlan(3, style: "Rest", isRestDay: true)
        ]
        let arms = allocation(
            area: "Triceps",
            targetFrequency: 3,
            directSetTarget: 9,
            weightedStimulusTarget: 10,
            preferredStyles: ["Arms"]
        )
        let upperOnly = allocation(
            area: "Upper Chest",
            targetFrequency: 3,
            directSetTarget: 9,
            weightedStimulusTarget: 10,
            preferredStyles: ["Upper"]
        )

        let result = service.styleFeasibleAllocations([arms, upperOnly], dayPlans: plans)

        // Zero compatible days is "the style list is unusable", not "stop training" — left alone.
        XCTAssertEqual(result[0].targetFrequency, 3, "Zero compatible days must leave the allocation untouched")
        // One compatible day against a target of three IS a real infeasibility.
        XCTAssertEqual(result[1].targetFrequency, 1)
        XCTAssertLessThan(result[1].directSetTarget, 9)
    }

    // MARK: - 2. The row trade must not overspend the back's movement budget

    /// `maintenanceSlotBudgetsAreFeasible` is whole-week and all-groups: once ANY group is over
    /// its distinct-movement cap, `menuPlanningBudgetAllows` returns false for every candidate on
    /// every day, and every later additive pass — `enforceMaintenanceExposureBreadth` included —
    /// silently becomes a no-op. So a trade that buys a row by pushing back from three movements
    /// to four costs the breadth of every other muscle in the week.
    func testTheRowTradeLeavesEveryMaintenanceLedgerFeasible() throws {
        let blueprint = try fixtureBlueprint()
        let intent = try fixtureIntent()

        // Back sits at exactly three distinct VERTICAL pulls — the cap a recovery-tight ceiling
        // of 8 can dose at three sets apiece — so appending a fourth back movement is impossible
        // and the trade path is the only way a row can be seated.
        var menus: [[ClaudeService.PreSelectedExercise]] = blueprint.dayPlans.map { plan in
            plan.isRestDay ? [] : [slot("Machine Chest Press", "Chest")]
        }
        guard let upperDay = blueprint.dayPlans.firstIndex(where: {
            !$0.isRestDay && service.canonicalTrainingStyle($0.style) == "Upper"
        }) ?? blueprint.dayPlans.firstIndex(where: {
            !$0.isRestDay && service.canonicalTrainingStyle($0.style) == "Pull"
        }) else {
            throw XCTSkip("This fixture's split has no Upper or Pull day to seat back work on")
        }
        menus[upperDay] = [
            slot("Lat Pulldown", "Lats"),
            slot("Neutral-Grip Lat Pulldown", "Lats"),
            slot("Pull-Up (Weighted or Assisted)", "Lats"),
            slot("Cable Crunch", "Abs")
        ]

        XCTAssertFalse(
            service.menusContainMovementPattern(
                service.horizontalPullPatterns,
                trainingGroupSeed: "back",
                in: menus
            ),
            "Fixture precondition: the constructed week must start with no rowing"
        )

        let repaired = service.enforceHorizontalPullCoverage(
            menus,
            blueprint: blueprint,
            trainingIntent: intent,
            weekNumber: 1,
            avoidedExercises: []
        )

        XCTAssertTrue(
            service.menusContainMovementPattern(
                service.horizontalPullPatterns,
                trainingGroupSeed: "back",
                in: repaired
            ),
            "The pass must still seat a row — that is the defect it exists to fix"
        )
        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: repaired,
                selectedToday: [],
                blueprint: blueprint
            ),
            """
            The row was seated by overspending a maintenance ledger. That breach makes \
            menuPlanningBudgetAllows return false for every candidate on every day, which \
            silently disables enforceMaintenanceExposureBreadth for the whole week.
            """
        )
    }

    // MARK: - 3. Presence is not balance

    /// The owner's real Week 1: six overhead-pulling sets against one 2-set Chest-Supported Row,
    /// with the actual Pull day carrying no row at all. The old rule returned clean.
    func testASingleTokenRowDoesNotSatisfyTheBalanceRule() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Neutral-Grip Lat Pulldown", "Lats", sets: 2),
            exercise("Pull-Up (Weighted or Assisted)", "Lats", sets: 2),
            exercise("Lat Pulldown", "Lats", sets: 2),
            exercise("Chest-Supported Row", "Upper Back", sets: 2)
        ]))

        XCTAssertEqual(issues.count, 1, "\(issues)")
        XCTAssertTrue(issues[0].contains("overhead-pulling sets against only"), issues[0])
        XCTAssertTrue(issues[0].contains("6 overhead-pulling sets"), issues[0])
        XCTAssertTrue(issues[0].contains("only 2 rowing"), issues[0])
    }

    /// The ratio line is 2:1, not "any imbalance". Six vertical against three rowing is a
    /// vertical-leaning week, not a token one, and must stay quiet.
    func testAVerticalLeaningButBalancedWeekIsNotFlagged() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Lat Pulldown", "Lats", sets: 3),
            exercise("Pull-Up (Weighted or Assisted)", "Lats", sets: 3),
            exercise("Chest-Supported Row", "Upper Back", sets: 3)
        ]))

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    /// The `verticalSets >= 4` floor. A small back week has nothing to balance, and firing there
    /// would make the rule noise rather than signal.
    func testASmallBackWeekIsNotFlagged() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Lat Pulldown", "Lats", sets: 3),
            exercise("Chest-Supported Row", "Upper Back", sets: 1)
        ]))

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    /// Deliberately asymmetric: rows load the lats through a full range, so a row-dominant week
    /// is not told off for lacking a pulldown.
    func testARowDominantWeekIsNotFlagged() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Chest-Supported Row", "Upper Back", sets: 4),
            exercise("Seated Cable Row", "Mid Back", sets: 4),
            exercise("Lat Pulldown", "Lats", sets: 2)
        ]))

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    // MARK: - Disposition and owner-facing copy

    /// Both paths must agree. An unclassified finding is an acceptable warning under menu-lock and
    /// a HARD FAILURE unlocked, so leaving this one to fall through would discard a paid week on
    /// the procedural path over a slot the planner had already tried and failed to place.
    func testTheBalanceFindingIsAnAcceptableWarningOnBothPaths() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Neutral-Grip Lat Pulldown", "Lats", sets: 2),
            exercise("Pull-Up (Weighted or Assisted)", "Lats", sets: 2),
            exercise("Lat Pulldown", "Lats", sets: 2),
            exercise("Chest-Supported Row", "Upper Back", sets: 2)
        ]))

        guard let finding = issues.first else {
            XCTFail("The imbalanced fixture must produce a finding to classify")
            return
        }

        XCTAssertEqual(service.validationDisposition(for: finding, menuLocked: true), .acceptableWarning)
        XCTAssertEqual(service.validationDisposition(for: finding, menuLocked: false), .acceptableWarning)
    }

    /// The maintenance FLOOR had no owner-facing translation while its ceiling twin did, so the
    /// single finding of the owner's real Week 1 rendered as "A plan check didn't pass … isn't
    /// recognized well enough to explain here."
    func testEveryBackAndMaintenanceFindingHasPlainLanguageCopy() {
        let findings = [
            "Non-priority muscle group 'Triceps' falls below the maintenance weekly volume floor (2 sets vs 3). MAINT-001 puts maintenance near 6-10 quality sets per week.",
            "The week trains the back with no horizontal pull at all — every back movement pulls down from overhead.",
            "The week's back work is 6 overhead-pulling sets against only 2 rowing set(s) — more than twice as much vertical as horizontal."
        ]

        for finding in findings {
            let notice = WorkoutValidatorNotice.notices(from: [finding])
            XCTAssertEqual(notice.count, 1)
            XCTAssertNotEqual(
                notice[0].headline,
                "A plan check didn't pass",
                "This finding falls through to the unclassified notice: \(finding)"
            )
            XCTAssertEqual(
                notice[0].severity,
                .attention,
                "A coverage hole is not a tuning note: \(finding)"
            )
        }
    }
}
