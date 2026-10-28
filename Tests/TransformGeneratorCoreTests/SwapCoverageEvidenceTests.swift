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

    /// Swaps a lifter would reasonably reach for when the planned station is busy. Each pair
    /// shares the muscle and the joint action; several cross a label the catalog splits finely
    /// (Mid Back vs Upper Back rows, Chest vs Upper Chest presses, pressdowns vs extensions)
    /// or are a step harder (Leg Press to Back Squat, the owner's own example). Owner,
    /// 2026-10-27: "in general the substitutions need to be more broadened out".
    func testSwapsAcrossFinelySplitLabelsAreOffered() {
        let pairs: [(String, String)] = [
            ("Leg Press", "Back Squat"),
            ("Leg Press", "Dumbbell Bulgarian Split Squat"),
            ("Dumbbell Walking Lunge", "Dumbbell Bulgarian Split Squat"),
            ("Seated Cable Row", "Chest-Supported Row"),
            ("Machine Row", "Single-Arm Dumbbell Row"),
            ("Lat Pulldown", "Single-Arm Cable Row"),
            ("Lat Pulldown", "Pull-Up (Weighted or Assisted)"),
            ("Machine Chest Press", "Flat Barbell Bench Press"),
            ("Incline Dumbbell Press", "Dumbbell Bench Press"),
            ("Cable Triceps Pressdown", "Overhead Cable Triceps Extension"),
            ("Dumbbell Hammer Curl", "Incline Dumbbell Curl"),
            ("Chest-Supported Rear Delt Row", "Reverse Pec Deck"),
            ("Barbell Overhead Press", "Landmine Press"),
            ("Trap Bar Deadlift", "Barbell Romanian Deadlift"),
            ("Glute-Ham Raise", "Seated Leg Curl"),
            ("Barbell Hip Thrust", "45-Degree Back Extension"),
            ("Dip (Assisted or Weighted)", "Close-Grip Barbell Bench Press"),
            ("Cable Crunch", "Hanging Knee Raise"),
        ]
        for (original, candidate) in pairs {
            XCTAssertEqual(ExerciseReplacement.liveSwapBlockers(originalName: original, candidateName: candidate), [],
                           "\(original) -> \(candidate)")
        }
    }

    /// The broadening must not reach a different muscle, swap an isolation for a compound,
    /// or raise shoulder risk (the owner reports shoulder pain when pressing overhead).
    func testSwapsThatChangeTheJobOrRaiseShoulderRiskStayRefused() {
        let pairs: [(String, String)] = [
            ("Landmine Press", "Machine Shoulder Press"),
            ("Dumbbell Shoulder Press", "Barbell Overhead Press"),
            ("Machine Shoulder Press", "Barbell Overhead Press"),
            ("Close-Grip Barbell Bench Press", "Dip (Assisted or Weighted)"),
            ("Incline Smith Machine Press", "Machine Shoulder Press"),
            ("Dumbbell Lateral Raise", "Machine Shoulder Press"),
            ("Machine Lateral Raise", "Cable Upright Row"),
            ("Seated Cable Row", "Lat Pulldown"),
            ("Seated Leg Curl", "Barbell Curl"),
            ("Cable Triceps Pressdown", "Machine Leg Extension"),
            ("Leg Press", "Barbell Romanian Deadlift"),
            ("Machine Leg Extension", "Leg Press"),
            ("Seated Leg Curl", "Nordic Hamstring Curl"),
            ("Cable Fly", "Machine Chest Press"),
            ("Cable Face Pull", "Reverse Pec Deck"),
            ("Barbell Shrug", "Barbell Bent-Over Row"),
        ]
        for (original, candidate) in pairs {
            XCTAssertFalse(ExerciseReplacement.liveSwapBlockers(originalName: original, candidateName: candidate).isEmpty,
                           "\(original) -> \(candidate)")
        }
    }

    /// Every catalogued exercise has a live alternative except three. Landmine Press and
    /// Close-Grip Bench: every same-job option carries more shoulder risk. Cable Upright Row:
    /// no other upright row is catalogued, and lateral raises are another job and class. On 6599156, 20
    /// exercises had none (swap-coverage.txt).
    func testOnlyShoulderProtectedExercisesHaveNoAlternative() {
        let names = Set(ClaudeService.shared.exerciseMetadataCatalog.values.map(\.canonicalName))
        let stranded = names.filter { name in
            !names.contains { other in
                other != name && ExerciseReplacement.liveSwapBlockers(originalName: name, candidateName: other).isEmpty
            }
        }
        XCTAssertEqual(stranded, ["Cable Upright Row", "Close-Grip Barbell Bench Press", "Landmine Press"])
    }

    /// The picker labels a harder option and a shifted emphasis; a like-for-like swap carries
    /// no note.
    func testPickerLabelsHarderAndShiftedEmphasisSwaps() {
        XCTAssertNil(ExerciseReplacement.liveSwapNote(originalName: "Leg Press", candidateName: "Hack Squat"))
        XCTAssertEqual(ExerciseReplacement.liveSwapNote(originalName: "Leg Press", candidateName: "Back Squat"),
                       "Harder: more tiring than the planned exercise")
        XCTAssertEqual(ExerciseReplacement.liveSwapNote(originalName: "Incline Dumbbell Press", candidateName: "Dumbbell Bench Press"),
                       "Works Chest rather than Upper Chest")
        XCTAssertEqual(ExerciseReplacement.liveSwapNote(originalName: "Seated Cable Row", candidateName: "Barbell Bent-Over Row"),
                       "Harder: more tiring than the planned exercise. Works Upper Back rather than Mid Back")
    }
}
