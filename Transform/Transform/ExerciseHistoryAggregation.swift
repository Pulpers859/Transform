import Foundation
import SwiftData

/// What past sessions say about which movements to avoid, which to push down the list, and how
/// long next week's sessions should be.
///
/// WHY THIS IS ITS OWN TYPE
/// -----------------------
/// This lived as a method on `WorkoutView`, a SwiftUI file the headless generator harness cannot
/// compile, so the rules that decide whether a movement is banned outright, deprioritised, or
/// counted against the session clock had no executed coverage at all — and they are keyed on
/// `ExerciseWeightEntry.canonicalLookupKey`, the naming path that silently erased logged weights
/// once before. Moving the aggregation here is what lets those rules be pinned by tests.
///
/// TWO BUGS THIS HAS NOW OUTLIVED
/// ------------------------------
/// The original walked EVERY program with no notion of when anything happened, so two skips in
/// January still counted in December and the evidence only ever grew. That became a real defect
/// once `timeSkipExercises.count` started shortening the session clock: the trim had no release,
/// and a lifter who fixed his schedule and finished every session for six months was still handed
/// a permanently shortened week.
///
/// The first fix — expire circumstantial skips after 84 CALENDAR days — released the ratchet but
/// bought a second defect with it. The bar is two skips inside one window, so a lifter training
/// less often than roughly every 84 days could never reach it: each skip aged out before the next
/// one landed, and a genuinely recurring problem stayed invisible. A rule that quietly stops
/// working for anyone training twice a month is not a rule about recency, it is a rule about
/// frequency, and frequency was never the question being asked.
///
/// So the window counts SESSIONS, not days. "Recently" now means "in the last
/// `recentSessionWindow` times you actually trained", which is the same span for someone lifting
/// five times a week as for someone lifting twice a month. At the owner's roughly five sessions a
/// week, 60 sessions is about the same twelve weeks the calendar rule gave him — so this fixes
/// the sporadic case without disturbing the case that already worked.
///
/// The `@MainActor` is load-bearing rather than decorative. The Xcode app target sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so it is redundant there — but the SPM harness
/// target that compiles this file for `swift test` sets no such default, and without it the
/// MainActor-isolated tests could not call this synchronously. `SessionLifecycle.swift` is the
/// precedent for that exact combination (@MainActor + SwiftData models inside the harness);
/// `SessionLogResolution.swift`, cited when this file was created, is the precedent for moving a
/// view method into the harness for testability but is NOT @MainActor — it takes plain values.
@MainActor
enum ExerciseHistoryAggregator {

    /// How many of the lifter's most recent TRAINED sessions a circumstantial skip still counts
    /// in. Sixty is about twelve weeks at five sessions a week — the span the previous calendar
    /// rule gave the owner — but it now means the same thing for someone training far less often,
    /// which is the whole point of counting sessions instead of days.
    static let recentSessionWindow = 60

    /// A backstop the session window cannot provide on its own. Someone returning after a long
    /// layoff still has their last sixty sessions on record, but a movement abandoned for time
    /// before a two-year gap says nothing about the gym, the schedule, or the body they have now.
    /// This is the only place calendar age still decides anything for a circumstantial skip.
    static let staleSessionCutoffDays = 730

    /// A skip only counts once it has happened twice: once is a bad day, twice is a pattern.
    static let recurrenceBar = 2

    /// One trained session, with the date used to order it.
    ///
    /// `programCreatedDate` and `dayNumber` are carried purely as tiebreakers: Swift's `sorted`
    /// is not guaranteed stable, and many days legitimately share a date — every day of a program
    /// trained before the session clock existed inherits that program's creation date. Without a
    /// total order, which sessions fall inside the window could vary between runs of the same
    /// data, which is exactly the kind of quiet non-determinism this repo has been bitten by.
    private struct TrainedSession {
        let date: Date
        let programCreatedDate: Date
        let dayNumber: Int
        let day: WorkoutDay
    }

    /// - Parameter now: injected so the backstop is testable without touching the clock,
    ///   following the parameter-seam precedent `RecoveryModulationTests` sets for stored state.
    static func context(
        from programs: [WorkoutProgram],
        now: Date = Date()
    ) -> ClaudeService.ExerciseHistoryContext {
        var painExercises = Set<String>()
        var equipmentSkipExercises = Set<String>()
        var priorMesocycleExercises = Set<String>()

        var painCounts: [String: Int] = [:]
        var equipmentCounts: [String: Int] = [:]
        var timeCounts: [String: Int] = [:]

        var trainedSessions: [TrainedSession] = []

        // Pass one: everything that ignores the window — pain, and the prior-mesocycle memory
        // that exists to vary work between blocks and is supposed to be historical.
        for program in programs {
            let isArchived = program.isArchived
            for day in program.sortedDays where !day.isRestDay {
                var showsEvidenceOfTraining = !day.sessionCalendarDates.isEmpty

                for exercise in day.sortedExercises {
                    let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                    guard !key.isEmpty else { continue }

                    if isArchived {
                        priorMesocycleExercises.insert(key)
                    }

                    guard let status = exercise.completionStatus else { continue }
                    showsEvidenceOfTraining = true
                    guard status != .completed else { continue }

                    if status == .skippedPain {
                        // NOT windowed, deliberately. Pain is the one signal here about the
                        // lifter's body rather than his circumstances, and a movement that hurt
                        // him is not something to quietly reintroduce because enough sessions
                        // have gone by. Changing that is the owner's call, not a side effect.
                        painCounts[key, default: 0] += 1
                    }
                }

                // Only days the lifter actually trained can occupy a slot in the window. A day
                // scheduled for next week has no stamps and no dispositions, and letting it count
                // would let an untrained future push real history out of view.
                guard showsEvidenceOfTraining else { continue }

                // A day that was trained carries its own session stamps. A day from before the
                // session clock existed carries none, so it inherits its program's creation date
                // — always present, and enough to order a whole old block together.
                trainedSessions.append(
                    TrainedSession(
                        date: day.sessionCalendarDates.max() ?? program.createdDate,
                        programCreatedDate: program.createdDate,
                        dayNumber: day.dayNumber,
                        day: day
                    )
                )
            }
        }

        let staleCutoff = Calendar.current.date(
            byAdding: .day,
            value: -staleSessionCutoffDays,
            to: now
        ) ?? .distantPast

        let recentSessions = trainedSessions
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                if lhs.programCreatedDate != rhs.programCreatedDate {
                    return lhs.programCreatedDate > rhs.programCreatedDate
                }
                return lhs.dayNumber > rhs.dayNumber
            }
            .prefix(recentSessionWindow)
            .filter { $0.date >= staleCutoff }

        // Pass two: the circumstantial skips, which only count inside the window.
        for session in recentSessions {
            for exercise in session.day.sortedExercises {
                let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                guard !key.isEmpty, let status = exercise.completionStatus else { continue }
                switch status {
                case .skippedEquipment:
                    equipmentCounts[key, default: 0] += 1
                case .skippedTime:
                    timeCounts[key, default: 0] += 1
                default:
                    break
                }
            }
        }

        // One pain report is enough; it is not a recurrence question.
        for (key, count) in painCounts where count >= 1 {
            painExercises.insert(key)
        }
        for (key, count) in equipmentCounts where count >= recurrenceBar {
            equipmentSkipExercises.insert(key)
        }
        var timeSkipExercises = Set<String>()
        for (key, count) in timeCounts where count >= recurrenceBar {
            timeSkipExercises.insert(key)
        }

        let activeCount = programs.filter { !$0.isArchived }.count
        let archivedCount = programs.filter { $0.isArchived }.count
        let mesocycleIndex = activeCount > 0 ? archivedCount : max(0, archivedCount - 1)

        return ClaudeService.ExerciseHistoryContext(
            painExercises: painExercises,
            equipmentSkipExercises: equipmentSkipExercises,
            timeSkipExercises: timeSkipExercises,
            priorMesocycleExercises: priorMesocycleExercises,
            mesocycleIndex: mesocycleIndex
        )
    }
}
