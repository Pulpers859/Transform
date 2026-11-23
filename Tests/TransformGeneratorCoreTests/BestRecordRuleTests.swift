import XCTest
import SwiftData
@testable import Transform

/// Council review of 2026-11-23 (owner-approved item 3).
///
/// * A typo (250 instead of 25) raised the stored best, fired the "New best" banner, and
///   correcting the set on the card did not lower it again: the card's path only ever raised.
/// * The history screen's rebuild broke ties at equal weight by "newest wins" while every other
///   path preferred more reps, so editing there could swap BW x 20 for BW x 12 and let the next
///   ordinary session announce a false best.
final class BestRecordRuleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private func at(_ days: Double) -> Date { t0.addingTimeInterval(days * 86_400) }
    private func record(_ weight: Double, _ reps: Int?, _ days: Double) -> ExerciseBestCandidate {
        ExerciseBestCandidate(date: at(days), weightLbs: weight, reps: reps)
    }

    // MARK: - One ordering

    func testHeavierWinsThenMoreRepsThenNewer() {
        XCTAssertTrue(ExerciseBestRule.isBetter(record(30, 5, 0), than: record(25, 12, 1)))
        XCTAssertTrue(ExerciseBestRule.isBetter(record(25, 12, 0), than: record(25, 10, 1)))
        XCTAssertTrue(ExerciseBestRule.isBetter(record(25, 10, 1), than: record(25, 10, 0)))
        XCTAssertFalse(ExerciseBestRule.isBetter(record(25, 10, 1), than: record(25, 11, 0)))
    }

    /// The history-screen case: bodyweight 20 reps must stay the best over a newer 12.
    func testRebuildKeepsMoreRepsAtEqualWeight() {
        let best = ExerciseBestRule.best(of: [record(0, 20, 0), record(0, 12, 7)])
        XCTAssertEqual(best, record(0, 20, 0))
    }

    /// The rebuild and the card's step-by-step path must name the same best for any history.
    func testRebuildMatchesTheStepByStepPath() throws {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let histories: [[ExerciseBestCandidate]] = [
            [record(0, 20, 0), record(0, 12, 7), record(0, 15, 14)],
            [record(100, 8, 0), record(100, 8, 7), record(95, 12, 14)],
            [record(50, 10, 0), record(55, 6, 7), record(55, 8, 14), record(55, 8, 21)],
        ]
        for history in histories {
            let first = history[0]
            let entry = ExerciseWeightEntry(loggedAt: first.date, exerciseName: "Cable Curl",
                                            weightLbs: first.weightLbs, repsCompleted: first.reps)
            context.insert(entry)
            for step in history.dropFirst() {
                entry.applyLog(loggedAt: step.date, exerciseName: "Cable Curl",
                               weightLbs: step.weightLbs, repsCompleted: step.reps, notes: "")
            }
            let rebuilt = try XCTUnwrap(ExerciseBestRule.best(of: history))
            XCTAssertEqual(entry.bestWeightLbs, rebuilt.weightLbs, "\(history)")
            XCTAssertEqual(entry.bestRepsCompleted, rebuilt.reps, "\(history)")
            XCTAssertEqual(entry.bestLoggedAt, rebuilt.date, "\(history)")
        }
    }

    // MARK: - Correcting one session

    /// The owner-facing bug: 250 typed for 25, then corrected on the card.
    func testCorrectingATypoLowersTheBestItSet() {
        let typo = record(250, 10, 0)
        let revised = record(25, 10, 0.01)
        let older = [record(25, 10, -7), record(22.5, 12, -14)]
        let best = ExerciseBestRule.revisedBest(storedBest: typo, sessionPreviousDate: typo.date,
                                                revisedSession: revised, otherSessions: older)
        XCTAssertEqual(best, revised)
    }

    /// Clearing the typo set entirely (the session no longer counts) falls back to history.
    func testRemovingTheSessionThatSetTheBestFallsBackToHistory() {
        let typo = record(250, 10, 0)
        let older = [record(25, 10, -7), record(22.5, 12, -14)]
        let best = ExerciseBestRule.revisedBest(storedBest: typo, sessionPreviousDate: typo.date,
                                                revisedSession: nil, otherSessions: older)
        XCTAssertEqual(best, record(25, 10, -7))
    }

    /// A best this session did not set is never lowered, even when no log row supports it
    /// (legacy summaries predate performance logs).
    func testABestFromAnotherSessionIsKept() {
        let legacy = record(100, 8, -60)
        let best = ExerciseBestRule.revisedBest(storedBest: legacy, sessionPreviousDate: at(0),
                                                revisedSession: record(90, 10, 0), otherSessions: [record(85, 10, -7)])
        XCTAssertEqual(best, legacy)
    }

    func testASessionThatBeatsAnotherSessionsBestTakesIt() {
        let best = ExerciseBestRule.revisedBest(storedBest: record(100, 8, -7), sessionPreviousDate: at(0),
                                                revisedSession: record(105, 6, 0), otherSessions: [record(100, 8, -7)])
        XCTAssertEqual(best, record(105, 6, 0))
    }

    /// Removing the only session that ever counted leaves no best.
    func testRemovingTheOnlySessionLeavesNoBest() {
        let only = record(250, 10, 0)
        XCTAssertNil(ExerciseBestRule.revisedBest(storedBest: only, sessionPreviousDate: only.date,
                                                  revisedSession: nil, otherSessions: []))
    }
}
