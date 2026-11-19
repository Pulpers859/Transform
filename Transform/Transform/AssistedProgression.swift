import Foundation

/// Progression for pull-ups, chin-ups and dips done on an assistance machine, where the number
/// on the machine is HELP: more is easier, so progress means the number going DOWN.
///
/// Why this exists (owner, 2026-11-19): with no way to record assistance, the owner logged
/// these sets as bodyweight. The bodyweight engine then read a set he finished comfortably on
/// the machine as bodyweight work that was going well, and told him to strap on load.
/// Assistance now has its own field (`SetLogEntry.assistLbs`), and this type grades it the way
/// `WorkoutProgressionEngine` grades load, with every direction reversed.
///
/// Deliberately NOT a negative weight. Code across the app reads a set's weight as never below
/// zero: the working-set analysis drops negatives as junk, and the bodyweight check treats
/// anything up to 1 lb (negatives included) as bodyweight. Each would have misread assistance
/// silently.
///
/// The machine's step size is not known, so no cue names a specific next setting; it says
/// "one setting lighter / heavier than X lb". The decisions and both of those sentences are
/// pinned by AssistedProgressionTests; the card, logger and sheet wiring is UI and is not.
enum AssistedProgression {
    /// The sets the weight summary may be built from: those without assistance. See
    /// `ExercisePerformanceLog.summarySetLogs` for why assisted sets are kept out.
    static func summarySets(_ sets: [SetLogEntry]) -> [SetLogEntry] {
        sets.filter { $0.assistLbs == nil }
    }

    /// Same tolerance the working-set analysis uses to call two loads "the same weight".
    static let sameSettingToleranceLbs = 0.5

    /// Movements offered the Assisted switch: the pull-up, chin-up and dip family, the ones
    /// assistance machines exist for. Name-based like `WorkoutProgressionEngine`'s
    /// bodyweight check, because equipment metadata is not available on every path.
    static func supportsAssistance(_ exerciseName: String) -> Bool {
        let lowered = exerciseName.lowercased()
        let markers = ["pull-up", "pull up", "pullup", "chin-up", "chin up", "chinup", "dip"]
        return markers.contains { lowered.contains($0) }
    }

    enum Verdict: Equatable {
        /// Every working set reached the top of the range (or most did): use less help.
        case lessAssistance
        /// Inside the range: build reps at this setting.
        case buildReps
        /// Some set fell under the range: keep this setting and build reps.
        case holdAssistance
        /// Under the range at this setting in two sessions running: use more help.
        case moreAssistance
    }

    struct Decision: Equatable {
        let verdict: Verdict
        /// The working setting (`workingSets`).
        let assistLbs: Double
        let workingSetCount: Int
        let ceilingSetCount: Int
        let belowFloorSetCount: Int
        let minimumReps: Int
        let belowFloorStreak: Int
    }

    /// The assisted working sets of one session: sets with assistance and at least one rep, at
    /// the setting used for the MOST sets; a tie goes to the least help (the harder setting).
    /// Nil when the session has no assisted set.
    ///
    /// Not simply "least help used": one hard attempt at a lighter setting (10 lb help for 2
    /// reps among three sets of 10 at 40 lb) then became the graded setting, the next
    /// session's prefill and the stall-streak anchor (independent audit, 2026-11-19). The load
    /// engine screens such sets out with `WorkingSetAnalysis`; this is the assisted equivalent.
    static func workingSets(_ sets: [SetLogEntry]) -> (assist: Double, sets: [SetLogEntry])? {
        let assisted = sets.filter { ($0.assistLbs ?? -1) >= 0 && $0.repsCompleted > 0 }
        let settings = assisted.compactMap(\.assistLbs)
        guard !settings.isEmpty else { return nil }
        func atSetting(_ help: Double) -> [SetLogEntry] {
            assisted.filter { abs(($0.assistLbs ?? help) - help) <= sameSettingToleranceLbs }
        }
        let chosen = settings.min { lhs, rhs in
            let lhsCount = atSetting(lhs).count
            let rhsCount = atSetting(rhs).count
            return lhsCount != rhsCount ? lhsCount > rhsCount : lhs < rhs
        } ?? settings[0]
        return (chosen, atSetting(chosen))
    }

    /// The setting to prefill for the next assisted set: the working setting of the most
    /// recent session that used assistance. Nil when none did.
    static func suggestedAssist(from sets: [SetLogEntry]) -> Double? {
        workingSets(sets)?.assist
    }

    /// How many recent sessions (newest first, the graded one included) were assisted at this
    /// same setting and finished under the rep floor. Stops at the first session that breaks
    /// the pattern, exactly like `WorkoutProgressionEngine.belowFloorStreak`.
    static func belowFloorStreak(
        for canonicalExerciseKey: String,
        from snapshots: [WorkoutPerformanceLogSnapshot],
        assistLbs: Double,
        repFloor: Int,
        lookback: Int = 4
    ) -> Int {
        let recent = snapshots
            .filter { $0.canonicalExerciseKey == canonicalExerciseKey }
            .sorted { $0.loggedAt > $1.loggedAt }
            .prefix(max(1, lookback))
        var streak = 0
        for snapshot in recent {
            guard let session = workingSets(snapshot.setLogs),
                  abs(session.assist - assistLbs) <= sameSettingToleranceLbs,
                  let lowest = session.sets.map(\.repsCompleted).min(), lowest < repFloor
            else { break }
            streak += 1
        }
        return streak
    }

    /// Grades one session's assisted sets against the rep range. Same thresholds as
    /// `WorkoutProgressionEngine.evaluate`: every working set at the ceiling, or at least
    /// two-thirds of them, earns the progression step; any set under the floor holds; two
    /// such sessions in a row at the same setting reverse it.
    static func evaluate(sets: [SetLogEntry], repRange: RepRange, belowFloorStreak: Int = 0) -> Decision? {
        guard let session = workingSets(sets) else { return nil }
        let reps = session.sets.map(\.repsCompleted)
        guard let minimum = reps.min() else { return nil }
        let ceiling = reps.filter { $0 >= repRange.high }.count
        let belowFloor = reps.filter { $0 < repRange.low }.count
        let majority = max(1, Int(ceil(Double(reps.count) * 0.67)))

        let verdict: Verdict
        if minimum >= repRange.high {
            verdict = .lessAssistance
        } else if minimum < repRange.low {
            verdict = belowFloorStreak >= 2 ? .moreAssistance : .holdAssistance
        } else {
            verdict = ceiling >= majority ? .lessAssistance : .buildReps
        }
        return Decision(
            verdict: verdict,
            assistLbs: session.assist,
            workingSetCount: reps.count,
            ceilingSetCount: ceiling,
            belowFloorSetCount: belowFloor,
            minimumReps: minimum,
            belowFloorStreak: belowFloorStreak
        )
    }

    /// The card's sentence for a decision.
    static func cue(for decision: Decision, repRange: RepRange) -> String {
        let help = "\(formatWeight(decision.assistLbs)) lb assistance"
        switch decision.verdict {
        case .lessAssistance:
            let earned = decision.ceilingSetCount == decision.workingSetCount
                ? "every assisted set hit \(repRange.high)"
                : "\(decision.ceilingSetCount) of \(setsLabel(decision.workingSetCount)) hit \(repRange.high)"
            return decision.assistLbs > 0
                ? "Less help next time: \(earned) with \(help). Go one setting lighter than \(formatWeight(decision.assistLbs)) lb."
                : "\(earned.prefix(1).uppercased() + earned.dropFirst()) with no assistance. Try it without the machine next time."
        case .buildReps:
            return "On track with \(help): build all sets to \(repRange.high) reps (lowest was \(decision.minimumReps))."
        case .holdAssistance:
            return "Keep \(help): \(decision.belowFloorSetCount) of \(setsLabel(decision.workingSetCount)) finished under \(repRange.low). Get every set to \(repRange.low) first."
        case .moreAssistance:
            return "Under \(repRange.low) reps \(decision.belowFloorStreak) sessions in a row with \(help). Go one setting heavier (more help) than \(formatWeight(decision.assistLbs)) lb."
        }
    }
}
