import Foundation
import XCTest
@testable import Transform

/// The 2026-09-08 Week 1 bundle. The validator reported seven findings; FIVE of them were one
/// defect, and it was a defect this repo had already found once and fixed in only one of the
/// places it lived.
///
/// `sanitizedPreferredStyles` deduplicates by CANONICAL style but returns the first literal
/// spelling it saw. With the model supplying "Upper" and the Core/Abs catalogue list
/// `["Legs", "Lower", "Upper"]` behind it, the seed is `["Upper"] + ["Legs", "Lower", "Upper"]`
/// and the result is `["Upper", "Legs"]` — the spelling the owner's blueprint actually printed.
/// (A pure fallback ships `["Legs", "Upper"]`; either way a lower-body day arrives as "Legs".)
/// Day plans carry the canonical "Lower". Eight planner sites asked "does this allocation belong
/// on this day's style"; three folded both sides, four compared them raw, and one folded only the
/// day. For those five, every lower-body day in the week was invisible to a priority spelled
/// "Legs".
///
/// What that produced on the owner's actual week:
///   - `companionSupportAreas` left Core/Abs off the Lower day, so it was never seeded there.
///   - `enforcePriorityDirectSetFeasibility` saw ONE compatible day and stacked BOTH of Core/Abs'
///     exercise slots onto it.
///   - A non-focus session may carry only `maxPerSessionDirectSets` = 3 direct sets for that
///     allocation, and two `.core` movements need 2 + 2 = 4 to clear `minimumSetFloor`. So the
///     allocator's floor pass hit the per-session cap in `canAddSet`, returned false, and Cable
///     Crunch shipped at ONE SET.
///   - Findings 2-5 (1/2 exposure days, 1/2 meaningful exposures, 3/6 direct sets, 3/8.5 weighted
///     stimulus) are the same stacking seen from the weekly ledger instead of the daily one.
///
/// Both halves are pinned here, and the second is narrower than it sounds. The style comparison
/// is now spelling-independent everywhere. The funding rule governs
/// `enforcePriorityDirectSetFeasibility`, the pass that TOPS UP a priority's exposures; it does
/// not govern the base menu, whose focus slots come from `focusExerciseTargetCount` and can still
/// reach three per session with no reference to the per-session direct cap. A session can
/// therefore still be handed more slots than it can fund. What is fixed is the pass that was
/// doing it on the owner's week.
@MainActor
final class PriorityStyleAndSlotCapacityTests: XCTestCase {

    private let service = ClaudeService.shared

    /// Core/Abs exactly as the owner's week produced it: the literal "Legs" spelling, a
    /// 6-set / 2-exposure target, and the 3-set non-focus session cap that the two-slot stack
    /// could not fund.
    private func coreAbsAllocation(
        preferredStyles: [String] = ["Upper", "Legs"],
        targetFrequency: Int = 2,
        maxPerSessionDirectSets: Double = 3,
        maxFocusSessionDirectSets: Double = 5
    ) -> ClaudeService.BlueprintPriorityAllocation {
        ClaudeService.BlueprintPriorityAllocation(
            area: "Core/Abs",
            priorityLevel: "Medium",
            rationale: "",
            targetFrequency: targetFrequency,
            targetExerciseSlots: 2,
            directSetTarget: 6,
            weightedStimulusTarget: 8.5,
            maxPerSessionDirectSets: maxPerSessionDirectSets,
            maxFocusSessionDirectSets: maxFocusSessionDirectSets,
            preferredStyles: preferredStyles,
            preferredMovementPatterns: [],
            volumeBias: "Moderate",
            directWorkBias: "Maintenance"
        )
    }

    private func dayPlan(_ index: Int, style: String) -> ClaudeService.BlueprintDayPlan {
        ClaudeService.BlueprintDayPlan(
            dayIndex: index,
            style: style,
            focusArea: nil,
            supportAreas: [],
            targetFatigueCap: 99,
            targetSessionMinutes: 75,
            targetPrioritySlots: 1,
            emphasisPatterns: [],
            isRestDay: false
        )
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

    // MARK: - 1. Style compatibility is about the session, not the spelling

    /// The single predicate every other site now delegates to. "Legs" and "Lower" are one
    /// session; either spelling on either side must match.
    func testStyleMatchingIsIndependentOfSpellingOnBothSides() {
        let legsSpelled = coreAbsAllocation(preferredStyles: ["Upper", "Legs"])
        let lowerSpelled = coreAbsAllocation(preferredStyles: ["Upper", "Lower"])

        XCTAssertTrue(
            service.allocationPrefersStyle(legsSpelled, "Lower"),
            "A priority whose style list reads 'Legs' must match a day whose style reads 'Lower'"
        )
        XCTAssertTrue(service.allocationPrefersStyle(legsSpelled, "Legs"))
        XCTAssertTrue(service.allocationPrefersStyle(lowerSpelled, "Legs"))
        XCTAssertTrue(service.allocationPrefersStyle(lowerSpelled, "Lower"))

        // The fix widens one equivalence; it does not make everything match everything.
        XCTAssertFalse(service.allocationPrefersStyle(legsSpelled, "Pull"))
        XCTAssertFalse(service.allocationPrefersStyle(legsSpelled, "Arms"))
        XCTAssertFalse(service.allocationPrefersStyle(legsSpelled, "Push"))
    }

    /// `companionSupportAreas` is the site that decided the owner's menu. Day 4 was a Lower day
    /// with no core work at all, and this is why: the filter could not see that Core/Abs belonged
    /// there, so the day was seeded without it and both core slots went to Day 1.
    func testALowerDayListsALegsSpelledPriorityAsSupport() {
        let core = coreAbsAllocation()

        let support = service.companionSupportAreas(
            for: "Lower",
            focus: nil,
            allocations: [core],
            usageCounts: [:],
            weeklyStyles: ["Upper", "Push", "Lower", "Arms", "Pull"]
        )

        XCTAssertEqual(
            support,
            ["Core/Abs"],
            "A Lower day must be able to carry a priority whose style list spells that session 'Legs'"
        )
    }

    /// Same comparison, the other consumer: a Lower day could not even nominate Core/Abs as its
    /// focus, which is why the owner's Day 4 printed "focus Balanced".
    func testALowerDayCanTakeALegsSpelledPriorityAsItsFocus() {
        let core = coreAbsAllocation()

        XCTAssertEqual(
            service.blueprintFocusAllocation(
                for: "Lower",
                allocations: [core],
                usageCounts: [:]
            )?.area,
            "Core/Abs"
        )
        // Still refuses a priority that genuinely does not belong on the day.
        XCTAssertNil(
            service.blueprintFocusAllocation(
                for: "Pull",
                allocations: [core],
                usageCounts: [:]
            )
        )
    }

    /// Split selection reads the same predicate. A demand score that depended on which of two
    /// synonyms an allocation happened to carry could drop the very day a priority needed.
    func testStyleDemandIsScoredIdenticallyForLegsAndLower() {
        let core = coreAbsAllocation()

        let legsDemand = service.styleDemandScore(for: "Legs", allocations: [core])
        let lowerDemand = service.styleDemandScore(for: "Lower", allocations: [core])

        XCTAssertEqual(legsDemand, lowerDemand, "Two spellings of one session must score the same")
        XCTAssertGreaterThan(lowerDemand, 0, "A Legs-spelled priority must register demand for a Lower day")
        XCTAssertEqual(service.styleDemandScore(for: "Pull", allocations: [core]), 0)
    }

    // MARK: - 2. A session may not hold slots it is not allowed to fund

    /// The arithmetic that stranded Cable Crunch at one set, stated as a rule.
    ///
    /// Three earlier attempts at this defect all searched for another SET to spend and were each
    /// blocked by a ceiling that was already spent. The set was never available. The second slot
    /// was the thing that should not have existed.
    func testASessionNeverHoldsMoreSlotsThanItsCapCanFundToTheFloor() {
        // The owner's case verbatim: 3 direct sets available, two `.core` movements needing two
        // sets each. One slot, not two.
        XCTAssertEqual(
            service.fundablePrioritySlotsPerSession(
                for: coreAbsAllocation(),
                isFocusDay: false
            ),
            1,
            "A 3-set session cap cannot fund two movements to a 2-set floor"
        )

        // The same priority on its own focus day may carry 5 sets, which funds two.
        XCTAssertEqual(
            service.fundablePrioritySlotsPerSession(
                for: coreAbsAllocation(),
                isFocusDay: true
            ),
            2
        )

        // A 4-set cap is exactly two floors, so two slots stay legal — the guard must not
        // over-restrict the sessions that were always fine.
        XCTAssertEqual(
            service.fundablePrioritySlotsPerSession(
                for: coreAbsAllocation(maxPerSessionDirectSets: 4),
                isFocusDay: false
            ),
            2
        )

        // Two per session stays the ceiling however generous the cap reads.
        XCTAssertEqual(
            service.fundablePrioritySlotsPerSession(
                for: coreAbsAllocation(maxPerSessionDirectSets: 12),
                isFocusDay: false
            ),
            2
        )

        // A cap too small for even one floor still yields one: a priority with a real target is
        // never left with zero placeable slots, and the allocator owns the dose from there.
        XCTAssertEqual(
            service.fundablePrioritySlotsPerSession(
                for: coreAbsAllocation(maxPerSessionDirectSets: 1),
                isFocusDay: false
            ),
            1
        )
    }

    /// End-to-end proof of the exact 2026-09-08 failure: a Core/Abs allocation spelled its lower
    /// preference "Legs", while the day plan called the same session "Lower". The feasibility
    /// pass used to stack two core slots on Upper, and the allocator could fund only 1 + 2 sets
    /// under that day's three-set cap. The passes must now distribute one slot per compatible day
    /// before set allocation begins.
    func testFeasibilityPassDistributesEverySlotBeforeTheAllocatorFundsSets() {
        let allocation = coreAbsAllocation()
        let intent = service.fallbackTrainingIntentPlan(from: ["Core/Abs"])
        let blueprint = ClaudeService.ProgramBlueprint(
            evidenceVersion: "test",
            splitRecommendation: "Upper / Lower",
            weeklyTrainingDays: 2,
            priorityAllocations: [allocation],
            dayPlans: [dayPlan(1, style: "Upper"), dayPlan(2, style: "Lower")],
            topLeverageChange: "",
            posturalFocus: "(none)",
            injuryRiskFocus: "(none)",
            programmingNotes: [],
            calibration: service.neutralCalibrationProfile()
        )
        let seededMenus = [
            [slot("Cable Crunch", "Abs")],
            [slot("Back Squat", "Quads")]
        ]

        let feasibleMenus = service.enforcePriorityDirectSetFeasibility(
            seededMenus,
            blueprint: blueprint,
            trainingIntent: intent,
            weekNumber: 1,
            avoidedExercises: []
        )
        let coreSlotsByDay = feasibleMenus.map { menu in
            menu.filter {
                service.focusStimulusKind(
                    exerciseName: $0.exerciseName,
                    muscleTarget: $0.muscleTarget,
                    focusArea: "Core/Abs"
                ) == .prime
            }.count
        }
        XCTAssertEqual(coreSlotsByDay, [1, 1], "Core work must be spread before dosage is funded")

        let allocatedMenus = service.allocateWeeklySetPrescription(
            feasibleMenus,
            blueprint: blueprint,
            weekNumber: 1
        )
        let coreSets = allocatedMenus.joined().filter {
            service.focusStimulusKind(
                exerciseName: $0.exerciseName,
                muscleTarget: $0.muscleTarget,
                focusArea: "Core/Abs"
            ) == .prime
        }.map(\.prescribedSets).sorted()

        XCTAssertEqual(coreSets, [3, 3])
        XCTAssertTrue(
            allocatedMenus.joined().allSatisfy {
                $0.prescribedSets >= service.minimumSetFloor(
                    forExerciseName: $0.exerciseName,
                    muscleTarget: $0.muscleTarget
                )
            },
            "No planned movement may survive below its role's useful set floor"
        )
    }

    // MARK: - 3. The maintenance-floor finding counts its movements

    /// The finding used to assert its own cause — "short of exercise SLOTS, not sets" — without
    /// ever counting the slots, and on the owner's week that assertion was false. `Calves` shipped
    /// 2 sets from ONE Standing Calf Raise, an `.accessory` whose week-1 role default is 3, so the
    /// group was short of a SET a day budget refused, not short of an exercise. Nothing downstream
    /// acts on this finding, so its wording is the whole of its value; this pins that the number
    /// it now reports is real.
    func testTheMovementCountBehindAMaintenanceShortfallIsCountedNotAssumed() {
        let aliases = service.normalizedGroupAliases(forSeed: "calf")

        func week(_ exercises: [(String, String, Int)]) -> [WorkoutDayResponse] {
            (1...7).map { dayNumber in
                WorkoutDayResponse(
                    dayNumber: dayNumber,
                    dayName: dayNumber == 1 ? "Lower" : "Rest",
                    muscleGroups: "",
                    isRestDay: dayNumber != 1,
                    notes: "",
                    exercises: dayNumber == 1 ? exercises.map {
                        WorkoutExerciseResponse(
                            exerciseName: $0.0,
                            sets: $0.2,
                            reps: "",
                            tempo: "",
                            restSeconds: 0,
                            notes: "",
                            muscleTarget: $0.1
                        )
                    } : []
                )
            }
        }

        // The owner's week: one calf movement, two sets.
        XCTAssertEqual(
            service.weeklyDirectMovements(
                forGroupAliases: aliases,
                days: week([
                    ("Back Squat", "Quads", 3),
                    ("Standing Calf Raise", "Calves", 2)
                ])
            ),
            1,
            "One calf movement is one movement, however many sets it carries"
        )

        // Two distinct calf movements is a genuine slot count of two, and the squat still must
        // not be counted as calf work.
        XCTAssertEqual(
            service.weeklyDirectMovements(
                forGroupAliases: aliases,
                days: week([
                    ("Back Squat", "Quads", 3),
                    ("Standing Calf Raise", "Calves", 2),
                    ("Seated Calf Raise", "Calves", 2)
                ])
            ),
            2
        )

        // The same movement repeated is one SLOT, not two — the count is distinct movements, which
        // is the number the "needs another weekly exposure" repair is about.
        XCTAssertEqual(
            service.weeklyDirectMovements(
                forGroupAliases: aliases,
                days: week([
                    ("Standing Calf Raise", "Calves", 2),
                    ("Standing Calf Raise", "Calves", 2)
                ])
            ),
            1
        )

        XCTAssertEqual(
            service.weeklyDirectMovements(
                forGroupAliases: aliases,
                days: week([("Back Squat", "Quads", 3)])
            ),
            0,
            "A week with no calf work has no calf movements"
        )
    }
}
