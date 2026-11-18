import Foundation

/// The settings half of a backup: profile, injury note, medical screening answers, targets,
/// check-in answers and theme, read from and written to UserDefaults.
///
/// Moved out of `DataBackupManager.swift`, which the headless test package cannot compile.
/// The JSON shape is unchanged, so every existing backup still decodes.
nonisolated struct ProfileSettingsSnapshot: Codable {
    let age: String?
    let sex: String?
    let build: String?
    let height: String?
    let currentWeight: String?
    let occupation: String?
    let trainingFrequency: String?
    let trainingAge: String?
    let equipmentAccess: String?
    let averageSleep: String?
    let painHistory: String?
    let activityLevel: String?
    let primaryGoal: String?
    let lifestyleConstraints: String?
    let weightValue: String?
    let weightUnit: String?
    let goalDetail: String?
    let ageValue: Int?
    let heightFeet: Int?
    let heightInches: Int?
    let heightCm: Int?
    let heightUnit: String?
    let trainingDays: Int?
    let sleepHours: Double?
    let sleepNotes: String?
    let calorieTarget: Int?
    let proteinTarget: Double?
    let carbTarget: Double?
    let fatTarget: Double?
    let bodyWeightGoal: Double?
    let medicalCurrentInjury: Bool?
    let medicalPainDuringExercise: Bool?
    let medicalCardioMetabolic: Bool?
    let medicalMedications: Bool?
    let medicalPregnancySurgery: Bool?
    let medicalSymptoms: Bool?
    let analysisCheckInTrainingContext: String?
    let analysisCheckInBodyweightTrend: String?
    let analysisCheckInRecoverySleep: String?
    let analysisCheckInStressSchedule: String?
    let analysisCheckInSorenessPain: String?
    let analysisCheckInNutritionAdherence: String?
    let analysisCheckInHungerLevel: Int?
    let analysisCheckInEnergyLevel: Int?
    let analysisCheckInCravingsLevel: Int?
    let derivedSleepTrendSummary: String?
    // Optional so older backups (without this key) still decode.
    let derivedSleepRecoveryState: String?
    let appearanceMode: Int?
    let nutritionShiftWorkMode: String?
    /// When the body-weight goal was last set (seconds since 1970). Goal progress is measured
    /// from this date (`AppSettingsStore.bodyWeightGoalSetAt`), so restoring the goal without
    /// it would measure from the wrong starting weight. Absent in older backups.
    var bodyWeightGoalSetAt: Double? = nil

    static func fromUserDefaults(_ d: UserDefaults = .standard) -> ProfileSettingsSnapshot {
        return ProfileSettingsSnapshot(
            age: d.string(forKey: AppSettingsKeys.analysisAge),
            sex: d.string(forKey: AppSettingsKeys.analysisSex),
            build: d.string(forKey: AppSettingsKeys.analysisBuild),
            height: d.string(forKey: AppSettingsKeys.analysisHeight),
            currentWeight: d.string(forKey: AppSettingsKeys.analysisCurrentWeight),
            occupation: d.string(forKey: AppSettingsKeys.analysisOccupation),
            trainingFrequency: d.string(forKey: AppSettingsKeys.analysisTrainingFrequency),
            trainingAge: d.string(forKey: AppSettingsKeys.analysisTrainingAge),
            equipmentAccess: d.string(forKey: AppSettingsKeys.analysisEquipmentAccess),
            averageSleep: d.string(forKey: AppSettingsKeys.analysisAverageSleep),
            painHistory: d.string(forKey: AppSettingsKeys.analysisPainHistory),
            activityLevel: d.string(forKey: AppSettingsKeys.analysisActivityLevel),
            primaryGoal: d.string(forKey: AppSettingsKeys.analysisPrimaryGoal),
            lifestyleConstraints: d.string(forKey: AppSettingsKeys.analysisLifestyleConstraints),
            weightValue: d.string(forKey: AppSettingsKeys.analysisWeightValue),
            weightUnit: d.string(forKey: AppSettingsKeys.analysisWeightUnit),
            goalDetail: d.string(forKey: AppSettingsKeys.analysisGoalDetail),
            ageValue: d.object(forKey: AppSettingsKeys.analysisAgeValue) as? Int,
            heightFeet: d.object(forKey: AppSettingsKeys.analysisHeightFeet) as? Int,
            heightInches: d.object(forKey: AppSettingsKeys.analysisHeightInches) as? Int,
            heightCm: d.object(forKey: AppSettingsKeys.analysisHeightCm) as? Int,
            heightUnit: d.string(forKey: AppSettingsKeys.analysisHeightUnit),
            trainingDays: d.object(forKey: AppSettingsKeys.analysisTrainingDays) as? Int,
            sleepHours: Self.storedNumber(d, AppSettingsKeys.analysisSleepHours),
            sleepNotes: d.string(forKey: AppSettingsKeys.analysisSleepNotes),
            calorieTarget: Self.storedInteger(d, AppSettingsKeys.calorieTarget),
            proteinTarget: Self.storedNumber(d, AppSettingsKeys.proteinTarget),
            carbTarget: Self.storedNumber(d, AppSettingsKeys.carbTarget),
            fatTarget: Self.storedNumber(d, AppSettingsKeys.fatTarget),
            bodyWeightGoal: Self.storedNumber(d, AppSettingsKeys.bodyWeightGoal),
            medicalCurrentInjury: d.object(forKey: AppSettingsKeys.medicalCurrentInjury) as? Bool,
            medicalPainDuringExercise: d.object(forKey: AppSettingsKeys.medicalPainDuringExercise) as? Bool,
            medicalCardioMetabolic: d.object(forKey: AppSettingsKeys.medicalCardioMetabolic) as? Bool,
            medicalMedications: d.object(forKey: AppSettingsKeys.medicalMedications) as? Bool,
            medicalPregnancySurgery: d.object(forKey: AppSettingsKeys.medicalPregnancySurgery) as? Bool,
            medicalSymptoms: d.object(forKey: AppSettingsKeys.medicalSymptoms) as? Bool,
            analysisCheckInTrainingContext: d.string(forKey: AppSettingsKeys.analysisCheckInTrainingContext),
            analysisCheckInBodyweightTrend: d.string(forKey: AppSettingsKeys.analysisCheckInBodyweightTrend),
            analysisCheckInRecoverySleep: d.string(forKey: AppSettingsKeys.analysisCheckInRecoverySleep),
            analysisCheckInStressSchedule: d.string(forKey: AppSettingsKeys.analysisCheckInStressSchedule),
            analysisCheckInSorenessPain: d.string(forKey: AppSettingsKeys.analysisCheckInSorenessPain),
            analysisCheckInNutritionAdherence: d.string(forKey: AppSettingsKeys.analysisCheckInNutritionAdherence),
            analysisCheckInHungerLevel: d.object(forKey: AppSettingsKeys.analysisCheckInHungerLevel) as? Int,
            analysisCheckInEnergyLevel: d.object(forKey: AppSettingsKeys.analysisCheckInEnergyLevel) as? Int,
            analysisCheckInCravingsLevel: d.object(forKey: AppSettingsKeys.analysisCheckInCravingsLevel) as? Int,
            derivedSleepTrendSummary: d.string(forKey: AppSettingsKeys.derivedSleepTrendSummary),
            derivedSleepRecoveryState: d.string(forKey: AppSettingsKeys.derivedSleepRecoveryState),
            appearanceMode: d.object(forKey: AppSettingsKeys.appearanceMode) as? Int,
            nutritionShiftWorkMode: d.string(forKey: AppSettingsKeys.nutritionShiftWorkMode),
            bodyWeightGoalSetAt: (d.object(forKey: AppSettingsKeys.bodyWeightGoalSetAt) as? NSNumber)
                .map(\.doubleValue).flatMap { $0 > 0 ? $0 : nil }
        )
    }

    func applyToUserDefaults(_ d: UserDefaults = .standard) {
        if let v = age { d.set(v, forKey: AppSettingsKeys.analysisAge) }
        if let v = sex { d.set(v, forKey: AppSettingsKeys.analysisSex) }
        if let v = build { d.set(v, forKey: AppSettingsKeys.analysisBuild) }
        if let v = height { d.set(v, forKey: AppSettingsKeys.analysisHeight) }
        if let v = currentWeight { d.set(v, forKey: AppSettingsKeys.analysisCurrentWeight) }
        if let v = occupation { d.set(v, forKey: AppSettingsKeys.analysisOccupation) }
        if let v = trainingFrequency { d.set(v, forKey: AppSettingsKeys.analysisTrainingFrequency) }
        if let v = trainingAge { d.set(v, forKey: AppSettingsKeys.analysisTrainingAge) }
        if let v = equipmentAccess { d.set(v, forKey: AppSettingsKeys.analysisEquipmentAccess) }
        if let v = averageSleep { d.set(v, forKey: AppSettingsKeys.analysisAverageSleep) }
        if let v = painHistory { d.set(v, forKey: AppSettingsKeys.analysisPainHistory) }
        if let v = activityLevel { d.set(v, forKey: AppSettingsKeys.analysisActivityLevel) }
        if let v = primaryGoal { d.set(v, forKey: AppSettingsKeys.analysisPrimaryGoal) }
        if let v = lifestyleConstraints { d.set(v, forKey: AppSettingsKeys.analysisLifestyleConstraints) }
        if let v = weightValue { d.set(v, forKey: AppSettingsKeys.analysisWeightValue) }
        if let v = weightUnit { d.set(v, forKey: AppSettingsKeys.analysisWeightUnit) }
        if let v = goalDetail { d.set(v, forKey: AppSettingsKeys.analysisGoalDetail) }
        if let v = ageValue { d.set(v, forKey: AppSettingsKeys.analysisAgeValue) }
        if let v = heightFeet { d.set(v, forKey: AppSettingsKeys.analysisHeightFeet) }
        if let v = heightInches { d.set(v, forKey: AppSettingsKeys.analysisHeightInches) }
        if let v = heightCm { d.set(v, forKey: AppSettingsKeys.analysisHeightCm) }
        if let v = heightUnit { d.set(v, forKey: AppSettingsKeys.analysisHeightUnit) }
        if let v = trainingDays { d.set(v, forKey: AppSettingsKeys.analysisTrainingDays) }
        if let v = sleepHours { d.set(Self.text(v), forKey: AppSettingsKeys.analysisSleepHours) }
        if let v = sleepNotes { d.set(v, forKey: AppSettingsKeys.analysisSleepNotes) }
        if let v = calorieTarget { d.set(String(v), forKey: AppSettingsKeys.calorieTarget) }
        if let v = proteinTarget { d.set(Self.text(v), forKey: AppSettingsKeys.proteinTarget) }
        if let v = carbTarget { d.set(Self.text(v), forKey: AppSettingsKeys.carbTarget) }
        if let v = fatTarget { d.set(Self.text(v), forKey: AppSettingsKeys.fatTarget) }
        if let v = bodyWeightGoal { d.set(Self.text(v), forKey: AppSettingsKeys.bodyWeightGoal) }
        if let v = medicalCurrentInjury { d.set(v, forKey: AppSettingsKeys.medicalCurrentInjury) }
        if let v = medicalPainDuringExercise { d.set(v, forKey: AppSettingsKeys.medicalPainDuringExercise) }
        if let v = medicalCardioMetabolic { d.set(v, forKey: AppSettingsKeys.medicalCardioMetabolic) }
        if let v = medicalMedications { d.set(v, forKey: AppSettingsKeys.medicalMedications) }
        if let v = medicalPregnancySurgery { d.set(v, forKey: AppSettingsKeys.medicalPregnancySurgery) }
        if let v = medicalSymptoms { d.set(v, forKey: AppSettingsKeys.medicalSymptoms) }
        if let v = analysisCheckInTrainingContext { d.set(v, forKey: AppSettingsKeys.analysisCheckInTrainingContext) }
        if let v = analysisCheckInBodyweightTrend { d.set(v, forKey: AppSettingsKeys.analysisCheckInBodyweightTrend) }
        if let v = analysisCheckInRecoverySleep { d.set(v, forKey: AppSettingsKeys.analysisCheckInRecoverySleep) }
        if let v = analysisCheckInStressSchedule { d.set(v, forKey: AppSettingsKeys.analysisCheckInStressSchedule) }
        if let v = analysisCheckInSorenessPain { d.set(v, forKey: AppSettingsKeys.analysisCheckInSorenessPain) }
        if let v = analysisCheckInNutritionAdherence { d.set(v, forKey: AppSettingsKeys.analysisCheckInNutritionAdherence) }
        if let v = analysisCheckInHungerLevel { d.set(v, forKey: AppSettingsKeys.analysisCheckInHungerLevel) }
        if let v = analysisCheckInEnergyLevel { d.set(v, forKey: AppSettingsKeys.analysisCheckInEnergyLevel) }
        if let v = analysisCheckInCravingsLevel { d.set(v, forKey: AppSettingsKeys.analysisCheckInCravingsLevel) }
        if let v = derivedSleepTrendSummary { d.set(v, forKey: AppSettingsKeys.derivedSleepTrendSummary) }
        if let v = derivedSleepRecoveryState { d.set(v, forKey: AppSettingsKeys.derivedSleepRecoveryState) }
        if let v = appearanceMode { d.set(v, forKey: AppSettingsKeys.appearanceMode) }
        if let v = nutritionShiftWorkMode { d.set(v, forKey: AppSettingsKeys.nutritionShiftWorkMode) }
        // SEAM: pre-fix behaviour, the goal date is not restored.
    }

    // MARK: - Settings the app stores as text

    // The calorie, protein, carb and fat targets, the body-weight goal and the usual sleep
    // hours are edited through `@AppStorage` String fields (AppSettingsView), so UserDefaults
    // holds them as TEXT. This type read them with `as? Int` / `as? Double`, which is always
    // nil for text, so every backup silently left all six out and a restore could not bring
    // them back (bug audit 2026-11-17, F4). The backup fields stay numeric so the file format
    // does not change. They are read from text OR a number, and written back as text, the
    // form `@AppStorage` and `AppSettingsStore`'s readers expect.
    // Pinned by ProfileSettingsBackupTests.

    /// A stored whole number, from text or a number. Matches `AppSettingsStore.integer(for:)`,
    /// which parses the text with `Int(_:)`.
    static func storedInteger(_ d: UserDefaults, _ key: String) -> Int? {
        if true { return d.object(forKey: key) as? Int } // SEAM: pre-fix behaviour
        if let text = d.object(forKey: key) as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (d.object(forKey: key) as? NSNumber)?.intValue
    }

    /// A stored decimal, from text or a number. A comma decimal is accepted because the
    /// sheets that write these allow one.
    static func storedNumber(_ d: UserDefaults, _ key: String) -> Double? {
        if true { return d.object(forKey: key) as? Double } // SEAM: pre-fix behaviour
        if let text = d.object(forKey: key) as? String {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard let value = Double(cleaned), value.isFinite else { return nil }
            return value
        }
        guard let value = (d.object(forKey: key) as? NSNumber)?.doubleValue, value.isFinite else { return nil }
        return value
    }

    /// The text written back: "180" for a whole number, "7.5" otherwise.
    static func text(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
