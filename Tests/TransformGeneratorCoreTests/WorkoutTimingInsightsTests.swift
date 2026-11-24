import XCTest
@testable import Transform

/// Council review of 2026-11-23 (owner-approved item 7). The Dashboard's "Workout Timing" card
/// could crown a time of day "Best results" from a single session, scored easier sessions higher
/// (a `(5 - effort)` term), added raw counts of better/worse sessions (so the slot trained most
/// often won), counted deload weeks, and dropped sessions started from midnight to 4:59 out of
/// every slot while still counting them in the total.
final class WorkoutTimingInsightsTests: XCTestCase {
    private func session(_ hour: Int, effort: Int = 4, stimulus: Int = 4, performance: Int = 0, deload: Bool = false) -> WorkoutTimingInsights.Session {
        WorkoutTimingInsights.Session(hour: hour, effort: effort, stimulus: stimulus, performance: performance, isDeload: deload)
    }

    func testOneSessionCannotBeTheBestTime() {
        let sessions = [session(6, effort: 1, stimulus: 5)] + Array(repeating: session(19), count: 8)
        let best = WorkoutTimingInsights.best(WorkoutTimingInsights.buckets(sessions))
        XCTAssertNotEqual(best?.label, "Early AM\n5-8")
    }

    /// A time with fewer than two eligible slots to compare has no "best".
    func testNoBestWithoutTwoSlotsToCompare() {
        let sessions = Array(repeating: session(19), count: 8)
        XCTAssertNil(WorkoutTimingInsights.best(WorkoutTimingInsights.buckets(sessions)))
    }

    /// Rates, not counts: 3 of 3 better beats 5 of 9 better.
    func testBetterSessionsAreJudgedAsAShare() {
        let morning = Array(repeating: session(10, performance: 1), count: 3)
        let evening = Array(repeating: session(19, performance: 1), count: 5) + Array(repeating: session(19), count: 4)
        let best = WorkoutTimingInsights.best(WorkoutTimingInsights.buckets(morning + evening))
        XCTAssertEqual(best?.label, "Morning\n9-11")
    }

    /// An easier session is not a better one.
    func testLowerEffortDoesNotScoreHigher() {
        let easy = Array(repeating: session(10, effort: 1), count: 3)
        let hard = Array(repeating: session(19, effort: 5), count: 3)
        let buckets = WorkoutTimingInsights.buckets(easy + hard)
        XCTAssertEqual(buckets.map(\.score), [buckets[0].score, buckets[0].score])
    }

    /// Equal scores name no best (follow-up review 2026-11-24: the earliest slot always won).
    func testATieNamesNoBest() {
        let sessions = Array(repeating: session(10), count: 3) + Array(repeating: session(19), count: 3)
        XCTAssertNil(WorkoutTimingInsights.best(WorkoutTimingInsights.buckets(sessions)))
    }

    func testAfterMidnightSessionsLandInTheNightSlot() {
        let sessions = [session(1), session(2), session(23)]
        let night = WorkoutTimingInsights.buckets(sessions).first { $0.label.hasPrefix("Night") }
        XCTAssertEqual(night?.sessionCount, 3)
    }

    func testDeloadWeeksAreLeftOut() {
        let sessions = Array(repeating: session(19), count: 3) + [session(10, deload: true)]
        let buckets = WorkoutTimingInsights.buckets(sessions)
        XCTAssertEqual(buckets.map(\.label), ["Evening\n18-20"])
    }
}
