import XCTest
@testable import Transform

/// The banner translator matches on raw-validator-string substrings, in order. Membership
/// ("every pattern reaches some branch") is not the property that matters — FIRST-match
/// correctness is. A generic pattern sitting ahead of a specific one produces confidently wrong
/// advice, which is strictly worse than the unclassified fallback the design already accounts
/// for. These cases are real validator sentences, copied in the shape the generator emits them.
final class WorkoutValidatorNoticeTests: XCTestCase {

    private func notice(_ raw: String) -> WorkoutValidatorNotice {
        let all = WorkoutValidatorNotice.notices(from: [raw])
        XCTAssertEqual(all.count, 1, "One issue should translate to exactly one notice")
        return all[0]
    }

    // MARK: - First-match routing

    func testEachValidatorMessageRoutesToItsIntendedNotice() {
        let cases: [(raw: String, expectedHeadlineFragment: String, expected: WorkoutValidatorNotice.Severity)] = [
            (
                "Muscle group 'Hamstrings' receives zero direct sets this week. BASE-001 requires every major muscle group to keep at least a minimal weekly exposure — even maintenance is not zero.",
                "has no direct work", .attention
            ),
            (
                "Day 3 exercise Lat Pulldown: the coaching cue 'hold 70 lb' contradicts the app's logged progression verdict — ADD LOAD (rep ceiling beaten at 70 lb).",
                "disagrees with your logged history", .attention
            ),
            (
                "Blueprint priority 'Quads' severely overshot its direct-set target (22.0/12.0). The weekly volume is dangerously above the evidence-based range and must be restructured.",
                "far more volume than planned", .attention
            ),
            (
                "Blueprint priority 'Upper Chest' missed its direct-set target (6.0/10.0).",
                "under its volume target", .tuning
            ),
            (
                "Blueprint priority 'Lateral Deltoids' missed its frequency target (1/2 targeted days).",
                "fewer days than planned", .tuning
            ),
            (
                "Non-priority muscle group 'Calves' exceeds the maintenance weekly volume ceiling (12.0/10.0). Maintenance means roughly 6-10 quality sets per week — trim redundant filler instead of stacking volume the recovery budget cannot pay for.",
                "more work than it needs", .headsUp
            ),
            (
                "Day 5 carries too much total fatigue load for a hypertrophy week (26). Reduce redundant compounds or redistribute work.",
                "heavy session", .headsUp
            ),
            (
                "Blueprint day 2 expected a Push session, but the generated day reads as Pull.",
                "different split than planned", .tuning
            ),
            (
                "Blueprint day 3 opens its Upper Chest focus with support/corrective work before the main hypertrophy movement. Put the prime growth slot first.",
                "leads with support work", .tuning
            ),
            (
                "Blueprint day 4 targets Lateral Deltoids, but never includes a prime hypertrophy movement for that focus.",
                "leans on support work", .tuning
            ),
            (
                "Blueprint day 1 was planned for 3 Upper Chest priority slots, but only 1 exercises clearly support that focus and the session only delivered 3 quality direct sets to that area.",
                "fewer movements for its focus", .tuning
            ),
            (
                "Day 2 did not follow the Pre-Selected Exercise Menu at slot 3: expected Cable Lateral Raise, but generated Dumbbell Lateral Raise.",
                "differ from the plan", .headsUp
            ),
            (
                "Day 6 exercises create excessive shoulder joint stress across the session.",
                "demanding on the shoulders", .headsUp
            ),
            (
                "Day 4 uses one identical rest prescription for every movement in a mixed session.",
                "same rest or tempo", .tuning
            )
        ]

        for testCase in cases {
            let result = notice(testCase.raw)
            XCTAssertTrue(
                result.headline.localizedCaseInsensitiveContains(testCase.expectedHeadlineFragment),
                "\"\(testCase.raw.prefix(60))…\" routed to \"\(result.headline)\", expected a headline containing \"\(testCase.expectedHeadlineFragment)\""
            )
            XCTAssertEqual(
                result.severity, testCase.expected,
                "Severity mismatch for \"\(result.headline)\""
            )
        }
    }

    // MARK: - Safety-relevant routing

    /// A note that claims shoulder-friendliness the programming does not deliver must NOT get
    /// the generic "follow the exercise list rather than the note" advice — that inverts the
    /// safety framing for someone with a flagged shoulder.
    func testShoulderFriendlyClaimDoesNotGetTheGenericIgnoreTheNoteAdvice() {
        let result = notice("Day 3 notes describe a shoulder-friendly session, but the programming contradicts that.")
        XCTAssertEqual(result.severity, .headsUp)
        XCTAssertFalse(
            result.detail.localizedCaseInsensitiveContains("follow the exercise list"),
            "Shoulder-safety claims must carry caution, not the cosmetic-mismatch advice"
        )
        XCTAssertTrue(result.detail.localizedCaseInsensitiveContains("cuff"))
    }

    /// A cosmetic note/programming mismatch keeps the plain advice.
    func testCosmeticNoteMismatchKeepsPlainAdvice() {
        let result = notice("Day 2 notes describe a low-fatigue session, but the programming contradicts that.")
        XCTAssertEqual(result.severity, .tuning)
        XCTAssertTrue(result.detail.localizedCaseInsensitiveContains("follow the exercise list"))
    }

    // MARK: - Substitution branches (safety framing)

    func testShoulderRiskSubstitutionIsAttentionAndNamesTheLift() {
        let result = notice("Day 4: 'Lat Pulldown' was replaced with 'Behind-the-Neck Pulldown', but the substitution significantly increases shoulder risk (1 → 3). Prefer lower-risk alternatives.")
        XCTAssertEqual(result.severity, .attention)
        XCTAssertTrue(result.headline.contains("Lat Pulldown"), result.headline)
        XCTAssertTrue(result.detail.localizedCaseInsensitiveContains("shoulder"))
    }

    func testLooseSubstitutionIsHeadsUpAndNamesTheLift() {
        let result = notice("Day 2: 'Barbell Romanian Deadlift' was replaced with 'Leg Extension', but the substitution changes the primary muscle target from Hamstrings to Quads. Keep substitutes within the same muscle group.")
        XCTAssertEqual(result.severity, .headsUp)
        XCTAssertTrue(result.headline.contains("Barbell Romanian Deadlift"), result.headline)
    }

    // MARK: - Quoted-subject extraction

    /// Validator prose contains contractions. A naive first-apostrophe scan would open on the
    /// one in "app's" and return garbage as the subject.
    func testContractionsDoNotBecomeTheQuotedSubject() {
        let result = notice("Blueprint priority 'Upper Chest' missed its direct-set target (6.0/10.0), and the app's planner couldn't fund more.")
        XCTAssertTrue(result.headline.hasPrefix("Upper Chest"), result.headline)
    }

    func testNoQuotedTermFallsBackToGenericSubject() {
        let result = notice("Blueprint priority missed its direct-set target (6.0/10.0).")
        XCTAssertTrue(result.headline.localizedCaseInsensitiveContains("a priority muscle"), result.headline)
    }

    // MARK: - Day-number safety

    /// `Blueprint day N` carries `ProgramDayPlan.dayIndex`, a 1-based index WITHIN the week —
    /// in week 3 "Blueprint day 2" is the user's Day 16. Rendering it as a day number would
    /// point the owner at the wrong session.
    func testBlueprintDayIndexIsNeverRenderedAsADayNumber() {
        let result = notice("Blueprint day 2 opens its Quads focus with support/corrective work before the main hypertrophy movement.")
        XCTAssertFalse(
            result.headline.contains("Day 2"),
            "Blueprint day indices must not surface as user-facing day numbers"
        )
    }

    /// A real day number in the same lowercase mid-sentence position IS safe to render.
    func testRealDayNumberIsRendered() {
        let result = notice("Blueprint priority 'Quads' exceeds its focus-day direct-set cap on day 5 (10.0 vs 8.0). Distribute the work more intelligently across the week.")
        XCTAssertTrue(result.headline.contains("Day 5") || result.detail.contains("Day 5"))
    }

    // MARK: - Unclassified findings

    func testUnrecognizedFindingIsNotReassuring() {
        let result = notice("Some entirely new validator rule fired with wording nobody mapped.")
        XCTAssertEqual(result.severity, .tuning)
        XCTAssertFalse(
            result.detail.localizedCaseInsensitiveContains("safe to train"),
            "An unclassified finding must not claim the week is safe — it was never read"
        )
        XCTAssertTrue(result.detail.localizedCaseInsensitiveContains("Generator Lab"))
    }

    // MARK: - Grouping

    func testRepeatedFindingsCollapseAndCount() {
        let notices = WorkoutValidatorNotice.notices(from: [
            "Day 1 exercise Cable Fly notes are empty or too short.",
            "Day 2 exercise Leg Press notes are empty or too short.",
            "Day 3 exercise Cable Curl notes are empty or too short."
        ])
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].occurrences, 3)
        XCTAssertTrue(notices[0].displayHeadline.contains("(3)"))
    }

    func testNoticesSortMostSevereFirstAndSummaryTakesTheWorst() {
        let notices = WorkoutValidatorNotice.notices(from: [
            "Blueprint priority 'Upper Chest' missed its direct-set target (6.0/10.0).",
            "Muscle group 'Hamstrings' receives zero direct sets this week."
        ])
        XCTAssertEqual(notices.count, 2)
        XCTAssertEqual(notices[0].severity, .attention)
        XCTAssertEqual(WorkoutValidatorNotice.summarySeverity(for: notices), .attention)
    }

    func testEmptyWarningsProduceNoNotices() {
        XCTAssertTrue(WorkoutValidatorNotice.notices(fromWarningsText: "").isEmpty)
        XCTAssertTrue(WorkoutValidatorNotice.notices(fromWarningsText: "\n  \n").isEmpty)
    }

    // MARK: - Value extraction

    func testVolumeRatioIsRenderedWithoutTrailingZeros() {
        let result = notice("Blueprint priority 'Biceps' missed its direct-set target (6.0/10.0).")
        XCTAssertTrue(result.detail.contains("6 hard sets"), result.detail)
        XCTAssertTrue(result.detail.contains("target of 10"), result.detail)
    }

    func testFractionalVolumeKeepsOneDecimal() {
        let result = notice("Blueprint priority 'Biceps' missed its direct-set target (6.5/10.0).")
        XCTAssertTrue(result.detail.contains("6.5 hard sets"), result.detail)
    }
}
