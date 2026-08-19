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
    private func plannedWeek(weekNumber: Int = 1) throws -> (
        blueprint: ClaudeService.ProgramBlueprint,
        menus: [[ClaudeService.PreSelectedExercise]]
    ) {
        guard let url = Bundle.module.url(forResource: "five-maintenance-errors", withExtension: "json") else {
            XCTFail("Bundled generator regression fixture is missing")
            throw CocoaError(.fileNoSuchFile)
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let intent = service.trainingIntentPlan(from: fixture.analysis)
        let blueprint = service.programBlueprint(for: intent, weekNumber: weekNumber)
        let menus = service.preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: intent,
            weekNumber: weekNumber,
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
        isRestDay: Bool = false,
        fatigueCap: Int = 20
    ) -> ClaudeService.BlueprintDayPlan {
        ClaudeService.BlueprintDayPlan(
            dayIndex: index,
            style: style,
            focusArea: focusArea,
            supportAreas: [],
            targetFatigueCap: fatigueCap,
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

    /// A movement named "row" that is not one. Both of these are shoulder work, and neither may
    /// stand in for the week's rowing.
    ///
    /// Today the catalogue is what catches them: `Cable Upright Row` carries the "Upright Row"
    /// pattern and `Chest-Supported Rear Delt Row` carries "Rear Delt Row", so neither reaches
    /// `horizontalPullPatterns` at all. The rule ALSO requires a row to directly train the back,
    /// which is redundant for every one of the ten catalogue rows — all of them do — and is there
    /// for the case the catalogue does not cover: `inferredExerciseMetadata` hands the "Row"
    /// pattern to any unknown exercise whose NAME contains "row". This test pins the outcome, not
    /// which of the two conditions produced it.
    /// Note precisely what this guards: the CATALOGUE's patterns, not the muscle condition. If the
    /// muscle condition were deleted this test would still pass, because both fixtures are already
    /// excluded a line earlier by their movement pattern.
    /// `testNoCatalogueEntryCarriesTheRowPatternWithoutTrainingTheBack` is the muscle tripwire.
    func testAMovementMerelyNamedRowIsExcludedByItsPattern() {
        for shoulderWork in [
            (name: "Cable Upright Row", target: "Lateral Deltoids"),
            (name: "Chest-Supported Rear Delt Row", target: "Rear Deltoids")
        ] {
            let issues = service.validateBackPatternBalance(days: week([
                exercise("Lat Pulldown", "Lats", sets: 3),
                exercise("Pull-Up (Weighted or Assisted)", "Lats", sets: 2),
                exercise(shoulderWork.name, shoulderWork.target, sets: 3)
            ]))

            XCTAssertEqual(issues.count, 1, "\(shoulderWork.name) must not stand in for a row")
        }
    }

    /// The tripwire for the muscle half of the row rule, read off the RAW catalogue rather than
    /// the back-filtered view of it.
    ///
    /// An earlier version of this test walked `metadataFocusExerciseCatalog(for: "back")`, which
    /// SELECTS entries by the very property the test then asserted — it could not fail. This one
    /// scans every entry in the catalogue, so adding a movement carrying the "Row" pattern that
    /// does not train the back fails here.
    ///
    /// That is exactly the day the muscle condition in `validateBackPatternBalance` starts to
    /// matter. It is unreachable today — all ten rowing entries train the back — and this test is
    /// what will say so when that stops being true.
    func testNoCatalogueEntryCarriesTheRowPatternWithoutTrainingTheBack() {
        let backAliases = service.normalizedGroupAliases(forSeed: "back")
        var rowCount = 0

        for entry in service.exerciseMetadataEntries
        where service.horizontalPullPatterns.contains(entry.movementPattern) {
            rowCount += 1
            XCTAssertTrue(
                service.exerciseDirectlyTargets(
                    groupAliases: backAliases,
                    exerciseName: entry.canonicalName,
                    muscleTarget: entry.primaryAreas.first ?? ""
                ),
                """
                \(entry.canonicalName) carries the Row pattern but does not train the back \
                (primary: \(entry.primaryAreas)). The muscle condition in validateBackPatternBalance \
                is now load-bearing — write a test that isolates it.
                """
            )
        }

        XCTAssertGreaterThan(rowCount, 0, "The catalogue must contain at least one rowing movement")
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
            service.menusContainMovementPattern(
                service.horizontalPullPatterns,
                trainingGroupSeed: "back",
                in: menus
            ),
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

    /// The trimmed plan must still obey the arithmetic every other layer assumes: slots-per-session
    /// x sessions x ~4 working sets has to cover the printed weekly target. An earlier draft of the
    /// clamp sized capacity from the SESSION caps alone and would have printed a target that forces
    /// a movement above four working sets — the exact shape `minimumExerciseSlots` exists to stop,
    /// and the invariant `ResidueMuscleDoseTests` already pins for un-clamped plans.
    func testAClampedPlanStillCarriesItsPrintedTargetWithinTheFourSetCeiling() {
        let plans = [
            dayPlan(1, style: "Upper"), dayPlan(2, style: "Legs"),
            dayPlan(3, style: "Recovery", isRestDay: true), dayPlan(4, style: "Lower"),
            dayPlan(5, style: "Pull"), dayPlan(6, style: "Legs"),
            dayPlan(7, style: "Recovery", isRestDay: true)
        ]

        // A generous focus-day cap is what made the session-only formula look sufficient.
        let clamped = service.styleFeasibleAllocations(
            [
                allocation(
                    area: "Lateral Deltoids",
                    targetFrequency: 3,
                    directSetTarget: 14,
                    maxPerSessionDirectSets: 5,
                    maxFocusSessionDirectSets: 10,
                    preferredStyles: ["Upper"]
                )
            ],
            dayPlans: plans
        )

        for allocation in clamped {
            let exposures = service.prioritySlotsPerSession(for: allocation) * allocation.targetFrequency
            XCTAssertGreaterThanOrEqual(
                Double(exposures) * 4.0, allocation.directSetTarget,
                """
                '\(allocation.area)' plans \(exposures) exposures for \(allocation.directSetTarget) \
                sets — that forces an exercise above four working sets.
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

    /// The outcome that matters, asserted end to end: a fully planned week leaves no muscle group
    /// under the maintenance floor.
    ///
    /// Deliberately checks the VALIDATOR verdict rather than the slot count. The breadth pass is
    /// best-effort by design — it will not overcrowd a session to buy a slot — so demanding two
    /// slots unconditionally would assert something the planner is right to refuse. What must
    /// hold is that the week it ships is not under-dosing anyone.
    func testAPlannedWeekLeavesNoGroupBelowTheMaintenanceFloor() throws {
        let (blueprint, menus) = try plannedWeek()

        let days = menus.indices.map { dayIndex in
            WorkoutDayResponse(
                dayNumber: dayIndex + 1,
                dayName: menus[dayIndex].isEmpty ? "Rest" : "Training",
                muscleGroups: "",
                isRestDay: menus[dayIndex].isEmpty,
                notes: "",
                exercises: menus[dayIndex].map {
                    exercise($0.exerciseName, $0.muscleTarget, sets: $0.prescribedSets)
                }
            )
        }
        let recoveryTight = blueprint.calibration.recoveryConstrained
            || blueprint.calibration.poorNutritionAdherence

        let issues = service.validateNonPriorityMuscleVolume(
            days: days,
            blueprint: blueprint,
            recoveryTight: recoveryTight
        )

        XCTAssertTrue(
            issues.filter { $0.contains("falls below the maintenance weekly volume floor") }.isEmpty,
            "\(issues.filter { $0.contains("falls below") })"
        )
    }

    /// Breadth must never be bought by making a session worse. `validateSessionFocusDiscipline`
    /// calls a Lower day with seven or more movements "too crowded for a fatigue-managed Lower
    /// session", and the first version of the balance passes used a flat ceiling of eight and
    /// earned exactly that finding by appending a second calf movement to a six-movement Legs day.
    func testALowerDayIsNotFilledPastItsCrowdingLimit() {
        for style in ["Lower", "Legs"] {
            XCTAssertEqual(service.comfortableDayExerciseCeiling(forStyle: style, weekNumber: 1), 6)
        }
        for style in ["Push", "Upper"] {
            XCTAssertEqual(service.comfortableDayExerciseCeiling(forStyle: style, weekNumber: 1), 8)
        }
    }

    /// A deload week is BUILT smaller on purpose — `preSelectedExerciseMenu` drops its per-day
    /// target from six movements to five to reduce the work. A pass that appends movements back
    /// would undo the deload, and would do it more eagerly than in a loading week: a five-movement
    /// day leaves more muscle groups holding a single slot for the breadth pass to notice.
    func testADeloadWeekIsNeverGrownByTheBalancePasses() {
        for style in ["Lower", "Legs", "Push", "Upper", "Pull", "Arms"] {
            XCTAssertEqual(
                service.comfortableDayExerciseCeiling(
                    forStyle: style,
                    weekNumber: MesocyclePhase.deloadWeek
                ),
                service.deloadDayExerciseTarget,
                "A \(style) deload day must not be grown past the size the planner built"
            )
        }

        // The planner builds deload days at exactly this size, so the ceiling forbids any
        // addition rather than merely limiting it.
        let deloadDay = (1...service.deloadDayExerciseTarget).map { index in
            ClaudeService.PreSelectedExercise(
                exerciseName: "Filler \(index)",
                muscleTarget: "Chest",
                movementPattern: "Horizontal Press",
                role: .accessory,
                prescribedSets: 1
            )
        }
        XCTAssertFalse(
            deloadDay.count < service.comfortableDayExerciseCeiling(
                forStyle: "Push",
                weekNumber: MesocyclePhase.deloadWeek
            ),
            "A deload day built to target must already be at its ceiling"
        )
    }

    /// A deload day may exceed its target for exactly ONE reason: `enforceBaselineMuscleCoverage`
    /// placing the week's only exposure for a muscle that would otherwise receive nothing at all.
    ///
    /// The first version of this test simply demanded every deload day sit at or under the target,
    /// and CI was right to fail it — a real deload week came back with six movements on day 2. The
    /// cause was not the balance passes, which are capped, but the zero-coverage repair, which is
    /// deliberately allowed to grow a deload day. A muscle receiving no work for a week is worse
    /// than one extra light movement. This asserts that justification instead of pretending the
    /// stricter rule holds.
    func testADeloadDayGrowsOnlyToKeepAMuscleOffZero() throws {
        let (_, deloadMenus) = try plannedWeek(weekNumber: MesocyclePhase.deloadWeek)

        let soleExposureGroups = service.majorMuscleGroups.filter { group in
            service.maintenanceSlots(in: deloadMenus, forSeed: group.seed).count == 1
        }

        for (dayIndex, day) in deloadMenus.enumerated()
        where day.count > service.deloadDayExerciseTarget {
            let carriesASoleExposure = day.contains { slot in
                soleExposureGroups.contains { group in
                    service.exerciseDirectlyTargets(
                        groupAliases: service.normalizedGroupAliases(forSeed: group.seed),
                        exerciseName: slot.exerciseName,
                        muscleTarget: slot.muscleTarget
                    )
                }
            }

            XCTAssertTrue(
                carriesASoleExposure,
                """
                Deload day \(dayIndex + 1) grew to \(day.count) movements with nothing on it that \
                is a muscle's only weekly exposure: \(day.map(\.exerciseName)). Something other \
                than the zero-coverage repair is growing the deload week.
                """
            )
        }
    }

    /// A latent substring bug the balance passes uncovered: day-style matching is a raw substring
    /// test, and "back" matches "kick*back*", so `Cable Glute Kickback` read as legitimate
    /// Upper-day work and was appended to a chest-and-delts session.
    func testGluteWorkCannotBePlacedOnAnUpperBodyDay() {
        let kickback = exercise("Cable Glute Kickback", "Glutes", sets: 3)

        for style in ["Upper", "Push", "Pull", "Arms"] {
            XCTAssertFalse(
                service.exerciseMatchesDayStyle(kickback, style: style),
                "Glute work must not be placeable on a \(style) day"
            )
        }
        XCTAssertTrue(service.exerciseMatchesDayStyle(kickback, style: "Lower"))
    }

    func testAPlannedWeekPlacesNoLowerBodyWorkOnAnUpperBodyDay() throws {
        let (blueprint, menus) = try plannedWeek()

        for (dayIndex, day) in menus.enumerated() where !day.isEmpty {
            guard dayIndex < blueprint.dayPlans.count else { continue }
            let style = service.canonicalTrainingStyle(blueprint.dayPlans[dayIndex].style)
            guard ["Upper", "Push", "Pull", "Arms"].contains(style) else { continue }

            for slot in day {
                XCTAssertFalse(
                    "\(slot.exerciseName) \(slot.muscleTarget)".lowercased().contains("glute"),
                    "Day \(dayIndex + 1) is a \(style) session but carries \(slot.exerciseName)"
                )
            }
        }
    }

    // MARK: - Budgets the balance passes must not break

    /// `fatigueContribution` charges a movement its full `fatigueCost` at ONE set — the multiplier
    /// only rises at four sets and again at five — so an appended movement spends day fatigue that
    /// no later pass can walk back. `allocateWeeklySetPrescription` keeps a finished day inside its
    /// cap only while the SEEDED day already fits; past that line it can decline to fund sets but
    /// cannot remove the movement that broke the budget.
    ///
    /// Left unchecked a balance pass could earn "carries too much total fatigue load", which is
    /// correction-worthy under menu-lock: a paid correction call, and the whole paid candidate set
    /// discarded if it survives.
    func testABalancePassWillNotPushADayPastItsFatigueCap() {
        let menu = [
            ClaudeService.PreSelectedExercise(
                exerciseName: "Back Squat",
                muscleTarget: "Quads",
                movementPattern: "Squat",
                role: .anchor,
                prescribedSets: 1
            )
        ]
        let candidate = (name: "Standing Calf Raise", target: "Calves")

        let seededFatigue = service.estimatedDayFatigue(for: [
            exercise("Back Squat", "Quads", sets: 1),
            exercise("Standing Calf Raise", "Calves", sets: 1)
        ])

        XCTAssertFalse(
            service.seededDayFitsItsBudgets(
                adding: candidate,
                to: menu,
                plan: dayPlan(1, style: "Lower", fatigueCap: seededFatigue - 1),
                weekNumber: 1
            ),
            "A day already at its fatigue cap must not accept another movement"
        )
        XCTAssertTrue(
            service.seededDayFitsItsBudgets(
                adding: candidate,
                to: menu,
                plan: dayPlan(1, style: "Lower", fatigueCap: seededFatigue),
                weekNumber: 1
            ),
            "A day with room must still accept it"
        )
    }

    /// The property that matters end to end: no planned day exceeds the fatigue cap its own plan
    /// set for it, once every movement is seeded.
    func testNoPlannedDayIsSeededPastItsFatigueCap() throws {
        let (blueprint, menus) = try plannedWeek()

        for (dayIndex, day) in menus.enumerated() where !day.isEmpty {
            guard dayIndex < blueprint.dayPlans.count,
                  !blueprint.dayPlans[dayIndex].isRestDay else { continue }

            let seeded = day.map { exercise($0.exerciseName, $0.muscleTarget, sets: 1) }
            XCTAssertLessThanOrEqual(
                service.estimatedDayFatigue(for: seeded),
                blueprint.dayPlans[dayIndex].targetFatigueCap,
                "Day \(dayIndex + 1) is over its fatigue cap before a single set is funded"
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
