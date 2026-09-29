import Foundation
import SwiftData

/// Single owner of two questions that used to be answered ad hoc in five different
/// places: "is this training day finished?" and "when did the session actually end?".
///
/// Five call sites can change an exercise's disposition — the completion checkmark, the
/// "finish as modified" prompt, the Skip menu, the Clear-status button, and the day-level
/// toggle in the week list. Three of them recomputed `day.isCompleted`, two did not, and
/// none of them closed the session clock. Two user-visible bugs fell out of that:
///
/// 1. Skipping the last outstanding exercise ("ran out of time") set the exercise's flags
///    but never re-derived the day, so the day stayed unfinished forever: no feedback
///    prompt, no end stamp — the exact case this type was written for.
/// 2. "Finished" in the feedback sheet was the timestamp of the last *logged set*, so
///    every minute after the final rep — the last rest, the cooldown, the walk to the
///    checkmark — was silently cut off the recorded session length.
///
/// Every disposition change now funnels through `syncDayCompletion`. It is the only place
/// allowed to flip `day.isCompleted`, and `markSessionEnded` is the only place allowed to
/// close the clock.
@MainActor
enum SessionLifecycle {

    enum ResetFailure: LocalizedError {
        case unavailable, pendingChanges, ambiguousHistory
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Only a training day in the current program can be reset."
            case .pendingChanges: return "Finish saving your current edits, then try again."
            case .ambiguousHistory: return "Some saved records cannot be safely assigned to this day. Nothing was reset."
            }
        }
    }

    static func canCancelAccidentalStart(_ day: WorkoutDay, logs: [ExercisePerformanceLog]) -> Bool {
        guard day.feedbackSubmittedAt == nil, day.sessionEffort == 0, day.stimulusQuality == 0,
              day.jointPain == 0, day.performanceRatingRaw.isEmpty, day.sessionFeedbackNotes.isEmpty,
              day.exercises.allSatisfy({ !$0.isCompleted && $0.completionStatusRaw.isEmpty && $0.painReviewRaw.isEmpty })
        else { return false }
        return !logs.contains { $0.workoutDayNumber == day.dayNumber && $0.loggedAt >= (day.program?.createdDate ?? .distantPast) }
    }

    /// Destructive, explicit owner action. Never use the display resolver's latest-log fallback
    /// to select records for deletion. Tests in WorkoutDayResetTests pin the ownership boundary.
    static func reset(_ day: WorkoutDay, in context: ModelContext,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard let program = day.program, !program.isArchived, !day.isRestDay else { throw ResetFailure.unavailable }
        guard !context.hasChanges else { throw ResetFailure.pendingChanges }
        let programs = try context.fetch(FetchDescriptor<WorkoutProgram>())
        guard !programs.contains(where: { $0 !== program && $0.createdDate >= program.createdDate }) else {
            throw ResetFailure.ambiguousHistory
        }
        let logs = try context.fetch(FetchDescriptor<ExercisePerformanceLog>())
        let keys = Set(day.exercises.map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) })
        let recent = logs.filter { $0.loggedAt >= program.createdDate }
        guard !recent.contains(where: { $0.workoutDayNumber == 0 && keys.contains($0.canonicalExerciseKey) }),
              program.days.filter({ $0.dayNumber == day.dayNumber }).count == 1 else {
            throw ResetFailure.ambiguousHistory
        }
        let removed = recent.filter { $0.workoutDayNumber == day.dayNumber }
        guard removed.allSatisfy({ keys.contains($0.canonicalExerciseKey) }) else { throw ResetFailure.ambiguousHistory }
        let otherDays = programs.filter { $0 !== program }.flatMap(\.days).filter { $0.dayNumber == day.dayNumber }
        guard !removed.contains(where: { log in
            otherDays.contains { other in
                // A historical log's date is editable independently of its day's clock.
                // Without a stored program ID, identical old day/key ownership is ambiguous.
                other.exercises.contains { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) == log.canonicalExerciseKey }
            }
        }) else { throw ResetFailure.ambiguousHistory }
        let removedIDs = Set(removed.map(\.persistentModelID))
        let remaining = logs.filter { !removedIDs.contains($0.persistentModelID) }
        let summaries = try context.fetch(FetchDescriptor<ExerciseWeightEntry>())
        for summary in summaries where removed.contains(where: { $0.canonicalExerciseKey == summary.canonicalExerciseKey }) {
            // A correction can advance a log's timestamp while leaving an earlier personal
            // best in the summary. Without provenance, do not guess which session owns it.
            if let bestDate = summary.bestLoggedAt, bestDate >= program.createdDate,
               !logs.contains(where: { $0.canonicalExerciseKey == summary.canonicalExerciseKey && $0.loggedAt == bestDate }) {
                throw ResetFailure.ambiguousHistory
            }
            if summary.hasBestRecord && summary.bestLoggedAt == nil { throw ResetFailure.ambiguousHistory }
        }

        // Restore sets performed on earlier segments of a replacement chain to its active lift.
        var restoredSets: [(WorkoutExercise, Int)] = []
        var accountedExercises = Set<PersistentIdentifier>()
        for active in day.activeExercises {
            var total = active.sets
            var cursor = active
            var visited = Set([active.persistentModelID])
            while true {
                let predecessors = day.exercises.filter {
                    !$0.replacementName.isEmpty && ExerciseReplacement.identity($0.replacementName)
                        == ExerciseReplacement.identity(cursor.exerciseName)
                }
                guard predecessors.count <= 1 else { throw ResetFailure.ambiguousHistory }
                guard let prior = predecessors.first else { break }
                guard visited.insert(prior.persistentModelID).inserted else { throw ResetFailure.ambiguousHistory }
                let priorLogs = removed.filter { $0.canonicalExerciseKey == ExerciseWeightEntry.canonicalLookupKey(prior.exerciseName) }
                guard priorLogs.count <= 1 else { throw ResetFailure.ambiguousHistory }
                if let log = priorLogs.first {
                    let numbers = Set(log.decodedSetLogs.map(\.setNumber))
                    guard !numbers.isEmpty, numbers.count == log.decodedSetLogs.count,
                          numbers == Set(1...numbers.count), numbers.count <= prior.sets else { throw ResetFailure.ambiguousHistory }
                    total += numbers.count
                }
                cursor = prior
            }
            restoredSets.append((active, total))
            guard accountedExercises.isDisjoint(with: visited) else { throw ResetFailure.ambiguousHistory }
            accountedExercises.formUnion(visited)
        }
        guard accountedExercises.count == day.exercises.count else { throw ResetFailure.ambiguousHistory }

        let daySnapshot = (day.isCompleted, day.isSessionClosed, day.sessionStartedAt, day.sessionEndedAt,
                           day.feedbackSubmittedAt, day.sessionEffort, day.stimulusQuality, day.jointPain,
                           day.performanceRatingRaw, day.sessionFeedbackNotes)
        let exerciseSnapshots = day.exercises.map { ($0, $0.sets, $0.isCompleted, $0.completionStatusRaw, $0.painReviewRaw) }
        let summarySnapshots = summaries.map { ($0, $0.loggedAt, $0.weightLbs, $0.repsCompleted, $0.notes,
                                               $0.bestLoggedAt, $0.bestWeightLbs, $0.bestRepsCompleted, $0.bestNotes) }
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            for summary in summaries {
                let deletedDates = Set(removed.filter { $0.canonicalExerciseKey == summary.canonicalExerciseKey }.map(\.loggedAt))
                guard !deletedDates.isEmpty else { continue }
                var records = remaining.filter { $0.canonicalExerciseKey == summary.canonicalExerciseKey }.map { log in
                    let top = WorkingSetAnalysis.summaryTop(from: log.decodedSetLogs)
                    return ResetRecord(date: log.loggedAt, weight: top?.weightLbs ?? log.weightLbs,
                                       reps: top?.reps ?? log.repsCompleted, notes: log.notes)
                }
                // Summaries may carry legacy history with no performance-log row. Preserve it.
                if !deletedDates.contains(summary.loggedAt) {
                    records.append(ResetRecord(date: summary.loggedAt, weight: summary.weightLbs, reps: summary.repsCompleted, notes: summary.notes))
                }
                if let date = summary.bestLoggedAt, !deletedDates.contains(date) {
                    records.append(ResetRecord(date: date, weight: summary.bestWeightLbs, reps: summary.bestRepsCompleted, notes: summary.bestNotes))
                }
                guard let latest = records.max(by: { $0.date < $1.date }) else {
                    context.delete(summary)
                    continue
                }
                let best = records.max {
                    if abs($0.weight - $1.weight) > 0.001 { return $0.weight < $1.weight }
                    if ($0.reps ?? 0) != ($1.reps ?? 0) { return ($0.reps ?? 0) < ($1.reps ?? 0) }
                    return $0.date < $1.date
                }!
                if deletedDates.contains(summary.loggedAt) {
                    summary.loggedAt = latest.date
                    summary.weightLbs = latest.weight
                    summary.repsCompleted = latest.reps
                    summary.notes = latest.notes
                }
                if summary.bestLoggedAt.map(deletedDates.contains) ?? false {
                    summary.bestLoggedAt = best.date
                    summary.bestWeightLbs = best.weight
                    summary.bestRepsCompleted = best.reps
                    summary.bestNotes = best.notes
                }
            }
            for log in removed { context.delete(log) }
            for (exercise, sets) in restoredSets { exercise.sets = sets }
            for exercise in day.exercises {
                exercise.isCompleted = false
                exercise.completionStatusRaw = ""
                exercise.painReviewRaw = ""
            }
            day.isCompleted = false
            day.isSessionClosed = false
            day.sessionStartedAt = nil
            day.sessionEndedAt = nil
            day.feedbackSubmittedAt = nil
            day.sessionEffort = 0
            day.stimulusQuality = 0
            day.jointPain = 0
            day.performanceRatingRaw = ""
            day.sessionFeedbackNotes = ""
            try save(context)
        } catch {
            context.rollback()
            // SwiftData rollback restores disk state but does not reliably refresh objects
            // already held by SwiftUI. Keep those references consistent as well.
            (day.isCompleted, day.isSessionClosed, day.sessionStartedAt, day.sessionEndedAt,
             day.feedbackSubmittedAt, day.sessionEffort, day.stimulusQuality, day.jointPain,
             day.performanceRatingRaw, day.sessionFeedbackNotes) = daySnapshot
            for (exercise, sets, completed, status, pain) in exerciseSnapshots {
                exercise.sets = sets
                exercise.isCompleted = completed
                exercise.completionStatusRaw = status
                exercise.painReviewRaw = pain
            }
            for (summary, date, weight, reps, notes, bestDate, bestWeight, bestReps, bestNotes) in summarySnapshots {
                summary.loggedAt = date
                summary.weightLbs = weight
                summary.repsCompleted = reps
                summary.notes = notes
                summary.bestLoggedAt = bestDate
                summary.bestWeightLbs = bestWeight
                summary.bestRepsCompleted = bestReps
                summary.bestNotes = bestNotes
            }
            throw error
        }
    }

    private struct ResetRecord {
        let date: Date
        let weight: Double
        let reps: Int?
        let notes: String
    }

    /// Warm-up lead: the athlete is already training (warming up) before the first rep is
    /// logged, so an *inferred* start is back-dated by this much to approximate real
    /// session length. Applies ONLY to an inferred start — a manual "Start session" tap
    /// records an exact time and is left untouched. The athlete can still nudge it in the
    /// feedback sheet.
    /// `nonisolated` so non-isolated contexts can read it — notably the feedback sheet's
    /// `init`, which needs the same lead to build its placeholder start.
    nonisolated static let inferredWarmupLeadMinutes = 10

    /// What `syncDayCompletion` actually changed, so the caller can decide whether to
    /// present the feedback sheet without re-deriving the state itself.
    enum Transition: Equatable {
        /// Every exercise is now resolved and the day just flipped to finished.
        case justFinished
        /// The day was finished and is now open again (a status was cleared).
        case reopened
        case unchanged
    }

    // MARK: - Day completion

    /// Re-derives `day.isCompleted` from its exercises and, on the moment it becomes
    /// true, closes the session clock. Safe to call after any disposition change; it is a
    /// no-op when nothing moved.
    @discardableResult
    static func syncDayCompletion(for day: WorkoutDay, now: Date = .now) -> Transition {
        let wasFinished = day.isCompleted
        let isFinished = day.allExercisesResolved
        guard wasFinished != isFinished else { return .unchanged }

        day.isCompleted = isFinished
        guard isFinished else {
            // Un-resolving an exercise means training resumed: let the clock track again.
            day.isSessionClosed = false
            return .reopened
        }

        markSessionEnded(for: day, now: now)
        return .justFinished
    }

    // MARK: - Session clock

    /// Stamps the real end of training and closes the clock.
    ///
    /// Idempotent: once closed, a later call cannot push the end forward, so re-opening
    /// feedback an hour after training does not silently add an hour to the session.
    /// Skipped once feedback is submitted, so an end time the athlete adjusted by hand in
    /// the sheet is never quietly overwritten.
    static func markSessionEnded(for day: WorkoutDay, now: Date = .now) {
        guard day.feedbackSubmittedAt == nil, !day.isSessionClosed else { return }
        // Keep the later of the two: a set stamped after this tap — a correction entered
        // with a hand-picked time — is still real work and must not be truncated away.
        if day.sessionEndedAt.map({ $0 < now }) ?? true {
            day.sessionEndedAt = now
        }
        day.isSessionClosed = true
    }

    /// Auto-tracks the session clock from logged work. The first set logged marks the
    /// start (minus the warm-up lead); each later set advances the end, so a session that
    /// is abandoned without a finish tap still carries a real duration.
    ///
    /// Only touches a live session — not one already closed or rated — and only for logs
    /// stamped today, so correcting an old session's set tomorrow cannot rewrite its clock.
    static func noteSetLogged(for exercise: WorkoutExercise, at date: Date) {
        guard let day = exercise.day,
              day.feedbackSubmittedAt == nil,
              !day.isSessionClosed,
              Calendar.current.isDateInToday(date) else { return }

        if day.sessionStartedAt == nil {
            day.sessionStartedAt = date.addingTimeInterval(-Double(inferredWarmupLeadMinutes) * 60)
        }
        if let end = day.sessionEndedAt {
            if date > end { day.sessionEndedAt = date }
        } else {
            day.sessionEndedAt = date
        }
    }
}
