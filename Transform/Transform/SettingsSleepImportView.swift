import SwiftUI
import SwiftData

/// Settings screen for the Apple Health sleep source. Turning this on lets the app read
/// the sleep interval Apple's own Sleep feature records (iPhone Sleep Schedule / Focus,
/// no Apple Watch required) so wake time comes from the phone instead of from when you
/// happened to open the app. Read-only, and it never overwrites a night you logged by
/// hand.
struct SettingsSleepImportView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettingsKeys.healthKitSleepImportEnabled) private var importEnabled = false

    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var lastImport: Date? =
        UserDefaults.standard.object(forKey: AppSettingsKeys.healthKitSleepLastImport) as? Date

    private var isAvailable: Bool { SleepHealthKitService.shared.isHealthDataAvailable }

    var body: some View {
        List {
            Section {
                Toggle("Import from Apple Health", isOn: Binding(
                    get: { importEnabled },
                    set: { handleToggle($0) }
                ))
                .disabled(isWorking || !isAvailable)

                if importEnabled {
                    Button {
                        Task { await runImport() }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            if isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isWorking)

                    LabeledContent("Last sync") {
                        Text(lastImportText).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Sleep Source")
            } footer: {
                Text(isAvailable
                    ? "Reads the sleep your iPhone already records and fills in nights you didn't log yourself. Apple Health access is read-only — Transform never writes sleep back."
                    : "Apple Health isn't available on this device, so sleep import can't be enabled here.")
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                howItWorksRow(
                    "1",
                    "Set up Sleep in the Health app",
                    "Health → Browse → Sleep → set a Sleep Schedule. Your iPhone then records when you're in bed and asleep — no Apple Watch needed."
                )
                howItWorksRow(
                    "2",
                    "Your hand logs always win",
                    "A night you logged yourself is never replaced by an import. Apple Health only fills days you left blank, and re-syncs update only its own entries."
                )
                howItWorksRow(
                    "3",
                    "Short blips are ignored",
                    "A brief in-bed moment or a nap won't be recorded as a full night, so a 2 a.m. phone check can't fake a short night and hold back your training."
                )
            } header: {
                Text("How it works")
            }
        }
        .navigationTitle("Sleep Source")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func howItWorksRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(TFColor.sleep)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var lastImportText: String {
        guard let lastImport else { return "Never" }
        return lastImport.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Actions

    private func handleToggle(_ newValue: Bool) {
        guard newValue else {
            importEnabled = false
            statusMessage = nil
            return
        }
        Task {
            isWorking = true
            // Presents Apple's permission sheet. HealthKit deliberately hides whether the
            // user granted read access, so a successful request is not proof of data — the
            // import result below is what we actually report.
            let presented = await SleepHealthKitService.shared.requestAuthorization()
            guard presented else {
                importEnabled = false
                isWorking = false
                statusMessage = "Apple Health isn't available on this device."
                return
            }
            importEnabled = true
            await runImport()
        }
    }

    private func runImport() async {
        isWorking = true
        defer { isWorking = false }

        let result = await SleepHealthKitService.shared.importRecentSleep(into: modelContext)
        lastImport = UserDefaults.standard.object(forKey: AppSettingsKeys.healthKitSleepLastImport) as? Date

        switch result {
        case .unavailable:
            importEnabled = false
            statusMessage = "Apple Health isn't available on this device."
        case .failed(let message):
            statusMessage = message
        case .completed(let inserted, let updated):
            if inserted == 0 && updated == 0 {
                statusMessage = "No new sleep to import. If you just turned this on, open Health → Browse → Sleep and make sure a Sleep Schedule is set up, then sync again."
            } else {
                var parts: [String] = []
                if inserted > 0 { parts.append("\(inserted) night\(inserted == 1 ? "" : "s") added") }
                if updated > 0 { parts.append("\(updated) updated") }
                statusMessage = parts.joined(separator: ", ") + "."
            }
        }
    }
}
