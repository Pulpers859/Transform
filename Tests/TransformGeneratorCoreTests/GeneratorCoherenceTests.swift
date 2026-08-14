import XCTest
@testable import Transform

/// Tests for COUPLINGS rather than components.
///
/// Every regression in the exercise-naming and coaching work shared one shape: two structures
/// that must agree, agreeing only by hand. Each had passing tests. The tests checked the parts
/// in isolation, and nothing checked that the parts still matched each other.
///
/// * The exercise catalog, the procedural selection pool, and the priority accessory catalogs
///   all carry the same identities. A rename touched one of the three; selection looks
///   exercises up BY NAME against metadata, so the halves disagreed and the deterministic menu
///   silently changed its picks. It took three CI rounds to find. `testEveryNameInEveryList...`
///   below would have found it in one.
/// * The banned-prose fragments were written out three times. The audit copy drifted, so a cue
///   could pass its own safety check and still hard-fail generation, discarding a paid week.
///
/// A test here should fail when two things stop agreeing — not when either one changes.
@MainActor
final class GeneratorCoherenceTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Name-list coherence

    /// Every exercise identity the generator can select must exist in the metadata catalog,
    /// either directly or through the alias table.
    ///
    /// Metadata drives fatigue cost, muscle credit and pattern caps. A name that misses the
    /// catalog does not error — it silently scores as unknown, which is how a rename to one
    /// list reshuffled entire training days.
    func testEveryGeneratorNameResolvesToACatalogIdentity() {
        let catalog = Set(service.exerciseMetadataEntries.map(\.canonicalName))
        XCTAssertFalse(catalog.isEmpty, "Catalog failed to load; the rest of this test would pass vacuously")

        var checked = 0
        for style in ["Push", "Pull", "Lower", "Legs", "Upper", "Arms"] {
            for entry in service.exerciseCatalog(for: style) {
                checked += 1
                let resolved = service.canonicalExerciseName(entry.name, muscleTarget: entry.target)
                XCTAssertTrue(
                    catalog.contains(resolved),
                    "'\(entry.name)' in the \(style) selection pool resolves to '\(resolved)', which is not a catalog identity — selection would score it as unknown"
                )
            }
        }
        XCTAssertGreaterThan(checked, 40, "Selection pools look empty; this test needs real data to mean anything")
    }

    /// The disambiguation map must not name an exercise the catalog has never heard of, in
    /// either direction: a stale source silently does nothing, and a target that is not a
    /// catalog identity renames records onto a name the generator cannot produce.
    func testDisambiguationMapAgreesWithTheCatalog() {
        let catalog = Set(service.exerciseMetadataEntries.map(\.canonicalName))

        for (old, new) in ExerciseNameDisambiguation.renames {
            XCTAssertTrue(
                catalog.contains(new),
                "'\(old)' renames to '\(new)', which is not a catalog identity — stored history would move to a name nothing generates"
            )
            XCTAssertFalse(
                catalog.contains(old),
                "'\(old)' is still a catalog identity AND a rename source — the catalog and the map disagree about which name is current"
            )
        }
    }

    /// The alias table must send every pre-rename name forward. A repair pass once rewrote the
    /// alias SOURCES instead of their targets, turning 25 entries into identity pairs and
    /// quietly dropping resolution for every old name.
    func testEveryRenameSourceStillResolvesForward() {
        for (old, new) in ExerciseNameDisambiguation.renames {
            XCTAssertEqual(
                service.canonicalExerciseName(old, muscleTarget: ""), new,
                "A model still emitting '\(old)' must land on '\(new)' rather than creating a second identity"
            )
        }
    }

    // MARK: - Banned-prose coherence

    /// The audit must cover the validator, not merely resemble it. It previously mirrored only
    /// the display filter, leaving six validator fragments unchecked — and the validator is the
    /// list whose violation costs an entire paid AI week.
    func testAuditCoversEveryValidatorBannedFragment() {
        for fragment in ProgressionProseFragments.validatorBanned {
            XCTAssertTrue(
                CoachingVoiceAudit.forbiddenFragments.contains(fragment),
                "'\(fragment)' hard-fails generation but is absent from the audit a cue is checked against"
            )
        }
    }

    /// The composed list is what makes the copies unnecessary; if it ever stops covering a
    /// sub-list, the copies are back.
    func testComposedFragmentListCoversEverySubList() {
        let all = Set(ProgressionProseFragments.all)
        for (label, list) in [
            ("validatorBanned", ProgressionProseFragments.validatorBanned),
            ("progressionOwnedByBanner", ProgressionProseFragments.progressionOwnedByBanner),
            ("sessionRecap", ProgressionProseFragments.sessionRecap),
            ("deloadContext", ProgressionProseFragments.deloadContext)
        ] {
            for fragment in list {
                XCTAssertTrue(all.contains(fragment), "\(label) fragment '\(fragment)' missing from the composed list")
            }
        }
    }

    /// The rule and the guard have to agree at runtime, not just by inspection.
    func testValidatorAgreesWithItsOwnFragmentList() {
        for fragment in ProgressionProseFragments.validatorBanned {
            XCTAssertTrue(
                service.notesContainProgressionInstruction("Keep the elbows tucked. \(fragment) here."),
                "The validator does not flag '\(fragment)', which its own banned list claims it does"
            )
        }
    }

    // MARK: - Cue content against the real rule

    /// Re-stated against the composed source rather than the audit's own copy, so this cannot
    /// pass by both sides sharing the same mistake.
    func testNoEmittableCueContainsAnyBannedFragment() {
        for cue in CoachingVoiceAudit.allCues() {
            let lowered = cue.lowercased()
            for fragment in ProgressionProseFragments.all {
                XCTAssertFalse(
                    lowered.contains(fragment),
                    "Cue contains banned fragment '\(fragment)': \(cue)"
                )
            }
        }
    }
}
