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
                    Text("These fields shape the Claude body-analysis prompt. Leave a field blank only if you truly want that detail treated as unknown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    settingsField("Age", text: $analysisAge, keyboard: .numberPad)
                    settingsField("Sex / Gender", text: $analysisSex)
                    settingsField("Build", text: $analysisBuild)
                    settingsField("Height", text: $analysisHeight)
                    settingsField("Current Weight", text: $analysisCurrentWeight)
                    settingsField("Occupation", text: $analysisOccupation)
                    settingsField("Training Frequency", text: $analysisTrainingFrequency)
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
                    .font(.subheadline.weight(.medium))
                TextField("Add \(title.lowercased())…", text: text, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
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
        analysisAge = Config.defaultAnalysisAge
        analysisSex = Config.defaultAnalysisSex
        analysisBuild = Config.defaultAnalysisBuild
        analysisHeight = Config.defaultAnalysisHeight
        analysisCurrentWeight = Config.defaultAnalysisCurrentWeight
        analysisOccupation = Config.defaultAnalysisOccupation
        analysisTrainingFrequency = Config.defaultAnalysisTrainingFrequency
        analysisPrimaryGoal = Config.defaultAnalysisPrimaryGoal
        analysisLifestyleConstraints = Config.defaultAnalysisLifestyleConstraints

        calorieTarget = String(Config.defaultCalorieTarget)
        proteinTarget = String(format: "%.0f", Config.defaultProteinTargetG)
        carbTarget = String(format: "%.0f", Config.defaultCarbTargetG)
        fatTarget = String(format: "%.0f", Config.defaultFatTargetG)
        bodyWeightGoal = String(format: "%.0f", Config.defaultBodyWeightGoalLbs)
    }
}
