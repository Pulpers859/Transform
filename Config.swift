import Foundation

enum Config {
    // Built-in default for zero-friction usage, with optional runtime overrides.
    static let bundledAnthropicAPIKey = "" // Set once and keep; env/Info.plist can still override.

    // Profile fields ship blank: prompts treat blank fields as unknown instead of
    // inventing them, so no fabricated persona leaks into analysis or coaching.
    static let defaultAnalysisAge = ""
    static let defaultAnalysisSex = ""
    static let defaultAnalysisBuild = ""
    static let defaultAnalysisHeight = ""
    static let defaultAnalysisCurrentWeight = ""
    static let defaultAnalysisOccupation = ""
    static let defaultAnalysisTrainingFrequency = ""
    static let defaultAnalysisPrimaryGoal = ""
    static let defaultAnalysisLifestyleConstraints = ""

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

    // Current Anthropic model aliases. The previous snapshot IDs
    // (claude-opus-4-1-20250805, claude-sonnet-4-20250514) are deprecated and
    // begin returning 404 at retirement (Sonnet 4: 2026-06-15, Opus 4.1: 2026-08-05).
    // Note: these models reject assistant prefill and `temperature` — request
    // construction must not reintroduce either.
    static let claudeModel = "claude-opus-4-8" // Vision tasks (body analysis)
    static let claudeModelLite = "claude-sonnet-4-6" // Text tasks (macro estimation)

    static var calorieTarget: Int { AppSettingsStore.calorieTarget }
    static var proteinTargetG: Double { AppSettingsStore.proteinTargetG }
    static var carbTargetG: Double { AppSettingsStore.carbTargetG }
    static var fatTargetG: Double { AppSettingsStore.fatTargetG }
    static var bodyWeightGoalLbs: Double { AppSettingsStore.bodyWeightGoalLbs }
    static var analysisClientProfilePrompt: String { AppSettingsStore.analysisClientProfile.promptDescription }
}

/// Parses user-typed numeric text accepting both "." and "," decimal separators.
/// The iOS decimal pad shows "," in many locales, where Double("12,5") returns
/// nil and silently disables Save buttons with no explanation.
enum UserNumberParser {
    static func double(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = Double(trimmed) { return parsed }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    static func int(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = Int(trimmed) { return parsed }
        // Accept decimal input for integer fields by rounding (e.g. "450.5" kcal).
        return double(from: trimmed).map { Int($0.rounded()) }
    }
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
            // Clamp both directions: floors catch lowball/zero output, ceilings catch
            // hallucinated extremes, mirroring AppSettingsStore's accepted ranges.
            return DailyMacroTargets(
                calories: min(max(macros.calories, 1200), 7000),
                proteinG: min(max(macros.proteinG, 60), 400),
                carbsG: min(max(macros.carbsG, 50), 700),
                fatG: min(max(macros.fatG, 25), 250),
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
    static let analysisPrimaryGoal = "analysis_profile_primary_goal"
    static let analysisLifestyleConstraints = "analysis_profile_lifestyle_constraints"

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
    let primaryGoal: String
    let lifestyleConstraints: String

    var promptDescription: String {
        let lines = [
            ("Age", age),
            ("Sex/Gender", sex),
            ("Build", build),
            ("Height", height),
            ("Current Body Weight", currentWeight),
            ("Occupation", occupation),
            ("Training Frequency", trainingFrequency),
            ("Primary Goal", primaryGoal),
            ("Lifestyle Constraints", lifestyleConstraints)
        ]
        .map { label, value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return "- \(label): \(cleaned.isEmpty ? "(unspecified)" : cleaned)"
        }
        .joined(separator: "\n")

        return """
        Use the following user-editable profile context when personalizing the assessment.
        Treat blank or unspecified fields as unknown rather than inventing them.
        \(lines)
        """
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
            primaryGoal: string(for: AppSettingsKeys.analysisPrimaryGoal, default: Config.defaultAnalysisPrimaryGoal),
            lifestyleConstraints: string(for: AppSettingsKeys.analysisLifestyleConstraints, default: Config.defaultAnalysisLifestyleConstraints)
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
        if let stored = numericString(for: key), let parsed = UserNumberParser.int(from: stored) {
            return Swift.max(min, Swift.min(max, parsed))
        }
        return defaultValue
    }

    private static func double(for key: String, default defaultValue: Double, min: Double, max: Double) -> Double {
        if let stored = numericString(for: key), let parsed = UserNumberParser.double(from: stored) {
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

    static var anthropicKey: String? {
        if let env = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        if let plistValue = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String {
            let cleaned = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return nil
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
