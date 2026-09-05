import Foundation
import XCTest
@testable import Transform

/// The app decides three things from what happened in past sessions: which movements to avoid
/// outright, which to push down the list, and — since the session-clock trim landed — how long
/// next week's sessions should be.
///
/// It used to decide all three from EVERY session ever recorded, with no sense of when anything
/// happened. Two movements abandoned for time in January still shortened the week in December,
/// and there was no way to earn that back: the evidence only grew. This pins the window that
/// releases it, and pins that pain is deliberately exempt.
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

    /// Appends one trained day carrying `skips`, stamped `daysAgo` unless `stamped` is false.
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

    private func context(_ programs: [WorkoutProgram]) -> ClaudeService.ExerciseHistoryContext {
        ExerciseHistoryAggregator.context(from: programs, now: now)
    }

    // MARK: - The ratchet

    /// Two recent abandonments are exactly what the trim is meant to react to.
    func testRecentlyAbandonedMovementsStillCount() {
        let program = makeProgram()
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 3)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 10)

        XCTAssertEqual(context([program]).timeSkipExercises.count, 1)
    }

    /// The whole point of the fix: a lifter who fixed his schedule gets his session length back.
    func testAbandonmentsOlderThanTheWindowStopCounting() {
        let program = makeProgram()
        let stale = ExerciseHistoryAggregator.circumstantialSkipWindowDays + 1
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: stale)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: stale + 7)

        XCTAssertTrue(
            context([program]).timeSkipExercises.isEmpty,
            "Evidence older than the window must release, or the session trim can never be earned back"
        )
    }

    /// The bar is two WITHIN the window, not two ever. One recent skip plus one ancient one is
    /// not a live pattern.
    func testOneRecentSkipPlusOneAncientOneIsNotAPattern() {
        let program = makeProgram()
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 5)
        addDay(
            to: program,
            dayNumber: 2,
            skips: [("Cable Crunch", .skippedTime)],
            daysAgo: ExerciseHistoryAggregator.circumstantialSkipWindowDays + 30
        )

        XCTAssertTrue(context([program]).timeSkipExercises.isEmpty)
    }

    /// A skip exactly on the window edge is still inside it — the boundary is inclusive, so a
    /// pattern does not blink out a day early.
    func testTheWindowBoundaryIsInclusive() {
        let program = makeProgram()
        let edge = ExerciseHistoryAggregator.circumstantialSkipWindowDays
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: edge)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: edge - 1)

        XCTAssertEqual(context([program]).timeSkipExercises.count, 1)
    }

    // MARK: - Equipment ages the same way; pain does not

    func testEquipmentSkipsAlsoRelease() {
        let program = makeProgram()
        let stale = ExerciseHistoryAggregator.circumstantialSkipWindowDays + 5
        addDay(to: program, dayNumber: 1, skips: [("Pec Deck", .skippedEquipment)], daysAgo: stale)
        addDay(to: program, dayNumber: 2, skips: [("Pec Deck", .skippedEquipment)], daysAgo: stale)

        XCTAssertTrue(context([program]).equipmentSkipExercises.isEmpty)
    }

    /// Pain is about his body, not his schedule. A movement that hurt him is not reintroduced
    /// because a timer expired — and one report is enough, where the others need two.
    func testPainIsNeverAgedOutAndNeedsOnlyOneReport() {
        let program = makeProgram()
        addDay(
            to: program,
            dayNumber: 1,
            skips: [("Upright Row", .skippedPain)],
            daysAgo: ExerciseHistoryAggregator.circumstantialSkipWindowDays * 10
        )

        XCTAssertEqual(
            context([program]).painExercises.count,
            1,
            "A painful movement must stay avoided no matter how long ago it hurt"
        )
    }

    // MARK: - Days with no session stamps

    /// Days trained before the session clock existed carry no stamps. They inherit their
    /// program's creation date so an old block ages out as a unit rather than counting forever.
    func testUnstampedDaysInAnOldProgramAgeOutWithThatProgram() {
        let program = makeProgram(
            archived: true,
            createdDaysAgo: ExerciseHistoryAggregator.circumstantialSkipWindowDays + 20
        )
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 0, stamped: false)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 0, stamped: false)

        XCTAssertTrue(context([program]).timeSkipExercises.isEmpty)
    }

    /// The same unstamped days in a CURRENT program still count — the fallback ages history, it
    /// does not discard undated evidence outright.
    func testUnstampedDaysInACurrentProgramStillCount() {
        let program = makeProgram(createdDaysAgo: 5)
        addDay(to: program, dayNumber: 1, skips: [("Cable Crunch", .skippedTime)], daysAgo: 0, stamped: false)
        addDay(to: program, dayNumber: 2, skips: [("Cable Crunch", .skippedTime)], daysAgo: 0, stamped: false)

        XCTAssertEqual(context([program]).timeSkipExercises.count, 1)
    }

    // MARK: - Ageing must not disturb what it was not meant to touch

    /// `priorMesocycleExercises` drives variation between training blocks, so it is supposed to
    /// be historical. Ageing the skip counters must not have quietly narrowed it.
    func testPriorMesocycleMemoryIsNotAged() {
        let old = makeProgram(
            archived: true,
            createdDaysAgo: ExerciseHistoryAggregator.circumstantialSkipWindowDays * 4
        )
        addDay(to: old, dayNumber: 1, skips: [("Incline Press", .skippedTime)], daysAgo: 0, stamped: false)

        let result = context([old])
        XCTAssertTrue(
            result.priorMesocycleExercises.contains(ExerciseWeightEntry.canonicalLookupKey("Incline Press")),
            "Movements from previous blocks must stay known even when their skips have aged out"
        )
        XCTAssertTrue(result.timeSkipExercises.isEmpty)
    }

    /// Mesocycle counting is independent of the window.
    func testMesocycleIndexIsUnaffectedByTheWindow() {
        let archivedOne = makeProgram(archived: true, createdDaysAgo: 400)
        let archivedTwo = makeProgram(archived: true, createdDaysAgo: 200)
        let active = makeProgram(createdDaysAgo: 3)

        XCTAssertEqual(context([archivedOne, archivedTwo, active]).mesocycleIndex, 2)
        XCTAssertEqual(context([archivedOne, archivedTwo]).mesocycleIndex, 1)
    }

    // MARK: - Shape

    /// Rest days and completed exercises are not skips, and an unnamed exercise cannot be keyed.
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
}
