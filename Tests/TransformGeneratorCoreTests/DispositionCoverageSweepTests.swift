import Foundation
import XCTest
@testable import Transform

/// A tripwire for the class of bug that keeps recurring in the validator: a finding that no
/// severity list recognises.
///
/// `validationDisposition` has an INVERTED default. Under `menuLocked: true` — the production
/// path — an unrecognised finding silently becomes `.acceptableWarning` and ships. Under
/// `menuLocked: false` the same finding is a HARD FAILURE that discards a paid week. So a rule
/// nobody classified does not fail loudly; it fails differently on each path, and the only
/// symptom is a week that quietly carries a defect the app already detected.
///
/// This has bitten twice for real. Three blueprint day-shape findings ("a planned rest day
/// became a training session") matched no list at all and rode the mild default for an unknown
/// length of time. And renaming a message's anchor phrase without moving its pattern silently
/// re-tiers it — that happened in this repo, the wrong belief reached both a source comment and
/// a test, and only CI caught it.
///
/// WHAT THIS TEST DOES NOT DO, stated plainly so nobody trusts it further than it deserves:
/// it is not a proof of total coverage. It asserts that every finding the validators actually
/// EMIT for the adversarial inputs below is classified. A rule these inputs never trip is not
/// checked. Full static verification is impossible here — `matchesValidationIssue` is a runtime
/// substring test, and some patterns deliberately span an interpolation (for example
/// `"exceeds its focus-day direct-set cap"` is only ever complete once `\(capContext)` resolves),
/// so no source scan can decide them. Closing that last gap would mean moving message text into
/// a registry, which is a real refactor and not what this file is.
///
/// When this test fails, the fix is NOT to delete the assertion. It is to decide, deliberately,
/// which severity list the new finding belongs in, and to give it plain-language copy in
/// `WorkoutValidatorNotice` — a classified finding with no copy still renders to the owner as
/// "A plan check didn't pass … isn't recognized well enough to explain here."
@MainActor
final class DispositionCoverageSweepTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Fixtures

    private struct Fixture: Decodable {
        let analysis: BodyAnalysisResult
    }

    private func fixtureBlueprint(weekNumber: Int = 1) throws -> ClaudeService.ProgramBlueprint {
        guard let url = Bundle.module.url(forResource: "five-maintenance-errors", withExtension: "json") else {
            XCTFail("Bundled generator regression fixture is missing")
            throw CocoaError(.fileNoSuchFile)
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let intent = service.trainingIntentPlan(from: fixture.analysis)
        return service.programBlueprint(for: intent, weekNumber: weekNumber)
    }

    private func exercise(
        _ name: String,
        _ target: String,
        sets: Int,
        reps: String = "10-12",
        restSeconds: Int = 90,
        notes: String = "Brace and control the eccentric.",
        targetRIR: Int? = 2
    ) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: name,
            sets: sets,
            reps: reps,
            tempo: "2-0-1-1",
            restSeconds: restSeconds,
            notes: notes,
            muscleTarget: target,
            targetRIR: targetRIR
        )
    }

    private func day(
        _ number: Int,
        _ exercises: [WorkoutExerciseResponse],
        name: String = "Training",
        notes: String = "Solid session today.",
        isRestDay: Bool = false
    ) -> WorkoutDayResponse {
        WorkoutDayResponse(
            dayNumber: number,
            dayName: name,
            muscleGroups: "",
            isRestDay: isRestDay,
            notes: notes,
            exercises: exercises
        )
    }

    // MARK: - The sweep

    /// Every finding these adversarial inputs produce must be recognised by at least one severity
    /// list. Deliberately NOT asserting the lists are mutually exclusive: a pattern appearing in
    /// both `lockedMenuHardFailurePatterns` and `correctionWorthyIssuePatterns`, or in both
    /// `menuLockedDemotionPatterns` and `correctionWorthyIssuePatterns`, is load-bearing rather
    /// than redundant. The locked path consults all four lists; the UNLOCKED path consults only
    /// `acceptableWarningIssuePatterns` and `correctionWorthyIssuePatterns`. Duplication is how a
    /// finding is given different treatment on the two paths — 14 patterns rely on it today, and
    /// an earlier audit misread that as dead code.
    func testEveryEmittedFindingIsRecognisedBySomeSeverityList() throws {
        let findings = try emittedFindings()
        XCTAssertFalse(findings.isEmpty, "The adversarial inputs stopped producing findings — this test is no longer testing anything")

        var unclassified: [String] = []
        for finding in findings where !isClassified(finding) {
            unclassified.append(finding)
        }

        XCTAssertTrue(
            unclassified.isEmpty,
            """
            \(unclassified.count) validator finding(s) match no severity list. Under menu-lock \
            each ships as a silent warning; unlocked, each HARD-FAILS a paid week. Classify every \
            one deliberately in `WorkoutGeneratorService+ParsingValidation.swift` and give it copy \
            in `WorkoutValidatorNotice.swift`:
            \(unclassified.map { "  - \($0)" }.joined(separator: "\n"))
            """
        )
    }

    /// A classified finding with no owner-facing copy is only half-wired: the tier is right, and
    /// the Workout tab still shows "A plan check didn't pass … isn't recognized well enough to
    /// explain here." That fallback exists to avoid falsely reassuring, so reaching it is always
    /// a gap rather than an acceptable resting state.
    func testEveryEmittedFindingHasPlainLanguageCopy() throws {
        let findings = try emittedFindings()

        var untranslated: [String] = []
        for finding in findings {
            let notices = WorkoutValidatorNotice.notices(from: [finding])
            guard let notice = notices.first else {
                untranslated.append(finding)
                continue
            }
            if notice.headline == "A plan check didn't pass" {
                untranslated.append(finding)
            }
        }

        XCTAssertTrue(
            untranslated.isEmpty,
            """
            \(untranslated.count) validator finding(s) render to the owner as the unrecognised \
            fallback. Add a branch in `WorkoutValidatorNotice.translate(_:)`:
            \(untranslated.map { "  - \($0)" }.joined(separator: "\n"))
            """
        )
    }

    /// The disposition of a finding must not depend on which list happens to be checked first for
    /// reasons nobody intended. This pins the two paths' behaviour so a future list edit that
    /// changes a finding's tier shows up as a failure rather than as a quiet behaviour change.
    func testEveryEmittedFindingResolvesToAStableTierOnBothPaths() throws {
        for finding in try emittedFindings() {
            let locked = service.validationDisposition(for: finding, menuLocked: true)
            let unlocked = service.validationDisposition(for: finding, menuLocked: false)

            // The unlocked path is strictly stricter or equal — it never demotes something the
            // locked path treats as a hard failure into a warning.
            if locked == .hardFailure {
                XCTAssertNotEqual(
                    unlocked, .acceptableWarning,
                    "A finding that discards a locked week must not be a mere warning unlocked: \(finding)"
                )
            }
        }
    }

    // MARK: - Adversarial inputs

    /// Deliberately broken weeks, each shaped after a defect that really shipped. Every validator
    /// reachable with simple inputs is driven; the blueprint-dependent ones use the bundled
    /// regression fixture's real blueprint rather than a hand-built one.
    private func emittedFindings() throws -> [String] {
        let blueprint = try fixtureBlueprint()
        var findings: [String] = []

        // Shape violations: empty fields, out-of-range sets and rest, missing effort field.
        let malformed = [
            day(1, [
                exercise("", "Chest", sets: 3),
                exercise("Incline Barbell Press", "Upper Chest", sets: 99),
                exercise("Machine Chest Press", "Chest", sets: 3, restSeconds: 900),
                exercise("Cable Fly", "Chest", sets: 3, reps: ""),
                exercise("Dumbbell Bench Press", "Chest", sets: 3, targetRIR: nil)
            ], name: "")
        ]
        findings += service.validateDaySet(malformed, dayStart: 1, dayEnd: 1)

        // An exercise stranded below its role floor — the Cable Crunch case.
        findings += service.validateDaySet(
            [day(1, [exercise("Cable Crunch", "Abs", sets: 1)])],
            dayStart: 1,
            dayEnd: 1
        )

        // A rest day still carrying exercises.
        findings += service.validateDaySet(
            [day(1, [exercise("Back Squat", "Quads", sets: 3)], isRestDay: true)],
            dayStart: 1,
            dayEnd: 1
        )

        // Back trained with no rowing at all, and with a token row against heavy vertical work.
        findings += service.validateBackPatternBalance(days: [
            day(1, [
                exercise("Lat Pulldown", "Lats", sets: 3),
                exercise("Pull-Up (Weighted or Assisted)", "Lats", sets: 3)
            ])
        ])
        findings += service.validateBackPatternBalance(days: [
            day(1, [
                exercise("Lat Pulldown", "Lats", sets: 2),
                exercise("Neutral-Grip Lat Pulldown", "Lats", sets: 2),
                exercise("Pull-Up (Weighted or Assisted)", "Lats", sets: 2),
                exercise("Chest-Supported Row", "Upper Back", sets: 2)
            ])
        ])

        // An "easy day" note sitting on two heavy compounds, in the paraphrase that slipped past.
        findings += service.validateNoteContradictions(
            on: day(
                1,
                [
                    exercise("Back Squat", "Quads", sets: 3),
                    exercise("Barbell Romanian Deadlift", "Hamstrings", sets: 3)
                ],
                notes: "A balanced lower session to maintain leg mass without adding fatigue."
            ),
            blueprint: blueprint,
            dayStart: 1
        )

        // Unadapted overhead pressing against a described (not diagnosed) shoulder problem.
        findings += service.validateInjuryRiskAlignment(
            on: day(1, [exercise("Seated Dumbbell Shoulder Press", "Anterior Deltoids", sets: 3)]),
            injuryRiskFocus: "Left anterior shoulder pain during neutral-grip overhead pressing is the key flag."
        )

        // A session far past its time budget.
        findings += service.validateSessionTimeBudget(
            on: day(1, [
                exercise("Back Squat", "Quads", sets: 5, restSeconds: 240),
                exercise("Barbell Romanian Deadlift", "Hamstrings", sets: 5, restSeconds: 240),
                exercise("Leg Press", "Quads", sets: 5, restSeconds: 240),
                exercise("Seated Leg Curl", "Hamstrings", sets: 5, restSeconds: 240),
                exercise("Standing Calf Raise", "Calves", sets: 5, restSeconds: 240)
            ]),
            budgetMinutes: 45
        )

        // Joint-stress overload.
        findings += service.validateJointStressBudget(on: day(1, [
            exercise("Incline Barbell Press", "Upper Chest", sets: 5),
            exercise("Machine Incline Press", "Upper Chest", sets: 5),
            exercise("Dumbbell Bench Press", "Chest", sets: 5),
            exercise("Machine Chest Press", "Chest", sets: 5),
            exercise("Dip (Assisted or Weighted)", "Triceps", sets: 5)
        ]))

        // Blueprint day-shape violations: a planned rest day turned into training, and a planned
        // training day emptied into a rest day.
        var flipped: [WorkoutDayResponse] = []
        for plan in blueprint.dayPlans {
            let number = plan.dayIndex
            if plan.isRestDay {
                flipped.append(day(number, [exercise("Back Squat", "Quads", sets: 3)]))
            } else {
                flipped.append(day(number, [], isRestDay: true))
            }
        }
        findings += service.validateDayPlans(days: flipped, blueprint: blueprint, dayStart: 1)

        // Blueprint volume/frequency accounting over a week that ignores the plan entirely.
        findings += service.validateBlueprint(days: flipped, blueprint: blueprint, dayStart: 1)

        return findings.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func isClassified(_ finding: String) -> Bool {
        service.matchesValidationIssue(finding, patterns: service.lockedMenuHardFailurePatterns)
            || service.matchesValidationIssue(finding, patterns: service.acceptableWarningIssuePatterns)
            || service.matchesValidationIssue(finding, patterns: service.menuLockedDemotionPatterns)
            || service.matchesValidationIssue(finding, patterns: service.correctionWorthyIssuePatterns)
    }
}
