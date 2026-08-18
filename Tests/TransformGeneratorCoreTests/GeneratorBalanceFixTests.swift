import Foundation
import XCTest
@testable import Transform

/// Five planner defects found by auditing a real Week 1 bundle whose validator reported
/// "Validator Issues: None." Every one of them was invisible to the validator, and every one was
/// owned by the deterministic planner rather than the AI — the menu is locked before the model
/// sees it, so nothing downstream could have repaired any of them.
///
///  1. `ORD-001` was applied focus-first, so a Legs day carrying the week's Core/Abs focus put
///     `Hanging Knee Raise` in slot 1 and `Trap Bar Deadlift` in slot 2.
///  2. `BASE-001`'s single "back" bucket let a five-day week ship eight back sets with no row.
///  3. The two-per-pattern cap counted `Lat Pulldown` and `Neutral-Grip Lat Pulldown` as two
///     exercises.
///  4. A priority's `targetFrequency` was never reconciled with the number of style-compatible
///     days the chosen split actually contains.
///  5. `MAINT-001` enforced only the ceiling, so Triceps shipped on 2 weekly sets beside Calves
///     on 6.
@MainActor
final class GeneratorBalanceFixTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Fixture pipeline

    private struct Fixture: Decodable {
        let analysis: BodyAnalysisResult
    }

    /// The real planning pipeline on the audited priority shape (Upper Chest / Lateral Deltoids /
    /// Core-Abs), so these assertions describe a week the generator can actually produce rather
    /// than a hand-built one that flatters the rules.
    private func plannedWeek() throws -> (
        blueprint: ClaudeService.ProgramBlueprint,
        menus: [[ClaudeService.PreSelectedExercise]]
    ) {
        guard let url = Bundle.module.url(forResource: "five-maintenance-errors", withExtension: "json") else {
            XCTFail("Bundled generator regression fixture is missing")
            throw CocoaError(.fileNoSuchFile)
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let intent = service.trainingIntentPlan(from: fixture.analysis)
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        let menus = service.preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: intent,
            weekNumber: 1,
            previousWeekDays: nil
        )
        return (blueprint, menus)
    }

    private func role(_ exercise: ClaudeService.PreSelectedExercise) -> ClaudeService.ProceduralExerciseRole {
        service.proceduralExerciseRole(
            for: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget
        )
    }

    private func dayPlan(
        _ index: Int,
        style: String,
        focusArea: String? = nil,
        isRestDay: Bool = false
    ) -> ClaudeService.BlueprintDayPlan {
        ClaudeService.BlueprintDayPlan(
            dayIndex: index,
            style: style,
            focusArea: focusArea,
            supportAreas: [],
            targetFatigueCap: 20,
            targetSessionMinutes: 70,
            targetPrioritySlots: 1,
            emphasisPatterns: [],
            isRestDay: isRestDay
        )
    }

    private func allocation(
        area: String,
        targetFrequency: Int,
        directSetTarget: Double = 10,
        maxPerSessionDirectSets: Double = 4,
        maxFocusSessionDirectSets: Double = 8,
        preferredStyles: [String]
    ) -> ClaudeService.BlueprintPriorityAllocation {
        ClaudeService.BlueprintPriorityAllocation(
            area: area,
            priorityLevel: "High",
            rationale: "",
            targetFrequency: targetFrequency,
            targetExerciseSlots: 3,
            directSetTarget: directSetTarget,
            weightedStimulusTarget: directSetTarget + 1,
            maxPerSessionDirectSets: maxPerSessionDirectSets,
            maxFocusSessionDirectSets: maxFocusSessionDirectSets,
            preferredStyles: preferredStyles,
            preferredMovementPatterns: [],
            volumeBias: "High",
            directWorkBias: "Direct emphasis"
        )
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

    // MARK: - 1. ORD-001: anchors lead, core trails

    /// The defect verbatim: a heavy compound must never be preceded by direct core work.
    func testCoreNeverPrecedesAnAnchorInAPlannedWeek() throws {
        let (blueprint, menus) = try plannedWeek()

        for (dayIndex, day) in menus.enumerated() where !day.isEmpty {
            guard dayIndex < blueprint.dayPlans.count, !blueprint.dayPlans[dayIndex].isRestDay else { continue }
            guard let firstAnchor = day.firstIndex(where: { role($0) == .anchor }) else { continue }

            let coreBeforeAnchor = day.prefix(firstAnchor).filter { role($0) == .core }
            XCTAssertTrue(
                coreBeforeAnchor.isEmpty,
                """
                Day \(dayIndex + 1) runs core work before its anchor lift: \
                \(coreBeforeAnchor.map(\.exerciseName).joined(separator: ", ")) precede \
                \(day[firstAnchor].exerciseName).
                """
            )
        }
    }

    /// The focus area may still reorder work, but only inside its band.
    func testFocusOrderingCannotHoistAnIsolationAheadOfAnAnchor() {
        let coreFocus = ClaudeService.MusclePriorityIntent(
            area: "Core/Abs",
            priorityLevel: "Medium",
            rank: 1,
            rationale: "",
            weeklyDayTarget: 2,
            weeklyExerciseTarget: 2,
            weeklyDirectSetTarget: 6,
            weeklyStimulusTarget: 8.5,
            preferredStyles: ["Upper", "Legs"],
            preferredMovementPatterns: [],
            coverageKeywords: [],
            accessoryCatalog: [],
            volumeBias: "Moderate",
            directWorkBias: "Maintenance"
        )

        // The audited Day 2, in the order the selector handed it over.
        let ordered = service.arrangeProceduralSelection(
            [
                ("Hanging Knee Raise", "Lower Abs"),
                ("Trap Bar Deadlift", "Posterior Chain"),
                ("Nordic Hamstring Curl", "Hamstrings"),
                ("Barbell Hip Thrust", "Glutes"),
                ("Seated Leg Curl", "Hamstrings")
            ],
            lockedPrefixCount: 0,
            focusIntent: coreFocus
        )

        XCTAssertEqual(
            ordered.first?.name, "Trap Bar Deadlift",
            "The session's heaviest lift must lead even on a day whose focus tag is the core."
        )
        XCTAssertEqual(
            ordered.last?.name, "Hanging Knee Raise",
            "Direct core work belongs at the end of a session that contains an anchor."
        )
    }

    /// ORD-001's "explicitly core-biased" exception, read narrowly: a session with no anchor at
    /// all really is built around its small work, so core may lead there.
    func testCoreMayLeadASessionThatHasNoAnchor() {
        let coreFocus = ClaudeService.MusclePriorityIntent(
            area: "Core/Abs",
            priorityLevel: "Medium",
            rank: 1,
            rationale: "",
            weeklyDayTarget: 2,
            weeklyExerciseTarget: 2,
            weeklyDirectSetTarget: 6,
            weeklyStimulusTarget: 8.5,
            preferredStyles: ["Upper"],
            preferredMovementPatterns: [],
            coverageKeywords: [],
            accessoryCatalog: [],
            volumeBias: "Moderate",
            directWorkBias: "Maintenance"
        )

        let ordered = service.arrangeProceduralSelection(
            [
                ("Machine Lateral Raise", "Lateral Deltoids"),
                ("Cable Crunch", "Abs")
            ],
            lockedPrefixCount: 0,
            focusIntent: coreFocus
        )

        XCTAssertEqual(ordered.first?.name, "Cable Crunch")
    }

    // MARK: - 2. A week that trains the back needs a row

    func testValidatorFlagsAWeekWhoseBackWorkIsAllVertical() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Lat Pulldown", "Lats", sets: 3),
            exercise("Neutral-Grip Lat Pulldown", "Lats", sets: 3),
            exercise("Pull-Up (Weighted or Assisted)", "Lats", sets: 2)
        ]))

        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("no horizontal pull at all"), issues[0])
    }

    /// The first draft of this fix counted "Face Pull" as horizontal pulling, which would have
    /// left the rule silent on the exact week that prompted it — that week contained a Cable Face
    /// Pull and still had no rowing anywhere. A face pull is light rear-delt and external-rotation
    /// work; it does not load the rhomboids and mid-traps through a rowing range.
    func testAFacePullDoesNotSatisfyTheRowRequirement() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Lat Pulldown", "Lats", sets: 3),
            exercise("Pull-Up (Weighted or Assisted)", "Lats", sets: 2),
            exercise("Cable Face Pull", "Rear Deltoids", sets: 3)
        ]))

        XCTAssertEqual(issues.count, 1, "A face pull must not stand in for a row")
    }

    func testARowSatisfiesTheRequirement() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Lat Pulldown", "Lats", sets: 3),
            exercise("Chest-Supported Row", "Upper Back", sets: 3)
        ]))

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    /// Directional on purpose — rows still load the lats through a full range, so a week built on
    /// rowing is not told off for lacking a pulldown.
    func testAWeekOfRowsIsNotFlaggedForLackingAVerticalPull() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Chest-Supported Row", "Upper Back", sets: 3),
            exercise("Seated Cable Row", "Upper Back", sets: 3)
        ]))

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    func testAWeekWithNoBackWorkIsNotFlagged() {
        let issues = service.validateBackPatternBalance(days: week([
            exercise("Incline Barbell Press", "Upper Chest", sets: 3)
        ]))

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    func testAPlannedWeekTrainingTheBackContainsARow() throws {
        let (_, menus) = try plannedWeek()

        let backAliases = service.normalizedGroupAliases(forSeed: "back")
        let trainsBack = menus.joined().contains {
            service.exerciseDirectlyTargets(
                groupAliases: backAliases,
                exerciseName: $0.exerciseName,
                muscleTarget: $0.muscleTarget
            )
        }
        try XCTSkipUnless(trainsBack, "This fixture's split trains no back at all")

        XCTAssertTrue(
            service.menusContainMovementPattern(service.horizontalPullPatterns, in: menus),
            "A planned week that trains the back must contain a rowing movement"
        )
    }

    // MARK: - 3. Grip variants are one exercise, not two

    func testTwoGripsOfOneMovementCannotShareASession() {
        XCTAssertFalse(
            service.dayPatternCapAllows(
                candidateName: "Neutral-Grip Lat Pulldown",
                candidateTarget: "Lats",
                in: [(name: "Lat Pulldown", target: "Lats")]
            ),
            "Lat Pulldown and Neutral-Grip Lat Pulldown are one movement wearing two labels"
        )
    }

    /// The exclusions carry the rule. Stance changes the muscle, unilateral changes the demand,
    /// and the implement is normal variation — none of them are relabelling.
    func testStanceUnilateralAndImplementVariantsRemainAllowed() {
        XCTAssertTrue(
            service.dayPatternCapAllows(
                candidateName: "Seated Calf Raise", candidateTarget: "Calves",
                in: [(name: "Standing Calf Raise", target: "Calves")]
            ),
            "Standing and seated calf raises train different muscles"
        )
        XCTAssertTrue(
            service.dayPatternCapAllows(
                candidateName: "Single-Leg Standing Calf Raise", candidateTarget: "Calves",
                in: [(name: "Standing Calf Raise", target: "Calves")]
            ),
            "A unilateral version is a different demand, not a relabelling"
        )
        XCTAssertTrue(
            service.dayPatternCapAllows(
                candidateName: "Machine Incline Press", candidateTarget: "Upper Chest",
                in: [(name: "Incline Dumbbell Press", target: "Upper Chest")]
            ),
            "Swapping the implement is normal, useful variation"
        )
    }

    /// A stem must never collapse to something generic enough to collide with unrelated work.
    func testStemmingNeverReducesANameToASingleGenericWord() {
        XCTAssertEqual(service.gripVariantStem(forExerciseName: "EZ-Bar Curl"), "ez bar curl")
        XCTAssertEqual(service.gripVariantStem(forExerciseName: "Neutral-Grip Lat Pulldown"), "lat pulldown")
        XCTAssertEqual(service.gripVariantStem(forExerciseName: "Lat Pulldown"), "lat pulldown")
    }

    func testAPlannedWeekShipsNoGripVariantDuplicates() throws {
        let (_, menus) = try plannedWeek()

        for (dayIndex, day) in menus.enumerated() where day.count > 1 {
            for i in day.indices {
                for j in day.indices where j > i {
                    XCTAssertFalse(
                        service.isGripVariantDuplicate(
                            candidateName: day[j].exerciseName,
                            candidateTarget: day[j].muscleTarget,
                            of: day[i].exerciseName,
                            otherTarget: day[i].muscleTarget
                        ),
                        "Day \(dayIndex + 1) spends two slots on \(day[i].exerciseName) / \(day[j].exerciseName)"
                    )
                }
            }
        }
    }

    // MARK: - 4. A plan may not promise more exposures than the split can hold

    func testFrequencyIsClampedToTheStyleCompatibleDayCount() {
        // The audited split exactly: only Upper and Push are compatible with Push/Upper/Arms.
        let plans = [
            dayPlan(1, style: "Upper"), dayPlan(2, style: "Legs"),
            dayPlan(3, style: "Recovery", isRestDay: true), dayPlan(4, style: "Push"),
            dayPlan(5, style: "Lower"), dayPlan(6, style: "Pull"),
            dayPlan(7, style: "Recovery", isRestDay: true)
        ]
        let clamped = service.styleFeasibleAllocations(
            [allocation(area: "Lateral Deltoids", targetFrequency: 3, preferredStyles: ["Push", "Upper", "Arms"])],
            dayPlans: plans
        )

        XCTAssertEqual(clamped[0].targetFrequency, 2)
        // Focus day 8 + one other session at 4 covers the whole 10-set dose, so the lifter loses
        // a spread across the week, not volume.
        XCTAssertEqual(clamped[0].directSetTarget, 10, accuracy: 0.001)
    }

    func testVolumeIsCutOnlyWhenTheSurvivingSessionsCannotHoldIt() {
        let plans = [
            dayPlan(1, style: "Upper"), dayPlan(2, style: "Legs"),
            dayPlan(3, style: "Recovery", isRestDay: true), dayPlan(4, style: "Lower"),
            dayPlan(5, style: "Pull"), dayPlan(6, style: "Legs"),
            dayPlan(7, style: "Recovery", isRestDay: true)
        ]
        let clamped = service.styleFeasibleAllocations(
            [
                allocation(
                    area: "Lateral Deltoids",
                    targetFrequency: 3,
                    directSetTarget: 12,
                    maxPerSessionDirectSets: 4,
                    maxFocusSessionDirectSets: 5,
                    preferredStyles: ["Upper"]
                )
            ],
            dayPlans: plans
        )

        XCTAssertEqual(clamped[0].targetFrequency, 1)
        XCTAssertEqual(clamped[0].directSetTarget, 5, accuracy: 0.001, "One session can hold only its focus-day cap")
        XCTAssertEqual(
            clamped[0].weightedStimulusTarget, 13.0 * (5.0 / 12.0), accuracy: 0.001,
            "Weighted stimulus scales with the direct-set cut so funding cannot chase a dead target"
        )
    }

    func testAnAchievableFrequencyIsLeftAlone() {
        let plans = [
            dayPlan(1, style: "Upper"), dayPlan(2, style: "Push"),
            dayPlan(3, style: "Recovery", isRestDay: true), dayPlan(4, style: "Arms"),
            dayPlan(5, style: "Lower"), dayPlan(6, style: "Pull"),
            dayPlan(7, style: "Recovery", isRestDay: true)
        ]
        let original = allocation(area: "Lateral Deltoids", targetFrequency: 3, preferredStyles: ["Push", "Upper", "Arms"])
        let clamped = service.styleFeasibleAllocations([original], dayPlans: plans)

        XCTAssertEqual(clamped[0].targetFrequency, 3)
        XCTAssertEqual(clamped[0].directSetTarget, original.directSetTarget, accuracy: 0.001)
    }

    /// Zero compatible days means the style list is unusable for this split, not that the priority
    /// should stop training. Clamping to zero would be the worse answer.
    func testAllocationSurvivesASplitWithNoCompatibleDayAtAll() {
        let plans = [
            dayPlan(1, style: "Legs"), dayPlan(2, style: "Lower"),
            dayPlan(3, style: "Recovery", isRestDay: true), dayPlan(4, style: "Legs"),
            dayPlan(5, style: "Lower"), dayPlan(6, style: "Legs"),
            dayPlan(7, style: "Recovery", isRestDay: true)
        ]
        let clamped = service.styleFeasibleAllocations(
            [allocation(area: "Lateral Deltoids", targetFrequency: 3, preferredStyles: ["Push", "Upper", "Arms"])],
            dayPlans: plans
        )

        XCTAssertEqual(clamped[0].targetFrequency, 3)
    }

    /// The property the clamp exists to guarantee: every printed plan is buildable.
    func testEveryPlannedPriorityFrequencyIsReachableInItsOwnSplit() throws {
        let (blueprint, _) = try plannedWeek()

        let trainingStyles = blueprint.dayPlans
            .filter { !$0.isRestDay }
            .map { service.canonicalTrainingStyle($0.style) }

        for allocation in blueprint.priorityAllocations {
            let compatible = trainingStyles.filter { allocation.preferredStyles.contains($0) }.count
            guard compatible > 0 else { continue }
            XCTAssertLessThanOrEqual(
                allocation.targetFrequency, compatible,
                """
                '\(allocation.area)' is planned for \(allocation.targetFrequency) exposures on \
                \(allocation.preferredStyles.joined(separator: "/")) days, but the split contains \
                only \(compatible).
                """
            )
        }
    }

    // MARK: - 5. Maintenance has a floor, not only a ceiling

    func testAGroupBelowTheMaintenanceFloorIsFlagged() throws {
        let (blueprint, _) = try plannedWeek()
        let issues = service.validateNonPriorityMuscleVolume(
            days: week([exercise("Rope Triceps Pressdown", "Triceps", sets: 2)]),
            blueprint: blueprint,
            recoveryTight: false
        )

        XCTAssertTrue(
            issues.contains { $0.contains("'Triceps' falls below the maintenance weekly volume floor") },
            "\(issues)"
        )
    }

    func testAGroupAtTheFloorIsNotFlagged() throws {
        let (blueprint, _) = try plannedWeek()
        let issues = service.validateNonPriorityMuscleVolume(
            days: week([exercise("Rope Triceps Pressdown", "Triceps", sets: 4)]),
            blueprint: blueprint,
            recoveryTight: false
        )

        XCTAssertFalse(issues.contains { $0.contains("'Triceps' falls below") }, "\(issues)")
    }

    /// Constrained recovery lowers the whole band, floor included (SLEEP-002).
    func testTheFloorDropsWhenRecoveryIsConstrained() throws {
        let (blueprint, _) = try plannedWeek()
        let days = week([exercise("Rope Triceps Pressdown", "Triceps", sets: 3)])

        XCTAssertTrue(
            service.validateNonPriorityMuscleVolume(days: days, blueprint: blueprint, recoveryTight: false)
                .contains { $0.contains("'Triceps' falls below") }
        )
        XCTAssertFalse(
            service.validateNonPriorityMuscleVolume(days: days, blueprint: blueprint, recoveryTight: true)
                .contains { $0.contains("'Triceps' falls below") }
        )
    }

    /// A group at zero keeps its own, louder finding — the floor rule must not swallow it.
    func testZeroCoverageStillReportsAsZeroRatherThanAsBelowFloor() throws {
        let (blueprint, _) = try plannedWeek()
        let issues = service.validateNonPriorityMuscleVolume(
            days: week([exercise("Rope Triceps Pressdown", "Triceps", sets: 4)]),
            blueprint: blueprint,
            recoveryTight: false
        )

        XCTAssertTrue(issues.contains { $0.contains("'Biceps' receives zero direct sets") }, "\(issues)")
        XCTAssertFalse(issues.contains { $0.contains("'Biceps' falls below") }, "\(issues)")
    }

    /// The structural half: a group holding one slot is capped near its role default no matter how
    /// much weekly budget remains, so the repair has to be a second slot.
    func testCoveredNonPriorityGroupsReachTheExposureFloor() throws {
        let (blueprint, menus) = try plannedWeek()

        for group in service.majorMuscleGroups {
            guard !service.isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint) else { continue }
            let slots = service.maintenanceSlots(in: menus, forSeed: group.seed)
            guard !slots.isEmpty else { continue }

            XCTAssertGreaterThanOrEqual(
                slots.count, service.maintenanceExposureFloor,
                "'\(group.label)' holds \(slots.count) weekly slot(s); one slot cannot reach a maintenance dose"
            )
        }
    }

    // MARK: - Ownership of the two new findings

    /// Both are pure exercise-selection verdicts. Unclassified findings are an acceptable warning
    /// under menu-lock and a HARD FAILURE unlocked, and neither layer being judged can act on
    /// these — so leaving them unclassified would discard a paid week over a slot that provably
    /// could not be placed.
    func testBothNewFindingsAreAcceptableWarningsOnBothPaths() {
        let findings = [
            "The week trains the back with no horizontal pull at all — every back movement pulls down from overhead.",
            "Non-priority muscle group 'Triceps' falls below the maintenance weekly volume floor (2 sets vs 4)."
        ]

        for finding in findings {
            XCTAssertEqual(service.validationDisposition(for: finding, menuLocked: true), .acceptableWarning, finding)
            XCTAssertEqual(service.validationDisposition(for: finding, menuLocked: false), .acceptableWarning, finding)
        }
    }
}
