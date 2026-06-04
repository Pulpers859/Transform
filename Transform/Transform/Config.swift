import Foundation

enum Config {
    // Keep first-run profile defaults blank so body analysis starts from user input,
    // not a baked-in persona that can bias coaching.
    static let defaultAnalysisAge = ""
    static let defaultAnalysisSex = ""
    static let defaultAnalysisBuild = ""
    static let defaultAnalysisHeight = ""
    static let defaultAnalysisCurrentWeight = ""
    static let defaultAnalysisOccupation = ""
    static let defaultAnalysisTrainingFrequency = ""
    static let defaultAnalysisTrainingAge = ""
    static let defaultAnalysisEquipmentAccess = ""
    static let defaultAnalysisAverageSleep = ""
    static let defaultAnalysisPainHistory = ""
    static let defaultAnalysisActivityLevel = ""
    static let defaultAnalysisPrimaryGoal = ""
    static let defaultAnalysisLifestyleConstraints = ""
    static let defaultAnalysisCheckInTrainingContext = ""
    static let defaultAnalysisCheckInBodyweightTrend = ""
    static let defaultAnalysisCheckInRecoverySleep = ""
    static let defaultAnalysisCheckInStressSchedule = ""
    static let defaultAnalysisCheckInSorenessPain = ""
    static let defaultAnalysisCheckInNutritionAdherence = ""
    static let defaultAnalysisCheckInHungerLevel = 0
    static let defaultAnalysisCheckInEnergyLevel = 0
    static let defaultAnalysisCheckInCravingsLevel = 0

    static let defaultCalorieTarget = 2200
    static let defaultProteinTargetG = 190.0
    static let defaultCarbTargetG = 220.0
    static let defaultFatTargetG = 65.0
    static let defaultBodyWeightGoalLbs = 185.0

    static var anthropicAPIKey: String { anthropicKeyStatus.apiKey ?? "" }

    static var hasAnthropicKey: Bool {
        anthropicKeyStatus.isConfigured
    }

    static var anthropicKeyStatus: AnthropicAPIKeyStatus {
        APIKeyProvider.anthropicKeyStatus
    }

    static var anthropicKeyInlineHelpText: String {
        anthropicKeyStatus.inlineHelpText
    }

    static var anthropicKeyStartupAlertMessage: String? {
        anthropicKeyStatus.startupAlertMessage
    }

    static let claudeModel = "claude-opus-4-8"
    static let claudeModelLite = "claude-sonnet-4-6"

    static var calorieTarget: Int { AppSettingsStore.calorieTarget }
    static var proteinTargetG: Double { AppSettingsStore.proteinTargetG }
    static var carbTargetG: Double { AppSettingsStore.carbTargetG }
    static var fatTargetG: Double { AppSettingsStore.fatTargetG }
    static var bodyWeightGoalLbs: Double { AppSettingsStore.bodyWeightGoalLbs }
    static var analysisClientProfilePrompt: String { AppSettingsStore.analysisClientProfile.promptDescription }
    static var analysisCheckInPrompt: String { AppSettingsStore.analysisCheckIn.promptDescription }
    static var analysisInputContext: AnalysisInputContext { AppSettingsStore.analysisInputContext }
}

enum PersonalProfileSeed {
    static let age = "30"
    static let sex = "Male"
    static let build = "Mesomorph build"
    static let height = "6'0\""
    static let currentWeight = "195 lbs"
    static let occupation = "Emergency medicine physician"
    static let trainingFrequency = "Training 5-6 days/week"
    static let trainingAge = "4 years of consistent lifting"
    static let equipmentAccess = "Commercial gym with full machine, cable, dumbbell, and barbell access"
    static let averageSleep = "Variable due to shift work; often 5-7 hours"
    static let painHistory = "No major active injury reported; monitor overuse and recovery around long shifts"
    static let activityLevel = "High daily activity from long clinical shifts and time on feet"
    static let primaryGoal = "Body recomposition with visible abs and aesthetic proportions while maintaining performance for demanding clinical shifts"
    static let lifestyleConstraints = "Shift-work schedule with variable sleep and meal timing"
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
    let floorAdjustments: [String]

    init(
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        source: MacroTargetSource,
        floorAdjustments: [String] = []
    ) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.source = source
        self.floorAdjustments = floorAdjustments
    }

    var wasAdjustedBySafetyFloor: Bool {
        !floorAdjustments.isEmpty
    }
}

enum MacroTargetResolver {
    static func resolve(from analysis: BodyAnalysisResult?, bodyweightLbs: Double? = nil) -> DailyMacroTargets {
        if let macros = analysis?.macroTargets {
            let bw = bodyweightLbs ?? profileBodyweightLbs()
            var adjustments: [String] = []

            let calFloor = calorieFloor(bodyweightLbs: bw)
            let proFloor = proteinFloor(bodyweightLbs: bw)
            let fFloor = fatFloor(bodyweightLbs: bw)

            let resolvedCalories = max(macros.calories, calFloor)
            let resolvedProtein = max(macros.proteinG, proFloor)
            let resolvedFat = max(macros.fatG, fFloor)

            if macros.calories < calFloor {
                adjustments.append("Calories raised from \(macros.calories) to \(calFloor) (safety floor: BW×10)")
            }
            if macros.proteinG < proFloor {
                adjustments.append("Protein raised from \(Int(macros.proteinG))g to \(Int(proFloor))g (safety floor: 1.4 g/kg)")
            }
            if macros.fatG < fFloor {
                adjustments.append("Fat raised from \(Int(macros.fatG))g to \(Int(fFloor))g (safety floor: 0.35 g/kg)")
            }

            return DailyMacroTargets(
                calories: resolvedCalories,
                proteinG: resolvedProtein,
                carbsG: max(macros.carbsG, 50),
                fatG: resolvedFat,
                source: .analysis,
                floorAdjustments: adjustments
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

    static func profileBodyweightLbs() -> Double? {
        let raw = AppSettingsStore.analysisClientProfile.currentWeight
        let scanner = Scanner(string: raw)
        guard let value = scanner.scanDouble(), value > 50 else { return nil }
        let remaining = raw[scanner.currentIndex...].trimmingCharacters(in: .whitespaces).lowercased()
        if remaining.hasPrefix("kg") {
            return value * 2.205
        }
        return value
    }

    private static func calorieFloor(bodyweightLbs: Double?) -> Int {
        guard let bw = bodyweightLbs else { return 1200 }
        return max(1200, Int(bw * 10))
    }

    private static func proteinFloor(bodyweightLbs: Double?) -> Double {
        guard let bw = bodyweightLbs else { return 60 }
        let kg = bw / 2.205
        return max(60, kg * 1.4)
    }

    private static func fatFloor(bodyweightLbs: Double?) -> Double {
        guard let bw = bodyweightLbs else { return 25 }
        let kg = bw / 2.205
        return max(25, kg * 0.35)
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
    static let analysisCheckInHungerLevel = "analysis_checkin_hunger_level"
    static let analysisCheckInEnergyLevel = "analysis_checkin_energy_level"
    static let analysisCheckInCravingsLevel = "analysis_checkin_cravings_level"

    static let calorieTarget = "nutrition_calorie_target"
    static let proteinTarget = "nutrition_protein_target"
    static let carbTarget = "nutrition_carb_target"
    static let fatTarget = "nutrition_fat_target"
    static let bodyWeightGoal = "body_weight_goal"
    static let appearanceMode = "app_appearance_mode"
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
    let hungerLevel: Int
    let energyLevel: Int
    let cravingsLevel: Int

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
            nutritionAdherence: nutritionAdherence,
            hungerLevel: hungerLevel > 0 ? hungerLevel : nil,
            energyLevel: energyLevel > 0 ? energyLevel : nil,
            cravingsLevel: cravingsLevel > 0 ? cravingsLevel : nil
        )
        return snapshot.hasMeaningfulContent ? snapshot : nil
    }
}

enum AppSettingsStore {
    private static let defaults = UserDefaults.standard

    static func seedPersonalProfileIfNeeded() {
        let seededValues: [(String, String)] = [
            (AppSettingsKeys.analysisAge, PersonalProfileSeed.age),
            (AppSettingsKeys.analysisSex, PersonalProfileSeed.sex),
            (AppSettingsKeys.analysisBuild, PersonalProfileSeed.build),
            (AppSettingsKeys.analysisHeight, PersonalProfileSeed.height),
            (AppSettingsKeys.analysisCurrentWeight, PersonalProfileSeed.currentWeight),
            (AppSettingsKeys.analysisOccupation, PersonalProfileSeed.occupation),
            (AppSettingsKeys.analysisTrainingFrequency, PersonalProfileSeed.trainingFrequency),
            (AppSettingsKeys.analysisTrainingAge, PersonalProfileSeed.trainingAge),
            (AppSettingsKeys.analysisEquipmentAccess, PersonalProfileSeed.equipmentAccess),
            (AppSettingsKeys.analysisAverageSleep, PersonalProfileSeed.averageSleep),
            (AppSettingsKeys.analysisPainHistory, PersonalProfileSeed.painHistory),
            (AppSettingsKeys.analysisActivityLevel, PersonalProfileSeed.activityLevel),
            (AppSettingsKeys.analysisPrimaryGoal, PersonalProfileSeed.primaryGoal),
            (AppSettingsKeys.analysisLifestyleConstraints, PersonalProfileSeed.lifestyleConstraints)
        ]

        for (key, value) in seededValues where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

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
            nutritionAdherence: string(for: AppSettingsKeys.analysisCheckInNutritionAdherence, default: Config.defaultAnalysisCheckInNutritionAdherence),
            hungerLevel: integer(for: AppSettingsKeys.analysisCheckInHungerLevel, default: Config.defaultAnalysisCheckInHungerLevel, min: 0, max: 10),
            energyLevel: integer(for: AppSettingsKeys.analysisCheckInEnergyLevel, default: Config.defaultAnalysisCheckInEnergyLevel, min: 0, max: 10),
            cravingsLevel: integer(for: AppSettingsKeys.analysisCheckInCravingsLevel, default: Config.defaultAnalysisCheckInCravingsLevel, min: 0, max: 10)
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

    static var personalAnalysisProfile: AnalysisClientProfile {
        AnalysisClientProfile(
            age: PersonalProfileSeed.age,
            sex: PersonalProfileSeed.sex,
            build: PersonalProfileSeed.build,
            height: PersonalProfileSeed.height,
            currentWeight: PersonalProfileSeed.currentWeight,
            occupation: PersonalProfileSeed.occupation,
            trainingFrequency: PersonalProfileSeed.trainingFrequency,
            trainingAge: PersonalProfileSeed.trainingAge,
            equipmentAccess: PersonalProfileSeed.equipmentAccess,
            averageSleep: PersonalProfileSeed.averageSleep,
            painHistory: PersonalProfileSeed.painHistory,
            activityLevel: PersonalProfileSeed.activityLevel,
            primaryGoal: PersonalProfileSeed.primaryGoal,
            lifestyleConstraints: PersonalProfileSeed.lifestyleConstraints
        )
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

enum AnthropicAPIKeyStatus: Equatable {
    case configured(String)
    case missingSecretsFile(expectedBundlePath: String)
    case unreadableSecretsFile(expectedBundlePath: String)
    case missingKey(expectedBundlePath: String)
    case placeholderValue(expectedBundlePath: String)

    var apiKey: String? {
        switch self {
        case .configured(let key):
            return key
        default:
            return nil
        }
    }

    var isConfigured: Bool {
        apiKey != nil
    }

    var inlineHelpText: String {
        switch self {
        case .configured:
            return ""
        case .missingSecretsFile:
            return "AI is unavailable. Transform looked for a bundled Secrets.plist and did not find one."
        case .unreadableSecretsFile:
            return "AI is unavailable. Transform found Secrets.plist but could not read it as a valid property list."
        case .missingKey:
            return "AI is unavailable. Secrets.plist is bundled, but ANTHROPIC_API_KEY is missing or empty."
        case .placeholderValue:
            return "AI is unavailable. Secrets.plist still contains the placeholder key instead of your real ANTHROPIC_API_KEY."
        }
    }

    var startupAlertMessage: String? {
        guard !isConfigured else { return nil }
        return """
        \(inlineHelpText)

        Supported setup:
        1. Create a local file named Secrets.plist inside the Transform app source folder.
        2. Add ANTHROPIC_API_KEY with your real key.
        3. Leave it uncommitted; the app folder is synchronized into the Transform target during your local Xcode build.

        Exact bundled path checked at runtime:
        \(expectedBundlePath)
        """
    }

    var requestFailureMessage: String {
        startupAlertMessage ?? inlineHelpText
    }

    private var expectedBundlePath: String {
        switch self {
        case .configured:
            return APIKeyProvider.expectedBundleSecretsPath
        case .missingSecretsFile(let path),
             .unreadableSecretsFile(let path),
             .missingKey(let path),
             .placeholderValue(let path):
            return path
        }
    }
}

enum APIKeyProvider {
    private static let plistKey = "ANTHROPIC_API_KEY"
    private static let secretsPlistName = "Secrets"
    static var expectedBundleSecretsPath: String {
        (Bundle.main.bundlePath as NSString).appendingPathComponent("\(secretsPlistName).plist")
    }

    static var anthropicKeyStatus: AnthropicAPIKeyStatus {
        let expectedPath = expectedBundleSecretsPath

        guard let url = Bundle.main.url(forResource: secretsPlistName, withExtension: "plist") else {
            return .missingSecretsFile(expectedBundlePath: expectedPath)
        }

        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any] else {
            return .unreadableSecretsFile(expectedBundlePath: expectedPath)
        }

        guard let rawValue = dictionary[plistKey] as? String else {
            return .missingKey(expectedBundlePath: expectedPath)
        }

        let cleaned = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .missingKey(expectedBundlePath: expectedPath)
        }

        guard !placeholderValues.contains(cleaned.lowercased()) else {
            return .placeholderValue(expectedBundlePath: expectedPath)
        }

        return .configured(cleaned)
    }

    private static let placeholderValues: Set<String> = [
        "your_api_key_here",
        "sk-ant-your-real-key-goes-here"
    ]
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
