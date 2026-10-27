import Foundation
import XCTest
@testable import Transform

/// Measures every catalogued exercise's in-session swap list (owner, 2026-10-27: "the
/// substitutions need to be more broadened out"). For each exercise it records the live
/// alternatives and the near misses that a single rule refuses, so a broadening is designed
/// from the numbers rather than from one example. Diagnostic; writes
/// TRANSFORM_SWAP_COVERAGE_OUTPUT when set.
@MainActor
final class SwapCoverageEvidenceTests: XCTestCase {
    func testRecordEverySwapListAndWhatBlocksItsNearMisses() throws {
        let names = Set(ClaudeService.shared.exerciseMetadataCatalog.values.map(\.canonicalName)).sorted()
        var lines: [String] = []
        var counts: [Int] = []
        for name in names {
            var alternatives: [String] = []
            var nearMisses: [String] = []
            for other in names where other != name {
                let blockers = ExerciseReplacement.liveSwapBlockers(originalName: name, candidateName: other)
                if blockers.isEmpty { alternatives.append(other) }
                else if blockers.count == 1, blockers != ["same"], blockers != ["unknown"] {
                    nearMisses.append("\(other) [\(blockers[0])]")
                }
            }
            counts.append(alternatives.count)
            lines.append("\(name): \(alternatives.count) | \(alternatives.joined(separator: ", "))")
            if !nearMisses.isEmpty { lines.append("   near: \(nearMisses.joined(separator: "; "))") }
        }
        let histogram = Dictionary(grouping: counts, by: { min($0, 5) }).mapValues(\.count)
        lines.insert("exercises: \(names.count); with 0/1/2/3/4/5+ alternatives: "
            + (0...5).map { String(histogram[$0] ?? 0) }.joined(separator: "/"), at: 0)
        XCTAssertFalse(names.isEmpty)
        if let path = ProcessInfo.processInfo.environment["TRANSFORM_SWAP_COVERAGE_OUTPUT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
