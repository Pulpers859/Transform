import XCTest
@testable import Transform

/// The automatic-backup drop guard and launch-time recovery rules (`BackupEntryCounts`), and
/// how a deliberate, confirmed removal such as Reset Workout Day is acknowledged.
final class BackupDropGuardTests: XCTestCase {
    private func counts(logs: Int, summaries: Int) -> BackupEntryCounts {
        BackupEntryCounts(sleep: 30, weight: 10, nutrition: 0, measurement: 4,
                          exerciseWeights: summaries, exerciseLogs: logs, analyses: 2, workouts: 2)
    }

    /// Bug audit 2026-11-17, F2/F5. Resetting a 6-exercise day whose lifts have no other history
    /// removes 6 logs and 6 summaries. Unacknowledged, the backup after it was skipped and the
    /// next launch merged the pre-reset backup back in, undoing the reset; a smaller reset
    /// produced "Data loss detected" instead.
    func testAcknowledgedResetTriggersNeitherRecoveryNorALossWarning() {
        let baseline = counts(logs: 40, summaries: 20)
        let before = baseline
        let after = counts(logs: 34, summaries: 14)
        // The shape of the bug: without acknowledgement both rules fire on the owner's own reset.
        XCTAssertTrue(after.hasSignificantDrop(comparedTo: baseline))
        XCTAssertTrue(after.shouldAttemptAutomaticRecovery(comparedTo: baseline))

        let removed = BackupEntryCounts.deliberateRemoval(before: before, after: after)
        let adjusted = baseline.acknowledgingDeliberateRemoval(removed, after: after)
        XCTAssertFalse(after.hasSignificantDrop(comparedTo: adjusted))
        XCTAssertFalse(after.shouldAttemptAutomaticRecovery(comparedTo: adjusted))
        XCTAssertEqual(adjusted, after)
    }

    /// Records that were already missing before the reset, with no explanation, must stay
    /// visible to both rules: a deliberate action never launders an earlier loss.
    func testAcknowledgingAResetNeverHidesAnEarlierUnexplainedLoss() {
        let baseline = counts(logs: 40, summaries: 20)
        let before = counts(logs: 30, summaries: 20)   // 10 logs gone, unexplained
        let after = counts(logs: 24, summaries: 20)    // the reset removed 6 more
        let adjusted = baseline.acknowledgingDeliberateRemoval(
            BackupEntryCounts.deliberateRemoval(before: before, after: after), after: after)
        XCTAssertEqual(adjusted.exerciseLogs, 34)
        XCTAssertTrue(after.hasSignificantDrop(comparedTo: adjusted))
    }

    /// Sets logged after the baseline was taken and then reset must not loosen the guard for
    /// a later, unexplained loss. Subtracting the removal from the baseline alone would.
    func testAcknowledgingAResetDoesNotLoosenTheGuardBySetsLoggedSinceTheBaseline() {
        let baseline = counts(logs: 40, summaries: 20)
        let before = counts(logs: 46, summaries: 20)   // 6 logged since the last backup
        let after = counts(logs: 40, summaries: 20)    // and reset again
        let adjusted = baseline.acknowledgingDeliberateRemoval(
            BackupEntryCounts.deliberateRemoval(before: before, after: after), after: after)
        XCTAssertEqual(adjusted.exerciseLogs, 40)
        XCTAssertTrue(counts(logs: 37, summaries: 20).hasSignificantDrop(comparedTo: adjusted),
                      "Three logs vanishing later must still be caught")
    }

    /// A category that grew during the action removed nothing.
    func testDeliberateRemovalNeverGoesNegative() {
        let removed = BackupEntryCounts.deliberateRemoval(before: counts(logs: 10, summaries: 5),
                                                          after: counts(logs: 12, summaries: 3))
        XCTAssertEqual(removed.exerciseLogs, 0)
        XCTAssertEqual(removed.exerciseWeights, 2)
        XCTAssertEqual(removed.sleep, 0)
    }

    /// The stored baseline JSON keeps its keys, so counts saved by the previous version load.
    func testStoredCountsShapeIsUnchanged() throws {
        let original = counts(logs: 7, summaries: 3)
        let data = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertEqual(json["exerciseLogs"], 7)
        XCTAssertEqual(json["total"], original.total)
        XCTAssertEqual(try JSONDecoder().decode(BackupEntryCounts.self, from: data), original)
        let legacy = try JSONDecoder().decode(BackupEntryCounts.self, from: Data(#"{"sleep":3,"weight":2,"nutrition":1}"#.utf8))
        XCTAssertEqual(legacy.total, 6)
    }
}
