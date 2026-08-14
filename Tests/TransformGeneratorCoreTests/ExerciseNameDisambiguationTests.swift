import XCTest
@testable import Transform

/// Coverage for exercise-name disambiguation and the key migration it depends on.
///
/// This sits on the code path that once silently erased every logged weight the owner had
/// (INC-2). The failure mode is not a crash: the records stay on the device, keyed under a
/// name nothing looks up any more, and the app simply shows an empty history. So the property
/// that actually matters is not "the name is prettier" — it is "a record written before the
/// rename and a record written after it resolve to the SAME key".
@MainActor
final class ExerciseNameDisambiguationTests: XCTestCase {

    private func key(_ name: String) -> String {
        ExerciseWeightEntry.canonicalLookupKey(name)
    }

    // MARK: - The reason a migration is required at all

    /// If this ever fails, the migration has become unnecessary — or, far more likely, someone
    /// added equipment words to the key's stop-word list and merged genuinely different lifts.
    func testRenamingChangesTheLookupKey() {
        XCTAssertNotEqual(
            key("Hammer Curl"), key("Dumbbell Hammer Curl"),
            "Equipment words are not stop words, so a rename moves the key — which is exactly why records already on the device must be rewritten"
        )
    }

    /// The whole point: after the startup pass rewrites a stored name, the old record and any
    /// new record land on one key and consolidate into a single history.
    func testEveryRenameConvergesOnOneKeyAfterMigration() {
        for (old, new) in ExerciseNameDisambiguation.renames {
            XCTAssertEqual(
                key(ExerciseNameDisambiguation.resolved(old)), key(new),
                "A pre-rename '\(old)' record must key identically to a post-rename '\(new)' one"
            )
        }
    }

    /// The migration runs on every launch. If it were not idempotent it would rewrite records
    /// forever and the startup save would never settle.
    func testResolutionIsIdempotent() {
        for (old, new) in ExerciseNameDisambiguation.renames {
            XCTAssertEqual(ExerciseNameDisambiguation.resolved(old), new)
            XCTAssertEqual(ExerciseNameDisambiguation.resolved(new), new, "Already-renamed names must pass through untouched")
        }
    }

    /// Model output is not case- or plural-stable.
    func testResolutionToleratesCasingAndWhitespace() {
        XCTAssertEqual(ExerciseNameDisambiguation.resolved("hammer curl"), "Dumbbell Hammer Curl")
        XCTAssertEqual(ExerciseNameDisambiguation.resolved("  Skull Crusher  "), "EZ-Bar Skull Crusher")
        XCTAssertEqual(ExerciseNameDisambiguation.resolved("HAMMER   CURL"), "Dumbbell Hammer Curl")
    }

    func testUnknownNamesArePassedThroughUnchanged() {
        XCTAssertEqual(ExerciseNameDisambiguation.resolved("Back Squat"), "Back Squat")
        XCTAssertEqual(ExerciseNameDisambiguation.resolved("Some Novel Apparatus"), "Some Novel Apparatus")
        XCTAssertFalse(ExerciseNameDisambiguation.needsRename("Lat Pulldown"))
    }

    // MARK: - Collisions

    /// A rename that lands on a name already in use would MERGE two different lifts into one
    /// progression history — the same data loss from the opposite direction.
    func testNoRenameCollidesWithAnotherRenameOrACloseSibling() {
        let siblings = [
            "Seated Leg Curl", "Lying Leg Curl", "Cable Hammer Curl", "Machine Preacher Curl",
            "Incline Dumbbell Curl", "Barbell Curl", "EZ-Bar Curl", "Cable Curl",
            "Bayesian Cable Curl", "Single-Leg Hip Thrust", "Trap Bar Deadlift"
        ]
        var seen: [String: String] = [:]
        for name in Array(ExerciseNameDisambiguation.renames.values) + siblings {
            let k = key(name)
            if let existing = seen[k], existing != name {
                XCTFail("'\(name)' collides with '\(existing)' on key '\(k)'")
            }
            seen[k] = name
        }
    }

    /// A rename target must never itself be a rename source, or resolution would need more
    /// than one hop and `resolved` only does one.
    func testNoRenameChains() {
        for new in ExerciseNameDisambiguation.renames.values {
            XCTAssertNil(
                ExerciseNameDisambiguation.renames[new],
                "'\(new)' is both a rename target and a rename source — resolution is single-hop"
            )
        }
    }

    // MARK: - Stemming edge cases the incident log requires executing, not tracing

    /// INC-2 and its 2026-07-06 addendum: naive plural stripping split "press"/"presses" and
    /// e-ending singulars from their plurals, orphaning history both times. Mental tracing
    /// missed the second one for three weeks; running the algorithm caught it.
    func testSingularAndPluralFormsShareAKey() {
        for (singular, plural) in [
            ("Bench Press", "Bench Presses"),
            ("Lateral Raise", "Lateral Raises"),
            ("Cable Fly", "Cable Flies"),
            ("Cable Cross", "Cable Crosses"),
            ("Walking Lunge", "Walking Lunges"),
            ("Machine Crunch", "Machine Crunches"),
            ("Dumbbell Hammer Curl", "Dumbbell Hammer Curls")
        ] {
            XCTAssertEqual(key(singular), key(plural), "\(singular) / \(plural) must key identically")
        }
    }

    /// Word order must not matter — the key sorts its tokens.
    func testTokenOrderDoesNotAffectTheKey() {
        XCTAssertEqual(key("Dumbbell Hammer Curl"), key("Hammer Curl Dumbbell"))
    }

    // MARK: - The renamed names still classify correctly for coaching

    /// Renaming feeds `CoachingVoice`, which keys cues by movement pattern. A rename that
    /// misroutes the classifier would fix an ambiguous label and break the cue in one step.
    func testRenamedExercisesStillClassifyToTheRightPattern() {
        let expected: [(String, CoachingVoice.Pattern)] = [
            ("Dumbbell Hammer Curl", .bicepCurl),
            ("EZ-Bar Skull Crusher", .tricepExtension),
            ("EZ-Bar Preacher Curl", .bicepCurl),
            ("Machine Leg Curl", .legCurl),
            ("Machine Leg Extension", .legExtension),
            ("Barbell Hip Thrust", .hipThrust),
            ("Barbell Romanian Deadlift", .hinge),
            ("Cable Face Pull", .rearDelt),
            ("Landmine Meadows Row", .horizontalPull),
            ("Close-Grip Barbell Bench Press", .horizontalPress),
            ("Dumbbell Arnold Press", .overheadPress),
            ("Cable Pallof Press", .core),
            ("Dumbbell Walking Lunge", .lunge),
            ("Dumbbell Bulgarian Split Squat", .lunge),
            ("EZ-Bar JM Press", .tricepExtension)
        ]
        for (name, want) in expected {
            XCTAssertEqual(CoachingVoice.pattern(forName: name, muscleTarget: ""), want, "\(name) misclassified")
        }
    }
}
