import XCTest
@testable import Transform

/// Headless coverage for the session completion / clock state machine.
///
/// Both bugs pinned here were reported from a real session: the feedback sheet showed a
/// finish time ten minutes earlier than the wall clock, and skipping the last exercise for
/// time never surfaced the feedback prompt at all. Every path that can finish a day now
/// funnels through `SessionLifecycle`, so these are the rules that keep it honest.
@MainActor
final class SessionLifecycleTests: XCTestCase {

    // MARK: - Builders

    private func makeDay(exerciseCount: Int = 3) -> WorkoutDay {
        let day = WorkoutDay(dayNumber: 1, dayName: "Push", muscleGroups: "Chest, Shoulders")
        for index in 0..<exerciseCount {
            let exercise = WorkoutExercise(
                order: index,
                exerciseName: "Exercise \(index)",
                sets: 3,
                reps: "8-12"
            )
            exercise.day = day
            day.exercises.append(exercise)
        }
        return day
    }

    /// Today at a fixed clock time. Anchored to the current day so the `isDateInToday`
    /// guards behave, and to fixed hours so ordering never depends on what time CI runs.
    private func at(_ hour: Int, _ minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    // MARK: - Finish time reflects the finish, not the last logged set

    /// The reported bug: the clock stopped at the last logged set (7:06) while the athlete
    /// actually finished at 7:16, silently shaving ten minutes off the session.
    func testFinishingStampsTheFinishTimeNotTheLastLoggedSet() {
        let day = makeDay()
        day.sessionStartedAt = at(6, 43)
        day.sessionEndedAt = at(7, 6)   // last logged set

        for exercise in day.exercises { exercise.isCompleted = true }
        let transition = SessionLifecycle.syncDayCompletion(for: day, now: at(7, 16))

        XCTAssertEqual(transition, .justFinished)
        XCTAssertEqual(day.sessionEndedAt, at(7, 16))
        XCTAssertEqual(day.sessionDurationMinutes, 33)
        XCTAssertTrue(day.isSessionClosed)
    }

    /// Re-opening feedback later must not keep pushing the end forward — the second call
    /// is the athlete revisiting a finished session, not training for another hour.
    func testClosingIsIdempotent() {
        let day = makeDay()
        day.sessionStartedAt = at(6, 43)
        for exercise in day.exercises { exercise.isCompleted = true }
        SessionLifecycle.syncDayCompletion(for: day, now: at(7, 16))

        SessionLifecycle.markSessionEnded(for: day, now: at(8, 30))

        XCTAssertEqual(day.sessionEndedAt, at(7, 16))
    }

    /// A set corrected the next day must not rewrite a finished session's clock.
    func testSetLoggedOnAClosedSessionDoesNotMoveTheClock() {
        let day = makeDay()
        day.sessionStartedAt = at(6, 43)
        for exercise in day.exercises { exercise.isCompleted = true }
        SessionLifecycle.syncDayCompletion(for: day, now: at(7, 16))

        SessionLifecycle.noteSetLogged(for: day.exercises[0], at: at(7, 30))

        XCTAssertEqual(day.sessionEndedAt, at(7, 16))
    }

    /// Submitted feedback is the athlete's own word on the session; nothing may overwrite it.
    func testRatedSessionIsNeverRestamped() {
        let day = makeDay()
        day.sessionStartedAt = at(6, 43)
        day.sessionEndedAt = at(7, 16)
        day.feedbackSubmittedAt = at(7, 20)

        SessionLifecycle.markSessionEnded(for: day, now: at(9, 0))

        XCTAssertEqual(day.sessionEndedAt, at(7, 16))
    }

    // MARK: - Ran out of time

    /// The second reported bug: the last exercise was skipped for time rather than
    /// completed, so the day never finished and the feedback sheet never appeared.
    func testSkippingTheLastExerciseFinishesTheDay() {
        let day = makeDay()
        day.sessionStartedAt = at(6, 43)
        for exercise in day.exercises.dropLast() { exercise.isCompleted = true }

        let last = day.exercises.last!
        last.completionStatus = .skippedTime
        last.isCompleted = true
        let transition = SessionLifecycle.syncDayCompletion(for: day, now: at(7, 16))

        XCTAssertEqual(transition, .justFinished)
        XCTAssertTrue(day.isCompleted)
        XCTAssertEqual(day.sessionEndedAt, at(7, 16))
    }

    func testSkipForAnyReasonResolvesTheExercise() {
        for status: ExerciseCompletionStatus in [.skippedTime, .skippedEquipment, .skippedPain] {
            let day = makeDay(exerciseCount: 1)
            let exercise = day.exercises[0]
            exercise.completionStatus = status
            exercise.isCompleted = true

            XCTAssertTrue(exercise.isResolved, "\(status.rawValue) should resolve the exercise")
            XCTAssertEqual(SessionLifecycle.syncDayCompletion(for: day, now: at(7, 16)), .justFinished)
        }
    }

    /// A substitution is work the athlete still performs, so it must not finish the day on
    /// its own — that would tick off a session with real sets still outstanding.
    func testSubstitutionAloneDoesNotFinishTheDay() {
        let day = makeDay(exerciseCount: 1)
        day.exercises[0].completionStatus = .substituted

        XCTAssertFalse(day.exercises[0].isResolved)
        XCTAssertEqual(SessionLifecycle.syncDayCompletion(for: day, now: at(7, 16)), .unchanged)
        XCTAssertFalse(day.isCompleted)
    }

    // MARK: - Re-opening

    /// Clearing a skip means training resumed: the day re-opens and the clock tracks again.
    func testClearingASkipReopensTheDayAndTheClock() {
        let day = makeDay()
        day.sessionStartedAt = at(6, 43)
        for exercise in day.exercises { exercise.isCompleted = true }
        day.exercises.last!.completionStatus = .skippedTime
        SessionLifecycle.syncDayCompletion(for: day, now: at(7, 16))

        let last = day.exercises.last!
        last.completionStatus = nil
        last.isCompleted = false
        let transition = SessionLifecycle.syncDayCompletion(for: day, now: at(7, 20))

        XCTAssertEqual(transition, .reopened)
        XCTAssertFalse(day.isCompleted)
        XCTAssertFalse(day.isSessionClosed)
        // The recorded end survives the re-open; resumed work advances it from there.
        XCTAssertEqual(day.sessionEndedAt, at(7, 16))

        SessionLifecycle.noteSetLogged(for: last, at: at(7, 30))
        XCTAssertEqual(day.sessionEndedAt, at(7, 30))
    }

    // MARK: - Guards

    /// `allSatisfy` on an empty collection is true, which would silently tick off rest days.
    func testEmptyDayIsNeverAutoFinished() {
        let day = WorkoutDay(dayNumber: 2, dayName: "Rest", muscleGroups: "", isRestDay: true)

        XCTAssertFalse(day.allExercisesResolved)
        XCTAssertEqual(SessionLifecycle.syncDayCompletion(for: day, now: at(7, 16)), .unchanged)
        XCTAssertFalse(day.isCompleted)
    }

    func testFirstLoggedSetBackdatesTheStartByTheWarmupLead() {
        let day = makeDay()
        let now = Date()

        SessionLifecycle.noteSetLogged(for: day.exercises[0], at: now)

        let expected = now.addingTimeInterval(-Double(SessionLifecycle.inferredWarmupLeadMinutes) * 60)
        XCTAssertEqual(day.sessionStartedAt!.timeIntervalSince(expected), 0, accuracy: 0.001)
        XCTAssertEqual(day.sessionEndedAt, now)
    }

    /// A manual start is an exact time the athlete chose; the warm-up lead is not applied
    /// again on top of it.
    func testManualStartIsNotBackdatedByALaterSet() {
        let day = makeDay()
        let start = Date().addingTimeInterval(-1_800)
        day.sessionStartedAt = start

        SessionLifecycle.noteSetLogged(for: day.exercises[0], at: .now)

        XCTAssertEqual(day.sessionStartedAt, start)
    }

    /// Correcting yesterday's session today must not drag its clock into the present.
    func testSetLoggedOnAnotherDayIsIgnored() {
        let day = makeDay()
        let yesterday = Date().addingTimeInterval(-86_400)

        SessionLifecycle.noteSetLogged(for: day.exercises[0], at: yesterday)

        XCTAssertNil(day.sessionStartedAt)
        XCTAssertNil(day.sessionEndedAt)
    }

    // MARK: - Derived state

    func testReviewableSessionCoversFinishedAndCutShortSessions() {
        let finished = makeDay()
        finished.isCompleted = true
        XCTAssertTrue(finished.hasReviewableSession)

        let cutShort = makeDay()
        cutShort.sessionStartedAt = at(6, 43)
        SessionLifecycle.markSessionEnded(for: cutShort, now: at(7, 16))
        XCTAssertTrue(cutShort.hasReviewableSession, "a session finished early must stay reachable")
        XCTAssertFalse(cutShort.isSessionInProgress)

        let running = makeDay()
        running.sessionStartedAt = at(6, 43)
        XCTAssertFalse(running.hasReviewableSession)
        XCTAssertTrue(running.isSessionInProgress)
    }

    /// 22:50 displayed as "22 min" reads as an off-by-one against the clock times shown
    /// beside it.
    func testDurationRoundsRatherThanTruncates() {
        let day = makeDay()
        day.sessionStartedAt = at(6, 43)
        day.sessionEndedAt = day.sessionStartedAt!.addingTimeInterval(22 * 60 + 50)

        XCTAssertEqual(day.sessionDurationMinutes, 23)
    }
}
