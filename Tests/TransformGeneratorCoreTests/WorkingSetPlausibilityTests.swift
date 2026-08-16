import XCTest
@testable import Transform

/// A logged load feeds the stored best AND the next session's target, so a mis-keyed entry
/// is not a cosmetic problem — it silently re-baselines the coaching. Two of the three
/// guards need history to work (the intra-session detector needs 3+ sets to establish a
/// center; the cross-session check needs a previous session), which leaves the first
/// single-set session of an exercise unguarded.
///
/// What is pinned here is deliberately narrow: an ABSOLUTE ceiling, which is the only thing
/// decidable with no reference load. It catches heavy-lift-scale slips (175 -> 1755) and by
/// design does NOT catch a first-ever 25 lb curl entered as 250 — nothing in the data can.
/// The threshold's real risk is the opposite direction, so the boundary is pinned on both
/// sides: a false "typing slip" on a genuine heavy leg press would be worse than the miss.
final class WorkingSetPlausibilityTests: XCTestCase {

    private func set(_ number: Int, _ weight: Double, _ reps: Int) -> SetLogEntry {
        SetLogEntry(setNumber: number, weightLbs: weight, repsCompleted: reps)
    }

    // MARK: - The hole the other two guards leave open

    /// The exact fat-finger case: 175 typed as 1755, one set, first time doing the lift.
    func testSingleMisKeyedSetIsFlaggedWithNoHistoryAtAll() {
        let analysis = WorkingSetAnalysis.analyze([set(1, 1755, 12)])
        XCTAssertEqual(analysis.implausibleSets.count, 1)
        XCTAssertEqual(analysis.implausibleSets.first?.setNumber, 1)
    }

    /// Two sets is still below the intra-session detector's 3-set minimum.
    func testTwoSetSessionIsStillCoveredWhereTheAnomalyDetectorCannotRun() {
        let analysis = WorkingSetAnalysis.analyze([set(1, 1750, 10), set(2, 175, 10)])
        XCTAssertTrue(analysis.anomalies.isEmpty, "Precondition: the center-based detector needs 3+ sets")
        XCTAssertEqual(analysis.implausibleSets.map(\.setNumber), [1])
        // Pinned because the card's wording branches on this: nothing excluded it, so it IS
        // driving the best and the next target and must get the stronger sentence.
        XCTAssertEqual(analysis.implausibleSets.first?.role, .working)
    }

    /// A dropped decimal reads as a plain number, so nothing upstream rejects it.
    func testDroppedDecimalIsFlagged() {
        XCTAssertFalse(WorkingSetAnalysis.analyze([set(1, 1225, 8)]).implausibleSets.isEmpty)
    }

    // MARK: - Must never argue with a real session

    /// A fully plate-loaded leg press is the heaviest thing anyone actually logs here.
    /// If this ever fires, the threshold is wrong — a false "typing slip" on a genuine PR
    /// is worse than the miss it was added to prevent.
    func testHeavyButRealLegPressIsNotFlagged() {
        for load in [405.0, 720.0, 900.0, 1080.0] {
            XCTAssertTrue(
                WorkingSetAnalysis.analyze([set(1, load, 8)]).implausibleSets.isEmpty,
                "\(load) lb is a real training load and must not be called a typing slip"
            )
        }
    }

    /// The pre-save sheet judges a typed draft through this predicate rather than through
    /// `analyze`, so it is pinned directly — the sheet itself is a SwiftUI/SwiftData view
    /// outside this harness and its wiring cannot be executed here.
    func testSharedPredicateMatchesTheSetLevelClassification() {
        for load in [0.0, 45.0, 500.0, 1199.0, 1200.0, 5000.0] {
            XCTAssertEqual(
                WorkingSetAnalysis.isImplausibleLoad(load),
                !WorkingSetAnalysis.analyze([set(1, load, 10)]).implausibleSets.isEmpty,
                "The draft-time and saved-set answers must agree at \(load) lb"
            )
        }
    }

    /// The cutover itself, pinned on both sides so it cannot drift silently. 1150 is a
    /// reachable sled load; 1200 is the declared boundary and is inclusive.
    func testThresholdBoundaryIsPinnedOnBothSides() {
        XCTAssertEqual(WorkingSetAnalysis.implausibleLoadLbs, 1200)
        XCTAssertTrue(WorkingSetAnalysis.analyze([set(1, 1150, 8)]).implausibleSets.isEmpty)
        XCTAssertTrue(WorkingSetAnalysis.analyze([set(1, 1199.5, 8)]).implausibleSets.isEmpty)
        XCTAssertFalse(WorkingSetAnalysis.analyze([set(1, 1200, 8)]).implausibleSets.isEmpty)
        XCTAssertFalse(WorkingSetAnalysis.analyze([set(1, 1250, 8)]).implausibleSets.isEmpty)
    }

    /// The documented limit, asserted so nobody "fixes" it by tightening the ceiling into
    /// the range where real training loads live. An ordinary-magnitude typo on a FIRST-ever
    /// session is not detectable here and is handled by the cross-session check from the
    /// second session onward.
    func testOrdinaryMagnitudeTypoIsExplicitlyOutOfScope() {
        XCTAssertTrue(
            WorkingSetAnalysis.analyze([set(1, 250, 12)]).implausibleSets.isEmpty,
            "250 lb is a real load on plenty of movements; only history can judge it"
        )
    }

    func testBodyweightAndOrdinaryLoadsAreNotFlagged() {
        let analysis = WorkingSetAnalysis.analyze([set(1, 0, 15), set(2, 25, 12), set(3, 185, 8)])
        XCTAssertTrue(analysis.implausibleSets.isEmpty)
    }

    // MARK: - Relationship to the existing detector

    /// The two checks are independent: a normal-magnitude outlier stays the anomaly
    /// detector's job, and must not start reporting as a typing slip.
    func testOrdinaryOutlierRemainsAnAnomalyAndNotAnImplausibleLoad() {
        let analysis = WorkingSetAnalysis.analyze([set(1, 90, 10), set(2, 90, 10), set(3, 180, 10), set(4, 90, 10)])
        XCTAssertEqual(analysis.anomalies.map(\.setNumber), [3])
        XCTAssertTrue(analysis.implausibleSets.isEmpty)
    }

    /// An implausible load is still an anomaly when there are enough sets to see it —
    /// the view's branch order (implausible first) is what keeps the message specific.
    func testImplausibleLoadAlsoRegistersAsAnAnomalyWhenTheSessionHasEnoughSets() {
        let analysis = WorkingSetAnalysis.analyze([set(1, 175, 10), set(2, 175, 10), set(3, 1755, 10)])
        XCTAssertEqual(analysis.anomalies.map(\.setNumber), [3])
        XCTAssertEqual(analysis.implausibleSets.map(\.setNumber), [3])
        XCTAssertEqual(analysis.workingWeight, 175, "The mis-log must not become the working load")
    }

    /// The card's wording branches on this role, because the CONSEQUENCE differs: a mis-log
    /// the anomaly rule already caught is not driving anything, and telling the lifter it
    /// "becomes your best and your next target" there would be a false statement. Only a set
    /// that survives as `.working` actually feeds `topWorkingSet`.
    func testRoleDistinguishesADrivingMisLogFromAnAlreadyExcludedOne() {
        let excluded = WorkingSetAnalysis.analyze([set(1, 175, 10), set(2, 175, 10), set(3, 1755, 10)])
        XCTAssertEqual(excluded.implausibleSets.first?.role, .anomaly)
        XCTAssertEqual(excluded.topWorkingSet?.weightLbs, 175)

        let driving = WorkingSetAnalysis.analyze([set(1, 1755, 10)])
        XCTAssertEqual(driving.implausibleSets.first?.role, .working)
        XCTAssertEqual(driving.topWorkingSet?.weightLbs, 1755, "Nothing can exclude it — hence the stronger warning")
    }
}
