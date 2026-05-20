import Foundation

// MARK: - Body Analysis Result Models

struct BodyAnalysisResult: Codable {
    let overallAssessment: String
    let trainingAssessment: String
    let nutritionAssessment: String
    let recoveryRiskAssessment: String
    let adherenceAssessment: String
    let analysisLimitations: String
    let inputContext: AnalysisInputContext?
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
        case trainingAssessment
        case nutritionAssessment
        case recoveryRiskAssessment
        case adherenceAssessment
        case analysisLimitations
        case inputContext
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
        trainingAssessment: String,
        nutritionAssessment: String,
        recoveryRiskAssessment: String,
        adherenceAssessment: String,
        analysisLimitations: String,
        inputContext: AnalysisInputContext?,
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
        self.trainingAssessment = trainingAssessment
        self.nutritionAssessment = nutritionAssessment
        self.recoveryRiskAssessment = recoveryRiskAssessment
        self.adherenceAssessment = adherenceAssessment
        self.analysisLimitations = analysisLimitations
        self.inputContext = inputContext
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
        trainingAssessment = try container.decodeIfPresent(String.self, forKey: .trainingAssessment) ?? ""
        nutritionAssessment = try container.decodeIfPresent(String.self, forKey: .nutritionAssessment) ?? ""
        recoveryRiskAssessment = try container.decodeIfPresent(String.self, forKey: .recoveryRiskAssessment) ?? ""
        adherenceAssessment = try container.decodeIfPresent(String.self, forKey: .adherenceAssessment) ?? ""
        analysisLimitations = try container.decodeIfPresent(String.self, forKey: .analysisLimitations) ?? ""
        inputContext = try? container.decodeIfPresent(AnalysisInputContext.self, forKey: .inputContext)
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
        macroTargets = try? container.decode(AnalysisMacroTargets.self, forKey: .macroTargets)
        structuredTrainingIntent = try? container.decode(StructuredTrainingIntent.self, forKey: .structuredTrainingIntent)
    }
}

extension BodyAnalysisResult {
    func withInputContext(_ inputContext: AnalysisInputContext) -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: overallAssessment,
            trainingAssessment: trainingAssessment,
            nutritionAssessment: nutritionAssessment,
            recoveryRiskAssessment: recoveryRiskAssessment,
            adherenceAssessment: adherenceAssessment,
            analysisLimitations: analysisLimitations,
            inputContext: inputContext,
            regionBreakdown: regionBreakdown,
            topLeverageChange: topLeverageChange,
            priorityMuscles: priorityMuscles,
            workoutRecommendations: workoutRecommendations,
            dietRecommendations: dietRecommendations,
            posturalNotes: posturalNotes,
            estimatedBodyFat: estimatedBodyFat,
            metabolicHealthNotes: metabolicHealthNotes,
            psychologicalInsights: psychologicalInsights,
            injuryRiskNotes: injuryRiskNotes,
            macroTargets: macroTargets,
            structuredTrainingIntent: structuredTrainingIntent
        )
    }

    var resolvedTrainingAssessment: String {
        let trimmed = trainingAssessment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return overallAssessment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedNutritionAssessment: String {
        let trimmed = nutritionAssessment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let firstRecommendation = dietRecommendations.first {
            return firstRecommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    var resolvedRecoveryRiskAssessment: String {
        let trimmed = recoveryRiskAssessment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return [posturalNotes, injuryRiskNotes, metabolicHealthNotes]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var resolvedAdherenceAssessment: String {
        let trimmed = adherenceAssessment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return psychologicalInsights.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedAnalysisLimitations: String {
        let trimmed = analysisLimitations.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "Photo-based analysis is strongest for visible physique patterns, rough body-composition bands, and broad hypertrophy priorities. It is weaker for injury, metabolic, posture, and adherence inference without training history, recovery data, and user-reported context."
    }

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

struct AnalysisInputContext: Codable {
    let profile: AnalysisProfileSnapshot
    let checkIn: AnalysisCheckInSnapshot?
    let progress: AnalysisProgressSnapshot?

    var promptDescription: String {
        var sections: [String] = [profile.promptDescription]
        if let checkIn {
            sections.append(checkIn.promptDescription)
        }
        if let progress {
            sections.append(progress.promptDescription)
        }
        return sections.joined(separator: "\n\n")
    }

    var coachingContextSummary: String {
        var parts: [String] = [profile.summaryDescription]
        if let checkIn {
            parts.append(checkIn.summaryDescription)
        }
        if let progress {
            parts.append(progress.summaryDescription)
        }
        return parts.joined(separator: "\n")
    }

    var compactSummaryItems: [String] {
        var items = profile.compactSummaryItems
        if let checkIn {
            items.append(contentsOf: checkIn.compactSummaryItems)
        }
        if let progress {
            items.append(contentsOf: progress.compactSummaryItems)
        }
        return Array(items.prefix(4))
    }

    var detailSections: [AnalysisContextSection] {
        var sections = [AnalysisContextSection(title: "Profile", items: profile.detailSummaryItems)]
        if let checkIn, !checkIn.detailSummaryItems.isEmpty {
            sections.append(AnalysisContextSection(title: "Current Check-In", items: checkIn.detailSummaryItems))
        }
        if let progress, !progress.detailSummaryItems.isEmpty {
            sections.append(AnalysisContextSection(title: "Progress Since Prior Analysis", items: progress.detailSummaryItems))
        }
        return sections
    }
}

extension AnalysisInputContext {
    func withProgress(_ progress: AnalysisProgressSnapshot?) -> AnalysisInputContext {
        AnalysisInputContext(
            profile: profile,
            checkIn: checkIn,
            progress: progress
        )
    }
}

struct AnalysisProfileSnapshot: Codable {
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

    private var lines: [(String, String)] {
        [
            ("Age", age),
            ("Sex/Gender", sex),
            ("Build", build),
            ("Height", height),
            ("Current Body Weight", currentWeight),
            ("Occupation", occupation),
            ("Training Frequency", trainingFrequency),
            ("Training Age / Experience", trainingAge),
            ("Equipment Access", equipmentAccess),
            ("Average Sleep / Recovery", averageSleep),
            ("Pain / Injury Context", painHistory),
            ("Activity Level", activityLevel),
            ("Primary Goal", primaryGoal),
            ("Lifestyle Constraints", lifestyleConstraints)
        ]
    }

    var promptDescription: String {
        let rendered = lines
            .map { label, value in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return "- \(label): \(cleaned.isEmpty ? "(unspecified)" : cleaned)"
            }
            .joined(separator: "\n")

        return """
        Use the following user-editable profile context when personalizing the assessment.
        Treat blank or unspecified fields as unknown rather than inventing them.
        \(rendered)
        """
    }

    var summaryDescription: String {
        let rendered = lines
            .compactMap { label, value -> String? in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return nil }
                return "- \(label): \(cleaned)"
            }
            .joined(separator: "\n")
        return rendered.isEmpty ? "Profile context: (none provided)" : "Profile context:\n\(rendered)"
    }

    var compactSummaryItems: [String] {
        [
            compactLine(label: "Goal", value: primaryGoal),
            compactLine(label: "Training", value: trainingFrequency),
            compactLine(label: "Recovery", value: averageSleep),
            compactLine(label: "Equipment", value: equipmentAccess)
        ].compactMap { $0 }
    }

    var detailSummaryItems: [String] {
        lines.compactMap { label, value in
            compactLine(label: label, value: value)
        }
    }
}

struct AnalysisCheckInSnapshot: Codable {
    let trainingContext: String
    let bodyweightTrend: String
    let recoverySleep: String
    let stressSchedule: String
    let sorenessPain: String
    let nutritionAdherence: String

    private var lines: [(String, String)] {
        [
            ("Current Training Context", trainingContext),
            ("Bodyweight / Visual Trend", bodyweightTrend),
            ("Recovery / Sleep Last 7 Days", recoverySleep),
            ("Stress / Schedule Pressure", stressSchedule),
            ("Soreness / Pain Flags", sorenessPain),
            ("Nutrition Adherence / Appetite", nutritionAdherence)
        ]
    }

    var hasMeaningfulContent: Bool {
        lines.contains { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var promptDescription: String {
        let rendered = lines
            .map { label, value in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return "- \(label): \(cleaned.isEmpty ? "(unspecified)" : cleaned)"
            }
            .joined(separator: "\n")

        return """
        Current check-in context for this analysis.
        Use it to sharpen recovery, nutrition, and programming interpretation instead of over-reading the photos.
        \(rendered)
        """
    }

    var summaryDescription: String {
        let rendered = lines
            .compactMap { label, value -> String? in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return nil }
                return "- \(label): \(cleaned)"
            }
            .joined(separator: "\n")
        return rendered.isEmpty ? "Current check-in: (none provided)" : "Current check-in:\n\(rendered)"
    }

    var compactSummaryItems: [String] {
        [
            compactLine(label: "Training", value: trainingContext),
            compactLine(label: "Bodyweight", value: bodyweightTrend),
            compactLine(label: "Recovery", value: recoverySleep),
            compactLine(label: "Pain", value: sorenessPain)
        ].compactMap { $0 }
    }

    var detailSummaryItems: [String] {
        lines.compactMap { label, value in
            compactLine(label: label, value: value)
        }
    }
}

struct AnalysisProgressSnapshot: Codable {
    let previousAnalysisAgeDays: Int
    let previousPriorityAreas: [String]
    let previousTopLeverageChange: String
    let bodyweightTrend: String
    let nutritionAdherence: String
    let performanceSignals: String
    let dataQualityNotes: String

    var promptDescription: String {
        let prioritySummary = previousPriorityAreas.isEmpty
            ? "(none recorded)"
            : previousPriorityAreas.joined(separator: ", ")
        let leverage = previousTopLeverageChange.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        Progress context from app data since the prior saved analysis (\(previousAnalysisAgeDays) day(s) ago).
        Use this to evaluate whether the previous direction appears to be working instead of treating the new photos like an isolated snapshot.
        - Previous priority areas: \(prioritySummary)
        - Previous highest-leverage recommendation: \(leverage.isEmpty ? "(none recorded)" : leverage)
        - Bodyweight trend: \(bodyweightTrend)
        - Nutrition adherence from logs: \(nutritionAdherence)
        - Workout/performance signal from logs: \(performanceSignals)
        - Data quality notes: \(dataQualityNotes)
        """
    }

    var summaryDescription: String {
        let prioritySummary = previousPriorityAreas.isEmpty
            ? "(none recorded)"
            : previousPriorityAreas.joined(separator: ", ")
        let leverage = previousTopLeverageChange.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        Progress since prior analysis (\(previousAnalysisAgeDays) day(s)):
        - Previous priority areas: \(prioritySummary)
        - Previous highest-leverage change: \(leverage.isEmpty ? "(none recorded)" : leverage)
        - Bodyweight trend: \(bodyweightTrend)
        - Nutrition adherence: \(nutritionAdherence)
        - Workout/performance signal: \(performanceSignals)
        - Data quality notes: \(dataQualityNotes)
        """
    }

    var compactSummaryItems: [String] {
        var items: [String] = []
        if !previousPriorityAreas.isEmpty {
            items.append("Previous priorities: \(previousPriorityAreas.joined(separator: ", ").truncatedForAnalysisUI(70))")
        }
        items.append("Bodyweight trend: \(bodyweightTrend.truncatedForAnalysisUI(95))")
        items.append("Nutrition adherence: \(nutritionAdherence.truncatedForAnalysisUI(95))")
        return items
    }

    var detailSummaryItems: [String] {
        let prioritySummary = previousPriorityAreas.isEmpty
            ? "(none recorded)"
            : previousPriorityAreas.joined(separator: ", ")
        let leverage = previousTopLeverageChange.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            "Previous priority areas: \(prioritySummary)",
            "Previous highest-leverage change: \(leverage.isEmpty ? "(none recorded)" : leverage)",
            "Bodyweight trend: \(bodyweightTrend)",
            "Nutrition adherence: \(nutritionAdherence)",
            "Workout/performance signal: \(performanceSignals)",
            "Data quality notes: \(dataQualityNotes)"
        ]
    }
}

struct AnalysisContextSection {
    let title: String
    let items: [String]
}

struct AnalysisLoggedWeightPoint {
    let date: Date
    let weightLbs: Double
}

struct AnalysisLoggedNutritionDay {
    let date: Date
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct AnalysisExerciseProgressSnapshot {
    let exerciseName: String
    let canonicalExerciseKey: String
    let latestWeightLbs: Double
    let latestDate: Date
    let bestWeightLbs: Double
    let bestLoggedAt: Date?
    let bestRepsCompleted: Int?
}

struct AnalysisExercisePerformanceEvent {
    let exerciseName: String
    let canonicalExerciseKey: String
    let loggedAt: Date
    let weightLbs: Double
    let repsCompleted: Int?
}

struct AnalysisMacroTargetSnapshot {
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

enum AnalysisProgressSnapshotBuilder {
    static func build(
        previousAnalysisDate: Date,
        previousPriorityAreas: [String],
        previousTopLeverageChange: String,
        currentDate: Date = .now,
        weightPoints: [AnalysisLoggedWeightPoint],
        nutritionDays: [AnalysisLoggedNutritionDay],
        macroTargets: AnalysisMacroTargetSnapshot,
        exerciseEvents: [AnalysisExercisePerformanceEvent],
        exerciseSnapshots: [AnalysisExerciseProgressSnapshot]
    ) -> AnalysisProgressSnapshot {
        let ageDays = max(Calendar.current.dateComponents([.day], from: previousAnalysisDate, to: currentDate).day ?? 0, 0)

        return AnalysisProgressSnapshot(
            previousAnalysisAgeDays: ageDays,
            previousPriorityAreas: previousPriorityAreas,
            previousTopLeverageChange: previousTopLeverageChange,
            bodyweightTrend: bodyweightTrendSummary(from: weightPoints),
            nutritionAdherence: nutritionSummary(from: nutritionDays, macroTargets: macroTargets, ageDays: ageDays),
            performanceSignals: performanceSummary(
                from: exerciseEvents,
                exerciseSnapshots: exerciseSnapshots,
                since: previousAnalysisDate
            ),
            dataQualityNotes: dataQualityNotes(
                ageDays: ageDays,
                weightLogCount: weightPoints.count,
                nutritionDayCount: nutritionDays.count,
                exerciseEventCount: exerciseEvents.filter { $0.loggedAt >= previousAnalysisDate }.count,
                exerciseSnapshotCount: exerciseSnapshots.count,
                since: previousAnalysisDate
            )
        )
    }

    private static func bodyweightTrendSummary(from points: [AnalysisLoggedWeightPoint]) -> String {
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first else {
            return "No bodyweight logs were recorded since the last analysis."
        }
        guard let last = sorted.last, sorted.count > 1 else {
            return "One bodyweight log was recorded since the last analysis: \(formatWeight(first.weightLbs)) lb."
        }

        let elapsedDays = max(Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 0, 1)
        let delta = last.weightLbs - first.weightLbs
        let weeklyRate = delta / Double(elapsedDays) * 7.0
        let direction = directionPhrase(for: delta)
        return "Weight \(direction) from \(formatWeight(first.weightLbs)) to \(formatWeight(last.weightLbs)) lb (\(signedWeight(delta)) lb over \(elapsedDays) day(s), about \(signedWeight(weeklyRate)) lb/week) across \(sorted.count) log(s)."
    }

    private static func nutritionSummary(
        from days: [AnalysisLoggedNutritionDay],
        macroTargets: AnalysisMacroTargetSnapshot,
        ageDays: Int
    ) -> String {
        guard !days.isEmpty else {
            return "No nutrition logs were recorded since the last analysis."
        }

        let loggedDays = Double(days.count)
        let averageCalories = Double(days.reduce(0) { $0 + $1.calories }) / loggedDays
        let averageProtein = days.reduce(0.0) { $0 + $1.proteinG } / loggedDays
        let averageCarbs = days.reduce(0.0) { $0 + $1.carbsG } / loggedDays
        let averageFat = days.reduce(0.0) { $0 + $1.fatG } / loggedDays

        let calorieHitDays = days.filter { day in
            let lowerBound = Double(macroTargets.calories) * 0.90
            let upperBound = Double(macroTargets.calories) * 1.10
            return Double(day.calories) >= lowerBound && Double(day.calories) <= upperBound
        }.count

        let proteinHitDays = days.filter { $0.proteinG >= macroTargets.proteinG * 0.90 }.count
        let coverage = ageDays > 0 ? "\(days.count) of \(ageDays) day(s)" : "\(days.count) day(s)"

        return "Nutrition was logged on \(coverage). Average intake was \(Int(averageCalories.rounded())) kcal, \(Int(averageProtein.rounded())) g protein, \(Int(averageCarbs.rounded())) g carbs, and \(Int(averageFat.rounded())) g fat versus targets of \(macroTargets.calories) kcal, \(Int(macroTargets.proteinG.rounded())) g protein, \(Int(macroTargets.carbsG.rounded())) g carbs, and \(Int(macroTargets.fatG.rounded())) g fat. Calories landed within about 10% of target on \(calorieHitDays)/\(days.count) logged day(s), and protein hit at least 90% of target on \(proteinHitDays)/\(days.count) logged day(s)."
    }

    private static func performanceSummary(
        from events: [AnalysisExercisePerformanceEvent],
        exerciseSnapshots snapshots: [AnalysisExerciseProgressSnapshot],
        since previousAnalysisDate: Date
    ) -> String {
        let recentEvents = events
            .filter { $0.loggedAt >= previousAnalysisDate }
            .sorted { $0.loggedAt > $1.loggedAt }

        if !recentEvents.isEmpty {
            let distinctMovements = Set(recentEvents.map(\.canonicalExerciseKey)).count
            let groupedByMovement = Dictionary(grouping: events) { $0.canonicalExerciseKey }
            let movementSummaries = recentEvents.reduce(into: [String: String]()) { partialResult, event in
                guard partialResult[event.canonicalExerciseKey] == nil else { return }
                let movementEvents = groupedByMovement[event.canonicalExerciseKey] ?? []
                let baselineBest = movementEvents
                    .filter { $0.loggedAt < previousAnalysisDate }
                    .max {
                        if abs($0.weightLbs - $1.weightLbs) > 0.001 {
                            return $0.weightLbs < $1.weightLbs
                        }
                        return $0.loggedAt < $1.loggedAt
                    }
                let postAnalysisBest = movementEvents
                    .filter { $0.loggedAt >= previousAnalysisDate }
                    .max {
                        if abs($0.weightLbs - $1.weightLbs) > 0.001 {
                            return $0.weightLbs < $1.weightLbs
                        }
                        return $0.loggedAt < $1.loggedAt
                    }

                guard let postAnalysisBest else { return }

                if let baselineBest, postAnalysisBest.weightLbs > baselineBest.weightLbs + 0.001 {
                    partialResult[event.canonicalExerciseKey] = "\(postAnalysisBest.exerciseName) improved from \(formatWeight(baselineBest.weightLbs)) to \(formatWeight(postAnalysisBest.weightLbs)) lb"
                } else {
                    var benchmark = "\(postAnalysisBest.exerciseName) logged at \(formatWeight(postAnalysisBest.weightLbs)) lb"
                    if let reps = postAnalysisBest.repsCompleted {
                        benchmark += " x \(reps)"
                    }
                    partialResult[event.canonicalExerciseKey] = benchmark
                }
            }

            let highlighted = recentEvents
                .compactMap { movementSummaries[$0.canonicalExerciseKey] }
                .uniquePreservingOrder()
                .prefix(3)
                .joined(separator: "; ")

            return "\(recentEvents.count) logged exercise performance event(s) were recorded since the last analysis across \(distinctMovements) movement(s). \(highlighted.isEmpty ? "Recent performance data exists but no standout benchmark could be summarized cleanly." : highlighted + ".")"
        }

        let updated = snapshots
            .filter { snapshot in
                snapshot.latestDate >= previousAnalysisDate
                    || (snapshot.bestLoggedAt ?? .distantPast) >= previousAnalysisDate
            }
            .sorted { $0.latestDate > $1.latestDate }

        guard !updated.isEmpty else {
            return "No exercise strength summaries were updated since the last analysis."
        }

        let refreshedBests = updated
            .filter { ($0.bestLoggedAt ?? .distantPast) >= previousAnalysisDate && $0.bestWeightLbs > 0 }
            .prefix(3)
            .map { snapshot in
                var entry = "\(snapshot.exerciseName) \(formatWeight(snapshot.bestWeightLbs)) lb"
                if let reps = snapshot.bestRepsCompleted {
                    entry += " x \(reps)"
                }
                return entry
            }

        let bestText = refreshedBests.isEmpty
            ? "No clearly newer best loads were captured in the summary data."
            : "Recent bests logged since the last analysis: \(refreshedBests.joined(separator: "; "))."

        return "\(updated.count) exercise summary record(s) were updated since the last analysis across \(Set(updated.map(\.canonicalExerciseKey)).count) movement(s). \(bestText)"
    }

    private static func dataQualityNotes(
        ageDays: Int,
        weightLogCount: Int,
        nutritionDayCount: Int,
        exerciseEventCount: Int,
        exerciseSnapshotCount: Int,
        since previousAnalysisDate: Date
    ) -> String {
        var notes: [String] = []
        if weightLogCount < 2 {
            notes.append("Bodyweight trend confidence is limited because fewer than two weight logs were recorded in this window.")
        }
        if nutritionDayCount == 0 {
            notes.append("Nutrition adherence could not be evaluated because no intake was logged in this window.")
        }
        if exerciseEventCount == 0 && exerciseSnapshotCount == 0 {
            notes.append("Workout performance context is limited because no exercise strength summaries are stored.")
        } else if exerciseEventCount == 0 {
            notes.append("No append-only performance events were logged in this window, so workout feedback falls back to latest/best movement summaries.")
        } else {
            notes.append("Performance history now preserves logged exercise events over time, but it still reflects only what was actually logged, not guaranteed full set-by-set completion unless you record each working effort.")
        }
        if ageDays <= 7 {
            notes.append("The lookback window is short, so apparent changes may be mostly noise.")
        }
        return notes.joined(separator: " ")
    }

    private static func formatWeight(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }

    private static func signedWeight(_ value: Double) -> String {
        let formatted = formatWeight(abs(value))
        if value > 0.05 {
            return "+\(formatted)"
        }
        if value < -0.05 {
            return "-\(formatted)"
        }
        return "0"
    }

    private static func directionPhrase(for delta: Double) -> String {
        if delta > 0.05 {
            return "increased"
        }
        if delta < -0.05 {
            return "decreased"
        }
        return "held roughly steady"
    }
}

private extension Sequence where Element == String {
    func uniquePreservingOrder() -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in self {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }
}

private func compactLine(label: String, value: String, limit: Int = 80) -> String? {
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }
    return "\(label): \(cleaned.truncatedForAnalysisUI(limit))"
}

private extension String {
    func truncatedForAnalysisUI(_ limit: Int) -> String {
        guard count > limit else { return self }
        let truncated = prefix(max(0, limit - 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(truncated)…"
    }
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
