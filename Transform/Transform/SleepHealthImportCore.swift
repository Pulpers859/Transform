import Foundation

// Foundation-only reconciliation core for importing sleep from an external timing
// source (Apple Health / HealthKit) into Transform's SleepEntry store.
//
// WHY THIS EXISTS (and why it is Foundation-only)
// -----------------------------------------------
// The 3-tap quick log reconstructs *when you slept* from *when you opened the app*, so
// a late-morning log skews wake time (log at 10:38, wake recorded as 10:38). The
// structural fix is to read a real slept interval from a sensor source instead of
// treating the human as the clock. Apple's system Sleep feature (Sleep Focus / Sleep
// Schedule) writes dated in-bed / asleep intervals to HealthKit with NO Apple Watch
// required, and SleepEntry is already interval-based (resolvedStartDate/EndDate), so
// importing is an input-source swap — not a rewrite of anything downstream.
//
// The hard part is not the HKHealthStore call; it is deciding what to DO with the
// samples, and that decision is pure and easy to get wrong:
//   * HealthKit returns fragmented segments — several asleep/in-bed rows per night,
//     possibly from more than one source — that must be coalesced into one night.
//   * A short in-bed blip (a 2 a.m. phone check, an afternoon lie-down) must not become
//     a "night" that anchors a phantom restricted day and wrongly suppresses training.
//   * A night the user already logged by hand must NEVER be silently overwritten — a
//     deliberate human report is the most trustworthy signal we have.
//   * Re-syncing the same night must update the existing row in place, not pile up
//     duplicate entries.
// That logic lives here, behind the headless test harness, separate from the iOS-only
// HKHealthStore I/O in SleepHealthKitService.swift.

/// Where a SleepEntry's timing came from. Defaulted to `.manual` on the model so every
/// existing/human-entered record is treated as manual and is never overwritten by an
/// import; only rows this importer created carry `.healthKit`.
enum SleepEntrySource: String, Codable, CaseIterable {
    case manual
    case healthKit
}

/// The kind of raw HealthKit sleep segment, coarsened to the three states we act on.
enum HealthSleepStage: Equatable {
    /// Any classified "asleep" value (core / deep / REM / unspecified).
    case asleep
    /// "In bed" but not classified asleep (iPhone-only schedule data is mostly this).
    case inBed
    /// "Awake" during the sleep window. Never anchors a night on its own; it only
    /// separates clusters when the awake gap is long enough.
    case awake
}

/// One raw HealthKit sleep sample projected onto Foundation types.
struct HealthSleepSegment: Equatable {
    let start: Date
    let end: Date
    let stage: HealthSleepStage
    /// HealthKit source name (e.g. "iPhone", a watch/tracker app). Retained for future
    /// source-preference logic; unused by the current coalescing rules.
    let sourceName: String?

    init(start: Date, end: Date, stage: HealthSleepStage, sourceName: String? = nil) {
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceName = sourceName
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// A resolved main-sleep night the importer wants to persist.
struct SleepImportCandidate: Equatable {
    /// Start of the calendar wake-day this night is credited to (day of `end`).
    let wakeDayStart: Date
    let start: Date
    let end: Date

    var durationHours: Double { max(0, end.timeIntervalSince(start) / 3600) }
}

/// Why a resolved night was not written as an insert/update.
enum SleepImportSkipReason: Equatable {
    /// The user already logged a main sleep by hand on this wake-day. Never overwrite it.
    case manualEntryPresent
    /// A previously-imported row already matches this night within tolerance.
    case alreadyUpToDate
    /// A wake-day had sleep segments but none formed a plausible main sleep (all too
    /// short — naps/blips — or implausibly long from overlapping sources).
    case noPlausibleMainSleep
    /// The night is the same sleep as an entry already stored (a hand-logged nap or
    /// post-call recovery sleep, or an imported night credited to another day): they overlap
    /// by at least half of the shorter one (`isSameSleep`). Importing it would count the
    /// same hours twice.
    case overlapsExistingEntry
    /// The owner deleted the night Apple Health supplied for this wake-day.
    case declinedByUser
}

/// What the SwiftData layer should do for one resolved wake-day. `ID` is the caller's
/// opaque row identity (SwiftData's PersistentIdentifier on-device); the core never
/// touches SwiftData itself.
enum SleepImportPlan<ID: Equatable>: Equatable {
    case insert(SleepImportCandidate)
    case update(id: ID, to: SleepImportCandidate)
    case skip(SleepImportSkipReason, wakeDayStart: Date)
}

/// Minimal projection of an existing SleepEntry the reconciler needs. Supplied by the
/// SwiftData layer so this core stays free of SwiftData/HealthKit.
struct ExistingSleepProjection<ID: Equatable>: Equatable {
    let id: ID
    let wakeDayStart: Date
    let start: Date
    let end: Date
    let isMainSleep: Bool
    let source: SleepEntrySource
}

enum SleepHealthImportCore {
    /// Shortest cluster accepted as a *main* sleep. Below this, a detected interval is a
    /// nap or an in-bed blip, not a night — importing it as a main sleep would anchor a
    /// phantom restricted day and wrongly suppress training. A genuinely tiny night can
    /// still be reported by hand (an intentional signal we trust). On-call short nights
    /// of ~3 h are preserved because the floor sits below them.
    static let mainSleepMinHours = 2.5

    /// Longest plausible single night. Beyond this, the cluster is almost certainly two
    /// overlapping sources or bad data merged together; skip rather than record a
    /// 20-hour "night".
    static let mainSleepMaxHours = 16.0

    /// Adjacent sleep segments separated by less than this are the same night. Bridges
    /// HealthKit's per-stage fragmentation and brief mid-night awakenings (60 min).
    static let clusterGapToleranceMinutes = 60.0

    /// Sub-tolerance timing drift between an existing imported row and a re-detected
    /// night is treated as unchanged, so routine re-syncs don't churn the store.
    static let updateEpsilonMinutes = 5.0

    /// Build the persist plan for a batch of HealthKit segments against existing rows.
    /// Deterministic and side-effect free.
    /// - Parameter declinedWakeDays: calendar-date keys (`SleepImportDeclines.dayKey`) of
    ///   wake-days whose imported night the owner deleted. Never re-imported.
    static func plan<ID: Equatable>(
        segments: [HealthSleepSegment],
        existing: [ExistingSleepProjection<ID>],
        declinedWakeDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> [SleepImportPlan<ID>] {
        let clusters = coalesce(segments)
        guard !clusters.isEmpty else { return [] }

        // One main sleep per wake-day: the longest plausible cluster ending that day.
        let byWakeDay = Dictionary(grouping: clusters) { calendar.startOfDay(for: $0.end) }
        var plans: [SleepImportPlan<ID>] = []

        for wakeDayStart in byWakeDay.keys.sorted() {
            let dayClusters = byWakeDay[wakeDayStart] ?? []
            let plausible = dayClusters.filter {
                let hours = $0.end.timeIntervalSince($0.start) / 3600
                return hours >= mainSleepMinHours && hours <= mainSleepMaxHours
            }
            guard !plausible.isEmpty else {
                // There was sleep data for this day but nothing formed a real night.
                plans.append(.skip(.noPlausibleMainSleep, wakeDayStart: wakeDayStart))
                continue
            }

            // Deleting an imported night is a decision about that night; without remembering
            // it, the next sync (any night in the 14-day window) put it straight back. Keyed
            // by calendar date, not a timestamp, so a time-zone change cannot unmatch it.
            if declinedWakeDays.contains(SleepImportDeclines.dayKey(for: wakeDayStart, calendar: calendar)) {
                plans.append(.skip(.declinedByUser, wakeDayStart: wakeDayStart))
                continue
            }

            // Longest plausible block first, as before. When it is the same sleep as an entry
            // already stored, try the next one rather than giving up on the day: a short
            // on-call night (01:00-04:00) followed by a hand-logged recovery sleep
            // (09:00-14:00) must still import the night, which is the signal that should
            // lower the recovery tier. Independent audit, 2026-11-18.
            var decision: SleepImportPlan<ID>?
            for cluster in plausible.sorted(by: { $0.duration > $1.duration }) {
                let candidate = SleepImportCandidate(
                    wakeDayStart: wakeDayStart,
                    start: cluster.start,
                    end: cluster.end
                )
                let outcome = reconcile(candidate: candidate, existing: existing)
                if case .skip(.overlapsExistingEntry, _) = outcome {
                    decision = decision ?? outcome
                    continue
                }
                decision = outcome
                break
            }
            if let decision { plans.append(decision) }
        }

        return plans
    }

    // MARK: - Coalescing

    private struct NightCluster {
        let start: Date
        let end: Date
        var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    /// Merge fragmented segments into night clusters. Asleep and in-bed segments group
    /// together by proximity; within a cluster the night interval is the extent of the
    /// *asleep* segments when any exist (trimming leading/trailing in-bed-awake time),
    /// falling back to the in-bed extent for iPhone-only schedule data. Pure "awake"
    /// segments never start or extend a night — they only break a cluster when the gap
    /// they create exceeds the tolerance.
    private static func coalesce(_ segments: [HealthSleepSegment]) -> [NightCluster] {
        let working = segments
            .filter { ($0.stage == .asleep || $0.stage == .inBed) && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard let first = working.first else { return [] }

        let gap = clusterGapToleranceMinutes * 60
        var clusters: [[HealthSleepSegment]] = []
        var current: [HealthSleepSegment] = [first]
        var currentEnd = first.end

        for segment in working.dropFirst() {
            if segment.start <= currentEnd.addingTimeInterval(gap) {
                current.append(segment)
                currentEnd = max(currentEnd, segment.end)
            } else {
                clusters.append(current)
                current = [segment]
                currentEnd = segment.end
            }
        }
        clusters.append(current)

        return clusters.map { cluster in
            let asleep = cluster.filter { $0.stage == .asleep }
            let basis = asleep.isEmpty ? cluster : asleep
            let start = basis.map(\.start).min() ?? cluster[0].start
            let end = basis.map(\.end).max() ?? cluster[0].end
            return NightCluster(start: start, end: end)
        }
    }

    // MARK: - Reconciliation

    /// The Health night (`nightStart`...`nightEnd`) is the same sleep as a stored entry when
    /// at least half of the NIGHT is already covered by it. Measured against the night, not
    /// the shorter of the two: measured against the shorter, a 30-minute nap logged just
    /// before bed "fully overlapped" an 8-hour night that Health had joined to it (segments
    /// under 60 minutes apart coalesce), and the whole night was dropped (independent audit,
    /// 2026-11-18). A recovery sleep or nap logged over the same hours still covers the night;
    /// a quick log's invented window grazing the next night does not.
    static func isSameSleep(_ nightStart: Date, _ nightEnd: Date, _ entryStart: Date, _ entryEnd: Date) -> Bool {
        let overlap = min(nightEnd, entryEnd).timeIntervalSince(max(nightStart, entryStart))
        let night = nightEnd.timeIntervalSince(nightStart)
        guard overlap > 0, night > 0 else { return false }
        return overlap >= night / 2
    }

    private static func reconcile<ID: Equatable>(
        candidate: SleepImportCandidate,
        existing: [ExistingSleepProjection<ID>]
    ) -> SleepImportPlan<ID> {
        let mainOnDay = existing.filter {
            $0.isMainSleep && $0.wakeDayStart == candidate.wakeDayStart
        }

        // A human-entered night wins outright: never overwrite an intentional report.
        if mainOnDay.contains(where: { $0.source == .manual }) {
            return .skip(.manualEntryPresent, wakeDayStart: candidate.wakeDayStart)
        }

        let imported = mainOnDay.first(where: { $0.source == .healthKit })

        // Never import a night that is the same sleep as one already stored. Only a same-day
        // MAIN manual night used to block an import, so a hand-logged nap or post-call
        // recovery sleep covering the same hours was imported again as a main sleep and the
        // day's total counted those hours twice, reading as better rested than the lifter
        // was (bug audit 2026-11-18).
        //
        // "Same sleep" is `isSameSleep`, not "any overlap". The quick log stores INVENTED
        // times (a duration counted back from when it was saved, or from 23:59 when saved
        // shortly after midnight), so it can overlap the following real night by hours
        // without being that night; refusing any overlap would have dropped real nights.
        // The imported row this candidate would update is excluded: overlapping itself is
        // the expected case. Pinned by SleepHealthImportCoreTests.
        if existing.contains(where: { entry in
            entry.id != imported?.id
                && isSameSleep(candidate.start, candidate.end, entry.start, entry.end)
        }) {
            return .skip(.overlapsExistingEntry, wakeDayStart: candidate.wakeDayStart)
        }

        // Update the existing imported row in place if the detected night moved.
        if let imported {
            let epsilon = updateEpsilonMinutes * 60
            let unchanged = abs(imported.start.timeIntervalSince(candidate.start)) <= epsilon
                && abs(imported.end.timeIntervalSince(candidate.end)) <= epsilon
            return unchanged
                ? .skip(.alreadyUpToDate, wakeDayStart: candidate.wakeDayStart)
                : .update(id: imported.id, to: candidate)
        }

        return .insert(candidate)
    }
}

/// Remembers the wake-days whose Apple Health night the owner deleted, so the importer does
/// not put it back on the next sync. Stored in UserDefaults as calendar-date text
/// ("2026-11-18"), not a timestamp: a start-of-day timestamp taken in one time zone does not
/// match the same date's start-of-day in another, so a deletion made before travelling came
/// back afterwards (independent audit, 2026-11-18). Entries older than `retentionDays` are
/// dropped when a new one is recorded; the importer only looks back
/// `SleepHealthKitService.importWindowDays`, so an older decline can never matter again.
/// The storage and pruning are pinned by SleepHealthImportCoreTests; the wiring (recording
/// in `SleepHistoryView.deleteEpisode`, loading in `SleepHealthKitService`) is UI/HealthKit
/// code and not covered by a test.
enum SleepImportDeclines {
    static let retentionDays = 60

    /// "yyyy-MM-dd" of `date` in `calendar`. Sorts in date order as plain text.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func load(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: AppSettingsKeys.healthKitSleepDeclinedWakeDays) ?? [])
    }

    static func record(
        wakeDayOf end: Date,
        now: Date = .now,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        let cutoff = dayKey(for: cutoffDate, calendar: calendar)
        var days = load(defaults).filter { $0 >= cutoff }
        days.insert(dayKey(for: end, calendar: calendar))
        defaults.set(days.sorted(), forKey: AppSettingsKeys.healthKitSleepDeclinedWakeDays)
    }
}
