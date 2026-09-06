import Foundation
import XCTest
@testable import Transform

/// The app decides three things from what happened in past sessions: which movements to avoid
/// outright, which to push down the list, and — since the session-clock trim landed — how long
/// next week's sessions should be.
///
/// It first decided all three from EVERY session ever recorded, so evidence only grew and the
/// session trim could never be earned back. The fix for that expired circumstantial skips after
/// 84 CALENDAR days, which released the ratchet and introduced a quieter defect: the bar is two
/// skips inside one window, so anyone training less often than that could never reach it. Each
/// skip aged out before the next landed and a real recurring problem stayed invisible.
///
/// The window now counts SESSIONS. These pin that it behaves the same for a frequent lifter,
/// works for an infrequent one, and still lets go.
@MainActor
final class ExerciseHistoryRecencyTests: XCTestCase {

    private let now = Date()

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now)!
    }

    /// Labels copied from the real initialisers in `WorkoutModels.swift`, not typed from memory.
    private func makeProgram(archived: Bool = false, createdDaysAgo: Int = 0) -> WorkoutProgram {
        let program = WorkoutProgram(
            programName: "Test Block",
            programSummary: "",
            splitType: "Push/Pull/Legs",
            daysPerWeek: 5,
            focusAreas: "Chest"
        )
        program.isArchived = archived
        program.createdDate = daysAgo(createdDaysAgo)
        return program
    }

    /// Appends one TRAINED day. A day only occupies a window slot if it shows evidence of having
    /// been trained, which a session stamp or any completion status provides.
    @discardableResult
    private func addDay(
        to program: WorkoutProgram,
        dayNumber: Int,
        skips: [(name: String, status: ExerciseCompletionStatus)],
        daysAgo ageInDays: Int,
        stamped: Bool = true
    ) -> WorkoutDay {
        let day = WorkoutDay(dayNumber: dayNumber, dayName: "Push", muscleGroups: "Chest")
        if stamped {
            day.sessionStartedAt = daysAgo(ageInDays)
            day.sessionEndedAt = daysAgo(ageInDays)
        }
        for (index, skip) in skips.enumerated() {
            let exercise = WorkoutExercise(
                order: index,
                exerciseName: skip.name,
                sets: 3,
                reps: "8-12"
            )
            exercise.completionStatus = skip.status
            exercise.day = day
            day.exercises.append(exercise)
        }
        day.program = program
        program.days.append(day)
        return day
    }

    /// `count` ordinary completed sessions, newest at `startingDaysAgo`, one per day going back.
    private func addCompletedSessions(
        to program: WorkoutProgram,
        count: Int,
        startingDaysAgo: Int,
        firstDayNumber: Int = 1000
    ) {
        for offset in 0..<count {
            addDay(
                to: program,
                dayNumber: firstDayNumber + offset,
                skips: [("Barbell Bench Press", .completed)],
                daysAgo: startingDaysAgo + offset
            )
        }
    }

    private func context(_ programs: [WorkoutProgram]) -> ClaudeService.ExerciseHistoryContext {
        ExerciseHistoryAggregator.context(from: programs, now: now)
    }

    // MARK: - The defect this rewrite exists to fix

    /// THE POINT. Someone training twice a month abandons the same movement twice, four months
    /// apart. Under the old 84-day calendar window the first skip expired before the second
    /// landed, so a real pattern was invisible to a lifter purely because of how often he trains.
    /// Two sessions is two sessions.
    func testAnInfrequentLifterStillReachesTheRecurrenceBar() {
        let program = makeProgram(createdDaysAgo: 200)
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 130)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 15)

        XCTAssertEqual(
            context([program]).timeSkipExercises.count, 1,
            "Four months apart is still the last two sessions for someone who trains twice a month"
        )
    }

    /// The frequent case must be unchanged: two recent skips are exactly what the trim reacts to.
    func testRecentlyAbandonedMovementsStillCount() {
        let program = makeProgram()
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 3)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 10)

        XCTAssertEqual(context([program]).timeSkipExercises.count, 1)
    }

    // MARK: - It still lets go

    /// The original defect must stay fixed: a lifter who sorted his schedule out gets his session
    /// length back once enough training has happened since.
    func testSkipsPushedOutByLaterSessionsStopCounting() {
        let program = makeProgram(createdDaysAgo: 400)
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 300)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 299)
        addCompletedSessions(
            to: program,
            count: ExerciseHistoryAggregator.recentSessionWindow,
            startingDaysAgo: 1
        )

        XCTAssertTrue(
            context([program]).timeSkipExercises.isEmpty,
            "A full window of clean sessions since must clear the evidence"
        )
    }

    /// One short of a full window, the evidence is still in view — this is the half that fails if
    /// the window is removed or mis-sized, so the test above cannot pass vacuously.
    func testOneSessionShortOfAFullWindowTheEvidenceSurvives() {
        let program = makeProgram(createdDaysAgo: 400)
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 300)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 299)
        addCompletedSessions(
            to: program,
            count: ExerciseHistoryAggregator.recentSessionWindow - 2,
            startingDaysAgo: 1
        )

        XCTAssertEqual(context([program]).timeSkipExercises.count, 1)
    }

    /// The bar is two skips INSIDE the window, not two ever.
    func testOneRecentSkipPlusOnePushedOutIsNotAPattern() {
        let program = makeProgram(createdDaysAgo: 400)
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 350)
        addCompletedSessions(
            to: program,
            count: ExerciseHistoryAggregator.recentSessionWindow,
            startingDaysAgo: 2
        )
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 1)

        XCTAssertTrue(context([program]).timeSkipExercises.isEmpty)
    }

    // MARK: - The calendar backstop

    /// Counting sessions alone would keep evidence from before a multi-year layoff alive forever.
    /// A movement abandoned for time before a two-year gap says nothing about the gym, the
    /// schedule, or the body the lifter has now.
    func testEvidenceFromBeforeALongLayoffIsDroppedEvenWithinTheSessionWindow() {
        let ancient = ExerciseHistoryAggregator.staleSessionCutoffDays + 30
        let program = makeProgram(createdDaysAgo: ancient + 10)
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: ancient)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: ancient)

        XCTAssertTrue(
            context([program]).timeSkipExercises.isEmpty,
            "Only two sessions on record, so the session window holds them — the backstop must not"
        )
    }

    /// Just inside the backstop, the same two sessions still count, so the test above is measuring
    /// the cutoff rather than something incidental.
    func testEvidenceJustInsideTheBackstopStillCounts() {
        let recent = ExerciseHistoryAggregator.staleSessionCutoffDays - 30
        let program = makeProgram(createdDaysAgo: recent + 10)
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: recent)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: recent)

        XCTAssertEqual(context([program]).timeSkipExercises.count, 1)
    }

    // MARK: - Untrained days must not consume the window

    /// Days scheduled but not yet trained carry no stamps and no dispositions. If they took window
    /// slots, a program generated for the weeks ahead would push real history out of view the
    /// moment it was created.
    func testUnTrainedFutureDaysDoNotPushOutRealHistory() {
        let program = makeProgram(createdDaysAgo: 30)
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 20)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 19)
        for dayNumber in 100..<(100 + ExerciseHistoryAggregator.recentSessionWindow * 2) {
            let scheduled = WorkoutDay(dayNumber: dayNumber, dayName: "Push", muscleGroups: "Chest")
            let exercise = WorkoutExercise(order: 0, exerciseName: "Barbell Bench Press", sets: 3, reps: "8-12")
            exercise.day = scheduled
            scheduled.exercises.append(exercise)
            scheduled.program = program
            program.days.append(scheduled)
        }

        XCTAssertEqual(
            context([program]).timeSkipExercises.count, 1,
            "Days never trained must not occupy window slots"
        )
    }

    // MARK: - Equipment ages the same way; pain does not

    func testEquipmentSkipsAlsoRelease() {
        let program = makeProgram(createdDaysAgo: 400)
        addDay(to: program, dayNumber: 1, skips: [("Pec Deck", .skippedEquipment)], daysAgo: 300)
        addDay(to: program, dayNumber: 2, skips: [("Pec Deck", .skippedEquipment)], daysAgo: 299)
        addCompletedSessions(
            to: program,
            count: ExerciseHistoryAggregator.recentSessionWindow,
            startingDaysAgo: 1
        )

        XCTAssertTrue(context([program]).equipmentSkipExercises.isEmpty)
    }

    /// Pain is about his body, not his schedule. A movement that hurt him is not reintroduced
    /// because enough sessions have gone by — and one report is enough, where the others need two.
    func testPainIsNeverWindowedAndNeedsOnlyOneReport() {
        let program = makeProgram(createdDaysAgo: 3000)
        addDay(to: program, dayNumber: 1, skips: [("Upright Row", .skippedPain)], daysAgo: 2500)
        addCompletedSessions(
            to: program,
            count: ExerciseHistoryAggregator.recentSessionWindow * 2,
            startingDaysAgo: 1
        )

        XCTAssertEqual(
            context([program]).painExercises.count, 1,
            "A painful movement stays avoided however long ago it hurt and however much training since"
        )
    }

    // MARK: - Ageing must not disturb what it was not meant to touch

    /// `priorMesocycleExercises` drives variation between training blocks, so it is supposed to be
    /// historical. Windowing the skip counters must not have quietly narrowed it.
    func testPriorMesocycleMemoryIsNotWindowed() {
        let old = makeProgram(archived: true, createdDaysAgo: 3000)
        addDay(to: old, dayNumber: 1, skips: [("Incline Press", .skippedTime)], daysAgo: 2900)

        let result = context([old])
        XCTAssertTrue(
            result.priorMesocycleExercises.contains(ExerciseWeightEntry.canonicalLookupKey("Incline Press")),
            "Movements from previous blocks must stay known even when their skips have dropped out"
        )
        XCTAssertTrue(result.timeSkipExercises.isEmpty, "That skip is past the backstop")
    }

    func testMesocycleIndexIsUnaffectedByTheWindow() {
        let archivedOne = makeProgram(archived: true, createdDaysAgo: 400)
        let archivedTwo = makeProgram(archived: true, createdDaysAgo: 200)
        let active = makeProgram(createdDaysAgo: 3)

        XCTAssertEqual(context([archivedOne, archivedTwo, active]).mesocycleIndex, 2)
        XCTAssertEqual(context([archivedOne, archivedTwo]).mesocycleIndex, 1)
    }

    // MARK: - Shape

    func testCompletedWorkAndRestDaysContributeNothing() {
        let program = makeProgram()
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .completed)], daysAgo: 2)
        let rest = WorkoutDay(dayNumber: 2, dayName: "Rest", muscleGroups: "", isRestDay: true)
        rest.program = program
        program.days.append(rest)

        let result = context([program])
        XCTAssertTrue(result.timeSkipExercises.isEmpty)
        XCTAssertTrue(result.painExercises.isEmpty)
        XCTAssertTrue(result.equipmentSkipExercises.isEmpty)
    }

    func testNoProgramsProducesAnEmptyContext() {
        let result = context([])
        XCTAssertTrue(result.timeSkipExercises.isEmpty)
        XCTAssertTrue(result.painExercises.isEmpty)
        XCTAssertTrue(result.equipmentSkipExercises.isEmpty)
        XCTAssertTrue(result.priorMesocycleExercises.isEmpty)
        XCTAssertEqual(result.mesocycleIndex, 0)
    }

    /// The same data must produce the same answer. Many days legitimately share a date, and
    /// `sorted` is not guaranteed stable, so the ordering carries explicit tiebreakers.
    func testTheWindowIsDeterministicWhenSessionsShareADate() {
        func build() -> ClaudeService.ExerciseHistoryContext {
            let program = makeProgram(createdDaysAgo: 50)
            for dayNumber in 1...(ExerciseHistoryAggregator.recentSessionWindow + 10) {
                addDay(
                    to: program,
                    dayNumber: dayNumber,
                    skips: [("Cable Crunch", .skippedTime)],
                    daysAgo: 0,
                    stamped: false
                )
            }
            return context([program])
        }

        let first = build()
        for _ in 0..<5 {
            XCTAssertEqual(build().timeSkipExercises, first.timeSkipExercises)
        }
    }
}
