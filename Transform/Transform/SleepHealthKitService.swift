import Foundation
import SwiftData

#if canImport(HealthKit)
import HealthKit
#endif

/// Result of an import pass, surfaced to the settings UI so the state we show the user
/// is the honest outcome, not an assumption.
enum SleepImportResult: Equatable {
    /// HealthKit is not available on this device (e.g. iPad without Health).
    case unavailable
    /// The query or a save failed. `message` is user-safe.
    case failed(String)
    /// Completed. Zero/zero is a legitimate outcome — no new sleep to import, or read
    /// access was declined (HealthKit deliberately does not tell apps which it was), so
    /// the UI copy must not promise data that isn't there.
    case completed(inserted: Int, updated: Int)
}

/// Bridges Apple Health sleep data into Transform's SleepEntry store. All decision logic
/// lives in the Foundation-only SleepHealthImportCore (harness-tested); this type only
/// does the HKHealthStore I/O and applies the resulting plan to SwiftData.
///
/// Read-only: Transform never writes sleep back to HealthKit, so only a share-usage
/// (read) description and the HealthKit read entitlement are required.
@MainActor
final class SleepHealthKitService {
    static let shared = SleepHealthKitService()

    /// Trailing window imported on each sync. Matches the ~7-day trend window with a few
    /// days of slack so a couple of missed syncs still backfill.
    ///
    /// `nonisolated` because this is read as a DEFAULT ARGUMENT (`days: Int =
    /// SleepHealthKitService.importWindowDays`), and default-argument expressions are evaluated
    /// in the caller's context rather than the callee's — so a main-actor-isolated constant
    /// cannot be reached there. That is a warning today and an error in the Swift 6 language
    /// mode. Safe to expose: an immutable `Int` is Sendable, so there is nothing to race on.
    nonisolated static let importWindowDays = 14

    private init() {}

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Prompt for read access to sleep. Returns false only when the request itself could
    /// not be presented; because HealthKit hides read-grant state, a `true` here means
    /// "the user saw the sheet", not "access was granted".
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isHealthDataAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType])
            return true
        } catch {
            print("[SleepHK] Authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Query the recent window, reconcile via the core, and persist inserts/updates.
    @discardableResult
    func importRecentSleep(
        days: Int = SleepHealthKitService.importWindowDays,
        into modelContext: ModelContext
    ) async -> SleepImportResult {
        guard isHealthDataAvailable else { return .unavailable }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let samples: [HKCategorySample]
        do {
            samples = try await fetchSleepSamples(predicate: predicate)
        } catch {
            print("[SleepHK] Sample query failed: \(error.localizedDescription)")
            return .failed("Could not read sleep from Apple Health.")
        }

        let segments = samples.compactMap(Self.segment(from:))

        let entries: [SleepEntry]
        do {
            entries = try modelContext.fetch(FetchDescriptor<SleepEntry>())
        } catch {
            print("[SleepHK] Could not load existing sleep entries: \(error.localizedDescription)")
            return .failed("Could not read existing sleep entries.")
        }

        let calendar = Calendar.current
        let existing = entries.map { entry in
            ExistingSleepProjection(
                id: entry.persistentModelID,
                wakeDayStart: calendar.startOfDay(for: entry.resolvedEndDate),
                start: entry.resolvedStartDate,
                end: entry.resolvedEndDate,
                isMainSleep: entry.episodeType == .mainSleep,
                source: entry.source
            )
        }
        let entriesByID = Dictionary(
            entries.map { ($0.persistentModelID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let plan = SleepHealthImportCore.plan(
            segments: segments,
            existing: existing,
            calendar: calendar
        )

        var inserted = 0
        var updated = 0
        for step in plan {
            switch step {
            case .insert(let candidate):
                // Imported nights carry no felt quality (rating 0 = unrated) and no shift
                // context; the aggregation core treats unrated nights correctly.
                let entry = SleepEntry(
                    startDate: candidate.start,
                    endDate: candidate.end,
                    qualityRating: 0,
                    shiftType: .off,
                    episodeType: .mainSleep,
                    source: .healthKit
                )
                modelContext.insert(entry)
                inserted += 1
            case .update(let id, let candidate):
                if let entry = entriesByID[id] {
                    entry.updateTiming(start: candidate.start, end: candidate.end)
                    updated += 1
                }
            case .skip:
                break
            }
        }

        if inserted > 0 || updated > 0 {
            guard PersistenceReporter.save(modelContext, operation: "Apple Health sleep import") else {
                modelContext.rollback()
                return .failed("Could not save imported sleep.")
            }
            SleepTrendStore.refresh(using: modelContext)
            DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        }

        UserDefaults.standard.set(Date(), forKey: AppSettingsKeys.healthKitSleepLastImport)
        return .completed(inserted: inserted, updated: updated)
    }

    // MARK: - HealthKit plumbing

    private func fetchSleepSamples(predicate: NSPredicate) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private static func segment(from sample: HKCategorySample) -> HealthSleepSegment? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
        let stage: HealthSleepStage
        switch value {
        case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            stage = .asleep
        case .inBed:
            stage = .inBed
        case .awake:
            stage = .awake
        @unknown default:
            return nil
        }
        return HealthSleepSegment(
            start: sample.startDate,
            end: sample.endDate,
            stage: stage,
            sourceName: sample.sourceRevision.source.name
        )
    }
    #else
    var isHealthDataAvailable: Bool { false }

    @discardableResult
    func requestAuthorization() async -> Bool { false }

    @discardableResult
    func importRecentSleep(
        days: Int = SleepHealthKitService.importWindowDays,
        into modelContext: ModelContext
    ) async -> SleepImportResult {
        .unavailable
    }
    #endif
}
