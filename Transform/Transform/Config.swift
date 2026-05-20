import Foundation

enum Config {
    // Keep this blank in git. If you want the blunt-force local-only route, you can
    // paste your key here on your Mac and never commit that change.
    static let bundledAnthropicAPIKey = ""

    static let defaultAnalysisAge = "30"
    static let defaultAnalysisSex = "Male"
    static let defaultAnalysisBuild = "Mesomorph build"
    static let defaultAnalysisHeight = "6'0\""
    static let defaultAnalysisCurrentWeight = "195 lbs"
    static let defaultAnalysisOccupation = "Emergency medicine physician"
    static let defaultAnalysisTrainingFrequency = "Training 5-6 days/week"
    static let defaultAnalysisTrainingAge = "4 years of consistent lifting"
    static let defaultAnalysisEquipmentAccess = "Commercial gym with full machine, cable, dumbbell, and barbell access"
    static let defaultAnalysisAverageSleep = "Variable due to shift work; often 5-7 hours"
    static let defaultAnalysisPainHistory = "No major active injury reported; monitor overuse and recovery around long shifts"
    static let defaultAnalysisActivityLevel = "High daily activity from long clinical shifts and time on feet"
    static let defaultAnalysisPrimaryGoal = "Body recomposition with visible abs and aesthetic proportions while maintaining performance for demanding clinical shifts"
    static let defaultAnalysisLifestyleConstraints = "Shift-work schedule with variable sleep and meal timing"
    static let defaultAnalysisCheckInTrainingContext = ""
    static let defaultAnalysisCheckInBodyweightTrend = ""
    static let defaultAnalysisCheckInRecoverySleep = ""
    static let defaultAnalysisCheckInStressSchedule = ""
    static let defaultAnalysisCheckInSorenessPain = ""
    static let defaultAnalysisCheckInNutritionAdherence = ""

    static let defaultCalorieTarget = 2200
    static let defaultProteinTargetG = 190.0
    static let defaultCarbTargetG = 220.0
    static let defaultFatTargetG = 65.0
    static let defaultBodyWeightGoalLbs = 185.0

    static var anthropicAPIKey: String {
        APIKeyProvider.anthropicKey ?? bundledAnthropicAPIKey
    }

    static var hasAnthropicKey: Bool {
        !anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Anthropic snapshot IDs from the official models docs. Snapshot IDs are more stable
    // than free-floating aliases when you want predictable generation behavior over time.
    static let claudeModel = "claude-opus-4-1-20250805" // Vision tasks (body analysis)
    static let claudeModelLite = "claude-sonnet-4-20250514" // Text tasks (macro estimation)

    static var calorieTarget: Int { AppSettingsStore.calorieTarget }
    static var proteinTargetG: Double { AppSettingsStore.proteinTargetG }
    static var carbTargetG: Double { AppSettingsStore.carbTargetG }
    static var fatTargetG: Double { AppSettingsStore.fatTargetG }
    static var bodyWeightGoalLbs: Double { AppSettingsStore.bodyWeightGoalLbs }
    static var analysisClientProfilePrompt: String { AppSettingsStore.analysisClientProfile.promptDescription }
    static var analysisCheckInPrompt: String { AppSettingsStore.analysisCheckIn.promptDescription }
    static var analysisInputContext: AnalysisInputContext { AppSettingsStore.analysisInputContext }
}

enum MacroTargetSource {
    case analysis
    case config
}

struct DailyMacroTargets {
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let source: MacroTargetSource
}

enum MacroTargetResolver {
    static func resolve(from analysis: BodyAnalysisResult?) -> DailyMacroTargets {
        if let macros = analysis?.macroTargets {
            return DailyMacroTargets(
                calories: max(macros.calories, 1200),
                proteinG: max(macros.proteinG, 60),
                carbsG: max(macros.carbsG, 50),
                fatG: max(macros.fatG, 25),
                source: .analysis
            )
        }

        return DailyMacroTargets(
            calories: Config.calorieTarget,
            proteinG: Config.proteinTargetG,
            carbsG: Config.carbTargetG,
            fatG: Config.fatTargetG,
            source: .config
        )
    }
}

enum AppSettingsKeys {
    static let analysisAge = "analysis_profile_age"
    static let analysisSex = "analysis_profile_sex"
    static let analysisBuild = "analysis_profile_build"
    static let analysisHeight = "analysis_profile_height"
    static let analysisCurrentWeight = "analysis_profile_current_weight"
    static let analysisOccupation = "analysis_profile_occupation"
    static let analysisTrainingFrequency = "analysis_profile_training_frequency"
    static let analysisTrainingAge = "analysis_profile_training_age"
    static let analysisEquipmentAccess = "analysis_profile_equipment_access"
    static let analysisAverageSleep = "analysis_profile_average_sleep"
    static let analysisPainHistory = "analysis_profile_pain_history"
    static let analysisActivityLevel = "analysis_profile_activity_level"
    static let analysisPrimaryGoal = "analysis_profile_primary_goal"
    static let analysisLifestyleConstraints = "analysis_profile_lifestyle_constraints"
    static let analysisCheckInTrainingContext = "analysis_checkin_training_context"
    static let analysisCheckInBodyweightTrend = "analysis_checkin_bodyweight_trend"
    static let analysisCheckInRecoverySleep = "analysis_checkin_recovery_sleep"
    static let analysisCheckInStressSchedule = "analysis_checkin_stress_schedule"
    static let analysisCheckInSorenessPain = "analysis_checkin_soreness_pain"
    static let analysisCheckInNutritionAdherence = "analysis_checkin_nutrition_adherence"

    static let calorieTarget = "nutrition_calorie_target"
    static let proteinTarget = "nutrition_protein_target"
    static let carbTarget = "nutrition_carb_target"
    static let fatTarget = "nutrition_fat_target"
    static let bodyWeightGoal = "body_weight_goal"
}

struct AnalysisClientProfile {
    let age: String
    let sex: String
    let build: String
    let height: String
    let currentWeight: String
    let occupation: String
    let trainingFrequency: String
    let trainingAge: String
    let equipmentAccess: String
    let averageSleep: String
    let painHistory: String
    let activityLevel: String
    let primaryGoal: String
    let lifestyleConstraints: String

    var promptDescription: String {
        snapshot.promptDescription
    }

    var snapshot: AnalysisProfileSnapshot {
        AnalysisProfileSnapshot(
            age: age,
            sex: sex,
            build: build,
            height: height,
            currentWeight: currentWeight,
            occupation: occupation,
            trainingFrequency: trainingFrequency,
            trainingAge: trainingAge,
            equipmentAccess: equipmentAccess,
            averageSleep: averageSleep,
            painHistory: painHistory,
            activityLevel: activityLevel,
            primaryGoal: primaryGoal,
            lifestyleConstraints: lifestyleConstraints
        )
    }
}

struct AnalysisCheckIn {
    let trainingContext: String
    let bodyweightTrend: String
    let recoverySleep: String
    let stressSchedule: String
    let sorenessPain: String
    let nutritionAdherence: String

    var promptDescription: String {
        snapshot?.promptDescription ?? """
        Current check-in context for this analysis.
        Use it to sharpen recovery, nutrition, and programming interpretation instead of over-reading the photos.
        - No current check-in provided.
        """
    }

    var snapshot: AnalysisCheckInSnapshot? {
        let snapshot = AnalysisCheckInSnapshot(
            trainingContext: trainingContext,
            bodyweightTrend: bodyweightTrend,
            recoverySleep: recoverySleep,
            stressSchedule: stressSchedule,
            sorenessPain: sorenessPain,
            nutritionAdherence: nutritionAdherence
        )
        return snapshot.hasMeaningfulContent ? snapshot : nil
    }
}

enum AppSettingsStore {
    private static let defaults = UserDefaults.standard

    static var analysisClientProfile: AnalysisClientProfile {
        AnalysisClientProfile(
            age: string(for: AppSettingsKeys.analysisAge, default: Config.defaultAnalysisAge),
            sex: string(for: AppSettingsKeys.analysisSex, default: Config.defaultAnalysisSex),
            build: string(for: AppSettingsKeys.analysisBuild, default: Config.defaultAnalysisBuild),
            height: string(for: AppSettingsKeys.analysisHeight, default: Config.defaultAnalysisHeight),
            currentWeight: string(for: AppSettingsKeys.analysisCurrentWeight, default: Config.defaultAnalysisCurrentWeight),
            occupation: string(for: AppSettingsKeys.analysisOccupation, default: Config.defaultAnalysisOccupation),
            trainingFrequency: string(for: AppSettingsKeys.analysisTrainingFrequency, default: Config.defaultAnalysisTrainingFrequency),
            trainingAge: string(for: AppSettingsKeys.analysisTrainingAge, default: Config.defaultAnalysisTrainingAge),
            equipmentAccess: string(for: AppSettingsKeys.analysisEquipmentAccess, default: Config.defaultAnalysisEquipmentAccess),
            averageSleep: string(for: AppSettingsKeys.analysisAverageSleep, default: Config.defaultAnalysisAverageSleep),
            painHistory: string(for: AppSettingsKeys.analysisPainHistory, default: Config.defaultAnalysisPainHistory),
            activityLevel: string(for: AppSettingsKeys.analysisActivityLevel, default: Config.defaultAnalysisActivityLevel),
            primaryGoal: string(for: AppSettingsKeys.analysisPrimaryGoal, default: Config.defaultAnalysisPrimaryGoal),
            lifestyleConstraints: string(for: AppSettingsKeys.analysisLifestyleConstraints, default: Config.defaultAnalysisLifestyleConstraints)
        )
    }

    static var analysisCheckIn: AnalysisCheckIn {
        AnalysisCheckIn(
            trainingContext: string(for: AppSettingsKeys.analysisCheckInTrainingContext, default: Config.defaultAnalysisCheckInTrainingContext),
            bodyweightTrend: string(for: AppSettingsKeys.analysisCheckInBodyweightTrend, default: Config.defaultAnalysisCheckInBodyweightTrend),
            recoverySleep: string(for: AppSettingsKeys.analysisCheckInRecoverySleep, default: Config.defaultAnalysisCheckInRecoverySleep),
            stressSchedule: string(for: AppSettingsKeys.analysisCheckInStressSchedule, default: Config.defaultAnalysisCheckInStressSchedule),
            sorenessPain: string(for: AppSettingsKeys.analysisCheckInSorenessPain, default: Config.defaultAnalysisCheckInSorenessPain),
            nutritionAdherence: string(for: AppSettingsKeys.analysisCheckInNutritionAdherence, default: Config.defaultAnalysisCheckInNutritionAdherence)
        )
    }

    static var analysisInputContext: AnalysisInputContext {
        AnalysisInputContext(
            profile: analysisClientProfile.snapshot,
            checkIn: analysisCheckIn.snapshot,
            progress: nil
        )
    }

    static var calorieTarget: Int {
        integer(for: AppSettingsKeys.calorieTarget, default: Config.defaultCalorieTarget, min: 1200, max: 7000)
    }

    static var proteinTargetG: Double {
        double(for: AppSettingsKeys.proteinTarget, default: Config.defaultProteinTargetG, min: 40, max: 400)
    }

    static var carbTargetG: Double {
        double(for: AppSettingsKeys.carbTarget, default: Config.defaultCarbTargetG, min: 25, max: 700)
    }

    static var fatTargetG: Double {
        double(for: AppSettingsKeys.fatTarget, default: Config.defaultFatTargetG, min: 20, max: 250)
    }

    static var bodyWeightGoalLbs: Double {
        double(for: AppSettingsKeys.bodyWeightGoal, default: Config.defaultBodyWeightGoalLbs, min: 50, max: 999)
    }

    private static func string(for key: String, default defaultValue: String) -> String {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func integer(for key: String, default defaultValue: Int, min: Int, max: Int) -> Int {
        if let stored = numericString(for: key), let parsed = Int(stored) {
            return Swift.max(min, Swift.min(max, parsed))
        }
        return defaultValue
    }

    private static func double(for key: String, default defaultValue: Double, min: Double, max: Double) -> Double {
        if let stored = numericString(for: key), let parsed = Double(stored) {
            return Swift.max(min, Swift.min(max, parsed))
        }
        return defaultValue
    }

    private static func numericString(for key: String) -> String? {
        defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum APIKeyProvider {
    private static let envKey = "ANTHROPIC_API_KEY"
    private static let plistKey = "ANTHROPIC_API_KEY"
    private static let secretsPlistName = "Secrets"

    static var anthropicKey: String? {
        if let env = cleanedSecret(ProcessInfo.processInfo.environment[envKey]) {
            return env
        }

        if let url = Bundle.main.url(forResource: secretsPlistName, withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dictionary = object as? [String: Any],
           let secret = cleanedSecret(dictionary[plistKey] as? String) {
            return secret
        }

        if let plistValue = cleanedSecret(Bundle.main.object(forInfoDictionaryKey: plistKey) as? String) {
            return plistValue
        }

        return nil
    }

    private static func cleanedSecret(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard !cleaned.hasPrefix("$("), !cleaned.hasSuffix(")") else {
            return nil
        }
        guard cleaned.lowercased() != "your_api_key_here" else {
            return nil
        }
        guard cleaned.lowercased() != "sk-ant-your-real-key-goes-here" else {
            return nil
        }
        return cleaned
    }
}

enum GeneratedContentSource: String, CaseIterable {
    case aiCoach = "[AI Coach]"
    case recoveryEngine = "[Recovery Engine]"

    var label: String {
        switch self {
        case .aiCoach:
            return "AI Coach"
        case .recoveryEngine:
            return "Recovery Engine"
        }
    }

    static func detect(in text: String) -> GeneratedContentSource? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { trimmed.hasPrefix($0.rawValue) }
    }

    static func strip(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source = detect(in: trimmed) else {
            return trimmed
        }
        return String(trimmed.dropFirst(source.rawValue.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prefixing(_ text: String) -> String {
        "\(rawValue) \(GeneratedContentSource.strip(from: text))"
    }
}
