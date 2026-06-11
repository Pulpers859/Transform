import Foundation

// MARK: - Body Analysis Result Models

struct BodyAnalysisResult: Codable {
    let overallAssessment: String
    let regionBreakdown: [RegionAssessment]
    let topLeverageChange: String
    let priorityMuscles: [String]
    let workoutRecommendations: [String]
    let dietRecommendations: [String]
    let posturalNotes: String
    let estimatedBodyFat: String
    let metabolicHealthNotes: String
    let psychologicalInsights: String
    let injuryRiskNotes: String
    let macroTargets: AnalysisMacroTargets?
    let structuredTrainingIntent: StructuredTrainingIntent?

    enum CodingKeys: String, CodingKey {
        case overallAssessment
        case regionBreakdown
        case topLeverageChange
        case priorityMuscles
        case workoutRecommendations
        case dietRecommendations
        case posturalNotes
        case estimatedBodyFat
        case metabolicHealthNotes
        case psychologicalInsights
        case injuryRiskNotes
        case macroTargets
        case structuredTrainingIntent
    }

    init(
        overallAssessment: String,
        regionBreakdown: [RegionAssessment],
        topLeverageChange: String,
        priorityMuscles: [String],
        workoutRecommendations: [String],
        dietRecommendations: [String],
        posturalNotes: String,
        estimatedBodyFat: String,
        metabolicHealthNotes: String,
        psychologicalInsights: String,
        injuryRiskNotes: String,
        macroTargets: AnalysisMacroTargets?,
        structuredTrainingIntent: StructuredTrainingIntent?
    ) {
        self.overallAssessment = overallAssessment
        self.regionBreakdown = regionBreakdown
        self.topLeverageChange = topLeverageChange
        self.priorityMuscles = priorityMuscles
        self.workoutRecommendations = workoutRecommendations
        self.dietRecommendations = dietRecommendations
        self.posturalNotes = posturalNotes
        self.estimatedBodyFat = estimatedBodyFat
        self.metabolicHealthNotes = metabolicHealthNotes
        self.psychologicalInsights = psychologicalInsights
        self.injuryRiskNotes = injuryRiskNotes
        self.macroTargets = macroTargets
        self.structuredTrainingIntent = structuredTrainingIntent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overallAssessment = try container.decode(String.self, forKey: .overallAssessment)
        regionBreakdown = try container.decode([RegionAssessment].self, forKey: .regionBreakdown)
        topLeverageChange = try container.decode(String.self, forKey: .topLeverageChange)
        priorityMuscles = try container.decode([String].self, forKey: .priorityMuscles)
        workoutRecommendations = try container.decode([String].self, forKey: .workoutRecommendations)
        dietRecommendations = try container.decode([String].self, forKey: .dietRecommendations)
        posturalNotes = try container.decode(String.self, forKey: .posturalNotes)
        estimatedBodyFat = try container.decode(String.self, forKey: .estimatedBodyFat)
        metabolicHealthNotes = try container.decode(String.self, forKey: .metabolicHealthNotes)
        psychologicalInsights = try container.decode(String.self, forKey: .psychologicalInsights)
        injuryRiskNotes = try container.decode(String.self, forKey: .injuryRiskNotes)
        // These fields are optional in the schema, but present-but-malformed payloads
        // must not silently demote the analysis to the degraded path — log the decode
        // error so quality regressions are visible instead of vanishing as nil.
        do {
            macroTargets = try container.decodeIfPresent(AnalysisMacroTargets.self, forKey: .macroTargets)
        } catch {
            print("[BodyAnalysisResult] macroTargets present but malformed, dropping: \(error)")
            macroTargets = nil
        }
        do {
            structuredTrainingIntent = try container.decodeIfPresent(StructuredTrainingIntent.self, forKey: .structuredTrainingIntent)
        } catch {
            print("[BodyAnalysisResult] structuredTrainingIntent present but malformed, dropping: \(error)")
            structuredTrainingIntent = nil
        }
    }
}

extension BodyAnalysisResult {
    var programmingPriorityAreas: [String] {
        if let structuredPriorities = structuredTrainingIntent?.priorities,
           !structuredPriorities.isEmpty {
            return uniqueOrderedAnalysisValues(structuredPriorities.map(\.area))
        }
        return uniqueOrderedAnalysisValues(priorityMuscles)
    }

    var highPriorityRegionsToAddress: [String] {
        uniqueOrderedAnalysisValues(
            regionBreakdown
                .filter { $0.priority.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("High") == .orderedSame }
                .map(\.region)
        )
    }

    var programmingPrioritySummary: String {
        programmingPriorityAreas.joined(separator: ", ")
    }
}

struct StructuredTrainingIntent: Codable {
    let splitRecommendation: String
    let weeklyTrainingDays: Int
    let priorities: [StructuredTrainingPriority]
    let programmingNotes: [String]
}

struct StructuredTrainingPriority: Codable {
    let area: String
    let priorityLevel: String
    let rationale: String
    let weeklyDayTarget: Int
    let weeklyExerciseTarget: Int
    let preferredStyles: [String]
    let preferredMovementPatterns: [String]
    let volumeBias: String
    let directWorkBias: String
}

struct AnalysisMacroTargets: Codable {
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG
        case carbsG
        case fatG
    }

    init(calories: Int, proteinG: Double, carbsG: Double, fatG: Double) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let caloriesValue = try AnalysisMacroTargets.decodeNumericValue(container, key: .calories)
        let proteinValue = try AnalysisMacroTargets.decodeNumericValue(container, key: .proteinG)
        let carbsValue = try AnalysisMacroTargets.decodeNumericValue(container, key: .carbsG)
        let fatValue = try AnalysisMacroTargets.decodeNumericValue(container, key: .fatG)

        calories = Int(caloriesValue.rounded())
        proteinG = proteinValue
        carbsG = carbsValue
        fatG = fatValue
    }

    private static func decodeNumericValue(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) throws -> Double {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let intValue = try? container.decode(Int.self, forKey: key) {
            return Double(intValue)
        }
        if let stringValue = try? container.decode(String.self, forKey: key),
           let parsed = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected numeric value")
    }
}

struct RegionAssessment: Codable, Identifiable {
    let id = UUID()
    let region: String
    let assessment: String
    let priority: String

    enum CodingKeys: String, CodingKey {
        case region, assessment, priority
    }
}

private func uniqueOrderedAnalysisValues(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed.lowercased()
        guard !seen.contains(key) else { return nil }
        seen.insert(key)
        return trimmed
    }
}
