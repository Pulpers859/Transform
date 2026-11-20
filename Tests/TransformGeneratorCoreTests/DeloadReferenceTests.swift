import XCTest
import SwiftData
@testable import Transform

/// Owner, 2026-11-20: after finishing the week-4 deload, the first week of the new block
/// suggested weights and reps from the deload sessions. A deload is lighter on purpose, so it
/// is not "what was lifted last time" while a full-week session exists.
///
/// The fixture is the owner's Machine Incline Press history from his screenshot: Oct 26
/// 160x12, 170x12, 180x10 and Nov 12 140x12, 140x12, 150x10. The day numbers are assumed
/// (week 3 and week 4, Day 1); the app does not show them.
final class DeloadReferenceTests: XCTestCase {
    private let key = "machine incline press"

    private func sets(_ pairs: [(Double, Int)]) -> [SetLogEntry] {
        pairs.enumerated().map { SetLogEntry(setNumber: $0.offset + 1, weightLbs: $0.element.0, repsCompleted: $0.element.1) }
    }

    private func session(_ day: Int, daysAgo: Int, _ pairs: [(Double, Int)], key: String? = nil) -> WorkoutPerformanceLogSnapshot {
        WorkoutPerformanceLogSnapshot(
            canonicalExerciseKey: key ?? self.key,
            loggedAt: Date(timeIntervalSince1970: 2_000_000_000 - Double(daysAgo) * 86_400),
            setLogs: sets(pairs),
            prescribedReps: "10-12",
            prescribedSets: 3,
            workoutDayNumber: day
        )
    }

    private var week3: [(Double, Int)] { [(160, 12), (170, 12), (180, 10)] }
    private var deload: [(Double, Int)] { [(140, 12), (140, 12), (150, 10)] }

    // MARK: - Which sessions are deload sessions

    func testOnlyWeekFourDaysAreDeloadSessions() {
        let deloadDays = (0...35).filter { MesocyclePhase.isDeloadSession(workoutDayNumber: $0) }
        XCTAssertEqual(deloadDays, Array(22...28))
    }

    func testSessionRuleMatchesTheWorkoutDaysOwnDeloadFlag() throws {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        for dayNumber in 1...35 {
            let day = WorkoutDay(dayNumber: dayNumber, dayName: "Day", muscleGroups: "Chest")
            context.insert(day)
            XCTAssertEqual(MesocyclePhase.isDeloadSession(workoutDayNumber: dayNumber), day.isDeloadWeek, "day \(dayNumber)")
        }
    }

    // MARK: - The selection rule (used by the card's previous-session lookup)

    func testDeloadSessionsAreDroppedWhenAFullWeekSessionExists() {
        let sessions = [(day: 15, id: "week3"), (day: 22, id: "deload")]
        let kept = MesocyclePhase.excludingDeloadSessions(sessions, workoutDayNumber: { $0.day }, isUsable: { _ in true })
        XCTAssertEqual(kept.map { $0.id }, ["week3"])
    }

    func testDeloadSessionsAreKeptWhenTheyAreAllThereIs() {
        let sessions = [(day: 22, id: "deload a"), (day: 26, id: "deload b")]
        let kept = MesocyclePhase.excludingDeloadSessions(sessions, workoutDayNumber: { $0.day }, isUsable: { _ in true })
        XCTAssertEqual(kept.map { $0.id }, ["deload a", "deload b"])
    }

    func testAFullWeekSessionWithNoSetsDoesNotHideTheDeload() {
        let sessions = [(day: 15, id: "empty week3", usable: false), (day: 22, id: "deload", usable: true)]
        let kept = MesocyclePhase.excludingDeloadSessions(sessions, workoutDayNumber: { $0.day }, isUsable: { $0.usable })
        XCTAssertEqual(kept.map { $0.id }, ["empty week3", "deload"])
    }

    func testLegacySessionsWithoutADayNumberCountAsFullWeek() {
        let sessions = [(day: 0, id: "legacy"), (day: 22, id: "deload")]
        let kept = MesocyclePhase.excludingDeloadSessions(sessions, workoutDayNumber: { $0.day }, isUsable: { _ in true })
        XCTAssertEqual(kept.map { $0.id }, ["legacy"])
    }

    // MARK: - Generation and card history (`progressionHistory`)

    func testNewBlockIsGradedFromTheLastFullWeekNotTheDeload() {
        let history = WorkoutProgressionEngine.progressionHistory([
            session(15, daysAgo: 17, week3),
            session(22, daysAgo: 0, deload)
        ])
        let latest = WorkoutProgressionEngine.latestUsableSetLogs(for: key, from: history)
        XCTAssertEqual(latest, sets(week3))

        let range = RepRange(low: 10, high: 12)
        let decision = WorkoutProgressionEngine.evaluate(
            latestSetLogs: latest, summaryWeight: 150, summaryReps: 10, repRange: range)
        let fromWeek3 = WorkoutProgressionEngine.evaluate(
            latestSetLogs: sets(week3), summaryWeight: 180, summaryReps: 10, repRange: range)
        XCTAssertEqual(decision?.workingWeight, fromWeek3?.workingWeight)
        XCTAssertNotEqual(decision?.workingWeight, WorkingSetAnalysis.analyze(sets(deload)).workingWeight)
    }

    func testTheDeloadsRecordedRepRangeDoesNotBecomeTheGradedOne() {
        var light = session(22, daysAgo: 0, deload)
        light.prescribedReps = "12-15"
        let history = WorkoutProgressionEngine.progressionHistory([session(15, daysAgo: 17, week3), light])
        let newest = history.filter { $0.canonicalExerciseKey == key }.max { $0.loggedAt < $1.loggedAt }
        XCTAssertEqual(newest?.prescribedReps, "10-12")
    }

    func testEachExerciseIsJudgedOnItsOwnHistory() {
        let other = "barbell curl"
        let history = WorkoutProgressionEngine.progressionHistory([
            session(15, daysAgo: 17, week3),
            session(22, daysAgo: 0, deload),
            session(23, daysAgo: 0, [(50, 12)], key: other)
        ])
        XCTAssertEqual(history.map(\.workoutDayNumber), [15, 23])
    }

    func testOrderIsPreserved() {
        let input = [
            session(3, daysAgo: 30, week3),
            session(22, daysAgo: 0, deload),
            session(15, daysAgo: 17, week3),
            session(1, daysAgo: 40, week3)
        ]
        XCTAssertEqual(WorkoutProgressionEngine.progressionHistory(input).map(\.workoutDayNumber), [3, 15, 1])
    }
}
