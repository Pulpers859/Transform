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
    let usedPerSetEvidence: Bool
    let effortSignal: WorkoutExerciseEffortSignal
}

struct WorkoutPerformanceLogSnapshot: Equatable {
    let canonicalExerciseKey: String
    let loggedAt: Date
    let setLogs: [SetLogEntry]
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
        effortSignal: WorkoutExerciseEffortSignal = .insufficientEvidence
    ) -> WorkoutProgressionDecision? {
        if let workingWeight = analysis.workingWeight, !analysis.workingSets.isEmpty {
            let reps = analysis.workingSets.map(\.reps)
            let minimumReps = reps.min()
            let ceilingCount = reps.filter { $0 >= repRange.high }.count
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
            let kind = effortSignal == .protectRecovery && repKind != .holdBelowRange
                ? ClaudeService.ProgressionVerdictKind.holdForRecovery
                : repKind

            return WorkoutProgressionDecision(
                kind: kind,
                workingWeight: workingWeight,
                minimumWorkingReps: minimumReps,
                workingSetCount: workingCount,
                ceilingSetCount: ceilingCount,
                usedPerSetEvidence: true,
                effortSignal: effortSignal
            )
        }

        guard let summaryWeight, summaryWeight > 0, let summaryReps, summaryReps > 0 else {
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
            usedPerSetEvidence: false,
            effortSignal: .insufficientEvidence
        )
    }

    static func evaluate(
        latestSetLogs: [SetLogEntry],
        summaryWeight: Double?,
        summaryReps: Int?,
        repRange: RepRange,
        effortSignal: WorkoutExerciseEffortSignal = .insufficientEvidence
    ) -> WorkoutProgressionDecision? {
        evaluate(
            analysis: WorkingSetAnalysis.analyze(latestSetLogs),
            summaryWeight: summaryWeight,
            summaryReps: summaryReps,
            repRange: repRange,
            effortSignal: effortSignal
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

    static func nextLoad(from weight: Double, exerciseName: String) -> Double {
        guard weight > 0 else { return 2.5 }
        let isDumbbell = isDumbbellLift(exerciseName)
        let coarseIncrements = isDumbbell || isStackLift(exerciseName)
        let step: Double = coarseIncrements ? 5.0 : 2.5
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

    private static func isStackLift(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.contains("pressdown") || lowered.contains("pushdown")
            || lowered.contains("pulldown") || lowered.contains("pec deck") {
            return true
        }
        let tokens = lowered.split { !$0.isLetter }
        return tokens.contains("cable") || tokens.contains("machine")
    }
}
