import Foundation

extension ClaudeService {
    struct TrainingIntentPlan {
        let splitRecommendation: String
        let weeklyTrainingDays: Int?
        let programmingNotes: [String]
        let priorities: [MusclePriorityIntent]
        let topLeverageChange: String
        let posturalFocus: String
        let injuryRiskFocus: String
        let calibration: ProgramCalibrationProfile
    }

    struct MusclePriorityIntent {
        let area: String
        let priorityLevel: String
        let rank: Int
        let rationale: String
        let weeklyDayTarget: Int
        let weeklyExerciseTarget: Int
        let weeklyDirectSetTarget: Double
        let weeklyStimulusTarget: Double
        let preferredStyles: [String]
        let preferredMovementPatterns: [String]
        let coverageKeywords: [String]
        let accessoryCatalog: [(name: String, target: String)]
        let volumeBias: String
        let directWorkBias: String
    }

    struct PriorityCoverage {
        let label: String
        let dayMatches: Int
        let meaningfulDayMatches: Int
        let exerciseMatches: Int
        let variationCount: Int
        let directSets: Double
        let weightedStimulus: Double
        let peakSessionFatigue: Int
    }

    struct ProgramCalibrationProfile {
        let lowPerformanceDataQuality: Bool
        let poorNutritionAdherence: Bool
        let recoveryConstrained: Bool
        let recompositionGoal: Bool
        let weeklyVolumeScale: Double
        let reduceExerciseSlotComplexity: Bool
        let defaultSessionTimeCapMinutes: Int
        let sessionTimeCapsByStyle: [String: Int]
        let programmingNotes: [String]
    }

    struct PriorityFocusProfile {
        let label: String
        let triggerKeywords: [String]
        let coverageKeywords: [String]
        let preferredStyles: [String]
        let accessoryCatalog: [(name: String, target: String)]
    }

    struct ExerciseMetadata {
        let canonicalName: String
        let primaryAreas: [String]
        let secondaryAreas: [String]
        let movementPattern: String
        let fatigueCost: Int
    }

    enum FocusStimulusKind {
        case prime
        case secondary
        case support
        case none
    }

    struct FocusStimulusSummary {
        let matchedExercises: Int
        let primeExercises: Int
        let supportExercises: Int
        let qualityDirectSets: Double
        let firstMatchedKind: FocusStimulusKind
        let firstPrimeIndex: Int?
    }

    struct PreviousWeekDecodeResult {
        let days: [WorkoutDayResponse]
        let weekSummary: String?
        let warning: String?
    }

    struct AnalysisDecodeResult {
        let analysis: BodyAnalysisResult?
        let warning: String?
    }

    struct HypertrophyEvidenceProfile {
        let version: String
        let defaultTrainingDays: Int
        let allowedStyles: [String]
        let frequencyTargetsByPriority: [String: Int]
        let exerciseSlotTargetsByPriority: [String: Int]
        let directSetTargetsByPriority: [String: ClosedRange<Double>]
        let directSetTargetsByVolumeBias: [String: Double]
        let directWorkBiasAdjustments: [String: Double]
        let phasePrescriptionsByWeek: [Int: EvidencePhasePrescription]
        let restSecondsByRole: [String: Int]
        let sessionFatigueCapsByStyle: [String: Int]
        let maxSessionPriorityFatigue: Int
        let focusSessionDirectSetShareByPriority: [String: Double]
        let weightedStimulusBonusDirect: Double
        let weightedStimulusBonusIndirect: Double
    }

    struct EvidencePhasePrescription {
        let anchorSets: Int
        let secondarySets: Int
        let accessorySets: Int
        let coreSets: Int
        let anchorRepRange: String
        let secondaryRepRange: String
        let accessoryRepRange: String
        let coreRepRange: String
    }

    struct BlueprintPriorityAllocation {
        let area: String
        let priorityLevel: String
        let rationale: String
        let targetFrequency: Int
        let targetExerciseSlots: Int
        let directSetTarget: Double
        let weightedStimulusTarget: Double
        let maxPerSessionDirectSets: Double
        let maxFocusSessionDirectSets: Double
        let preferredStyles: [String]
        let preferredMovementPatterns: [String]
        let volumeBias: String
        let directWorkBias: String
    }

    struct BlueprintDayPlan {
        let dayIndex: Int
        let style: String
        let focusArea: String?
        let supportAreas: [String]
        let targetFatigueCap: Int
        let targetSessionMinutes: Int
        let targetPrioritySlots: Int
        let emphasisPatterns: [String]
        let isRestDay: Bool
    }

    struct ProgramBlueprint {
        let evidenceVersion: String
        let splitRecommendation: String
        let weeklyTrainingDays: Int
        let priorityAllocations: [BlueprintPriorityAllocation]
        let dayPlans: [BlueprintDayPlan]
        let topLeverageChange: String
        let posturalFocus: String
        let injuryRiskFocus: String
        let programmingNotes: [String]
    }

    struct WeekStimulusReport {
        var directSets: [String: Double] = [:]
        var directSetsByDay: [String: [Int: Double]] = [:]
        var weightedStimulus: [String: Double] = [:]
        var exposureDays: [String: Set<Int>] = [:]
        var exerciseMatches: [String: Int] = [:]
        var exerciseKeys: [String: Set<String>] = [:]
        var exerciseNames: [String: Set<String>] = [:]
        var peakSessionFatigue: [String: Int] = [:]
        var dailyFatigue: [Int: Int] = [:]
    }

    enum ProceduralExerciseRole: String {
        case anchor
        case secondary
        case accessory
        case core
    }

}
