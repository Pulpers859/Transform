import SwiftUI
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextInputFocused: Bool
    @State private var showRestoreDefaultsConfirm = false

    // MARK: - Structured fields

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

    // MARK: - Medical screening

    @AppStorage(AppSettingsKeys.medicalCurrentInjury) private var medicalCurrentInjury = false
    @AppStorage(AppSettingsKeys.medicalPainDuringExercise) private var medicalPainDuringExercise = false
    @AppStorage(AppSettingsKeys.medicalCardioMetabolic) private var medicalCardioMetabolic = false
    @AppStorage(AppSettingsKeys.medicalMedications) private var medicalMedications = false
    @AppStorage(AppSettingsKeys.medicalPregnancySurgery) private var medicalPregnancySurgery = false
    @AppStorage(AppSettingsKeys.medicalSymptoms) private var medicalSymptoms = false

    // MARK: - Fallback targets

    @AppStorage(AppSettingsKeys.calorieTarget) private var calorieTarget = String(Config.defaultCalorieTarget)
    @AppStorage(AppSettingsKeys.proteinTarget) private var proteinTarget = String(format: "%.0f", Config.defaultProteinTargetG)
    @AppStorage(AppSettingsKeys.carbTarget) private var carbTarget = String(format: "%.0f", Config.defaultCarbTargetG)
    @AppStorage(AppSettingsKeys.fatTarget) private var fatTarget = String(format: "%.0f", Config.defaultFatTargetG)
    @AppStorage(AppSettingsKeys.bodyWeightGoal) private var bodyWeightGoal = String(format: "%.0f", Config.defaultBodyWeightGoalLbs)
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceMode = 0

    // MARK: - Bindings

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

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Body Analysis Profile") {
                    Text("These fields shape the body-analysis prompt and make the assessment smarter than photos alone. Leave a field blank only if you truly want that detail treated as unknown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Stepper("Age: \(ageValue > 0 ? "\(ageValue)" : "—")", value: $ageValue, in: 0...120)

                    Picker("Sex / Gender", selection: sexBinding) {
                        ForEach(SexOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    presetPicker("Build", selection: buildBinding)
                    presetHint(buildBinding.wrappedValue.promptDescription)

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

                    settingsField("Occupation", text: $analysisOccupation)

                    Stepper("Training: \(trainingDays > 0 ? "\(trainingDays) days/week" : "—")", value: $trainingDays, in: 0...7)

                    presetPicker("Training Age / Experience", selection: trainingExperienceBinding)
                    presetHint(trainingExperienceBinding.wrappedValue.promptDescription)

                    presetPicker("Equipment Access", selection: equipmentAccessBinding)
                    presetHint(equipmentAccessBinding.wrappedValue.promptDescription)

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

                Section {
                    Text("Answer these so the app can flag when medical clearance may be appropriate before high-intensity training. These are not a diagnosis — consult your physician.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Current injury", isOn: $medicalCurrentInjury)
                    Toggle("Pain during exercise", isOn: $medicalPainDuringExercise)
                    Toggle("Heart / metabolic / kidney / BP condition", isOn: $medicalCardioMetabolic)
                    Toggle("Medication affecting HR, BP, balance, or glucose", isOn: $medicalMedications)
                    Toggle("Pregnant, postpartum, or recent surgery", isOn: $medicalPregnancySurgery)
                    Toggle("Dizziness, chest pain, fainting, or unusual SOB", isOn: $medicalSymptoms)
                } header: {
                    Text("Medical Screening")
                }

                Section("Fallback Targets") {
                    Text("These are used by Dashboard and Nutrition when no fresh AI-derived macro targets exist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    settingsField("Calories", text: $calorieTarget, suffix: "kcal", keyboard: .numberPad)
                    settingsField("Protein", text: $proteinTarget, suffix: "g", keyboard: .decimalPad)
                    settingsField("Carbs", text: $carbTarget, suffix: "g", keyboard: .decimalPad)
                    settingsField("Fat", text: $fatTarget, suffix: "g", keyboard: .decimalPad)
                    settingsField("Body Weight Goal", text: $bodyWeightGoal, suffix: "lb", keyboard: .decimalPad)
                }

                Section {
                    Button("Restore Defaults", role: .destructive) {
                        showRestoreDefaultsConfirm = true
                    }
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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        normalizeHeightInputs()
                        dismiss()
                    }
                    .bold()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        normalizeHeightInputs()
                        isTextInputFocused = false
                    }
                }
            }
        }
    }

    // MARK: - Helpers

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

    private func normalizeHeightInputs() {
        if heightFeet > 0 {
            heightFeet = min(max(heightFeet, 3), 8)
        }
        heightInches = min(max(heightInches, 0), 11)
        if heightCm > 0 {
            heightCm = min(max(heightCm, 100), 250)
        }
    }

    private func restoreDefaults() {
        ageValue = PersonalProfileSeed.ageValue
        analysisSex = PersonalProfileSeed.sex
        analysisBuild = PersonalProfileSeed.build
        heightFeet = PersonalProfileSeed.heightFeet
        heightInches = PersonalProfileSeed.heightInches
        heightCm = PersonalProfileSeed.heightCm
        heightUnit = PersonalProfileSeed.heightUnit
        weightValue = PersonalProfileSeed.weightValue
        weightUnit = PersonalProfileSeed.weightUnit
        analysisOccupation = PersonalProfileSeed.occupation
        trainingDays = PersonalProfileSeed.trainingDays
        analysisTrainingAge = PersonalProfileSeed.trainingAge
        analysisEquipmentAccess = PersonalProfileSeed.equipmentAccess
        sleepHoursStr = String(format: "%.1f", PersonalProfileSeed.sleepHours)
        sleepNotes = PersonalProfileSeed.sleepNotes
        analysisPainHistory = PersonalProfileSeed.painHistory
        analysisActivityLevel = ActivityLevel.veryActive.rawValue
        analysisPrimaryGoal = GoalCategory.recomposition.rawValue
        analysisGoalDetail = PersonalProfileSeed.goalDetail
        analysisLifestyleConstraints = PersonalProfileSeed.lifestyleConstraints

        medicalCurrentInjury = false
        medicalPainDuringExercise = false
        medicalCardioMetabolic = false
        medicalMedications = false
        medicalPregnancySurgery = false
        medicalSymptoms = false

        calorieTarget = String(Config.defaultCalorieTarget)
        proteinTarget = String(format: "%.0f", Config.defaultProteinTargetG)
        carbTarget = String(format: "%.0f", Config.defaultCarbTargetG)
        fatTarget = String(format: "%.0f", Config.defaultFatTargetG)
        bodyWeightGoal = String(format: "%.0f", Config.defaultBodyWeightGoalLbs)
        appearanceMode = 0
    }
}
