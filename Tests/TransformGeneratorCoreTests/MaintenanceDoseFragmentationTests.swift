import Foundation
import XCTest
@testable import Transform

/// The owner generated a recovery-tight Week 1 and every quad, hamstring, glute, back and
/// triceps movement in it read `2×8-12`. That was not randomness and not a display bug: it was
/// arithmetic. `maintenanceSlotBudgetsAreFeasible` capped distinct movements per non-priority
/// muscle group at `maintenanceCeiling / 2` — 4 movements against a recovery-tight ceiling of 8 —
/// and the maintenance funding loop fills round-robin from a seed of one set, so four movements
/// land on exactly 2 sets apiece as the ceiling closes. The tell was calves: the only lower-body
/// group that drew fewer movements, and the only one that got 3 sets each.
///
/// Two hard sets is below a productive hypertrophy dose for a movement, and it is also too thin
/// for the app's own progression tracker to read a trend from. The divisor is now 3 (rounded up),
/// so the same ceiling admits 3 movements and the loop lands 3/3/2 — identical weekly total, two
/// movements at a real dose instead of none.
///
/// These tests replace the exact `menuSignature` snapshot that used to guard this fixture. The
/// snapshot moved with this change and could not be recomputed without a Swift toolchain; these
/// assert the PROPERTY the change was made for, which is a stronger guard than a brittle string
/// dump and does not need regenerating when an unrelated exercise is renamed.
@MainActor
final class MaintenanceDoseFragmentationTests: XCTestCase {

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

    /// Weekly sets per DISTINCT movement, for every non-priority major muscle group.
    ///
    /// Grouped by normalized exercise name to match `maintenanceSlotBudgetsAreFeasible`, which
    /// counts distinct names rather than slots — a movement programmed on two days is one movement
    /// carrying the sum of both doses, not two thin ones. Tuple members have no key paths in
    /// Swift, so these stay closures.
    private func maintenanceDoses(
        blueprint: ClaudeService.ProgramBlueprint,
        menus: [[ClaudeService.PreSelectedExercise]]
    ) -> [String: [Int]] {
        var byGroup: [String: [Int]] = [:]
        for group in service.majorMuscleGroups {
            guard !service.isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint) else { continue }
            let aliases = service.normalizedGroupAliases(forSeed: group.seed)
            var setsByMovement: [String: Int] = [:]
            for menu in menus {
                for exercise in menu where service.exerciseDirectlyTargets(
                    groupAliases: aliases,
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget
                ) {
                    let key = service.normalizeExerciseName(exercise.exerciseName)
                    setsByMovement[key, default: 0] += exercise.prescribedSets
                }
            }
            if !setsByMovement.isEmpty {
                byGroup[group.label] = setsByMovement.values.sorted()
            }
        }
        return byGroup
    }

    // MARK: - The reported symptom

    /// The exact thing the owner saw. A group trained by more than one movement must not have
    /// every one of those movements stuck below a real dose.
    func testNoMaintenanceGroupIsEntirelyFragmentedIntoTwoSetDoses() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()
        XCTAssertTrue(blueprint.calibration.recoveryConstrained, "Premise: this fixture is the recovery-tight case.")

        for (label, doses) in maintenanceDoses(blueprint: blueprint, menus: menus) where doses.count > 1 {
            XCTAssertTrue(
                doses.contains { $0 >= 3 },
                "'\(label)' is spread across \(doses.count) movements at \(doses) sets — every one below a productive dose."
            )
        }
    }

    /// The breadth cap itself, stated as the number it now produces.
    func testRecoveryTightCeilingAdmitsThreeMovementsNotFour() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()

        for (label, doses) in maintenanceDoses(blueprint: blueprint, menus: menus) {
            XCTAssertLessThanOrEqual(
                doses.count, 3,
                "'\(label)' holds \(doses.count) distinct movements; a ceiling of 8 cannot dose more than 3 meaningfully."
            )
        }
    }

    /// The change must not have bought dose quality by quietly spending more total volume — the
    /// maintenance ceiling is a recovery guard and still binds.
    func testWeeklyMaintenanceVolumeStaysUnderTheRecoveryCeiling() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()

        for (label, doses) in maintenanceDoses(blueprint: blueprint, menus: menus) {
            XCTAssertLessThanOrEqual(
                doses.reduce(0, +), 8,
                "'\(label)' totals \(doses.reduce(0, +)) weekly sets against a recovery-tight ceiling of 8."
            )
        }
    }

    // MARK: - The gate in isolation

    /// Guards the cap directly so the arithmetic cannot drift back to a two-set divisor even if
    /// the fixture's exercise mix changes. Four distinct triceps movements were feasible before
    /// this change and must not be now; three must still fit.
    func testMaintenanceSlotGateRejectsAFourthMovementWhenRecoveryIsTight() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        let triceps: [(name: String, target: String)] = [
            ("Rope Triceps Pressdown", "Triceps"),
            ("V-Bar Pressdown", "Triceps"),
            ("Overhead Cable Triceps Extension", "Triceps"),
            ("Cable Kickback", "Triceps")
        ]

        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: Array(triceps.prefix(3)),
                blueprint: blueprint
            ),
            "Three movements must still fit — 3/3/2 spends the whole ceiling."
        )
        XCTAssertFalse(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: triceps,
                blueprint: blueprint
            ),
            "A fourth movement is what forced every triceps slot down to 2 sets."
        )
    }

    /// Dose quality must never be the reason a day menu ends up too short to ship. A menu under
    /// five exercises is a validator hard failure and a deterministic dead-end, so the last-resort
    /// sweeps drop to the old two-set dose — reproducing the previous cap exactly — just as they
    /// already drop the pattern cap and the priority-dose gate.
    func testRescueSweepsMayStillTakeAFourthMovementToAvoidAShortMenu() throws {
        let (blueprint, _) = try fixtureBlueprintAndMenus()

        let triceps: [(name: String, target: String)] = [
            ("Rope Triceps Pressdown", "Triceps"),
            ("V-Bar Pressdown", "Triceps"),
            ("Overhead Cable Triceps Extension", "Triceps"),
            ("Cable Kickback", "Triceps")
        ]

        XCTAssertTrue(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: triceps,
                blueprint: blueprint,
                meaningfulDoseSets: 2
            ),
            "The rescue path must still be able to reach four movements rather than ship a short menu."
        )
        XCTAssertFalse(
            service.maintenanceSlotBudgetsAreFeasible(
                existingMenus: [],
                selectedToday: triceps + [("Cable Triceps Pressdown", "Triceps")],
                blueprint: blueprint,
                meaningfulDoseSets: 2
            ),
            "Relaxing the dose must reproduce the OLD cap of 4, not remove the cap."
        )
    }

    /// Priority-FUNDED work is deliberately exempt from this gate — it has its own dose budget in
    /// `priorityDoseBudgetsAreFeasible`. If the maintenance cap started applying to it, it would
    /// starve the very muscles the analysis asked to emphasise.
    ///
    /// The exemption is per MOVEMENT, not per bucket. It used to be per bucket, and that is what
    /// starved the rear delts: a Lateral Deltoids priority marked the whole "shoulders" bucket
    /// prioritized, so rear-delt work — which no priority allocation pays for — escaped this cap
    /// AND the allocator's maintenance funding, and shipped at the bare two-set floor. See
    /// `ResidueMuscleDoseTests`. This test now pins the narrower, correct exemption.
    ///
    /// Asserted against the REAL gate, not against `maintenanceDoses`. An earlier version checked
    /// that prioritized groups were absent from that helper's output — which the helper guarantees
    /// by construction, since it skips prioritized groups before writing anything. That assertion
    /// could not fail and proved nothing.
    func testPriorityFundedMovementsAreExemptFromTheMaintenanceBreadthCap() throws {
        let (blueprint, menus) = try fixtureBlueprintAndMenus()

        let prioritized = service.majorMuscleGroups.filter {
            service.isMajorMuscleGroupPrioritized(seed: $0.seed, blueprint: blueprint)
        }
        XCTAssertFalse(
            prioritized.isEmpty,
            "Premise: this fixture prioritizes Upper Chest / Lateral Deltoids / Core-Abs, so at least one major group must read as prioritized."
        )

        // Only a group carrying MORE priority-funded movements than the cap allows can demonstrate
        // the exemption. Skip loudly rather than pass vacuously if the fixture has none.
        var provedExemption = false
        for group in prioritized {
            let aliases = service.normalizedGroupAliases(forSeed: group.seed)
            var movements: [(name: String, target: String)] = []
            var seen = Set<String>()
            for exercise in menus.joined() where service.exerciseDirectlyTargets(
                groupAliases: aliases,
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            ) {
                // Residue is NOT exempt any more, so it cannot be part of this proof.
                guard service.earnsDirectPriorityCredit(
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget,
                    blueprint: blueprint
                ) else { continue }
                let key = service.normalizeExerciseName(exercise.exerciseName)
                guard seen.insert(key).inserted else { continue }
                movements.append((name: exercise.exerciseName, target: exercise.muscleTarget))
            }
            guard movements.count > 3 else { continue }

            provedExemption = true
            XCTAssertTrue(
                service.maintenanceSlotBudgetsAreFeasible(
                    existingMenus: [],
                    selectedToday: movements,
                    blueprint: blueprint
                ),
                "'\(group.label)' carries \(movements.count) priority-funded movements — the maintenance cap must not apply to work a priority budget already pays for."
            )
        }

        try XCTSkipUnless(
            provedExemption,
            "No prioritized group in this fixture exceeded the 3-movement cap with priority-funded movements alone, so the exemption could not be demonstrated."
        )
    }

    // MARK: - The cap arithmetic, both recovery states

    /// The divisor change affects BOTH ceilings, not only the recovery-tight one the owner hit:
    /// 8 goes 4->3 and 10 goes 5->4. That is intended — two sets on a movement is thin whether or
    /// not recovery is constrained — but it is a real behaviour change for normal-recovery weeks
    /// too, so it is pinned here rather than left for the recovery-tight fixture to imply.
    ///
    /// Expressed as the arithmetic itself because the normal-recovery branch has no fixture: the
    /// bundled regression fixture is deliberately the recovery-constrained case.
    func testBreadthCapArithmeticForBothCeilingsAndBothDoses() {
        func maxSlots(ceiling: Int, dose: Int) -> Int { (ceiling + dose - 1) / dose }

        // Strict dose (normal selection): one fewer movement in both recovery states.
        XCTAssertEqual(maxSlots(ceiling: 8, dose: 3), 3, "Recovery-tight: 3 movements land 3/3/2.")
        XCTAssertEqual(maxSlots(ceiling: 10, dose: 3), 4, "Normal recovery: 4 movements land 3/3/2/2.")

        // Relaxed dose (last-resort short-menu sweeps): must reproduce the PREVIOUS caps exactly,
        // so tightening dose quality can never be why a day menu is too short to ship.
        XCTAssertEqual(maxSlots(ceiling: 8, dose: 2), 8 / 2)
        XCTAssertEqual(maxSlots(ceiling: 10, dose: 2), 10 / 2)
    }
}
