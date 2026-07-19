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
    static func plan<ID: Equatable>(
        segments: [HealthSleepSegment],
        existing: [ExistingSleepProjection<ID>],
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
            guard let main = plausible.max(by: { $0.duration < $1.duration }) else {
                // There was sleep data for this day but nothing formed a real night.
                plans.append(.skip(.noPlausibleMainSleep, wakeDayStart: wakeDayStart))
                continue
            }

            let candidate = SleepImportCandidate(
                wakeDayStart: wakeDayStart,
                start: main.start,
                end: main.end
            )
            plans.append(reconcile(candidate: candidate, existing: existing))
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

        // Update the existing imported row in place if the detected night moved.
        if let imported = mainOnDay.first(where: { $0.source == .healthKit }) {
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
