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

    /// A full tie keeps the record where it was first set (data review, 2026-11-24): letting
    /// the newer tie take it over moved the best's date onto a session row, so correcting that
    /// session later rebuilt the best from rows only and lost an older best with no row behind it.
    func testHeavierWinsThenMoreRepsThenTheFirstToSetIt() {
        XCTAssertTrue(ExerciseBestRule.isBetter(record(30, 5, 0), than: record(25, 12, 1)))
        XCTAssertTrue(ExerciseBestRule.isBetter(record(25, 12, 0), than: record(25, 10, 1)))
        XCTAssertFalse(ExerciseBestRule.isBetter(record(25, 10, 1), than: record(25, 10, 0)))
        XCTAssertTrue(ExerciseBestRule.isBetter(record(25, 10, 0), than: record(25, 10, 1)))
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

    /// The owner-facing bug: 250 typed for 25, then corrected on the card. The corrected set
    /// only ties last week's 25 x 10, so the record stays where it was first set.
    func testCorrectingATypoLowersTheBestItSet() {
        let typo = record(250, 10, 0)
        let revised = record(25, 10, 0.01)
        let older = [record(25, 10, -7), record(22.5, 12, -14)]
        let best = ExerciseBestRule.revisedBest(storedBest: typo, sessionPreviousDate: typo.date,
                                                revisedSession: revised, otherSessions: older)
        XCTAssertEqual(best, record(25, 10, -7))
    }

    /// The data-review case: an old best with no session row, then a session that only ties
    /// it. The tie must not take the record over (and so cannot lose it on a later correction).
    func testATieNeverTakesOverAnOlderBest() {
        let legacy = record(200, 8, -200)
        XCTAssertEqual(ExerciseBestRule.revisedBest(storedBest: legacy, sessionPreviousDate: at(0),
                                                    revisedSession: record(200, 8, 0), otherSessions: []), legacy)
    }

    // MARK: - Which set is the session's record (exercise-evidence consult 2026-11-24)

    private func sets(_ pairs: [(Double, Int)]) -> [SetLogEntry] {
        pairs.enumerated().map { SetLogEntry(setNumber: $0.offset + 1, weightLbs: $0.element.0, repsCompleted: $0.element.1) }
    }

    /// A real top set followed by back-offs at 70%: the typo filter used for progression flags
    /// the 100, but it is the session's record.
    func testATopSetWithBackOffsIsTheRecord() throws {
        let top = try XCTUnwrap(ExerciseBestRule.recordTop(from: sets([(100, 3), (70, 10), (70, 10)])))
        XCTAssertEqual(top.weightLbs, 100)
        XCTAssertEqual(top.reps, 3)
    }

    /// A lone set at twice the session's middle weight or more is still treated as a typo.
    func testALoneDoubleWeightSetIsNotARecord() throws {
        XCTAssertEqual(try XCTUnwrap(ExerciseBestRule.recordTop(from: sets([(250, 10), (25, 10), (25, 10)]))).weightLbs, 25)
        XCTAssertEqual(try XCTUnwrap(ExerciseBestRule.recordTop(from: sets([(180, 8), (90, 8), (90, 8)]))).weightLbs, 90)
        // Repeated, it is real.
        XCTAssertEqual(try XCTUnwrap(ExerciseBestRule.recordTop(from: sets([(180, 8), (180, 8), (90, 8)]))).weightLbs, 180)
    }

    /// The heaviest set is the record even when a lighter set has the higher estimated max
    /// (devil's advocate, 2026-11-24: 200x6 then 195x10 dropped the best back to 195x10, and the
    /// next week's 200x6 announced a "new best" again).
    func testTheHeaviestSetIsTheRecordNotTheHighestEstimate() throws {
        let top = try XCTUnwrap(ExerciseBestRule.recordTop(from: sets([(200, 6), (195, 10)])))
        XCTAssertEqual(top.weightLbs, 200)
        XCTAssertEqual(top.reps, 6)
    }

    /// Bodyweight: the record is the most reps.
    func testBodyweightRecordIsTheMostReps() throws {
        let top = try XCTUnwrap(ExerciseBestRule.recordTop(from: sets([(0, 12), (0, 15), (0, 10)])))
        XCTAssertEqual(top.reps, 15)
    }

    // MARK: - Other paths that write a best or "Last"

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// Duplicate summaries merged at startup ranked equal-weight bests by date alone.
    @MainActor
    func testMergingDuplicateSummariesKeepsTheMoreRepsBest() throws {
        let ctx = try context()
        let older = ExerciseWeightEntry(loggedAt: at(0), exerciseName: "Push-Up", weightLbs: 0, repsCompleted: 20)
        let newer = ExerciseWeightEntry(loggedAt: at(7), exerciseName: "Push-Up", weightLbs: 0, repsCompleted: 12)
        ctx.insert(older)
        ctx.insert(newer)
        _ = try ExerciseWeightStore.normalizeAndConsolidate(in: ctx)
        try ctx.save()
        // The newest summary survives and carries the merged best.
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ExerciseWeightEntry>()), 1)
        XCTAssertEqual(newer.bestRepsCompleted, 20)
    }

    /// Correcting a set in an OLD session must not make that session the "Last" one.
    func testAnOlderLogDoesNotRewindLast() throws {
        let ctx = try context()
        let entry = ExerciseWeightEntry(loggedAt: at(14), exerciseName: "Cable Curl", weightLbs: 30, repsCompleted: 10)
        ctx.insert(entry)
        entry.applyLog(loggedAt: at(0), exerciseName: "Cable Curl", weightLbs: 25, repsCompleted: 12, notes: "")
        XCTAssertEqual(entry.loggedAt, at(14))
        XCTAssertEqual(entry.weightLbs, 30)
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
