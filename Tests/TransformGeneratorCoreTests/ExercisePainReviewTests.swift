import XCTest
@testable import Transform

@MainActor
final class ExercisePainReviewTests: XCTestCase {
    private func program(_ names: [String]) -> WorkoutProgram {
        let program = WorkoutProgram(programName: "Test", programSummary: "", splitType: "Full Body", daysPerWeek: 3, focusAreas: "")
        let day = WorkoutDay(dayNumber: 1, dayName: "Training", muscleGroups: "Chest")
        day.program = program
        program.days = [day]
        day.exercises = names.enumerated().map { index, name in
            let exercise = WorkoutExercise(order: index, exerciseName: name, sets: 3, reps: "8-12")
            exercise.day = day
            exercise.completionStatus = .skippedPain
            return exercise
        }
        return program
    }

    func testLegacyAndUnknownFlagsAreActiveAndRequireReview() {
        let p = program(["Bench Press"])
        let e = p.days[0].exercises[0]
        let key = ExerciseWeightEntry.canonicalLookupKey(e.exerciseName)
        for flag in ["", "unknown-future-value", "stillPainful", "notSure"] {
            e.painReviewRaw = flag
            XCTAssertEqual(ExercisePainReview.activeKeys(from: [p]), [key])
            XCTAssertTrue(ExercisePainReview.reviewItems(from: [p], includeResolved: false)[0].requiresReview)
        }
    }

    func testEveryReviewNeedsValidExplicitChoiceAndEmptySelectionCannotBypassIt() {
        let p = program(["Bench Press", "Squat"])
        let items = ExercisePainReview.reviewItems(from: [p], includeResolved: false)
        XCTAssertFalse(ExercisePainReview.canContinue(items: items, selections: [:]))
        var selected = Dictionary(uniqueKeysWithValues: items.map { ($0.key, "notSure") })
        XCTAssertTrue(ExercisePainReview.canContinue(items: items, selections: selected))
        selected[items[0].key] = ""
        XCTAssertFalse(ExercisePainReview.canContinue(items: items, selections: selected))
        selected[items[0].key] = "unknown"
        XCTAssertFalse(ExercisePainReview.canContinue(items: items, selections: selected))
    }

    func testGenerationReviewCannotReleasePersistentAvoidanceWhenNewPainExists() {
        let p = program(["Bench Press", "Bench Press"])
        let key = ExerciseWeightEntry.canonicalLookupKey("Bench Press")
        p.days[0].exercises[0].painReviewRaw = "avoid"
        ExercisePainReview.apply(choice: "resolved", to: key, programs: [p])
        XCTAssertEqual(p.days[0].exercises[0].painReviewRaw, "avoid")
        XCTAssertEqual(p.days[0].exercises[1].painReviewRaw, "resolved")
        XCTAssertEqual(ExerciseHistoryAggregator.context(from: [p]).painExercises, [key])
    }

    func testResolutionAndRecurrenceReachRealGeneratorHistoryWithoutDeletingRecords() {
        let p = program(["Dumbbell Lateral Raise"])
        let key = ExerciseWeightEntry.canonicalLookupKey("Dumbbell Lateral Raise")
        XCTAssertEqual(ExerciseHistoryAggregator.context(from: [p]).painExercises, [key])
        ExercisePainReview.apply(choice: "resolved", to: key, programs: [p])
        XCTAssertTrue(ExerciseHistoryAggregator.context(from: [p]).painExercises.isEmpty)
        p.days[0].exercises[0].painReviewRaw = ""
        XCTAssertEqual(ExerciseHistoryAggregator.context(from: [p]).painExercises, [key])
        XCTAssertEqual(p.days[0].exercises.count, 1)
        XCTAssertEqual(p.days[0].exercises[0].completionStatus, .skippedPain)
    }

    func testResolutionPreservesHistoryAcrossCanonicalAliasesAndPrograms() {
        let old = program(["Bench Press"])
        old.isArchived = true
        let current = program(["Bench Presses"])
        let key = ExerciseWeightEntry.canonicalLookupKey("Bench Press")
        ExercisePainReview.apply(choice: "resolved", to: key, programs: [old, current])
        XCTAssertTrue(ExercisePainReview.activeKeys(from: [old, current]).isEmpty)
        XCTAssertTrue(ExercisePainReview.reviewItems(from: [old, current], includeResolved: false).isEmpty)
        XCTAssertEqual(ExercisePainReview.reviewItems(from: [old, current], includeResolved: true).count, 1)
        for p in [old, current] {
            XCTAssertEqual(p.days[0].exercises[0].completionStatus, .skippedPain)
            XCTAssertEqual(p.days[0].exercises[0].sets, 3)
        }
    }

    func testNewPainReactivatesResolvedCanonicalHistory() {
        let p = program(["Bench Press", "Bench Presses"])
        let key = ExerciseWeightEntry.canonicalLookupKey("Bench Press")
        ExercisePainReview.apply(choice: "resolved", to: key, programs: [p])
        p.days[0].exercises[1].painReviewRaw = ""
        XCTAssertEqual(ExercisePainReview.activeKeys(from: [p]), [key])
        XCTAssertTrue(ExercisePainReview.reviewItems(from: [p], includeResolved: false)[0].requiresReview)
    }

    func testAvoidRemainsExcludedWithoutRepeatedGateUntilExplicitlyChanged() {
        let p = program(["Bench Press"])
        let key = ExerciseWeightEntry.canonicalLookupKey("Bench Press")
        ExercisePainReview.apply(choice: "avoid", to: key, programs: [p])
        XCTAssertEqual(ExercisePainReview.activeKeys(from: [p]), [key])
        XCTAssertFalse(ExercisePainReview.reviewItems(from: [p], includeResolved: false)[0].requiresReview)
        ExercisePainReview.apply(choice: "invalid", to: key, programs: [p])
        XCTAssertEqual(p.days[0].exercises[0].painReviewRaw, "avoid")
        ExercisePainReview.apply(choice: "resolved", to: key, programs: [p])
        XCTAssertEqual(ExercisePainReview.activeKeys(from: [p]), [key], "Generation review cannot undo an explicit persistent avoidance")
        ExercisePainReview.apply(choice: "resolved", to: key, programs: [p], includePersistentAvoidances: true)
        XCTAssertTrue(ExercisePainReview.activeKeys(from: [p]).isEmpty)
    }

    func testNonPainDispositionAndOtherCanonicalHistoryAreUntouched() {
        let p = program(["Bench Press", "Squat", "Bench Press"])
        p.days[0].exercises[2].completionStatus = .skippedEquipment
        ExercisePainReview.apply(choice: "resolved", to: ExerciseWeightEntry.canonicalLookupKey("Bench Press"), programs: [p])
        XCTAssertEqual(p.days[0].exercises[2].painReviewRaw, "")
        XCTAssertEqual(ExercisePainReview.activeKeys(from: [p]), [ExerciseWeightEntry.canonicalLookupKey("Squat")])
    }

    func testCatalogAliasPainBlocksCanonicalReplacementWithoutRekeyingHistory() {
        let p = program(["Rope Pushdown", "Rope Triceps Pressdown"])
        let key = ExerciseWeightEntry.canonicalLookupKey("Rope Triceps Pressdown")
        XCTAssertEqual(ExercisePainReview.reviewItems(from: [p], includeResolved: false).count, 1)
        XCTAssertTrue(ExerciseHistoryAggregator.context(from: [p]).painExercises.contains(key))
        ExercisePainReview.apply(choice: "resolved", to: key, programs: [p])
        XCTAssertTrue(ExerciseHistoryAggregator.context(from: [p]).painExercises.isEmpty)
        XCTAssertEqual(p.days[0].exercises[0].exerciseName, "Rope Pushdown")
        XCTAssertEqual(p.days[0].exercises[0].completionStatus, .skippedPain)
    }
}
