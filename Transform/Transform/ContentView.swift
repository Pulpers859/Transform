import SwiftUI
import Foundation
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceMode = 0
    let startupWarning: String?
    @State private var didShowStartupWarning = false
    @State private var appAlert: AppAlertContent?

    var resolvedColorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    init(startupWarning: String? = nil) {
        self.startupWarning = startupWarning
    }

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }

            BodyAnalysisView()
                .tabItem {
                    Label("Analysis", systemImage: "camera.viewfinder")
                }

            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }

            NutritionView()
                .tabItem {
                    Label("Nutrition", systemImage: "fork.knife")
                }
        }
        .preferredColorScheme(resolvedColorScheme)
        .tint(.orange)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                if !WorkoutGenerationDiagnostics.isActive {
                    DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
                }
            }
        }
        .onAppear {
            if !didShowStartupWarning, let startupWarning {
                didShowStartupWarning = true
                appAlert = AppAlertContent(
                    title: "Storage Warning",
                    message: startupWarning
                )
            } else if !didShowStartupWarning, let generationCrash = WorkoutGenerationDiagnostics.consumeUnexpectedTerminationMessage() {
                didShowStartupWarning = true
                appAlert = AppAlertContent(
                    title: "Generation Interrupted",
                    message: generationCrash
                )
            } else if !didShowStartupWarning, let apiKeyWarning = Config.anthropicKeyStartupAlertMessage {
                didShowStartupWarning = true
                appAlert = AppAlertContent(
                    title: "API Key Setup",
                    message: apiKeyWarning
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .persistenceSaveFailed)) { notification in
            let fallbackMessage = "A save operation failed. Your recent changes may not be stored."
            let message = (notification.userInfo?[PersistenceReporter.messageUserInfoKey] as? String) ?? fallbackMessage
            appAlert = AppAlertContent(
                title: "Save Failed",
                message: message
            )
        }
        .alert(item: $appAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct AppAlertContent: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
