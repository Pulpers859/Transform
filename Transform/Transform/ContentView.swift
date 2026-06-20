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
    @State private var apiKeySetupPresentation: APIKeySetupPresentation?

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
        .tint(TFColor.accent)
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
                    message: startupWarning,
                    onDismiss: showAPIKeySetupIfNeeded
                )
            } else if !didShowStartupWarning, let generationCrash = WorkoutGenerationDiagnostics.consumeUnexpectedTerminationMessage() {
                didShowStartupWarning = true
                appAlert = AppAlertContent(
                    title: "Generation Interrupted",
                    message: generationCrash,
                    onDismiss: showAPIKeySetupIfNeeded
                )
            } else if !didShowStartupWarning {
                didShowStartupWarning = true
                showAPIKeySetupIfNeeded()
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
        .onReceive(NotificationCenter.default.publisher(for: .dataIntegrityWarning)) { notification in
            let fallbackMessage = "Stored data looks incomplete compared with the last launch. Check your rolling backup and export a manual backup before making more changes."
            let message = (notification.userInfo?[PersistenceReporter.messageUserInfoKey] as? String)
                ?? (notification.userInfo?["message"] as? String)
                ?? fallbackMessage
            appAlert = AppAlertContent(
                title: "Data Integrity Warning",
                message: message
            )
        }
        .alert(item: $appAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    alert.onDismiss?()
                }
            )
        }
        .sheet(item: $apiKeySetupPresentation) { presentation in
            APIKeySetupView(presentation: presentation) {}
        }
    }

    private func showAPIKeySetupIfNeeded() {
        if !Config.hasAnthropicKey {
            apiKeySetupPresentation = .startup
        }
    }
}

struct AppAlertContent: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let onDismiss: (() -> Void)?

    init(title: String, message: String, onDismiss: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.onDismiss = onDismiss
    }
}
