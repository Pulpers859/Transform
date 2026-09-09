import Foundation
import XCTest
@testable import Transform

/// The 2026-09-08 Week 1 bundle. The validator reported seven findings; FIVE of them were one
/// defect, and it was a defect this repo had already found once and fixed in only one of the
/// places it lived.
///
/// `sanitizedPreferredStyles` deduplicates by CANONICAL style but returns the first literal
/// spelling it saw, so a Core/Abs allocation falling back to the catalogue list
/// `["Legs", "Lower", "Upper"]` ships `["Upper", "Legs"]`. Day plans carry the canonical "Lower".
/// Eight planner sites asked "does this allocation belong on this day's style"; three folded both
/// sides and five compared them raw. For the raw five, every lower-body day in the week was
/// invisible to a priority spelled "Legs".
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
/// Both halves are pinned here: the comparison is now spelling-independent everywhere, and a
/// session is never handed more slots for a priority than it is allowed to fund.
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

    // MARK: - 3. A day is admitted on what it must deliver, not on one set each

    /// `seededDayFitsItsBudgets` decides whether a session can take another movement, and it used
    /// to ask that question with every movement at ONE SET. One set is not what the day is
    /// obliged to deliver: `minimumSetFloor` is, and the reduction loops and the validator both
    /// treat it as the number no movement may ship below. A day that fits at one set each and not
    /// at floors was admitted on a promise it could not keep, and whichever movement lost the
    /// allocator's ranking shipped at one set.
    ///
    /// Built from the estimator itself rather than from hardcoded minutes, so it measures the
    /// change instead of restating it: it first proves the two projections genuinely differ, then
    /// pins the gate against each.
    func testASessionIsBudgetedAtRoleFloorsRatherThanAtOneSetEach() {
        let existing = [
            ("Back Squat", "Quads"),
            ("Barbell Romanian Deadlift", "Hamstrings"),
            ("Leg Press", "Quads")
        ]
        let candidate = (name: "Barbell Hip Thrust", target: "Glutes")
        let everyMovement = existing + [(candidate.name, candidate.target)]

        func projectedMinutes(atRoleFloor: Bool) -> Int {
            let exercises = everyMovement.map { item -> WorkoutExerciseResponse in
                WorkoutExerciseResponse(
                    exerciseName: item.0,
                    sets: atRoleFloor
                        ? service.minimumSetFloor(forExerciseName: item.0, muscleTarget: item.1)
                        : 1,
                    reps: "",
                    tempo: "",
                    restSeconds: service.proceduralRestSeconds(for: item.0, muscleTarget: item.1),
                    notes: "",
                    muscleTarget: item.1
                )
            }
            return service.estimatedSessionMinutes(
                for: service.proceduralTrainingDay(from: exercises)
            )
        }

        let oneSetMinutes = projectedMinutes(atRoleFloor: false)
        let floorMinutes = projectedMinutes(atRoleFloor: true)

        // If these were equal the rest of the test would prove nothing.
        XCTAssertGreaterThan(
            floorMinutes,
            oneSetMinutes,
            "Every role floor is at least two sets, so the floor projection must cost more clock than one set each"
        )

        let menu = existing.map { slot($0.0, $0.1) }

        // A budget that the one-set projection clears and the floor projection does not. The gate
        // has a +3 tolerance, so subtract past it.
        let tooTight = floorMinutes - 4
        XCTAssertGreaterThanOrEqual(
            tooTight + 3,
            oneSetMinutes,
            "This cap must be one the OLD one-set projection would have accepted, or the test is not measuring the change"
        )
        XCTAssertFalse(
            service.seededDayFitsItsBudgets(
                adding: candidate,
                to: menu,
                plan: dayPlan(3, sessionMinutes: tooTight),
                weekNumber: 1
            ),
            "A day that only fits while every movement sits at one set must not accept another movement"
        )

        // Real room is still real room; the gate must not simply refuse everything.
        XCTAssertTrue(
            service.seededDayFitsItsBudgets(
                adding: candidate,
                to: menu,
                plan: dayPlan(3, sessionMinutes: floorMinutes),
                weekNumber: 1
            ),
            "A day whose budget covers every movement at its floor must still accept it"
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

    private func dayPlan(_ index: Int, sessionMinutes: Int) -> ClaudeService.BlueprintDayPlan {
        ClaudeService.BlueprintDayPlan(
            dayIndex: index,
            style: "Lower",
            focusArea: nil,
            supportAreas: [],
            targetFatigueCap: 99,
            targetSessionMinutes: sessionMinutes,
            targetPrioritySlots: 1,
            emphasisPatterns: [],
            isRestDay: false
        )
    }
}
