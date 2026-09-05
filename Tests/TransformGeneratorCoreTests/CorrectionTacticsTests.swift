import Foundation
import XCTest
@testable import Transform

/// A correction pass costs a paid API call. It is worth that only if the model is told how to
/// resolve the finding — a complaint written for a human reviewer, handed over with no remedy,
/// makes the model infer both cause and fix from prose, which is the weakest possible form of a
/// repair request and the most likely to come back unresolved and discard the week.
///
/// Several findings were classified as correction-worthy without ever being given a tactic:
/// the two blueprint rest/training day-shape findings, and all three effort-field findings.
/// These tests pin that every correction-worthy finding this repo emits either has a tactic or is
/// deliberately covered by the generic rule.
@MainActor
final class CorrectionTacticsTests: XCTestCase {

    private let service = ClaudeService.shared

    /// The generic line is always present; a tactic is an ADDITION to it, never a replacement.
    private let genericRule = "the listed validator issues are not optional"

    // MARK: - Day-shape findings

    func testAFlippedRestDayGetsAnExplicitRepairInstruction() {
        let tactics = service.correctionTactics(for: [
            "Blueprint day 3 was planned as a rest/recovery day, but the generated output turned it into a training session."
        ])

        XCTAssertTrue(tactics.contains(genericRule), tactics)
        XCTAssertTrue(tactics.contains("isRestDay"), "The model must be told which field to set: \(tactics)")
        XCTAssertTrue(
            tactics.contains("EMPTY exercises array"),
            "Setting the flag without clearing the exercises would just trade one finding for another: \(tactics)"
        )
    }

    func testAnEmptiedTrainingDayGetsAnExplicitRepairInstruction() {
        let tactics = service.correctionTactics(for: [
            "Blueprint day 2 expected a Legs training session, but the generated output made it a rest day."
        ])

        XCTAssertTrue(tactics.contains("isRestDay"), tactics)
        XCTAssertTrue(
            tactics.contains("Pre-Selected Exercise Menu"),
            "Restoring a training day means restoring its locked exercises, not inventing some: \(tactics)"
        )
    }

    /// The repair must be scoped. A model told only "a day is wrong" can renumber or drop days to
    /// make the complaint go away, which trades a correction-worthy finding for a hard failure.
    func testTheDayShapeTacticForbidsRestructuringTheWeek() {
        let tactics = service.correctionTactics(for: [
            "Blueprint day 3 was planned as a rest/recovery day, but the generated output turned it into a training session."
        ])

        XCTAssertTrue(tactics.contains("Do not add, drop, or renumber days"), tactics)
    }

    // MARK: - Effort findings

    func testTheRestrictedRecoveryFindingTellsTheModelWhichWayToMoveTheNumber() {
        let tactics = service.correctionTactics(for: [
            "Day 1 exercise Cable Lateral Raise is prescribed targetRIR 0 on a Restricted-recovery week — SLEEP-002 takes the cut from accessory hard-set exposure."
        ])

        XCTAssertTrue(tactics.contains("targetRIR"), tactics)
        XCTAssertTrue(
            tactics.contains("further from failure"),
            "Direction is the whole point — moving it the wrong way satisfies nothing: \(tactics)"
        )
        XCTAssertTrue(
            tactics.contains("do not soften the heavy compounds"),
            "SLEEP-002 protects intensity on the main lifts; the tactic must say so: \(tactics)"
        )
    }

    func testAMissingOrImpossibleEffortValueGetsARange() {
        for finding in [
            "Day 1 exercise Cable Crunch is missing targetRIR — state working-set effort in the structured field, not in prose.",
            "Day 1 exercise Cable Crunch has an out-of-range targetRIR of 9 — working-set effort belongs between 0 and 5 reps in reserve."
        ] {
            let tactics = service.correctionTactics(for: [finding])
            XCTAssertTrue(tactics.contains("0 to 5"), "\(finding) -> \(tactics)")
            XCTAssertTrue(tactics.contains("never in the note"), "\(finding) -> \(tactics)")
        }
    }

    // MARK: - Shape of the output

    func testAnUnrecognisedFindingStillGetsTheGenericRuleAndNothingElse() {
        let tactics = service.correctionTactics(for: ["Something nobody has written a tactic for."])

        XCTAssertTrue(tactics.contains(genericRule), tactics)
        XCTAssertEqual(
            tactics.components(separatedBy: "\n").count,
            1,
            "An unrecognised finding must not pick up an unrelated tactic: \(tactics)"
        )
    }

    func testTacticsAccumulateWhenSeveralFindingsArrivedTogether() {
        let tactics = service.correctionTactics(for: [
            "Blueprint day 3 was planned as a rest/recovery day, but the generated output turned it into a training session.",
            "Day 1 exercise Cable Crunch is missing targetRIR — state working-set effort in the structured field, not in prose."
        ])

        XCTAssertTrue(tactics.contains("isRestDay"), tactics)
        XCTAssertTrue(tactics.contains("0 to 5"), tactics)
        XCTAssertGreaterThanOrEqual(tactics.components(separatedBy: "\n").count, 3, tactics)
    }

    // MARK: - The invariant

    /// Every finding routed to a paid correction pass should arrive with an instruction for fixing
    /// it. This walks the real `correctionWorthyIssuePatterns` list rather than a hand-typed
    /// sample, so a future correction-worthy rule added without a tactic shows up here.
    ///
    /// The allow-list is for findings whose repair genuinely needs no instruction beyond the
    /// finding text plus the generic rule — mostly prose rewrites, where the issue string already
    /// names the offending sentence and what is wrong with it.
    func testEveryCorrectionWorthyFindingHasATacticOrIsDeliberatelyGeneric() {
        let genericByDesign: Set<String> = [
            // PROSE REWRITES. The finding text already quotes the offending sentence and names the
            // standard it broke, so the generic rule plus the finding is the whole instruction.
            "notes are empty or too short",
            "notes do not include a concrete progression cue",
            "session notes are empty or too short",
            "session notes are generic",
            "session notes talk about",
            "notes claim",
            "notes contradict the actual programming",
            "notes describe a low-fatigue",
            "notes describe a shoulder-friendly",
            "is not clearly adapted to the shoulder risk",

            // EXERCISE-SELECTION AND VOLUME VERDICTS. Under menu lock the AI may not add, drop or
            // swap a movement or change a set count, so there is no instruction to give it — a
            // tactic here would be telling the model to do something it is forbidden to do. These
            // stay correction-worthy for the UNLOCKED procedural path, where the planner reads the
            // finding rather than the prompt.
            "missed its direct-set target", "missed its frequency target",
            "minimum viable stimulus threshold", "uses too many weekly exercise variations",
            "was supposed to emphasize", "opens its", "is supposed to emphasize quads",
            "stacks too many", "the generated day reads as", "reads as a broad lower-body session",
            "never includes a prime hypertrophy movement",
            "excessive shoulder joint stress", "excessive elbow joint stress",
            "excessive lower-back stress", "excessive knee joint stress",
            "exceeds its focus-day direct-set cap", "exceeds its per-session direct-set cap",
            "exceeds the maintenance weekly volume ceiling",
            "overshot its direct-set target enough to create avoidable fatigue",
            "was replaced with a poor substitute",
            "substitution changes the primary muscle target",
            "substitution significantly increases fatigue",
            "spends too many", "low-value filler", "Trim redundant focus work",
            "does not clearly support", "already reached its weekly target",
            "is concentrated into overly fatiguing sessions", "was planned for",
            "uses shoulder-intensive pressing on an Arms/Lateral focus day"
        ]

        var missing: [String] = []
        for pattern in service.correctionWorthyIssuePatterns where !genericByDesign.contains(pattern) {
            // Feed the pattern itself as the finding: `correctionTactics` matches by substring, so
            // a pattern that has a tactic will produce more than the generic line alone.
            let tactics = service.correctionTactics(for: [pattern])
            if tactics.components(separatedBy: "\n").count <= 1 {
                missing.append(pattern)
            }
        }

        XCTAssertTrue(
            missing.isEmpty,
            """
            \(missing.count) correction-worthy finding(s) are sent to a PAID correction call with \
            no instruction for resolving them. Add a tactic in `correctionTactics(for:)`, or add \
            the pattern to `genericByDesign` here with a reason:
            \(missing.map { "  - \($0)" }.joined(separator: "\n"))
            """
        )
    }
}
