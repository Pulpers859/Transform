import Foundation

extension ClaudeService {
    func trainingIntentPlan(from analysis: BodyAnalysisResult) -> TrainingIntentPlan {
        if let structuredIntent = analysis.structuredTrainingIntent,
           !structuredIntent.priorities.isEmpty {
            return trainingIntentPlan(from: structuredIntent, analysis: analysis)
        }

        let focusAreas = derivedPriorityAreas(from: analysis)
        let priorities = focusAreas.enumerated().map { index, area in
            musclePriorityIntent(
                area: area,
                rank: index,
                regionBreakdown: analysis.regionBreakdown,
                workoutRecommendations: analysis.workoutRecommendations,
                leverageChange: analysis.topLeverageChange
            )
        }

        let basePlan = TrainingIntentPlan(
            splitRecommendation: "Adaptive Hypertrophy Split",
            weeklyTrainingDays: nil,
            programmingNotes: [],
            priorities: mergedPriorityIntents(priorities),
            topLeverageChange: analysis.topLeverageChange.trimmedOr(default: "(not provided)"),
            posturalFocus: analysis.posturalNotes.trimmedOr(default: "(none)"),
            injuryRiskFocus: analysis.injuryRiskNotes.trimmedOr(default: "(none)"),
            calibration: neutralCalibrationProfile()
        )
        return calibratedTrainingIntentPlan(basePlan, using: calibrationProfile(from: analysis))
    }

    func fallbackTrainingIntentPlan(from focusAreas: [String]) -> TrainingIntentPlan {
        let priorities = prioritizedFocusAreas(from: focusAreas).enumerated().map { index, area in
            musclePriorityIntent(
                area: area,
                rank: index,
                regionBreakdown: [],
                workoutRecommendations: [],
                leverageChange: ""
            )
        }

        return TrainingIntentPlan(
            splitRecommendation: "Adaptive Hypertrophy Split",
            weeklyTrainingDays: nil,
            programmingNotes: [],
            priorities: mergedPriorityIntents(priorities),
            topLeverageChange: "(not provided)",
            posturalFocus: "(none)",
            injuryRiskFocus: "(none)",
            calibration: neutralCalibrationProfile()
        )
    }

    func trainingIntentPlan(from structuredIntent: StructuredTrainingIntent, analysis: BodyAnalysisResult) -> TrainingIntentPlan {
        let priorities = structuredIntent.priorities.enumerated().map { index, priority in
            musclePriorityIntent(from: priority, rank: index, analysis: analysis)
        }

        let basePlan = TrainingIntentPlan(
            splitRecommendation: structuredIntent.splitRecommendation.trimmedOr(default: "Adaptive Hypertrophy Split"),
            weeklyTrainingDays: max(4, min(6, structuredIntent.weeklyTrainingDays)),
            programmingNotes: structuredIntent.programmingNotes.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            priorities: mergedPriorityIntents(priorities),
            topLeverageChange: analysis.topLeverageChange.trimmedOr(default: "(not provided)"),
            posturalFocus: analysis.posturalNotes.trimmedOr(default: "(none)"),
            injuryRiskFocus: analysis.injuryRiskNotes.trimmedOr(default: "(none)"),
            calibration: neutralCalibrationProfile()
        )
        return calibratedTrainingIntentPlan(basePlan, using: calibrationProfile(from: analysis))
    }

    func trainingIntentContext(from trainingIntent: TrainingIntentPlan) -> String {
        guard !trainingIntent.priorities.isEmpty else {
            return "Structured training intent: no priority muscles were available, so use balanced hypertrophy programming."
        }

        let lines = trainingIntent.priorities.map { intent in
            let movementPatterns = intent.preferredMovementPatterns.joined(separator: ", ")
            return """
            - rank \(intent.rank + 1): \(intent.area) [\(intent.priorityLevel)]
              rationale: \(intent.rationale)
              weekly_targets: \(intent.weeklyDayTarget) days, \(intent.weeklyExerciseTarget) targeted exercises, \(formatStimulusValue(intent.weeklyDirectSetTarget)) direct sets, \(formatStimulusValue(intent.weeklyStimulusTarget)) weighted stimulus
              preferred_styles: \(intent.preferredStyles.joined(separator: ", "))
              preferred_patterns: \(movementPatterns.isEmpty ? "(none inferred)" : movementPatterns)
              volume_bias: \(intent.volumeBias)
              direct_work_bias: \(intent.directWorkBias)
            """
        }.joined(separator: "\n")

        return """
        Structured training intent (derived from the analysis and used as the programming contract):
        split_recommendation: \(trainingIntent.splitRecommendation)
        weekly_training_days: \(trainingIntent.weeklyTrainingDays.map { String($0) } ?? "(model-decided within 4-6)")
        top_leverage_change: \(trainingIntent.topLeverageChange)
        postural_focus: \(trainingIntent.posturalFocus)
        injury_risk_focus: \(trainingIntent.injuryRiskFocus)
        programming_notes: \(trainingIntent.programmingNotes.isEmpty ? "(none)" : trainingIntent.programmingNotes.joined(separator: " | "))
        priorities:
        \(lines)
        """
    }

    func blueprintContext(from blueprint: ProgramBlueprint) -> String {
        let priorityLines = blueprint.priorityAllocations.map { allocation in
            let patterns = allocation.preferredMovementPatterns.joined(separator: ", ")
            return """
            - \(allocation.area): \(allocation.targetFrequency) exposures, \(formatStimulusValue(allocation.directSetTarget)) direct sets, \(formatStimulusValue(allocation.weightedStimulusTarget)) weighted stimulus, max \(formatStimulusValue(allocation.maxPerSessionDirectSets)) direct sets per session (\(formatStimulusValue(allocation.maxFocusSessionDirectSets)) on a designated focus day), styles \(allocation.preferredStyles.joined(separator: ", ")), patterns \(patterns.isEmpty ? "(none)" : patterns)
            """
        }.joined(separator: "\n")

        let dayLines = blueprint.dayPlans.map { dayPlan in
            if dayPlan.isRestDay {
                return "- day \(dayPlan.dayIndex): Rest / Recovery"
            }

            let focus = dayPlan.focusArea ?? "Balanced"
            let support = dayPlan.supportAreas.isEmpty
                ? ""
                : "; support \(dayPlan.supportAreas.joined(separator: ", "))"
            let patterns = dayPlan.emphasisPatterns.joined(separator: ", ")
            return "- day \(dayPlan.dayIndex): \(dayPlan.style) focus \(focus)\(support); priority slots \(dayPlan.targetPrioritySlots); fatigue cap \(dayPlan.targetFatigueCap); session budget ~\(dayPlan.targetSessionMinutes) min; patterns \(patterns.isEmpty ? "(none)" : patterns)"
        }.joined(separator: "\n")

        return """
        Deterministic weekly blueprint (generated from the evidence profile and used as the execution plan):
        evidence_version: \(blueprint.evidenceVersion)
        split_recommendation: \(blueprint.splitRecommendation)
        weekly_training_days: \(blueprint.weeklyTrainingDays)
        top_leverage_change: \(blueprint.topLeverageChange)
        postural_focus: \(blueprint.posturalFocus)
        injury_risk_focus: \(blueprint.injuryRiskFocus)
        programming_notes: \(blueprint.programmingNotes.isEmpty ? "(none)" : blueprint.programmingNotes.joined(separator: " | "))
        priority_allocations:
        \(priorityLines)
        day_plans:
        \(dayLines)
        """
    }

    func generationContext(analysisSummary: String, trainingIntentSummary: String, blueprintSummary: String) -> String {
        """
        --- Body Analysis ---
        \(analysisSummary)
        --- end Body Analysis ---

        --- Structured Training Intent ---
        \(trainingIntentSummary)
        --- end Structured Training Intent ---

        --- Weekly Blueprint ---
        \(blueprintSummary)
        --- end Weekly Blueprint ---
        """
    }

    func programBlueprint(for trainingIntent: TrainingIntentPlan, weekNumber: Int) -> ProgramBlueprint {
        let trainingDays = max(4, min(6, trainingIntent.weeklyTrainingDays ?? evidenceProfile.defaultTrainingDays))
        let allocations = mergedPriorityIntents(trainingIntent.priorities).map { intent in
            blueprintAllocation(for: intent)
        }
        let dayPlans = buildBlueprintDayPlans(
            trainingDays: trainingDays,
            priorityAllocations: allocations,
            weekNumber: weekNumber,
            calibration: trainingIntent.calibration
        )

        return ProgramBlueprint(
            evidenceVersion: evidenceProfile.version,
            splitRecommendation: trainingIntent.splitRecommendation,
            weeklyTrainingDays: trainingDays,
            priorityAllocations: allocations,
            dayPlans: dayPlans,
            topLeverageChange: trainingIntent.topLeverageChange,
            posturalFocus: trainingIntent.posturalFocus,
            injuryRiskFocus: trainingIntent.injuryRiskFocus,
            programmingNotes: trainingIntent.programmingNotes,
            calibration: trainingIntent.calibration
        )
    }

    func blueprintAllocation(for intent: MusclePriorityIntent) -> BlueprintPriorityAllocation {
        let normalizedLevel = normalizedPriorityLevel(intent.priorityLevel, rank: intent.rank)
        let evenlyDistributedCap = max(3, ceil(intent.weeklyDirectSetTarget / Double(max(1, intent.weeklyDayTarget))))
        let focusShare = evidenceProfile.focusSessionDirectSetShareByPriority[normalizedLevel] ?? 0.7
        let focusSessionCap = max(
            evenlyDistributedCap,
            ceil(intent.weeklyDirectSetTarget * focusShare)
        )

        return BlueprintPriorityAllocation(
            area: intent.area,
            priorityLevel: intent.priorityLevel,
            rationale: intent.rationale,
            targetFrequency: intent.weeklyDayTarget,
            targetExerciseSlots: intent.weeklyExerciseTarget,
            directSetTarget: intent.weeklyDirectSetTarget,
            weightedStimulusTarget: intent.weeklyStimulusTarget,
            maxPerSessionDirectSets: evenlyDistributedCap,
            maxFocusSessionDirectSets: min(intent.weeklyDirectSetTarget, focusSessionCap),
            preferredStyles: intent.preferredStyles,
            preferredMovementPatterns: intent.preferredMovementPatterns,
            volumeBias: intent.volumeBias,
            directWorkBias: intent.directWorkBias
        )
    }

    func buildBlueprintDayPlans(
        trainingDays: Int,
        priorityAllocations: [BlueprintPriorityAllocation],
        weekNumber: Int,
        calibration: ProgramCalibrationProfile
    ) -> [BlueprintDayPlan] {
        let restPattern = defaultRestPattern(for: trainingDays, weekNumber: weekNumber)
        let styles = orderedBlueprintStyles(for: priorityAllocations, trainingDays: trainingDays)
        var styleIndex = 0
        var usageCounts: [String: Int] = [:]
        var plans: [BlueprintDayPlan] = []

        for dayIndex in 1...7 {
            if restPattern[dayIndex - 1] {
                plans.append(
                    BlueprintDayPlan(
                        dayIndex: dayIndex,
                        style: "Recovery",
                        focusArea: nil,
                        supportAreas: [],
                        targetFatigueCap: 0,
                        targetSessionMinutes: 0,
                        targetPrioritySlots: 0,
                        emphasisPatterns: [],
                        isRestDay: true
                    )
                )
                continue
            }

            let style = styles[styleIndex % styles.count]
            styleIndex += 1
            let focus = blueprintFocusAllocation(for: style, allocations: priorityAllocations, usageCounts: usageCounts)
            if let focus {
                usageCounts[focus.area, default: 0] += 1
            }
            let supportAreas = companionSupportAreas(
                for: style,
                focus: focus,
                allocations: priorityAllocations,
                usageCounts: usageCounts,
                weeklyStyles: styles
            )

            plans.append(
                BlueprintDayPlan(
                    dayIndex: dayIndex,
                    style: style,
                    focusArea: focus?.area,
                    supportAreas: supportAreas,
                    targetFatigueCap: evidenceProfile.sessionFatigueCapsByStyle[style.lowercased()] ?? 18,
                    targetSessionMinutes: sessionTimeCapMinutes(for: style, calibration: calibration),
                    targetPrioritySlots: focus.map(prioritySlotsPerSession(for:)) ?? 1,
                    emphasisPatterns: Array((focus?.preferredMovementPatterns ?? []).prefix(3)),
                    isRestDay: false
                )
            )
        }

        return plans
    }

    func defaultRestPattern(for trainingDays: Int, weekNumber: Int) -> [Bool] {
        switch trainingDays {
        case 4:
            return [false, false, true, false, true, false, true]
        case 6:
            return weekNumber == 4
                ? [false, false, false, true, false, false, true]
                : [false, false, false, true, false, false, false]
        default:
            return weekNumber == 4
                ? [false, false, true, false, false, true, false]
                : [false, false, true, false, false, false, true]
        }
    }

    func orderedBlueprintStyles(for allocations: [BlueprintPriorityAllocation], trainingDays: Int) -> [String] {
        let template = defaultStyleTemplate(for: trainingDays)
        let demandByStyle = Dictionary(
            uniqueKeysWithValues: evidenceProfile.allowedStyles.map { style in
                (style, styleDemandScore(for: style, allocations: allocations))
            }
        )

        var selected = rankedStyles(
            from: evidenceProfile.allowedStyles,
            demandByStyle: demandByStyle,
            template: template
        )

        if trainingDays < selected.count {
            selected = Array(selected.prefix(trainingDays))
        }

        ensureStylePresence(
            "Lower",
            in: &selected,
            trainingDays: trainingDays,
            demandByStyle: demandByStyle,
            template: template
        )

        if trainingDays >= 5 {
            let armDemand = demandByStyle["Arms", default: 0]
            let legsDemand = demandByStyle["Legs", default: 0] + demandByStyle["Lower", default: 0]
            if armDemand <= legsDemand && !selected.contains("Legs") {
                replaceLowestDemandStyle(
                    in: &selected,
                    with: "Legs",
                    preserving: ["Lower", "Push", "Pull"],
                    demandByStyle: demandByStyle,
                    template: template
                )
            } else if armDemand > legsDemand && !selected.contains("Arms") {
                replaceLowestDemandStyle(
                    in: &selected,
                    with: "Arms",
                    preserving: ["Lower", "Push", "Pull"],
                    demandByStyle: demandByStyle,
                    template: template
                )
            }
        }

        return arrangeStyleSequence(
            selected,
            demandByStyle: demandByStyle,
            template: template
        )
    }

    func defaultStyleTemplate(for trainingDays: Int) -> [String] {
        switch trainingDays {
        case 4:
            return ["Push", "Lower", "Pull", "Upper"]
        case 6:
            return ["Push", "Lower", "Pull", "Upper", "Legs", "Arms"]
        default:
            return ["Push", "Lower", "Pull", "Upper", "Legs", "Arms"]
        }
    }

    func styleDemandScore(for style: String, allocations: [BlueprintPriorityAllocation]) -> Int {
        allocations.reduce(0) { partialResult, allocation in
            guard allocation.preferredStyles.contains(style) else { return partialResult }
            let frequencyScore = allocation.targetFrequency
            let slotScore = allocation.targetExerciseSlots
            let specialtyBonus = specialtyDemandBonus(for: style, area: allocation.area)
            return partialResult + frequencyScore + slotScore + specialtyBonus
        }
    }

    func specialtyDemandBonus(for style: String, area: String) -> Int {
        switch style {
        case "Arms":
            return isArmPriorityArea(area) ? 2 : 0
        case "Legs", "Lower":
            return isLowerBodyPriorityArea(area) ? 1 : 0
        case "Push":
            return isPushPriorityArea(area) ? 1 : 0
        case "Pull":
            return isPullPriorityArea(area) ? 1 : 0
        default:
            return 0
        }
    }

    func isArmPriorityArea(_ area: String) -> Bool {
        let normalized = normalizedPriorityText(area)
        return normalized.contains("arm")
            || normalized.contains("bicep")
            || normalized.contains("tricep")
            || normalized.contains("brachialis")
            || normalized.contains("forearm")
    }

    func isLowerBodyPriorityArea(_ area: String) -> Bool {
        let normalized = normalizedPriorityText(area)
        return normalized.contains("quad")
            || normalized.contains("hamstring")
            || normalized.contains("glute")
            || normalized.contains("calf")
    }

    func isPushPriorityArea(_ area: String) -> Bool {
        let normalized = normalizedPriorityText(area)
        return containsPriorityPhrase(
            in: normalized,
            keywords: ["chest", "upper chest", "tricep", "anterior delt", "lateral delt", "shoulders"]
        )
    }

    func isPullPriorityArea(_ area: String) -> Bool {
        let normalized = normalizedPriorityText(area)
        return containsPriorityPhrase(
            in: normalized,
            keywords: ["lats", "lat width", "back", "rear delt", "posterior delt", "bicep", "upper back", "mid back"]
        )
    }

    func rankedStyles(
        from styles: [String],
        demandByStyle: [String: Int],
        template: [String]
    ) -> [String] {
        styles.sorted { lhs, rhs in
            let lhsDemand = demandByStyle[lhs, default: 0]
            let rhsDemand = demandByStyle[rhs, default: 0]
            if lhsDemand != rhsDemand { return lhsDemand > rhsDemand }
            return templateIndex(for: lhs, within: template) < templateIndex(for: rhs, within: template)
        }
    }

    func ensureStylePresence(
        _ style: String,
        in selected: inout [String],
        trainingDays: Int,
        demandByStyle: [String: Int],
        template: [String]
    ) {
        guard trainingDays >= 4 else { return }
        if selected.contains(style) { return }

        if selected.count < trainingDays {
            selected.append(style)
            return
        }

        replaceLowestDemandStyle(
            in: &selected,
            with: style,
            preserving: ["Push", "Pull"],
            demandByStyle: demandByStyle,
            template: template
        )
    }

    func replaceLowestDemandStyle(
        in selected: inout [String],
        with style: String,
        preserving preservedStyles: Set<String>,
        demandByStyle: [String: Int],
        template: [String]
    ) {
        guard !selected.contains(style) else { return }

        let replacementIndex = selected.enumerated()
            .filter { !preservedStyles.contains($0.element) }
            .min { lhs, rhs in
                let lhsDemand = demandByStyle[lhs.element, default: 0]
                let rhsDemand = demandByStyle[rhs.element, default: 0]
                if lhsDemand != rhsDemand { return lhsDemand < rhsDemand }
                return templateIndex(for: lhs.element, within: template) > templateIndex(for: rhs.element, within: template)
            }?.offset

        if let replacementIndex {
            selected[replacementIndex] = style
        }
    }

    func arrangeStyleSequence(
        _ styles: [String],
        demandByStyle: [String: Int],
        template: [String]
    ) -> [String] {
        var remaining = styles
        var arranged: [String] = []

        while !remaining.isEmpty {
            let nextIndex = remaining.enumerated().max { lhs, rhs in
                sequenceScore(
                    for: lhs.element,
                    after: arranged.last,
                    remaining: remaining,
                    demandByStyle: demandByStyle,
                    template: template
                ) < sequenceScore(
                    for: rhs.element,
                    after: arranged.last,
                    remaining: remaining,
                    demandByStyle: demandByStyle,
                    template: template
                )
            }?.offset ?? 0

            arranged.append(remaining.remove(at: nextIndex))
        }

        return arranged
    }

    func sequenceScore(
        for style: String,
        after previousStyle: String?,
        remaining: [String],
        demandByStyle: [String: Int],
        template: [String]
    ) -> Int {
        var score = demandByStyle[style, default: 0] * 10
        score -= templateIndex(for: style, within: template)

        guard let previousStyle else { return score }

        let hasNonShoulderOption = remaining.contains { candidate in
            candidate != style && !isShoulderIntensiveStyle(candidate)
        }
        let hasNonLowerOption = remaining.contains { candidate in
            candidate != style && !isLowerBodyStyle(candidate)
        }

        if isShoulderIntensiveStyle(previousStyle) && isShoulderIntensiveStyle(style) && hasNonShoulderOption {
            score -= 100
        }

        if isLowerBodyStyle(previousStyle) && isLowerBodyStyle(style) && hasNonLowerOption {
            score -= 40
        }

        if previousStyle == style {
            score -= 60
        }

        return score
    }

    func templateIndex(for style: String, within template: [String]) -> Int {
        template.firstIndex(of: style) ?? template.count
    }

    func isShoulderIntensiveStyle(_ style: String) -> Bool {
        switch style {
        case "Push", "Upper", "Arms":
            return true
        default:
            return false
        }
    }

    func isLowerBodyStyle(_ style: String) -> Bool {
        style == "Lower" || style == "Legs"
    }

    func blueprintFocusAllocation(
        for style: String,
        allocations: [BlueprintPriorityAllocation],
        usageCounts: [String: Int]
    ) -> BlueprintPriorityAllocation? {
        allocations
            .filter { allocation in
                allocation.preferredStyles.contains(style)
                    && usageCounts[allocation.area, default: 0] < allocation.targetFrequency
            }
            .sorted { lhs, rhs in
                let lhsUsage = usageCounts[lhs.area, default: 0]
                let rhsUsage = usageCounts[rhs.area, default: 0]
                if lhsUsage != rhsUsage { return lhsUsage < rhsUsage }
                if lhs.targetFrequency != rhs.targetFrequency { return lhs.targetFrequency > rhs.targetFrequency }
                return lhs.directSetTarget > rhs.directSetTarget
            }
            .first
    }

    func prioritySlotsPerSession(for allocation: BlueprintPriorityAllocation) -> Int {
        let rawSlots = Double(allocation.targetExerciseSlots) / Double(max(1, allocation.targetFrequency))
        return max(1, min(3, Int(ceil(rawSlots))))
    }

    func companionSupportAreas(
        for style: String,
        focus: BlueprintPriorityAllocation?,
        allocations: [BlueprintPriorityAllocation],
        usageCounts: [String: Int],
        weeklyStyles: [String]
    ) -> [String] {
        let supportLimit = maximumCompanionSupportAreas(for: style, focus: focus)

        return allocations
            .filter { allocation in
                allocation.preferredStyles.contains(style)
                    && allocation.area != focus?.area
                    && usageCounts[allocation.area, default: 0] < allocation.targetFrequency
            }
            .sorted { lhs, rhs in
                supportNeedScore(
                    for: lhs,
                    usageCounts: usageCounts,
                    weeklyStyles: weeklyStyles
                ) > supportNeedScore(
                    for: rhs,
                    usageCounts: usageCounts,
                    weeklyStyles: weeklyStyles
                )
            }
            .prefix(supportLimit)
            .map(\.area)
    }

    func maximumCompanionSupportAreas(
        for style: String,
        focus: BlueprintPriorityAllocation?
    ) -> Int {
        switch canonicalTrainingStyle(style) {
        case "Upper":
            return focus == nil ? 1 : 2
        default:
            return 1
        }
    }

    func supportNeedScore(
        for allocation: BlueprintPriorityAllocation,
        usageCounts: [String: Int],
        weeklyStyles: [String]
    ) -> Int {
        let remainingFrequency = max(0, allocation.targetFrequency - usageCounts[allocation.area, default: 0])
        let compatibleStyleCount = max(1, weeklyStyles.filter { allocation.preferredStyles.contains($0) }.count)
        let scarcityBonus = remainingFrequency >= compatibleStyleCount ? 12 : compatibleStyleCount <= 2 ? 6 : 0
        return (remainingFrequency * 100) + (scarcityBonus * 10) + Int(ceil(allocation.directSetTarget))
    }

    func prioritizedFocusAreas(from focusAreas: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for area in focusAreas {
            let trimmed = area.trimmedOr(default: "")
            guard !trimmed.isEmpty else { continue }

            let canonicalArea = canonicalPriorityAreaName(trimmed)
            let key = normalizedPriorityText(canonicalArea)
            guard !seen.contains(key) else { continue }

            seen.insert(key)
            result.append(canonicalArea)
        }

        return Array(result.prefix(3))
    }

    func mergedPriorityIntents(_ priorities: [MusclePriorityIntent]) -> [MusclePriorityIntent] {
        var mergedByArea: [String: MusclePriorityIntent] = [:]
        var orderedAreas: [String] = []

        for priority in priorities {
            let canonicalArea = canonicalPriorityAreaName(priority.area)
            let key = normalizedPriorityText(canonicalArea)
            let normalizedPriority = priorityIntent(priority, area: canonicalArea, rank: priority.rank)

            guard let existing = mergedByArea[key] else {
                mergedByArea[key] = normalizedPriority
                orderedAreas.append(key)
                continue
            }

            mergedByArea[key] = mergePriorityIntent(existing, normalizedPriority)
        }

        return orderedAreas
            .compactMap { mergedByArea[$0] }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.weeklyDirectSetTarget > rhs.weeklyDirectSetTarget
            }
            .enumerated()
            .map { index, intent in
                priorityIntent(intent, area: intent.area, rank: index)
            }
    }

    func mergePriorityIntent(_ lhs: MusclePriorityIntent, _ rhs: MusclePriorityIntent) -> MusclePriorityIntent {
        let dominant: MusclePriorityIntent
        let secondary: MusclePriorityIntent
        let lhsDominates: Bool

        if priorityScore(for: lhs.priorityLevel) != priorityScore(for: rhs.priorityLevel) {
            lhsDominates = priorityScore(for: lhs.priorityLevel) > priorityScore(for: rhs.priorityLevel)
        } else if lhs.weeklyDirectSetTarget != rhs.weeklyDirectSetTarget {
            lhsDominates = lhs.weeklyDirectSetTarget > rhs.weeklyDirectSetTarget
        } else {
            lhsDominates = lhs.rank <= rhs.rank
        }

        dominant = lhsDominates ? lhs : rhs
        secondary = lhsDominates ? rhs : lhs

        return MusclePriorityIntent(
            area: canonicalPriorityAreaName(dominant.area),
            priorityLevel: priorityScore(for: lhs.priorityLevel) >= priorityScore(for: rhs.priorityLevel) ? lhs.priorityLevel : rhs.priorityLevel,
            rank: min(lhs.rank, rhs.rank),
            rationale: mergedPriorityRationale(lhs.rationale, rhs.rationale),
            weeklyDayTarget: max(lhs.weeklyDayTarget, rhs.weeklyDayTarget),
            weeklyExerciseTarget: max(lhs.weeklyExerciseTarget, rhs.weeklyExerciseTarget),
            weeklyDirectSetTarget: max(lhs.weeklyDirectSetTarget, rhs.weeklyDirectSetTarget),
            weeklyStimulusTarget: max(lhs.weeklyStimulusTarget, rhs.weeklyStimulusTarget),
            preferredStyles: mergedUniqueStrings(dominant.preferredStyles + secondary.preferredStyles, canonicalizer: { canonicalTrainingStyle($0) }),
            preferredMovementPatterns: mergedUniqueStrings(dominant.preferredMovementPatterns + secondary.preferredMovementPatterns, canonicalizer: { normalizedPriorityText($0) }),
            coverageKeywords: mergedUniqueStrings(dominant.coverageKeywords + secondary.coverageKeywords, canonicalizer: { normalizedPriorityText($0) }),
            accessoryCatalog: mergedAccessoryCatalogs(dominant.accessoryCatalog, secondary.accessoryCatalog),
            volumeBias: dominant.volumeBias,
            directWorkBias: dominant.directWorkBias
        )
    }

    func mergedPriorityRationale(_ lhs: String, _ rhs: String) -> String {
        let parts = mergedUniqueStrings([lhs, rhs], canonicalizer: { normalizedPriorityText($0) })
        return parts.joined(separator: " ")
    }

    func mergedUniqueStrings(
        _ values: [String],
        canonicalizer: (String) -> String
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmedOr(default: "")
            guard !trimmed.isEmpty else { continue }

            let key = canonicalizer(trimmed)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }

        return result
    }

    func mergedAccessoryCatalogs(
        _ lhs: [(name: String, target: String)],
        _ rhs: [(name: String, target: String)]
    ) -> [(name: String, target: String)] {
        var seen = Set<String>()
        var result: [(name: String, target: String)] = []

        for entry in lhs + rhs {
            let name = entry.name.trimmedOr(default: "")
            let target = entry.target.trimmedOr(default: "")
            guard !name.isEmpty, !target.isEmpty else { continue }

            let canonicalTarget = canonicalPriorityAreaName(target)
            let key = "\(normalizeExerciseName(name))|\(normalizedPriorityText(canonicalTarget))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append((name: name, target: canonicalTarget))
        }

        return result
    }

    func priorityIntent(_ intent: MusclePriorityIntent, area: String, rank: Int) -> MusclePriorityIntent {
        MusclePriorityIntent(
            area: area,
            priorityLevel: intent.priorityLevel,
            rank: rank,
            rationale: intent.rationale,
            weeklyDayTarget: intent.weeklyDayTarget,
            weeklyExerciseTarget: intent.weeklyExerciseTarget,
            weeklyDirectSetTarget: intent.weeklyDirectSetTarget,
            weeklyStimulusTarget: intent.weeklyStimulusTarget,
            preferredStyles: intent.preferredStyles,
            preferredMovementPatterns: intent.preferredMovementPatterns,
            coverageKeywords: intent.coverageKeywords,
            accessoryCatalog: intent.accessoryCatalog,
            volumeBias: intent.volumeBias,
            directWorkBias: intent.directWorkBias
        )
    }

    func proceduralPreviousExercisesByStyle(
        from previousWeekDays: [WorkoutDayResponse]?
    ) -> [String: [[WorkoutExerciseResponse]]] {
        guard let previousWeekDays else { return [:] }

        return Dictionary(grouping: previousWeekDays.filter { !$0.isRestDay }, by: { day in
            canonicalTrainingStyle(inferredDayStyle(dayName: day.dayName, muscleGroups: day.muscleGroups) ?? "Unknown")
        }).mapValues { groupedDays in
            groupedDays
                .sorted { $0.dayNumber < $1.dayNumber }
                .map(\.exercises)
        }
    }

    func groupedTrainingDaysByStyle(_ days: [WorkoutDayResponse]) -> [String: [WorkoutDayResponse]] {
        Dictionary(grouping: days.filter { !$0.isRestDay }, by: { day in
            canonicalTrainingStyle(inferredDayStyle(dayName: day.dayName, muscleGroups: day.muscleGroups) ?? "Unknown")
        }).mapValues { groupedDays in
            groupedDays.sorted { $0.dayNumber < $1.dayNumber }
        }
    }

    func neutralCalibrationProfile() -> ProgramCalibrationProfile {
        ProgramCalibrationProfile(
            lowPerformanceDataQuality: false,
            poorNutritionAdherence: false,
            recoveryConstrained: false,
            recompositionGoal: false,
            readinessMode: .normal,
            weeklyVolumeScale: 1.0,
            reduceExerciseSlotComplexity: false,
            defaultSessionTimeCapMinutes: 75,
            sessionTimeCapsByStyle: [
                "Push": 75,
                "Pull": 75,
                "Upper": 75,
                "Lower": 75,
                "Legs": 75,
                "Arms": 60
            ],
            programmingNotes: []
        )
    }

    func calibrationProfile(from analysis: BodyAnalysisResult) -> ProgramCalibrationProfile {
        let profile = analysis.inputContext?.profile
        let checkIn = analysis.inputContext?.checkIn
        let progress = analysis.inputContext?.progress

        let goalText = normalizedPriorityText([
            profile?.primaryGoal ?? "",
            analysis.overallAssessment,
            analysis.trainingAssessment,
            analysis.nutritionAssessment
        ].joined(separator: " "))

        let recompositionGoal = containsAny(
            goalText,
            keywords: ["recomp", "recomposition", "fat loss", "deficit", "cut", "visible abs"]
        )

        let nutritionText = normalizedPriorityText([
            progress?.nutritionAdherence ?? "",
            analysis.adherenceAssessment,
            analysis.psychologicalInsights,
            analysis.nutritionAssessment
        ].joined(separator: " "))
        let nutritionCoverage = loggedCoverageRatio(from: progress?.nutritionAdherence ?? "")
        let proteinCoverage = proteinTargetHitRatio(from: progress?.nutritionAdherence ?? "")
        let poorNutritionAdherence =
            containsAny(
                nutritionText,
                keywords: [
                    "no nutrition logs were recorded",
                    "nutrition adherence could not be evaluated",
                    "minimal nutrition logging",
                    "poor nutrition adherence",
                    "inconsistent logging"
                ]
            )
            || nutritionCoverage.map { $0 < 0.5 } == true
            || proteinCoverage.map { $0 < 0.5 } == true

        let performanceText = normalizedPriorityText([
            progress?.performanceSignals ?? "",
            progress?.dataQualityNotes ?? "",
            analysis.analysisLimitations
        ].joined(separator: " "))
        let lowPerformanceDataQuality = containsAny(
            performanceText,
            keywords: [
                "no append only performance events were logged",
                "no append-only performance events were logged",
                "performance context is limited",
                "no exercise strength summaries are stored",
                "falls back to latest best movement summaries",
                "fewer than two weight logs"
            ]
        )

        let recoveryText = normalizedPriorityText([
            profile?.averageSleep ?? "",
            profile?.lifestyleConstraints ?? "",
            checkIn?.recoverySleep ?? "",
            checkIn?.stressSchedule ?? "",
            analysis.metabolicHealthNotes,
            analysis.recoveryRiskAssessment
        ].joined(separator: " "))
        let recoveryHours = representativeSleepHours(from: recoveryText)
        let recoveryConstrained =
            containsAny(
                recoveryText,
                keywords: [
                    "shift work",
                    "shift-work",
                    "variable sleep",
                    "poor sleep",
                    "long clinical shifts",
                    "stressful shifts",
                    "high stress"
                ]
            )
            || recoveryHours.map { $0 < 7.0 } == true

        let readinessMode = WorkoutReadinessMode(
            rawValue: UserDefaults.standard.string(forKey: "workout_readiness_mode") ?? "normal"
        ) ?? .normal

        var weeklyVolumeScale = 1.0
        if lowPerformanceDataQuality {
            weeklyVolumeScale *= 0.92
        }
        if poorNutritionAdherence && recompositionGoal {
            weeklyVolumeScale *= 0.90
        }
        if recoveryConstrained {
            weeklyVolumeScale *= 0.95
        }
        if readinessMode != .normal {
            weeklyVolumeScale *= readinessMode.volumeScale
        }
        weeklyVolumeScale = max(0.70, min(1.0, weeklyVolumeScale))

        let reduceExerciseSlotComplexity = lowPerformanceDataQuality
            || (poorNutritionAdherence && recompositionGoal)
            || readinessMode == .postCall
        let baseTimeCap = recoveryConstrained ? 70 : 75
        let defaultSessionTimeCapMinutes = min(baseTimeCap, readinessMode.sessionTimeCap)
        let styleSessionCaps: [String: Int] = [
            "Push": defaultSessionTimeCapMinutes,
            "Pull": defaultSessionTimeCapMinutes,
            "Upper": defaultSessionTimeCapMinutes,
            "Lower": min(recoveryConstrained ? 70 : 75, readinessMode.sessionTimeCap),
            "Legs": min(recoveryConstrained ? 70 : 75, readinessMode.sessionTimeCap),
            "Arms": min(recoveryConstrained ? 55 : 60, readinessMode.sessionTimeCap)
        ]

        var notes: [String] = []
        if lowPerformanceDataQuality {
            notes.append("Recent performance-data quality is limited, so keep exercise selection stable and progression conservative until more high-quality logs exist.")
        }
        if poorNutritionAdherence && recompositionGoal {
            notes.append("Nutrition adherence is the bottleneck right now, so keep specialization volume near the recoverable lower-mid range instead of chasing extra fatigue.")
        }
        if recoveryConstrained {
            notes.append("Session design should stay tight for shift-work recovery: trim filler first, keep compounds honest, and protect the weekly time budget.")
        }
        let readinessGuidance = readinessMode.programmingGuidance
        if !readinessGuidance.isEmpty {
            notes.append(readinessGuidance)
        }

        return ProgramCalibrationProfile(
            lowPerformanceDataQuality: lowPerformanceDataQuality,
            poorNutritionAdherence: poorNutritionAdherence,
            recoveryConstrained: recoveryConstrained,
            recompositionGoal: recompositionGoal,
            readinessMode: readinessMode,
            weeklyVolumeScale: weeklyVolumeScale,
            reduceExerciseSlotComplexity: reduceExerciseSlotComplexity,
            defaultSessionTimeCapMinutes: defaultSessionTimeCapMinutes,
            sessionTimeCapsByStyle: styleSessionCaps,
            programmingNotes: notes
        )
    }

    func calibratedTrainingIntentPlan(
        _ plan: TrainingIntentPlan,
        using calibration: ProgramCalibrationProfile
    ) -> TrainingIntentPlan {
        let adjustedPriorities = plan.priorities.map { intent in
            adjustedPriorityIntent(intent, using: calibration)
        }
        let adjustedNotes = (plan.programmingNotes + calibration.programmingNotes).uniquePreservingOrder()

        return TrainingIntentPlan(
            splitRecommendation: plan.splitRecommendation,
            weeklyTrainingDays: plan.weeklyTrainingDays,
            programmingNotes: adjustedNotes,
            priorities: adjustedPriorities,
            topLeverageChange: plan.topLeverageChange,
            posturalFocus: plan.posturalFocus,
            injuryRiskFocus: plan.injuryRiskFocus,
            calibration: calibration
        )
    }

    func adjustedPriorityIntent(
        _ intent: MusclePriorityIntent,
        using calibration: ProgramCalibrationProfile
    ) -> MusclePriorityIntent {
        let normalizedLevel = normalizedPriorityLevel(intent.priorityLevel, rank: intent.rank)
        let minimumWeeklyDirectTarget = normalizedLevel == "High" ? 6.0 : normalizedLevel == "Medium" ? 4.0 : 3.0
        let scaledDirectSets = roundedStimulusValue(
            max(minimumWeeklyDirectTarget, intent.weeklyDirectSetTarget * calibration.weeklyVolumeScale)
        )
        let scaledStimulus = roundedStimulusValue(
            max(scaledDirectSets + 1.0, intent.weeklyStimulusTarget * calibration.weeklyVolumeScale)
        )

        var adjustedExerciseTarget = intent.weeklyExerciseTarget
        if calibration.reduceExerciseSlotComplexity && adjustedExerciseTarget > 2 {
            adjustedExerciseTarget -= 1
        }
        if calibration.recoveryConstrained && normalizedLevel != "High" && adjustedExerciseTarget > 1 {
            adjustedExerciseTarget -= 1
        }

        return MusclePriorityIntent(
            area: intent.area,
            priorityLevel: intent.priorityLevel,
            rank: intent.rank,
            rationale: intent.rationale,
            weeklyDayTarget: intent.weeklyDayTarget,
            weeklyExerciseTarget: max(1, min(5, adjustedExerciseTarget)),
            weeklyDirectSetTarget: scaledDirectSets,
            weeklyStimulusTarget: scaledStimulus,
            preferredStyles: intent.preferredStyles,
            preferredMovementPatterns: intent.preferredMovementPatterns,
            coverageKeywords: intent.coverageKeywords,
            accessoryCatalog: intent.accessoryCatalog,
            volumeBias: intent.volumeBias,
            directWorkBias: intent.directWorkBias
        )
    }

    func sessionTimeCapMinutes(for style: String, calibration: ProgramCalibrationProfile) -> Int {
        calibration.sessionTimeCapsByStyle[canonicalTrainingStyle(style)] ?? calibration.defaultSessionTimeCapMinutes
    }

    func roundedStimulusValue(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    func loggedCoverageRatio(from summary: String) -> Double? {
        let pattern = #"logged on (\d+) of (\d+) day(?:s|\(s\))?"#
        guard let match = firstRegexMatch(pattern: pattern, in: summary),
              match.count == 3,
              let numerator = Double(match[1]),
              let denominator = Double(match[2]),
              denominator > 0 else {
            return nil
        }
        return numerator / denominator
    }

    func proteinTargetHitRatio(from summary: String) -> Double? {
        let pattern = #"protein hit at least 90% of target on (\d+)\/(\d+) logged day(?:s|\(s\))?"#
        guard let match = firstRegexMatch(pattern: pattern, in: summary),
              match.count == 3,
              let numerator = Double(match[1]),
              let denominator = Double(match[2]),
              denominator > 0 else {
            return nil
        }
        return numerator / denominator
    }

    func representativeSleepHours(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)\s*hour"#
        if let match = firstRegexMatch(pattern: pattern, in: text),
           match.count == 3,
           let lower = Double(match[1]),
           let upper = Double(match[2]) {
            return (lower + upper) / 2
        }

        let simplePattern = #"(\d+(?:\.\d+)?)\s*hour"#
        if let match = firstRegexMatch(pattern: simplePattern, in: text),
           match.count == 2,
           let hours = Double(match[1]) {
            return hours
        }

        return nil
    }

    func firstRegexMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }
}

private extension Array where Element == String {
    func uniquePreservingOrder() -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in self {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }
}
