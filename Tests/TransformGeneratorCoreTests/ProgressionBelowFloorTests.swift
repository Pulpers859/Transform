import XCTest
@testable import Transform

/// Pins the two facts the below-range coaching sentence is built from.
///
/// The card described EVERY below-range session as "a working set dropped to N" — wording
/// that means one set slipped among good ones. It rendered unchanged for a real session
/// where nothing reached the target (55 lb for 14 and 12 against a 15-20 prescription),
/// so the harder case read as the milder one. The sentence lives in a SwiftUI file that
/// this harness cannot compile, but the count it reads from is engine state and is pinned
/// here.
///
/// Also pins that the shared 1RM estimator answers for high-rep sets. The progression
/// chart used to carry its own copy that silently DISCARDED anything over 15 reps, so a
/// lifter training accessories at 15-20 had almost every point deleted and the chart drew
/// a lone dot with no line.
@MainActor
final class ProgressionBelowFloorTests: XCTestCase {

    private func set(_ n: Int, weight: Double, reps: Int, rir: Double? = nil) -> SetLogEntry {
        SetLogEntry(setNumber: n, weightLbs: weight, repsCompleted: reps, rir: rir)
    }

    private func decision(
        _ logs: [SetLogEntry],
        range: RepRange,
        summaryWeight: Double? = nil,
        summaryReps: Int? = nil
    ) throws -> WorkoutProgressionDecision {
        try XCTUnwrap(WorkoutProgressionEngine.evaluate(
            latestSetLogs: logs,
            summaryWeight: summaryWeight ?? logs.first?.weightLbs,
            summaryReps: summaryReps ?? logs.first?.repsCompleted,
            repRange: range
        ))
    }

    // MARK: - Below-floor counting

    /// The exact session that produced the misleading copy.
    func testEverySetUnderTheFloorIsCountedAsEverySet() throws {
        let result = try decision(
            [set(1, weight: 55, reps: 14), set(2, weight: 55, reps: 12)],
            range: RepRange(low: 15, high: 20)
        )
        XCTAssertEqual(result.kind, .holdBelowRange)
        XCTAssertEqual(result.workingSetCount, 2)
        XCTAssertEqual(result.belowFloorSetCount, 2,
                       "Both sets missed 15; copy calling this 'a working set' understates it")
        XCTAssertEqual(result.minimumWorkingReps, 12)
    }

    /// The case the old wording actually described, which must stay distinguishable.
    func testOneSlippedSetAmongGoodOnesCountsOnce() throws {
        let result = try decision(
            [set(1, weight: 55, reps: 16), set(2, weight: 55, reps: 18), set(3, weight: 55, reps: 12)],
            range: RepRange(low: 15, high: 20)
        )
        XCTAssertEqual(result.kind, .holdBelowRange)
        XCTAssertEqual(result.workingSetCount, 3)
        XCTAssertEqual(result.belowFloorSetCount, 1,
                       "One set under the floor is a different session from all of them")
    }

    func testSetsInsideTheRangeCountNoMisses() throws {
        let result = try decision(
            [set(1, weight: 55, reps: 16), set(2, weight: 55, reps: 17), set(3, weight: 55, reps: 18)],
            range: RepRange(low: 15, high: 20)
        )
        XCTAssertEqual(result.kind, .addRepsInRange)
        XCTAssertEqual(result.belowFloorSetCount, 0)
    }

    /// A rep count equal to the floor is inside the range, not a miss.
    func testRepsExactlyOnTheFloorAreNotAMiss() throws {
        let result = try decision(
            [set(1, weight: 47, reps: 15), set(2, weight: 47, reps: 20)],
            range: RepRange(low: 15, high: 20)
        )
        XCTAssertEqual(result.belowFloorSetCount, 0)
        XCTAssertNotEqual(result.kind, .holdBelowRange)
    }

    /// Legacy records with no per-set detail analyse no working sets, so they must claim
    /// no miss count rather than an invented one; their copy never cites a count.
    func testSummaryOnlyEvidenceClaimsNoSetCounts() throws {
        let result = try XCTUnwrap(WorkoutProgressionEngine.evaluate(
            latestSetLogs: [],
            summaryWeight: 55,
            summaryReps: 12,
            repRange: RepRange(low: 15, high: 20)
        ))
        XCTAssertEqual(result.kind, .holdBelowRange)
        XCTAssertFalse(result.usedPerSetEvidence)
        XCTAssertEqual(result.workingSetCount, 0)
        XCTAssertEqual(result.belowFloorSetCount, 0)
    }

    // MARK: - Shared 1RM estimator

    func testHighRepSetsStillProduceAnEstimate() {
        // The progression chart's private copy returned nothing above 15 reps, deleting
        // whole sessions from the graph instead of plotting them.
        let e1rm = WorkingSetAnalysis.estimatedOneRepMax(weight: 50, reps: 20)
        XCTAssertGreaterThan(e1rm, 0, "A 20-rep set is real training, not missing data")
        XCTAssertEqual(e1rm, 50 * (1 + 20.0 / 30.0), accuracy: 0.001,
                       "Above Brzycki's reliable range the estimate is Epley alone")
    }

    func testEstimateBlendsInsideBrzyckiReliableRange() {
        let epley = 55 * (1 + 12.0 / 30.0)
        let brzycki = 55 * 36.0 / (37.0 - 12.0)
        XCTAssertEqual(WorkingSetAnalysis.estimatedOneRepMax(weight: 55, reps: 12),
                       (epley + brzycki) / 2, accuracy: 0.001)
    }

    func testZeroLoadOrZeroRepsHasNoEstimate() {
        XCTAssertEqual(WorkingSetAnalysis.estimatedOneRepMax(weight: 0, reps: 15), 0)
        XCTAssertEqual(WorkingSetAnalysis.estimatedOneRepMax(weight: 55, reps: 0), 0)
    }
}
