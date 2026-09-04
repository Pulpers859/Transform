import Foundation
import XCTest
@testable import Transform

/// The weekly split is chosen by `styleDemandScore`, which reads ONLY the priority allocations.
/// A style no priority asks for scores exactly zero. With six allowed styles and four or five
/// training days the ranked list is truncated to fit, and the zero-demand style is what falls off.
///
/// For a lifter whose priorities are all pressing or core areas — a very ordinary shape — that
/// zero-demand style is "Pull", and the week ships with no pulling day at all. An audited Week 1
/// with priorities Upper Chest / Lateral Deltoids / Core-Abs produced Upper, Legs, Push, Lower,
/// Arms: eighteen chest sets, three back sets (one isolation lat movement), and zero rear-delt
/// sets, for a lifter whose analysis explicitly asked for continued upper-back and rear-delt
/// emphasis and who reported left anterior shoulder pain.
///
/// Nothing downstream could catch it. BASE-001 is satisfied by ONE directly targeting movement
/// anywhere in the week, and it skips prioritized groups, so a lateral-raise priority hides the
/// entire shoulder bucket — rear delts included. There is no pressing-to-pulling balance rule
/// anywhere in the generator.
@MainActor
final class PullingDayPresenceTests: XCTestCase {

    private let service = ClaudeService.shared

    private func allocation(
        area: String,
        priorityLevel: String,
        targetFrequency: Int,
        targetExerciseSlots: Int,
        directSetTarget: Double,
        maxPerSessionDirectSets: Double,
        maxFocusSessionDirectSets: Double,
        preferredStyles: [String]
    ) -> ClaudeService.BlueprintPriorityAllocation {
        ClaudeService.BlueprintPriorityAllocation(
            area: area,
            priorityLevel: priorityLevel,
            rationale: "",
            targetFrequency: targetFrequency,
            targetExerciseSlots: targetExerciseSlots,
            directSetTarget: directSetTarget,
            weightedStimulusTarget: directSetTarget,
            maxPerSessionDirectSets: maxPerSessionDirectSets,
            maxFocusSessionDirectSets: maxFocusSessionDirectSets,
            preferredStyles: preferredStyles,
            preferredMovementPatterns: [],
            volumeBias: "High",
            directWorkBias: "Direct emphasis"
        )
    }

    /// The exact priority shape from the audited bundle.
    private var auditedAllocations: [ClaudeService.BlueprintPriorityAllocation] {
        [
            allocation(
                area: "Upper Chest",
                priorityLevel: "High",
                targetFrequency: 2,
                targetExerciseSlots: 3,
                directSetTarget: 10,
                maxPerSessionDirectSets: 5,
                maxFocusSessionDirectSets: 8,
                preferredStyles: ["Push", "Upper"]
            ),
            allocation(
                area: "Lateral Deltoids",
                priorityLevel: "High",
                targetFrequency: 3,
                targetExerciseSlots: 3,
                directSetTarget: 10,
                maxPerSessionDirectSets: 4,
                maxFocusSessionDirectSets: 8,
                preferredStyles: ["Push", "Upper", "Arms"]
            ),
            allocation(
                area: "Core/Abs",
                priorityLevel: "Medium",
                targetFrequency: 2,
                targetExerciseSlots: 2,
                directSetTarget: 6,
                maxPerSessionDirectSets: 3,
                maxFocusSessionDirectSets: 5,
                preferredStyles: ["Upper", "Legs"]
            )
        ]
    }

    // MARK: - The reported defect

    func testFiveDayWeekKeepsAPullingDayWhenNoPriorityIsAPullingArea() {
        let styles = service.orderedBlueprintStyles(for: auditedAllocations, trainingDays: 5)
        XCTAssertTrue(
            styles.contains("Pull"),
            "A five-day week with no pulling priority shipped no pulling day at all: \(styles)"
        )
        XCTAssertEqual(styles.count, 5, "The week must still be exactly five training days: \(styles)")
    }

    func testFourDayWeekKeepsAPullingDayToo() {
        let styles = service.orderedBlueprintStyles(for: auditedAllocations, trainingDays: 4)
        XCTAssertTrue(
            styles.contains("Pull"),
            "A four-day week dropped the pulling day: \(styles)"
        )
        XCTAssertEqual(styles.count, 4, "The week must still be exactly four training days: \(styles)")
    }

    // MARK: - The donor must not be chosen by demand alone

    /// "Legs" carries the lowest demand of the displaceable styles, so a plain lowest-demand swap
    /// takes it — and Core/Abs, whose only other compatible style is "Upper", is then left with a
    /// single day. One day at a focus cap of five cannot carry a six-set weekly target, so the
    /// week trades a back hole for a core hole. "Arms" is the only donor that strands nobody.
    func testThePullingDayDisplacesArmsRatherThanLegs() {
        let styles = service.orderedBlueprintStyles(for: auditedAllocations, trainingDays: 5)
        XCTAssertTrue(
            styles.contains("Legs"),
            "Core/Abs lost the only day besides Upper that it can be trained on: \(styles)"
        )
        XCTAssertFalse(
            styles.contains("Arms"),
            "Arms was the one safely displaceable style and it survived instead: \(styles)"
        )
    }

    func testEveryPriorityCanStillReachItsWeeklyTargetAfterTheSwap() {
        let styles = service.orderedBlueprintStyles(for: auditedAllocations, trainingDays: 5)
        for allocation in auditedAllocations {
            let reachable = service.reachableWeeklyDirectSets(for: allocation, within: styles)
            XCTAssertGreaterThanOrEqual(
                reachable,
                allocation.directSetTarget,
                """
                '\(allocation.area)' needs \(allocation.directSetTarget) weekly direct sets but the \
                chosen week (\(styles)) can only deliver \(reachable).
                """
            )
        }
    }

    // MARK: - The guarantee must not create a worse hole than it fills

    /// Every displaceable style here is the sole home of some priority, so there is no safe donor.
    /// The guarantee must back off rather than strand one of them to buy a pulling day.
    func testTheGuaranteeBacksOffWhenEveryDonorWouldStrandAPriority() {
        let allocations = [
            allocation(
                area: "Upper Chest",
                priorityLevel: "High",
                targetFrequency: 1,
                targetExerciseSlots: 3,
                directSetTarget: 8,
                maxPerSessionDirectSets: 4,
                maxFocusSessionDirectSets: 8,
                preferredStyles: ["Upper"]
            ),
            allocation(
                area: "Biceps",
                priorityLevel: "High",
                targetFrequency: 1,
                targetExerciseSlots: 3,
                directSetTarget: 8,
                maxPerSessionDirectSets: 4,
                maxFocusSessionDirectSets: 8,
                preferredStyles: ["Arms"]
            ),
            allocation(
                area: "Quads",
                priorityLevel: "High",
                targetFrequency: 1,
                targetExerciseSlots: 3,
                directSetTarget: 8,
                maxPerSessionDirectSets: 4,
                maxFocusSessionDirectSets: 8,
                preferredStyles: ["Legs"]
            )
        ]

        let styles = service.orderedBlueprintStyles(for: allocations, trainingDays: 5)
        for allocation in allocations {
            let reachable = service.reachableWeeklyDirectSets(for: allocation, within: styles)
            XCTAssertGreaterThanOrEqual(
                reachable,
                allocation.directSetTarget,
                """
                Buying a pulling day stranded '\(allocation.area)': the week \(styles) delivers \
                \(reachable) of \(allocation.directSetTarget) weekly direct sets.
                """
            )
        }
    }

    /// A priority that already asks for pulling work gets the day on demand alone. The guarantee
    /// must not fire a second time and displace anything.
    func testAPullingPriorityAlreadyEarnsItsDayWithoutTheGuarantee() {
        let allocations = [
            allocation(
                area: "Lats",
                priorityLevel: "High",
                targetFrequency: 3,
                targetExerciseSlots: 3,
                directSetTarget: 10,
                maxPerSessionDirectSets: 4,
                maxFocusSessionDirectSets: 8,
                preferredStyles: ["Pull", "Upper"]
            ),
            allocation(
                area: "Upper Chest",
                priorityLevel: "High",
                targetFrequency: 2,
                targetExerciseSlots: 3,
                directSetTarget: 10,
                maxPerSessionDirectSets: 5,
                maxFocusSessionDirectSets: 8,
                preferredStyles: ["Push", "Upper"]
            )
        ]

        let styles = service.orderedBlueprintStyles(for: allocations, trainingDays: 5)
        XCTAssertTrue(styles.contains("Pull"), "A Lats priority lost its pulling day: \(styles)")
        XCTAssertEqual(
            styles.filter { $0 == "Pull" }.count,
            1,
            "The pulling day was added twice: \(styles)"
        )
    }

    func testSixDayWeekIsUnchangedBecauseEveryStyleAlreadyFits() {
        let styles = service.orderedBlueprintStyles(for: auditedAllocations, trainingDays: 6)
        XCTAssertEqual(
            Set(styles),
            Set(["Push", "Pull", "Legs", "Lower", "Upper", "Arms"]),
            "A six-day week has room for every allowed style and should keep all of them: \(styles)"
        )
    }

    func testNoStyleIsSelectedTwice() {
        for trainingDays in 4...6 {
            let styles = service.orderedBlueprintStyles(for: auditedAllocations, trainingDays: trainingDays)
            XCTAssertEqual(
                Set(styles).count,
                styles.count,
                "\(trainingDays)-day week repeated a style: \(styles)"
            )
        }
    }

    // MARK: - The feasibility helper the donor choice rests on

    func testReachableSetsGiveOneDayTheFocusCapAndTheRestTheEvenCap() {
        let alloc = allocation(
            area: "Lateral Deltoids",
            priorityLevel: "High",
            targetFrequency: 3,
            targetExerciseSlots: 3,
            directSetTarget: 10,
            maxPerSessionDirectSets: 4,
            maxFocusSessionDirectSets: 8,
            preferredStyles: ["Push", "Upper", "Arms"]
        )
        XCTAssertEqual(service.reachableWeeklyDirectSets(for: alloc, within: ["Push"]), 8, accuracy: 0.001)
        XCTAssertEqual(service.reachableWeeklyDirectSets(for: alloc, within: ["Push", "Upper"]), 12, accuracy: 0.001)
    }

    /// The blueprint never plans more focus days than `targetFrequency`, so counting every
    /// compatible style would claim capacity the week will never actually build.
    func testReachableSetsAreBoundedByTargetFrequency() {
        let alloc = allocation(
            area: "Core/Abs",
            priorityLevel: "Medium",
            targetFrequency: 1,
            targetExerciseSlots: 2,
            directSetTarget: 6,
            maxPerSessionDirectSets: 3,
            maxFocusSessionDirectSets: 5,
            preferredStyles: ["Upper", "Legs", "Lower"]
        )
        XCTAssertEqual(
            service.reachableWeeklyDirectSets(for: alloc, within: ["Upper", "Legs", "Lower"]),
            5,
            accuracy: 0.001,
            "Three compatible styles but only one planned exposure — capacity is one focus day."
        )
    }

    func testReachableSetsAreZeroWithNoCompatibleStyle() {
        let alloc = allocation(
            area: "Core/Abs",
            priorityLevel: "Medium",
            targetFrequency: 2,
            targetExerciseSlots: 2,
            directSetTarget: 6,
            maxPerSessionDirectSets: 3,
            maxFocusSessionDirectSets: 5,
            // Was `["Upper", "Legs"]` against `["Push", "Pull", "Lower"]`, which asserted ZERO
            // reachable sets. That expectation encoded the raw-vs-canonical style bug: "Legs" and
            // "Lower" are one canonical style, so that allocation was always compatible with the
            // Lower day and the honest answer was never zero. `["Arms"]` is genuinely absent from
            // this week, which is what the test's own name claims to be testing.
            preferredStyles: ["Arms"]
        )
        XCTAssertEqual(
            service.reachableWeeklyDirectSets(for: alloc, within: ["Push", "Pull", "Lower"]),
            0,
            accuracy: 0.001
        )
    }

    /// The canonical-style tripwire. `canonicalTrainingStyle` folds "Legs" into "Lower", and this
    /// screen decides whether dropping a style would starve a priority — so treating the two
    /// spellings as different styles made a Core/Abs priority look unservable on a week that
    /// actually had two lower-body days for it.
    func testLegsAndLowerAreOneStyleOnBothSidesOfTheComparison() {
        let alloc = allocation(
            area: "Core/Abs",
            priorityLevel: "Medium",
            targetFrequency: 2,
            targetExerciseSlots: 2,
            directSetTarget: 6,
            maxPerSessionDirectSets: 3,
            maxFocusSessionDirectSets: 5,
            preferredStyles: ["Upper", "Legs"]
        )

        // A "Lower" day must satisfy a "Legs" preference: one focus day, nothing else compatible.
        XCTAssertEqual(
            service.reachableWeeklyDirectSets(for: alloc, within: ["Push", "Pull", "Lower"]),
            5,
            accuracy: 0.001,
            "A Lower day must satisfy a Legs preference"
        )

        // And the reverse spelling, so neither direction can regress.
        XCTAssertEqual(
            service.reachableWeeklyDirectSets(for: alloc, within: ["Push", "Pull", "Legs"]),
            5,
            accuracy: 0.001,
            "A Legs day must satisfy a Legs preference too"
        )

        // Two distinct lower-body days must still count as TWO exposures — canonicalizing the
        // comparison must not collapse the week's days into one.
        XCTAssertEqual(
            service.reachableWeeklyDirectSets(for: alloc, within: ["Legs", "Lower"]),
            8,
            accuracy: 0.001,
            "Canonicalizing the comparison must not merge two separate training days"
        )
    }
}
