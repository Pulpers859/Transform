import Foundation
import SwiftData

/// Explicit restrictions are separate from the historical fact that a movement hurt.
@MainActor
enum ExercisePainReview {
    struct Item: Identifiable {
        let key: String
        let name: String
        let choice: String
        let requiresReview: Bool
        var id: String { key }
    }

    static let choices = ["stillPainful", "notSure", "resolved", "avoid"]

    static func canContinue(items: [Item], selections: [String: String]) -> Bool {
        items.allSatisfy { choices.contains(selections[$0.key] ?? "") }
    }

    static func activeKeys(from programs: [WorkoutProgram]) -> Set<String> {
        var keys = Set(reviewItems(from: programs, includeResolved: true)
            .filter { $0.choice != "resolved" }.map(\.key))
        for exercise in programs.flatMap(\.sortedDays).flatMap(\.sortedExercises)
        where exercise.completionStatus == .skippedPain && keys.contains(identity(exercise.exerciseName)) {
            keys.insert(ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName))
        }
        return keys
    }

    /// Expand catalog aliases for restrictions only. Stored performance keys are untouched.
    static func identity(_ name: String) -> String {
        ExerciseWeightEntry.canonicalLookupKey(ClaudeService.shared.canonicalExerciseName(name, muscleTarget: ""))
    }

    static func reviewItems(from programs: [WorkoutProgram], includeResolved: Bool) -> [Item] {
        var grouped: [String: [WorkoutExercise]] = [:]
        for program in programs {
            for day in program.sortedDays where !day.isRestDay {
                for exercise in day.sortedExercises where exercise.completionStatus == .skippedPain {
                    let key = identity(exercise.exerciseName)
                    guard !key.isEmpty else { continue }
                    grouped[key, default: []].append(exercise)
                }
            }
        }
        return grouped.compactMap { key, exercises -> Item? in
            let active = exercises.filter { $0.painReviewRaw != "resolved" }
            guard includeResolved || !active.isEmpty else { return nil }
            let temporary = active.filter { $0.painReviewRaw != "avoid" }
            // Any new/legacy pain report outranks an earlier resolution or avoid decision.
            let temporaryChoice = temporary.allSatisfy { $0.painReviewRaw == "stillPainful" } ? "stillPainful" : "notSure"
            let choice = active.isEmpty ? "resolved" : temporary.isEmpty ? "avoid" : temporaryChoice
            let name = exercises.map(\.exerciseName).sorted().first ?? key
            return Item(key: key, name: name, choice: choice, requiresReview: !temporary.isEmpty)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Mutates only review flags; caller owns save and rollback. Never clears pain history.
    static func apply(choice: String, to key: String, programs: [WorkoutProgram], includePersistentAvoidances: Bool = false) {
        guard choices.contains(choice), !key.isEmpty else { return }
        for program in programs {
            for day in program.sortedDays {
                for exercise in day.sortedExercises
                where exercise.completionStatus == .skippedPain
                    && identity(exercise.exerciseName) == key {
                    if exercise.painReviewRaw == "avoid" && !includePersistentAvoidances { continue }
                    exercise.painReviewRaw = choice
                }
            }
        }
    }
}
