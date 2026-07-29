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
