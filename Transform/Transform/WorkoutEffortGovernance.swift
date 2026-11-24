import Foundation

struct WorkoutSessionFeedbackSnapshot: Equatable {
    let effort: Int
    let stimulus: Int
    let jointPain: Int
    let performanceRawValue: String
}

enum WorkoutEffortGovernance {
    enum Signal: Equatable {
        case protectRecovery
        case progressionHeadroom
        case neutral
    }

    static func signal(
        from feedback: [WorkoutSessionFeedbackSnapshot],
        lookback: Int = 3
    ) -> Signal {
        let recent = Array(feedback.suffix(max(1, lookback)))
        guard recent.count >= 2 else { return .neutral }

        let recoveryFlags = recent.filter { snapshot in
            snapshot.jointPain >= 3
                || snapshot.performanceRawValue.caseInsensitiveCompare("Worse") == .orderedSame
                || snapshot.effort >= 5
        }.count
        if recoveryFlags >= 2 {
            return .protectRecovery
        }

        let headroomFlags = recent.filter { snapshot in
            snapshot.effort <= 3
                && snapshot.jointPain <= 1
                && snapshot.performanceRawValue.caseInsensitiveCompare("Worse") != .orderedSame
        }.count
        if headroomFlags >= 2 {
            return .progressionHeadroom
        }

        return .neutral
    }

    /// The AI's governance sentence for a week of ratings. RED-TEST STUB (round 3): the old
    /// reading, `guidance(for: signal(from:))`.
    static func guidance(forWeek feedback: [WorkoutSessionFeedbackSnapshot]) -> String {
        guidance(for: signal(from: feedback))
    }

    static func guidance(for signal: Signal) -> String {
        switch signal {
        case .protectRecovery:
            return "Governance signal: protect recovery. Hold load progression this week; if pain or performance remains poor, reduce the lowest-priority isolation set and keep compounds inside the prescribed effort cap. This is a conservative session-level signal, not a diagnosis."
        case .progressionHeadroom:
            return "Governance signal: progression headroom. Keep the double-progression ladder: add reps before load, and add load only when all working sets meet the rep ceiling."
        case .neutral:
            return "Governance signal: neutral. Use actual per-set performance and the prescribed rep range as the primary progression evidence."
        }
    }

    // MARK: - Session ratings and weight suggestions (council review 2026-11-23)
    //
    // The session card promised "Next week holds load steady" after a painful or tough week, but
    // nothing behind it did: the weight suggestion read only the exercise's own logged reps in
    // reserve. Exercise-evidence consult (2026-11-23), option (a): a week whose ratings say
    // "protect recovery" holds the NEXT week's weight suggestions, on every exercise (a rating
    // names no body part), for that one week only. Evidence is weak (expert consensus that lifters
    // may back off when fatigued; nothing tests holding on ratings); holding costs at most one
    // weight step, progressing through joint pain risks aggravating it. The repeated-miss rule
    // still wins: a load twice missed comes down. Pinned by SessionRatingHoldTests.

    /// The ratings signal that governs `targetWeek`'s weight suggestions: the previous week's
    /// rated sessions only, in day order (the same sessions the card line describes).
    ///
    /// Protect = 2 of the last 3 with joint pain >= 3 or a "Worse" performance. Effort is NOT a
    /// trigger here (consult 2026-11-24, pick c): effort 5 is what week 3 asks for, and the
    /// reps-based check already holds an exercise trained harder than prescribed. Effort still
    /// reaches the AI through `signal(from:)` / `guidance(for:)`. Headroom is reported as
    /// `signal(from:)` reports it; it changes no weight.
    static func signal(governingWeek targetWeek: Int,
                       rated: [(week: Int, dayNumber: Int, feedback: WorkoutSessionFeedbackSnapshot)]) -> Signal {
        let week = rated.filter { $0.week == targetWeek - 1 }.sorted { $0.dayNumber < $1.dayNumber }.map(\.feedback)
        let recent = week.suffix(3)
        let flags = recent.filter {
            $0.jointPain >= 3 || $0.performanceRawValue.caseInsensitiveCompare("Worse") == .orderedSame
        }.count
        if recent.count >= 2 && flags >= 2 { return .protectRecovery }
        return signal(from: week) == .progressionHeadroom ? .progressionHeadroom : .neutral
    }

    /// Either source protecting means protect. Neutral and headroom ratings change nothing: the
    /// app already adds reps before weight, so headroom needs no extra rule.
    static func mergedEffortSignal(_ repsSignal: WorkoutExerciseEffortSignal, sessionRatings: Signal) -> WorkoutExerciseEffortSignal {
        sessionRatings == .protectRecovery ? .protectRecovery : repsSignal
    }

    /// Why a weight is being held, for the card's hold line. The logged reps win the wording when
    /// both apply, because they are about this exercise.
    static func holdReason(repsSignal: WorkoutExerciseEffortSignal, sessionRatings: Signal) -> String {
        if repsSignal != .protectRecovery && sessionRatings == .protectRecovery {
            return "your recent session ratings flagged pain or a tough week, so recover before adding"
        }
        return "recent sets were close to failure, so recover before adding"
    }

    /// The card line, only where the NEXT week is an ordinary training week (devil's advocate
    /// 2026-11-24): the week before the deload would promise "weights hold steady" beside a
    /// deload card saying go lighter, and the block's last week is followed by a new program
    /// whose week 1 reads only its own ratings.
    static func cardLine(for signal: Signal, ratedWeek: Int, blockWeeks: Int) -> String? {
        guard ratedWeek + 1 < blockWeeks, !MesocyclePhase.isDeloadWeek(ratedWeek + 1) else { return nil }
        return cardLine(for: signal)
    }

    /// A rep-range or set-count change can translate the load. In a protected week it may come
    /// down but not go up (consult 2026-11-24, RATE-001 follow-up).
    static func cappedTranslatedLoad(_ load: Double, lastWorkingWeight: Double, sessionRatings: Signal) -> Double {
        sessionRatings == .protectRecovery ? min(load, lastWorkingWeight) : load
    }

    /// The line under a rated session describing what the ratings do to next week.
    static func cardLine(for signal: Signal) -> String? {
        switch signal {
        case .protectRecovery:
            return "Next week, your weight suggestions hold steady so you can recover."
        case .progressionHeadroom:
            return "Good week — keep building reps at your current weights, then add weight once every set reaches the top of its range."
        case .neutral:
            return nil
        }
    }
}
