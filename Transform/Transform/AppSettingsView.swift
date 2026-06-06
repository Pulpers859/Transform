import SwiftUI
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

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
                        let totalInches = Double(heightCm) / 2.54
                        heightFeet = Int(totalInches) / 12
                        heightInches = Int(round(totalInches)) % 12
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

    private var goalBinding: Binding<GoalCategory> {
        Binding(
            get: { GoalCategory(rawValue: analysisPrimaryGoal) ?? .notSpecified },
            set: { analysisPrimaryGoal = $0.rawValue }
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

                    settingsField("Build", text: $analysisBuild)

                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Height Unit", selection: heightUnitBinding) {
                            ForEach(HeightUnit.allCases) { unit in
                                Text(unit.label).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)

                        if HeightUnit(rawValue: heightUnit) == .metric {
                            Stepper("Height: \(heightCm > 0 ? "\(heightCm) cm" : "—")", value: $heightCm, in: 0...250)
                        } else {
                            HStack {
                                Stepper("Feet: \(heightFeet > 0 ? "\(heightFeet)" : "—")", value: $heightFeet, in: 0...8)
                                Stepper("In: \(heightInches)", value: $heightInches, in: 0...11)
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

                    settingsField("Training Age / Experience", text: $analysisTrainingAge, axis: .vertical)
                    settingsField("Equipment Access", text: $analysisEquipmentAccess, axis: .vertical)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Avg Sleep")
                            Spacer()
                            TextField("0", text: $sleepHoursStr)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 50)
                            Text("hrs/night")
                                .foregroundStyle(.secondary)
                        }
                        TextField("Recovery notes (optional)", text: $sleepNotes, axis: .vertical)
                            .lineLimit(2...3)
                            .textInputAutocapitalization(.sentences)
                            .font(.subheadline)
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
