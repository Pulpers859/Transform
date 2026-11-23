import Foundation

/// The Dashboard's "Workout Timing" card rules. RED-TEST STUB (council review 2026-11-23):
/// reproduces the card's previous rules so WorkoutTimingInsightsTests can be seen failing.
enum WorkoutTimingInsights {
    struct Session: Equatable {
        var hour: Int
        var effort: Int
        var stimulus: Int
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
    static let maximumScore = 5.0

    static func counted(_ sessions: [Session]) -> [Session] { sessions }

    static func buckets(_ sessions: [Session]) -> [Bucket] {
        guard sessions.count >= minimumSessions else { return [] }
        let ranges: [(label: String, range: ClosedRange<Int>)] = [
            ("Early AM\n5-8", 5...8), ("Morning\n9-11", 9...11), ("Midday\n12-14", 12...14),
            ("Afternoon\n15-17", 15...17), ("Evening\n18-20", 18...20), ("Night\n21+", 21...23)
        ]
        return ranges.compactMap { slot in
            let inSlot = sessions.filter { slot.range.contains($0.hour) }
            guard !inSlot.isEmpty else { return nil }
            let count = Double(inSlot.count)
            let avgStimulus = Double(inSlot.map(\.stimulus).reduce(0, +)) / count
            let avgEffort = Double(inSlot.map(\.effort).reduce(0, +)) / count
            let better = inSlot.filter { $0.performance > 0 }.count
            let worse = inSlot.filter { $0.performance < 0 }.count
            let score = avgStimulus * 0.5 + (5.0 - avgEffort) * 0.2 + Double(better - worse) * 0.3
            return Bucket(label: slot.label, sessionCount: inSlot.count, avgStimulus: avgStimulus, avgEffort: avgEffort, score: score)
        }
    }

    static func best(_ buckets: [Bucket]) -> Bucket? {
        buckets.max(by: { $0.score < $1.score })
    }
}
