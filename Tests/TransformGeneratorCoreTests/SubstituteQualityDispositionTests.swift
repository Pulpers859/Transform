import Foundation
import XCTest
@testable import Transform

/// `validateSubstituteQuality` emits three findings, and for a long time the repo carried a
/// FOURTH pattern for it — "was replaced with a poor substitute" — in two disposition lists and
/// in the user-facing copy mapper. No emitter has ever produced that phrase. It was matched by a
/// verification script only because the script grepped every string literal in the source,
/// including the pattern lists themselves, so the pattern found its own declaration and reported
/// a pass. Three places looked covered and none of them were.
///
/// The lesson is that a pattern list can only be trusted against strings copied from the
/// EMITTER. Every message below is pasted verbatim from
/// `WorkoutGeneratorService+ParsingValidation.swift`, with the interpolations filled in.
@MainActor
final class SubstituteQualityDispositionTests: XCTestCase {

    private let service = ClaudeService.shared

    private let changesTarget = "Day 2: 'Barbell Romanian Deadlift' was replaced with 'Leg Extension', but the substitution changes the primary muscle target from Hamstrings to Quads. Keep substitutes within the same muscle group."
    private let increasesFatigue = "Day 3: 'Machine Chest Press' was replaced with 'Barbell Bench Press', but the substitution significantly increases fatigue cost (2 → 4). Prefer similar or lower fatigue alternatives."
    private let increasesShoulderRisk = "Day 4: 'Lat Pulldown' was replaced with 'Behind-the-Neck Pulldown', but the substitution significantly increases shoulder risk (1 → 3). Prefer lower-risk alternatives."

    private var allThree: [String] {
        [changesTarget, increasesFatigue, increasesShoulderRisk]
    }

    // MARK: - Dispositions

    /// Under menu lock the exercise list is fixed before the model is called, and this check
    /// compares THIS week's locked menu against LAST week's — it is not about the model's output
    /// at all. Paying for a correction pass could never resolve it.
    func testEverySubstituteFindingIsAFreeWarningUnderMenuLock() {
        for issue in allThree {
            XCTAssertEqual(
                service.validationDisposition(for: issue, menuLocked: true),
                .acceptableWarning,
                "A menu-locked week must not buy a correction it cannot use: \(issue)"
            )
        }
    }

    /// On the unlocked procedural path the planner reads the finding itself and can still act, so
    /// two of the three stay correction-worthy. The shoulder-risk one is a deliberate exception —
    /// it ships as a warning on both paths.
    func testTheUnlockedPathStillTreatsTwoOfThemAsRepairable() {
        XCTAssertEqual(
            service.validationDisposition(for: changesTarget, menuLocked: false),
            .correctionPass
        )
        XCTAssertEqual(
            service.validationDisposition(for: increasesFatigue, menuLocked: false),
            .correctionPass
        )
        XCTAssertEqual(
            service.validationDisposition(for: increasesShoulderRisk, menuLocked: false),
            .acceptableWarning
        )
    }

    // MARK: - The copy the lifter actually reads

    /// Demoting a finding to a warning only helps if the warning says something. Each of the
    /// three must produce real copy rather than the unrecognised-finding fallback.
    func testEverySubstituteFindingGetsItsOwnPlainLanguageNotice() {
        for issue in allThree {
            let notices = WorkoutValidatorNotice.notices(from: [issue])
            XCTAssertEqual(notices.count, 1, issue)
            guard let notice = notices.first else { continue }

            XCTAssertFalse(
                notice.detail.isEmpty,
                "A demoted finding the lifter can see must explain itself: \(issue)"
            )
            XCTAssertTrue(
                notice.headline.lowercased().contains("swap")
                    || notice.headline.lowercased().contains("match")
                    || notice.headline.lowercased().contains("risk"),
                "Expected substitution copy, got \(notice.headline) for \(issue)"
            )
        }
    }

    /// The phrase that was never emitted must not quietly come back. If a future edit
    /// reintroduces it as a pattern, it will match this string and nothing else — which is the
    /// whole problem.
    func testThePhraseNoEmitterProducesIsNotClassifiedAsAKnownFinding() {
        let invented = "Day 1: 'Cable Fly' was replaced with a poor substitute."

        XCTAssertEqual(
            service.validationDisposition(for: invented, menuLocked: true),
            .acceptableWarning,
            "Unclassified findings default to a warning under lock; that is expected"
        )
        XCTAssertEqual(
            service.validationDisposition(for: invented, menuLocked: false),
            .hardFailure,
            """
            This phrase appears in no emitted message, so on the unlocked path it must fall \
            through to the inverted default rather than being recognised. If this assertion \
            starts failing, someone has re-added a pattern for a string the validator never \
            produces — check the emitter in validateSubstituteQuality before adding it back.
            """
        )
    }
}
