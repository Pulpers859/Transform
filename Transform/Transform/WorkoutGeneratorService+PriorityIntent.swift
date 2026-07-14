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
        let setTarget = weeklyDirectSetTarget(for: priorityLevel, volumeBias: defaultVolumeBias, directWorkBias: defaultDirectWorkBias)

        return MusclePriorityIntent(
            area: canonicalArea,
            priorityLevel: priorityLevel,
            rank: rank,
            rationale: rationale,
            weeklyDayTarget: weeklyDayTarget(for: priorityLevel, rank: rank),
            weeklyExerciseTarget: max(
                weeklyExerciseTarget(for: priorityLevel, rank: rank),
                minimumExerciseSlots(forWeeklySetTarget: setTarget)
            ),
            weeklyDirectSetTarget: setTarget,
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
        let setTarget = weeklyDirectSetTarget(for: level, volumeBias: cleanedVolumeBias, directWorkBias: cleanedDirectWorkBias)

        return MusclePriorityIntent(
            area: canonicalArea,
            priorityLevel: level,
            rank: rank,
            rationale: cleanedRationale,
            weeklyDayTarget: max(1, min(3, priority.weeklyDayTarget)),
            // The structured intent's slot count is advisory; the set-target floor is not.
            // An AI-supplied 2 slots against a 10.5-set target is what produced a 6-set
            // single-exercise correction in the 2026-07-14 audit.
            weeklyExerciseTarget: max(
                max(1, min(5, priority.weeklyExerciseTarget)),
                minimumExerciseSlots(forWeeklySetTarget: setTarget)
            ),
            weeklyDirectSetTarget: setTarget,
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

    /// Minimum weekly exercise slots implied by a direct-set target so that no single
    /// exercise is forced above ~4 working sets. Without this floor, a 10+ set priority
    /// arriving with 2 slots makes the correction pass inflate one exercise to 5-6 sets
    /// to satisfy the validator — diminishing-returns volume the slot math created.
    func minimumExerciseSlots(forWeeklySetTarget setTarget: Double) -> Int {
        max(1, Int(ceil(setTarget / 4.0)))
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
        var directSetsByDay: [Int: Double] = [:]

        let dayMatches = aliases.reduce(into: Set<Int>()) { partialResult, alias in
            partialResult.formUnion(stimulusReport.exposureDays[alias] ?? [])
        }.count

        for alias in aliases {
            for (dayNumber, directSets) in stimulusReport.directSetsByDay[alias] ?? [:] {
                directSetsByDay[dayNumber, default: 0] += directSets
            }
        }

        let meaningfulThreshold = minimumMeaningfulPriorityExposureSets(for: allocation.area)
        let meaningfulDayMatches = directSetsByDay.values.filter { $0 + 0.01 >= meaningfulThreshold }.count

        let exerciseMatches = aliases.reduce(into: Set<String>()) { partialResult, alias in
            partialResult.formUnion(stimulusReport.exerciseKeys[alias] ?? [])
        }.count

        let variationCount = aliases.reduce(into: Set<String>()) { partialResult, alias in
            partialResult.formUnion(stimulusReport.exerciseNames[alias] ?? [])
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
            meaningfulDayMatches: meaningfulDayMatches,
            exerciseMatches: exerciseMatches,
            variationCount: variationCount,
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
                    let credit = stimulusCredit(for: exercise, area: area)
                    guard credit.directSets > 0 || credit.weightedStimulus > 0 else { continue }

                    if credit.directSets > 0 {
                        report.directSets[area, default: 0] += credit.directSets
                        var dayDirectSets = report.directSetsByDay[area, default: [:]]
                        dayDirectSets[day.dayNumber, default: 0] += credit.directSets
                        report.directSetsByDay[area] = dayDirectSets
                    }
                    report.weightedStimulus[area, default: 0] += credit.weightedStimulus
                    report.exposureDays[area, default: []].insert(day.dayNumber)
                    report.exerciseMatches[area, default: 0] += 1
                    report.exerciseKeys[area, default: []].insert(exerciseKey)
                    report.exerciseNames[area, default: []].insert(normalizeExerciseName(exercise.exerciseName))
                    stimulatedAreas.insert(area)
                    fatigueByArea[area, default: 0] += fatigueContribution
                }

                for area in metadata.secondaryAreas {
                    report.weightedStimulus[area, default: 0] += Double(exercise.sets) * 0.5
                    report.exposureDays[area, default: []].insert(day.dayNumber)
                    report.exerciseMatches[area, default: 0] += 1
                    report.exerciseKeys[area, default: []].insert(exerciseKey)
                    report.exerciseNames[area, default: []].insert(normalizeExerciseName(exercise.exerciseName))
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
        stimulusCredit(for: exercise, area: area).directSets
    }

    // MARK: - Major Muscle Group Accounting (BASE-001 floor / maintenance ceiling)

    /// EvidenceProfile.md BASE-001 [confidence: high]. Seeds resolve through
    /// `stimulusAreaAliases`, so "back" covers Lats/Upper Back/Mid Back and "core"
    /// covers Abs/Obliques/Serratus. "calf" (not "calves") because the alias table
    /// matches on the substring "calf".
    var majorMuscleGroups: [(label: String, seed: String)] {
        [
            ("Chest", "chest"),
            ("Back", "back"),
            ("Shoulders", "shoulders"),
            ("Biceps", "biceps"),
            ("Triceps", "triceps"),
            ("Quads", "quads"),
            ("Hamstrings", "hamstrings"),
            ("Glutes", "glutes"),
            ("Calves", "calf"),
            ("Core", "core")
        ]
    }

    func normalizedGroupAliases(forSeed seed: String) -> Set<String> {
        Set(stimulusAreaAliases(for: seed).map(normalizedPriorityText))
    }

    /// Maps a specific priority to explicit major-muscle ledgers. Composite exercise metadata such
    /// as Posterior Chain and Quads/Glutes must not make neighboring groups look prioritized.
    func majorMuscleGroupSeeds(forPriorityArea area: String) -> Set<String> {
        let normalized = normalizedPriorityText(area)
        if normalized.contains("posterior chain") {
            return ["hamstrings", "glutes"]
        }
        if normalized.contains("quad") && normalized.contains("glute") {
            return ["quads", "glutes"]
        }
        if normalized == "arms" || normalized.contains("arm development") {
            return ["biceps", "triceps"]
        }
        if normalized == "legs" || normalized.contains("lower body") {
            return ["quads", "hamstrings", "glutes", "calf"]
        }
        if normalized.contains("upper chest") || normalized == "chest" || normalized.contains("pec") {
            return ["chest"]
        }
        if normalized.contains("lateral delt") || normalized.contains("rear delt")
            || normalized.contains("posterior delt") || normalized.contains("front delt")
            || normalized.contains("anterior delt") || normalized.contains("shoulder") {
            return ["shoulders"]
        }
        if containsPriorityPhrase(
            in: normalized,
            keywords: ["back", "lat", "lats", "latissimus dorsi", "latissimus"]
        ) {
            return ["back"]
        }
        if normalized.contains("bicep") || normalized.contains("brachialis") {
            return ["biceps"]
        }
        if normalized.contains("tricep") { return ["triceps"] }
        if normalized.contains("quad") { return ["quads"] }
        if normalized.contains("hamstring") { return ["hamstrings"] }
        if normalized.contains("glute") { return ["glutes"] }
        if normalized.contains("calf") { return ["calf"] }
        if normalized.contains("core") || normalized.contains("abs")
            || normalized.contains("oblique") || normalized.contains("serratus") {
            return ["core"]
        }
        return []
    }

    func isMajorMuscleGroupPrioritized(seed: String, blueprint: ProgramBlueprint) -> Bool {
        let normalizedSeed = normalizedPriorityText(seed)
        return blueprint.priorityAllocations.contains {
            majorMuscleGroupSeeds(forPriorityArea: $0.area)
                .map(normalizedPriorityText)
                .contains(normalizedSeed)
        }
    }

    func exerciseDirectlyTargets(
        groupAliases: Set<String>,
        exerciseName: String,
        muscleTarget: String
    ) -> Bool {
        let metadata = exerciseMetadata(forExerciseName: exerciseName, muscleTarget: muscleTarget)
        let primaryAliases = Set(
            metadata.primaryAreas
                .flatMap { stimulusAreaAliases(for: $0) }
                .map(normalizedPriorityText)
        )
        return !groupAliases.isDisjoint(with: primaryAliases)
    }

    /// Weekly direct sets for one muscle group, computed straight from the days rather
    /// than from `WeekStimulusReport` — the report keys per metadata area, so summing
    /// Lats + Upper Back + Mid Back keys would double-count multi-area rows.
    func weeklyDirectSets(forGroupAliases aliases: Set<String>, days: [WorkoutDayResponse]) -> Double {
        days.filter { !$0.isRestDay }.reduce(0.0) { weekTotal, day in
            weekTotal + day.exercises.reduce(0.0) { dayTotal, exercise in
                guard exerciseDirectlyTargets(
                    groupAliases: aliases,
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget
                ) else { return dayTotal }
                return dayTotal + Double(exercise.sets)
            }
        }
    }

    func weightedStimulusCredit(for exercise: WorkoutExerciseResponse, area: String) -> Double {
        stimulusCredit(for: exercise, area: area).weightedStimulus
    }

    func stimulusCredit(for exercise: WorkoutExerciseResponse, area: String) -> StimulusCredit {
        let qualityKind = focusStimulusKind(
            exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget,
            focusArea: area
        )
        if qualityKind == .support {
            return StimulusCredit(
                directSets: 0,
                weightedStimulus: focusStimulusCredit(for: qualityKind) * Double(exercise.sets)
            )
        }
        let qualityCredit = focusStimulusCredit(for: qualityKind) * Double(exercise.sets)
        if qualityCredit > 0 {
            return StimulusCredit(directSets: qualityCredit, weightedStimulus: qualityCredit)
        }

        let metadata = exerciseMetadata(for: exercise)
        let areaAliases = Set(stimulusAreaAliases(for: area).map(normalizedPriorityText))
        let primaryAliases = Set(metadata.primaryAreas.flatMap { stimulusAreaAliases(for: $0) }.map(normalizedPriorityText))
        if !areaAliases.isDisjoint(with: primaryAliases) {
            return StimulusCredit(directSets: Double(exercise.sets), weightedStimulus: Double(exercise.sets))
        }

        let secondaryAliases = Set(metadata.secondaryAreas.flatMap { stimulusAreaAliases(for: $0) }.map(normalizedPriorityText))
        if !areaAliases.isDisjoint(with: secondaryAliases) {
            let credit = Double(exercise.sets) * 0.5
            return StimulusCredit(directSets: credit, weightedStimulus: credit)
        }

        return .none
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

    func minimumMeaningfulPriorityExposureSets(for area: String) -> Double {
        let normalized = normalizedPriorityText(area)
        if containsAny(
            normalized,
            keywords: [
                "lateral delt", "rear delt", "posterior delt", "anterior delt", "shoulder",
                "bicep", "tricep", "brachialis", "forearm", "calf", "abs", "core", "oblique", "serratus"
            ]
        ) {
            return 2.0
        }
        return 3.0
    }

    func maximumUsefulVariationCount(for allocation: BlueprintPriorityAllocation) -> Int {
        switch normalizedPriorityLevel(allocation.priorityLevel, rank: 0) {
        case "High":
            return 4
        case "Medium":
            return 3
        default:
            return 2
        }
    }

}
