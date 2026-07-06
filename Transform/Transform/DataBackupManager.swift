import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

nonisolated private enum BackupFormat {
    static let currentVersion = 9
    static let supportedVersions: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9]
}

@MainActor
private func mainActorMap<Input, Output>(
    _ values: [Input],
    _ transform: @MainActor (Input) -> Output
) -> [Output] {
    var results: [Output] = []
    results.reserveCapacity(values.count)
    for value in values {
        results.append(transform(value))
    }
    return results
}

@MainActor
private func mainActorFirst<Input>(
    in values: [Input],
    where predicate: @MainActor (Input) -> Bool
) -> Input? {
    for value in values where predicate(value) {
        return value
    }
    return nil
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let incoming = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = incoming
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated struct TransformBackupPayload: Codable {
    let version: Int
    let exportedAt: Date
    let weights: [WeightSnapshot]
    let sleep: [SleepSnapshot]?
    let measurements: [MeasurementSnapshot]
    let nutrition: [NutritionSnapshot]
    let favorites: [FavoriteFoodSnapshot]
    let savedNutritionProtocols: [SavedNutritionProtocolSnapshot]?
    let progressPhotos: [ProgressPhotoSnapshot]?
    let analyses: [AnalysisSnapshot]
    let workouts: [WorkoutProgramSnapshot]
    let exerciseWeights: [ExerciseWeightSnapshot]?
    let exercisePerformanceLogs: [ExercisePerformanceLogSnapshot]?
    let profileSettings: ProfileSettingsSnapshot?

    init(
        version: Int,
        exportedAt: Date,
        weights: [WeightSnapshot],
        sleep: [SleepSnapshot]?,
        measurements: [MeasurementSnapshot],
        nutrition: [NutritionSnapshot],
        favorites: [FavoriteFoodSnapshot],
        savedNutritionProtocols: [SavedNutritionProtocolSnapshot]?,
        progressPhotos: [ProgressPhotoSnapshot]?,
        analyses: [AnalysisSnapshot],
        workouts: [WorkoutProgramSnapshot],
        exerciseWeights: [ExerciseWeightSnapshot]?,
        exercisePerformanceLogs: [ExercisePerformanceLogSnapshot]?,
        profileSettings: ProfileSettingsSnapshot? = nil
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.weights = weights
        self.sleep = sleep
        self.measurements = measurements
        self.nutrition = nutrition
        self.favorites = favorites
        self.savedNutritionProtocols = savedNutritionProtocols
        self.progressPhotos = progressPhotos
        self.analyses = analyses
        self.workouts = workouts
        self.exerciseWeights = exerciseWeights
        self.exercisePerformanceLogs = exercisePerformanceLogs
        self.profileSettings = profileSettings
    }
}

// Legacy backup shape (before sugar/fiber/favorites fields were introduced).
nonisolated struct LegacyTransformBackupPayload: Codable {
    let weights: [WeightSnapshot]
    let measurements: [MeasurementSnapshot]
    let nutrition: [LegacyNutritionSnapshot]
    let analyses: [AnalysisSnapshot]
    let workouts: [WorkoutProgramSnapshot]
}

nonisolated struct LegacyNutritionSnapshot: Codable {
    let date: Date
    let mealName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let notes: String
}

nonisolated struct WeightSnapshot: Codable {
    let date: Date
    let weightLbs: Double
    let notes: String
}

nonisolated struct SleepSnapshot: Codable {
    let date: Date
    let durationHours: Double
    let qualityRating: Int
    let shiftTypeRaw: String
    let notes: String
    let startDate: Date?
    let endDate: Date?
    let episodeTypeRaw: String?
}

nonisolated struct MeasurementSnapshot: Codable {
    let date: Date
    let chestIn: Double?
    let waistIn: Double?
    let hipsIn: Double?
    let neckIn: Double?
    let leftArmIn: Double?
    let rightArmIn: Double?
    let leftThighIn: Double?
    let rightThighIn: Double?
    let leftCalfIn: Double?
    let rightCalfIn: Double?
    let bodyFatPct: Double?
    let notes: String
    let measurementTiming: String?
    let isStandardMeasurement: Bool?

    init(
        date: Date,
        chestIn: Double?,
        waistIn: Double?,
        hipsIn: Double?,
        neckIn: Double?,
        leftArmIn: Double?,
        rightArmIn: Double?,
        leftThighIn: Double?,
        rightThighIn: Double?,
        leftCalfIn: Double? = nil,
        rightCalfIn: Double? = nil,
        bodyFatPct: Double?,
        notes: String,
        measurementTiming: String? = nil,
        isStandardMeasurement: Bool? = nil
    ) {
        self.date = date
        self.chestIn = chestIn
        self.waistIn = waistIn
        self.hipsIn = hipsIn
        self.neckIn = neckIn
        self.leftArmIn = leftArmIn
        self.rightArmIn = rightArmIn
        self.leftThighIn = leftThighIn
        self.rightThighIn = rightThighIn
        self.leftCalfIn = leftCalfIn
        self.rightCalfIn = rightCalfIn
        self.bodyFatPct = bodyFatPct
        self.notes = notes
        self.measurementTiming = measurementTiming
        self.isStandardMeasurement = isStandardMeasurement
    }
}

nonisolated struct NutritionSnapshot: Codable {
    let date: Date
    let mealName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let sugarG: Double
    let fiberG: Double
    let fatG: Double
    let notes: String
}

nonisolated struct FavoriteFoodSnapshot: Codable {
    let createdAt: Date
    let name: String
    let mealName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let sugarG: Double
    let fiberG: Double
    let fatG: Double
}

nonisolated struct SavedNutritionProtocolSnapshot: Codable {
    let createdAt: Date
    let updatedAt: Date
    let programJSON: String
    let followupWeeksJSON: String
    let macroReviewJSON: String?
    let macroReviewUpdatedAt: Date?
    let appliedCalories: Int?
    let appliedProteinG: Double?
    let appliedCarbsG: Double?
    let appliedFatG: Double?
}

nonisolated struct ProgressPhotoSnapshot: Codable {
    let date: Date
    let pose: String
    let imageData: Data
    let aiAnalysis: String?
    let notes: String
}

nonisolated struct AnalysisSnapshot: Codable {
    let date: Date
    let photoData: Data
    let pose: String
    let analysisJSON: String
    let photoCount: Int
    let analysisResult: String
    let priorityMuscles: String
    let dietRecommendation: String
}

nonisolated struct WorkoutProgramSnapshot: Codable {
    let id: UUID
    let createdDate: Date
    let programName: String
    let programSummary: String
    let splitType: String
    let daysPerWeek: Int
    let totalDays: Int
    let focusAreas: String
    let sourceAnalysisDate: Date?
    let programJSON: String
    let currentWeek: Int
    let maxWeeks: Int
    let analysisJSON: String
    let days: [WorkoutDaySnapshot]
    let isArchived: Bool?
}

nonisolated struct WorkoutDaySnapshot: Codable {
    let dayNumber: Int
    let dayName: String
    let muscleGroups: String
    let isRestDay: Bool
    let notes: String
    let isCompleted: Bool
    let feedbackSubmittedAt: Date?
    let sessionEffort: Int?
    let stimulusQuality: Int?
    let jointPain: Int?
    let performanceRatingRaw: String?
    let sessionFeedbackNotes: String?
    let sessionStartedAt: Date?
    let sessionEndedAt: Date?
    let exercises: [WorkoutExerciseSnapshot]
}

nonisolated struct WorkoutExerciseSnapshot: Codable {
    let order: Int
    let exerciseName: String
    let sets: Int
    let reps: String
    let tempo: String?
    let restSeconds: Int
    let notes: String
    let muscleTarget: String
    let isCompleted: Bool
    let completionStatusRaw: String?
}

nonisolated struct ExerciseWeightSnapshot: Codable {
    let loggedAt: Date
    let exerciseName: String
    let weightLbs: Double
    let repsCompleted: Int?
    let notes: String
    let canonicalExerciseKey: String?
    let bestWeightLbs: Double?
    let bestLoggedAt: Date?
    let bestRepsCompleted: Int?
    let bestNotes: String?
}

nonisolated struct ExercisePerformanceLogSnapshot: Codable {
    let loggedAt: Date
    let exerciseName: String
    let weightLbs: Double
    let repsCompleted: Int?
    let notes: String
    let muscleTarget: String
    let canonicalExerciseKey: String?
    let setLogsJSON: String?
    let workoutDayNumber: Int?
}

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
    let appearanceMode: Int?
    let nutritionShiftWorkMode: String?

    static func fromUserDefaults() -> ProfileSettingsSnapshot {
        let d = UserDefaults.standard
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
            sleepHours: d.object(forKey: AppSettingsKeys.analysisSleepHours) as? Double,
            sleepNotes: d.string(forKey: AppSettingsKeys.analysisSleepNotes),
            calorieTarget: d.object(forKey: AppSettingsKeys.calorieTarget) as? Int,
            proteinTarget: d.object(forKey: AppSettingsKeys.proteinTarget) as? Double,
            carbTarget: d.object(forKey: AppSettingsKeys.carbTarget) as? Double,
            fatTarget: d.object(forKey: AppSettingsKeys.fatTarget) as? Double,
            bodyWeightGoal: d.object(forKey: AppSettingsKeys.bodyWeightGoal) as? Double,
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
            appearanceMode: d.object(forKey: AppSettingsKeys.appearanceMode) as? Int,
            nutritionShiftWorkMode: d.string(forKey: AppSettingsKeys.nutritionShiftWorkMode)
        )
    }

    func applyToUserDefaults() {
        let d = UserDefaults.standard
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
        if let v = sleepHours { d.set(v, forKey: AppSettingsKeys.analysisSleepHours) }
        if let v = sleepNotes { d.set(v, forKey: AppSettingsKeys.analysisSleepNotes) }
        if let v = calorieTarget { d.set(v, forKey: AppSettingsKeys.calorieTarget) }
        if let v = proteinTarget { d.set(v, forKey: AppSettingsKeys.proteinTarget) }
        if let v = carbTarget { d.set(v, forKey: AppSettingsKeys.carbTarget) }
        if let v = fatTarget { d.set(v, forKey: AppSettingsKeys.fatTarget) }
        if let v = bodyWeightGoal { d.set(v, forKey: AppSettingsKeys.bodyWeightGoal) }
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
        if let v = appearanceMode { d.set(v, forKey: AppSettingsKeys.appearanceMode) }
        if let v = nutritionShiftWorkMode { d.set(v, forKey: AppSettingsKeys.nutritionShiftWorkMode) }
    }
}

@MainActor private extension WeightSnapshot {
    init(_ entry: WeightEntry) {
        self.init(date: entry.date, weightLbs: entry.weightLbs, notes: entry.notes)
    }

    var dedupeKey: String {
        "\(date.timeIntervalSince1970)-\(weightLbs)-\(notes)"
    }

    func makeModel() -> WeightEntry {
        WeightEntry(date: date, weightLbs: weightLbs, notes: notes)
    }
}

@MainActor private extension SleepSnapshot {
    init(_ entry: SleepEntry) {
        self.init(
            date: entry.date,
            durationHours: entry.durationHours,
            qualityRating: entry.qualityRating,
            shiftTypeRaw: entry.shiftTypeRaw,
            notes: entry.notes,
            startDate: entry.startDate,
            endDate: entry.endDate,
            episodeTypeRaw: entry.episodeTypeRaw
        )
    }

    var dedupeKey: String {
        let resolvedEnd = endDate ?? (
            Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        )
        let resolvedStart = startDate ?? resolvedEnd.addingTimeInterval(-durationHours * 3600)
        return "\(resolvedStart.timeIntervalSince1970)-\(resolvedEnd.timeIntervalSince1970)-\(episodeTypeRaw ?? SleepEpisodeType.mainSleep.rawValue)"
    }

    func makeModel() -> SleepEntry {
        let resolvedEnd = endDate ?? (
            Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        )
        let resolvedStart = startDate ?? resolvedEnd.addingTimeInterval(-durationHours * 3600)
        return SleepEntry(
            startDate: resolvedStart,
            endDate: resolvedEnd,
            qualityRating: qualityRating,
            shiftType: SleepShiftType(rawValue: shiftTypeRaw) ?? .off,
            episodeType: SleepEpisodeType(rawValue: episodeTypeRaw ?? "") ?? .mainSleep,
            notes: notes
        )
    }
}

@MainActor private extension MeasurementSnapshot {
    init(_ entry: MeasurementEntry) {
        self.init(
            date: entry.date,
            chestIn: entry.chestIn,
            waistIn: entry.waistIn,
            hipsIn: entry.hipsIn,
            neckIn: entry.neckIn,
            leftArmIn: entry.leftArmIn,
            rightArmIn: entry.rightArmIn,
            leftThighIn: entry.leftThighIn,
            rightThighIn: entry.rightThighIn,
            leftCalfIn: entry.leftCalfIn,
            rightCalfIn: entry.rightCalfIn,
            bodyFatPct: entry.bodyFatPct,
            notes: entry.notes,
            measurementTiming: entry.measurementTiming,
            isStandardMeasurement: entry.isStandardMeasurement
        )
    }

    var dedupeKey: String {
        "\(date.timeIntervalSince1970)-\(waistIn ?? -1)-\(chestIn ?? -1)-\(notes)"
    }

    func makeModel() -> MeasurementEntry {
        let entry = MeasurementEntry(date: date)
        entry.chestIn = chestIn
        entry.waistIn = waistIn
        entry.hipsIn = hipsIn
        entry.neckIn = neckIn
        entry.leftArmIn = leftArmIn
        entry.rightArmIn = rightArmIn
        entry.leftThighIn = leftThighIn
        entry.rightThighIn = rightThighIn
        entry.leftCalfIn = leftCalfIn
        entry.rightCalfIn = rightCalfIn
        entry.bodyFatPct = bodyFatPct
        entry.notes = notes
        entry.measurementTiming = measurementTiming
        entry.isStandardMeasurement = isStandardMeasurement ?? true
        return entry
    }
}

@MainActor private extension NutritionSnapshot {
    init(_ entry: NutritionEntry) {
        self.init(
            date: entry.date,
            mealName: entry.mealName,
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            sugarG: entry.sugarG,
            fiberG: entry.fiberG,
            fatG: entry.fatG,
            notes: entry.notes
        )
    }

    var dedupeKey: String {
        "\(date.timeIntervalSince1970)-\(mealName)-\(notes)-\(calories)-\(carbsG)-\(proteinG)-\(fatG)"
    }

    func makeModel() -> NutritionEntry {
        NutritionEntry(
            date: date,
            mealName: mealName,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            notes: notes,
            sugarG: sugarG,
            fiberG: fiberG
        )
    }
}

@MainActor private extension FavoriteFoodSnapshot {
    init(_ favorite: FavoriteFood) {
        self.init(
            createdAt: favorite.createdAt,
            name: favorite.name,
            mealName: favorite.mealName,
            calories: favorite.calories,
            proteinG: favorite.proteinG,
            carbsG: favorite.carbsG,
            sugarG: favorite.sugarG,
            fiberG: favorite.fiberG,
            fatG: favorite.fatG
        )
    }

    var dedupeKey: String {
        "\(mealName)-\(name.lowercased())"
    }

    func apply(to favorite: FavoriteFood) {
        favorite.createdAt = createdAt
        favorite.calories = calories
        favorite.proteinG = proteinG
        favorite.carbsG = carbsG
        favorite.sugarG = sugarG
        favorite.fiberG = fiberG
        favorite.fatG = fatG
    }

    func makeModel() -> FavoriteFood {
        FavoriteFood(
            createdAt: createdAt,
            name: name,
            mealName: mealName,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            sugarG: sugarG,
            fiberG: fiberG,
            fatG: fatG
        )
    }
}

@MainActor private extension SavedNutritionProtocolSnapshot {
    init(_ protocolModel: SavedNutritionProtocol) {
        self.init(
            createdAt: protocolModel.createdAt,
            updatedAt: protocolModel.updatedAt,
            programJSON: protocolModel.programJSON,
            followupWeeksJSON: protocolModel.followupWeeksJSON,
            macroReviewJSON: protocolModel.macroReviewJSON,
            macroReviewUpdatedAt: protocolModel.macroReviewUpdatedAt,
            appliedCalories: protocolModel.appliedCalories,
            appliedProteinG: protocolModel.appliedProteinG,
            appliedCarbsG: protocolModel.appliedCarbsG,
            appliedFatG: protocolModel.appliedFatG
        )
    }

    var dedupeKey: String {
        "\(createdAt.timeIntervalSince1970)-\(programJSON)-\(followupWeeksJSON)-\(macroReviewJSON ?? "")"
    }

    func makeModel() -> SavedNutritionProtocol {
        let model = SavedNutritionProtocol(
            createdAt: createdAt,
            updatedAt: updatedAt,
            programJSON: programJSON,
            followupWeeksJSON: followupWeeksJSON
        )
        model.macroReviewJSON = macroReviewJSON ?? ""
        model.macroReviewUpdatedAt = macroReviewUpdatedAt
        model.appliedCalories = appliedCalories
        model.appliedProteinG = appliedProteinG
        model.appliedCarbsG = appliedCarbsG
        model.appliedFatG = appliedFatG
        return model
    }
}

@MainActor private extension ProgressPhotoSnapshot {
    init(_ photo: ProgressPhoto) {
        self.init(
            date: photo.date,
            pose: photo.pose,
            imageData: photo.imageData,
            aiAnalysis: photo.aiAnalysis,
            notes: photo.notes
        )
    }

    var dedupeKey: String {
        "\(date.timeIntervalSince1970)-\(pose)-\(imageData.count)-\(notes)-\(aiAnalysis ?? "")"
    }

    func makeModel() -> ProgressPhoto {
        let photo = ProgressPhoto(
            date: date,
            pose: pose,
            imageData: imageData,
            notes: notes
        )
        photo.aiAnalysis = aiAnalysis
        return photo
    }
}

@MainActor private extension AnalysisSnapshot {
    init(_ session: BodyAnalysisSession) {
        self.init(
            date: session.date,
            photoData: session.photoData,
            pose: session.pose,
            analysisJSON: session.analysisJSON,
            photoCount: session.photoCount,
            analysisResult: session.analysisResult,
            priorityMuscles: session.programmingPrioritySummary,
            dietRecommendation: session.dietRecommendation
        )
    }

    var dedupeKey: String {
        "\(date.timeIntervalSince1970)-\(pose)-\(photoCount)-\(analysisResult)"
    }

    func makeModel() -> BodyAnalysisSession {
        BodyAnalysisSession(
            date: date,
            photoData: photoData,
            pose: pose,
            analysisResult: analysisResult,
            priorityMuscles: priorityMuscles,
            dietRecommendation: dietRecommendation,
            analysisJSON: analysisJSON,
            photoCount: photoCount
        )
    }
}

@MainActor private extension WorkoutExerciseSnapshot {
    init(_ exercise: WorkoutExercise) {
        self.init(
            order: exercise.order,
            exerciseName: exercise.exerciseName,
            sets: exercise.sets,
            reps: exercise.reps,
            tempo: exercise.tempo,
            restSeconds: exercise.restSeconds,
            notes: exercise.notes,
            muscleTarget: exercise.muscleTarget,
            isCompleted: exercise.isCompleted,
            completionStatusRaw: exercise.completionStatusRaw.isEmpty ? nil : exercise.completionStatusRaw
        )
    }

    func makeModel() -> WorkoutExercise {
        let exercise = WorkoutExercise(
            order: order,
            exerciseName: exerciseName,
            sets: sets,
            reps: reps,
            tempo: tempo ?? "",
            restSeconds: restSeconds,
            notes: notes,
            muscleTarget: muscleTarget
        )
        exercise.isCompleted = isCompleted
        exercise.completionStatusRaw = completionStatusRaw ?? ""
        return exercise
    }
}

@MainActor private extension WorkoutDaySnapshot {
    init(_ day: WorkoutDay) {
        self.init(
            dayNumber: day.dayNumber,
            dayName: day.dayName,
            muscleGroups: day.muscleGroups,
            isRestDay: day.isRestDay,
            notes: day.notes,
            isCompleted: day.isCompleted,
            feedbackSubmittedAt: day.feedbackSubmittedAt,
            sessionEffort: day.sessionEffort,
            stimulusQuality: day.stimulusQuality,
            jointPain: day.jointPain,
            performanceRatingRaw: day.performanceRatingRaw,
            sessionFeedbackNotes: day.sessionFeedbackNotes,
            sessionStartedAt: day.sessionStartedAt,
            sessionEndedAt: day.sessionEndedAt,
            exercises: mainActorMap(day.sortedExercises, WorkoutExerciseSnapshot.init)
        )
    }

    func makeModel() -> WorkoutDay {
        let day = WorkoutDay(
            dayNumber: dayNumber,
            dayName: dayName,
            muscleGroups: muscleGroups,
            isRestDay: isRestDay,
            notes: notes
        )
        day.isCompleted = isCompleted
        day.feedbackSubmittedAt = feedbackSubmittedAt
        day.sessionEffort = sessionEffort ?? 0
        day.stimulusQuality = stimulusQuality ?? 0
        day.jointPain = jointPain ?? 0
        day.performanceRatingRaw = performanceRatingRaw ?? ""
        day.sessionFeedbackNotes = sessionFeedbackNotes ?? ""
        day.sessionStartedAt = sessionStartedAt
        day.sessionEndedAt = sessionEndedAt

        for exerciseSnapshot in exercises {
            let exercise = exerciseSnapshot.makeModel()
            exercise.day = day
            day.exercises.append(exercise)
        }

        return day
    }
}

@MainActor private extension WorkoutProgramSnapshot {
    init(_ program: WorkoutProgram) {
        self.init(
            id: program.id,
            createdDate: program.createdDate,
            programName: program.programName,
            programSummary: program.programSummary,
            splitType: program.splitType,
            daysPerWeek: program.daysPerWeek,
            totalDays: program.totalDays,
            focusAreas: program.focusAreas,
            sourceAnalysisDate: program.sourceAnalysisDate,
            programJSON: program.programJSON,
            currentWeek: program.currentWeek,
            maxWeeks: program.maxWeeks,
            analysisJSON: program.analysisJSON,
            days: mainActorMap(program.sortedDays, WorkoutDaySnapshot.init),
            isArchived: program.isArchived
        )
    }

    func makeModel() -> WorkoutProgram {
        let program = WorkoutProgram(
            programName: programName,
            programSummary: programSummary,
            splitType: splitType,
            daysPerWeek: daysPerWeek,
            totalDays: totalDays,
            focusAreas: focusAreas,
            sourceAnalysisDate: sourceAnalysisDate,
            programJSON: programJSON,
            currentWeek: currentWeek,
            maxWeeks: maxWeeks,
            analysisJSON: analysisJSON
        )
        program.id = id
        program.createdDate = createdDate
        program.isArchived = isArchived ?? false

        for daySnapshot in days {
            let day = daySnapshot.makeModel()
            day.program = program
            program.days.append(day)
        }

        return program
    }
}

@MainActor private extension ExerciseWeightSnapshot {
    var resolvedCanonicalKey: String {
        let recomputed = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        if !recomputed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recomputed
        }
        return canonicalExerciseKey ?? recomputed
    }

    init(_ entry: ExerciseWeightEntry) {
        self.init(
            loggedAt: entry.loggedAt,
            exerciseName: entry.exerciseName,
            weightLbs: entry.weightLbs,
            repsCompleted: entry.repsCompleted,
            notes: entry.notes,
            canonicalExerciseKey: entry.canonicalExerciseKey,
            bestWeightLbs: entry.hasBestRecord ? entry.bestWeightLbs : entry.weightLbs,
            bestLoggedAt: entry.bestLoggedAt ?? entry.loggedAt,
            bestRepsCompleted: entry.bestRepsCompleted ?? entry.repsCompleted,
            bestNotes: entry.hasBestRecord ? entry.bestNotes : entry.notes
        )
    }

    var dedupeKey: String {
        resolvedCanonicalKey
    }

    func makeModel() -> ExerciseWeightEntry {
        let entry = ExerciseWeightEntry(
            loggedAt: loggedAt,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            repsCompleted: repsCompleted,
            notes: notes
        )
        entry.canonicalExerciseKey = resolvedCanonicalKey
        entry.bestWeightLbs = bestWeightLbs ?? weightLbs
        entry.bestLoggedAt = bestLoggedAt ?? loggedAt
        entry.bestRepsCompleted = bestRepsCompleted ?? repsCompleted
        entry.bestNotes = bestNotes ?? notes
        return entry
    }

    func merge(into entry: ExerciseWeightEntry) {
        let incomingLast = ExerciseWeightEntry(
            loggedAt: loggedAt,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            repsCompleted: repsCompleted,
            notes: notes
        )

        if entry.loggedAt <= incomingLast.loggedAt {
            entry.loggedAt = incomingLast.loggedAt
            entry.exerciseName = incomingLast.exerciseName
            entry.normalizedExerciseName = incomingLast.normalizedExerciseName
            entry.weightLbs = incomingLast.weightLbs
            entry.repsCompleted = incomingLast.repsCompleted
            entry.notes = incomingLast.notes
        }

        let incomingBestWeight = bestWeightLbs ?? weightLbs
        let incomingBestDate = bestLoggedAt ?? loggedAt
        let incomingBestNotes = bestNotes ?? notes
        let shouldReplaceBest = !entry.hasBestRecord
            || incomingBestWeight > entry.bestWeightLbs + 0.001
            || (abs(incomingBestWeight - entry.bestWeightLbs) <= 0.001
                && (entry.bestLoggedAt ?? .distantPast) < incomingBestDate)

        if shouldReplaceBest {
            entry.bestWeightLbs = incomingBestWeight
            entry.bestLoggedAt = incomingBestDate
            entry.bestRepsCompleted = bestRepsCompleted ?? repsCompleted
            entry.bestNotes = incomingBestNotes
        }

        entry.canonicalExerciseKey = resolvedCanonicalKey
    }
}

@MainActor private extension ExercisePerformanceLogSnapshot {
    var resolvedCanonicalKey: String {
        let recomputed = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        if !recomputed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recomputed
        }
        return canonicalExerciseKey ?? recomputed
    }

    init(_ entry: ExercisePerformanceLog) {
        self.init(
            loggedAt: entry.loggedAt,
            exerciseName: entry.exerciseName,
            weightLbs: entry.weightLbs,
            repsCompleted: entry.repsCompleted,
            notes: entry.notes,
            muscleTarget: entry.muscleTarget,
            canonicalExerciseKey: entry.canonicalExerciseKey,
            setLogsJSON: entry.setLogsJSON.isEmpty ? nil : entry.setLogsJSON,
            workoutDayNumber: entry.workoutDayNumber
        )
    }

    var dedupeKey: String {
        let repText = repsCompleted.map(String.init) ?? "nil"
        return "\(resolvedCanonicalKey)-\(loggedAt.timeIntervalSince1970)-\(weightLbs)-\(repText)-\(notes)"
    }

    func makeModel() -> ExercisePerformanceLog {
        let entry = ExercisePerformanceLog(
            loggedAt: loggedAt,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            repsCompleted: repsCompleted,
            notes: notes,
            muscleTarget: muscleTarget,
            workoutDayNumber: workoutDayNumber ?? 0
        )
        entry.canonicalExerciseKey = resolvedCanonicalKey
        entry.setLogsJSON = setLogsJSON ?? ""
        return entry
    }
}

@MainActor private extension LegacyNutritionSnapshot {
    func makeNutritionSnapshot() -> NutritionSnapshot {
        NutritionSnapshot(
            date: date,
            mealName: mealName,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            sugarG: 0,
            fiberG: 0,
            fatG: fatG,
            notes: notes
        )
    }
}

@MainActor
final class DataBackupManager {
    static let shared = DataBackupManager()
    private init() {}
    let currentBackupVersion = BackupFormat.currentVersion
    private let supportedBackupVersions = BackupFormat.supportedVersions

    /// Set when the app falls back to an ephemeral in-memory store, so an empty
    /// store can't overwrite the last good on-disk backup.
    var suppressAutomaticBackups = false

    func exportDocument(using modelContext: ModelContext) throws -> BackupDocument {
        let payload = try buildPayload(using: modelContext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return BackupDocument(data: data)
    }

    func importBackup(from data: Data, into modelContext: ModelContext) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: TransformBackupPayload
        if let decoded = try? decoder.decode(TransformBackupPayload.self, from: data) {
            payload = decoded
        } else if let legacy = try? decoder.decode(LegacyTransformBackupPayload.self, from: data) {
            payload = migrateLegacyPayload(legacy)
        } else {
            throw BackupError.parseError("Unsupported or corrupt backup format.")
        }

        guard supportedBackupVersions.contains(payload.version) else {
            throw BackupError.unsupportedVersion(payload.version)
        }

        let originalAutosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = originalAutosave }

        do {
            try modelContext.transaction {
                try merge(payload: payload, into: modelContext)
            }
            SleepTrendStore.refresh(using: modelContext)
            writeAutomaticBackup(using: modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Coalesced variant for high-frequency in-workout writes (set logging, completion
    /// toggles). The SwiftData save is already durable; the automatic backup is a full
    /// export (photos + all data) and must not run once per tap. The scene-phase hook in
    /// ContentView still writes a fresh backup whenever the app backgrounds, so the
    /// recovery snapshot never lags a finished session.
    private var lastCoalescedBackupAt: Date?
    private static let coalescedBackupMinInterval: TimeInterval = 45

    func writeAutomaticBackupCoalesced(using modelContext: ModelContext) {
        let now = Date()
        if let last = lastCoalescedBackupAt,
           now.timeIntervalSince(last) < Self.coalescedBackupMinInterval {
            return
        }
        lastCoalescedBackupAt = now
        writeAutomaticBackup(using: modelContext)
    }

    func writeAutomaticBackup(using modelContext: ModelContext) {
        guard !suppressAutomaticBackups else { return }
        do {
            let document = try exportDocument(using: modelContext)
            let counts = try? entryCounts(using: modelContext)
            if let counts, let lastKnown = loadLastKnownCounts() {
                if counts.hasSignificantDrop(comparedTo: lastKnown) {
                    print("[Backup] Skipping auto-backup: significant data drop detected. Previous: \(lastKnown.debugSummary) Current: \(counts.debugSummary) Drop: \(counts.dropSummary(comparedTo: lastKnown)). Preserving existing backups.")
                    return
                }
            }

            rotateBackups()
            let url = automaticBackupURL(slot: 0)
            // The backup contains body photos and health/medical PII. Encrypt it at
            // rest with file protection so it is unreadable while the device is locked.
            try document.data.write(to: url, options: [.atomic, .completeFileProtection])

            if let counts {
                saveLastKnownCounts(counts)
            }
        } catch {
            print("[Backup] Automatic backup failed: \(error.localizedDescription)")
        }
    }

    /// Merges the last automatic backup (if any) into the given context. Used to
    /// recover user data when the persistent store fails to initialize and the app
    /// falls back to an in-memory store, so a storage failure isn't silent total
    /// data loss. The merge is additive and dedupe-guarded, so this is safe even if
    /// the target store already holds data. Returns true if a backup was applied.
    @discardableResult
    func restoreFromAutomaticBackupIfAvailable(into modelContext: ModelContext) -> Bool {
        let url = automaticBackupURL(slot: 0)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return false
        }
        do {
            try importBackup(from: data, into: modelContext)
            return true
        } catch {
            print("[Backup] Automatic backup restore failed: \(error.localizedDescription)")
            return false
        }
    }

    private static let backupSlots = 3

    private func automaticBackupURL(slot: Int) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return slot == 0
            ? dir.appendingPathComponent("Transform_AutoBackup.json")
            : dir.appendingPathComponent("Transform_AutoBackup_\(slot).json")
    }

    private func rotateBackups() {
        let fm = FileManager.default
        for slot in stride(from: Self.backupSlots - 1, through: 1, by: -1) {
            let dest = automaticBackupURL(slot: slot)
            let source = automaticBackupURL(slot: slot - 1)
            try? fm.removeItem(at: dest)
            if fm.fileExists(atPath: source.path) {
                try? fm.copyItem(at: source, to: dest)
            }
        }
    }

    struct EntryCounts: Codable {
        let sleep: Int
        let weight: Int
        let nutrition: Int
        let measurement: Int
        let exerciseWeights: Int
        let exerciseLogs: Int
        let analyses: Int
        let workouts: Int
        let favorites: Int
        let savedNutritionProtocols: Int
        let progressPhotos: Int

        private enum CodingKeys: String, CodingKey {
            case sleep
            case weight
            case nutrition
            case measurement
            case exerciseWeights
            case exerciseLogs
            case analyses
            case workouts
            case favorites
            case savedNutritionProtocols
            case progressPhotos
            case total
        }

        init(
            sleep: Int,
            weight: Int,
            nutrition: Int,
            measurement: Int = 0,
            exerciseWeights: Int = 0,
            exerciseLogs: Int = 0,
            analyses: Int = 0,
            workouts: Int = 0,
            favorites: Int = 0,
            savedNutritionProtocols: Int = 0,
            progressPhotos: Int = 0
        ) {
            self.sleep = sleep
            self.weight = weight
            self.nutrition = nutrition
            self.measurement = measurement
            self.exerciseWeights = exerciseWeights
            self.exerciseLogs = exerciseLogs
            self.analyses = analyses
            self.workouts = workouts
            self.favorites = favorites
            self.savedNutritionProtocols = savedNutritionProtocols
            self.progressPhotos = progressPhotos
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sleep = try container.decodeIfPresent(Int.self, forKey: .sleep) ?? 0
            weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 0
            nutrition = try container.decodeIfPresent(Int.self, forKey: .nutrition) ?? 0
            measurement = try container.decodeIfPresent(Int.self, forKey: .measurement) ?? 0
            exerciseWeights = try container.decodeIfPresent(Int.self, forKey: .exerciseWeights) ?? 0
            exerciseLogs = try container.decodeIfPresent(Int.self, forKey: .exerciseLogs) ?? 0
            analyses = try container.decodeIfPresent(Int.self, forKey: .analyses) ?? 0
            workouts = try container.decodeIfPresent(Int.self, forKey: .workouts) ?? 0
            favorites = try container.decodeIfPresent(Int.self, forKey: .favorites) ?? 0
            savedNutritionProtocols = try container.decodeIfPresent(Int.self, forKey: .savedNutritionProtocols) ?? 0
            progressPhotos = try container.decodeIfPresent(Int.self, forKey: .progressPhotos) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sleep, forKey: .sleep)
            try container.encode(weight, forKey: .weight)
            try container.encode(nutrition, forKey: .nutrition)
            try container.encode(measurement, forKey: .measurement)
            try container.encode(exerciseWeights, forKey: .exerciseWeights)
            try container.encode(exerciseLogs, forKey: .exerciseLogs)
            try container.encode(analyses, forKey: .analyses)
            try container.encode(workouts, forKey: .workouts)
            try container.encode(favorites, forKey: .favorites)
            try container.encode(savedNutritionProtocols, forKey: .savedNutritionProtocols)
            try container.encode(progressPhotos, forKey: .progressPhotos)
            try container.encode(total, forKey: .total)
        }

        var total: Int {
            sleep
                + weight
                + nutrition
                + measurement
                + exerciseWeights
                + exerciseLogs
                + analyses
                + workouts
                + favorites
                + savedNutritionProtocols
                + progressPhotos
        }

        var debugSummary: String {
            "sleep=\(sleep) weight=\(weight) nutrition=\(nutrition) measurement=\(measurement) exerciseWeights=\(exerciseWeights) exerciseLogs=\(exerciseLogs) analyses=\(analyses) workouts=\(workouts) favorites=\(favorites) savedProtocols=\(savedNutritionProtocols) progressPhotos=\(progressPhotos)"
        }

        func dropSummary(comparedTo previous: EntryCounts) -> String {
            "sleep=\(previous.sleep - sleep) weight=\(previous.weight - weight) nutrition=\(previous.nutrition - nutrition) measurement=\(previous.measurement - measurement) exerciseWeights=\(previous.exerciseWeights - exerciseWeights) exerciseLogs=\(previous.exerciseLogs - exerciseLogs) analyses=\(previous.analyses - analyses) workouts=\(previous.workouts - workouts) favorites=\(previous.favorites - favorites) savedProtocols=\(previous.savedNutritionProtocols - savedNutritionProtocols) progressPhotos=\(previous.progressPhotos - progressPhotos) total=\(previous.total - total)"
        }

        func hasSignificantDrop(comparedTo previous: EntryCounts) -> Bool {
            let measurementDrop = previous.measurement - measurement
            let exerciseWeightDrop = previous.exerciseWeights - exerciseWeights
            let exerciseLogDrop = previous.exerciseLogs - exerciseLogs
            let analysesDrop = previous.analyses - analyses
            let workoutsDrop = previous.workouts - workouts
            let favoritesDrop = previous.favorites - favorites
            let savedProtocolDrop = previous.savedNutritionProtocols - savedNutritionProtocols
            let progressPhotoDrop = previous.progressPhotos - progressPhotos
            let totalDrop = previous.total - total

            return (previous.sleep - sleep) > 2
                || (previous.weight - weight) > 2
                || (previous.nutrition - nutrition) > 5
                || measurementDrop > 2
                || exerciseWeightDrop > 2
                || exerciseLogDrop > 2
                || analysesDrop > 1
                || workoutsDrop > 1
                || favoritesDrop > 10
                || savedProtocolDrop > 1
                || progressPhotoDrop > 1
                || totalDrop > 10
        }

        func shouldAttemptAutomaticRecovery(comparedTo previous: EntryCounts) -> Bool {
            let totalDrop = previous.total - total
            let zeroedHighValueCategories = [
                previous.exerciseLogs > 0 && exerciseLogs == 0,
                previous.exerciseWeights > 0 && exerciseWeights == 0,
                previous.analyses > 0 && analyses == 0,
                previous.workouts > 0 && workouts == 0,
                previous.savedNutritionProtocols > 0 && savedNutritionProtocols == 0
            ].filter { $0 }.count

            return totalDrop > 10
                || (previous.exerciseLogs > 2 && exerciseLogs == 0)
                || (previous.exerciseWeights > 2 && exerciseWeights == 0)
                || zeroedHighValueCategories >= 2
        }
    }

    func entryCounts(using modelContext: ModelContext) throws -> EntryCounts {
        let sleep = try modelContext.fetchCount(FetchDescriptor<SleepEntry>())
        let weight = try modelContext.fetchCount(FetchDescriptor<WeightEntry>())
        let nutrition = try modelContext.fetchCount(FetchDescriptor<NutritionEntry>())
        let measurement = try modelContext.fetchCount(FetchDescriptor<MeasurementEntry>())
        let exerciseWeights = try modelContext.fetchCount(FetchDescriptor<ExerciseWeightEntry>())
        let exerciseLogs = try modelContext.fetchCount(FetchDescriptor<ExercisePerformanceLog>())
        let analyses = try modelContext.fetchCount(FetchDescriptor<BodyAnalysisSession>())
        let workouts = try modelContext.fetchCount(FetchDescriptor<WorkoutProgram>())
        let favorites = try modelContext.fetchCount(FetchDescriptor<FavoriteFood>())
        let savedNutritionProtocols = try modelContext.fetchCount(FetchDescriptor<SavedNutritionProtocol>())
        let progressPhotos = try modelContext.fetchCount(FetchDescriptor<ProgressPhoto>())

        return EntryCounts(
            sleep: sleep,
            weight: weight,
            nutrition: nutrition,
            measurement: measurement,
            exerciseWeights: exerciseWeights,
            exerciseLogs: exerciseLogs,
            analyses: analyses,
            workouts: workouts,
            favorites: favorites,
            savedNutritionProtocols: savedNutritionProtocols,
            progressPhotos: progressPhotos
        )
    }

    private static let countsKey = "transform.lastKnownEntryCounts"

    private func saveLastKnownCounts(_ counts: EntryCounts) {
        if let data = try? JSONEncoder().encode(counts) {
            UserDefaults.standard.set(data, forKey: Self.countsKey)
        }
    }

    private func loadLastKnownCounts() -> EntryCounts? {
        guard let data = UserDefaults.standard.data(forKey: Self.countsKey) else { return nil }
        return try? JSONDecoder().decode(EntryCounts.self, from: data)
    }

    @MainActor
    func scheduleAutomaticBackup(using modelContext: ModelContext) {
        guard !suppressAutomaticBackups else { return }
        Task { @MainActor in
            await Task.yield()
            writeAutomaticBackup(using: modelContext)
        }
    }

    @MainActor
    func attemptAutomaticRecoveryIfNeeded(using modelContext: ModelContext) -> String? {
        guard
            let previous = loadLastKnownCounts(),
            let current = try? entryCounts(using: modelContext),
            current.shouldAttemptAutomaticRecovery(comparedTo: previous)
        else {
            return nil
        }

        guard restoreFromAutomaticBackupIfAvailable(into: modelContext) else {
            return nil
        }

        guard let recovered = try? entryCounts(using: modelContext) else {
            return "Stored data looked incomplete at startup, so Transform restored the most recent automatic backup."
        }

        guard recovered.total > current.total else { return nil }

        return "Stored data looked incomplete at startup, so Transform restored the most recent automatic backup and recovered \(recovered.total - current.total) records."
    }

    private func buildPayload(using modelContext: ModelContext) throws -> TransformBackupPayload {
        let weights = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        let sleep = try modelContext.fetch(FetchDescriptor<SleepEntry>())
        let measurements = try modelContext.fetch(FetchDescriptor<MeasurementEntry>())
        let nutrition = try modelContext.fetch(FetchDescriptor<NutritionEntry>())
        let favorites = try modelContext.fetch(FetchDescriptor<FavoriteFood>())
        let savedNutritionProtocols = try modelContext.fetch(FetchDescriptor<SavedNutritionProtocol>())
        let progressPhotos = try modelContext.fetch(FetchDescriptor<ProgressPhoto>())
        let analyses = try modelContext.fetch(FetchDescriptor<BodyAnalysisSession>())
        let workouts = try modelContext.fetch(FetchDescriptor<WorkoutProgram>())
        let exerciseWeights = try modelContext.fetch(FetchDescriptor<ExerciseWeightEntry>())
        let exercisePerformanceLogs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())

        return TransformBackupPayload(
            version: currentBackupVersion,
            exportedAt: .now,
            weights: mainActorMap(weights, WeightSnapshot.init),
            sleep: mainActorMap(sleep, SleepSnapshot.init),
            measurements: mainActorMap(measurements, MeasurementSnapshot.init),
            nutrition: mainActorMap(nutrition, NutritionSnapshot.init),
            favorites: mainActorMap(favorites, FavoriteFoodSnapshot.init),
            savedNutritionProtocols: mainActorMap(savedNutritionProtocols, SavedNutritionProtocolSnapshot.init),
            progressPhotos: mainActorMap(progressPhotos, ProgressPhotoSnapshot.init),
            analyses: mainActorMap(analyses, AnalysisSnapshot.init),
            workouts: mainActorMap(workouts, WorkoutProgramSnapshot.init),
            exerciseWeights: mainActorMap(exerciseWeights, ExerciseWeightSnapshot.init),
            exercisePerformanceLogs: mainActorMap(exercisePerformanceLogs, ExercisePerformanceLogSnapshot.init),
            profileSettings: ProfileSettingsSnapshot.fromUserDefaults()
        )
    }

    private func merge(payload: TransformBackupPayload, into modelContext: ModelContext) throws {
        let existingWeights = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        let existingSleep = try modelContext.fetch(FetchDescriptor<SleepEntry>())
        let existingMeasurements = try modelContext.fetch(FetchDescriptor<MeasurementEntry>())
        let existingNutrition = try modelContext.fetch(FetchDescriptor<NutritionEntry>())
        let existingFavorites = try modelContext.fetch(FetchDescriptor<FavoriteFood>())
        let existingSavedNutritionProtocols = try modelContext.fetch(FetchDescriptor<SavedNutritionProtocol>())
        let existingProgressPhotos = try modelContext.fetch(FetchDescriptor<ProgressPhoto>())
        let existingAnalyses = try modelContext.fetch(FetchDescriptor<BodyAnalysisSession>())
        let existingWorkouts = try modelContext.fetch(FetchDescriptor<WorkoutProgram>())
        var existingExerciseWeights = try modelContext.fetch(FetchDescriptor<ExerciseWeightEntry>())
        let existingExercisePerformanceLogs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())

        var weightKeys = Set(mainActorMap(existingWeights) { WeightSnapshot($0).dedupeKey })
        var sleepKeys = Set(mainActorMap(existingSleep) { SleepSnapshot($0).dedupeKey })
        var measurementKeys = Set(mainActorMap(existingMeasurements) { MeasurementSnapshot($0).dedupeKey })
        var nutritionKeys = Set(mainActorMap(existingNutrition) { NutritionSnapshot($0).dedupeKey })
        var favoriteKeys = Set(mainActorMap(existingFavorites) { FavoriteFoodSnapshot($0).dedupeKey })
        var savedNutritionProtocolKeys = Set(mainActorMap(existingSavedNutritionProtocols) {
            SavedNutritionProtocolSnapshot($0).dedupeKey
        })
        var progressPhotoKeys = Set(mainActorMap(existingProgressPhotos) { ProgressPhotoSnapshot($0).dedupeKey })
        var analysisKeys = Set(mainActorMap(existingAnalyses) { AnalysisSnapshot($0).dedupeKey })
        var workoutKeys = Set(mainActorMap(existingWorkouts) { $0.id.uuidString })
        var exerciseWeightKeys = Set(mainActorMap(existingExerciseWeights) { ExerciseWeightSnapshot($0).dedupeKey })
        var exercisePerformanceLogKeys = Set(mainActorMap(existingExercisePerformanceLogs) {
            ExercisePerformanceLogSnapshot($0).dedupeKey
        })

        for item in payload.weights {
            let key = item.dedupeKey
            guard !weightKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            weightKeys.insert(key)
        }

        for item in payload.sleep ?? [] {
            let key = item.dedupeKey
            guard !sleepKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            sleepKeys.insert(key)
        }

        for item in payload.measurements {
            let key = item.dedupeKey
            guard !measurementKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            measurementKeys.insert(key)
        }

        for item in payload.nutrition {
            let key = item.dedupeKey
            guard !nutritionKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            nutritionKeys.insert(key)
        }

        for item in payload.favorites {
            let key = item.dedupeKey
            if let existing = mainActorFirst(
                in: existingFavorites,
                where: { FavoriteFoodSnapshot($0).dedupeKey == key }
            ) {
                item.apply(to: existing)
            } else if !favoriteKeys.contains(key) {
                modelContext.insert(item.makeModel())
                favoriteKeys.insert(key)
            }
        }

        for item in payload.savedNutritionProtocols ?? [] {
            let key = item.dedupeKey
            guard !savedNutritionProtocolKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            savedNutritionProtocolKeys.insert(key)
        }

        for item in payload.progressPhotos ?? [] {
            let key = item.dedupeKey
            guard !progressPhotoKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            progressPhotoKeys.insert(key)
        }

        for item in payload.analyses {
            let key = item.dedupeKey
            guard !analysisKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            analysisKeys.insert(key)
        }

        for item in payload.workouts {
            guard !workoutKeys.contains(item.id.uuidString) else { continue }
            let program = item.makeModel()
            modelContext.insert(program)
            workoutKeys.insert(item.id.uuidString)
        }

        for item in payload.exerciseWeights ?? [] {
            let key = item.dedupeKey
            if let existing = mainActorFirst(
                in: existingExerciseWeights,
                where: { ExerciseWeightSnapshot($0).dedupeKey == key }
            ) {
                item.merge(into: existing)
                exerciseWeightKeys.insert(key)
                continue
            }

            let created = item.makeModel()
            modelContext.insert(created)
            existingExerciseWeights.append(created)
            exerciseWeightKeys.insert(key)
        }

        for item in payload.exercisePerformanceLogs ?? [] {
            let key = item.dedupeKey
            guard !exercisePerformanceLogKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            exercisePerformanceLogKeys.insert(key)
        }

        _ = try ExerciseWeightStore.normalizeAndConsolidate(in: modelContext)

        payload.profileSettings?.applyToUserDefaults()
    }

    private func migrateLegacyPayload(_ legacy: LegacyTransformBackupPayload) -> TransformBackupPayload {
        TransformBackupPayload(
            version: 1,
            exportedAt: .now,
            weights: legacy.weights,
            sleep: nil,
            measurements: legacy.measurements,
            nutrition: mainActorMap(legacy.nutrition) { $0.makeNutritionSnapshot() },
            favorites: [],
            savedNutritionProtocols: nil,
            progressPhotos: nil,
            analyses: legacy.analyses,
            workouts: legacy.workouts,
            exerciseWeights: [],
            exercisePerformanceLogs: []
        )
    }
}

nonisolated enum BackupError: LocalizedError {
    case parseError(String)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .parseError(let message):
            return message
        case .unsupportedVersion(let version):
            if version > BackupFormat.currentVersion {
                return "This backup was created by a newer app version (backup format \(version)). Update Transform before importing to avoid data loss."
            }
            return "Unsupported backup version \(version)."
        }
    }
}
