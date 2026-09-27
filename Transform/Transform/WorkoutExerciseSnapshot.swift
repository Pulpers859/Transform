import Foundation

/// Actual backup wire shape, shared with the headless tests. Additive optional fields
/// decode old backups without inventing a recovery decision or replacement preference.
nonisolated struct WorkoutExerciseSnapshot: Codable {
    let order: Int
    let exerciseName: String
    let sets: Int
    let reps: String
    let tempo: String?
    let restSeconds: Int
    let notes: String
    let muscleTarget: String
    let isCompleted: Bool
    let completionStatusRaw: String?
    let targetRIR: Int?
    let coachingSourceRaw: String?
    let painReviewRaw: String?
    let replacementName: String?
    let preferredReplacementName: String?
}
