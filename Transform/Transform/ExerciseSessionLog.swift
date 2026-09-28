import Foundation

/// Shared model adapter: replacement accounting and the logger must read the same session.
@MainActor
enum ExerciseSessionLog {
    static func resolve(for exercise: WorkoutExercise, among logs: [ExercisePerformanceLog], on date: Date) -> ExercisePerformanceLog? {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let pool = logs.filter {
            $0.canonicalExerciseKey == key && $0.workoutDayNumber == (exercise.day?.dayNumber ?? 0)
                && SessionLogResolution.belongsToProgram(logDate: $0.loggedAt, programStart: exercise.day?.program?.createdDate)
        }
        let index = SessionLogResolution.indexOfSession(candidateDates: pool.map(\.loggedAt),
            sessionDates: exercise.day?.sessionCalendarDates ?? [], viewingDate: date)
        return index.map { pool[$0] }
    }
}
