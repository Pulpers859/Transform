import SwiftUI
import SwiftData
import Foundation

// MARK: - Body Weight Entry
@Model
class WeightEntry {
    var date: Date
    var weightLbs: Double = 0
    var notes: String = ""

    init(date: Date = .now, weightLbs: Double, notes: String = "") {
        self.date = date
        self.weightLbs = weightLbs
        self.notes = notes
    }
}

// MARK: - Sleep Episode
@Model
class SleepEntry {
    // `date` and `durationHours` are retained for lightweight migration from
    // the original daily-summary model. New code keeps them synchronized.
    var date: Date
    var durationHours: Double = 0
    var qualityRating: Int = 0
    var shiftTypeRaw: String = SleepShiftType.off.rawValue
    var notes: String = ""
    var startDate: Date?
    var endDate: Date?
    var episodeTypeRaw: String = SleepEpisodeType.mainSleep.rawValue
    // Where this record's timing came from. Defaults to `.manual` so every existing
    // record (pre-migration) and every hand-entered log is treated as manual and is
    // never overwritten by the HealthKit importer — see SleepHealthImportCore.
    var sourceRaw: String = SleepEntrySource.manual.rawValue

    init(
        startDate: Date,
        endDate: Date,
        qualityRating: Int,
        shiftType: SleepShiftType,
        episodeType: SleepEpisodeType,
        notes: String = "",
        source: SleepEntrySource = .manual
    ) {
        self.date = endDate
        self.durationHours = max(0, endDate.timeIntervalSince(startDate) / 3600)
        self.qualityRating = qualityRating
        self.shiftTypeRaw = shiftType.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.episodeTypeRaw = episodeType.rawValue
        self.notes = notes
        self.sourceRaw = source.rawValue
    }

    var shiftType: SleepShiftType {
        get { SleepShiftType(rawValue: shiftTypeRaw) ?? .off }
        set { shiftTypeRaw = newValue.rawValue }
    }

    var episodeType: SleepEpisodeType {
        get { SleepEpisodeType(rawValue: episodeTypeRaw) ?? .mainSleep }
        set { episodeTypeRaw = newValue.rawValue }
    }

    var source: SleepEntrySource {
        get { SleepEntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var resolvedEndDate: Date { endDate ?? date }

    var resolvedStartDate: Date {
        startDate ?? resolvedEndDate.addingTimeInterval(-durationHours * 3600)
    }

    var resolvedDurationHours: Double {
        max(0, resolvedEndDate.timeIntervalSince(resolvedStartDate) / 3600)
    }

    func updateTiming(start: Date, end: Date) {
        startDate = start
        endDate = end
        date = end
        durationHours = max(0, end.timeIntervalSince(start) / 3600)
    }
}

// MARK: - Body Measurements
@Model
class MeasurementEntry {
    var date: Date
    var chestIn: Double?
    var waistIn: Double?
    var hipsIn: Double?
    var neckIn: Double?
    var leftArmIn: Double?
    var rightArmIn: Double?
    var leftThighIn: Double?
    var rightThighIn: Double?
    var leftCalfIn: Double?
    var rightCalfIn: Double?
    var bodyFatPct: Double?
    var notes: String = ""
    var measurementTiming: String?
    var isStandardMeasurement: Bool = true

    init(date: Date = .now) {
        self.date = date
        self.notes = ""
    }

    var hasCoreMeasurements: Bool {
        waistIn != nil || neckIn != nil || hipsIn != nil
    }

    var hasAdvancedMeasurements: Bool {
        chestIn != nil || leftArmIn != nil || rightArmIn != nil
            || leftThighIn != nil || rightThighIn != nil
            || leftCalfIn != nil || rightCalfIn != nil
    }

    var filledFieldCount: Int {
        let fields: [Double?] = [
            chestIn, waistIn, hipsIn, neckIn,
            leftArmIn, rightArmIn, leftThighIn, rightThighIn,
            leftCalfIn, rightCalfIn, bodyFatPct
        ]
        return fields.compactMap({ $0 }).count
    }
}

// MARK: - Nutrition Log
@Model
class NutritionEntry {
    var date: Date
    var mealName: String = ""
    var calories: Int = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var sugarG: Double = 0
    var fiberG: Double = 0
    var fatG: Double = 0
    var notes: String = ""

    init(date: Date = .now, mealName: String, calories: Int,
         proteinG: Double, carbsG: Double, fatG: Double, notes: String = "",
         sugarG: Double = 0, fiberG: Double = 0) {
        self.date = date
        self.mealName = mealName
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.sugarG = sugarG
        self.fiberG = fiberG
        self.fatG = fatG
        self.notes = notes
    }
}

// MARK: - Saved Nutrition Protocol
@Model
class SavedNutritionProtocol {
    var createdAt: Date
    var updatedAt: Date
    var programJSON: String = ""
    var followupWeeksJSON: String = ""
    var macroReviewJSON: String = ""
    var macroReviewUpdatedAt: Date?
    var appliedCalories: Int?
    var appliedProteinG: Double?
    var appliedCarbsG: Double?
    var appliedFatG: Double?

    init(
        createdAt: Date = .now,
        updatedAt: Date = .now,
        programJSON: String,
        followupWeeksJSON: String
    ) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.programJSON = programJSON
        self.followupWeeksJSON = followupWeeksJSON
    }

    var appliedMacroOverride: AdaptiveMacroOverride? {
        guard let calories = appliedCalories,
              let proteinG = appliedProteinG,
              let carbsG = appliedCarbsG,
              let fatG = appliedFatG else {
            return nil
        }
        return AdaptiveMacroOverride(
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG
        )
    }
}

// MARK: - Saved Favorite Food
@Model
class FavoriteFood {
    var createdAt: Date
    var name: String = ""
    var mealName: String = ""
    var calories: Int = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var sugarG: Double = 0
    var fiberG: Double = 0
    var fatG: Double = 0

    init(
        createdAt: Date = .now,
        name: String,
        mealName: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        sugarG: Double = 0,
        fiberG: Double = 0,
        fatG: Double
    ) {
        self.createdAt = createdAt
        self.name = name
        self.mealName = mealName
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.sugarG = sugarG
        self.fiberG = fiberG
        self.fatG = fatG
    }
}

// MARK: - Progress Photo
@Model
class ProgressPhoto {
    var date: Date
    var pose: String = ""
    var imageData: Data
    var aiAnalysis: String?
    var notes: String = ""

    init(date: Date = .now, pose: String, imageData: Data, notes: String = "") {
        self.date = date
        self.pose = pose
        self.imageData = imageData
        self.notes = notes
    }
}

// MARK: - Body Analysis Session
@Model
class BodyAnalysisSession {
    var date: Date
    var photoData: Data
    var pose: String = ""
    var analysisJSON: String = ""     // Full JSON — decode to BodyAnalysisResult
    var photoCount: Int = 1            // Number of photos used

    // Legacy fields for backward compat with existing saved data
    var analysisResult: String = ""
    var priorityMuscles: String = ""
    var dietRecommendation: String = ""
    @Transient var cachedDecodedAnalysisJSON: String = ""
    @Transient var cachedDecodedResultValue: BodyAnalysisResult?
    @Transient var cachedLegacyAnalysisResult: String = ""
    @Transient var cachedLegacyDecodedResultValue: BodyAnalysisResult?

    init(date: Date = .now, photoData: Data, pose: String,
         analysisResult: String, priorityMuscles: String, dietRecommendation: String,
         analysisJSON: String = "", photoCount: Int = 1) {
        self.date = date
        self.photoData = photoData
        self.pose = pose
        self.analysisResult = analysisResult
        self.priorityMuscles = priorityMuscles
        self.dietRecommendation = dietRecommendation
        self.analysisJSON = analysisJSON
        self.photoCount = photoCount
    }

    /// Decode the full result from stored JSON, with legacy fallback
    var decodedResult: BodyAnalysisResult? {
        if !analysisJSON.isEmpty {
            if cachedDecodedAnalysisJSON == analysisJSON {
                return cachedDecodedResultValue
            }

            let decoded = storedAnalysisData.flatMap { data in
                try? JSONDecoder().decode(BodyAnalysisResult.self, from: data)
            }
            cachedDecodedAnalysisJSON = analysisJSON
            cachedDecodedResultValue = decoded
            return decoded
        }

        if cachedLegacyAnalysisResult == analysisResult {
            return cachedLegacyDecodedResultValue
        }

        let decoded = legacyDecodedResult
        cachedLegacyAnalysisResult = analysisResult
        cachedLegacyDecodedResultValue = decoded
        return decoded
    }

    var programmingPriorityAreas: [String] {
        decodedResult?.programmingPriorityAreas ?? legacyPriorityMuscles
    }

    var programmingPrioritySummary: String {
        let summary = programmingPriorityAreas.joined(separator: ", ")
        return summary.isEmpty ? priorityMuscles : summary
    }

    var highPriorityRegionsToAddress: [String] {
        decodedResult?.highPriorityRegionsToAddress ?? []
    }
}

private extension BodyAnalysisSession {
    var storedAnalysisData: Data? {
        guard !analysisJSON.isEmpty else { return nil }
        return analysisJSON.data(using: .utf8)
    }

    var legacyDecodedResult: BodyAnalysisResult? {
        guard !analysisResult.isEmpty else { return nil }

        return BodyAnalysisResult(
            overallAssessment: analysisResult,
            trainingAssessment: "",
            nutritionAssessment: "",
            recoveryRiskAssessment: "",
            adherenceAssessment: "",
            analysisLimitations: "",
            inputContext: nil,
            regionBreakdown: [],
            topLeverageChange: "",
            priorityMuscles: legacyPriorityMuscles,
            workoutRecommendations: [],
            dietRecommendations: legacyDietRecommendations,
            posturalNotes: "",
            estimatedBodyFat: "",
            metabolicHealthNotes: "",
            psychologicalInsights: "",
            injuryRiskNotes: "",
            macroTargets: nil,
            structuredTrainingIntent: nil
        )
    }

    var legacyPriorityMuscles: [String] {
        priorityMuscles
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var legacyDietRecommendations: [String] {
        dietRecommendation.isEmpty ? [] : [dietRecommendation]
    }
}
