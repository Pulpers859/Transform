import Foundation
import XCTest
@testable import Transform

/// Menu-locked generation (INC-3) makes the deterministic planner the sole owner of exercise
/// identity, set counts, and day structure. The AI is forbidden to change them, and
/// `applyingPreselectedSetPrescription` overwrites its set numbers anyway. So a validator finding
/// about those things is unactionable by the AI *by construction*: it survives every retry AND
/// the correction pass, then fails `shouldAcceptAIOutput` and discards every paid candidate.
///
/// `validationDisposition` used to default to `.hardFailure`, which made every newly written
/// quality rule a coin flip — if its wording was not already in a hand-maintained demotion list,
/// it discarded the week, and the only way to find out was to pay for a generation. BASE-001
/// zero-coverage and the lower-body-balance finding each cost a full week of paid candidates that
/// way. The default is now inverted under a locked menu: only an explicit allow-list of shape and
/// safety findings may discard the week.
@MainActor
final class ValidationDispositionOwnershipTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - The inversion itself

    /// The regression that motivated the change. A plausible future quality rule, worded in a way
    /// no pattern list mentions, must not be able to throw away work the owner paid for.
    func testNovelUnclassifiedFindingDoesNotDiscardALockedMenuWeek() {
        let novel = "Day 3 places its heaviest hinge immediately after its heaviest squat, which blunts both."

        XCTAssertEqual(service.validationDisposition(for: novel, menuLocked: true), .acceptableWarning)
        XCTAssertNotEqual(
            service.validationDisposition(for: novel, menuLocked: true), .hardFailure,
            "An unclassified finding must never set hasPlannerOrStructuralFailure."
        )
    }

    /// The unlocked path is deliberately untouched — there the AI really can change selection, so
    /// an unknown finding staying strict is correct.
    func testUnlockedPathStillDefaultsToHardFailure() {
        let novel = "Day 3 places its heaviest hinge immediately after its heaviest squat, which blunts both."

        XCTAssertEqual(service.validationDisposition(for: novel, menuLocked: false), .hardFailure)
    }

    // MARK: - What may still discard a week

    func testStructuralShapeFindingsStillHardFailUnderALockedMenu() {
        let structural = [
            "Must contain exactly 7 days.",
            "Duplicate dayNumber values found.",
            "Training days must be between 4 and 6.",
            "Rest days must be between 1 and 3.",
            "daysPerWeek should be between 4 and 6.",
            "Day 2 must have 5-8 exercises.",
            "Day 2 has empty dayName.",
            "Day 2 has an exercise with empty exerciseName.",
            "Day 2 exercise Back Squat has invalid sets.",
            "Day 2 exercise Back Squat has invalid restSeconds.",
            "Day 2 exercise Back Squat has empty reps.",
            "Total training exercises are too low.",
            "Day 6 is rest day but has exercises.",
            "All days are rest days.",
            "programName is empty.",
            "programSummary is empty.",
            "weekSummary is empty."
        ]

        for issue in structural {
            XCTAssertEqual(
                service.validationDisposition(for: issue, menuLocked: true), .hardFailure,
                "'\(issue)' is a broken week, not a mediocre one."
            )
        }
    }

    /// Over-delivery is the planner's fault AND a real risk to the lifter, so it still stops the
    /// week. Under-delivery deliberately does not — the allocator already funded what it could.
    func testVolumeOverDeliveryStillHardFailsButUnderDeliveryDoesNot() {
        let overDelivery = [
            "Blueprint priority 'Quads' severely overshot its direct-set target (18.0 vs 10.0).",
            "Blueprint priority 'Quads' overshot its direct-set target enough to create avoidable fatigue (14.0 vs 10.0).",
            "Blueprint priority 'Quads' exceeds its focus-day direct-set cap on day 2.",
            "Blueprint priority 'Quads' exceeds its per-session direct-set cap on day 2.",
            "Non-priority muscle group 'Back' exceeds the maintenance weekly volume ceiling (12.0 vs 8.0)."
        ]
        for issue in overDelivery {
            XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .hardFailure, issue)
        }

        let underDelivery = [
            "Blueprint priority 'Quads' missed its direct-set target (6.0 vs 10.0).",
            "Blueprint priority 'Quads' missed its frequency target (1/2).",
            "Blueprint priority 'Quads' fell below the minimum viable stimulus threshold."
        ]
        for issue in underDelivery {
            XCTAssertEqual(
                service.validationDisposition(for: issue, menuLocked: true), .acceptableWarning,
                "Under-delivery cannot be repaired downstream — hard-failing only denies a program: \(issue)"
            )
        }
    }

    // MARK: - The two findings that were each paid for once

    func testHistoricalMoneyBurningFindingsStayWarnings() {
        let base001 = "Muscle group 'Calves' receives zero direct sets this week. BASE-001 requires every major muscle group to receive direct work."
        let lowerBalance = "Day 2 reads as a broad lower-body session but has no knee-dominant quad anchor."

        XCTAssertEqual(service.validationDisposition(for: base001, menuLocked: true), .acceptableWarning)
        XCTAssertEqual(service.validationDisposition(for: lowerBalance, menuLocked: true), .acceptableWarning)
    }

    // MARK: - Genuinely AI-owned findings still earn the cheap repair

    func testAIOwnedProseFindingsStillGetACorrectionPass() {
        let aiOwned = [
            "Day 2 exercise Back Squat is missing targetRIR — state working-set proximity to failure.",
            "Day 2 session notes are empty or too short — rewrite with real coaching content.",
            "Day 2 session notes are generic — rewrite with an analysis-anchored intent.",
            "Day 2 exercise Back Squat notes contain load/rep progression instructions.",
            "Day 3 did not follow the Pre-Selected Exercise Menu at slot 2: expected Leg Press."
        ]

        for issue in aiOwned {
            XCTAssertEqual(
                service.validationDisposition(for: issue, menuLocked: true), .correctionPass,
                "'\(issue)' is a field the AI actually writes — repair it rather than shipping or discarding."
            )
        }
    }

    // MARK: - Scoring consequence

    /// `scoreValidationIssues` weights hardFailure at 20, which is what makes a candidate lose.
    /// The inversion has to show up there too, or candidate ranking still punishes the AI for the
    /// planner's decisions.
    func testUnclassifiedFindingNoLongerCarriesHardFailureWeight() {
        let novel = ["Day 3 places its heaviest hinge immediately after its heaviest squat, which blunts both."]

        XCTAssertEqual(service.scoreValidationIssues(novel, menuLocked: true), 1)
        XCTAssertEqual(service.scoreValidationIssues(novel, menuLocked: false), 20)
    }

    /// The acceptance gate the whole thing feeds. A week whose only findings are planner-owned
    /// must now be shippable rather than discarded.
    func testWeekWithOnlyPlannerOwnedFindingsIsAccepted() {
        let issues = [
            "Muscle group 'Calves' receives zero direct sets this week. BASE-001 requires every major muscle group to receive direct work.",
            "Blueprint priority 'Quads' missed its direct-set target (6.0 vs 10.0).",
            "Day 3 places its heaviest hinge immediately after its heaviest squat, which blunts both."
        ]

        XCTAssertTrue(
            service.shouldAcceptAIOutput(despite: issues, menuLocked: true),
            "Every one of these is unactionable by the AI — discarding the week wastes what was paid for."
        )
    }

    /// ...but a genuinely broken week is still rejected.
    func testWeekWithAStructuralFindingIsStillRejected() {
        XCTAssertFalse(
            service.shouldAcceptAIOutput(despite: ["Must contain exactly 7 days."], menuLocked: true)
        )
    }

    // MARK: - List precedence

    /// The allow-list has to be the authority. An earlier draft checked
    /// `acceptableWarningIssuePatterns` first, which quietly made THAT list the authority: a
    /// finding matching both would ship a structurally broken week. The two lists do not overlap
    /// today, and this test is what stops that from being a fact someone has to re-verify by hand.
    func testHardFailureAllowListOutranksTheAcceptableWarningList() {
        let matchesBoth = "Too few anchor lifts carried over from last week. Must contain exactly 7 days."

        XCTAssertEqual(
            service.validationDisposition(for: matchesBoth, menuLocked: true), .hardFailure,
            "A finding that is also structural must not be demoted by a warning-list match."
        )
    }

    /// The unlocked path keeps its own acceptable-warning handling — an earlier draft moved that
    /// check inside the locked branch and silently promoted these to hard failures.
    func testUnlockedPathStillHonoursTheAcceptableWarningList() {
        let warnings = [
            "Blueprint priority 'Quads' undershot its targeted exercise-slot goal (2/3).",
            "Blueprint priority 'Quads' undershot its weighted stimulus target (7.0 vs 9.0).",
            "Too few anchor lifts carried over from last week."
        ]

        for issue in warnings {
            XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: false), .acceptableWarning, issue)
            XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .acceptableWarning, issue)
        }
    }

    /// The training-day mismatch pattern is anchored to its template's unique opening. The
    /// mid-sentence fragment it replaced ("but the generated week has") was generic enough that an
    /// unrelated count message could trip it and hard-fail a week this list exists to protect.
    func testTrainingDayMismatchIsMatchedByItsTemplateOpening() {
        let mismatch = "Blueprint calls for 5 training days, but the generated week has 4."
        XCTAssertEqual(service.validationDisposition(for: mismatch, menuLocked: true), .hardFailure)

        let unrelated = "Day 4 was planned for 6 exercises, but the generated week has a different emphasis."
        XCTAssertNotEqual(
            service.validationDisposition(for: unrelated, menuLocked: true), .hardFailure,
            "An unrelated finding that happens to share that phrasing must not discard the week."
        )
    }
}
