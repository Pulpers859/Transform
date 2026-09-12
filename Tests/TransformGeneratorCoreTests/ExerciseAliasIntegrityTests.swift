import XCTest
@testable import Transform

/// Every exercise alias must land on a real catalogue entry.
///
/// `exerciseNameAliasCache` exists so a model still emitting an older or looser name resolves
/// to the explicit catalogue entry instead of creating a second identity. An alias whose
/// TARGET is not itself a catalogue entry defeats that: it renames the movement into a third
/// identity that has no metadata at all, so `exerciseMetadata` falls through to inference and
/// the alias silently does the opposite of its job.
///
/// One shipped that way — "Close Grip Lat Pulldown" pointed at "Close-Grip Lat Pulldown",
/// which no `ExerciseMetadata` declares. Nothing catches that by reading, because it looks
/// exactly like the 172 correct entries around it.
@MainActor
final class ExerciseAliasIntegrityTests: XCTestCase {

    private let service = ClaudeService.shared

    func testEveryAliasResolvesToACatalogueEntry() {
        let canonicalNames = Set(service.exerciseMetadataEntries.map(\.canonicalName))
        XCTAssertFalse(canonicalNames.isEmpty, "Premise: the catalogue is not empty")

        var dangling: [String] = []
        for (source, target) in ClaudeService.exerciseNameAliasCache where !canonicalNames.contains(target) {
            dangling.append("\"\(source)\" -> \"\(target)\"")
        }

        XCTAssertTrue(
            dangling.isEmpty,
            "Alias targets that are not catalogue entries, so they rename a movement into an "
                + "identity with no metadata: \(dangling.sorted().joined(separator: ", "))"
        )
    }

    /// The catalogue itself must not carry two entries under one name — a duplicate would make
    /// `exerciseMetadata` depend on which one a lookup happened to reach.
    func testCatalogueCanonicalNamesAreUnique() {
        let names = service.exerciseMetadataEntries.map(\.canonicalName)
        let duplicates = Dictionary(grouping: names, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()

        XCTAssertTrue(
            duplicates.isEmpty,
            "Duplicate canonical names in the exercise catalogue: \(duplicates.joined(separator: ", "))"
        )
    }
}
