import Foundation

struct RepRange: Equatable {
    let low: Int
    let high: Int

    static func parse(_ reps: String) -> RepRange? {
        let cleaned = reps
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        if cleaned.contains("-") {
            let parts = cleaned.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, parts[0] > 0, parts[1] >= parts[0] else { return nil }
            return RepRange(low: parts[0], high: parts[1])
        }

        guard let single = Int(cleaned), single > 0 else { return nil }
        return RepRange(low: single, high: single)
    }
}

struct WorkoutProgressionDecision: Equatable {
    let kind: ClaudeService.ProgressionVerdictKind
    let workingWeight: Double
    let minimumWorkingReps: Int?
    let workingSetCount: Int
    let ceilingSetCount: Int
    /// How many working sets finished BELOW the prescribed rep floor.
    ///
    /// The card used to describe any below-range session as "a working set dropped to N",
    /// which reads as one set slipping among good ones. That sentence rendered unchanged for
    /// a session where EVERY set missed the floor (55 lb for 14 and 12 against a 15-20
    /// target), understating the miss to the one person who needed it stated plainly. The
    /// count is the only thing that separates "one set slipped" from "nothing reached the
    /// target", and those two sessions need different coaching.
    let belowFloorSetCount: Int
    /// Consecutive recent sessions at this load that finished under the rep floor, including
    /// this one. Carried so the cue can state how long the stall has run rather than
    /// asserting a stall the lifter has no way to check.
    let belowFloorStreak: Int
    let usedPerSetEvidence: Bool
    let effortSignal: WorkoutExerciseEffortSignal
}

struct WorkoutPerformanceLogSnapshot: Equatable {
    let canonicalExerciseKey: String
    let loggedAt: Date
    let setLogs: [SetLogEntry]
    /// The rep prescription this session ran under, empty when it predates the recording.
    /// Carried on the snapshot so the range can be resolved from the SAME decode pass that
    /// produces the sets — decoding every log a second time to read it would reintroduce
    /// the per-render cost `performanceSnapshotsByKey` exists to avoid.
    var prescribedReps: String = ""
    /// Set count the session was prescribed; 0 when it predates the recording. Rides along for
    /// the same reason as `prescribedReps` — one decode pass, not two.
    var prescribedSets: Int = 0
}

enum WorkoutExerciseEffortSignal: Equatable {
    case protectRecovery
    case progressionHeadroom
    case neutral
    case insufficientEvidence
}

enum WorkoutProgressionEngine {
    static func latestUsableSetLogs(
        for canonicalExerciseKey: String,
        from snapshots: [WorkoutPerformanceLogSnapshot]
    ) -> [SetLogEntry] {
        snapshots
            .filter { $0.canonicalExerciseKey == canonicalExerciseKey }
            .sorted { $0.loggedAt > $1.loggedAt }
            .first { !$0.setLogs.isEmpty }?
            .setLogs ?? []
    }

    static func evaluate(
        analysis: WorkingSetAnalysis,
        summaryWeight: Double?,
        summaryReps: Int?,
        repRange: RepRange,
        effortSignal: WorkoutExerciseEffortSignal = .insufficientEvidence,
        belowFloorStreak: Int = 0
    ) -> WorkoutProgressionDecision? {
        if let workingWeight = analysis.workingWeight, !analysis.workingSets.isEmpty {
            let reps = analysis.workingSets.map(\.reps)
            let minimumReps = reps.min()
            let ceilingCount = reps.filter { $0 >= repRange.high }.count
            let belowFloorCount = reps.filter { $0 < repRange.low }.count
            let workingCount = reps.count
            let majority = max(1, Int(ceil(Double(workingCount) * 0.67)))

            let repKind: ClaudeService.ProgressionVerdictKind
            if let minimumReps, minimumReps >= repRange.high {
                repKind = .addLoad
            } else if let minimumReps, minimumReps < repRange.low {
                repKind = .holdBelowRange
            } else {
                repKind = ceilingCount >= majority ? .addLoad : .addRepsInRange
            }
            // Holding is the right answer the FIRST time a session lands under the floor —
            // one hard session proves nothing about the load. It stops being the right
            // answer once holding has already been tried and the reps still did not come
            // back: at that point repeating "hold and build reps" just prescribes the same
            // failed session again. Two is the threshold because one is noise (a bad night,
            // a rushed session) and waiting for three spends another week under load the
            // lifter has already shown they cannot use.
            //
            // Recovery protection cannot outrank this. Both say "back off", but only this
            // one names the load, and holding a load that is too heavy is not protection.
            let kind: ClaudeService.ProgressionVerdictKind
            if repKind == .holdBelowRange && belowFloorStreak >= 2 {
                kind = .reduceLoad
            } else if effortSignal == .protectRecovery && repKind != .holdBelowRange {
                kind = .holdForRecovery
            } else {
                kind = repKind
            }

            return WorkoutProgressionDecision(
                kind: kind,
                workingWeight: workingWeight,
                minimumWorkingReps: minimumReps,
                workingSetCount: workingCount,
                ceilingSetCount: ceilingCount,
                belowFloorSetCount: belowFloorCount,
                belowFloorStreak: belowFloorStreak,
                usedPerSetEvidence: true,
                effortSignal: effortSignal
            )
        }

        // Weight 0 is a valid bodyweight summary; nil means no usable log at all.
        guard let summaryWeight, summaryWeight >= 0, let summaryReps, summaryReps > 0 else {
            return nil
        }

        let kind: ClaudeService.ProgressionVerdictKind
        if summaryReps >= repRange.high {
            kind = .addLoad
        } else if summaryReps < repRange.low {
            kind = .holdBelowRange
        } else {
            kind = .addRepsInRange
        }

        return WorkoutProgressionDecision(
            kind: kind,
            workingWeight: summaryWeight,
            minimumWorkingReps: summaryReps,
            workingSetCount: 0,
            ceilingSetCount: summaryReps >= repRange.high ? 1 : 0,
            // No per-set evidence means no analysed working sets to count, matching
            // `workingSetCount: 0` above. The copy for this path never cites a count.
            belowFloorSetCount: 0,
            // A streak is a per-set property; summary-only records cannot establish one,
            // so this path can never reach `.reduceLoad`.
            belowFloorStreak: 0,
            usedPerSetEvidence: false,
            effortSignal: .insufficientEvidence
        )
    }

    static func evaluate(
        latestSetLogs: [SetLogEntry],
        summaryWeight: Double?,
        summaryReps: Int?,
        repRange: RepRange,
        effortSignal: WorkoutExerciseEffortSignal = .insufficientEvidence,
        belowFloorStreak: Int = 0
    ) -> WorkoutProgressionDecision? {
        evaluate(
            analysis: WorkingSetAnalysis.analyze(latestSetLogs),
            summaryWeight: summaryWeight,
            summaryReps: summaryReps,
            repRange: repRange,
            effortSignal: effortSignal,
            belowFloorStreak: belowFloorStreak
        )
    }

    /// Uses only explicit RIR captured on working sets. Reps and load prove whether a
    /// double-progression step is mechanically available; they do not prove proximity to
    /// failure. Two corroborating sessions are required before effort can override that step.
    static func effortSignal(
        for canonicalExerciseKey: String,
        from snapshots: [WorkoutPerformanceLogSnapshot],
        lookback: Int = 3
    ) -> WorkoutExerciseEffortSignal {
        let recent = snapshots
            .filter { $0.canonicalExerciseKey == canonicalExerciseKey }
            .sorted { $0.loggedAt > $1.loggedAt }
            .prefix(max(1, lookback))

        let sessionRIRs: [[Double]] = recent.compactMap { snapshot in
            let workingSets = WorkingSetAnalysis.analyze(snapshot.setLogs).workingSets
            let values = workingSets.compactMap { rir -> Double? in
                guard let value = rir.rir, (0...6).contains(value) else { return nil }
                return value
            }
            guard !workingSets.isEmpty,
                  values.count == workingSets.count || (workingSets.count == 1 && values.count == 1)
            else { return nil }
            return values
        }

        guard sessionRIRs.count >= 2 else { return .insufficientEvidence }
        let averages = sessionRIRs.map { $0.reduce(0, +) / Double($0.count) }
        if averages.filter({ $0 <= 1 }).count >= 2 { return .protectRecovery }
        if averages.filter({ $0 >= 3 }).count >= 2 { return .progressionHeadroom }
        return .neutral
    }

    /// Loads at or under this are treated as bodyweight work. Covers true bodyweight
    /// logs (0) AND the historical workaround records where a bodyweight exercise was
    /// logged as "1 lb" because the logger once required a positive weight — those
    /// records are reinterpreted here rather than rewritten (no destructive migration).
    static let bodyweightEquivalentThresholdLbs = 1.0

    static func isBodyweightEquivalent(_ weight: Double) -> Bool {
        weight <= bodyweightEquivalentThresholdLbs
    }

    /// How many of the most recent consecutive sessions at THIS load finished under the
    /// rep floor. Counting stops at the first session that broke the pattern.
    ///
    /// Consecutive-and-at-the-same-load is the whole point. A session at a different weight
    /// ends the streak because it is a different experiment, and a session that reached the
    /// floor ends it because the load demonstrably works. Without both conditions this would
    /// count unrelated hard sessions scattered across a training block and recommend
    /// dropping a load that is fine.
    ///
    /// The session being graded is normally itself the newest snapshot, so a streak of 2
    /// means "this one and the one before it" — the first miss alone never trips it.
    static func belowFloorStreak(
        for canonicalExerciseKey: String,
        from snapshots: [WorkoutPerformanceLogSnapshot],
        workingWeight: Double,
        repFloor: Int,
        lookback: Int = 4
    ) -> Int {
        let recent = snapshots
            .filter { $0.canonicalExerciseKey == canonicalExerciseKey }
            .sorted { $0.loggedAt > $1.loggedAt }
            .prefix(max(1, lookback))

        var streak = 0
        for snapshot in recent {
            let analysis = WorkingSetAnalysis.analyze(snapshot.setLogs)
            guard let weight = analysis.workingWeight, !analysis.workingSets.isEmpty else { break }
            // Same tolerance the analyzer uses to call two logged loads "the same weight".
            guard abs(weight - workingWeight) <= max(0.5, workingWeight * 0.02) else { break }
            guard let lowest = analysis.workingSets.map(\.reps).min(), lowest < repFloor else { break }
            streak += 1
        }
        return streak
    }

    /// One increment DOWN, mirroring `nextLoad`, so a reduce-load cue names a load the
    /// lifter's equipment can actually make. Never returns a load at or below zero: the
    /// smallest real increment is the floor, and a bodyweight movement has nothing to drop.
    static func reducedLoad(from weight: Double, exerciseName: String) -> Double {
        guard !isBodyweightEquivalent(weight) else { return 0 }
        let isDumbbell = isDumbbellLift(exerciseName)
        let step = incrementLbs(forExerciseName: exerciseName)
        let rawDrop = max(weight * 0.05, step)
        let cappedDrop = min(rawDrop, isDumbbell ? 15.0 : 10.0)
        // DOWN, never nearest. Rounding a reduce-load cue up would hand back part of the drop
        // the lifter is being told to take, on the one verdict that fires because the current
        // load is already too heavy.
        return max(step, ((weight - cappedDrop) / step).rounded(.down) * step)
    }

    /// The smallest load step this exercise's equipment can actually make.
    ///
    /// ONE definition, used by every load the app recommends — up, down, or translated across a
    /// prescription change. Three copies of this rule would be three chances to recommend a
    /// weight that cannot be assembled.
    ///
    /// Selectorised stacks and barbells are 2.5 lb: the owner has 2.5 lb add-ons, and the old
    /// flat 5 lb assumption was a 10% jump on a 50 lb isolation lift — big enough to knock a
    /// lifter out of a 15-20 rep range in one step, which is exactly what happened on the cable
    /// face pull. Fixed dumbbells stay 5 lb because add-on plates do not apply to them.
    ///
    /// `override` is a per-exercise correction for equipment that genuinely cannot do 2.5 (a
    /// machine with welded 10 lb plates); ignored when zero or negative so "not recorded" can
    /// never be read as "no increment".
    static func incrementLbs(forExerciseName name: String, override: Double = 0) -> Double {
        if override > 0 { return override }
        return isDumbbellLift(name) ? 5.0 : 2.5
    }

    static func nextLoad(from weight: Double, exerciseName: String) -> Double {
        // From bodyweight (or a fake ~1 lb record), the first external step is one
        // small increment, not percentage math off a meaningless base.
        guard !isBodyweightEquivalent(weight) else { return 2.5 }
        let isDumbbell = isDumbbellLift(exerciseName)
        let step = incrementLbs(forExerciseName: exerciseName)
        let rawJump = max(weight * 0.025, step)
        let cappedJump = min(rawJump, isDumbbell ? 15.0 : 10.0)
        return ((weight + cappedJump) / step).rounded() * step
    }

    private static func isDumbbellLift(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.contains("dumbbell") { return true }
        let tokens = lowered.split { !$0.isLetter }
        return tokens.contains("db")
    }

    // `isStackLift` was removed with the coarse-increment rule it existed to serve: stacks and
    // barbells now share the same 2.5 lb step, so nothing needed to tell them apart any more.
}
