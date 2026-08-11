import Foundation

/// One resolved answer to "what happened on this exercise?".
///
/// WHY THIS EXISTS
/// ---------------
/// The exercise card assembled itself from four independent sources on different time
/// windows — an all-time weight summary, the previous session's set logs, today's set logs,
/// and the exercise's own flags — and each visual element picked whichever one it happened to
/// need. Nothing reconciled them, so the card could and did contradict itself on screen:
///
/// * "Last 40 lb x 15" sat directly above "🏆 Best 50 lb · 14 reps" where the 50 lb was
///   logged TODAY, while a warning four lines below asked the lifter to confirm that same
///   50 lb was not a mis-log. The card crowned a personal best and questioned it at once.
/// * An exercise finished as Modified with zero sets logged wore the same green check as the
///   five beside it that were actually performed, because the check reads `isCompleted` and
///   nothing else.
/// * A set logged at 15 reps against a 10-14 prescription, at RIR 4 against a target of 2,
///   counted toward "2/2 complete" and toward progression with nothing flagged. There was an
///   elaborate cross-session load-anomaly detector but no check that the work done matched
///   the work prescribed.
///
/// Resolving all of it in one place makes those contradictions unrepresentable rather than
/// individually patched. Every element on the card reads from this type.
///
/// OBSERVABILITY ONLY
/// ------------------
/// `adherence` reports; it never re-prescribes. The deterministic plan owns dosage (INC-8),
/// and the progression banner owns load and rep advice. A flag here is something to show the
/// lifter, never an input that silently rewrites the programme.
struct ExerciseSessionSummary: Equatable {

    // MARK: - State

    /// What the exercise IS right now. Replaces reading `isCompleted` and `completionStatus`
    /// separately at each call site, which is how a zero-set Modified exercise ended up
    /// rendering identically to a completed one.
    enum State: Equatable {
        case notStarted
        case inProgress(logged: Int, planned: Int)
        /// Every prescribed set logged.
        case completedAsPlanned(logged: Int)
        /// Marked done with fewer sets logged than prescribed — including none at all.
        /// `logged == 0` is the case that must never look like a finished lift.
        case completedModified(logged: Int, planned: Int)
        case skipped(ExerciseCompletionStatus)
        /// Swapped for something else and not yet resolved. Deliberately NOT a finished
        /// state: a substitution is work the lifter still performs.
        case substituted

        /// True when the exercise needs no further decision today.
        var isResolved: Bool {
            switch self {
            case .notStarted, .inProgress, .substituted: return false
            case .completedAsPlanned, .completedModified, .skipped: return true
            }
        }

        /// True only when the work was actually performed as written. The green "as planned"
        /// treatment is reserved for this; everything else earns a qualified presentation.
        var isCleanCompletion: Bool {
            if case .completedAsPlanned = self { return true }
            return false
        }

        /// Marked done with nothing logged at all — the state that most needs to not look
        /// like success.
        var isCompletedWithoutWork: Bool {
            if case .completedModified(let logged, _) = self { return logged == 0 }
            return false
        }
    }

    // MARK: - History

    struct PreviousSession: Equatable {
        let sets: [SetLogEntry]
        /// Sets actually recorded last time. Shown alongside the plan because a "3 sets"
        /// prescription displayed above a four-number history reads as a bug when it is
        /// simply what happened.
        var setCount: Int { sets.count }
    }

    struct BestRecord: Equatable {
        let weightLbs: Double
        let reps: Int?
        let achievedAt: Date?
        /// Whether this best was set in TODAY's session.
        ///
        /// The single most useful fact the old card threw away. "Last" deliberately excludes
        /// today while "Best" includes it, which is defensible individually and incoherent
        /// stacked in one box. Knowing which it is lets the card say "New best, today"
        /// instead of presenting a number the lifter just lifted as though it were history.
        let wasSetToday: Bool
    }

    // MARK: - Adherence

    /// Ways today's work departed from what was prescribed. Reported, never enforced.
    enum AdherenceFlag: Equatable {
        /// More reps than the top of the range — usually means the load was too light.
        case repsAboveRange(setNumber: Int, reps: Int, high: Int)
        /// Fewer reps than the bottom of the range.
        case repsBelowRange(setNumber: Int, reps: Int, low: Int)
        /// Logged effort well short of target. Two-plus RIR of slack is a warm-up being
        /// counted as a working set, not a rounding difference.
        case effortUnderTarget(setNumber: Int, rir: Double, target: Int)
        /// Marked done with fewer sets than prescribed.
        case setsIncomplete(logged: Int, planned: Int)

        /// Threshold for `effortUnderTarget`. One RIR of drift is normal self-report noise;
        /// two is a different kind of set.
        static let effortSlackThreshold: Double = 2
    }

    // MARK: - Stored

    let state: State
    let plannedSets: Int
    let repRange: RepRange?
    let targetRIR: Int?
    let todaysSets: [SetLogEntry]
    let previous: PreviousSession?
    let best: BestRecord?
    let adherence: [AdherenceFlag]

    var loggedSetCount: Int { todaysSets.count }

    /// True when the card should offer a way to record what was actually done. A lift marked
    /// finished with nothing logged leaves no trace for future programming.
    var needsLoggingPrompt: Bool { state.isCompletedWithoutWork }

    // MARK: - Resolution

    /// Builds the summary from the four sources the card used to read independently.
    ///
    /// - Parameters:
    ///   - isCompleted: the exercise's own completion flag.
    ///   - completionStatus: skip / modified / substituted, if any.
    ///   - plannedSets: prescribed set count.
    ///   - reps: the prescribed rep string, parsed into a range when it is parseable.
    ///   - targetRIR: structured effort target.
    ///   - todaysSets: sets logged today.
    ///   - previousSets: sets logged in the most recent EARLIER session.
    ///   - bestWeightLbs / bestReps / bestLoggedAt: the all-time record.
    ///   - now: injectable for deterministic tests.
    static func resolve(
        isCompleted: Bool,
        completionStatus: ExerciseCompletionStatus?,
        plannedSets: Int,
        reps: String,
        targetRIR: Int?,
        todaysSets: [SetLogEntry],
        previousSets: [SetLogEntry],
        bestWeightLbs: Double?,
        bestReps: Int?,
        bestLoggedAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ExerciseSessionSummary {
        let range = RepRange.parse(reps)
        let state = resolveState(
            isCompleted: isCompleted,
            completionStatus: completionStatus,
            plannedSets: plannedSets,
            loggedCount: todaysSets.count
        )

        let best: BestRecord? = bestWeightLbs.map { weight in
            BestRecord(
                weightLbs: weight,
                reps: bestReps,
                achievedAt: bestLoggedAt,
                // No timestamp means an older summary row that predates best-date tracking.
                // Treat it as historical: claiming "today" on missing evidence is the worse
                // error, since it is the claim that changes what the lifter is told.
                wasSetToday: bestLoggedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            )
        }

        return ExerciseSessionSummary(
            state: state,
            plannedSets: plannedSets,
            repRange: range,
            targetRIR: targetRIR,
            todaysSets: todaysSets,
            previous: previousSets.isEmpty ? nil : PreviousSession(sets: previousSets),
            best: best,
            adherence: adherenceFlags(
                state: state,
                todaysSets: todaysSets,
                repRange: range,
                targetRIR: targetRIR
            )
        )
    }

    private static func resolveState(
        isCompleted: Bool,
        completionStatus: ExerciseCompletionStatus?,
        plannedSets: Int,
        loggedCount: Int
    ) -> State {
        // Skip wins over everything: it is an explicit statement about the whole exercise,
        // and skips set `isCompleted = true` at the call site so checking that first would
        // read a skipped lift as completed.
        if let completionStatus, completionStatus.isSkipped {
            return .skipped(completionStatus)
        }
        if completionStatus == .substituted, !isCompleted {
            return .substituted
        }

        guard isCompleted else {
            return loggedCount == 0 ? .notStarted : .inProgress(logged: loggedCount, planned: plannedSets)
        }

        // Derived from the logs, not from the stored status: a lift can be marked complete
        // through several paths, and only the log count knows whether the work happened.
        if loggedCount >= plannedSets, plannedSets > 0 {
            return .completedAsPlanned(logged: loggedCount)
        }
        return .completedModified(logged: loggedCount, planned: plannedSets)
    }

    private static func adherenceFlags(
        state: State,
        todaysSets: [SetLogEntry],
        repRange: RepRange?,
        targetRIR: Int?
    ) -> [AdherenceFlag] {
        var flags: [AdherenceFlag] = []

        if case .completedModified(let logged, let planned) = state, planned > 0 {
            flags.append(.setsIncomplete(logged: logged, planned: planned))
        }

        for set in todaysSets {
            if let repRange {
                if set.repsCompleted > repRange.high {
                    flags.append(.repsAboveRange(setNumber: set.setNumber, reps: set.repsCompleted, high: repRange.high))
                } else if set.repsCompleted < repRange.low {
                    flags.append(.repsBelowRange(setNumber: set.setNumber, reps: set.repsCompleted, low: repRange.low))
                }
            }
            // Only flag effort the lifter actually reported. `rir` is optional by design so
            // legacy sessions never acquire invented effort data, and an absent value must
            // not be read as zero.
            if let target = targetRIR, let rir = set.rir,
               rir - Double(target) >= AdherenceFlag.effortSlackThreshold {
                flags.append(.effortUnderTarget(setNumber: set.setNumber, rir: rir, target: target))
            }
        }

        return flags
    }
}

// MARK: - Presentation

extension ExerciseSessionSummary.AdherenceFlag {
    /// One short line for the card. Deliberately descriptive rather than corrective — it says
    /// what happened, and leaves what to do about it to the progression banner, which is the
    /// single voice that owns load and rep advice.
    var noticeText: String {
        switch self {
        case .repsAboveRange(let setNumber, let reps, let high):
            return "Set \(setNumber) ran to \(reps) reps, past the \(high) you were aiming for."
        case .repsBelowRange(let setNumber, let reps, let low):
            return "Set \(setNumber) stopped at \(reps) reps, under the \(low) you were aiming for."
        case .effortUnderTarget(let setNumber, let rir, let target):
            let rirText = rir.rounded() == rir ? String(Int(rir)) : String(format: "%.1f", rir)
            return "Set \(setNumber) logged RIR \(rirText) against a target of \(target) — closer to a warm-up than a working set."
        case .setsIncomplete(let logged, let planned):
            return logged == 0
                ? "Marked done with no sets logged, so nothing from it reaches your history."
                : "Marked done after \(logged) of \(planned) sets."
        }
    }
}

extension ExerciseSessionSummary.State {
    /// Short label for the card. `nil` means the state needs no label — the ordinary case,
    /// where the completion check alone says everything.
    var qualifierLabel: String? {
        switch self {
        case .notStarted, .inProgress, .completedAsPlanned:
            return nil
        case .completedModified(let logged, _):
            return logged == 0 ? "Done · nothing logged" : "Done · modified"
        case .skipped(let status):
            return status.shortLabel
        case .substituted:
            return "Substituted"
        }
    }
}
