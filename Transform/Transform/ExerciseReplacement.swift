import Foundation
import SwiftData

/// A replacement is new remaining work, never a rename of recorded work. Catalog matching
/// preserves programming intent; it is not a claim that an alternative is pain-free.
enum ExerciseReplacement {
    enum Failure: LocalizedError {
        case unavailableSession, alreadyReplaced, noRemainingSets, ineligibleCandidate, unsavedChanges, incompleteHistory, preferenceUnavailable

        nonisolated var errorDescription: String? {
            switch self {
            case .unavailableSession: return "This session is finished or unavailable."
            case .alreadyReplaced: return "This exercise has already been replaced."
            case .noRemainingSets: return "There are no remaining sets to replace."
            case .ineligibleCandidate: return "This replacement is no longer available. Choose another exercise."
            case .unsavedChanges: return "Save your current changes before replacing this exercise."
            case .incompleteHistory: return "This earlier exercise has gaps in its set numbers or only a summary log. Returning could miscount your remaining sets, so no changes were made."
            case .preferenceUnavailable: return "You can return to this exercise today, but it does not meet the planner's future-substitution limits. Turn off the future preference to continue."
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
        compatible(originalName: originalName, candidateName: candidateName, returning: false)
    }

    private static func compatible(originalName: String, candidateName: String, returning: Bool, live: Bool = false) -> Bool {
        guard let original = metadata(originalName), let candidate = metadata(candidateName),
              ExerciseWeightEntry.canonicalLookupKey(original.canonicalName)
                != ExerciseWeightEntry.canonicalLookupKey(candidate.canonicalName) else { return false }
        let service = ClaudeService.shared
        let compoundClasses: Set<String> = ["Heavy Compound", "Hypertrophy Compound"]
        let sameClass = original.exerciseClass == candidate.exerciseClass
            || (live && compoundClasses.contains(original.exerciseClass) && compoundClasses.contains(candidate.exerciseClass))
        return Set(original.primaryAreas) == Set(candidate.primaryAreas)
            && original.movementPattern == candidate.movementPattern
            && sameClass
            && (live || service.proceduralExerciseRole(for: original.canonicalName,
                                              muscleTarget: original.primaryAreas.joined(separator: ", "))
                == service.proceduralExerciseRole(for: candidate.canonicalName,
                                                  muscleTarget: candidate.primaryAreas.joined(separator: ", ")))
            && (returning || (candidate.shoulderRisk <= original.shoulderRisk
                && candidate.systemicFatigue <= original.systemicFatigue
                && candidate.fatigueCost <= original.fatigueCost))
    }

    private static func identity(_ name: String) -> String {
        ExerciseWeightEntry.canonicalLookupKey(metadata(name)?.canonicalName ?? name)
    }

    /// Walk backward through this slot only. Never adopt another slot's historical card.
    @MainActor
    private static func ancestors(of exercise: WorkoutExercise) -> [WorkoutExercise] {
        guard let day = exercise.day else { return [] }
        var result: [WorkoutExercise] = []
        var visited: Set<String> = [identity(exercise.exerciseName)]
        var current = exercise
        while true {
            let predecessors = day.exercises.filter {
                !$0.replacementName.isEmpty && identity($0.replacementName) == identity(current.exerciseName)
            }
            guard predecessors.count == 1, let previous = predecessors.first,
                  visited.insert(identity(previous.exerciseName)).inserted else { break }
            result.append(previous)
            current = previous
        }
        return result
    }

    @MainActor
    private static func returningExercise(for exercise: WorkoutExercise, name: String) -> WorkoutExercise? {
        let matching = exercise.day?.exercises.filter { identity($0.exerciseName) == identity(name) } ?? []
        guard matching.count == 1, let prior = matching.first,
              // Reversal must not erase a recorded skip/pain disposition.
              prior.completionStatus?.isSkipped != true,
              ancestors(of: exercise).contains(where: { $0 === prior }) else { return nil }
        return prior
    }

    @MainActor
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
                let returning = returningExercise(for: exercise, name: candidate.canonicalName) != nil
                return (!occupied.contains(key) || returning) && !avoidedKeys.contains(key)
                    && compatible(originalName: exercise.exerciseName, candidateName: candidate.canonicalName, returning: returning, live: true)
            }
            .map(\.canonicalName)
            .sorted()
    }

    /// Visible only when the picker is empty. Do not call a session/storage gate a
    /// shortage of exercises; this report uses the same predicates as the picker.
    @MainActor
    static func emptyCandidateExplanation(for exercise: WorkoutExercise, avoidedKeys: Set<String>) -> String {
        if !exercise.replacementName.isEmpty {
            return "This is a previous replacement card. Open Replace on the active exercise instead. [R2: previous-card]"
        }
        if let reason = sessionBlockReason(exercise) { return reason }
        guard let day = exercise.day else { return "The exercise is not linked to its workout day. [R2: missing-day]" }
        guard metadata(exercise.exerciseName) != nil else {
            return "The exercise name could not be matched to the exercise library. [R2: unknown-name]"
        }
        let occupied = Set(day.exercises.flatMap { item in
            [ExerciseWeightEntry.canonicalLookupKey(item.exerciseName), identity(item.exerciseName)]
        })
        let compatibleNames = ClaudeService.shared.exerciseMetadataCatalog.values.filter {
            compatible(originalName: exercise.exerciseName, candidateName: $0.canonicalName,
                returning: returningExercise(for: exercise, name: $0.canonicalName) != nil, live: true)
        }.map(\.canonicalName)
        let unoccupied = compatibleNames.filter {
            !occupied.contains(ExerciseWeightEntry.canonicalLookupKey($0)) || returningExercise(for: exercise, name: $0) != nil
        }
        let available = unoccupied.filter { !avoidedKeys.contains(ExerciseWeightEntry.canonicalLookupKey($0)) }
        let counts = "[R2: compatible=\(compatibleNames.count), after-day-filter=\(unoccupied.count), after-pain-filter=\(available.count)]"
        if compatibleNames.isEmpty { return "The library has no alternative meeting this exercise's current matching rules. \(counts)" }
        if unoccupied.isEmpty { return "Matching alternatives are already on this day or belong to protected replacement history. \(counts)" }
        if available.isEmpty { return "The remaining matching alternatives are excluded by recorded pain restrictions. Review them in Exercise Preferences only if their status has changed. \(counts)" }
        return "Alternatives were found, but the list did not display them. Close and reopen this picker. \(counts)"
    }

    @MainActor
    private static func sessionAllowsReplacement(_ exercise: WorkoutExercise) -> Bool {
        sessionBlockReason(exercise) == nil
    }

    @MainActor
    private static func sessionBlockReason(_ exercise: WorkoutExercise) -> String? {
        guard let day = exercise.day else { return "The exercise is not linked to its workout day. [R2: missing-day]" }
        if day.isRestDay { return "This day is stored as a rest day. [R2: rest-day]" }
        if day.program?.isArchived == true { return "This workout belongs to an archived program. [R2: archived-program]" }
        if day.feedbackSubmittedAt != nil { return "This workout has submitted session feedback and is protected from replacement. [R2: rated-session]" }
        if let end = day.sessionEndedAt, !Calendar.current.isDateInToday(end) {
            return "This workout has a saved session-end date on a different calendar day, even if it appears unfinished. [R2: different-end-date]"
        }
        guard day.hasReviewableSession else { return nil }
        // Skipping the final lift auto-closes the day. Choosing an alternative immediately
        // afterwards is still today's training, unlike editing a historical/explicit finish.
        if day.isCompleted && (exercise.completionStatus?.isSkipped ?? false)
            && day.sessionEndedAt.map({ Calendar.current.isDateInToday($0) }) == true { return nil }
        return "This workout is stored as completed or closed, even if sets remain. [R2: completed=\(day.isCompleted), closed=\(day.isSessionClosed)]"
    }

    /// `loggedSetNumbers` must come from the session resolver for THIS day, not global history.
    /// A clean context prevents rollback from discarding an unrelated pending user edit.
    /// `save` is a failure-injection seam; production uses a single ModelContext save.
    @discardableResult
    @MainActor
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
        guard !preferFuture || compatible(originalName: exercise.exerciseName, candidateName: candidateName)
        else { throw Failure.preferenceUnavailable }
        // Logs are keyed by canonical name + day number + session date, not model identity.
        // Refuse an already-logged destination even if its old card is no longer on the day.
        let candidateKey = ExerciseWeightEntry.canonicalLookupKey(candidateName)
        let destinationLogs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())
        let returning = returningExercise(for: exercise, name: candidateName)
        guard returning != nil || !destinationLogs.contains(where: {
            $0.canonicalExerciseKey == candidateKey && $0.workoutDayNumber == day.dayNumber
                && Calendar.current.isDateInToday($0.loggedAt)
        }) else { throw Failure.ineligibleCandidate }

        let priorLog = returning.flatMap { ExerciseSessionLog.resolve(for: $0, among: destinationLogs, on: .now) }
        let priorNumbers = Set((priorLog?.decodedSetLogs ?? []).map(\.setNumber).filter { $0 > 0 })
        if returning != nil, let priorLog {
            guard !priorLog.decodedSetLogs.isEmpty,
                  priorNumbers.count == priorLog.decodedSetLogs.count,
                  priorNumbers == Set(1...max(1, priorNumbers.count)) else { throw Failure.incompleteHistory }
        }

        let oldExercises = day.exercises
        let oldOrders = oldExercises.map { ($0, $0.order) }
        let oldStatus = exercise.completionStatusRaw
        let oldCompleted = exercise.isCompleted
        let oldReplacement = exercise.replacementName
        let oldPreference = exercise.preferredReplacementName
        let sourceKey = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        // Choosing a previous exercise as the future preference must not leave A→B→A.
        let preferenceKeys: Set<String> = returning == nil ? [sourceKey] : [sourceKey, candidateKey]
        let oldPreferences = preferFuture ? programs.flatMap(\.days).flatMap(\.exercises)
            .filter { preferenceKeys.contains(ExerciseWeightEntry.canonicalLookupKey($0.exerciseName)) }
            .map { ($0, $0.preferredReplacementName) } : []
        let oldDayCompleted = day.isCompleted
        let oldDayClosed = day.isSessionClosed
        let oldDayEnded = day.sessionEndedAt
        let oldReturning = returning.map { ($0.sets, $0.completionStatusRaw, $0.isCompleted, $0.replacementName) }
        let oldIncoming = returning.map { prior in
            day.exercises.filter { !$0.replacementName.isEmpty && identity($0.replacementName) == identity(prior.exerciseName) }
                .map { ($0, $0.replacementName) }
        } ?? []
        let replacement = returning ?? WorkoutExercise(
            order: 0, exerciseName: candidate.canonicalName,
            sets: exercise.sets - completedCount, reps: exercise.reps,
            tempo: exercise.tempo, restSeconds: exercise.restSeconds,
            notes: "Replacement for \(exercise.exerciseName). Choose a load for this exercise; stop if it causes pain.",
            muscleTarget: candidate.primaryAreas.joined(separator: ", "), targetRIR: exercise.targetRIR
        )
        // Normalize slot order rather than adding one to a possibly noncontiguous order.
        var ordered = day.sortedExercises
        guard let index = ordered.firstIndex(where: { $0 === exercise }) else { throw Failure.unavailableSession }
        ordered.removeAll { $0 === replacement }
        let insertionIndex = ordered.firstIndex(where: { $0 === exercise }) ?? index
        ordered.insert(replacement, at: insertionIndex + 1)
        let autosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = autosave }
        if returning == nil { modelContext.insert(replacement) }
        else {
            // Remove the reused node from its old position before appending it as active.
            // This keeps A→B→C→A→C a chain, not two competing predecessors of C.
            for (incoming, _) in oldIncoming { incoming.replacementName = replacement.replacementName }
            replacement.sets = priorNumbers.count + exercise.sets - completedCount
            replacement.completionStatusRaw = ""
            replacement.isCompleted = false
            replacement.replacementName = ""
        }
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
            for (incoming, name) in oldIncoming { incoming.replacementName = name }
            if let returning, let oldReturning {
                returning.sets = oldReturning.0
                returning.completionStatusRaw = oldReturning.1
                returning.isCompleted = oldReturning.2
                returning.replacementName = oldReturning.3
            }
            for (item, preference) in oldPreferences { item.preferredReplacementName = preference }
            day.isCompleted = oldDayCompleted
            day.isSessionClosed = oldDayClosed
            day.sessionEndedAt = oldDayEnded
            throw error
        }
        return replacement
    }
}
