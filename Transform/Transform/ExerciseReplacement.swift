import Foundation
import SwiftData

/// A replacement is new remaining work, never a rename of recorded work. Catalog matching
/// preserves programming intent; it is not a claim that an alternative is pain-free.
@MainActor
enum ExerciseReplacement {
    enum Failure: LocalizedError {
        case unavailableSession, alreadyReplaced, noRemainingSets, ineligibleCandidate, unsavedChanges

        nonisolated var errorDescription: String? {
            switch self {
            case .unavailableSession: return "This session is finished or unavailable."
            case .alreadyReplaced: return "This exercise has already been replaced."
            case .noRemainingSets: return "There are no remaining sets to replace."
            case .ineligibleCandidate: return "This replacement is no longer available. Choose another exercise."
            case .unsavedChanges: return "Save your current changes before replacing this exercise."
            }
        }
    }

    /// Only explicit catalog entries/aliases qualify; inferred metadata is too permissive
    /// for a user-facing assertion that two movements fill the same slot.
    private static func metadata(_ name: String) -> ClaudeService.ExerciseMetadata? {
        let service = ClaudeService.shared
        let key = service.normalizeExerciseName(name)
        let resolved = ClaudeService.exerciseNameAliasCache[key].map(service.normalizeExerciseName) ?? key
        return service.exerciseMetadataCatalog[resolved]
    }

    static func compatible(originalName: String, candidateName: String) -> Bool {
        guard let original = metadata(originalName), let candidate = metadata(candidateName),
              ExerciseWeightEntry.canonicalLookupKey(original.canonicalName)
                != ExerciseWeightEntry.canonicalLookupKey(candidate.canonicalName) else { return false }
        let service = ClaudeService.shared
        return Set(original.primaryAreas) == Set(candidate.primaryAreas)
            && original.movementPattern == candidate.movementPattern
            && original.exerciseClass == candidate.exerciseClass
            && service.proceduralExerciseRole(for: original.canonicalName,
                                              muscleTarget: original.primaryAreas.joined(separator: ", "))
                == service.proceduralExerciseRole(for: candidate.canonicalName,
                                                  muscleTarget: candidate.primaryAreas.joined(separator: ", "))
            && candidate.shoulderRisk <= original.shoulderRisk
            && candidate.systemicFatigue <= original.systemicFatigue
            && candidate.fatigueCost <= original.fatigueCost
    }

    static func candidates(for exercise: WorkoutExercise, avoidedKeys: Set<String>) -> [String] {
        guard exercise.replacementName.isEmpty, let day = exercise.day,
              sessionAllowsReplacement(exercise) else { return [] }
        let occupied = Set(day.exercises.flatMap { item in
            [ExerciseWeightEntry.canonicalLookupKey(item.exerciseName),
             ExerciseWeightEntry.canonicalLookupKey(metadata(item.exerciseName)?.canonicalName ?? item.exerciseName)]
        })
        return ClaudeService.shared.exerciseMetadataCatalog.values
            .filter { candidate in
                let key = ExerciseWeightEntry.canonicalLookupKey(candidate.canonicalName)
                return !occupied.contains(key) && !avoidedKeys.contains(key)
                    && compatible(originalName: exercise.exerciseName, candidateName: candidate.canonicalName)
            }
            .map(\.canonicalName)
            .sorted()
    }

    private static func sessionAllowsReplacement(_ exercise: WorkoutExercise) -> Bool {
        guard let day = exercise.day, !day.isRestDay, day.program?.isArchived != true,
              day.feedbackSubmittedAt == nil else { return false }
        if let end = day.sessionEndedAt, !Calendar.current.isDateInToday(end) { return false }
        guard day.hasReviewableSession else { return true }
        // Skipping the final lift auto-closes the day. Choosing an alternative immediately
        // afterwards is still today's training, unlike editing a historical/explicit finish.
        return day.isCompleted && (exercise.completionStatus?.isSkipped ?? false)
            && day.sessionEndedAt.map { Calendar.current.isDateInToday($0) } == true
    }

    /// `loggedSetNumbers` must come from the session resolver for THIS day, not global history.
    /// A clean context prevents rollback from discarding an unrelated pending user edit.
    /// `save` is a failure-injection seam; production uses a single ModelContext save.
    @discardableResult
    static func replace(
        _ exercise: WorkoutExercise,
        with candidateName: String,
        loggedSetNumbers: Set<Int>,
        preferFuture: Bool,
        avoidedKeys: Set<String> = [],
        modelContext: ModelContext,
        save: @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> WorkoutExercise {
        guard let day = exercise.day, sessionAllowsReplacement(exercise),
              day.exercises.contains(where: { $0 === exercise }) else { throw Failure.unavailableSession }
        guard exercise.replacementName.isEmpty else { throw Failure.alreadyReplaced }
        let completedCount = loggedSetNumbers.filter { $0 > 0 }.count
        guard exercise.sets > completedCount else { throw Failure.noRemainingSets }
        guard !modelContext.hasChanges else { throw Failure.unsavedChanges }

        // Re-read exclusions when committing: a stale picker must not bypass a new pain flag.
        let programs = try modelContext.fetch(FetchDescriptor<WorkoutProgram>())
        let exclusions = avoidedKeys.union(ExercisePainReview.activeKeys(from: programs))
        guard candidates(for: exercise, avoidedKeys: exclusions).contains(candidateName),
              let candidate = metadata(candidateName) else { throw Failure.ineligibleCandidate }
        // Logs are keyed by canonical name + day number + session date, not model identity.
        // Refuse an already-logged destination even if its old card is no longer on the day.
        let candidateKey = ExerciseWeightEntry.canonicalLookupKey(candidateName)
        let destinationLogs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())
        guard !destinationLogs.contains(where: {
            $0.canonicalExerciseKey == candidateKey && $0.workoutDayNumber == day.dayNumber
                && Calendar.current.isDateInToday($0.loggedAt)
        }) else { throw Failure.ineligibleCandidate }

        let oldExercises = day.exercises
        let oldOrders = oldExercises.map { ($0, $0.order) }
        let oldStatus = exercise.completionStatusRaw
        let oldCompleted = exercise.isCompleted
        let oldReplacement = exercise.replacementName
        let oldPreference = exercise.preferredReplacementName
        let sourceKey = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let oldPreferences = preferFuture ? programs.flatMap(\.days).flatMap(\.exercises)
            .filter { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) == sourceKey }
            .map { ($0, $0.preferredReplacementName) } : []
        let oldDayCompleted = day.isCompleted
        let oldDayClosed = day.isSessionClosed
        let oldDayEnded = day.sessionEndedAt
        let replacement = WorkoutExercise(
            order: 0, exerciseName: candidate.canonicalName,
            sets: exercise.sets - completedCount, reps: exercise.reps,
            tempo: exercise.tempo, restSeconds: exercise.restSeconds,
            notes: "Replacement for \(exercise.exerciseName). Choose a load for this exercise; stop if it causes pain.",
            muscleTarget: candidate.primaryAreas.joined(separator: ", "), targetRIR: exercise.targetRIR
        )
        // Normalize slot order rather than adding one to a possibly noncontiguous order.
        var ordered = day.sortedExercises
        guard let index = ordered.firstIndex(where: { $0 === exercise }) else { throw Failure.unavailableSession }
        ordered.insert(replacement, at: index + 1)
        let autosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = autosave }
        modelContext.insert(replacement)
        replacement.day = day
        day.exercises = ordered
        for (position, item) in ordered.enumerated() { item.order = position }
        exercise.replacementName = candidate.canonicalName
        if exercise.completionStatus?.isSkipped != true { exercise.completionStatus = .substituted }
        exercise.isCompleted = true
        if preferFuture {
            for (item, _) in oldPreferences { item.preferredReplacementName = "" }
            exercise.preferredReplacementName = candidate.canonicalName
        }
        SessionLifecycle.syncDayCompletion(for: day)
        do {
            try save(modelContext)
        } catch {
            modelContext.rollback()
            // Restore in-memory references as well as persisted values; SwiftUI can still
            // hold these objects after rollback. No logs or weight entries were mutated.
            day.exercises = oldExercises
            for (item, order) in oldOrders { item.order = order }
            exercise.completionStatusRaw = oldStatus
            exercise.isCompleted = oldCompleted
            exercise.replacementName = oldReplacement
            exercise.preferredReplacementName = oldPreference
            for (item, preference) in oldPreferences { item.preferredReplacementName = preference }
            day.isCompleted = oldDayCompleted
            day.isSessionClosed = oldDayClosed
            day.sessionEndedAt = oldDayEnded
            throw error
        }
        return replacement
    }
}
