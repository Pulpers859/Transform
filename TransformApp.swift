import SwiftUI
import SwiftData

@main
struct TransformApp: App {
    private let startup: StartupConfiguration = StartupConfiguration.build()

    init() {
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

    static func build() -> StartupConfiguration {
        let schema = Schema([
            WeightEntry.self,
            MeasurementEntry.self,
            NutritionEntry.self,
            SavedNutritionProtocol.self,
            FavoriteFood.self,
            ProgressPhoto.self,
            BodyAnalysisSession.self,
            WorkoutProgram.self,
            WorkoutDay.self,
            WorkoutExercise.self,
            ExerciseWeightEntry.self
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
                if try ExerciseWeightStore.normalizeAndConsolidate(in: maintenanceContext) {
                    try maintenanceContext.save()
                }
            } catch {
                maintenanceContext.rollback()
                maintenanceWarning = "Stored exercise-weight summaries could not be normalized at startup. The app loaded, but some progression data may need review."
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
                // The in-memory store starts empty. If automatic backups kept running,
                // the first backgrounding would overwrite the last good on-disk backup
                // with an empty payload — exactly when that backup matters most.
                DataBackupManager.shared.suppressAutomaticBackups = true
                return StartupConfiguration(
                    container: fallbackContainer,
                    errorMessage: "Persistent storage failed to initialize. Running in temporary in-memory mode for this launch. Changes made now will not be saved permanently."
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
