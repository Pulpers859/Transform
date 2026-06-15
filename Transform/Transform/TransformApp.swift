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

            SleepTrendStore.refresh(using: maintenanceContext)
            DataIntegrityMonitor.checkOnStartup(using: maintenanceContext)

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
        let sleep: Int
        let weight: Int
        let nutrition: Int
        let measurement: Int
        let exerciseWeights: Int
        let exerciseLogs: Int
        let timestamp: Date

        init(sleep: Int, weight: Int, nutrition: Int, measurement: Int, exerciseWeights: Int = 0, exerciseLogs: Int = 0, timestamp: Date) {
            self.sleep = sleep
            self.weight = weight
            self.nutrition = nutrition
            self.measurement = measurement
            self.exerciseWeights = exerciseWeights
            self.exerciseLogs = exerciseLogs
            self.timestamp = timestamp
        }
    }

    static func checkOnStartup(using modelContext: ModelContext) {
        guard let previous = loadPreviousCounts() else {
            saveCounts(using: modelContext)
            return
        }

        guard let current = currentCounts(using: modelContext) else { return }

        let sleepDrop = previous.sleep - current.sleep
        let weightDrop = previous.weight - current.weight
        let nutritionDrop = previous.nutrition - current.nutrition
        let exerciseWeightDrop = previous.exerciseWeights - current.exerciseWeights
        let exerciseLogDrop = previous.exerciseLogs - current.exerciseLogs
        let totalDrop = (previous.sleep + previous.weight + previous.nutrition + previous.measurement + previous.exerciseWeights + previous.exerciseLogs)
                      - (current.sleep + current.weight + current.nutrition + current.measurement + current.exerciseWeights + current.exerciseLogs)

        if sleepDrop > 2 || weightDrop > 2 || nutritionDrop > 5 || exerciseLogDrop > 2 || totalDrop > 10 {
            print("[Integrity] DATA LOSS DETECTED at startup.")
            print("[Integrity] Previous (\(previous.timestamp)): sleep=\(previous.sleep) weight=\(previous.weight) nutrition=\(previous.nutrition) measurement=\(previous.measurement) exerciseWeights=\(previous.exerciseWeights) exerciseLogs=\(previous.exerciseLogs)")
            print("[Integrity] Current: sleep=\(current.sleep) weight=\(current.weight) nutrition=\(current.nutrition) measurement=\(current.measurement) exerciseWeights=\(current.exerciseWeights) exerciseLogs=\(current.exerciseLogs)")
            print("[Integrity] Drop: sleep=\(sleepDrop) weight=\(weightDrop) nutrition=\(nutritionDrop) exerciseWeights=\(exerciseWeightDrop) exerciseLogs=\(exerciseLogDrop) total=\(totalDrop)")
            NotificationCenter.default.post(
                name: .dataIntegrityWarning,
                object: nil,
                userInfo: ["message": "Data loss detected: \(totalDrop) entries missing since last launch. Check rolling backups in Documents folder."]
            )
        }

        saveCounts(using: modelContext)
    }

    private static func currentCounts(using modelContext: ModelContext) -> Counts? {
        do {
            return Counts(
                sleep: try modelContext.fetchCount(FetchDescriptor<SleepEntry>()),
                weight: try modelContext.fetchCount(FetchDescriptor<WeightEntry>()),
                nutrition: try modelContext.fetchCount(FetchDescriptor<NutritionEntry>()),
                measurement: try modelContext.fetchCount(FetchDescriptor<MeasurementEntry>()),
                exerciseWeights: try modelContext.fetchCount(FetchDescriptor<ExerciseWeightEntry>()),
                exerciseLogs: try modelContext.fetchCount(FetchDescriptor<ExercisePerformanceLog>()),
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
