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
}
