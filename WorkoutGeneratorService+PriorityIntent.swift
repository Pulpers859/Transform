import Foundation

extension ClaudeService {
    func derivedPriorityAreas(from analysis: BodyAnalysisResult) -> [String] {
        let explicit = prioritizedFocusAreas(from: analysis.programmingPriorityAreas)
        if !explicit.isEmpty {
            return explicit
        }

        let derived = analysis.regionBreakdown
            .filter { normalizedPriorityLevel($0.priority, rank: 0) != "Low" }
            .sorted { lhs, rhs in
                priorityScore(for: lhs.priority) > priorityScore(for: rhs.priority)
            }
            .map(\.region)

        return prioritizedFocusAreas(from: derived)
    }

    func musclePriorityIntent(
        area: String,
        rank: Int,
        regionBreakdown: [RegionAssessment],
        workoutRecommendations: [String],
        leverageChange: String
    ) -> MusclePriorityIntent {
        let canonicalArea = canonicalPriorityAreaName(area)
        let profile = priorityProfile(for: canonicalArea)
        let matchedRegion = bestMatchingRegionAssessment(for: canonicalArea, within: regionBreakdown)
        let priorityLevel = normalizedPriorityLevel(matchedRegion?.priority, rank: rank)
        let rationale = priorityRationale(
            area: canonicalArea,
            profile: profile,
            matchedRegion: matchedRegion,
            workoutRecommendations: workoutRecommendations,
            leverageChange: leverageChange
        )
        let preferredPatterns = inferredMovementPatterns(for: canonicalArea, profile: profile, workoutRecommendations: workoutRecommendations)
        let defaultVolumeBias = priorityLevel == "High" ? "High" : "Moderate"
        let defaultDirectWorkBias = profile.label == "Core/Abs" ? "Direct emphasis" : "Primary hypertrophy emphasis"

        return MusclePriorityIntent(
            area: canonicalArea,
            priorityLevel: priorityLevel,
            rank: rank,
            rationale: rationale,
            weeklyDayTarget: weeklyDayTarget(for: priorityLevel, rank: rank),
            weeklyExerciseTarget: weeklyExerciseTarget(for: priorityLevel, rank: rank),
            weeklyDirectSetTarget: weeklyDirectSetTarget(for: priorityLevel, volumeBias: defaultVolumeBias, directWorkBias: defaultDirectWorkBias),
            weeklyStimulusTarget: weeklyStimulusTarget(for: priorityLevel, volumeBias: defaultVolumeBias, directWorkBias: defaultDirectWorkBias),
            preferredStyles: profile.preferredStyles,
            preferredMovementPatterns: preferredPatterns,
            coverageKeywords: priorityCoverageKeywords(for: canonicalArea) + preferredPatterns,
            accessoryCatalog: profile.accessoryCatalog,
            volumeBias: defaultVolumeBias,
            directWorkBias: defaultDirectWorkBias
        )
    }

    func musclePriorityIntent(
        from priority: StructuredTrainingPriority,
        rank: Int,
        analysis: BodyAnalysisResult
    ) -> MusclePriorityIntent {
        let rawArea = priority.area.trimmedOr(default: "Priority Area")
        let canonicalArea = canonicalPriorityAreaName(rawArea)
        let profile = priorityProfile(for: canonicalArea)
        let fallbackIntent = musclePriorityIntent(
            area: canonicalArea,
            rank: rank,
            regionBreakdown: analysis.regionBreakdown,
            workoutRecommendations: analysis.workoutRecommendations,
            leverageChange: analysis.topLeverageChange
        )
        let level = normalizedPriorityLevel(priority.priorityLevel, rank: rank)
        let cleanedStyles = sanitizedPreferredStyles(
            priority.preferredStyles,
            profile: profile,
            fallback: fallbackIntent.preferredStyles
        )
        let cleanedPatterns = sanitizedPreferredMovementPatterns(
            priority.preferredMovementPatterns,
            area: canonicalArea,
            profile: profile,
            fallback: fallbackIntent.preferredMovementPatterns
        )
        let cleanedVolumeBias = priority.volumeBias.trimmedOr(default: fallbackIntent.volumeBias)
        let cleanedDirectWorkBias = priority.directWorkBias.trimmedOr(default: fallbackIntent.directWorkBias)
        let cleanedRationale = priority.rationale.trimmedOr(default: fallbackIntent.rationale)

        return MusclePriorityIntent(
            area: canonicalArea,
            priorityLevel: level,
            rank: rank,
            rationale: cleanedRationale,
            weeklyDayTarget: max(1, min(3, priority.weeklyDayTarget)),
            weeklyExerciseTarget: max(1, min(5, priority.weeklyExerciseTarget)),
            weeklyDirectSetTarget: weeklyDirectSetTarget(for: level, volumeBias: cleanedVolumeBias, directWorkBias: cleanedDirectWorkBias),
            weeklyStimulusTarget: weeklyStimulusTarget(for: level, volumeBias: cleanedVolumeBias, directWorkBias: cleanedDirectWorkBias),
            preferredStyles: cleanedStyles,
            preferredMovementPatterns: cleanedPatterns,
            coverageKeywords: priorityCoverageKeywords(for: canonicalArea) + cleanedPatterns,
            accessoryCatalog: profile.accessoryCatalog,
            volumeBias: cleanedVolumeBias,
            directWorkBias: cleanedDirectWorkBias
        )
    }

    func bestMatchingRegionAssessment(for area: String, within regionBreakdown: [RegionAssessment]) -> RegionAssessment? {
        let profile = priorityProfile(for: area)

        return regionBreakdown.first { region in
            let combined = normalizedPriorityText("\(region.region) \(region.assessment)")
            return profile.triggerKeywords.contains(where: { containsPriorityPhrase(in: combined, keywords: [$0]) })
        }
    }

    func priorityRationale(
        area: String,
        profile: PriorityFocusProfile,
        matchedRegion: RegionAssessment?,
        workoutRecommendations: [String],
        leverageChange: String
    ) -> String {
        let recommendation = matchingWorkoutRecommendation(for: area, profile: profile, within: workoutRecommendations)
        let regionNote = matchedRegion?.assessment.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let leverageNote = leverageChange.trimmedOr(default: "")

        let parts = [regionNote, recommendation, leverageNote]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.isEmpty {
            return "Use targeted hypertrophy work and intelligent session emphasis to improve \(area.lowercased())."
        }

        return parts.joined(separator: " ")
    }

    func matchingWorkoutRecommendation(
        for area: String,
        profile: PriorityFocusProfile,
        within workoutRecommendations: [String]
    ) -> String {
        for recommendation in workoutRecommendations {
            let normalized = normalizedPriorityText(recommendation)
            if profile.triggerKeywords.contains(where: { containsPriorityPhrase(in: normalized, keywords: [$0]) }) {
                return recommendation.trimmedOr(default: "")
            }
            if profile.coverageKeywords.contains(where: { containsPriorityPhrase(in: normalized, keywords: [$0]) }) {
                return recommendation.trimmedOr(default: "")
            }
        }

        return ""
    }

    func sanitizedPreferredStyles(
        _ providedStyles: [String],
        profile: PriorityFocusProfile,
        fallback: [String]
    ) -> [String] {
        let allowedStyles = Set(evidenceProfile.allowedStyles.map { canonicalTrainingStyle($0) })
        let supportedStyles = Set(profile.preferredStyles.map { canonicalTrainingStyle($0) })
        let cleaned = providedStyles
            .map { canonicalTrainingStyle($0.trimmedOr(default: "")) }
            .filter { !$0.isEmpty && allowedStyles.contains($0) }

        let aligned = cleaned.filter { supportedStyles.contains($0) }
        let seed = aligned.isEmpty ? fallback : aligned + fallback
        var seen = Set<String>()

        return seed.filter { style in
            let canonical = canonicalTrainingStyle(style)
            guard !seen.contains(canonical) else { return false }
            seen.insert(canonical)
            return true
        }
    }

    func sanitizedPreferredMovementPatterns(
        _ providedPatterns: [String],
        area: String,
        profile: PriorityFocusProfile,
        fallback: [String]
    ) -> [String] {
        let validProvided = providedPatterns
            .map { $0.trimmedOr(default: "") }
            .filter { !$0.isEmpty }
            .filter { structuredPatternSupportsPriority($0, area: area, profile: profile) }

        let seed = validProvided.isEmpty ? fallback : validProvided + fallback
        var seen = Set<String>()

        return seed.filter { pattern in
            let normalized = normalizedPriorityText(pattern)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    func structuredPatternSupportsPriority(
        _ pattern: String,
        area: String,
        profile: PriorityFocusProfile
    ) -> Bool {
        let normalizedPattern = normalizedPriorityText(pattern)
        guard !normalizedPattern.isEmpty else { return false }

        let supportedPhrases = Set(
            (profile.coverageKeywords + stimulusAreaAliases(for: area))
                .map(normalizedPriorityText)
        )

        if supportedPhrases.contains(normalizedPattern) {
            return true
        }

        let patternTokens = Set(priorityTextTokens(normalizedPattern))
        guard !patternTokens.isEmpty else { return false }

        return supportedPhrases.contains { phrase in
            let phraseTokens = Set(priorityTextTokens(phrase))
            let sharedTokens = patternTokens.intersection(phraseTokens)
            guard !sharedTokens.isEmpty else { return false }
            return sharedTokens.count >= min(patternTokens.count, max(1, phraseTokens.count - 1))
        }
    }

    func inferredMovementPatterns(
        for area: String,
        profile: PriorityFocusProfile,
        workoutRecommendations: [String]
    ) -> [String] {
        let matchedRecommendation = matchingWorkoutRecommendation(for: area, profile: profile, within: workoutRecommendations)
        let normalizedAreaTokens = normalizedPriorityText(area)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        let profilePatterns = profile.coverageKeywords.filter { keyword in
            let normalizedKeyword = normalizedPriorityText(keyword)
            return normalizedKeyword.contains(" ")
                || !normalizedAreaTokens.contains(normalizedKeyword)
        }

        if matchedRecommendation.isEmpty {
            return Array(profilePatterns.prefix(4))
        }

        let inferred = profilePatterns.filter { pattern in
            matchedRecommendation.localizedCaseInsensitiveContains(pattern)
        }

        return Array((inferred.isEmpty ? profilePatterns : inferred).prefix(4))
    }

    func normalizedPriorityLevel(_ rawValue: String?, rank: Int) -> String {
        let normalized = normalizedPriorityText(rawValue ?? "")
        if normalized.contains("high") { return "High" }
        if normalized.contains("medium") { return "Medium" }
        if normalized.contains("low") { return "Low" }
        return rank == 0 ? "High" : "Medium"
    }

    func priorityScore(for level: String) -> Int {
        switch normalizedPriorityLevel(level, rank: 0) {
        case "High": return 3
        case "Medium": return 2
        default: return 1
        }
    }

    func weeklyDayTarget(for priorityLevel: String, rank: Int) -> Int {
        // EvidenceProfile.md FREQ-001 [confidence: moderate]
        let normalizedLevel = normalizedPriorityLevel(priorityLevel, rank: rank)
        return evidenceProfile.frequencyTargetsByPriority[normalizedLevel] ?? 1
    }

    func weeklyExerciseTarget(for priorityLevel: String, rank: Int) -> Int {
        // EvidenceProfile.md SLOT-001 [confidence: moderate]
        let normalizedLevel = normalizedPriorityLevel(priorityLevel, rank: rank)
        return evidenceProfile.exerciseSlotTargetsByPriority[normalizedLevel] ?? 1
    }

    func weeklyDirectSetTarget(for priorityLevel: String, volumeBias: String, directWorkBias: String) -> Double {
        // EvidenceProfile.md VOL-001 [confidence: moderate]
        let normalizedLevel = normalizedPriorityLevel(priorityLevel, rank: 0)
        let baseRange = evidenceProfile.directSetTargetsByPriority[normalizedLevel]
            ?? evidenceProfile.directSetTargetsByPriority["Medium"]
            ?? 5...8
        var target = (baseRange.lowerBound + baseRange.upperBound) / 2
        let normalizedVolumeBias = normalizedPriorityText(volumeBias)
        if let volumeAdjustment = evidenceProfile.directSetTargetsByVolumeBias[normalizedVolumeBias] {
            target += volumeAdjustment
        } else if normalizedVolumeBias.contains("high") {
            target += 1.5
        } else if normalizedVolumeBias.contains("low") {
            target -= 1
        }
        let normalizedDirectBias = normalizedPriorityText(directWorkBias)
        if let directAdjustment = evidenceProfile.directWorkBiasAdjustments[normalizedDirectBias] {
            target += directAdjustment
        } else if normalizedDirectBias.contains("direct") {
            target += 1
        } else if normalizedDirectBias.contains("indirect") || normalizedDirectBias.contains("mixed") {
            target -= 0.5
        }

        return max(3, target)
    }

    func weeklyStimulusTarget(for priorityLevel: String, volumeBias: String, directWorkBias: String) -> Double {
        // EvidenceProfile.md VOL-002 [confidence: low-moderate]
        let directTarget = weeklyDirectSetTarget(for: priorityLevel, volumeBias: volumeBias, directWorkBias: directWorkBias)
        let normalizedDirectBias = normalizedPriorityText(directWorkBias)
        let bonus = normalizedDirectBias.contains("direct")
            ? evidenceProfile.weightedStimulusBonusDirect
            : evidenceProfile.weightedStimulusBonusIndirect
        return directTarget + bonus
    }

    func priorityCoverage(for allocation: BlueprintPriorityAllocation, stimulusReport: WeekStimulusReport) -> PriorityCoverage {
        let aliases = stimulusAreaAliases(for: allocation.area)

        let dayMatches = aliases.reduce(into: Set<Int>()) { partialResult, alias in
            partialResult.formUnion(stimulusReport.exposureDays[alias] ?? [])
        }.count

        let exerciseMatches = aliases.reduce(into: Set<String>()) { partialResult, alias in
            partialResult.formUnion(stimulusReport.exerciseKeys[alias] ?? [])
        }.count

        let directSets = aliases.reduce(0.0) { partialResult, alias in
            partialResult + (stimulusReport.directSets[alias] ?? 0)
        }

        let weightedStimulus = aliases.reduce(0.0) { partialResult, alias in
            partialResult + (stimulusReport.weightedStimulus[alias] ?? 0)
        }

        let peakSessionFatigue = aliases.reduce(0) { partialResult, alias in
            max(partialResult, stimulusReport.peakSessionFatigue[alias] ?? 0)
        }

        return PriorityCoverage(
            label: allocation.area,
            dayMatches: dayMatches,
            exerciseMatches: exerciseMatches,
            directSets: directSets,
            weightedStimulus: weightedStimulus,
            peakSessionFatigue: peakSessionFatigue
        )
    }

    func peakDirectSession(
        for allocation: BlueprintPriorityAllocation,
        stimulusReport: WeekStimulusReport
    ) -> (dayNumber: Int, directSets: Double)? {
        let aliases = stimulusAreaAliases(for: allocation.area)
        var totalsByDay: [Int: Double] = [:]

        for alias in aliases {
            for (dayNumber, directSets) in stimulusReport.directSetsByDay[alias] ?? [:] {
                totalsByDay[dayNumber, default: 0] += directSets
            }
        }

        guard let peak = totalsByDay.max(by: { lhs, rhs in lhs.value < rhs.value }) else {
            return nil
        }
        return (dayNumber: peak.key, directSets: peak.value)
    }

    func allowedPerSessionDirectSetCap(
        for allocation: BlueprintPriorityAllocation,
        dayNumber: Int,
        blueprint: ProgramBlueprint,
        dayStart: Int
    ) -> Double {
        if isBlueprintFocusDay(
            dayNumber: dayNumber,
            for: allocation,
            blueprint: blueprint,
            dayStart: dayStart
        ) {
            return allocation.maxFocusSessionDirectSets
        }
        return allocation.maxPerSessionDirectSets
    }

    func isBlueprintFocusDay(
        dayNumber: Int,
        for allocation: BlueprintPriorityAllocation,
        blueprint: ProgramBlueprint,
        dayStart: Int
    ) -> Bool {
        guard let relativeDayIndex = relativeBlueprintDayIndex(for: dayNumber, dayStart: dayStart),
              let plan = blueprint.dayPlans.first(where: { $0.dayIndex == relativeDayIndex }),
              let focusArea = plan.focusArea else {
            return false
        }

        let allocationAliases = Set(stimulusAreaAliases(for: allocation.area).map(normalizedPriorityText))
        let focusAliases = Set(stimulusAreaAliases(for: focusArea).map(normalizedPriorityText))
        return !allocationAliases.isDisjoint(with: focusAliases)
    }

    func blueprintDayNumber(_ relativeDayIndex: Int, dayStart: Int) -> Int {
        dayStart + relativeDayIndex - 1
    }

    func relativeBlueprintDayIndex(for actualDayNumber: Int, dayStart: Int) -> Int? {
        let relativeIndex = actualDayNumber - dayStart + 1
        return (1...7).contains(relativeIndex) ? relativeIndex : nil
    }

    func buildWeekStimulusReport(from days: [WorkoutDayResponse]) -> WeekStimulusReport {
        var report = WeekStimulusReport()

        for day in days where !day.isRestDay {
            var dayFatigue = 0
            var stimulatedAreas = Set<String>()
            var fatigueByArea: [String: Int] = [:]

            for exercise in day.exercises {
                let metadata = exerciseMetadata(for: exercise)
                let fatigueContribution = fatigueContribution(for: exercise, metadata: metadata)
                dayFatigue += fatigueContribution
                let exerciseKey = "\(day.dayNumber):\(normalizeExerciseName(exercise.exerciseName))"

                for area in metadata.primaryAreas {
                    let directCredit = directSetCredit(for: exercise, area: area)
                    guard directCredit > 0 else {
                        // Support-grade work contributes weighted stimulus only —
                        // no direct sets, exposure-frequency, or slot credit.
                        let kind = focusStimulusKind(
                            exerciseName: exercise.exerciseName,
                            muscleTarget: exercise.muscleTarget,
                            focusArea: area
                        )
                        if kind == .support {
                            report.weightedStimulus[area, default: 0] += focusStimulusCredit(for: .support) * Double(exercise.sets)
                        }
                        continue
                    }

                    report.directSets[area, default: 0] += directCredit
                    var dayDirectSets = report.directSetsByDay[area, default: [:]]
                    dayDirectSets[day.dayNumber, default: 0] += directCredit
                    report.directSetsByDay[area] = dayDirectSets
                    report.weightedStimulus[area, default: 0] += directCredit
                    report.exposureDays[area, default: []].insert(day.dayNumber)
                    report.exerciseMatches[area, default: 0] += 1
                    report.exerciseKeys[area, default: []].insert(exerciseKey)
                    stimulatedAreas.insert(area)
                    fatigueByArea[area, default: 0] += fatigueContribution
                }

                for area in metadata.secondaryAreas {
                    report.weightedStimulus[area, default: 0] += Double(exercise.sets) * 0.5
                    report.exposureDays[area, default: []].insert(day.dayNumber)
                    report.exerciseMatches[area, default: 0] += 1
                    report.exerciseKeys[area, default: []].insert(exerciseKey)
                    stimulatedAreas.insert(area)
                    fatigueByArea[area, default: 0] += max(1, fatigueContribution / 2)
                }
            }

            report.dailyFatigue[day.dayNumber] = dayFatigue
            for area in stimulatedAreas {
                let areaFatigue = fatigueByArea[area, default: 0]
                report.peakSessionFatigue[area] = max(report.peakSessionFatigue[area] ?? 0, areaFatigue)
            }
        }

        return report
    }

    func directSetCredit(for exercise: WorkoutExerciseResponse, area: String) -> Double {
        let qualityKind = focusStimulusKind(
            exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget,
            focusArea: area
        )
        switch qualityKind {
        case .prime, .secondary:
            return focusStimulusCredit(for: qualityKind) * Double(exercise.sets)
        case .support:
            // Support/scapular-control work must never be credited as direct
            // hypertrophy volume — returning a partial credit here let corrective
            // work satisfy direct-set targets. It still earns weighted-stimulus
            // credit in buildWeekStimulusReport. Returning 0 (not falling through)
            // also prevents the metadata path below from re-crediting it at 1.0.
            return 0
        case .none:
            break
        }

        let metadata = exerciseMetadata(for: exercise)
        let areaAliases = Set(stimulusAreaAliases(for: area).map(normalizedPriorityText))
        let primaryAliases = Set(metadata.primaryAreas.flatMap { stimulusAreaAliases(for: $0) }.map(normalizedPriorityText))
        if !areaAliases.isDisjoint(with: primaryAliases) {
            return Double(exercise.sets)
        }

        let secondaryAliases = Set(metadata.secondaryAreas.flatMap { stimulusAreaAliases(for: $0) }.map(normalizedPriorityText))
        if !areaAliases.isDisjoint(with: secondaryAliases) {
            return Double(exercise.sets) * 0.5
        }

        return 0
    }

    func fatigueContribution(for exercise: WorkoutExerciseResponse, metadata: ExerciseMetadata) -> Int {
        let setMultiplier = exercise.sets >= 5 ? 3 : exercise.sets >= 4 ? 2 : 1
        return metadata.fatigueCost * setMultiplier
    }

    func maxSessionFatigue(for intent: MusclePriorityIntent) -> Int {
        if intent.weeklyDayTarget >= 2 {
            return 18
        }
        return normalizedPriorityLevel(intent.priorityLevel, rank: intent.rank) == "High" ? 22 : 19
    }

    func maxSessionFatigue(for allocation: BlueprintPriorityAllocation) -> Int {
        if allocation.targetFrequency >= 2 {
            return evidenceProfile.maxSessionPriorityFatigue
        }
        return normalizedPriorityLevel(allocation.priorityLevel, rank: 0) == "High"
            ? evidenceProfile.maxSessionPriorityFatigue + 4
            : evidenceProfile.maxSessionPriorityFatigue + 1
    }

    func maxDailyFatigueThreshold(for days: [WorkoutDayResponse], dayNumber: Int) -> Int {
        guard let day = days.first(where: { $0.dayNumber == dayNumber }) else { return 13 }
        let style = inferredDayStyle(dayName: day.dayName, muscleGroups: day.muscleGroups) ?? ""

        return evidenceProfile.sessionFatigueCapsByStyle[style.lowercased()] ?? 18
    }

    func formatStimulusValue(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

}
