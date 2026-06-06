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

    static let defaultAnalysisGoalDetail = ""

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
    static var profileCompleteness: ProfileCompleteness { AppSettingsStore.profileCompleteness }
}

struct ProfileCompleteness {
    let filledCount: Int
    let totalCount: Int
    let missingFields: [String]

    var fraction: Double { totalCount > 0 ? Double(filledCount) / Double(totalCount) : 0 }

    var signal: String {
        switch fraction {
        case 0.85...: return "Strong"
        case 0.6...: return "Moderate"
        default: return "Weak"
        }
    }

    var summary: String {
        if missingFields.isEmpty { return "Profile signal: Strong" }
        let missing = missingFields.prefix(3).joined(separator: ", ")
        let extra = missingFields.count > 3 ? " + \(missingFields.count - 3) more" : ""
        return "Profile signal: \(signal) — Missing: \(missing)\(extra)"
    }
}

enum SexOption: String, CaseIterable, Identifiable {
    case notSpecified = ""
    case male = "Male"
    case female = "Female"
    case nonBinary = "Non-binary"
    case preferNotToSay = "Prefer not to say"
    var id: String { rawValue }
    var label: String { self == .notSpecified ? "Not specified" : rawValue }
}

enum WeightUnit: String, CaseIterable, Identifiable {
    case lb = "lb"
    case kg = "kg"
    var id: String { rawValue }
}

enum ActivityLevel: String, CaseIterable, Identifiable {
    case notSpecified = ""
    case sedentary = "Sedentary"
    case lightlyActive = "Lightly active"
    case moderatelyActive = "Moderately active"
    case veryActive = "Very active"
    case extremelyActive = "Extremely active"
    var id: String { rawValue }
    var label: String { self == .notSpecified ? "Not specified" : rawValue }
    var hint: String {
        switch self {
        case .notSpecified: return ""
        case .sedentary: return "Mostly sitting, minimal movement"
        case .lightlyActive: return "Some walking, light daily movement"
        case .moderatelyActive: return "Regular movement, on feet part of day"
        case .veryActive: return "Physically demanding job or high daily movement"
        case .extremelyActive: return "Heavy labor or athletic lifestyle"
        }
    }
}

enum GoalCategory: String, CaseIterable, Identifiable {
    case notSpecified = ""
    case fatLoss = "Fat loss"
    case muscleGain = "Muscle gain"
    case recomposition = "Body recomposition"
    case strength = "Strength"
    case generalHealth = "General health and fitness"
    var id: String { rawValue }
    var label: String { self == .notSpecified ? "Not specified" : rawValue }
}

enum HeightUnit: String, CaseIterable, Identifiable {
    case imperial = "ft/in"
    case metric = "cm"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .imperial: return "ft / in"
        case .metric: return "cm"
        }
    }
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
    static let weightValue = "195"
    static let weightUnit = "lb"
    static let goalDetail = "Visible abs and aesthetic proportions while maintaining performance for demanding clinical shifts"
    static let ageValue = 30
    static let heightFeet = 6
    static let heightInches = 0
    static let heightCm = 183
    static let heightUnit = "ft/in"
    static let trainingDays = 5
    static let sleepHours = 6.0
    static let sleepNotes = "Variable due to shift work"
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
        let defaults = UserDefaults.standard
        if let valueStr = defaults.string(forKey: AppSettingsKeys.analysisWeightValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let value = Double(valueStr), value > 50 {
            let unit = defaults.string(forKey: AppSettingsKeys.analysisWeightUnit) ?? "lb"
            return unit == "kg" ? value * 2.205 : value
        }
        let raw = defaults.string(forKey: AppSettingsKeys.analysisCurrentWeight) ?? ""
        let scanner = Scanner(string: raw)
        guard let value = scanner.scanDouble(), value > 50 else { return nil }
        let remaining = raw[scanner.currentIndex...].trimmingCharacters(in: .whitespaces).lowercased()
        return remaining.hasPrefix("kg") ? value * 2.205 : value
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
    static let analysisWeightValue = "analysis_profile_weight_value"
    static let analysisWeightUnit = "analysis_profile_weight_unit"
    static let analysisGoalDetail = "analysis_profile_goal_detail"
    static let analysisAgeValue = "analysis_profile_age_value"
    static let analysisHeightFeet = "analysis_profile_height_feet"
    static let analysisHeightInches = "analysis_profile_height_inches"
    static let analysisHeightCm = "analysis_profile_height_cm"
    static let analysisHeightUnit = "analysis_profile_height_unit"
    static let analysisTrainingDays = "analysis_profile_training_days"
    static let analysisSleepHours = "analysis_profile_sleep_hours"
    static let analysisSleepNotes = "analysis_profile_sleep_notes"
    static let medicalCurrentInjury = "medical_screen_current_injury"
    static let medicalPainDuringExercise = "medical_screen_pain_during_exercise"
    static let medicalCardioMetabolic = "medical_screen_cardio_metabolic"
    static let medicalMedications = "medical_screen_medications"
    static let medicalPregnancySurgery = "medical_screen_pregnancy_surgery"
    static let medicalSymptoms = "medical_screen_symptoms"
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

        migrateToStructuredFieldsIfNeeded()
    }

    private static func migrateToStructuredFieldsIfNeeded() {
        if defaults.object(forKey: AppSettingsKeys.analysisWeightValue) == nil {
            let raw = defaults.string(forKey: AppSettingsKeys.analysisCurrentWeight) ?? ""
            let scanner = Scanner(string: raw)
            if let value = scanner.scanDouble(), value > 0 {
                let tail = raw[scanner.currentIndex...].trimmingCharacters(in: .whitespaces).lowercased()
                let unit = tail.hasPrefix("kg") ? "kg" : "lb"
                defaults.set(String(format: "%.0f", value), forKey: AppSettingsKeys.analysisWeightValue)
                defaults.set(unit, forKey: AppSettingsKeys.analysisWeightUnit)
            }
        }

        if defaults.object(forKey: AppSettingsKeys.analysisAgeValue) == nil {
            let raw = defaults.string(forKey: AppSettingsKeys.analysisAge) ?? ""
            if let age = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), (1...120).contains(age) {
                defaults.set(age, forKey: AppSettingsKeys.analysisAgeValue)
            }
        }

        if defaults.object(forKey: AppSettingsKeys.analysisHeightFeet) == nil {
            let raw = defaults.string(forKey: AppSettingsKeys.analysisHeight) ?? ""
            if let (feet, inches) = parseImperialHeight(raw) {
                defaults.set(feet, forKey: AppSettingsKeys.analysisHeightFeet)
                defaults.set(inches, forKey: AppSettingsKeys.analysisHeightInches)
                defaults.set(HeightUnit.imperial.rawValue, forKey: AppSettingsKeys.analysisHeightUnit)
                let totalInches = feet * 12 + inches
                defaults.set(Int(round(Double(totalInches) * 2.54)), forKey: AppSettingsKeys.analysisHeightCm)
            } else if let cm = parseCmHeight(raw) {
                defaults.set(cm, forKey: AppSettingsKeys.analysisHeightCm)
                defaults.set(HeightUnit.metric.rawValue, forKey: AppSettingsKeys.analysisHeightUnit)
                let totalInches = Double(cm) / 2.54
                defaults.set(Int(totalInches) / 12, forKey: AppSettingsKeys.analysisHeightFeet)
                defaults.set(Int(totalInches) % 12, forKey: AppSettingsKeys.analysisHeightInches)
            }
        }

        if defaults.object(forKey: AppSettingsKeys.analysisTrainingDays) == nil {
            let raw = defaults.string(forKey: AppSettingsKeys.analysisTrainingFrequency) ?? ""
            let digits = raw.filter { $0.isNumber }
            if let first = digits.first, let days = Int(String(first)), (1...7).contains(days) {
                defaults.set(days, forKey: AppSettingsKeys.analysisTrainingDays)
            }
        }

        if defaults.object(forKey: AppSettingsKeys.analysisSleepHours) == nil {
            let raw = defaults.string(forKey: AppSettingsKeys.analysisAverageSleep) ?? ""
            let scanner = Scanner(string: raw)
            scanner.charactersToBeSkipped = CharacterSet.decimalDigits.inverted
            if let hours = scanner.scanDouble(), (1...14).contains(hours) {
                defaults.set(String(format: "%.1f", hours), forKey: AppSettingsKeys.analysisSleepHours)
            }
            let notes = raw.replacingOccurrences(of: "\\b\\d+[-–]?\\d*\\s*(hours?|hrs?)\\b", with: "", options: .regularExpression)
                .replacingOccurrences(of: "often|;|,", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                defaults.set(notes, forKey: AppSettingsKeys.analysisSleepNotes)
            }
        }

        if let current = defaults.string(forKey: AppSettingsKeys.analysisActivityLevel),
           !current.isEmpty,
           ActivityLevel(rawValue: current) == nil {
            let lower = current.lowercased()
            let mapped: ActivityLevel
            if lower.contains("sedentary") { mapped = .sedentary }
            else if lower.contains("extremely") || lower.contains("heavy labor") { mapped = .extremelyActive }
            else if lower.contains("very") || lower.contains("high") || lower.contains("demanding") || lower.contains("on feet") { mapped = .veryActive }
            else if lower.contains("moderate") || lower.contains("regular") { mapped = .moderatelyActive }
            else if lower.contains("light") { mapped = .lightlyActive }
            else { mapped = .notSpecified }
            if mapped != .notSpecified {
                defaults.set(mapped.rawValue, forKey: AppSettingsKeys.analysisActivityLevel)
            }
        }

        if defaults.object(forKey: AppSettingsKeys.analysisGoalDetail) == nil {
            let current = defaults.string(forKey: AppSettingsKeys.analysisPrimaryGoal) ?? ""
            if !current.isEmpty, GoalCategory(rawValue: current) == nil {
                let lower = current.lowercased()
                let category: GoalCategory
                if lower.contains("recomp") { category = .recomposition }
                else if lower.contains("fat loss") || lower.contains("cut") || lower.contains("lean out") { category = .fatLoss }
                else if lower.contains("muscle") || lower.contains("hypertrophy") || lower.contains("bulk") { category = .muscleGain }
                else if lower.contains("strength") || lower.contains("power") { category = .strength }
                else if lower.contains("health") || lower.contains("general") { category = .generalHealth }
                else { category = .notSpecified }
                if category != .notSpecified {
                    defaults.set(current, forKey: AppSettingsKeys.analysisGoalDetail)
                    defaults.set(category.rawValue, forKey: AppSettingsKeys.analysisPrimaryGoal)
                }
            }
        }
    }

    private static func parseImperialHeight(_ raw: String) -> (Int, Int)? {
        let pattern = #"(\d+)\s*[''′]\s*(\d+)\s*[""″]?"#
        guard let match = raw.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(raw[match])
        let digits = matched.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard digits.count >= 2,
              let feet = Int(digits[0]), (3...8).contains(feet),
              let inches = Int(digits[1]), (0...11).contains(inches) else { return nil }
        return (feet, inches)
    }

    private static func parseCmHeight(_ raw: String) -> Int? {
        let lower = raw.lowercased()
        guard lower.contains("cm") else { return nil }
        let scanner = Scanner(string: raw)
        scanner.charactersToBeSkipped = CharacterSet.decimalDigits.inverted
        guard let value = scanner.scanInt(), (100...250).contains(value) else { return nil }
        return value
    }

    static var analysisClientProfile: AnalysisClientProfile {
        AnalysisClientProfile(
            age: composedAgeString(),
            sex: string(for: AppSettingsKeys.analysisSex, default: Config.defaultAnalysisSex),
            build: string(for: AppSettingsKeys.analysisBuild, default: Config.defaultAnalysisBuild),
            height: composedHeightString(),
            currentWeight: composedWeightString(),
            occupation: string(for: AppSettingsKeys.analysisOccupation, default: Config.defaultAnalysisOccupation),
            trainingFrequency: composedTrainingFrequencyString(),
            trainingAge: string(for: AppSettingsKeys.analysisTrainingAge, default: Config.defaultAnalysisTrainingAge),
            equipmentAccess: string(for: AppSettingsKeys.analysisEquipmentAccess, default: Config.defaultAnalysisEquipmentAccess),
            averageSleep: composedSleepString(),
            painHistory: composedMedicalContext(),
            activityLevel: string(for: AppSettingsKeys.analysisActivityLevel, default: Config.defaultAnalysisActivityLevel),
            primaryGoal: composedGoalString(),
            lifestyleConstraints: string(for: AppSettingsKeys.analysisLifestyleConstraints, default: Config.defaultAnalysisLifestyleConstraints)
        )
    }

    private static func composedAgeString() -> String {
        if let age = defaults.object(forKey: AppSettingsKeys.analysisAgeValue) as? Int, age > 0 {
            return "\(age)"
        }
        return string(for: AppSettingsKeys.analysisAge, default: Config.defaultAnalysisAge)
    }

    private static func composedHeightString() -> String {
        let unitRaw = defaults.string(forKey: AppSettingsKeys.analysisHeightUnit) ?? ""
        if unitRaw == HeightUnit.metric.rawValue {
            let cm = defaults.integer(forKey: AppSettingsKeys.analysisHeightCm)
            if (100...250).contains(cm) { return "\(cm) cm" }
        } else if unitRaw == HeightUnit.imperial.rawValue {
            let feet = defaults.integer(forKey: AppSettingsKeys.analysisHeightFeet)
            let inches = defaults.integer(forKey: AppSettingsKeys.analysisHeightInches)
            if (3...8).contains(feet) { return "\(feet)'\(inches)\"" }
        }
        return string(for: AppSettingsKeys.analysisHeight, default: Config.defaultAnalysisHeight)
    }

    private static func composedWeightString() -> String {
        let value = string(for: AppSettingsKeys.analysisWeightValue, default: "")
        guard !value.isEmpty else {
            return string(for: AppSettingsKeys.analysisCurrentWeight, default: Config.defaultAnalysisCurrentWeight)
        }
        let unit = string(for: AppSettingsKeys.analysisWeightUnit, default: WeightUnit.lb.rawValue)
        return "\(value) \(unit)"
    }

    private static func composedTrainingFrequencyString() -> String {
        if let days = defaults.object(forKey: AppSettingsKeys.analysisTrainingDays) as? Int, (1...7).contains(days) {
            return "\(days) days/week"
        }
        return string(for: AppSettingsKeys.analysisTrainingFrequency, default: Config.defaultAnalysisTrainingFrequency)
    }

    private static func composedSleepString() -> String {
        let hoursStr = defaults.string(forKey: AppSettingsKeys.analysisSleepHours) ?? ""
        let notes = defaults.string(forKey: AppSettingsKeys.analysisSleepNotes)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let hours = Double(hoursStr), hours > 0 {
            let hoursText = hours.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(hours)) hours/night"
                : String(format: "%.1f hours/night", hours)
            return notes.isEmpty ? hoursText : "\(hoursText); \(notes)"
        }
        return string(for: AppSettingsKeys.analysisAverageSleep, default: Config.defaultAnalysisAverageSleep)
    }

    private static func composedMedicalContext() -> String {
        var parts: [String] = []

        var flags: [String] = []
        if defaults.bool(forKey: AppSettingsKeys.medicalCurrentInjury) { flags.append("current injury") }
        if defaults.bool(forKey: AppSettingsKeys.medicalPainDuringExercise) { flags.append("pain during exercise") }
        if defaults.bool(forKey: AppSettingsKeys.medicalCardioMetabolic) { flags.append("cardiovascular/metabolic/renal condition") }
        if defaults.bool(forKey: AppSettingsKeys.medicalMedications) { flags.append("medication affecting HR/BP/balance/glucose") }
        if defaults.bool(forKey: AppSettingsKeys.medicalPregnancySurgery) { flags.append("pregnant/postpartum/recent surgery") }
        if defaults.bool(forKey: AppSettingsKeys.medicalSymptoms) { flags.append("dizziness/chest pain/fainting/unusual SOB") }

        if !flags.isEmpty {
            parts.append("Medical screening flags: " + flags.joined(separator: "; ") + ". Recommend medical clearance before high-intensity training.")
        }

        let painText = string(for: AppSettingsKeys.analysisPainHistory, default: Config.defaultAnalysisPainHistory)
        if !painText.isEmpty {
            parts.append(painText)
        }

        return parts.joined(separator: " | ")
    }

    private static func composedGoalString() -> String {
        let category = string(for: AppSettingsKeys.analysisPrimaryGoal, default: "")
        let detail = string(for: AppSettingsKeys.analysisGoalDetail, default: "")
        if category.isEmpty && detail.isEmpty { return "" }
        if detail.isEmpty { return category }
        if category.isEmpty { return detail }
        return "\(category) — \(detail)"
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

    static var profileCompleteness: ProfileCompleteness {
        let checks: [(String, Bool)] = [
            ("Age", defaults.object(forKey: AppSettingsKeys.analysisAgeValue) != nil),
            ("Sex", !string(for: AppSettingsKeys.analysisSex, default: "").isEmpty),
            ("Height", defaults.object(forKey: AppSettingsKeys.analysisHeightFeet) != nil || defaults.object(forKey: AppSettingsKeys.analysisHeightCm) != nil),
            ("Weight", !string(for: AppSettingsKeys.analysisWeightValue, default: "").isEmpty),
            ("Activity level", !string(for: AppSettingsKeys.analysisActivityLevel, default: "").isEmpty),
            ("Goal", !string(for: AppSettingsKeys.analysisPrimaryGoal, default: "").isEmpty),
            ("Training frequency", defaults.object(forKey: AppSettingsKeys.analysisTrainingDays) != nil),
            ("Sleep", defaults.object(forKey: AppSettingsKeys.analysisSleepHours) != nil),
            ("Equipment", !string(for: AppSettingsKeys.analysisEquipmentAccess, default: "").isEmpty),
            ("Training experience", !string(for: AppSettingsKeys.analysisTrainingAge, default: "").isEmpty),
            ("Occupation", !string(for: AppSettingsKeys.analysisOccupation, default: "").isEmpty),
            ("Pain / injury", !string(for: AppSettingsKeys.analysisPainHistory, default: "").isEmpty),
        ]
        let filled = checks.filter(\.1).count
        let missing = checks.filter { !$0.1 }.map(\.0)
        return ProfileCompleteness(filledCount: filled, totalCount: checks.count, missingFields: missing)
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
