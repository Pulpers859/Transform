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
/// THE BUG THAT PROMPTED THE MOVE
/// -----------------------------
/// The old version walked EVERY program — active and archived — with no notion of when anything
/// happened. Two skips in January still counted in December, and there was no way to stop
/// counting them: the evidence only ever grew. That was already questionable for equipment, and
/// it became a real defect once `timeSkipExercises.count` started shortening the session clock,
/// because the trim then had no release. A lifter who fixed his schedule and finished every
/// session for six months would still be handed a permanently shortened week.
/// The `@MainActor` is load-bearing rather than decorative. The Xcode app target sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so it is redundant there — but the SPM harness
/// target that compiles this file for `swift test` sets no such default, and without it the
/// MainActor-isolated tests could not call this synchronously. `SessionLifecycle.swift` is the
/// precedent for that exact combination (@MainActor + SwiftData models inside the harness);
/// `SessionLogResolution.swift`, cited when this file was created, is the precedent for moving a
/// view method into the harness for testability but is NOT @MainActor — it takes plain values.
@MainActor
enum ExerciseHistoryAggregator {

    /// How far back a CIRCUMSTANTIAL skip still counts.
    ///
    /// 84 days is three full mesocycles at the program's four-week default, so evidence survives
    /// the current block and the two before it and then releases. Long enough that one good month
    /// cannot erase a real pattern; short enough that a pattern the lifter has actually fixed
    /// stops shaping his programming.
    ///
    /// KNOWN COST, stated rather than discovered later. Because the bar is two skips WITHIN one
    /// window, a lifter who trains less often than roughly every 84 days can never reach it: each
    /// skip ages out before the next one lands, so a genuinely recurring problem stays invisible
    /// to both `deprioritizedExercises` and the session-clock trim. That is the accepted price of
    /// having a release at all — the alternative it replaced had no release, and permanently
    /// shortened the week off two skips recorded years earlier. If it ever matters, the fix is to
    /// count back over the last N SESSIONS rather than the last N days, which does not depend on
    /// how often those sessions happen; that is a deliberate design change, not something to
    /// slide in here.
    static let circumstantialSkipWindowDays = 84

    /// A skip only counts once it has happened twice: once is a bad day, twice is a pattern.
    static let recurrenceBar = 2

    /// - Parameter now: injected so the window is testable without touching the clock, following
    ///   the parameter-seam precedent `RecoveryModulationTests` sets for stored state.
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

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -circumstantialSkipWindowDays,
            to: now
        ) ?? .distantPast

        for program in programs {
            let isArchived = program.isArchived
            for day in program.sortedDays where !day.isRestDay {
                // A day that was trained carries its own session stamps. A day from before the
                // session clock existed carries none, so it inherits its program's creation date
                // — always present, and enough to age a whole old mesocycle out together rather
                // than letting undated history count forever.
                let dayDate = day.sessionCalendarDates.max() ?? program.createdDate
                let isWithinWindow = dayDate >= cutoff

                for exercise in day.sortedExercises {
                    let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                    guard !key.isEmpty else { continue }

                    if isArchived {
                        priorMesocycleExercises.insert(key)
                    }

                    guard let status = exercise.completionStatus, status != .completed else { continue }
                    switch status {
                    case .skippedPain:
                        // NOT aged, deliberately. Pain is the one signal here that is about the
                        // lifter's body rather than his circumstances, and a movement that hurt
                        // him is not something to quietly reintroduce because a timer expired.
                        // Changing that is the owner's call, not a side effect of this fix.
                        painCounts[key, default: 0] += 1
                    case .skippedEquipment:
                        guard isWithinWindow else { continue }
                        equipmentCounts[key, default: 0] += 1
                    case .skippedTime:
                        guard isWithinWindow else { continue }
                        timeCounts[key, default: 0] += 1
                    default:
                        break
                    }
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
