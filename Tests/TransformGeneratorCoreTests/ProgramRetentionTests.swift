import XCTest
@testable import Transform

/// What counts as a program worth keeping when a new one replaces it.
///
/// Regeneration archives a program that holds athlete history and DELETES one that does
/// not (`WorkoutView.generateFirstWeek`). The predicate behind that fork decides whether
/// real training signal survives, so it gets executed coverage rather than inspection.
///
/// The bug these tests pin: the fork used `hasCompletedExercises`, which is only
/// `isCompleted`. `.substituted` is the one settling status that deliberately does not set
/// `isCompleted` — `ExerciseCompletionStatus.marksExerciseFinished` returns false for it
/// because a substitution is work still to be performed. Meanwhile
/// `WorkoutView.recurringSkipHistory` counts `.substituted` and feeds it into every later
/// generation prompt. So a program whose only athlete input was substitutions read as an
/// empty shell, was hard-deleted, and took that signal with it.
@MainActor
final class ProgramRetentionTests: XCTestCase {

    // MARK: - Builders

    private func makeProgram(configure: (WorkoutExercise) -> Void) -> WorkoutProgram {
        let program = WorkoutProgram(
            programName: "Test Program",
            programSummary: "Summary",
            splitType: "Push/Pull/Legs",
            daysPerWeek: 5,
            focusAreas: "Chest"
        )
        let day = WorkoutDay(dayNumber: 1, dayName: "Push", muscleGroups: "Chest")
        let exercise = WorkoutExercise(
            order: 0,
            exerciseName: "Barbell Bench Press",
            sets: 3,
            reps: "8-12"
        )
        configure(exercise)
        exercise.day = day
        day.exercises.append(exercise)
        day.program = program
        program.days.append(day)
        return program
    }

    // MARK: - The regression

    /// A substitution is athlete history the generator reads back, so the program must be
    /// archived, not deleted. `hasCompletedExercises` is asserted false in the same test to
    /// pin WHY the old predicate got this wrong rather than just asserting the new one.
    func testSubstitutionOnlyProgramCountsAsAthleteHistory() {
        let program = makeProgram { $0.completionStatus = .substituted }

        XCTAssertFalse(
            program.hasCompletedExercises,
            "A substitution deliberately leaves isCompleted false — that is the gap."
        )
        XCTAssertTrue(
            program.hasAthleteHistory,
            "A substituted exercise is signal recurringSkipHistory feeds to the next generation."
        )
    }

    /// The partial-logging case, and the reason `sessionStartedAt` is in the predicate.
    ///
    /// `autoCompleteAfterFinalSet` only sets `isCompleted` when the LAST prescribed set is
    /// logged, so an athlete who logged two sets of four and stopped leaves `isCompleted`
    /// false and no status at all. `SessionLifecycle.noteSetLogged` stamps `sessionStartedAt`
    /// on the first logged set, and that is the only mark such a program carries.
    func testAPartiallyLoggedSessionCountsAsAthleteHistory() {
        let program = makeProgram { _ in }
        program.days.first?.sessionStartedAt = Date()

        XCTAssertFalse(
            program.hasCompletedExercises,
            "Premise: logging some but not all sets never sets isCompleted"
        )
        XCTAssertTrue(
            program.hasAthleteHistory,
            "An athlete who started training this program has not left an empty shell"
        )
    }

    /// A rated session is history even if every exercise was left unticked.
    func testARatedSessionCountsAsAthleteHistory() {
        let program = makeProgram { _ in }
        program.days.first?.feedbackSubmittedAt = Date()

        XCTAssertTrue(program.hasAthleteHistory)
    }

    /// `WorkoutExercise.weightLogs` is NOT the signal, and this pins why rather than leaving
    /// the next reader to re-derive it. `summaryEntryOrCreate` fetches `ExerciseWeightEntry`
    /// globally by `canonicalExerciseKey` and never sets the inverse, so the relationship is
    /// always empty in the app — the only assignment to `ExerciseWeightEntry.exercise` in the
    /// tree is `survivor.exercise = nil`. A first version of `hasAthleteHistory` tested it and
    /// was therefore a guard no producer could reach. If a future change starts populating the
    /// relationship, this test failing is the signal to revisit the predicate.
    func testWeightLogsRelationshipIsNotPopulatedSoItCannotBeTheSignal() {
        let program = makeProgram { exercise in
            let entry = ExerciseWeightEntry(exerciseName: "Barbell Bench Press", weightLbs: 185)
            exercise.weightLogs.append(entry)
        }

        XCTAssertFalse(
            program.hasAthleteHistory,
            "Appending a weight log must not be what saves a program — the app never builds "
                + "this link, so relying on it would be a guard nothing can reach"
        )
    }

    // MARK: - The predicate must still say no to a genuinely untouched program

    /// The delete branch has to keep working. A program the athlete never opened is an
    /// empty shell and regeneration should remove it rather than pile up archives.
    func testUntouchedProgramHasNoAthleteHistory() {
        let program = makeProgram { _ in }

        XCTAssertFalse(program.hasCompletedExercises)
        XCTAssertFalse(
            program.hasAthleteHistory,
            "Widening the predicate must not turn every abandoned program into an archive."
        )
    }

    /// The original case still holds.
    func testCompletedProgramHasAthleteHistory() {
        let program = makeProgram { $0.isCompleted = true }

        XCTAssertTrue(program.hasCompletedExercises)
        XCTAssertTrue(program.hasAthleteHistory)
    }

    /// Every skip sets `isCompleted` at the call site, so skips were never the gap — but
    /// they are the history the archive rule exists to protect, so they stay pinned.
    func testSkippedForPainCountsAsAthleteHistory() {
        let program = makeProgram { exercise in
            exercise.completionStatus = .skippedPain
            exercise.isCompleted = true
        }

        XCTAssertTrue(program.hasAthleteHistory)
    }
}
