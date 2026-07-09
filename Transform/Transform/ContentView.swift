import SwiftUI
import Foundation
import Combine
import UIKit
import Observation

// MARK: - Tabs

enum AppTab: Hashable {
    case dashboard
    case analysis
    case workout
    case nutrition
}

// MARK: - Day Clock

/// Single refreshing source for "today". Date-derived dashboard state (today's
/// rings, greeting, 7-day windows) reads `today` so it invalidates when the
/// calendar day rolls over or the clock changes — without a per-minute
/// TimelineView re-evaluating the whole tree. Refreshed on significant time
/// changes (midnight, DST, carrier time) and on foreground activation.
@Observable
final class DayClock {
    private(set) var today: Date = Calendar.current.startOfDay(for: Date())

    func refresh() {
        let newToday = Calendar.current.startOfDay(for: Date())
        if newToday != today {
            today = newToday
        }
    }
}

// MARK: - Workout Deep Link

/// Lets the dashboard's training card land on the matching day page inside the
/// Workout tab: the dashboard posts the day number and switches tabs; the
/// Workout tab consumes the request and pushes the detail view.
@Observable
final class WorkoutDeepLink {
    var pendingDayNumber: Int?
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceMode = 0
    let startupWarning: String?
    @State private var didShowStartupWarning = false
    @State private var appAlert: AppAlertContent?
    @State private var apiKeySetupPresentation: APIKeySetupPresentation?
    @State private var selectedTab: AppTab = .dashboard
    @State private var dayClock = DayClock()
    @State private var workoutDeepLink = WorkoutDeepLink()
    @State private var bodyAnalysisRunStore = BodyAnalysisRunStore()

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
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppTab.dashboard)

            BodyAnalysisView()
                .tabItem {
                    Label("Analysis", systemImage: "camera.viewfinder")
                }
                .tag(AppTab.analysis)

            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.strengthtraining.traditional")
                }
                .tag(AppTab.workout)

            NutritionView()
                .tabItem {
                    Label("Nutrition", systemImage: "fork.knife")
                }
                .tag(AppTab.nutrition)
        }
        .environment(dayClock)
        .environment(workoutDeepLink)
        .environment(bodyAnalysisRunStore)
        .preferredColorScheme(resolvedColorScheme)
        .tint(TFColor.accent)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                dayClock.refresh()
            }
            if newPhase == .inactive || newPhase == .background {
                if !WorkoutGenerationDiagnostics.isActive {
                    DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            dayClock.refresh()
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
