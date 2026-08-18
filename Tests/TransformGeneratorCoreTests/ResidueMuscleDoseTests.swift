import Foundation
import XCTest
@testable import Transform

/// A major muscle group is a bookkeeping BUCKET, not a muscle. `stimulusAreaAliases` folds all
/// three deltoid heads into "shoulders", both chest regions into "chest", and Lats/Upper Back/Mid
/// Back into "back", so prioritizing ONE member marked the whole bucket prioritized — and every
/// call site that skipped prioritized buckets stopped seeing the other members along with it.
///
/// In `allocateWeeklySetPrescription` that was silent starvation. The maintenance funding loop
/// skips any exercise whose `groupTargets` are all false, and a movement targeting only the
/// un-prioritized members of a prioritized bucket had no group AND earned no priority credit. No
/// loop ever raised it. It shipped at the bare `minimumSetFloor` of 2 — not because two sets were
/// chosen for it, but because nothing in the allocator ever looked at it.
///
/// The owner spotted this by eye: his Week 1 carried three rear-delt movements at 2x apiece under
/// a Lateral Deltoids priority, sitting next to a back group the very same week dosed 3/3/2 —
/// because Back was not prioritized and therefore still had a ledger.
///
/// Nine of the twenty selectable priority labels sit in a bucket with siblings (Upper Chest, the
/// three deltoid heads, Lats, Upper Back, Lower Abs, Obliques, Anterior Core), so this was the
/// common case rather than an edge one.
@MainActor
final class ResidueMuscleDoseTests: XCTestCase {

    private let service = ClaudeService.shared

    private struct Fixture: Decodable {
        let analysis: BodyAnalysisResult
    }

    private func fixtureBlueprintAndMenus() throws -> (ClaudeService.ProgramBlueprint, [[ClaudeService.PreSelectedExercise]]) {
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

    /// Weekly sets per distinct movement in one group's RESIDUE — the work in it that no priority
    /// allocation pays for. Grouped by normalized name to match the gates, which count distinct
    /// names rather than slots.
    private func residueDoses(
        seed: String,
        blueprint: ClaudeService.ProgramBlueprint,
        menus: [[ClaudeService.PreSelectedExercise]]
    ) -> [String: Int] {
        let aliases = service.normalizedGroupAliases(forSeed: seed)
        var setsByMovement: [String: Int] = [:]
        for exercise in menus.joined() where service.exerciseCountsTowardMaintenance(
            groupSeed: seed,
            groupAliases: aliases,
            exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget,
            blueprint: blueprint
        ) {
            setsByMovement[service.normalizeExerciseName(exercise.exerciseName), default: 0] += exercise.prescribedSets
        }
        return setsByMovement
    }

    private func prioritizedSeeds(_ blueprint: ClaudeService.ProgramBlueprint) -> [String] {
        service.majorMuscleGroups
            .filter { service.isMajorMuscleGroupPrioritized(seed: $0.seed, blueprint: blueprint) }
            // Closure, not `map(\.seed)`: `majorMuscleGroups` is an array of TUPLES and Swift has
            // no key paths into tuple members.
            .map { $0.seed }
    }

    // MARK: - The reported symptom

    /// The exact thing the owner saw. A prioritized bucket's residue, once it holds more than one
    /// movement, must not have every one of those movements stuck below a productive dose — the
    /// same property `MaintenanceDoseFragmentationTests` asserts for un-prioritized groups.
    func testResidueOfAPrioritizedGroupIsNotEntirelyStuckAtTwoSets() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()

        var checkedAnyResidue = false
        for seed in prioritizedSeeds(blueprint) {
            let doses = residueDoses(seed: seed, blueprint: blueprint, menus: menus)
            guard doses.count > 1 else { continue }
            checkedAnyResidue = true
            XCTAssertTrue(
                doses.values.contains { $0 >= 3 },
                "Residue of prioritized group '\(seed)' is \(doses.sorted(by: { $0.key < $1.key })) — every movement below a productive dose, which is the starvation this fix exists to end."
            )
        }

        try XCTSkipUnless(
            checkedAnyResidue,
            "No prioritized group in this fixture carried more than one residue movement, so the symptom could not be reproduced."
        )
    }

    /// Rear delts specifically: this fixture prioritizes Lateral Deltoids, which marks the whole
    /// "shoulders" bucket prioritized, and the rear-delt work in it is the residue the owner saw
    /// programmed at 2/2/2.
    func testShoulderResidueExistsAndIsFundedInThisFixture() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()

        XCTAssertTrue(
            prioritizedSeeds(blueprint).contains("shoulders"),
            "Premise: this fixture's Lateral Deltoids priority must mark the shoulders bucket prioritized."
        )

        let doses = residueDoses(seed: "shoulders", blueprint: blueprint, menus: menus)
        XCTAssertFalse(doses.isEmpty, "Premise: this fixture programs rear-delt work the Lateral Deltoids budget does not pay for.")
        XCTAssertTrue(
            doses.values.contains { $0 >= 3 },
            "Shoulder residue is \(doses.sorted(by: { $0.key < $1.key })) — the rear-delt work is still starved."
        )
    }

    // MARK: - Funding the residue must not spend more than recovery allows

    /// Dose quality is bought from the residue's own maintenance ceiling, never on top of it. The
    /// ceiling is the recovery guard and still binds.
    func testResidueStaysUnderTheMaintenanceCeiling() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()
        XCTAssertTrue(blueprint.calibration.recoveryConstrained, "Premise: this fixture is the recovery-tight case.")

        for seed in prioritizedSeeds(blueprint) {
            let total = residueDoses(seed: seed, blueprint: blueprint, menus: menus).values.reduce(0, +)
            XCTAssertLessThanOrEqual(
                total, 8,
                "Residue of prioritized group '\(seed)' totals \(total) weekly sets against a recovery-tight ceiling of 8."
            )
        }
    }

    /// Nothing may ship at a single set.
    ///
    /// Written as a guard on the residue change — adding a ceiling where none existed could in
    /// principle strand a movement below `minimumSetFloor` — this immediately caught a DIFFERENT
    /// and PRE-EXISTING defect on its first CI run: "Behind-the-Back Cable Lateral Raise#1" on day
    /// one. That single set was already in the pinned snapshot at 57fe9bf, shipping to the owner,
    /// with nothing in the suite asserting against it.
    ///
    /// Cause: the priority funding loop optimizes weekly aggregate volume and ranks candidates by
    /// quality score, so a prime movement at three sets (30-3=27) always outbid an accessory still
    /// at its seed of one (10-1=9). Four distinct lateral raises shared an ~11.5-set budget; the
    /// primes drank it, and the floor pass afterwards could not lift the last movement to two
    /// without crossing the over-volume hard-fail line. The loop now funds every movement to its
    /// floor before pushing any movement beyond it.
    ///
    /// Kept deliberately broad — every day, every exercise, not just residue — because the defect
    /// it found was not the one it was written for.
    func testNoMovementInTheWeekShipsAtOneSet() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()
        diagnosisMenus = menus

        for (dayIndex, menu) in menus.enumerated() {
            for exercise in menu where exercise.prescribedSets < 2 {
                XCTFail(
                    "Day \(dayIndex + 1) '\(exercise.exerciseName)' ships at \(exercise.prescribedSets) set(s) — below the minimum worth programming.\n"
                        + blockedSetDiagnosis(dayIndex: dayIndex, menu: menu, blueprint: blueprint, exercise: exercise)
                )
            }
        }
    }

    /// Every ceiling in `canAddSet`, printed for the exercise that could not be lifted. Without
    /// this the failure says only "1 set" and the reason has to be guessed — and guessing it wrong
    /// costs a full CI round trip per attempt.
    private func blockedSetDiagnosis(
        dayIndex: Int,
        menu: [ClaudeService.PreSelectedExercise],
        blueprint: ClaudeService.ProgramBlueprint,
        exercise: ClaudeService.PreSelectedExercise
    ) -> String {
        let responses = menu.map {
            WorkoutExerciseResponse(
                exerciseName: $0.exerciseName,
                sets: $0.prescribedSets,
                reps: "8-12",
                tempo: "",
                restSeconds: 90,
                notes: "",
                muscleTarget: $0.muscleTarget
            )
        }
        var lines: [String] = []
        lines.append("  role=\(service.proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget))"
            + " roleDefaultSets=\(service.proceduralSets(for: 1, exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget))")

        if blueprint.dayPlans.indices.contains(dayIndex) {
            let plan = blueprint.dayPlans[dayIndex]
            lines.append("  day fatigue \(service.estimatedDayFatigue(for: responses))/\(plan.targetFatigueCap)"
                + "  minutes \(service.estimatedSessionMinutes(for: service.proceduralTrainingDay(from: responses)))/\(plan.targetSessionMinutes)"
                + "  focusArea=\(plan.focusArea ?? "nil")")
        }

        for allocation in blueprint.priorityAllocations {
            let unit = WorkoutExerciseResponse(
                exerciseName: exercise.exerciseName,
                sets: 1,
                reps: "",
                tempo: "",
                restSeconds: 0,
                notes: "",
                muscleTarget: exercise.muscleTarget
            )
            guard service.directSetCredit(for: unit, area: allocation.area) > 0 else { continue }
            let weekly = menus_directSets(for: allocation.area)
            let today = responses.reduce(0.0) { $0 + service.directSetCredit(for: $1, area: allocation.area) }
            lines.append("  priority '\(allocation.area)': weekly \(weekly)/\(allocation.directSetTarget)"
                + " (hard-fail line ~\(allocation.directSetTarget * 1.15))"
                + "  thisDay \(today) vs perSession \(allocation.maxPerSessionDirectSets) / focusSession \(allocation.maxFocusSessionDirectSets)"
                + "  kind=\(service.focusStimulusKind(exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget, focusArea: allocation.area))")
        }
        return lines.joined(separator: "\n")
    }

    /// Weekly direct sets for one area across the whole fixture week.
    private var diagnosisMenus: [[ClaudeService.PreSelectedExercise]] = []

    private func menus_directSets(for area: String) -> Double {
        diagnosisMenus.joined().reduce(0.0) { total, exercise in
            total + service.directSetCredit(
                for: WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: exercise.prescribedSets,
                    reps: "",
                    tempo: "",
                    restSeconds: 0,
                    notes: "",
                    muscleTarget: exercise.muscleTarget
                ),
                area: area
            )
        }
    }

    /// The ranking change stated directly: an exercise below its floor must outrank a
    /// higher-quality exercise that has already reached its own, or the stranding returns.
    ///
    /// Expressed as the arithmetic because the ranking is local to `allocateWeeklySetPrescription`
    /// and has no seam to call. The bonus must exceed any reachable quality score (prime 30 plus a
    /// focus bonus of 5, minus the set count) by a margin no realistic set count can close.
    func testBelowFloorBonusOutranksEveryQualityScore() {
        func rank(quality: Int, focus: Bool, sets: Int, floor: Int) -> Int {
            let belowFloorBonus = sets < floor ? 100 : 0
            return quality + (focus ? 5 : 0) + belowFloorBonus - sets
        }

        // The fixture's actual collision: a prime, focus-day lateral raise at three sets versus a
        // support-quality one still sitting at its seed.
        XCTAssertGreaterThan(
            rank(quality: 10, focus: false, sets: 1, floor: 2),
            rank(quality: 30, focus: true, sets: 3, floor: 2),
            "A movement below its minimum dose must be funded before a prime movement is pushed further."
        )

        // Once it reaches the floor, normal quality ordering resumes — the bonus must not turn
        // accessories into permanent winners.
        XCTAssertLessThan(
            rank(quality: 10, focus: false, sets: 2, floor: 2),
            rank(quality: 30, focus: true, sets: 3, floor: 2),
            "Past the floor, quality must decide again."
        )
    }

    /// `minimumSetFloor` depends only on the exercise's ROLE, so caching it per exercise in the
    /// allocator's accounting struct is safe. If it ever started varying with set count, the cached
    /// value would go stale and the floor-first rule would fund the wrong movements.
    func testMinimumSetFloorDoesNotVaryWithSetCount() {
        for name in ["Behind-the-Back Cable Lateral Raise", "Incline Barbell Press", "Cable Crunch"] {
            let floors = [1, 2, 3, 5].map { sets in
                service.minimumSetFloor(
                    for: WorkoutExerciseResponse(
                        exerciseName: name,
                        sets: sets,
                        reps: "8-12",
                        tempo: "",
                        restSeconds: 90,
                        notes: "",
                        muscleTarget: ""
                    )
                )
            }
            XCTAssertEqual(
                Set(floors).count, 1,
                "'\(name)' reports floors \(floors) across set counts — the allocator caches this value once."
            )
        }
    }

    // MARK: - The residue definition itself

    /// Work the priority budget already pays for must NOT also be governed as maintenance, or the
    /// same sets would be counted against two ceilings and the priority would be squeezed by its
    /// own funding.
    func testPriorityFundedWorkIsNeverCountedAsResidue() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()

        for seed in prioritizedSeeds(blueprint) {
            let aliases = service.normalizedGroupAliases(forSeed: seed)
            for exercise in menus.joined() where service.earnsDirectPriorityCredit(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                blueprint: blueprint
            ) {
                XCTAssertFalse(
                    service.exerciseCountsTowardMaintenance(
                        groupSeed: seed,
                        groupAliases: aliases,
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget,
                        blueprint: blueprint
                    ),
                    "'\(exercise.exerciseName)' is funded by a priority allocation and must not also debit '\(seed)' maintenance."
                )
            }
        }
    }

    /// `allocateWeeklySetPrescription` does NOT call `earnsDirectPriorityCredit`. It reuses its
    /// precomputed `unitDirect` array and asks `unitDirect.contains { $0 > 0 }`, so the fix relies
    /// on two separate expressions classifying every movement identically. An adversarial review of
    /// this change read the allocator's comment and concluded they might diverge — that they do not
    /// rests on `stimulusCredit` computing its `directSets` field as exactly `directSetCredit`,
    /// which is an implementation detail one refactor away from silently changing.
    ///
    /// If they ever disagree, the allocator funds a different set of movements than the menu gate
    /// budgeted for, and the starvation returns for whichever movements fall in the gap — with no
    /// validator rule left to catch it, because prioritized groups are exempt there by design.
    func testAllocatorAndCanonicalPriorityCreditChecksAgree() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()
        XCTAssertFalse(blueprint.priorityAllocations.isEmpty, "Premise: this fixture has priorities.")

        for exercise in menus.joined() {
            let probe = WorkoutExerciseResponse(
                exerciseName: exercise.exerciseName,
                sets: 1,
                reps: "",
                tempo: "",
                restSeconds: 0,
                notes: "",
                muscleTarget: exercise.muscleTarget
            )
            // Exactly what the allocator caches in `unitDirect`.
            let allocatorSaysFunded = blueprint.priorityAllocations.contains { allocation in
                service.stimulusCredit(for: probe, area: allocation.area).directSets > 0
            }
            let canonicalSaysFunded = service.earnsDirectPriorityCredit(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                blueprint: blueprint
            )

            XCTAssertEqual(
                allocatorSaysFunded, canonicalSaysFunded,
                "'\(exercise.exerciseName)' is classified differently by the allocator's cached unitDirect than by earnsDirectPriorityCredit — the residue ledger and the menu breadth gate would disagree about it."
            )
        }
    }

    /// The single line the equivalence above depends on, asserted directly so a refactor of
    /// `stimulusCredit` cannot quietly break the allocator's shortcut. Weighted stimulus is
    /// deliberately NOT asserted equal — it legitimately includes secondary and support credit,
    /// which is exactly why the shortcut must read `directSets` and nothing else.
    func testStimulusCreditDirectSetsIsExactlyDirectSetCredit() {
        let probes: [(name: String, target: String)] = [
            ("Incline Barbell Press", "Upper Chest"),
            ("Cable Fly", "Chest"),
            ("Cable Lateral Raise", "Lateral Deltoids"),
            ("Cable Face Pull", "Rear Deltoids"),
            ("Reverse Pec Deck", "Rear Deltoids"),
            ("Lat Pulldown", "Lats"),
            ("Dumbbell Hammer Curl", "Brachialis"),
            ("Rope Triceps Pressdown", "Triceps")
        ]

        for area in ["Upper Chest", "Lateral Deltoids", "Core/Abs", "Biceps", "Back"] {
            for probe in probes {
                let exercise = WorkoutExerciseResponse(
                    exerciseName: probe.name,
                    sets: 3,
                    reps: "",
                    tempo: "",
                    restSeconds: 0,
                    notes: "",
                    muscleTarget: probe.target
                )
                XCTAssertEqual(
                    service.stimulusCredit(for: exercise, area: area).directSets,
                    service.directSetCredit(for: exercise, area: area),
                    "'\(probe.name)' vs '\(area)': the allocator's residue shortcut assumes these are the same number."
                )
            }
        }
    }

    /// Un-prioritized groups must behave exactly as they did before: every directly-targeting
    /// movement counts, priority credit or not. Only prioritized buckets switch to residue-only.
    func testUnprioritizedGroupsStillCountEveryTargetingMovement() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()

        let unprioritized = service.majorMuscleGroups.filter {
            !service.isMajorMuscleGroupPrioritized(seed: $0.seed, blueprint: blueprint)
        }
        XCTAssertFalse(unprioritized.isEmpty, "Premise: this fixture leaves several groups un-prioritized.")

        for group in unprioritized {
            let aliases = service.normalizedGroupAliases(forSeed: group.seed)
            for exercise in menus.joined() {
                XCTAssertEqual(
                    service.exerciseCountsTowardMaintenance(
                        groupSeed: group.seed,
                        groupAliases: aliases,
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget,
                        blueprint: blueprint
                    ),
                    service.exerciseDirectlyTargets(
                        groupAliases: aliases,
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget
                    ),
                    "Un-prioritized group '\(group.label)' must be unchanged by the residue rule."
                )
            }
        }
    }

    // MARK: - The breadth cap now reaches residue

    /// `maintenanceSlotBudgetsAreFeasible` used to skip prioritized buckets outright, so nothing
    /// stopped a residue from seating more movements than its ceiling can dose. It now counts the
    /// residue on the same arithmetic: at a ceiling of 8 and a 3-set dose, three movements fit and
    /// a fourth does not.
    func testResidueBreadthIsCappedLikeAnyOtherMaintenanceGroup() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        let rearDelts: [(name: String, target: String)] = [
            ("Reverse Pec Deck", "Rear Deltoids"),
            ("Cable Face Pull", "Rear Deltoids"),
            ("Prone Incline Dumbbell Rear Delt Raise", "Rear Deltoids"),
            ("Dumbbell Rear Delt Fly", "Rear Deltoids")
        ]

        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: Array(rearDelts.prefix(3)),
                blueprint: blueprint
            ),
            "Three residue movements must still fit — 3/3/2 spends the whole ceiling."
        )
        XCTAssertFalse(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: rearDelts,
                blueprint: blueprint
            ),
            "A fourth residue movement is what forces every rear-delt slot back down to two sets."
        )
    }

    /// The rescue sweeps relax dose quality rather than ship a menu under five exercises, exactly
    /// as they already do for un-prioritized groups. Residue must not become a new way to
    /// dead-end menu planning.
    func testRescueSweepsMayStillOverfillResidueToAvoidAShortMenu() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        let rearDelts: [(name: String, target: String)] = [
            ("Reverse Pec Deck", "Rear Deltoids"),
            ("Cable Face Pull", "Rear Deltoids"),
            ("Prone Incline Dumbbell Rear Delt Raise", "Rear Deltoids"),
            ("Dumbbell Rear Delt Fly", "Rear Deltoids")
        ]

        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: rearDelts,
                blueprint: blueprint,
                meaningfulDoseSets: 2
            ),
            "The rescue path must still reach four residue movements rather than ship a short menu."
        )
    }

    // MARK: - Slots vs distinct names

    /// The counting mismatch that stranded a set. Both gates used to ask "how many distinct
    /// MOVEMENTS", but the allocator has to find a two-set floor for every SLOT, and the same
    /// movement programmed on two days is two slots. Four distinct lateral raises filling six
    /// slots read as "4 <= 5, fine" and then needed twelve sets from a budget of 11.5.
    ///
    /// Both counts are kept, because they answer different questions: distinct names decide how
    /// thinly weekly volume may be spread, slots decide whether every exposure is affordable.
    func testPriorityGateCountsSlotsNotDistinctNames() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        let lateralRaise = ("Cable Lateral Raise", "Lateral Deltoids")
        let behindTheBack = ("Behind-the-Back Cable Lateral Raise", "Lateral Deltoids")
        let machine = ("Machine Lateral Raise", "Lateral Deltoids")
        let leaning = ("Leaning Dumbbell Lateral Raise", "Lateral Deltoids")

        // The fixture's shape: FOUR distinct names, SIX slots. The old name-count read 4 and let
        // it through.
        let sixSlots: [(name: String, target: String)] = [
            lateralRaise, behindTheBack, leaning, machine, lateralRaise, machine
        ].map { (name: $0.0, target: $0.1) }
        XCTAssertEqual(Set(sixSlots.map { $0.name }).count, 4, "Premise: fewer names than slots.")

        XCTAssertFalse(
            service.priorityDoseBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: sixSlots,
                blueprint: blueprint
            ),
            "Six exposures need twelve sets at the floor; the priority cannot spend that much without hard-failing on volume."
        )

        XCTAssertTrue(
            service.priorityDoseBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: Array(sixSlots.prefix(5)),
                blueprint: blueprint
            ),
            "Five exposures at two sets is exactly what the budget can pay for and must stay legal."
        )
    }

    /// Same rule on the maintenance side, which had the same latent hole. Expressed with a
    /// repeated name so the two counts disagree: three distinct movements, five exposures.
    ///
    /// `selectedToday` carries all five rather than splitting them across `existingMenus` because
    /// the gate sums both lists — the arithmetic is identical and the intent stays readable.
    func testMaintenanceGateAlsoCountsSlotsNotDistinctNames() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        let triceps: [(name: String, target: String)] = [
            ("Rope Triceps Pressdown", "Triceps"),
            ("V-Bar Pressdown", "Triceps"),
            ("Overhead Cable Triceps Extension", "Triceps")
        ]
        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: triceps + [triceps[0]],
                blueprint: blueprint
            ),
            "Four exposures at two sets spends the whole ceiling of 8 and must stay legal."
        )
        XCTAssertFalse(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: triceps + [triceps[0], triceps[1]],
                blueprint: blueprint
            ),
            "Five exposures need ten sets against a recovery-tight ceiling of 8 — one would be stranded below the floor."
        )
    }

    /// The floor is 3 for an ANCHOR and 2 for everything else, so "slots x 2" under-counts what a
    /// heavy group actually costs. Three squat-pattern anchors need nine sets against a
    /// recovery-tight ceiling of eight; a flat two-set assumption reads that as six and admits a
    /// menu one of whose exposures can never be dosed — the same stranding as the lateral raise,
    /// one role up. The gates sum the real floors.
    ///
    /// Discriminating by construction: all three cases below hold distinct names at or under the
    /// breadth cap of 3 and slot COUNT at or under 4, so neither the name check nor a flat
    /// slots-times-two check could tell them apart. Only the summed floors can.
    func testAffordabilityUsesRealRoleFloorsNotATwoSetAssumption() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        let anchor = 3, other = 2
        XCTAssertEqual(service.minimumSetFloor(forExerciseName: "Back Squat", muscleTarget: "Quads"), anchor)
        XCTAssertEqual(service.minimumSetFloor(forExerciseName: "Front Squat", muscleTarget: "Quads"), anchor)
        XCTAssertEqual(service.minimumSetFloor(forExerciseName: "Trap Bar Deadlift", muscleTarget: "Quads"), anchor)
        XCTAssertEqual(service.minimumSetFloor(forExerciseName: "Leg Press", muscleTarget: "Quads"), other)
        XCTAssertEqual(service.minimumSetFloor(forExerciseName: "Machine Leg Extension", muscleTarget: "Quads"), other)

        // 3 + 2 + 2 = 7 against a ceiling of 8.
        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: [
                    ("Back Squat", "Quads"),
                    ("Leg Press", "Quads"),
                    ("Machine Leg Extension", "Quads")
                ],
                blueprint: blueprint
            ),
            "One anchor plus two lighter movements costs seven sets and fits."
        )

        // 3 + 3 + 3 = 9 against a ceiling of 8. Three slots, three names — invisible to both older
        // checks.
        XCTAssertFalse(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: [
                    ("Back Squat", "Quads"),
                    ("Front Squat", "Quads"),
                    ("Trap Bar Deadlift", "Quads")
                ],
                blueprint: blueprint
            ),
            "Three anchors need nine sets against a recovery-tight ceiling of eight — one could not reach its floor."
        )
    }

    /// A single exposure must never be rejected for costing more than the budget, or a group whose
    /// only viable catalog entry is an anchor could not be trained at all. The affordability rule
    /// is about sharing a budget, not about vetoing the first movement.
    func testALoneAnchorExposureIsAlwaysLegal() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: [("Back Squat", "Quads")],
                blueprint: blueprint
            ),
            "One anchor is always allowed whatever it costs."
        )
    }

    /// The slot floor must relax in the last-resort sweeps exactly as the breadth cap does, or it
    /// becomes a new way to dead-end menu planning — trading a warning for a hard failure.
    func testSlotFloorRelaxesInRescueSweeps() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        let triceps: [(name: String, target: String)] = [
            ("Rope Triceps Pressdown", "Triceps"),
            ("V-Bar Pressdown", "Triceps"),
            ("Overhead Cable Triceps Extension", "Triceps")
        ]
        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: triceps + [triceps[0], triceps[1]],
                blueprint: blueprint,
                meaningfulDoseSets: 2
            ),
            "A short menu is a hard failure and outranks dose hygiene; the rescue path must still get through."
        )
    }

    // MARK: - Hammer curls counted as nothing at all

    /// A second orphan of the same family, found while sweeping for the first. Hammer curls carry
    /// `primaryAreas: ["Brachialis"]`, and "Brachialis" appeared in no major muscle group's alias
    /// set — only the broad "arms" area listed it. So a hammer curl drew no maintenance funding,
    /// debited no weekly ceiling, and did not satisfy BASE-001: a week could program four sets of
    /// hammer curls and still be told the Biceps group received zero direct sets.
    func testHammerCurlsCountAsDirectBicepsWork() {
        let aliases = service.normalizedGroupAliases(forSeed: "biceps")

        for name in ["Dumbbell Hammer Curl", "Cable Hammer Curl"] {
            XCTAssertTrue(
                service.exerciseDirectlyTargets(
                    groupAliases: aliases,
                    exerciseName: name,
                    muscleTarget: "Brachialis"
                ),
                "'\(name)' is loaded elbow flexion and must debit the Biceps ledger."
            )
        }
    }

    /// The credit has to reach the priority ledger too, not just the maintenance one, or a Biceps
    /// priority still reads a hammer-curl week as unfunded.
    func testHammerCurlsEarnDirectCreditTowardABicepsPriority() {
        let probe = WorkoutExerciseResponse(
            exerciseName: "Dumbbell Hammer Curl",
            sets: 3,
            reps: "8-12",
            tempo: "",
            restSeconds: 90,
            notes: "",
            muscleTarget: "Brachialis"
        )

        XCTAssertEqual(service.directSetCredit(for: probe, area: "Biceps"), 3)
    }

    /// Widening the Biceps aliases must not leak into a neighbouring group. Triceps in particular
    /// shares the "Arms" parent, and an over-wide alias set there would let pressdowns satisfy a
    /// biceps target.
    func testBrachialisDoesNotLeakIntoOtherGroups() {
        for seed in ["triceps", "shoulders", "back", "chest"] {
            XCTAssertFalse(
                service.normalizedGroupAliases(forSeed: seed)
                    .contains(service.normalizedPriorityText("Brachialis")),
                "'\(seed)' must not claim brachialis work."
            )
        }
    }

    /// Every primary area the exercise catalog actually uses must belong to some major muscle
    /// group's ledger, or movements built on it are invisible to funding, ceilings and BASE-001 —
    /// which is precisely how the brachialis orphan survived.
    ///
    /// "Forearms" is the one remaining exception and is asserted as a KNOWN gap rather than
    /// quietly tolerated: closing it means adding a Forearms major group, which BASE-001 would
    /// then force into every single week. That is a programming decision for the owner, not a
    /// silent code change.
    func testEveryCatalogPrimaryAreaBelongsToSomeMajorGroupExceptForearms() {
        let ledgerAreas = service.majorMuscleGroups.reduce(into: Set<String>()) { result, group in
            result.formUnion(service.normalizedGroupAliases(forSeed: group.seed))
        }

        let catalogPrimaryAreas = [
            "Chest", "Upper Chest", "Back", "Lats", "Upper Back", "Mid Back",
            "Shoulders", "Lateral Deltoids", "Rear Deltoids", "Anterior Deltoids",
            "Biceps", "Brachialis", "Triceps", "Quads", "Hamstrings", "Glutes",
            "Quads/Glutes", "Posterior Chain", "Calves",
            "Core/Abs", "Abs", "Lower Abs", "Anterior Core", "Obliques"
        ]

        for area in catalogPrimaryAreas {
            XCTAssertTrue(
                ledgerAreas.contains(service.normalizedPriorityText(area)),
                "Catalog primary area '\(area)' belongs to no major muscle group — every movement built on it is invisible to funding and ceilings."
            )
        }

        XCTAssertFalse(
            ledgerAreas.contains(service.normalizedPriorityText("Forearms")),
            "Forearms now has a ledger. That is a real improvement, but BASE-001 will start demanding direct forearm work every week — update this test deliberately, with the owner's sign-off."
        )
    }
}
