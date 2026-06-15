import SwiftUI
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showRestoreDefaultsConfirm = false
    @State private var showDeleteAPIKeyConfirm = false
    @State private var apiKeySetupPresentation: APIKeySetupPresentation?
    @State private var hasAnthropicAPIKey = Config.hasAnthropicKey
    @State private var hasKeychainAPIKey = AnthropicAPIKeyStore.storedKey != nil
    @State private var apiKeyErrorMessage: String?
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceMode = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SettingsProfileView()
                    } label: {
                        Label("Profile", systemImage: "person.fill")
                    }

                    NavigationLink {
                        SettingsTargetsView()
                    } label: {
                        Label("Targets", systemImage: "target")
                    }

                    NavigationLink {
                        SettingsMedicalView()
                    } label: {
                        Label("Medical Screening", systemImage: "heart.text.clipboard")
                    }
                } header: {
                    Text("You")
                }

                Section {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                }

                Section {
                    LabeledContent("Anthropic API Key") {
                        Text(hasAnthropicAPIKey ? "Configured" : "Not Configured")
                            .foregroundStyle(hasAnthropicAPIKey ? TFColor.success : Color.secondary)
                    }

                    Button(hasKeychainAPIKey ? "Replace API Key" : "Add API Key") {
                        apiKeySetupPresentation = .settings
                    }

                    if hasKeychainAPIKey {
                        Button("Remove API Key", role: .destructive) {
                            showDeleteAPIKeyConfirm = true
                        }
                    }

                    if let apiKeyErrorMessage {
                        Text(apiKeyErrorMessage)
                            .font(.caption)
                            .foregroundStyle(TFColor.danger)
                    } else {
                        Text("Keys are stored in this device's Keychain and never committed to GitHub.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI")
                }

                Section {
                    Button("Restore All Defaults", role: .destructive) {
                        showRestoreDefaultsConfirm = true
                    }
                } footer: {
                    Text("Replaces all profile, target, and medical settings with app defaults.")
                }
            }
            .confirmationDialog(
                "Restore Defaults?",
                isPresented: $showRestoreDefaultsConfirm,
                titleVisibility: .visible
            ) {
                Button("Restore Defaults", role: .destructive) {
                    restoreDefaults()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This replaces all your saved profile and target settings with the app defaults.")
            }
            .confirmationDialog(
                "Remove API Key?",
                isPresented: $showDeleteAPIKeyConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove API Key", role: .destructive) {
                    deleteAPIKey()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("AI features will be unavailable unless a local build configuration provides another key.")
            }
            .sheet(item: $apiKeySetupPresentation) { presentation in
                APIKeySetupView(presentation: presentation) {
                    refreshAPIKeyStatus()
                }
            }
            .onAppear {
                refreshAPIKeyStatus()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
    }

    private func refreshAPIKeyStatus() {
        hasKeychainAPIKey = AnthropicAPIKeyStore.storedKey != nil
        hasAnthropicAPIKey = Config.hasAnthropicKey
        apiKeyErrorMessage = nil
    }

    private func deleteAPIKey() {
        do {
            try AnthropicAPIKeyStore.delete()
            refreshAPIKeyStatus()
        } catch {
            apiKeyErrorMessage = error.localizedDescription
        }
    }

    private func restoreDefaults() {
        let keys = AppSettingsKeys.self
        let seed = PersonalProfileSeed.self

        UserDefaults.standard.set(seed.ageValue, forKey: keys.analysisAgeValue)
        UserDefaults.standard.set(seed.sex, forKey: keys.analysisSex)
        UserDefaults.standard.set(seed.build, forKey: keys.analysisBuild)
        UserDefaults.standard.set(seed.heightFeet, forKey: keys.analysisHeightFeet)
        UserDefaults.standard.set(seed.heightInches, forKey: keys.analysisHeightInches)
        UserDefaults.standard.set(seed.heightCm, forKey: keys.analysisHeightCm)
        UserDefaults.standard.set(seed.heightUnit, forKey: keys.analysisHeightUnit)
        UserDefaults.standard.set(seed.weightValue, forKey: keys.analysisWeightValue)
        UserDefaults.standard.set(seed.weightUnit, forKey: keys.analysisWeightUnit)
        UserDefaults.standard.set(seed.occupation, forKey: keys.analysisOccupation)
        UserDefaults.standard.set(seed.trainingDays, forKey: keys.analysisTrainingDays)
        UserDefaults.standard.set(seed.trainingAge, forKey: keys.analysisTrainingAge)
        UserDefaults.standard.set(seed.equipmentAccess, forKey: keys.analysisEquipmentAccess)
        UserDefaults.standard.set(String(format: "%.1f", seed.sleepHours), forKey: keys.analysisSleepHours)
        UserDefaults.standard.set(seed.sleepNotes, forKey: keys.analysisSleepNotes)
        UserDefaults.standard.set(seed.painHistory, forKey: keys.analysisPainHistory)
        UserDefaults.standard.set(ActivityLevel.veryActive.rawValue, forKey: keys.analysisActivityLevel)
        UserDefaults.standard.set(GoalCategory.recomposition.rawValue, forKey: keys.analysisPrimaryGoal)
        UserDefaults.standard.set(seed.goalDetail, forKey: keys.analysisGoalDetail)
        UserDefaults.standard.set(seed.lifestyleConstraints, forKey: keys.analysisLifestyleConstraints)

        UserDefaults.standard.set(false, forKey: keys.medicalCurrentInjury)
        UserDefaults.standard.set(false, forKey: keys.medicalPainDuringExercise)
        UserDefaults.standard.set(false, forKey: keys.medicalCardioMetabolic)
        UserDefaults.standard.set(false, forKey: keys.medicalMedications)
        UserDefaults.standard.set(false, forKey: keys.medicalPregnancySurgery)
        UserDefaults.standard.set(false, forKey: keys.medicalSymptoms)

        UserDefaults.standard.set(String(Config.defaultCalorieTarget), forKey: keys.calorieTarget)
        UserDefaults.standard.set(String(format: "%.0f", Config.defaultProteinTargetG), forKey: keys.proteinTarget)
        UserDefaults.standard.set(String(format: "%.0f", Config.defaultCarbTargetG), forKey: keys.carbTarget)
        UserDefaults.standard.set(String(format: "%.0f", Config.defaultFatTargetG), forKey: keys.fatTarget)
        UserDefaults.standard.set(String(format: "%.0f", Config.defaultBodyWeightGoalLbs), forKey: keys.bodyWeightGoal)
        UserDefaults.standard.set(0, forKey: keys.appearanceMode)
        appearanceMode = 0
    }
}

// MARK: - Profile Sub-View

struct SettingsProfileView: View {
    @FocusState private var isTextInputFocused: Bool

    @AppStorage(AppSettingsKeys.analysisAgeValue) private var ageValue = 0
    @AppStorage(AppSettingsKeys.analysisSex) private var analysisSex = Config.defaultAnalysisSex
    @AppStorage(AppSettingsKeys.analysisBuild) private var analysisBuild = Config.defaultAnalysisBuild
    @AppStorage(AppSettingsKeys.analysisHeightFeet) private var heightFeet = 0
    @AppStorage(AppSettingsKeys.analysisHeightInches) private var heightInches = 0
    @AppStorage(AppSettingsKeys.analysisHeightCm) private var heightCm = 0
    @AppStorage(AppSettingsKeys.analysisHeightUnit) private var heightUnit = HeightUnit.imperial.rawValue
    @AppStorage(AppSettingsKeys.analysisWeightValue) private var weightValue = ""
    @AppStorage(AppSettingsKeys.analysisWeightUnit) private var weightUnit = WeightUnit.lb.rawValue
    @AppStorage(AppSettingsKeys.analysisOccupation) private var analysisOccupation = Config.defaultAnalysisOccupation
    @AppStorage(AppSettingsKeys.analysisTrainingDays) private var trainingDays = 0
    @AppStorage(AppSettingsKeys.analysisTrainingAge) private var analysisTrainingAge = Config.defaultAnalysisTrainingAge
    @AppStorage(AppSettingsKeys.analysisEquipmentAccess) private var analysisEquipmentAccess = Config.defaultAnalysisEquipmentAccess
    @AppStorage(AppSettingsKeys.analysisSleepHours) private var sleepHoursStr = ""
    @AppStorage(AppSettingsKeys.analysisSleepNotes) private var sleepNotes = ""
    @AppStorage(AppSettingsKeys.analysisPainHistory) private var analysisPainHistory = Config.defaultAnalysisPainHistory
    @AppStorage(AppSettingsKeys.analysisActivityLevel) private var analysisActivityLevel = Config.defaultAnalysisActivityLevel
    @AppStorage(AppSettingsKeys.analysisPrimaryGoal) private var analysisPrimaryGoal = Config.defaultAnalysisPrimaryGoal
    @AppStorage(AppSettingsKeys.analysisGoalDetail) private var analysisGoalDetail = Config.defaultAnalysisGoalDetail
    @AppStorage(AppSettingsKeys.analysisLifestyleConstraints) private var analysisLifestyleConstraints = Config.defaultAnalysisLifestyleConstraints

    private var sexBinding: Binding<SexOption> {
        Binding(
            get: { SexOption(rawValue: analysisSex) ?? .notSpecified },
            set: { analysisSex = $0.rawValue }
        )
    }

    private var weightUnitBinding: Binding<WeightUnit> {
        Binding(
            get: { WeightUnit(rawValue: weightUnit) ?? .lb },
            set: { weightUnit = $0.rawValue }
        )
    }

    private var heightUnitBinding: Binding<HeightUnit> {
        Binding(
            get: { HeightUnit(rawValue: heightUnit) ?? .imperial },
            set: { newUnit in
                if newUnit == .metric && HeightUnit(rawValue: heightUnit) == .imperial {
                    let totalInches = heightFeet * 12 + heightInches
                    if totalInches > 0 { heightCm = Int(round(Double(totalInches) * 2.54)) }
                } else if newUnit == .imperial && HeightUnit(rawValue: heightUnit) == .metric {
                    if heightCm > 0 {
                        let roundedTotalInches = Int(round(Double(heightCm) / 2.54))
                        heightFeet = roundedTotalInches / 12
                        heightInches = roundedTotalInches % 12
                    }
                }
                heightUnit = newUnit.rawValue
            }
        )
    }

    private var activityBinding: Binding<ActivityLevel> {
        Binding(
            get: { ActivityLevel(rawValue: analysisActivityLevel) ?? .notSpecified },
            set: { analysisActivityLevel = $0.rawValue }
        )
    }

    private var buildBinding: Binding<BuildProfileOption> {
        Binding(
            get: { BuildProfileOption.fromStoredValue(analysisBuild) },
            set: { analysisBuild = $0.rawValue }
        )
    }

    private var trainingExperienceBinding: Binding<TrainingExperienceOption> {
        Binding(
            get: { TrainingExperienceOption.fromStoredValue(analysisTrainingAge) },
            set: { analysisTrainingAge = $0.rawValue }
        )
    }

    private var equipmentAccessBinding: Binding<EquipmentAccessOption> {
        Binding(
            get: { EquipmentAccessOption.fromStoredValue(analysisEquipmentAccess) },
            set: { analysisEquipmentAccess = $0.rawValue }
        )
    }

    private var goalBinding: Binding<GoalCategory> {
        Binding(
            get: { GoalCategory(rawValue: analysisPrimaryGoal) ?? .notSpecified },
            set: {
                analysisPrimaryGoal = $0.rawValue
                analysisGoalDetail = $0.defaultDetail
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Text("These fields shape the body-analysis prompt and make the assessment smarter than photos alone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Basics") {
                Stepper("Age: \(ageValue > 0 ? "\(ageValue)" : "—")", value: $ageValue, in: 0...120)

                Picker("Sex / Gender", selection: sexBinding) {
                    ForEach(SexOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                presetPicker("Build", selection: buildBinding)
                presetHint(buildBinding.wrappedValue.promptDescription)
            }

            Section("Body") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Height Unit", selection: heightUnitBinding) {
                        ForEach(HeightUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)

                    if HeightUnit(rawValue: heightUnit) == .metric {
                        HStack {
                            Text("Height")
                            Spacer()
                            TextField("cm", value: $heightCm, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                                .focused($isTextInputFocused)
                            Text("cm")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text("Height")
                            Spacer()
                            TextField("ft", value: $heightFeet, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                                .focused($isTextInputFocused)
                            Text("ft")
                                .foregroundStyle(.secondary)
                            TextField("in", value: $heightInches, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                                .focused($isTextInputFocused)
                            Text("in")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Text("Current Weight")
                    Spacer()
                    TextField("0", text: $weightValue)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .focused($isTextInputFocused)
                    Picker("", selection: weightUnitBinding) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                }
            }

            Section("Training") {
                settingsField("Occupation", text: $analysisOccupation)

                Stepper("Training: \(trainingDays > 0 ? "\(trainingDays) days/week" : "—")", value: $trainingDays, in: 0...7)

                presetPicker("Training Age / Experience", selection: trainingExperienceBinding)
                presetHint(trainingExperienceBinding.wrappedValue.promptDescription)

                presetPicker("Equipment Access", selection: equipmentAccessBinding)
                presetHint(equipmentAccessBinding.wrappedValue.promptDescription)

                Picker("Activity Level", selection: activityBinding) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                if let hint = ActivityLevel(rawValue: analysisActivityLevel)?.hint, !hint.isEmpty {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recovery") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Avg Sleep")
                        Spacer()
                        TextField("0", text: $sleepHoursStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                            .focused($isTextInputFocused)
                        Text("hrs/night")
                            .foregroundStyle(.secondary)
                    }
                    TextField("Recovery notes (optional)", text: $sleepNotes, axis: .vertical)
                        .lineLimit(2...3)
                        .textInputAutocapitalization(.sentences)
                        .font(.subheadline)
                        .focused($isTextInputFocused)
                }

                settingsField("Pain / Injury Context", text: $analysisPainHistory, axis: .vertical)
            }

            Section("Goals") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Primary Goal", selection: goalBinding) {
                        ForEach(GoalCategory.allCases) { goal in
                            Text(goal.label).tag(goal)
                        }
                    }
                    if GoalCategory(rawValue: analysisPrimaryGoal) != .notSpecified {
                        TextField("Goal detail (optional)", text: $analysisGoalDetail, axis: .vertical)
                            .lineLimit(2...4)
                            .textInputAutocapitalization(.sentences)
                            .font(.subheadline)
                            .focused($isTextInputFocused)
                    }
                }

                settingsField("Lifestyle Constraints", text: $analysisLifestyleConstraints, axis: .vertical)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    normalizeHeightInputs()
                    isTextInputFocused = false
                }
            }
        }
        .onDisappear {
            normalizeHeightInputs()
        }
    }

    private func normalizeHeightInputs() {
        if heightFeet > 0 {
            heightFeet = min(max(heightFeet, 3), 8)
        }
        heightInches = min(max(heightInches, 0), 11)
        if heightCm > 0 {
            heightCm = min(max(heightCm, 100), 250)
        }
    }

    @ViewBuilder
    private func settingsField(
        _ title: String,
        text: Binding<String>,
        suffix: String? = nil,
        keyboard: UIKeyboardType = .default,
        axis: Axis = .horizontal
    ) -> some View {
        if axis == .vertical {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                TextField(title, text: text, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .focused($isTextInputFocused)
            }
        } else {
            HStack {
                Text(title)
                Spacer()
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .focused($isTextInputFocused)
                if let suffix {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func presetPicker<Option: ProfilePresetOption>(
        _ title: String,
        selection: Binding<Option>
    ) -> some View where Option.AllCases: RandomAccessCollection, Option.AllCases.Element == Option {
        Picker(title, selection: selection) {
            ForEach(Option.allCases) { option in
                Text(option.label).tag(option)
            }
        }
    }

    @ViewBuilder
    private func presetHint(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Targets Sub-View

struct SettingsTargetsView: View {
    @FocusState private var isTextInputFocused: Bool

    @AppStorage(AppSettingsKeys.calorieTarget) private var calorieTarget = String(Config.defaultCalorieTarget)
    @AppStorage(AppSettingsKeys.proteinTarget) private var proteinTarget = String(format: "%.0f", Config.defaultProteinTargetG)
    @AppStorage(AppSettingsKeys.carbTarget) private var carbTarget = String(format: "%.0f", Config.defaultCarbTargetG)
    @AppStorage(AppSettingsKeys.fatTarget) private var fatTarget = String(format: "%.0f", Config.defaultFatTargetG)
    @AppStorage(AppSettingsKeys.bodyWeightGoal) private var bodyWeightGoal = String(format: "%.0f", Config.defaultBodyWeightGoalLbs)

    var body: some View {
        Form {
            Section {
                Text("Used by Dashboard and Nutrition when no fresh AI-derived macro targets exist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Macros") {
                targetField("Calories", text: $calorieTarget, suffix: "kcal", keyboard: .numberPad)
                targetField("Protein", text: $proteinTarget, suffix: "g", keyboard: .decimalPad)
                targetField("Carbs", text: $carbTarget, suffix: "g", keyboard: .decimalPad)
                targetField("Fat", text: $fatTarget, suffix: "g", keyboard: .decimalPad)
            }

            Section("Weight") {
                targetField("Body Weight Goal", text: $bodyWeightGoal, suffix: "lb", keyboard: .decimalPad)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Targets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isTextInputFocused = false }
            }
        }
    }

    private func targetField(_ title: String, text: Binding<String>, suffix: String, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .focused($isTextInputFocused)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medical Sub-View

struct SettingsMedicalView: View {
    @AppStorage(AppSettingsKeys.medicalCurrentInjury) private var medicalCurrentInjury = false
    @AppStorage(AppSettingsKeys.medicalPainDuringExercise) private var medicalPainDuringExercise = false
    @AppStorage(AppSettingsKeys.medicalCardioMetabolic) private var medicalCardioMetabolic = false
    @AppStorage(AppSettingsKeys.medicalMedications) private var medicalMedications = false
    @AppStorage(AppSettingsKeys.medicalPregnancySurgery) private var medicalPregnancySurgery = false
    @AppStorage(AppSettingsKeys.medicalSymptoms) private var medicalSymptoms = false

    var body: some View {
        Form {
            Section {
                Text("Answer these so the app can flag when medical clearance may be appropriate before high-intensity training. These are not a diagnosis — consult your physician.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Current injury", isOn: $medicalCurrentInjury)
                Toggle("Pain during exercise", isOn: $medicalPainDuringExercise)
                Toggle("Heart / metabolic / kidney / BP condition", isOn: $medicalCardioMetabolic)
                Toggle("Medication affecting HR, BP, balance, or glucose", isOn: $medicalMedications)
                Toggle("Pregnant, postpartum, or recent surgery", isOn: $medicalPregnancySurgery)
                Toggle("Dizziness, chest pain, fainting, or unusual SOB", isOn: $medicalSymptoms)
            }
        }
        .navigationTitle("Medical Screening")
        .navigationBarTitleDisplayMode(.inline)
    }
}
