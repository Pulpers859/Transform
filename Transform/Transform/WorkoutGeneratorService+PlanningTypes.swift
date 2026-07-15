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

    struct WeeklyVariationBucket {
        let label: String
        let primaryAreas: Set<String>
    }

    struct WeeklyVariationViolation {
        let area: String
        let bucket: String
        let count: Int
        let cap: Int
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
        var directExerciseNames: [String: Set<String>] = [:]
        var peakSessionFatigue: [String: Int] = [:]
        var dailyFatigue: [Int: Int] = [:]
    }

    struct StimulusCredit {
        let directSets: Double
        let weightedStimulus: Double

        static let none = StimulusCredit(directSets: 0, weightedStimulus: 0)
    }

    enum ProceduralExerciseRole: String {
        case anchor
        case secondary
        case accessory
        case core
    }

    struct PreSelectedExercise {
        let exerciseName: String
        let muscleTarget: String
        let movementPattern: String
        let role: ProceduralExerciseRole
        var prescribedSets: Int
    }

    /// Deterministic double-progression verdict for one logged exercise, mirroring the
    /// ProgressionSuggestion banner. Built in WorkoutView from the same entries that feed
    /// the prompt's "app verdict" lines (98349db), and passed into validation so the
    /// validator can reject AI coaching cues that contradict the logged history.
    enum ProgressionVerdictKind: String {
        case addLoad
        case addRepsInRange
        case holdBelowRange
    }

    struct ExerciseProgressionVerdict {
        let canonicalKey: String
        let exerciseName: String
        let kind: ProgressionVerdictKind
        let weightLbs: Double
    }

    struct ExerciseHistoryContext {
        let painExercises: Set<String>
        let equipmentSkipExercises: Set<String>
        let priorMesocycleExercises: Set<String>
        let mesocycleIndex: Int
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
