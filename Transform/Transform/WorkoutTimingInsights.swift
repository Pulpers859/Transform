import Foundation

/// The Dashboard's "Workout Timing" card: rated sessions grouped by the hour they started, and
/// which time of day has gone best. Pinned by WorkoutTimingInsightsTests.
///
/// Council review 2026-11-23 (owner-approved). The card used to crown a "Best results" time from a
/// single session, score EASIER sessions higher (a `(5 - effort)` term: for muscle gain a lower
/// effort rating is not a better session), add raw counts of better/worse sessions (so the slot
/// trained most often won), count deload weeks (lighter on purpose), and drop sessions started
/// between midnight and 4:59 out of every slot while still counting them in the total. Now:
///  * deload-week sessions are left out;
///  * every hour belongs to a slot ("Night" runs 21:00-4:59);
///  * score = average stimulus rating + (share rated Better - share rated Worse);
///  * a slot can be "best" only with `minimumSessions` sessions, and only when at least two slots
///    qualify, so there is something to compare. All thresholds are heuristics.
enum WorkoutTimingInsights {
    struct Session: Equatable {
        var hour: Int
        var effort: Int
        var stimulus: Int
        /// +1 rated "Better", -1 "Worse", 0 otherwise.
        var performance: Int
        var isDeload: Bool
    }

    struct Bucket: Equatable {
        let label: String
        let sessionCount: Int
        let avgStimulus: Double
        let avgEffort: Double
        let score: Double
    }

    static let minimumSessions = 3
    /// Highest possible score: stimulus 5 plus every session rated Better.
    static let maximumScore = 6.0

    private static let slots: [(label: String, hours: Set<Int>)] = [
        ("Early AM\n5-8", Set(5...8)),
        ("Morning\n9-11", Set(9...11)),
        ("Midday\n12-14", Set(12...14)),
        ("Afternoon\n15-17", Set(15...17)),
        ("Evening\n18-20", Set(18...20)),
        ("Night\n21-4", Set(21...23).union(0...4))
    ]

    /// Sessions the card counts: rated, outside deload weeks.
    static func counted(_ sessions: [Session]) -> [Session] {
        sessions.filter { !$0.isDeload }
    }

    static func buckets(_ sessions: [Session]) -> [Bucket] {
        let usable = counted(sessions)
        guard usable.count >= minimumSessions else { return [] }
        return slots.compactMap { slot in
            let inSlot = usable.filter { slot.hours.contains($0.hour) }
            guard !inSlot.isEmpty else { return nil }
            let count = Double(inSlot.count)
            let avgStimulus = Double(inSlot.map(\.stimulus).reduce(0, +)) / count
            let avgEffort = Double(inSlot.map(\.effort).reduce(0, +)) / count
            let better = Double(inSlot.filter { $0.performance > 0 }.count)
            let worse = Double(inSlot.filter { $0.performance < 0 }.count)
            let score = avgStimulus + (better - worse) / count
            return Bucket(label: slot.label, sessionCount: inSlot.count, avgStimulus: avgStimulus,
                          avgEffort: avgEffort, score: score)
        }
    }

    static func best(_ buckets: [Bucket]) -> Bucket? {
        let eligible = buckets.filter { $0.sessionCount >= minimumSessions }
        guard eligible.count >= 2 else { return nil }
        return eligible.max(by: { $0.score < $1.score })
    }
}
