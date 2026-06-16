import SwiftUI
import SwiftData

@main
struct TransformApp: App {
    private let startup: StartupConfiguration = StartupConfiguration.build()

    init() {
        AppSettingsStore.seedPersonalProfileIfNeeded()
        _ = AppLifecycleMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            if let container = startup.container {
                ContentView(startupWarning: startup.errorMessage)
                    .modelContainer(container)
            } else {
                StartupErrorView(message: startup.errorMessage ?? "Unknown startup error")
            }
        }
    }
}

struct StartupConfiguration {
    let container: ModelContainer?
    let errorMessage: String?

    @MainActor
    static func build() -> StartupConfiguration {
        let schema = Schema([
            WeightEntry.self,
            SleepEntry.self,
            MeasurementEntry.self,
            NutritionEntry.self,
            SavedNutritionProtocol.self,
            FavoriteFood.self,
            ProgressPhoto.self,
            BodyAnalysisSession.self,
            WorkoutProgram.self,
            WorkoutDay.self,
            WorkoutExercise.self,
            ExerciseWeightEntry.self,
            ExercisePerformanceLog.self
        ])

        let diskConfig = ModelConfiguration(
            "TransformStore",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [diskConfig])
            let maintenanceContext = ModelContext(container)
            var maintenanceWarning: String?

            do {
                try SleepEpisodeMigration.migrateIfNeeded(using: maintenanceContext)
            } catch {
                maintenanceContext.rollback()
                print("[Startup] Sleep migration failed: \(error.localizedDescription)")
            }

            do {
                var exerciseDataChanged = try ExerciseWeightStore.normalizePerformanceLogs(in: maintenanceContext)
                if try ExerciseWeightStore.normalizeAndConsolidate(in: maintenanceContext) {
                    exerciseDataChanged = true
                }
                if exerciseDataChanged {
                    try maintenanceContext.save()
                }
            } catch {
                maintenanceContext.rollback()
                print("[Startup] Exercise normalization failed: \(error.localizedDescription)")
                maintenanceWarning = "Stored progression data could not be fully normalized at startup. The app loaded, but recent entries may need review."
            }

            if let recoveryMessage = DataBackupManager.shared.attemptAutomaticRecoveryIfNeeded(using: maintenanceContext) {
                maintenanceWarning = [maintenanceWarning, recoveryMessage]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
            }

            SleepTrendStore.refresh(using: maintenanceContext)
            if let integrityMessage = DataIntegrityMonitor.checkOnStartup(using: maintenanceContext) {
                maintenanceWarning = [maintenanceWarning, integrityMessage]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
            }

            return StartupConfiguration(container: container, errorMessage: maintenanceWarning)
        } catch {
            let fallback = ModelConfiguration(
                "TransformStoreFallback",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            do {
                let fallbackContainer = try ModelContainer(for: schema, configurations: [fallback])
                // Don't let this empty ephemeral store overwrite the last good
                // on-disk backup when the app next backgrounds.
                DataBackupManager.shared.suppressAutomaticBackups = true
                // Recover the last good on-disk backup into the ephemeral store so a
                // storage failure shows the user's data for this session instead of an
                // empty app. The restore is additive/dedupe-guarded and suppressing
                // auto-backups above prevents it from overwriting the good file.
                let recoveryContext = ModelContext(fallbackContainer)
                let restored = DataBackupManager.shared.restoreFromAutomaticBackupIfAvailable(into: recoveryContext)
                let fallbackMessage = restored
                    ? "Persistent storage failed to initialize. Your most recent backup has been loaded for this session, but changes made now will not be saved permanently. Relaunch to retry permanent storage."
                    : "Persistent storage failed to initialize. Running in temporary in-memory mode for this launch. Changes made now will not be saved permanently."
                return StartupConfiguration(
                    container: fallbackContainer,
                    errorMessage: fallbackMessage
                )
            } catch {
                return StartupConfiguration(
                    container: nil,
                    errorMessage: "App startup failed: could not initialize data storage."
                )
            }
        }
    }
}

// MARK: - Data Integrity Monitor

enum DataIntegrityMonitor {
    private static let countsKey = "transform.startupEntryCounts"

    struct Counts: Codable {
        let entries: DataBackupManager.EntryCounts
        let timestamp: Date

        private enum CodingKeys: String, CodingKey {
            case entries
            case timestamp
            case sleep
            case weight
            case nutrition
            case measurement
            case exerciseWeights
            case exerciseLogs
        }

        init(entries: DataBackupManager.EntryCounts, timestamp: Date) {
            self.entries = entries
            self.timestamp = timestamp
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()

            if let decodedEntries = try container.decodeIfPresent(DataBackupManager.EntryCounts.self, forKey: .entries) {
                entries = decodedEntries
                return
            }

            entries = DataBackupManager.EntryCounts(
                sleep: try container.decodeIfPresent(Int.self, forKey: .sleep) ?? 0,
                weight: try container.decodeIfPresent(Int.self, forKey: .weight) ?? 0,
                nutrition: try container.decodeIfPresent(Int.self, forKey: .nutrition) ?? 0,
                measurement: try container.decodeIfPresent(Int.self, forKey: .measurement) ?? 0,
                exerciseWeights: try container.decodeIfPresent(Int.self, forKey: .exerciseWeights) ?? 0,
                exerciseLogs: try container.decodeIfPresent(Int.self, forKey: .exerciseLogs) ?? 0
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(entries, forKey: .entries)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }

    static func checkOnStartup(using modelContext: ModelContext) -> String? {
        guard let previous = loadPreviousCounts() else {
            saveCounts(using: modelContext)
            return nil
        }

        guard let current = currentCounts(using: modelContext) else { return nil }

        if current.entries.hasSignificantDrop(comparedTo: previous.entries) {
            print("[Integrity] DATA LOSS DETECTED at startup.")
            print("[Integrity] Previous (\(previous.timestamp)): \(previous.entries.debugSummary)")
            print("[Integrity] Current: \(current.entries.debugSummary)")
            print("[Integrity] Drop: \(current.entries.dropSummary(comparedTo: previous.entries))")
            let totalDrop = previous.entries.total - current.entries.total
            let message = "Data loss detected: \(totalDrop) entries missing since last launch. Check the rolling backup and export a manual backup before making more changes."
            NotificationCenter.default.post(
                name: .dataIntegrityWarning,
                object: nil,
                userInfo: ["message": message]
            )
            saveCounts(using: modelContext)
            return message
        }

        saveCounts(using: modelContext)
        return nil
    }

    private static func currentCounts(using modelContext: ModelContext) -> Counts? {
        do {
            return Counts(
                entries: try DataBackupManager.shared.entryCounts(using: modelContext),
                timestamp: Date()
            )
        } catch {
            print("[Integrity] Could not fetch entry counts: \(error.localizedDescription)")
            return nil
        }
    }

    private static func saveCounts(using modelContext: ModelContext) {
        guard let counts = currentCounts(using: modelContext),
              let data = try? JSONEncoder().encode(counts) else { return }
        UserDefaults.standard.set(data, forKey: countsKey)
    }

    private static func loadPreviousCounts() -> Counts? {
        guard let data = UserDefaults.standard.data(forKey: countsKey) else { return nil }
        return try? JSONDecoder().decode(Counts.self, from: data)
    }
}

extension Notification.Name {
    static let dataIntegrityWarning = Notification.Name("transform.dataIntegrityWarning")
}

struct StartupErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(TFColor.accent)

                Text("Transform Could Not Start")
                    .font(.title2.bold())

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Try relaunching the app. If this persists, export/restore from backup once storage is available.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }
}
