import Foundation

enum WorkoutReadinessMode: String, CaseIterable, Identifiable {
    case normal = "normal"
    case sleepRestricted = "sleep_restricted"
    case postNightShift = "post_night_shift"
    case postCall = "post_call"
    case highStressClinicalBlock = "high_stress_clinical"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .sleepRestricted: return "Sleep Restricted"
        case .postNightShift: return "Post-Night Shift"
        case .postCall: return "Post-Call"
        case .highStressClinicalBlock: return "High-Stress Block"
        }
    }

    var volumeScale: Double {
        switch self {
        case .normal: return 1.0
        case .sleepRestricted: return 0.90
        case .postNightShift: return 0.85
        case .postCall: return 0.80
        case .highStressClinicalBlock: return 0.90
        }
    }

    var sessionTimeCap: Int {
        switch self {
        case .normal: return 75
        case .sleepRestricted: return 65
        case .postNightShift: return 60
        case .postCall: return 55
        case .highStressClinicalBlock: return 65
        }
    }

    var programmingGuidance: String {
        switch self {
        case .normal:
            return ""
        case .sleepRestricted:
            return "Sleep is restricted — reduce grinder sets, favor moderate RPE (7-8), keep compound movement patterns stable but cut accessory volume."
        case .postNightShift:
            return "Post-night shift — avoid heavy axial loading (heavy squats, deadlifts). Favor machine-based and cable work. Cap RPE at 7-8. Prioritize pump and technique over intensity."
        case .postCall:
            return "Post-call recovery session — use pump and technique bias. Cap RPE at 6-7. Favor familiar exercises with low novelty. Session should feel restorative, not depleting."
        case .highStressClinicalBlock:
            return "High-stress clinical block — keep exercise selection stable and familiar. Lower novelty and failure exposure. Maintain training frequency but reduce volume per session."
        }
    }
}

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
        let readinessMode: WorkoutReadinessMode
        let weeklyVolumeScale: Double
        let reduceExerciseSlotComplexity: Bool
        let defaultSessionTimeCapMinutes: Int
        let sessionTimeCapsByStyle: [String: Int]
        let programmingNotes: [String]
    }

    struct ExerciseSelectionContext {
        let calibration: ProgramCalibrationProfile
        let injuryRiskFocus: String
        let targetSessionMinutes: Int
        let style: String
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
        let equipment: String
        let exerciseClass: String
        let systemicFatigue: Int
        let stabilityDemand: Int
        let shoulderRisk: Int
        let preferredContexts: [String]
        let avoidContexts: [String]

        init(
            canonicalName: String,
            primaryAreas: [String],
            secondaryAreas: [String],
            movementPattern: String,
            fatigueCost: Int,
            equipment: String = "Unknown",
            exerciseClass: String = "Accessory",
            systemicFatigue: Int? = nil,
            stabilityDemand: Int = 2,
            shoulderRisk: Int = 1,
            preferredContexts: [String] = [],
            avoidContexts: [String] = []
        ) {
            self.canonicalName = canonicalName
            self.primaryAreas = primaryAreas
            self.secondaryAreas = secondaryAreas
            self.movementPattern = movementPattern
            self.fatigueCost = fatigueCost
            self.equipment = equipment
            self.exerciseClass = exerciseClass
            self.systemicFatigue = systemicFatigue ?? fatigueCost
            self.stabilityDemand = stabilityDemand
            self.shoulderRisk = shoulderRisk
            self.preferredContexts = preferredContexts
            self.avoidContexts = avoidContexts
        }
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
        let calibration: ProgramCalibrationProfile
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

    struct WeekDiffEntry: Identifiable {
        let id = UUID()
        let dayNumber: Int
        let dayName: String
        let kind: WeekDiffKind
        let exerciseName: String
        let detail: String
    }

    enum WeekDiffKind: String {
        case added = "Added"
        case removed = "Removed"
        case setsChanged = "Sets Changed"
        case repsChanged = "Reps Changed"
    }

}
