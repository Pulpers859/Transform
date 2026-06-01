import SwiftUI
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingsKeys.analysisAge) private var analysisAge = Config.defaultAnalysisAge
    @AppStorage(AppSettingsKeys.analysisSex) private var analysisSex = Config.defaultAnalysisSex
    @AppStorage(AppSettingsKeys.analysisBuild) private var analysisBuild = Config.defaultAnalysisBuild
    @AppStorage(AppSettingsKeys.analysisHeight) private var analysisHeight = Config.defaultAnalysisHeight
    @AppStorage(AppSettingsKeys.analysisCurrentWeight) private var analysisCurrentWeight = Config.defaultAnalysisCurrentWeight
    @AppStorage(AppSettingsKeys.analysisOccupation) private var analysisOccupation = Config.defaultAnalysisOccupation
    @AppStorage(AppSettingsKeys.analysisTrainingFrequency) private var analysisTrainingFrequency = Config.defaultAnalysisTrainingFrequency
    @AppStorage(AppSettingsKeys.analysisTrainingAge) private var analysisTrainingAge = Config.defaultAnalysisTrainingAge
    @AppStorage(AppSettingsKeys.analysisEquipmentAccess) private var analysisEquipmentAccess = Config.defaultAnalysisEquipmentAccess
    @AppStorage(AppSettingsKeys.analysisAverageSleep) private var analysisAverageSleep = Config.defaultAnalysisAverageSleep
    @AppStorage(AppSettingsKeys.analysisPainHistory) private var analysisPainHistory = Config.defaultAnalysisPainHistory
    @AppStorage(AppSettingsKeys.analysisActivityLevel) private var analysisActivityLevel = Config.defaultAnalysisActivityLevel
    @AppStorage(AppSettingsKeys.analysisPrimaryGoal) private var analysisPrimaryGoal = Config.defaultAnalysisPrimaryGoal
    @AppStorage(AppSettingsKeys.analysisLifestyleConstraints) private var analysisLifestyleConstraints = Config.defaultAnalysisLifestyleConstraints

    @AppStorage(AppSettingsKeys.calorieTarget) private var calorieTarget = String(Config.defaultCalorieTarget)
    @AppStorage(AppSettingsKeys.proteinTarget) private var proteinTarget = String(format: "%.0f", Config.defaultProteinTargetG)
    @AppStorage(AppSettingsKeys.carbTarget) private var carbTarget = String(format: "%.0f", Config.defaultCarbTargetG)
    @AppStorage(AppSettingsKeys.fatTarget) private var fatTarget = String(format: "%.0f", Config.defaultFatTargetG)
    @AppStorage(AppSettingsKeys.bodyWeightGoal) private var bodyWeightGoal = String(format: "%.0f", Config.defaultBodyWeightGoalLbs)

    var body: some View {
        NavigationStack {
            Form {
                Section("Body Analysis Profile") {
                    Text("These fields shape the body-analysis prompt and make the assessment smarter than photos alone. Leave a field blank only if you truly want that detail treated as unknown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    settingsField("Age", text: $analysisAge, keyboard: .numberPad)
                    settingsField("Sex / Gender", text: $analysisSex)
                    settingsField("Build", text: $analysisBuild)
                    settingsField("Height", text: $analysisHeight)
                    settingsField("Current Weight", text: $analysisCurrentWeight)
                    settingsField("Occupation", text: $analysisOccupation)
                    settingsField("Training Frequency", text: $analysisTrainingFrequency)
                    settingsField("Training Age / Experience", text: $analysisTrainingAge, axis: .vertical)
                    settingsField("Equipment Access", text: $analysisEquipmentAccess, axis: .vertical)
                    settingsField("Average Sleep / Recovery", text: $analysisAverageSleep, axis: .vertical)
                    settingsField("Pain / Injury Context", text: $analysisPainHistory, axis: .vertical)
                    settingsField("Activity Level", text: $analysisActivityLevel, axis: .vertical)
                    settingsField("Primary Goal", text: $analysisPrimaryGoal, axis: .vertical)
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
        analysisCurrentWeight = baselineProfile.currentWeight
        analysisOccupation = baselineProfile.occupation
        analysisTrainingFrequency = baselineProfile.trainingFrequency
        analysisTrainingAge = baselineProfile.trainingAge
        analysisEquipmentAccess = baselineProfile.equipmentAccess
        analysisAverageSleep = baselineProfile.averageSleep
        analysisPainHistory = baselineProfile.painHistory
        analysisActivityLevel = baselineProfile.activityLevel
        analysisPrimaryGoal = baselineProfile.primaryGoal
        analysisLifestyleConstraints = baselineProfile.lifestyleConstraints

        calorieTarget = String(Config.defaultCalorieTarget)
        proteinTarget = String(format: "%.0f", Config.defaultProteinTargetG)
        carbTarget = String(format: "%.0f", Config.defaultCarbTargetG)
        fatTarget = String(format: "%.0f", Config.defaultFatTargetG)
        bodyWeightGoal = String(format: "%.0f", Config.defaultBodyWeightGoalLbs)
    }
}
