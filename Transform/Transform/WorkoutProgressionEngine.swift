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
}

struct WorkoutPerformanceLogSnapshot: Equatable {
    let canonicalExerciseKey: String
    let loggedAt: Date
    let setLogs: [SetLogEntry]
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
        repRange: RepRange
    ) -> WorkoutProgressionDecision? {
        if let workingWeight = analysis.workingWeight, !analysis.workingSets.isEmpty {
            let reps = analysis.workingSets.map(\.reps)
            let minimumReps = reps.min()
            let ceilingCount = reps.filter { $0 >= repRange.high }.count
            let workingCount = reps.count
            let majority = max(1, Int(ceil(Double(workingCount) * 0.67)))

            let kind: ClaudeService.ProgressionVerdictKind
            if let minimumReps, minimumReps >= repRange.high {
                kind = .addLoad
            } else if let minimumReps, minimumReps < repRange.low {
                kind = .holdBelowRange
            } else {
                kind = ceilingCount >= majority ? .addLoad : .addRepsInRange
            }

            return WorkoutProgressionDecision(
                kind: kind,
                workingWeight: workingWeight,
                minimumWorkingReps: minimumReps,
                workingSetCount: workingCount,
                ceilingSetCount: ceilingCount,
                usedPerSetEvidence: true
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
            usedPerSetEvidence: false
        )
    }

    static func evaluate(
        latestSetLogs: [SetLogEntry],
        summaryWeight: Double?,
        summaryReps: Int?,
        repRange: RepRange
    ) -> WorkoutProgressionDecision? {
        evaluate(
            analysis: WorkingSetAnalysis.analyze(latestSetLogs),
            summaryWeight: summaryWeight,
            summaryReps: summaryReps,
            repRange: repRange
        )
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
