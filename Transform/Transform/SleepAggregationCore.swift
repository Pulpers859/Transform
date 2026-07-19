import Foundation

// Foundation-only aggregation core behind SleepTrendBuilder.
//
// WHY THIS EXISTS
// ---------------
// The recovery tier (RecoveryState.swift) is only as honest as the day aggregation
// feeding it, and that aggregation originally lived inside a SwiftUI/SwiftData file
// the headless test harness cannot compile. Two silent-dishonesty bugs hid there:
// a wake-day whose only logged episode was a nap counted as a full "logged day"
// (a 1.5h nap read as a 1.5h night, dragging the 3-day average into RESTRICTED),
// and nap-only days counted toward the under-5h/under-6h day tallies. This file
// holds the SwiftData-free math so the harness can pin both rules.
//
// SleepTracking.swift maps SleepEntry models into SleepEpisodeSample values and
// rebuilds its UI-facing snapshot on top of these numbers.

/// What a logged episode contributes to a wake-day.
enum SleepSampleKind: Equatable {
    case main
    case nap
    case recovery
}

/// Minimal SwiftData-free projection of one logged sleep episode.
struct SleepEpisodeSample {
    let start: Date
    let end: Date
    let durationHours: Double
    let quality: Int
    let kind: SleepSampleKind
    /// The episode was tagged with the post-call shift context.
    let isPostCallShift: Bool

    init(
        start: Date,
        end: Date,
        durationHours: Double,
        quality: Int,
        kind: SleepSampleKind,
        isPostCallShift: Bool = false
    ) {
        self.start = start
        self.end = end
        self.durationHours = durationHours
        self.quality = quality
        self.kind = kind
        self.isPostCallShift = isPostCallShift
    }
}

/// One anchored wake-day's aggregated numbers.
struct SleepDayAggregate: Equatable {
    let date: Date
    let totalHours: Double
    let mainSleepHours: Double
    let napHours: Double
    let averageQuality: Double
}

/// The numeric portion of a sleep trend over the trailing 7 wake-days.
struct SleepAggregateSnapshot {
    /// Anchored wake-days only, ascending by date.
    let days: [SleepDayAggregate]
    let sevenDayAverageHours: Double
    let threeDayAverageHours: Double
    let averageQuality: Double
    let variabilityHours: Double
    let underSixHours: Int
    let underFiveHours: Int
    let qualityDurationMismatchDays: Int
    let hasRecentPostCallRecovery: Bool
    let acuteLoggedDays: Int
    /// Wake-days in the window whose only logged episodes were naps. They are
    /// excluded from every average and day count above — a nap-only day is an
    /// unlogged night, not a 1.5-hour night — but surfaced so prompts and UI
    /// can say the exclusion happened instead of hiding it.
    let napOnlyDayCount: Int
}

enum SleepAggregationCore {
    /// A wake-day only participates in trend math when a main sleep or post-call
    /// recovery episode anchors it; naps add hours to an anchored day but can
    /// never create a day on their own.
    static func build(
        from samples: [SleepEpisodeSample],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SleepAggregateSnapshot? {
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let recent = samples.filter { $0.end >= cutoff && $0.end < tomorrow }

        let grouped = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.end) }
        let anchored = grouped.filter { _, episodes in
            episodes.contains { $0.kind != .nap }
        }
        let napOnlyDayCount = grouped.count - anchored.count

        let days = anchored.map { date, episodes -> SleepDayAggregate in
            let total = episodes.reduce(0) { $0 + $1.durationHours }
            let qualityWeight = episodes.reduce(0.0) { $0 + max($1.durationHours, 0.25) }
            let weightedQuality = episodes.reduce(0.0) {
                $0 + Double($1.quality) * max($1.durationHours, 0.25)
            } / max(qualityWeight, 0.25)
            return SleepDayAggregate(
                date: date,
                totalHours: total,
                mainSleepHours: episodes.filter { $0.kind == .main }.reduce(0) { $0 + $1.durationHours },
                napHours: episodes.filter { $0.kind == .nap }.reduce(0) { $0 + $1.durationHours },
                averageQuality: weightedQuality
            )
        }
        .sorted { $0.date < $1.date }
        guard !days.isEmpty else { return nil }

        let totals = days.map(\.totalHours)
        let sevenDayAverage = totals.reduce(0, +) / Double(totals.count)
        let threeDayCutoff = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let acuteDays = days.filter { $0.date >= threeDayCutoff }
        let threeDayAverage = acuteDays.isEmpty
            ? 0
            : acuteDays.map(\.totalHours).reduce(0, +) / Double(acuteDays.count)
        let variance = totals.map { pow($0 - sevenDayAverage, 2) }.reduce(0, +) / Double(totals.count)
        let averageQuality = days.map(\.averageQuality).reduce(0, +) / Double(days.count)
        let qualityDurationMismatch = days.filter {
            ($0.totalHours >= 7 && $0.averageQuality <= 2) || ($0.totalHours < 6 && $0.averageQuality >= 4)
        }.count
        // Post-call context is real regardless of anchoring, so this looks at all
        // recent episodes (a post-call nap still marks a post-call window).
        let recentPostCall = recent.contains {
            $0.end >= threeDayCutoff && ($0.kind == .recovery || $0.isPostCallShift)
        }

        return SleepAggregateSnapshot(
            days: days,
            sevenDayAverageHours: sevenDayAverage,
            threeDayAverageHours: threeDayAverage,
            averageQuality: averageQuality,
            variabilityHours: sqrt(variance),
            underSixHours: days.filter { $0.totalHours < 6 }.count,
            underFiveHours: days.filter { $0.totalHours < 5 }.count,
            qualityDurationMismatchDays: qualityDurationMismatch,
            hasRecentPostCallRecovery: recentPostCall,
            acuteLoggedDays: acuteDays.count,
            napOnlyDayCount: napOnlyDayCount
        )
    }
}

/// Wake-date crediting for the 3-tap quick log (the "ends now" composer).
///
/// Shortly after midnight, "last night" still means the sleep that ended the
/// previous morning — stamping it with the current clock time would credit it
/// to the NEW wake-day, leave the real day looking unlogged, and pre-fill
/// tomorrow's totals in the tier decision. Before the cutoff hour the quick log
/// therefore saves the episode ending just before midnight of the previous day.
enum SleepQuickLogPolicy {
    /// Before this hour, a quick log is credited to the previous wake-day.
    static let previousWakeDayCutoffHour = 4

    /// The end timestamp a quick log saved at `now` should carry.
    static func quickLogEnd(loggedAt now: Date, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard
            let cutoff = calendar.date(
                byAdding: .hour,
                value: previousWakeDayCutoffHour,
                to: startOfToday
            ),
            now < cutoff
        else { return now }
        return startOfToday.addingTimeInterval(-60)
    }

    /// The wake-day a quick log saved at `now` will be credited to.
    static func creditedWakeDayStart(loggedAt now: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: quickLogEnd(loggedAt: now, calendar: calendar))
    }
}
