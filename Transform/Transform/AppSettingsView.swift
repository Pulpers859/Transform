import SwiftUI
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.analysisAge) private var analysisAge = Config.defaultAnalysisAge
    @AppStorage(AppSettingsKeys.analysisSex) private var analysisSex = Config.defaultAnalysisSex
    @AppStorage(AppSettingsKeys.analysisBuild) private var analysisBuild = Config.defaultAnalysisBuild
    @AppStorage(AppSettingsKeys.analysisHeight) private var analysisHeight = Config.defaultAnalysisHeight
    @AppStorage(AppSettingsKeys.analysisWeightValue) private var weightValue = ""
    @AppStorage(AppSettingsKeys.analysisWeightUnit) private var weightUnit = WeightUnit.lb.rawValue
    @AppStorage(AppSettingsKeys.analysisOccupation) private var analysisOccupation = Config.defaultAnalysisOccupation
    @AppStorage(AppSettingsKeys.analysisTrainingFrequency) private var analysisTrainingFrequency = Config.defaultAnalysisTrainingFrequency
    @AppStorage(AppSettingsKeys.analysisTrainingAge) private var analysisTrainingAge = Config.defaultAnalysisTrainingAge
    @AppStorage(AppSettingsKeys.analysisEquipmentAccess) private var analysisEquipmentAccess = Config.defaultAnalysisEquipmentAccess
    @AppStorage(AppSettingsKeys.analysisAverageSleep) private var analysisAverageSleep = Config.defaultAnalysisAverageSleep
    @AppStorage(AppSettingsKeys.analysisPainHistory) private var analysisPainHistory = Config.defaultAnalysisPainHistory
    @AppStorage(AppSettingsKeys.analysisActivityLevel) private var analysisActivityLevel = Config.defaultAnalysisActivityLevel
    @AppStorage(AppSettingsKeys.analysisPrimaryGoal) private var analysisPrimaryGoal = Config.defaultAnalysisPrimaryGoal
    @AppStorage(AppSettingsKeys.analysisGoalDetail) private var analysisGoalDetail = Config.defaultAnalysisGoalDetail
    @AppStorage(AppSettingsKeys.analysisLifestyleConstraints) private var analysisLifestyleConstraints = Config.defaultAnalysisLifestyleConstraints

    @AppStorage(AppSettingsKeys.calorieTarget) private var calorieTarget = String(Config.defaultCalorieTarget)
    @AppStorage(AppSettingsKeys.proteinTarget) private var proteinTarget = String(format: "%.0f", Config.defaultProteinTargetG)
    @AppStorage(AppSettingsKeys.carbTarget) private var carbTarget = String(format: "%.0f", Config.defaultCarbTargetG)
    @AppStorage(AppSettingsKeys.fatTarget) private var fatTarget = String(format: "%.0f", Config.defaultFatTargetG)
    @AppStorage(AppSettingsKeys.bodyWeightGoal) private var bodyWeightGoal = String(format: "%.0f", Config.defaultBodyWeightGoalLbs)
    @AppStorage(AppSettingsKeys.appearanceMode) private var appearanceMode = 0

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

    private var activityBinding: Binding<ActivityLevel> {
        Binding(
            get: { ActivityLevel(rawValue: analysisActivityLevel) ?? .notSpecified },
            set: { analysisActivityLevel = $0.rawValue }
        )
    }

    private var goalBinding: Binding<GoalCategory> {
        Binding(
            get: { GoalCategory(rawValue: analysisPrimaryGoal) ?? .notSpecified },
            set: { analysisPrimaryGoal = $0.rawValue }
        )
    }

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

                    settingsField("Age", text: $analysisAge, keyboard: .numberPad)

                    Picker("Sex / Gender", selection: sexBinding) {
                        ForEach(SexOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }

                    settingsField("Build", text: $analysisBuild)
                    settingsField("Height", text: $analysisHeight)

                    HStack {
                        Text("Current Weight")
                        Spacer()
                        TextField("0", text: $weightValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Picker("", selection: weightUnitBinding) {
                            ForEach(WeightUnit.allCases) { unit in
                                Text(unit.rawValue).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 80)
                    }

                    settingsField("Occupation", text: $analysisOccupation)
                    settingsField("Training Frequency", text: $analysisTrainingFrequency)
                    settingsField("Training Age / Experience", text: $analysisTrainingAge, axis: .vertical)
                    settingsField("Equipment Access", text: $analysisEquipmentAccess, axis: .vertical)
                    settingsField("Average Sleep / Recovery", text: $analysisAverageSleep, axis: .vertical)
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
                        }
                    }

                    settingsField("Lifestyle Constraints", text: $analysisLifestyleConstraints, axis: .vertical)
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
                        restoreDefaults()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .bold()
                }
            }
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
            }
        } else {
            HStack {
                Text(title)
                Spacer()
                TextField(title, text: text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                if let suffix {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func restoreDefaults() {
        let baselineProfile = AppSettingsStore.personalAnalysisProfile
        analysisAge = baselineProfile.age
        analysisSex = baselineProfile.sex
        analysisBuild = baselineProfile.build
        analysisHeight = baselineProfile.height
        weightValue = PersonalProfileSeed.weightValue
        weightUnit = PersonalProfileSeed.weightUnit
        analysisOccupation = baselineProfile.occupation
        analysisTrainingFrequency = baselineProfile.trainingFrequency
        analysisTrainingAge = baselineProfile.trainingAge
        analysisEquipmentAccess = baselineProfile.equipmentAccess
        analysisAverageSleep = baselineProfile.averageSleep
        analysisPainHistory = baselineProfile.painHistory
        analysisActivityLevel = ActivityLevel.veryActive.rawValue
        analysisPrimaryGoal = GoalCategory.recomposition.rawValue
        analysisGoalDetail = PersonalProfileSeed.goalDetail
        analysisLifestyleConstraints = baselineProfile.lifestyleConstraints

        calorieTarget = String(Config.defaultCalorieTarget)
        proteinTarget = String(format: "%.0f", Config.defaultProteinTargetG)
        carbTarget = String(format: "%.0f", Config.defaultCarbTargetG)
        fatTarget = String(format: "%.0f", Config.defaultFatTargetG)
        bodyWeightGoal = String(format: "%.0f", Config.defaultBodyWeightGoalLbs)
        appearanceMode = 0
    }
}
