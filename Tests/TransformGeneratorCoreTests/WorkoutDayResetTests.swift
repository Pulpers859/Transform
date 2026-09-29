import XCTest
import SwiftData
@testable import Transform

@MainActor
final class WorkoutDayResetTests: XCTestCase {
    private func fixture() throws -> (ModelContainer, ModelContext, WorkoutDay, WorkoutExercise) {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                          ExerciseWeightEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let program = WorkoutProgram(programName: "Test", programSummary: "", splitType: "Upper", daysPerWeek: 3, focusAreas: "Shoulders")
        program.createdDate = Date().addingTimeInterval(-86400 * 7)
        let day = WorkoutDay(dayNumber: 1, dayName: "Upper", muscleGroups: "Shoulders")
        let exercise = WorkoutExercise(order: 0, exerciseName: "Dumbbell Lateral Raise", sets: 3, reps: "10-15")
        context.insert(program)
        program.days = [day]
        day.program = program
        day.exercises = [exercise]
        exercise.day = day
        try context.save()
        return (container, context, day, exercise)
    }

    func testCancelOldEmptySessionClearsReplacementGateWithoutFeedback() throws {
        let (container, context, day, exercise) = try fixture()
        day.sessionStartedAt = Date().addingTimeInterval(-86400 * 2)
        day.sessionEndedAt = day.sessionStartedAt
        day.isSessionClosed = true
        try context.save()
        XCTAssertTrue(SessionLifecycle.canCancelAccidentalStart(day, logs: []))
        XCTAssertTrue(ExerciseReplacement.candidates(for: exercise, avoidedKeys: []).isEmpty)
        try SessionLifecycle.reset(day, in: context)
        XCTAssertNil(day.sessionStartedAt)
        XCTAssertNil(day.sessionEndedAt)
        XCTAssertFalse(day.hasReviewableSession)
        XCTAssertFalse(ExerciseReplacement.candidates(for: exercise, avoidedKeys: []).isEmpty)
        let reloaded = try ModelContext(container).fetch(FetchDescriptor<WorkoutDay>()).first!
        XCTAssertNil(reloaded.sessionStartedAt)
        XCTAssertFalse(reloaded.isSessionClosed)
    }

    func testResetDeletesOnlyDayLogsAndRepairsLatestAndBest() throws {
        let (_, context, day, exercise) = try fixture()
        let now = Date()
        let old = ExercisePerformanceLog(loggedAt: now.addingTimeInterval(-86400 * 10), exerciseName: exercise.exerciseName, weightLbs: 15, repsCompleted: 12, workoutDayNumber: 1)
        let otherDay = ExercisePerformanceLog(loggedAt: now.addingTimeInterval(-3600), exerciseName: exercise.exerciseName, weightLbs: 20, repsCompleted: 12, workoutDayNumber: 2)
        let bad = ExercisePerformanceLog(loggedAt: now, exerciseName: exercise.exerciseName, weightLbs: 100, repsCompleted: 12, workoutDayNumber: 1)
        for log in [old, otherDay, bad] { context.insert(log) }
        let summary = ExerciseWeightEntry(loggedAt: now, exerciseName: exercise.exerciseName, weightLbs: 100, repsCompleted: 12)
        context.insert(summary)
        exercise.isCompleted = true
        exercise.completionStatus = .skippedPain
        exercise.painReviewRaw = "avoid"
        exercise.preferredReplacementName = "Machine Lateral Raise"
        day.feedbackSubmittedAt = now
        day.sessionEffort = 3
        day.stimulusQuality = 4
        day.jointPain = 2
        day.performanceRatingRaw = "anything"
        day.sessionFeedbackNotes = "mistake"
        day.isCompleted = true
        try context.save()
        XCTAssertFalse(SessionLifecycle.canCancelAccidentalStart(day, logs: [bad]))
        try SessionLifecycle.reset(day, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 2)
        XCTAssertEqual(summary.weightLbs, 20)
        XCTAssertEqual(summary.bestWeightLbs, 20)
        XCTAssertEqual(exercise.preferredReplacementName, "Machine Lateral Raise")
        XCTAssertFalse(exercise.isCompleted)
        XCTAssertEqual(exercise.completionStatusRaw, "")
        XCTAssertEqual(exercise.painReviewRaw, "")
        XCTAssertNil(day.feedbackSubmittedAt)
        XCTAssertEqual([day.sessionEffort, day.stimulusQuality, day.jointPain], [0, 0, 0])
        XCTAssertEqual(day.performanceRatingRaw, "")
        XCTAssertEqual(day.sessionFeedbackNotes, "")
    }

    func testPartialReplacementRestartsFullBudgetAndRetainsAlternative() throws {
        let (_, context, day, original) = try fixture()
        let log = ExercisePerformanceLog(exerciseName: original.exerciseName, weightLbs: 20, repsCompleted: 12,
            workoutDayNumber: 1, setLogs: [SetLogEntry(setNumber: 1, weightLbs: 20, repsCompleted: 12)])
        context.insert(log)
        try context.save()
        let replacement = try ExerciseReplacement.replace(original, with: "Machine Lateral Raise", loggedSetNumbers: [1], preferFuture: false, modelContext: context)
        XCTAssertEqual(replacement.sets, 2)
        try SessionLifecycle.reset(day, in: context)
        XCTAssertEqual(day.activeExercises.map(\.exerciseName), ["Machine Lateral Raise"])
        XCTAssertEqual(replacement.sets, 3)
        XCTAssertTrue(ExerciseReplacement.candidates(for: replacement, avoidedKeys: []).contains(original.exerciseName))
        try SessionLifecycle.reset(day, in: context)
        XCTAssertEqual(replacement.sets, 3)
    }

    func testSaveFailureRestoresLogsClockAndStatus() throws {
        let (container, context, day, exercise) = try fixture()
        let stamp = Date()
        day.sessionStartedAt = stamp
        exercise.completionStatus = .skippedTime
        let log = ExercisePerformanceLog(exerciseName: exercise.exerciseName, weightLbs: 20, repsCompleted: 10, workoutDayNumber: 1)
        context.insert(log)
        let summary = ExerciseWeightEntry(loggedAt: log.loggedAt, exerciseName: exercise.exerciseName, weightLbs: 20, repsCompleted: 10)
        context.insert(summary)
        try context.save()
        enum Failure: Error { case expected }
        XCTAssertThrowsError(try SessionLifecycle.reset(day, in: context, save: { _ in throw Failure.expected }))
        XCTAssertEqual(day.sessionStartedAt, stamp)
        XCTAssertEqual(exercise.completionStatus, .skippedTime)
        XCTAssertEqual(summary.weightLbs, 20)
        XCTAssertEqual(summary.bestWeightLbs, 20)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseWeightEntry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WorkoutDay>()).first?.sessionStartedAt, stamp)
    }

    func testUntraceablePersonalBestRefusesWithoutDeleting() throws {
        let (_, context, day, exercise) = try fixture()
        let log = ExercisePerformanceLog(exerciseName: exercise.exerciseName, weightLbs: 80, repsCompleted: 10, workoutDayNumber: 1)
        let summary = ExerciseWeightEntry(loggedAt: log.loggedAt, exerciseName: exercise.exerciseName, weightLbs: 80)
        summary.bestWeightLbs = 100
        summary.bestLoggedAt = log.loggedAt.addingTimeInterval(-60)
        context.insert(log)
        context.insert(summary)
        try context.save()
        XCTAssertThrowsError(try SessionLifecycle.reset(day, in: context))
        XCTAssertEqual(summary.bestWeightLbs, 100)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 1)
    }

    func testArchivedAndUnsavedDaysCannotReset() throws {
        let (_, context, day, _) = try fixture()
        day.sessionStartedAt = .now
        XCTAssertThrowsError(try SessionLifecycle.reset(day, in: context))
        day.program?.isArchived = true
        try context.save()
        XCTAssertThrowsError(try SessionLifecycle.reset(day, in: context))
        XCTAssertNotNil(day.sessionStartedAt)
    }

    func testSameTimestampOtherDayAndLegacyBestSurvive() throws {
        let (_, context, day, exercise) = try fixture()
        let now = Date()
        for number in [1, 2] {
            context.insert(ExercisePerformanceLog(loggedAt: now, exerciseName: exercise.exerciseName,
                weightLbs: Double(number * 10), repsCompleted: 12, workoutDayNumber: number))
        }
        let summary = ExerciseWeightEntry(loggedAt: now, exerciseName: exercise.exerciseName, weightLbs: 10)
        summary.bestLoggedAt = day.program!.createdDate.addingTimeInterval(-86400)
        summary.bestWeightLbs = 50
        context.insert(summary)
        try context.save()
        try SessionLifecycle.reset(day, in: context)
        XCTAssertEqual(summary.weightLbs, 20)
        XCTAssertEqual(summary.bestWeightLbs, 50)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 1)
    }

    func testBodyweightHistoryIsRetained() throws {
        let (_, context, day, exercise) = try fixture()
        let now = Date()
        context.insert(ExercisePerformanceLog(loggedAt: now.addingTimeInterval(-86400 * 10), exerciseName: exercise.exerciseName,
            weightLbs: 0, repsCompleted: 8, workoutDayNumber: 1))
        context.insert(ExercisePerformanceLog(loggedAt: now, exerciseName: exercise.exerciseName,
            weightLbs: 0, repsCompleted: 15, workoutDayNumber: 1))
        let summary = ExerciseWeightEntry(loggedAt: now, exerciseName: exercise.exerciseName, weightLbs: 0, repsCompleted: 15)
        context.insert(summary)
        try context.save()
        try SessionLifecycle.reset(day, in: context)
        XCTAssertEqual(summary.repsCompleted, 8)
        XCTAssertEqual(summary.bestRepsCompleted, 8)
    }

    func testResetOnlyRecordRemovesItsWeightSummary() throws {
        let (_, context, day, exercise) = try fixture()
        let log = ExercisePerformanceLog(exerciseName: exercise.exerciseName, weightLbs: 99, workoutDayNumber: 1)
        context.insert(log)
        context.insert(ExerciseWeightEntry(loggedAt: log.loggedAt, exerciseName: exercise.exerciseName, weightLbs: 99))
        try context.save()
        try SessionLifecycle.reset(day, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseWeightEntry>()), 0)
    }

    func testOverlappingOlderProgramRefusesReset() throws {
        let (_, context, day, exercise) = try fixture()
        let older = WorkoutProgram(programName: "Older", programSummary: "", splitType: "Upper", daysPerWeek: 3, focusAreas: "")
        older.createdDate = day.program!.createdDate.addingTimeInterval(-86400)
        older.isArchived = true
        let oldDay = WorkoutDay(dayNumber: 1, dayName: "Old", muscleGroups: "Shoulders")
        let oldExercise = WorkoutExercise(order: 0, exerciseName: exercise.exerciseName, sets: 3, reps: "10-15")
        context.insert(older)
        older.days = [oldDay]
        oldDay.program = older
        oldDay.exercises = [oldExercise]
        oldExercise.day = oldDay
        // A bulk edit can move the log into the current program's dates without moving
        // its original day's clock. Clock-date mismatch must not authorize deletion.
        oldDay.sessionEndedAt = older.createdDate
        context.insert(ExercisePerformanceLog(exerciseName: exercise.exerciseName, weightLbs: 20, workoutDayNumber: 1))
        try context.save()
        XCTAssertThrowsError(try SessionLifecycle.reset(day, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 1)
    }

    func testUnscopedLegacyRecordRefusesReset() throws {
        let (_, context, day, exercise) = try fixture()
        context.insert(ExercisePerformanceLog(exerciseName: exercise.exerciseName, weightLbs: 20))
        try context.save()
        XCTAssertThrowsError(try SessionLifecycle.reset(day, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 1)
    }

    func testEqualLoadBestKeepsHigherRepsNotNewestSession() throws {
        let (_, context, day, exercise) = try fixture()
        let now = Date()
        for (offset, weight, reps, number) in [(-200.0, 20.0, 15, 2), (-100.0, 20.0, 10, 3), (0.0, 30.0, 10, 1)] {
            context.insert(ExercisePerformanceLog(loggedAt: now.addingTimeInterval(offset), exerciseName: exercise.exerciseName,
                weightLbs: weight, repsCompleted: reps, workoutDayNumber: number))
        }
        let summary = ExerciseWeightEntry(loggedAt: now, exerciseName: exercise.exerciseName, weightLbs: 30, repsCompleted: 10)
        context.insert(summary)
        try context.save()
        try SessionLifecycle.reset(day, in: context)
        XCTAssertEqual(summary.repsCompleted, 10)
        XCTAssertEqual(summary.bestRepsCompleted, 15)
    }

    func testAliasReturnChainRestoresFullSetBudget() throws {
        let (_, context, day, original) = try fixture()
        original.exerciseName = "Leaning Lateral Raise"
        try context.save()
        let machine = try ExerciseReplacement.replace(original, with: "Machine Lateral Raise", loggedSetNumbers: [], preferFuture: false, modelContext: context)
        context.insert(ExercisePerformanceLog(exerciseName: machine.exerciseName, weightLbs: 20, workoutDayNumber: 1,
            setLogs: [SetLogEntry(setNumber: 1, weightLbs: 20, repsCompleted: 12)]))
        try context.save()
        let returned = try ExerciseReplacement.replace(machine, with: "Leaning Dumbbell Lateral Raise", loggedSetNumbers: [1], preferFuture: false, modelContext: context)
        XCTAssertTrue(returned === original)
        XCTAssertEqual(returned.sets, 2)
        try SessionLifecycle.reset(day, in: context)
        XCTAssertEqual(returned.sets, 3)
    }
}
