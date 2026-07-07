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
    static var medicalScreeningGate: MedicalScreeningGate { MedicalScreeningGate.evaluate() }
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

struct MedicalScreeningGate {
    enum GateLevel: Comparable {
        case clear
        case caution
        case warning
    }

    let level: GateLevel
    let alerts: [String]

    static func evaluate() -> MedicalScreeningGate {
        let defaults = UserDefaults.standard
        var alerts: [String] = []
        var level: GateLevel = .clear

        if defaults.bool(forKey: AppSettingsKeys.medicalSymptoms) {
            alerts.append("You reported dizziness, chest pain, fainting, or unusual shortness of breath. Medical clearance is strongly recommended before high-intensity training.")
            level = .warning
        }

        if defaults.bool(forKey: AppSettingsKeys.medicalCardioMetabolic) {
            alerts.append("You reported a cardiovascular, metabolic, renal, or blood pressure condition. Consider medical clearance before vigorous exercise.")
            if level < .caution { level = .caution }
        }

        if defaults.bool(forKey: AppSettingsKeys.medicalPregnancySurgery) {
            alerts.append("You indicated pregnancy, postpartum status, or recent surgery. Exercise programming should be conservative until cleared.")
            if level < .caution { level = .caution }
        }

        if defaults.bool(forKey: AppSettingsKeys.medicalCurrentInjury) {
            let painContext = defaults.string(forKey: AppSettingsKeys.analysisPainHistory)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if painContext.isEmpty {
                alerts.append("You indicated a current injury but the Pain / Injury Context field in Settings is empty. Adding details will improve exercise selection safety.")
            }
            if level < .caution { level = .caution }
        }

        if defaults.bool(forKey: AppSettingsKeys.medicalPainDuringExercise) {
            if level < .caution { level = .caution }
        }

        if defaults.bool(forKey: AppSettingsKeys.medicalMedications) {
            if level < .caution { level = .caution }
        }

        return MedicalScreeningGate(level: level, alerts: alerts)
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

    var defaultDetail: String {
        switch self {
        case .notSpecified:
            return ""
        case .fatLoss:
            return "Reduce body fat while preserving muscle, training performance, and sustainable energy."
        case .muscleGain:
            return "Build visible muscle with progressive training while limiting unnecessary fat gain."
        case .recomposition:
            return "Improve muscular definition and proportions while gradually reducing body fat."
        case .strength:
            return "Increase strength in repeatable compound movement patterns while maintaining balanced development."
        case .generalHealth:
            return "Improve fitness, movement quality, energy, and long-term training consistency."
        }
    }
}

nonisolated protocol ProfilePresetOption: Hashable, Identifiable, CaseIterable {
    var label: String { get }
}

nonisolated enum BuildProfileOption: String, ProfilePresetOption {
    case notSpecified = ""
    case leanNarrow = "Lean / Narrow Frame"
    case muscularMedium = "Muscular / Medium Frame (Mesomorph)"
    case broadSturdy = "Broad / Sturdy Frame"
    case averageMixed = "Average / Mixed Frame"

    var id: String { rawValue }
    var label: String { self == .notSpecified ? "Not specified" : rawValue }

    var promptDescription: String {
        switch self {
        case .notSpecified:
            return ""
        case .leanNarrow:
            return "Lean, relatively narrow frame with less baseline muscular thickness; use this only as descriptive context, not as a fixed metabolic body type."
        case .muscularMedium:
            return "Naturally muscular appearance with a medium frame and visible baseline muscle development; the familiar mesomorph label is descriptive only, not a medical classification."
        case .broadSturdy:
            return "Broad, sturdy frame with wider joints or torso structure and substantial baseline mass; distinguish skeletal frame from body-fat level."
        case .averageMixed:
            return "Average frame with mixed lean, muscular, and broad characteristics; avoid assuming a fixed somatotype or metabolism."
        }
    }

    static func fromStoredValue(_ value: String) -> BuildProfileOption {
        if let exact = Self(rawValue: value) { return exact }
        let normalized = value.lowercased()
        if normalized.contains("mesomorph") || normalized.contains("muscular") { return .muscularMedium }
        if normalized.contains("lean") || normalized.contains("narrow") || normalized.contains("ectomorph") { return .leanNarrow }
        if normalized.contains("broad") || normalized.contains("sturdy") || normalized.contains("endomorph") { return .broadSturdy }
        if normalized.contains("average") || normalized.contains("mixed") { return .averageMixed }
        return .notSpecified
    }
}

nonisolated enum TrainingExperienceOption: String, ProfilePresetOption {
    case notSpecified = ""
    case beginner = "Beginner"
    case novice = "Novice"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case returning = "Returning After a Layoff"

    var id: String { rawValue }
    var label: String { self == .notSpecified ? "Not specified" : rawValue }

    var promptDescription: String {
        switch self {
        case .notSpecified:
            return ""
        case .beginner:
            return "Less than 6 months of consistent resistance training; prioritize technique, simple progression, and low exercise complexity."
        case .novice:
            return "About 6-18 months of consistent resistance training; can progress frequently but still benefits from stable exercises and straightforward loading."
        case .intermediate:
            return "Roughly 1.5-5 years of consistent resistance training; needs planned progression, sufficient volume, and fatigue management."
        case .advanced:
            return "More than 5 years of serious, consistent resistance training; requires individualized loading, careful fatigue management, and highly trackable exercise selection."
        case .returning:
            return "Has prior resistance-training experience but is returning after a meaningful layoff; use conservative volume and load while rebuilding tolerance."
        }
    }

    static func fromStoredValue(_ value: String) -> TrainingExperienceOption {
        if let exact = Self(rawValue: value) { return exact }
        let normalized = value.lowercased()
        if normalized.contains("return") || normalized.contains("layoff") { return .returning }
        if normalized.contains("advanced") || normalized.contains("6 years") || normalized.contains("7 years") || normalized.contains("8 years") || normalized.contains("9 years") { return .advanced }
        if normalized.contains("intermediate") || normalized.contains("2 years") || normalized.contains("3 years") || normalized.contains("4 years") || normalized.contains("5 years") { return .intermediate }
        if normalized.contains("novice") || normalized.contains("1 year") { return .novice }
        if normalized.contains("beginner") || normalized.contains("month") || normalized.contains("new") { return .beginner }
        return .notSpecified
    }
}

nonisolated enum EquipmentAccessOption: String, ProfilePresetOption {
    case notSpecified = ""
    case commercialGym = "Full Commercial Gym"
    case homeGym = "Home Gym"
    case dumbbellsBench = "Dumbbells + Bench"
    case minimal = "Bands / Bodyweight / Minimal"

    var id: String { rawValue }
    var label: String { self == .notSpecified ? "Not specified" : rawValue }

    var promptDescription: String {
        switch self {
        case .notSpecified:
            return ""
        case .commercialGym:
            return "Full commercial gym access including barbells, dumbbells, benches, cables, plate-loaded and selectorized machines, racks, and common cardio equipment."
        case .homeGym:
            return "Home-gym access with a rack, barbell, plates, adjustable bench, dumbbells, and basic accessories; do not assume specialized machines or a full cable station."
        case .dumbbellsBench:
            return "Adjustable dumbbells and a bench are available; avoid programming barbells, cable stacks, or specialized machines."
        case .minimal:
            return "Minimal equipment limited to bodyweight, resistance bands, and small portable accessories; use movements that do not require gym machines or heavy free weights."
        }
    }

    static func fromStoredValue(_ value: String) -> EquipmentAccessOption {
        if let exact = Self(rawValue: value) { return exact }
        let normalized = value.lowercased()
        if normalized.contains("commercial") || normalized.contains("full machine") || normalized.contains("full gym") { return .commercialGym }
        if normalized.contains("home gym") || normalized.contains("rack") || normalized.contains("barbell") { return .homeGym }
        if normalized.contains("dumbbell") && normalized.contains("bench") { return .dumbbellsBench }
        if normalized.contains("band") || normalized.contains("bodyweight") || normalized.contains("minimal") { return .minimal }
        return .notSpecified
    }
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
    static let build = BuildProfileOption.muscularMedium.rawValue
    static let height = "6'0\""
    static let currentWeight = "195 lbs"
    static let occupation = "Emergency medicine physician"
    static let trainingFrequency = "Training 5-6 days/week"
    static let trainingAge = TrainingExperienceOption.intermediate.rawValue
    static let equipmentAccess = EquipmentAccessOption.commercialGym.rawValue
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

enum MacroTargetSource: Equatable {
    case analysis
    case adaptiveReview
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
    static func resolve(
        from analysis: BodyAnalysisResult?,
        bodyweightLbs: Double? = nil,
        adaptiveOverride: AdaptiveMacroOverride? = nil
    ) -> DailyMacroTargets {
        if let adaptiveOverride {
            return resolvedTargets(
                calories: adaptiveOverride.calories,
                proteinG: adaptiveOverride.proteinG,
                carbsG: adaptiveOverride.carbsG,
                fatG: adaptiveOverride.fatG,
                bodyweightLbs: bodyweightLbs,
                source: .adaptiveReview
            )
        }

        if let macros = analysis?.macroTargets {
            return resolvedTargets(
                calories: macros.calories,
                proteinG: macros.proteinG,
                carbsG: macros.carbsG,
                fatG: macros.fatG,
                bodyweightLbs: bodyweightLbs,
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

    private static func resolvedTargets(
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        bodyweightLbs: Double?,
        source: MacroTargetSource
    ) -> DailyMacroTargets {
        let bw = bodyweightLbs ?? profileBodyweightLbs()
        var adjustments: [String] = []
        let calFloor = contextAwareCalorieFloor(baseFloor: calorieFloor(bodyweightLbs: bw))
        let proFloor = proteinFloor(bodyweightLbs: bw)
        let fFloor = fatFloor(bodyweightLbs: bw)
        let resolvedCalories = max(calories, calFloor)
        let resolvedProtein = max(proteinG, proFloor)
        let resolvedFat = max(fatG, fFloor)

        if calories < calFloor {
            adjustments.append("Calories raised from \(calories) to \(calFloor) (safety floor: BW×10)")
        }
        if proteinG < proFloor {
            adjustments.append("Protein raised from \(Int(proteinG))g to \(Int(proFloor))g (safety floor: 1.4 g/kg)")
        }
        if fatG < fFloor {
            adjustments.append("Fat raised from \(Int(fatG))g to \(Int(fFloor))g (safety floor: 0.35 g/kg)")
        }

        return DailyMacroTargets(
            calories: resolvedCalories,
            proteinG: resolvedProtein,
            carbsG: max(carbsG, 50),
            fatG: resolvedFat,
            source: source,
            floorAdjustments: adjustments
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

    private static func contextAwareCalorieFloor(baseFloor: Int) -> Int {
        let defaults = UserDefaults.standard
        var floor = baseFloor

        if let age = defaults.object(forKey: AppSettingsKeys.analysisAgeValue) as? Int, age > 0, age < 18 {
            floor = max(floor, 1500)
        }

        if defaults.bool(forKey: AppSettingsKeys.medicalPregnancySurgery) {
            floor = max(floor, 1800)
        }

        let goal = defaults.string(forKey: AppSettingsKeys.analysisPrimaryGoal) ?? ""
        if goal == GoalCategory.strength.rawValue {
            floor = max(floor, 1600)
        }

        return floor
    }
}

// MARK: - Training Phase

/// Which direction the body-weight goal points relative to the current trend
/// weight. Every good/bad judgment on progress surfaces (weight delta badges,
/// calorie-average coloring, goal copy) must read this one resolver so a
/// deliberate gaining phase is never scored with weight-loss semantics.
enum TrainingPhase {
    case cutting
    case maintaining
    case gaining

    /// Deadband around the goal treated as maintenance so day-to-day noise near
    /// goal weight doesn't flip the dashboard between cut and gain semantics.
    static let maintenanceBandLbs = 2.0

    static func resolve(
        currentTrendWeightLbs: Double?,
        goalWeightLbs: Double = Config.bodyWeightGoalLbs
    ) -> TrainingPhase {
        guard let current = currentTrendWeightLbs else { return .maintaining }
        if goalWeightLbs < current - Self.maintenanceBandLbs { return .cutting }
        if goalWeightLbs > current + Self.maintenanceBandLbs { return .gaining }
        return .maintaining
    }

    /// Whether a weekly body-weight change moves toward the goal.
    /// `nil` means the change is inside the noise band and should render neutral.
    func isWeeklyChangeGood(_ weeklyChangeLbs: Double) -> Bool? {
        let noiseBandLbs = 0.15
        guard abs(weeklyChangeLbs) > noiseBandLbs else { return nil }
        switch self {
        case .cutting: return weeklyChangeLbs < 0
        case .gaining: return weeklyChangeLbs > 0
        case .maintaining: return abs(weeklyChangeLbs) < 0.75
        }
    }

    /// Whether an average calorie intake is on-plan against the target.
    /// Over target while gaining is expected; under-eating is the miss there.
    func isCalorieAverageGood(average: Double, target: Double) -> Bool {
        switch self {
        case .cutting, .maintaining: return average <= target
        case .gaining: return average >= target * 0.95
        }
    }
}

// MARK: - Analysis Freshness Policy

/// Single source of truth for how old a body analysis can be before the UI
/// nudges. Previously three call sites used three different day counts
/// (30/45, 42, 56), so the same analysis age produced conflicting verdicts.
enum AnalysisFreshness {
    case fresh
    case aging
    case stale

    static let agingAfterDays = 30
    static let staleAfterDays = 45

    static func resolve(daysAgo: Int) -> AnalysisFreshness {
        if daysAgo <= Self.agingAfterDays { return .fresh }
        if daysAgo <= Self.staleAfterDays { return .aging }
        return .stale
    }
}

// MARK: - Weight Goal Progress

/// Progress toward the body-weight goal measured from a phase anchor (the
/// trend weight when the goal was last set) rather than the oldest entry ever
/// logged, with explicit at-goal and past-goal states instead of a bar that
/// clamps at 100% forever and copy that misreads overshoot as approach.
enum WeightGoalState {
    case noData
    case approaching(progress: Double, remainingLbs: Double)
    case atGoal
    case pastGoal(overshootLbs: Double)
}

enum WeightGoalProgressResolver {
    /// Within this band of the goal the state reads "at goal".
    static let atGoalBandLbs = 1.5
    /// When no goal-change anchor is stored, measure from the trend weight
    /// roughly 12 weeks back so imported multi-year history can't define "start".
    static let fallbackAnchorWindowDays = 84

    static func resolve(
        trendPoints: [(date: Date, trendWeightLbs: Double)],
        goalLbs: Double,
        anchorDate: Date?,
        now: Date = Date()
    ) -> WeightGoalState {
        guard let current = trendPoints.last?.trendWeightLbs else { return .noData }
        if abs(current - goalLbs) <= Self.atGoalBandLbs { return .atGoal }

        let effectiveAnchorDate = anchorDate
            ?? Calendar.current.date(byAdding: .day, value: -Self.fallbackAnchorWindowDays, to: now)
            ?? now
        let anchorWeight = trendPoints.last(where: { $0.date <= effectiveAnchorDate })?.trendWeightLbs
            ?? trendPoints.first?.trendWeightLbs
            ?? current

        let anchorSide = anchorWeight - goalLbs
        let currentSide = current - goalLbs
        if anchorSide != 0, currentSide.sign != anchorSide.sign {
            return .pastGoal(overshootLbs: abs(currentSide))
        }

        let totalDistance = abs(anchorSide)
        guard totalDistance > 0.01 else {
            // Anchored at the goal but currently outside the band: drifted away.
            return .approaching(progress: 0, remainingLbs: abs(currentSide))
        }
        let covered = (totalDistance - abs(currentSide)) / totalDistance
        return .approaching(
            progress: max(0, min(1, covered)),
            remainingLbs: abs(currentSide)
        )
    }
}

nonisolated enum AppSettingsKeys {
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
    static let derivedSleepTrendSummary = "derived_sleep_trend_summary"

    static let calorieTarget = "nutrition_calorie_target"
    static let proteinTarget = "nutrition_protein_target"
    static let carbTarget = "nutrition_carb_target"
    static let fatTarget = "nutrition_fat_target"
    static let nutritionShiftWorkMode = "nutrition_shift_work_mode"
    static let bodyWeightGoal = "body_weight_goal"
    static let bodyWeightGoalSetAt = "body_weight_goal_set_at"
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
                let roundedTotalInches = Int(round(Double(cm) / 2.54))
                defaults.set(roundedTotalInches / 12, forKey: AppSettingsKeys.analysisHeightFeet)
                defaults.set(roundedTotalInches % 12, forKey: AppSettingsKeys.analysisHeightInches)
            }
        }

        if defaults.object(forKey: AppSettingsKeys.analysisTrainingDays) == nil {
            let raw = defaults.string(forKey: AppSettingsKeys.analysisTrainingFrequency) ?? ""
            let digits = raw.filter { $0.isNumber }
            if let first = digits.first, let days = Int(String(first)), (1...7).contains(days) {
                defaults.set(days, forKey: AppSettingsKeys.analysisTrainingDays)
            }
        }

        migratePresetValue(
            forKey: AppSettingsKeys.analysisBuild,
            mappedValue: BuildProfileOption.fromStoredValue(
                defaults.string(forKey: AppSettingsKeys.analysisBuild) ?? ""
            ).rawValue
        )
        migratePresetValue(
            forKey: AppSettingsKeys.analysisTrainingAge,
            mappedValue: TrainingExperienceOption.fromStoredValue(
                defaults.string(forKey: AppSettingsKeys.analysisTrainingAge) ?? ""
            ).rawValue
        )
        migratePresetValue(
            forKey: AppSettingsKeys.analysisEquipmentAccess,
            mappedValue: EquipmentAccessOption.fromStoredValue(
                defaults.string(forKey: AppSettingsKeys.analysisEquipmentAccess) ?? ""
            ).rawValue
        )

        if defaults.object(forKey: AppSettingsKeys.analysisSleepHours) == nil {
            let raw = defaults.string(forKey: AppSettingsKeys.analysisAverageSleep) ?? ""
            var sleepNumbers: [Double] = []
            let scanner = Scanner(string: raw)
            while !scanner.isAtEnd {
                if let num = scanner.scanDouble() {
                    if (1...14).contains(num) { sleepNumbers.append(num) }
                } else {
                    _ = scanner.scanCharacter()
                }
            }
            if !sleepNumbers.isEmpty {
                let midpoint = sleepNumbers.reduce(0, +) / Double(sleepNumbers.count)
                defaults.set(String(format: "%.1f", midpoint), forKey: AppSettingsKeys.analysisSleepHours)
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

    private static func migratePresetValue(forKey key: String, mappedValue: String) {
        let current = defaults.string(forKey: key) ?? ""
        guard !current.isEmpty, !mappedValue.isEmpty, current != mappedValue else { return }
        defaults.set(mappedValue, forKey: key)
    }

    static var analysisClientProfile: AnalysisClientProfile {
        AnalysisClientProfile(
            age: composedAgeString(),
            sex: string(for: AppSettingsKeys.analysisSex, default: Config.defaultAnalysisSex),
            build: buildPromptDescription(),
            height: composedHeightString(),
            currentWeight: composedWeightString(),
            occupation: string(for: AppSettingsKeys.analysisOccupation, default: Config.defaultAnalysisOccupation),
            trainingFrequency: composedTrainingFrequencyString(),
            trainingAge: trainingExperiencePromptDescription(),
            equipmentAccess: equipmentAccessPromptDescription(),
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

    private static func buildPromptDescription() -> String {
        let stored = string(for: AppSettingsKeys.analysisBuild, default: Config.defaultAnalysisBuild)
        let option = BuildProfileOption.fromStoredValue(stored)
        return option == .notSpecified ? stored : option.promptDescription
    }

    private static func trainingExperiencePromptDescription() -> String {
        let stored = string(for: AppSettingsKeys.analysisTrainingAge, default: Config.defaultAnalysisTrainingAge)
        let option = TrainingExperienceOption.fromStoredValue(stored)
        return option == .notSpecified ? stored : option.promptDescription
    }

    private static func equipmentAccessPromptDescription() -> String {
        let stored = string(for: AppSettingsKeys.analysisEquipmentAccess, default: Config.defaultAnalysisEquipmentAccess)
        let option = EquipmentAccessOption.fromStoredValue(stored)
        return option == .notSpecified ? stored : option.promptDescription
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
        return string(for: AppSettingsKeys.analysisPainHistory, default: Config.defaultAnalysisPainHistory)
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
        let manualRecovery = string(
            for: AppSettingsKeys.analysisCheckInRecoverySleep,
            default: Config.defaultAnalysisCheckInRecoverySleep
        )
        let derivedRecovery = string(for: AppSettingsKeys.derivedSleepTrendSummary, default: "")
        let combinedRecovery = [derivedRecovery, manualRecovery]
            .filter { !$0.isEmpty }
            .joined(separator: " Additional context: ")

        return AnalysisCheckIn(
            trainingContext: string(for: AppSettingsKeys.analysisCheckInTrainingContext, default: Config.defaultAnalysisCheckInTrainingContext),
            bodyweightTrend: string(for: AppSettingsKeys.analysisCheckInBodyweightTrend, default: Config.defaultAnalysisCheckInBodyweightTrend),
            recoverySleep: combinedRecovery,
            stressSchedule: string(for: AppSettingsKeys.analysisCheckInStressSchedule, default: Config.defaultAnalysisCheckInStressSchedule),
            sorenessPain: string(for: AppSettingsKeys.analysisCheckInSorenessPain, default: Config.defaultAnalysisCheckInSorenessPain),
            nutritionAdherence: string(for: AppSettingsKeys.analysisCheckInNutritionAdherence, default: Config.defaultAnalysisCheckInNutritionAdherence),
            hungerLevel: integer(for: AppSettingsKeys.analysisCheckInHungerLevel, default: Config.defaultAnalysisCheckInHungerLevel, min: 0, max: 10),
            energyLevel: integer(for: AppSettingsKeys.analysisCheckInEnergyLevel, default: Config.defaultAnalysisCheckInEnergyLevel, min: 0, max: 10),
            cravingsLevel: integer(for: AppSettingsKeys.analysisCheckInCravingsLevel, default: Config.defaultAnalysisCheckInCravingsLevel, min: 0, max: 10)
        )
    }

    static var medicalScreeningSnapshot: MedicalScreeningSnapshot? {
        let snapshot = MedicalScreeningSnapshot(
            currentInjury: defaults.bool(forKey: AppSettingsKeys.medicalCurrentInjury),
            painDuringExercise: defaults.bool(forKey: AppSettingsKeys.medicalPainDuringExercise),
            cardioMetabolic: defaults.bool(forKey: AppSettingsKeys.medicalCardioMetabolic),
            medicationsAffectingVitals: defaults.bool(forKey: AppSettingsKeys.medicalMedications),
            pregnancySurgery: defaults.bool(forKey: AppSettingsKeys.medicalPregnancySurgery),
            redFlagSymptoms: defaults.bool(forKey: AppSettingsKeys.medicalSymptoms)
        )
        return snapshot.hasAnyFlags ? snapshot : nil
    }

    static var analysisInputContext: AnalysisInputContext {
        AnalysisInputContext(
            profile: analysisClientProfile.snapshot,
            checkIn: analysisCheckIn.snapshot,
            progress: nil,
            medicalScreening: medicalScreeningSnapshot
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

    /// When the body-weight goal was last changed. Goal progress is measured
    /// from the trend weight at this date (the current "campaign"), not from
    /// the oldest weight entry ever logged.
    static var bodyWeightGoalSetAt: Date? {
        let stored = defaults.double(forKey: AppSettingsKeys.bodyWeightGoalSetAt)
        guard stored > 0 else { return nil }
        return Date(timeIntervalSince1970: stored)
    }

    static func stampBodyWeightGoalChange(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: AppSettingsKeys.bodyWeightGoalSetAt)
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
    case notConfigured

    var apiKey: String? {
        switch self {
        case .configured(let key): return key
        case .notConfigured: return nil
        }
    }

    var isConfigured: Bool { apiKey != nil }

    var inlineHelpText: String {
        switch self {
        case .configured: return ""
        case .notConfigured:
            return "AI is unavailable. Add your Anthropic API key in Transform Settings."
        }
    }

    var startupAlertMessage: String? {
        guard !isConfigured else { return nil }
        return """
        \(inlineHelpText)

        Open Settings and choose Add API Key. The key is stored in this device's Keychain and never leaves the device.
        """
    }

    var requestFailureMessage: String {
        startupAlertMessage ?? inlineHelpText
    }
}

enum APIKeyProvider {
    static var anthropicKeyStatus: AnthropicAPIKeyStatus {
        guard let raw = AnthropicAPIKeyStore.storedKey else {
            return .notConfigured
        }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .notConfigured }
        return .configured(cleaned)
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
