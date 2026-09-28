import XCTest
import SwiftData
@testable import Transform

@MainActor
final class ExerciseReplacementTests: XCTestCase {
    private let dumbbell = "Dumbbell Lateral Raise"
    private let machine = "Machine Lateral Raise"
    private let cable = "Cable Lateral Raise"

    private func fixture() throws -> (ModelContainer, ModelContext, WorkoutDay, WorkoutExercise) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self, configurations: configuration)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let program = WorkoutProgram(programName: "Test", programSummary: "", splitType: "Push",
                                     daysPerWeek: 3, focusAreas: "Shoulders")
        let day = WorkoutDay(dayNumber: 1, dayName: "Push", muscleGroups: "Shoulders")
        let original = WorkoutExercise(order: 4, exerciseName: dumbbell, sets: 3, reps: "10-15",
                                       muscleTarget: "Lateral Deltoids", targetRIR: 2)
        context.insert(program)
        program.days = [day]
        day.program = program
        day.exercises = [original]
        original.day = day
        try context.save()
        return (container, context, day, original)
    }

    func testExactLateralSlotDoesNotOfferPressesOrRearDelts() throws {
        let (_, _, _, original) = try fixture()
        let names = ExerciseReplacement.candidates(for: original, avoidedKeys: [])
        XCTAssertTrue(names.contains(cable))
        XCTAssertTrue(names.contains(machine))
        XCTAssertFalse(names.contains(dumbbell))
        XCTAssertTrue(names.allSatisfy { ExerciseReplacement.compatible(originalName: dumbbell, candidateName: $0) })
        XCTAssertFalse(ExerciseReplacement.compatible(originalName: dumbbell, candidateName: "Machine Shoulder Press"))
        XCTAssertFalse(ExerciseReplacement.compatible(originalName: dumbbell, candidateName: "Reverse Pec Deck"))
        XCTAssertFalse(ExerciseReplacement.compatible(originalName: "Unknown lateral exercise", candidateName: machine))
    }

    func testPartialReplacementKeepsPrescriptionAndLogsAndIndependentLoads() throws {
        let (_, context, day, original) = try fixture()
        let weight = ExerciseWeightEntry(exerciseName: dumbbell, weightLbs: 20, repsCompleted: 12)
        let machineWeight = ExerciseWeightEntry(exerciseName: machine, weightLbs: 45, repsCompleted: 10)
        let log = ExercisePerformanceLog(exerciseName: dumbbell, weightLbs: 20, repsCompleted: 12,
                                         workoutDayNumber: 1, prescribedSets: 3, prescribedReps: "10-15",
                                         setLogs: [SetLogEntry(setNumber: 1, weightLbs: 20, repsCompleted: 12)])
        context.insert(weight)
        context.insert(machineWeight)
        context.insert(log)
        try context.save()
        let originalJSON = log.setLogsJSON
        let inserted = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [1],
                                                       preferFuture: false, modelContext: context)
        XCTAssertEqual(original.exerciseName, dumbbell)
        XCTAssertEqual(original.sets, 3)
        XCTAssertEqual(log.setLogsJSON, originalJSON)
        XCTAssertEqual(log.prescribedSets, 3)
        XCTAssertEqual(log.canonicalExerciseKey, ExerciseWeightEntry.canonicalLookupKey(dumbbell))
        XCTAssertEqual(inserted.sets, 2)
        XCTAssertEqual(inserted.reps, "10-15")
        XCTAssertEqual(inserted.targetRIR, 2)
        XCTAssertEqual(original.completionStatus, .substituted)
        XCTAssertTrue(original.isCompleted)
        XCTAssertFalse(inserted.isCompleted)
        XCTAssertEqual(day.sortedExercises.map(\.exerciseName), [dumbbell, machine])
        XCTAssertEqual(weight.weightLbs, 20)
        XCTAssertEqual(machineWeight.weightLbs, 45)
        XCTAssertTrue(inserted.weightLogs.isEmpty)
        XCTAssertEqual(original.preferredReplacementName, "")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 1)
    }

    func testZeroLogsTransfersEntireRemainingBudgetAndPersistsPreference() throws {
        let (container, context, _, original) = try fixture()
        let inserted = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
                                                       preferFuture: true, modelContext: context)
        XCTAssertEqual(inserted.sets, 3)
        XCTAssertEqual(original.preferredReplacementName, machine)
        let reopened = ModelContext(container)
        let day = try XCTUnwrap(reopened.fetch(FetchDescriptor<WorkoutDay>()).first)
        XCTAssertEqual(day.sortedExercises.map(\.exerciseName), [dumbbell, machine])
        XCTAssertEqual(day.sortedExercises.first?.replacementName, machine)
        XCTAssertEqual(day.sortedExercises.last?.sets, 3)
        XCTAssertFalse(day.allExercisesResolved)
        let history = ExerciseHistoryAggregator.context(from: [try XCTUnwrap(day.program)])
        XCTAssertEqual(history.preferredReplacements[ExerciseWeightEntry.canonicalLookupKey(dumbbell)], machine)
    }

    func testAllSetsDoneRefusesAndPositiveDistinctNumbersAreCounted() throws {
        let (_, context, _, original) = try fixture()
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [1, 2, 3], preferFuture: false, modelContext: context))
        let inserted = try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [-1, 0, 1], preferFuture: false, modelContext: context)
        XCTAssertEqual(inserted.sets, 2)
    }

    func testUnrelatedDuplicatesAndSecondSwapOfHistoricalOriginalRefuse() throws {
        let (_, context, day, original) = try fixture()
        let duplicate = WorkoutExercise(order: 6, exerciseName: machine, sets: 3, reps: "10-15")
        context.insert(duplicate)
        duplicate.day = day
        day.exercises.append(duplicate)
        try context.save()
        XCTAssertFalse(ExerciseReplacement.candidates(for: original, avoidedKeys: []).contains(machine))
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: false, modelContext: context))
        let inserted = try ExerciseReplacement.replace(original, with: cable,
            loggedSetNumbers: [], preferFuture: false, modelContext: context)
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: false, modelContext: context))
        let returned = try ExerciseReplacement.replace(inserted, with: dumbbell,
            loggedSetNumbers: [], preferFuture: false, modelContext: context)
        XCTAssertTrue(returned === original)
        XCTAssertEqual(day.activeExercises.count, 2) // Original slot + unrelated machine slot.
    }

    func testInclineDumbbellSmithRoundTripReusesOriginalAndPersists() throws {
        let (container, context, day, original) = try fixture()
        original.exerciseName = "Incline Dumbbell Press"
        original.muscleTarget = "Upper Chest"
        try context.save()
        let smith = try ExerciseReplacement.replace(original, with: "Incline Smith Machine Press",
            loggedSetNumbers: [], preferFuture: false, modelContext: context)
        XCTAssertTrue(ExerciseReplacement.candidates(for: smith, avoidedKeys: []).contains("Incline Dumbbell Press"))
        XCTAssertFalse(ExerciseReplacement.candidates(for: smith, avoidedKeys: []).contains("Incline Barbell Press"))
        XCTAssertFalse(ExerciseReplacement.candidates(for: smith, avoidedKeys: []).contains("Machine Shoulder Press"))
        let returned = try ExerciseReplacement.replace(smith, with: "Incline Dumbbell Press",
            loggedSetNumbers: [], preferFuture: false, modelContext: context)
        XCTAssertTrue(returned === original)
        XCTAssertEqual(returned.sets, 3)
        XCTAssertEqual(day.activeExercises.map(\.exerciseName), ["Incline Dumbbell Press"])
        XCTAssertEqual(day.exercises.count, 2)
        let reopened = ModelContext(container)
        let restored = try XCTUnwrap(reopened.fetch(FetchDescriptor<WorkoutDay>()).first)
        XCTAssertEqual(restored.activeExercises.map(\.exerciseName), ["Incline Dumbbell Press"])
        XCTAssertEqual(restored.activeExercises.first?.sets, 3)
    }

    func testPartialReturnPreservesBothLogsAndTotalRemainingBudget() throws {
        let (_, context, day, original) = try fixture()
        let originalLog = ExercisePerformanceLog(exerciseName: dumbbell, weightLbs: 20, repsCompleted: 12,
            workoutDayNumber: 1, prescribedSets: 3, prescribedReps: "10-15",
            setLogs: [SetLogEntry(setNumber: 1, weightLbs: 20, repsCompleted: 12)])
        context.insert(originalLog)
        try context.save()
        let alternate = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [1],
            preferFuture: false, modelContext: context)
        let alternateLog = ExercisePerformanceLog(exerciseName: machine, weightLbs: 45, repsCompleted: 10,
            workoutDayNumber: 1, prescribedSets: 2, prescribedReps: "10-15",
            setLogs: [SetLogEntry(setNumber: 1, weightLbs: 45, repsCompleted: 10)])
        context.insert(alternateLog)
        try context.save()
        let originalJSON = originalLog.setLogsJSON
        let alternateJSON = alternateLog.setLogsJSON
        let returned = try ExerciseReplacement.replace(alternate, with: dumbbell, loggedSetNumbers: [1],
            preferFuture: false, modelContext: context)
        XCTAssertEqual(returned.sets, 2) // 1 original set saved + only 1 set still to do.
        XCTAssertEqual(day.activeExercises.count, 1)
        XCTAssertEqual(originalLog.setLogsJSON, originalJSON)
        XCTAssertEqual(alternateLog.setLogsJSON, alternateJSON)
        XCTAssertEqual(originalLog.prescribedSets, 3)
        XCTAssertEqual(originalLog.weightLbs, 20)
        XCTAssertEqual(alternateLog.weightLbs, 45)
        XCTAssertTrue(ExerciseSessionLog.resolve(for: returned, among: [alternateLog, originalLog], on: .now) === originalLog)
        let again = try ExerciseReplacement.replace(returned, with: machine, loggedSetNumbers: [1],
            preferFuture: false, modelContext: context)
        XCTAssertTrue(again === alternate)
        XCTAssertEqual(again.sets, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExercisePerformanceLog>()), 2)
    }

    func testRepeatedThreeWayReturnsNeverCreateDuplicateRowsOrLoseChoices() throws {
        let (_, context, day, original) = try fixture()
        var current = original
        for name in [machine, cable, dumbbell, cable, machine, dumbbell] + Array(repeating: [machine, cable, dumbbell], count: 10).flatMap({ $0 }) {
            XCTAssertTrue(ExerciseReplacement.candidates(for: current, avoidedKeys: []).contains(name), "Missing \(name) from \(current.exerciseName)")
            current = try ExerciseReplacement.replace(current, with: name, loggedSetNumbers: [],
                preferFuture: false, modelContext: context)
            XCTAssertEqual(current.sets, 3)
            XCTAssertEqual(day.activeExercises.count, 1)
            XCTAssertLessThanOrEqual(day.exercises.count, 3)
            XCTAssertEqual(Set(day.exercises.map(\.exerciseName)).count, day.exercises.count)
        }
    }

    func testReturnKeepsPainAndSkipExclusions() throws {
        for status: ExerciseCompletionStatus in [.skippedPain, .skippedEquipment, .skippedTime] {
            let (_, context, _, original) = try fixture()
            original.completionStatus = status
            original.painReviewRaw = "resolved"
            try context.save()
            let alternate = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
                preferFuture: false, modelContext: context)
            XCTAssertFalse(ExerciseReplacement.candidates(for: alternate, avoidedKeys: []).contains(dumbbell))
            XCTAssertEqual(original.completionStatus, status)
        }
        let (_, context, _, original) = try fixture()
        let alternate = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
            preferFuture: false, modelContext: context)
        XCTAssertThrowsError(try ExerciseReplacement.replace(alternate, with: dumbbell, loggedSetNumbers: [],
            preferFuture: false, avoidedKeys: [ExerciseWeightEntry.canonicalLookupKey(dumbbell)], modelContext: context))
    }

    func testReturnRejectsSparseAndSummaryOnlyLogsWithoutMutation() throws {
        for sets in [[], [SetLogEntry(setNumber: 4, weightLbs: 20, repsCompleted: 12)]] {
            let (_, context, day, original) = try fixture()
            let alternate = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
                preferFuture: false, modelContext: context)
            context.insert(ExercisePerformanceLog(exerciseName: dumbbell, weightLbs: 20,
                workoutDayNumber: 1, setLogs: sets))
            try context.save()
            XCTAssertThrowsError(try ExerciseReplacement.replace(alternate, with: dumbbell, loggedSetNumbers: [],
                preferFuture: false, modelContext: context))
            XCTAssertEqual(day.activeExercises.map(\.exerciseName), [machine])
            XCTAssertEqual(original.sets, 3)
        }
    }

    func testReturnPreferenceAndFailureRollback() throws {
        struct SaveFailure: Error {}
        let (container, context, day, original) = try fixture()
        let alternate = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
            preferFuture: true, modelContext: context)
        XCTAssertThrowsError(try ExerciseReplacement.replace(alternate, with: dumbbell, loggedSetNumbers: [],
            preferFuture: true, modelContext: context, save: { _ in throw SaveFailure() }))
        XCTAssertEqual(day.activeExercises.map(\.exerciseName), [machine])
        XCTAssertEqual(original.preferredReplacementName, machine)
        XCTAssertEqual(original.replacementName, machine)
        XCTAssertEqual(alternate.replacementName, "")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<WorkoutExercise>()), 2)
        try context.save()
        _ = try ExerciseReplacement.replace(alternate, with: dumbbell, loggedSetNumbers: [],
            preferFuture: true, modelContext: context)
        XCTAssertEqual(original.preferredReplacementName, "")
        XCTAssertEqual(alternate.preferredReplacementName, dumbbell)
    }

    func testFailedMiddleReturnRestoresAllChainEdges() throws {
        struct SaveFailure: Error {}
        let (container, context, day, original) = try fixture()
        let second = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
            preferFuture: false, modelContext: context)
        let third = try ExerciseReplacement.replace(second, with: cable, loggedSetNumbers: [],
            preferFuture: false, modelContext: context)
        let orderBefore = day.sortedExercises.map(\.exerciseName)
        XCTAssertThrowsError(try ExerciseReplacement.replace(third, with: machine, loggedSetNumbers: [],
            preferFuture: false, modelContext: context, save: { _ in throw SaveFailure() }))
        XCTAssertEqual(original.replacementName, machine)
        XCTAssertEqual(second.replacementName, cable)
        XCTAssertEqual(third.replacementName, "")
        XCTAssertEqual(day.sortedExercises.map(\.exerciseName), orderBefore)
        let reloaded = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<WorkoutDay>()).first)
        XCTAssertEqual(reloaded.activeExercises.map(\.exerciseName), [cable])
    }

    func testSharedSessionAdapterRejectsOldProgramAndWrongDayLogs() throws {
        let (_, _, day, original) = try fixture()
        let old = ExercisePerformanceLog(exerciseName: dumbbell, weightLbs: 100, workoutDayNumber: 1)
        old.loggedAt = try XCTUnwrap(day.program).createdDate.addingTimeInterval(-60)
        let otherDay = ExercisePerformanceLog(exerciseName: dumbbell, weightLbs: 200, workoutDayNumber: 2)
        let current = ExercisePerformanceLog(exerciseName: dumbbell, weightLbs: 20, workoutDayNumber: 1)
        XCTAssertNil(ExerciseSessionLog.resolve(for: original, among: [old, otherDay], on: .now))
        XCTAssertTrue(ExerciseSessionLog.resolve(for: original, among: [old, otherDay, current], on: .now) === current)
    }

    func testReversePreferenceCannotBeSilentlyIgnored() throws {
        let (_, context, _, original) = try fixture()
        original.exerciseName = "Incline Dumbbell Press"
        try context.save()
        let alternate = try ExerciseReplacement.replace(original, with: "Incline Smith Machine Press",
            loggedSetNumbers: [], preferFuture: false, modelContext: context)
        XCTAssertTrue(ExerciseReplacement.candidates(for: alternate, avoidedKeys: []).contains(original.exerciseName))
        XCTAssertFalse(ExerciseReplacement.compatible(originalName: alternate.exerciseName, candidateName: original.exerciseName))
        XCTAssertThrowsError(try ExerciseReplacement.replace(alternate, with: original.exerciseName,
            loggedSetNumbers: [], preferFuture: true, modelContext: context))
        XCTAssertEqual(alternate.preferredReplacementName, "")
        XCTAssertTrue(try ExerciseReplacement.replace(alternate, with: original.exerciseName,
            loggedSetNumbers: [], preferFuture: false, modelContext: context) === original)
    }

    func testPainExclusionRevalidatedAndOriginalPainNotErased() throws {
        let (_, context, day, original) = try fixture()
        let painDay = WorkoutDay(dayNumber: 2, dayName: "Earlier", muscleGroups: "Shoulders")
        let painful = WorkoutExercise(order: 0, exerciseName: machine, sets: 3, reps: "10-15")
        painful.completionStatus = .skippedPain
        painful.painReviewRaw = "notSure"
        context.insert(painDay)
        painDay.program = day.program
        day.program?.days.append(painDay)
        painDay.exercises = [painful]
        painful.day = painDay
        original.completionStatus = .skippedPain
        original.isCompleted = true
        try context.save()
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: false, modelContext: context))
        _ = try ExerciseReplacement.replace(original, with: cable,
            loggedSetNumbers: [], preferFuture: true, modelContext: context)
        XCTAssertEqual(original.completionStatus, .skippedPain)
        XCTAssertEqual(original.painReviewRaw, "")
    }

    func testFinishedSessionAndStaleCandidateRefuse() throws {
        let (_, context, day, original) = try fixture()
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: "Machine Shoulder Press",
            loggedSetNumbers: [], preferFuture: false, modelContext: context))
        day.isSessionClosed = true
        try context.save()
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: false, modelContext: context))
        XCTAssertEqual(day.exercises.count, 1)
    }

    func testFinalSkipCanBeReplacedTodayAndReopensSession() throws {
        let (_, context, day, original) = try fixture()
        original.completionStatus = .skippedEquipment
        original.isCompleted = true
        SessionLifecycle.syncDayCompletion(for: day)
        try context.save()
        XCTAssertTrue(day.isSessionClosed)
        _ = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
                                             preferFuture: false, modelContext: context)
        XCTAssertFalse(day.isCompleted)
        XCTAssertFalse(day.isSessionClosed)
        XCTAssertFalse(day.allExercisesResolved)
        XCTAssertEqual(original.completionStatus, .skippedEquipment)
    }

    func testSkipReasonsSurviveReplacementAndStillInformEquipmentHistory() throws {
        for status: ExerciseCompletionStatus in [.skippedEquipment, .skippedTime] {
            let (_, context, day, original) = try fixture()
            original.completionStatus = status
            original.isCompleted = true
            try context.save()
            _ = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
                preferFuture: false, modelContext: context)
            XCTAssertEqual(original.completionStatus, status)
            if status == .skippedEquipment {
                let prior = WorkoutDay(dayNumber: 2, dayName: "Earlier", muscleGroups: "Shoulders")
                let skipped = WorkoutExercise(order: 0, exerciseName: dumbbell, sets: 3, reps: "10-15")
                skipped.completionStatus = status
                prior.exercises = [skipped]
                skipped.day = prior
                prior.program = day.program
                day.program?.days.append(prior)
                XCTAssertTrue(ExerciseHistoryAggregator.context(from: [try XCTUnwrap(day.program)])
                    .equipmentSkipExercises.contains(ExerciseWeightEntry.canonicalLookupKey(dumbbell)))
            }
        }
    }

    func testHiddenOriginalCannotStrandReopenedDay() throws {
        let (_, context, day, original) = try fixture()
        let replacement = try ExerciseReplacement.replace(original, with: machine, loggedSetNumbers: [],
            preferFuture: false, modelContext: context)
        replacement.isCompleted = true
        SessionLifecycle.syncDayCompletion(for: day)
        XCTAssertTrue(day.isCompleted)
        for item in day.exercises { item.isCompleted = false }
        SessionLifecycle.syncDayCompletion(for: day)
        replacement.isCompleted = true
        SessionLifecycle.syncDayCompletion(for: day)
        XCTAssertTrue(day.isCompleted)
        XCTAssertTrue(original.isResolved)
        XCTAssertEqual(day.activeExercises.count, 1)
    }

    func testPastFinalSkipCannotReopenHistoricalDay() throws {
        let (_, context, day, original) = try fixture()
        original.completionStatus = .skippedEquipment
        original.isCompleted = true
        let yesterday = Date().addingTimeInterval(-48 * 60 * 60)
        SessionLifecycle.syncDayCompletion(for: day, now: yesterday)
        try context.save()
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: false, modelContext: context))
        XCTAssertTrue(day.isSessionClosed)
    }

    func testCompatibleCommonCurlsAndPresses() {
        XCTAssertTrue(ExerciseReplacement.compatible(originalName: "Dumbbell Shoulder Press",
                                                     candidateName: "Machine Shoulder Press"))
        XCTAssertTrue(ExerciseReplacement.compatible(originalName: "Incline Dumbbell Press",
                                                     candidateName: "Incline Barbell Press"))
        XCTAssertTrue(ExerciseReplacement.compatible(originalName: "Barbell Curl",
                                                     candidateName: "Cable Curl"))
    }

    func testUnrelatedUnsavedEditIsNotRolledBack() throws {
        let (_, context, day, original) = try fixture()
        day.notes = "Keep this pending user edit"
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: false, modelContext: context))
        XCTAssertEqual(day.notes, "Keep this pending user edit")
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(day.exercises.count, 1)
    }

    func testAlreadyLoggedDestinationCannotMergeIntoNewCard() throws {
        let (_, context, _, original) = try fixture()
        let log = ExercisePerformanceLog(exerciseName: machine, weightLbs: 45,
                                         workoutDayNumber: 1)
        context.insert(log)
        try context.save()
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: false, modelContext: context))
    }

    func testLatestPreferenceSupersedesOtherSourceRowsAndRollbackRestoresThem() throws {
        struct SaveFailure: Error {}
        let (_, context, day, original) = try fixture()
        let older = WorkoutExercise(order: 0, exerciseName: dumbbell, sets: 3, reps: "10-15")
        older.preferredReplacementName = cable
        let earlierDay = WorkoutDay(dayNumber: 2, dayName: "Earlier", muscleGroups: "Shoulders")
        context.insert(earlierDay)
        earlierDay.program = day.program
        day.program?.days.append(earlierDay)
        earlierDay.exercises = [older]
        older.day = earlierDay
        try context.save()
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: true, modelContext: context,
            save: { _ in throw SaveFailure() }))
        XCTAssertEqual(older.preferredReplacementName, cable)
        // Explicit restoration can mark equivalent values dirty; persist the verified snapshot.
        try context.save()
        _ = try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [], preferFuture: true, modelContext: context)
        XCTAssertEqual(older.preferredReplacementName, "")
        XCTAssertEqual(original.preferredReplacementName, machine)
    }

    func testFailedSaveRestoresOriginalAndOrdering() throws {
        struct SaveFailure: Error {}
        let (container, context, day, original) = try fixture()
        XCTAssertThrowsError(try ExerciseReplacement.replace(original, with: machine,
            loggedSetNumbers: [1], preferFuture: true, modelContext: context,
            save: { _ in throw SaveFailure() }))
        XCTAssertEqual(day.exercises.count, 1)
        XCTAssertTrue(day.exercises.first === original)
        XCTAssertEqual(original.order, 4)
        XCTAssertEqual(original.sets, 3)
        XCTAssertFalse(original.isCompleted)
        XCTAssertEqual(original.completionStatusRaw, "")
        XCTAssertEqual(original.replacementName, "")
        XCTAssertEqual(original.preferredReplacementName, "")
        let reopened = ModelContext(container)
        XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<WorkoutExercise>()), 1)
    }
}
