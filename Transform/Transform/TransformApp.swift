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
                if try ExerciseWeightStore.normalizeAndConsolidate(in: maintenanceContext) {
                    try maintenanceContext.save()
                }
                SleepTrendStore.refresh(using: maintenanceContext)
            } catch {
                maintenanceContext.rollback()
                maintenanceWarning = "Stored health or progression data could not be fully normalized at startup. The app loaded, but recent migrated entries may need review."
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

struct StartupErrorView: View {
    let message: String

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)

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
