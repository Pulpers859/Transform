import Foundation

extension ClaudeService {
    /// `unfinishedMovementCount` is how many DISTINCT movements the lifter has repeatedly failed
    /// to finish for time (`ExerciseHistoryContext.timeSkipExercises`). It reaches the session
    /// time cap through `calibrationProfile`; see the cap derivation there for why.
    ///
    /// Defaulted so the Generator Lab's debug paths, which have no logged history to draw on,
    /// behave exactly as before rather than silently inheriting someone else's.
    func trainingIntentPlan(
        from analysis: BodyAnalysisResult,
        unfinishedMovementCount: Int = 0
    ) -> TrainingIntentPlan {
        if let structuredIntent = analysis.structuredTrainingIntent,
           !structuredIntent.priorities.isEmpty {
            return trainingIntentPlan(
                from: structuredIntent,
                analysis: analysis,
                unfinishedMovementCount: unfinishedMovementCount
            )
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
        return calibratedTrainingIntentPlan(
            basePlan,
            using: calibrationProfile(from: analysis, unfinishedMovementCount: unfinishedMovementCount)
        )
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

    func trainingIntentPlan(
        from structuredIntent: StructuredTrainingIntent,
        analysis: BodyAnalysisResult,
        unfinishedMovementCount: Int = 0
    ) -> TrainingIntentPlan {
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
        return calibratedTrainingIntentPlan(
            basePlan,
            using: calibrationProfile(from: analysis, unfinishedMovementCount: unfinishedMovementCount)
        )
    }

    /// Renders the Training Intent block, reconciled against the Blueprint's per-priority
    /// allocations so the two printed blocks never disagree in silence.
    ///
    /// `blueprintAllocation(for:)` copies `targetFrequency`, `directSetTarget` and
    /// `weightedStimulusTarget` verbatim off the (already fully calibrated)
    /// `MusclePriorityIntent` before a single day exists. The ONLY step between that copy and
    /// this render that can change those three numbers is `styleFeasibleAllocations`, which
    /// clamps `targetFrequency` down to the count of days the chosen split can actually offer
    /// that priority's preferred styles, and — only when frequency was clamped — may also recut
    /// the direct-set and weighted-stimulus targets to what the surviving sessions can hold. So
    /// any disagreement this function finds between the intent's asked-for numbers and the
    /// blueprint's delivered numbers is guaranteed (by that call chain, verified by inspection at
    /// the time this was written) to be a style-feasibility clamp, never a recovery-modulation
    /// trim — recovery modulation runs earlier, inside `adjustedPriorityIntent`, and is already
    /// baked equally into both sides before `blueprintAllocation` ever copies the number. If a
    /// future change adds another step that can rewrite `BlueprintPriorityAllocation` after
    /// `programBlueprint` builds it, this attribution needs re-checking.
    ///
    /// This keeps the intent's asked-for number (so the record of what was requested survives
    /// calibration, per the doc comment on `styleFeasibleAllocations`) and adds what the week
    /// will actually deliver, in-line, only where the two disagree — the common path where they
    /// agree is unchanged.
    func trainingIntentContext(from trainingIntent: TrainingIntentPlan, blueprint: ProgramBlueprint) -> String {
        guard !trainingIntent.priorities.isEmpty else {
            return "Structured training intent: no priority muscles were available, so use balanced hypertrophy programming."
        }

        var allocationsByArea: [String: BlueprintPriorityAllocation] = [:]
        for allocation in blueprint.priorityAllocations {
            let key = normalizedPriorityText(canonicalPriorityAreaName(allocation.area))
            allocationsByArea[key] = allocation
        }

        let lines = trainingIntent.priorities.map { intent in
            let movementPatterns = intent.preferredMovementPatterns.joined(separator: ", ")
            let allocationKey = normalizedPriorityText(canonicalPriorityAreaName(intent.area))
            let weeklyTargetsText = reconciledWeeklyTargetsText(
                intent: intent,
                allocation: allocationsByArea[allocationKey]
            )
            return """
            - rank \(intent.rank + 1): \(intent.area) [\(intent.priorityLevel)]
              rationale: \(intent.rationale)
              weekly_targets: \(weeklyTargetsText)
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

    /// The `weekly_targets:` payload for one priority line. Renders the intent's asked-for
    /// numbers unchanged when they match what the blueprint will actually deliver; when they
    /// disagree, appends "(trimmed to N by the chosen split)" onto whichever fields the
    /// style-feasibility clamp actually touched (see `trainingIntentContext` doc comment for why
    /// that clamp is the only possible cause). `allocation` is nil only if a priority in the
    /// intent has no matching blueprint allocation at all — that should not happen given
    /// `programBlueprint` derives its allocations from this same priority list, but if it ever
    /// does, this renders the asked-for numbers only rather than guessing a delivered number.
    func reconciledWeeklyTargetsText(
        intent: MusclePriorityIntent,
        allocation: BlueprintPriorityAllocation?
    ) -> String {
        let exerciseText = "\(intent.weeklyExerciseTarget) targeted exercises"

        guard let allocation else {
            return "\(intent.weeklyDayTarget) days, \(exerciseText), \(formatStimulusValue(intent.weeklyDirectSetTarget)) direct sets, \(formatStimulusValue(intent.weeklyStimulusTarget)) weighted stimulus"
        }

        let daysText = reconciledIntMetric(asked: intent.weeklyDayTarget, delivered: allocation.targetFrequency, unit: "days")
        let directSetsText = reconciledDoubleMetric(asked: intent.weeklyDirectSetTarget, delivered: allocation.directSetTarget, unit: "direct sets")
        let stimulusText = reconciledDoubleMetric(asked: intent.weeklyStimulusTarget, delivered: allocation.weightedStimulusTarget, unit: "weighted stimulus")

        return "\(daysText), \(exerciseText), \(directSetsText), \(stimulusText)"
    }

    func reconciledIntMetric(asked: Int, delivered: Int, unit: String) -> String {
        guard asked != delivered else {
            return "\(asked) \(unit)"
        }
        return "\(asked) \(unit) (trimmed to \(delivered) by the chosen split)"
    }

    func reconciledDoubleMetric(asked: Double, delivered: Double, unit: String) -> String {
        guard abs(asked - delivered) > 0.0001 else {
            return "\(formatStimulusValue(asked)) \(unit)"
        }
        return "\(formatStimulusValue(asked)) \(unit) (trimmed to \(formatStimulusValue(delivered)) by the chosen split)"
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
            priorityAllocations: styleFeasibleAllocations(allocations, dayPlans: dayPlans),
            dayPlans: dayPlans,
            topLeverageChange: trainingIntent.topLeverageChange,
            posturalFocus: trainingIntent.posturalFocus,
            injuryRiskFocus: trainingIntent.injuryRiskFocus,
            programmingNotes: trainingIntent.programmingNotes,
            calibration: trainingIntent.calibration
        )
    }

    /// Re-cuts each priority's weekly frequency to the number of sessions it can legally train in.
    ///
    /// `blueprintAllocation` fixes `targetFrequency` from the evidence bands before a single day
    /// exists, and `buildBlueprintDayPlans` then chooses the split. Nothing reconciled the two, so
    /// a plan could promise a priority three exposures on "Push, Upper, Arms" days while choosing
    /// a split — Upper / Legs / Push / Lower / Pull — containing only two such days. The promise
    /// was not merely unmet: `enforcePriorityDirectSetFeasibility` chased it, ran out of legal
    /// days, and appended the third exposure to the PULL day, against the plan's own style list.
    /// Printing an unreachable number also makes the Generator Lab lie about what was attempted.
    ///
    /// Frequency is cut; the weekly set target is only cut when the surviving sessions genuinely
    /// cannot hold it. A focus day may carry `maxFocusSessionDirectSets` and every other session
    /// `maxPerSessionDirectSets`, so two sessions usually still fund the whole weekly dose — the
    /// lifter loses a spread, not volume. Weighted stimulus is scaled by the same ratio as direct
    /// sets so the funding loop cannot keep buying sets against a target the direct cap forbids.
    ///
    /// This deliberately does NOT rebuild the day plans, and the cost of that is worth stating
    /// rather than leaving to be rediscovered.
    ///
    /// `buildBlueprintDayPlans` has already run on the UNCLAMPED allocations, so two things were
    /// decided using a frequency this function is about to withdraw: which priority owns a
    /// contested style day (`blueprintFocusAllocation` filters on `usageCounts[area] <
    /// targetFrequency` and breaks ties by frequency, descending), and each day's
    /// `targetPrioritySlots`. A priority whose promised frequency was never reachable can
    /// therefore still out-rank an achievable one for a day it did not deserve.
    ///
    /// The blast radius is bounded and known: the only finding this can produce is "was planned
    /// for N priority slots", which is correction-worthy rather than a hard failure, so the worst
    /// case is one extra paid correction call — never a discarded week. Rebuilding the plans from
    /// the clamped copy would cost far more than that: the split itself is chosen from allocation
    /// demand, so clamped frequencies could select different styles, which changes the compatible
    /// day count, which changes the clamp. That is a fixed-point search over split selection, and
    /// it is not worth entering to improve a tiebreak. Plans first, promises trimmed to fit them.
    func styleFeasibleAllocations(
        _ allocations: [BlueprintPriorityAllocation],
        dayPlans: [BlueprintDayPlan]
    ) -> [BlueprintPriorityAllocation] {
        let trainingStyles = dayPlans
            .filter { !$0.isRestDay }
            .map { canonicalTrainingStyle($0.style) }

        return allocations.map { allocation in
            // Both sides of this comparison must be canonical, and only one of them used to be.
            //
            // `canonicalTrainingStyle` folds "Legs" and "Lower" into the single style "Lower",
            // and `trainingStyles` above is already folded. `preferredStyles` is NOT: it comes
            // from `sanitizedPreferredStyles`, whose fallback is the raw catalogue list, and the
            // Core/Abs profile lists BOTH spellings (`["Legs", "Lower", "Upper"]`). Dedup there
            // keeps the first literal spelling per bucket, so the allocation carried "Legs" and
            // the day carried the canonical "Lower" — and `["Upper", "Legs"].contains("Lower")`
            // is false. Every lower-body day was therefore invisible to this count.
            //
            // Live cost on the owner's Week 1: Core/Abs genuinely had three compatible days
            // (Upper, Legs, Lower) against a target frequency of 2, so this guard should have
            // returned the allocation untouched. Instead it saw ONE compatible day, clamped the
            // priority to 1 exposure, and recut 6 direct sets to 5 (and 8.5 weighted stimulus to
            // 7.1). That missing set is exactly what left Day 5's Cable Crunch stranded at ONE
            // set: the floor pass could not lift it to the `.core` two-set floor because the
            // over-volume ceiling (5 * 1.15 = 5.73) was already spent by the three exposures the
            // clamped budget never expected to fund.
            let preferredCanonicalStyles = Set(allocation.preferredStyles.map { canonicalTrainingStyle($0) })
            let compatibleDays = trainingStyles.filter { preferredCanonicalStyles.contains($0) }.count
            // Zero compatible days means the style list is unusable as a constraint for this
            // split, not that the priority should stop training. Leave the allocation alone and
            // let the feasibility pass place the work off-style rather than clamping to zero.
            guard compatibleDays > 0, compatibleDays < allocation.targetFrequency else {
                return allocation
            }

            // Two prime slots per session is the same ceiling `enforcePriorityDirectSetFeasibility`
            // applies when it places them, so the printed plan matches what can be built.
            let feasibleSlots = min(allocation.targetExerciseSlots, compatibleDays * 2)

            func recut(directSetTarget: Double, weightedStimulusTarget: Double) -> BlueprintPriorityAllocation {
                BlueprintPriorityAllocation(
                    area: allocation.area,
                    priorityLevel: allocation.priorityLevel,
                    rationale: allocation.rationale,
                    targetFrequency: compatibleDays,
                    targetExerciseSlots: feasibleSlots,
                    directSetTarget: directSetTarget,
                    weightedStimulusTarget: weightedStimulusTarget,
                    maxPerSessionDirectSets: allocation.maxPerSessionDirectSets,
                    maxFocusSessionDirectSets: allocation.maxFocusSessionDirectSets,
                    preferredStyles: allocation.preferredStyles,
                    preferredMovementPatterns: allocation.preferredMovementPatterns,
                    volumeBias: allocation.volumeBias,
                    directWorkBias: allocation.directWorkBias
                )
            }

            // TWO independent ceilings, and the plan may only promise the lower of them.
            //
            // The session ceiling is how much direct work the surviving sessions may carry. The
            // SLOT ceiling is how much the surviving exercise slots may carry at the roughly
            // four-working-set-per-movement limit the allocator enforces, and leaving it out was
            // wrong: a priority trimmed to one session with two slots can hold 8 sets however
            // generous its focus-day cap reads, so a capacity of 10 would have printed a target
            // that forces a movement above four working sets — the exact shape
            // `minimumExerciseSlots` exists to prevent.
            //
            // `prioritySlotsPerSession` is called on the re-cut allocation rather than restated
            // here, so the trimmed plan and the planner's own slot arithmetic cannot disagree.
            let sessionCapacity = allocation.maxFocusSessionDirectSets
                + Double(compatibleDays - 1) * allocation.maxPerSessionDirectSets
            let slotCapacity = Double(
                prioritySlotsPerSession(
                    for: recut(
                        directSetTarget: allocation.directSetTarget,
                        weightedStimulusTarget: allocation.weightedStimulusTarget
                    )
                ) * compatibleDays
            ) * 4.0

            let feasibleDirectSets = min(allocation.directSetTarget, min(sessionCapacity, slotCapacity))
            let volumeRatio = allocation.directSetTarget > 0
                ? feasibleDirectSets / allocation.directSetTarget
                : 1.0

            return recut(
                directSetTarget: feasibleDirectSets,
                weightedStimulusTarget: allocation.weightedStimulusTarget * volumeRatio
            )
        }
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
            return MesocyclePhase.isDeloadWeek(weekNumber)
                ? [false, false, false, true, false, false, true]
                : [false, false, false, true, false, false, false]
        default:
            return MesocyclePhase.isDeloadWeek(weekNumber)
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

        ensurePullingDayPresence(
            in: &selected,
            trainingDays: trainingDays,
            allocations: allocations,
            demandByStyle: demandByStyle,
            template: template
        )

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

    /// Guarantees the week keeps a dedicated pulling day.
    ///
    /// `styleDemandScore` is computed purely from the priority allocations, so a lifter whose
    /// priorities are all pressing or core areas scores "Pull" at exactly zero. With six allowed
    /// styles and only four or five training days the ranked list is truncated, and the pulling
    /// day is the one that falls off. A real audited week came back with three back sets and zero
    /// rear-delt sets against eighteen chest sets — for a lifter whose own analysis asked for
    /// continued upper-back and rear-delt emphasis, and who reported anterior shoulder pain.
    ///
    /// Baseline coverage (BASE-001) cannot catch this. It is satisfied by a single directly
    /// targeting movement anywhere in the week, so one isolation lat slot clears "back", and it
    /// skips prioritized groups entirely, so a lateral-raise priority makes the whole shoulder
    /// bucket — rear delts included — invisible to it.
    ///
    /// The donor is chosen by feasibility, not by demand alone. Dropping the lowest-demand style
    /// is exactly what strands a priority: in the audited week that was "Legs", the only day
    /// besides "Upper" that Core/Abs could live on, and Core/Abs cannot reach six weekly sets from
    /// a single day at a focus cap of five. Any style whose removal would put a priority further
    /// from its weekly direct-set target is disqualified, and if nothing is left the guarantee
    /// backs off rather than trading one hole for another.
    ///
    /// This runs AFTER the `trainingDays >= 5` Legs/Arms block on purpose. Run before it, that
    /// block re-inserts Arms by evicting the lowest-demand style — which is exactly the Legs day
    /// Core/Abs needs — and undoes the feasibility check below. Running after, it may displace a
    /// style that block just placed; that is intended. The structural lower-body guarantee is
    /// `ensureStylePresence("Lower")`, and "Lower" is preserved here, so a lower-body day always
    /// survives. The Legs/Arms block only decides which style rounds out the week.
    func ensurePullingDayPresence(
        in selected: inout [String],
        trainingDays: Int,
        allocations: [BlueprintPriorityAllocation],
        demandByStyle: [String: Int],
        template: [String]
    ) {
        guard trainingDays >= 4 else { return }
        guard evidenceProfile.allowedStyles.contains("Pull") else { return }
        if selected.contains("Pull") { return }

        if selected.count < trainingDays {
            selected.append("Pull")
            return
        }

        // "Push" and "Lower" are structurally guaranteed elsewhere; trading either of them for a
        // pulling day would just move the hole.
        let preserved: Set<String> = ["Push", "Lower", "Pull"]
        let current = selected

        let donorIndex = current.enumerated()
            .filter { !preserved.contains($0.element) }
            .filter { candidate in
                var remaining = current
                remaining[candidate.offset] = "Pull"
                return allocations.allSatisfy { allocation in
                    let after = reachableWeeklyDirectSets(for: allocation, within: remaining)
                    if after >= allocation.directSetTarget { return true }
                    // A priority that is already squeezed must not be squeezed further.
                    return after >= reachableWeeklyDirectSets(for: allocation, within: current)
                }
            }
            .min { lhs, rhs in
                let lhsDemand = demandByStyle[lhs.element, default: 0]
                let rhsDemand = demandByStyle[rhs.element, default: 0]
                if lhsDemand != rhsDemand { return lhsDemand < rhsDemand }
                return templateIndex(for: lhs.element, within: template) > templateIndex(for: rhs.element, within: template)
            }?.offset

        if let donorIndex {
            selected[donorIndex] = "Pull"
        }
    }

    /// The most direct sets `allocation` could still receive if the week only offered `styles`.
    ///
    /// One compatible day can be the priority's focus day and carries the higher focus cap; any
    /// others carry the evenly distributed per-session cap. The day count is bounded by
    /// `targetFrequency` because the blueprint never plans more focus days than that, so counting
    /// every compatible style would overstate what the week can actually deliver.
    ///
    /// Deliberately per-allocation: two priorities that both prefer the same single style each
    /// count that style's focus cap as their own, so contention between them is not modelled and
    /// the number can read high. That is acceptable because this is a SCREEN for disqualifying a
    /// donor, not a scheduler — and because `enforcePriorityExposureCoverage` draws its candidate
    /// days from every training day, not only style-compatible ones, so a preferred style is a
    /// placement preference rather than a hard limit on where a priority's work can land.
    func reachableWeeklyDirectSets(
        for allocation: BlueprintPriorityAllocation,
        within styles: [String]
    ) -> Double {
        // Canonical on both sides, for the same reason as `styleFeasibleAllocations`: "Legs" and
        // "Lower" are one style, and comparing a raw preference list against day styles that may
        // be spelled either way made a Core/Abs priority preferring "Legs" read as having ZERO
        // reachable sets on a week containing a Lower day. This function is the screen that
        // decides whether swapping a style out would starve a priority, so a false zero there
        // silently lets split selection drop a day the priority actually needed.
        //
        // Canonicalizing does NOT collapse two days into one: `styles` carries one entry per
        // training day, so a week with both a "Legs" day and a "Lower" day still counts two.
        let preferredCanonicalStyles = Set(allocation.preferredStyles.map { canonicalTrainingStyle($0) })
        let compatibleCount = min(
            styles.filter { preferredCanonicalStyles.contains(canonicalTrainingStyle($0)) }.count,
            max(1, allocation.targetFrequency)
        )
        guard compatibleCount > 0 else { return 0 }
        return allocation.maxFocusSessionDirectSets
            + allocation.maxPerSessionDirectSets * Double(compatibleCount - 1)
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

    /// Per-focus-day slot count for one priority, applied to every focus day.
    ///
    /// Rounding DOWN was tried here and reverted. It looked right — the weekly exposures this
    /// implies are `result * targetFrequency`, and rounding up can exceed `targetExerciseSlots` —
    /// but it breaks the invariant `minimumExerciseSlots` exists to hold: a 10-set priority with
    /// `targetFrequency` 2 fell to ONE slot per day, two exposures, five working sets apiece,
    /// which is well past the ~4-set ceiling the slot math is built on.
    /// `ResidueMuscleDoseTests.testReducedExposuresCanStillCarryTheWeeklySetTarget` is what caught
    /// it, and it stays as the guard on any future attempt.
    ///
    /// A single per-session number genuinely cannot express three slots across two days. The
    /// correct shape is an uneven 2/1 split with the remainder distributed, which is a real change
    /// to how `dayPlans` are built, not a rounding tweak. Not attempted here.
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
            recoveryTier: .insufficientData,
            recoveryAudit: "neutral calibration (no analysis context)",
            recompositionGoal: false,
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

    /// Hard lower bound on a session budget, whatever the recovery tier and the unfinished-work
    /// trim combine to. Currently HEADROOM: the arithmetic above cannot reach it (see the note at
    /// the trim), and `UnfinishedSessionBudgetTests` pins that fact so it stays deliberate.
    static let absoluteSessionTimeFloorMinutes = 45

    /// `recoveryDecision` defaults to the stored structured sleep state; the harness
    /// injects decisions directly so parallel test processes never race the shared
    /// UserDefaults plist.
    func calibrationProfile(
        from analysis: BodyAnalysisResult,
        recoveryDecision: RecoveryDecision? = nil,
        unfinishedMovementCount: Int = 0
    ) -> ProgramCalibrationProfile {
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

        // Recovery modulation runs on the structured, dated sleep state (RecoveryState.swift,
        // EvidenceProfile.md SLEEP-001) — never on regex over the derived prose summary,
        // which previously never expired and could silently constrain generation forever.
        let structuredDecision = recoveryDecision ?? sleepRecoveryDecision()

        // Fallback: with no fresh sleep logs, standing profile prose (occupation, lifestyle,
        // check-in text) may still justify constrained-level caution — but never restricted,
        // which is reserved for measured acute restriction. The derived sleep summary string
        // is deliberately excluded from this text.
        let recoveryTier: RecoveryTier
        let recoveryAudit: String
        if structuredDecision.tier == .insufficientData {
            let fallbackText = normalizedPriorityText([
                profile?.averageSleep ?? "",
                profile?.lifestyleConstraints ?? "",
                checkIn?.recoverySleep ?? "",
                checkIn?.stressSchedule ?? "",
                analysis.metabolicHealthNotes,
                analysis.recoveryRiskAssessment
            ].joined(separator: " "))
            let fallbackHours = representativeSleepHours(from: fallbackText)
            let fallbackConstrained =
                containsAny(
                    fallbackText,
                    keywords: [
                        "shift work",
                        "shift-work",
                        "variable sleep",
                        "poor sleep",
                        "under 5 hours",
                        "post-call recovery",
                        "high variability",
                        "long clinical shifts",
                        "stressful shifts",
                        "high stress"
                    ]
                )
                || fallbackHours.map { $0 < 7.0 } == true
            if fallbackConstrained {
                recoveryTier = .constrained
                recoveryAudit = "profile/check-in context (no fresh sleep logs: \(structuredDecision.audit))"
            } else {
                recoveryTier = .insufficientData
                recoveryAudit = structuredDecision.audit
            }
        } else {
            recoveryTier = structuredDecision.tier
            recoveryAudit = structuredDecision.audit
        }
        let recoveryConstrained = recoveryTier == .constrained || recoveryTier == .restricted

        var weeklyVolumeScale = 1.0
        if lowPerformanceDataQuality {
            weeklyVolumeScale *= 0.92
        }
        if poorNutritionAdherence && recompositionGoal {
            weeklyVolumeScale *= 0.90
        }
        // Recovery no longer contributes a flat scalar here: a ~5% shave frequently vanished
        // in 0.5-set rounding and cut first hard sets and marginal sets alike. It is replaced
        // by whole-set evidence-band caps in adjustedPriorityIntent (SLEEP-002).
        weeklyVolumeScale = max(0.70, min(1.0, weeklyVolumeScale))

        let reduceExerciseSlotComplexity = lowPerformanceDataQuality
            || (poorNutritionAdherence && recompositionGoal)
        let baseTimeCap: Int
        switch recoveryTier {
        case .restricted: baseTimeCap = 65
        case .constrained: baseTimeCap = 70
        case .ready, .insufficientData: baseTimeCap = 75
        }

        // The session budget now answers to whether the lifter actually FINISHES his sessions,
        // not only to how he slept.
        //
        // Until this, the cap came from the recovery tier alone. The app separately recorded every
        // movement he abandoned for time — one of his had been skipped for time three separate
        // times — printed that count into the prompt, and then planned the next week to exactly
        // the same length as if it had never happened. A plan he cannot finish is not a plan he is
        // following, and the exercises that lose are always the ones at the end.
        //
        // Deliberately modest and capped. One repeatedly-unfinished movement is worth 5 minutes,
        // two or more is worth 10, and it stops there: this is a nudge toward a session he
        // completes, not a spiral that shrinks the program every time a shift runs long.
        //
        // The floor below is HEADROOM, not an active guard, and the commit that introduced it
        // wrongly described it as protecting against a short-menu failure. It cannot: the lowest
        // `baseTimeCap` is 65 (Restricted) and the penalty caps at 10, so the smallest value this
        // expression can produce is 55 — the `max` never binds. It is kept because it is the
        // right shape if the ladder above or the penalty cap is ever changed, and
        // `UnfinishedSessionBudgetTests` pins the true minimum so a future edit that makes the
        // floor live shows up as a failing test rather than as a silently shorter week.
        //
        // Counting DISTINCT movements rather than total skips is deliberate too: `timeSkipExercises`
        // already requires a movement to have been abandoned at least twice before it counts, so
        // two of them means the problem is the session length rather than one awkward exercise.
        //
        // Reaches every style cap below EXCEPT "Arms", which carries its own hardcoded 50/55/60
        // ladder rather than deriving from this default. That is left alone deliberately: an Arms
        // day is already the shortest in the week, so it is the least likely to be the one running
        // over, and trimming the shortest session is where a time cut starts costing real work.
        let unfinishedPenalty = min(10, max(0, unfinishedMovementCount) * 5)
        let defaultSessionTimeCapMinutes = max(ClaudeService.absoluteSessionTimeFloorMinutes, baseTimeCap - unfinishedPenalty)
        let styleSessionCaps: [String: Int] = [
            "Push": defaultSessionTimeCapMinutes,
            "Pull": defaultSessionTimeCapMinutes,
            "Upper": defaultSessionTimeCapMinutes,
            "Lower": defaultSessionTimeCapMinutes,
            "Legs": defaultSessionTimeCapMinutes,
            "Arms": recoveryTier == .restricted ? 50 : (recoveryConstrained ? 55 : 60)
        ]

        var notes: [String] = []
        if lowPerformanceDataQuality {
            notes.append("Recent performance-data quality is limited, so keep exercise selection stable and progression conservative until more high-quality logs exist.")
        }
        if poorNutritionAdherence && recompositionGoal {
            notes.append("Nutrition adherence is the bottleneck right now, so keep specialization volume near the recoverable lower-mid range instead of chasing extra fatigue.")
        }
        switch recoveryTier {
        case .restricted:
            notes.append("Recovery modulation RESTRICTED (\(recoveryAudit)): weekly priority set targets are capped at the bottom of their evidence band. Take the cut from back-off and accessory sets — preserve the first 1-2 hard sets of each exercise and the session's identity, keep accessories about 1 rep further from failure, and do NOT reduce loads.")
        case .constrained:
            notes.append("Recovery modulation CONSTRAINED (\(recoveryAudit)): weekly priority set targets are capped at the midpoint of their evidence band. Session design should stay tight for shift-work recovery: trim filler first, keep compounds honest, and protect the weekly time budget.")
        case .insufficientData:
            notes.append("Recovery modulation OFF (\(recoveryAudit)): volume targets are unchanged rather than guessed from stale context.")
        case .ready:
            break
        }
        return ProgramCalibrationProfile(
            lowPerformanceDataQuality: lowPerformanceDataQuality,
            poorNutritionAdherence: poorNutritionAdherence,
            recoveryConstrained: recoveryConstrained,
            recoveryTier: recoveryTier,
            recoveryAudit: recoveryAudit,
            recompositionGoal: recompositionGoal,
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
        let preRecoveryDirectSets = roundedStimulusValue(
            max(minimumWeeklyDirectTarget, intent.weeklyDirectSetTarget * calibration.weeklyVolumeScale)
        )
        // Recovery tiers cut volume in whole sets anchored to the VOL-001 evidence bands
        // (restricted -> band floor, constrained -> band midpoint) instead of a flat
        // multiplier that rounding could erase. EvidenceProfile.md SLEEP-002.
        let scaledDirectSets = roundedStimulusValue(
            max(
                minimumWeeklyDirectTarget,
                recoveryCappedDirectTarget(
                    preRecoveryDirectSets,
                    priorityLevel: normalizedLevel,
                    tier: calibration.recoveryTier
                )
            )
        )
        let recoveryTrimDelta = max(0, preRecoveryDirectSets - scaledDirectSets)
        let scaledStimulus = roundedStimulusValue(
            max(
                scaledDirectSets + 1.0,
                intent.weeklyStimulusTarget * calibration.weeklyVolumeScale - recoveryTrimDelta
            )
        )

        var adjustedExerciseTarget = intent.weeklyExerciseTarget
        if calibration.reduceExerciseSlotComplexity && adjustedExerciseTarget > 2 {
            adjustedExerciseTarget -= 1
        }
        if calibration.recoveryConstrained && normalizedLevel != "High" && adjustedExerciseTarget > 1 {
            adjustedExerciseTarget -= 1
        }
        // Feasibility invariant: the slot count must always be able to hold the
        // (post-calibration) direct-set target under a ~4-set-per-exercise ceiling.
        // Without this floor, the recovery/complexity slot reductions above can decouple
        // slots from the target — e.g. 2 slots against a ~10-set High priority — leaving
        // the allocator physically unable to reach directSetTarget, which the validator
        // then reports as an unfixable "missed its direct-set target" hard failure.
        let slotFloor = minimumExerciseSlots(forWeeklySetTarget: scaledDirectSets)
        let reconciledExerciseTarget = max(1, min(5, max(adjustedExerciseTarget, slotFloor)))

        return MusclePriorityIntent(
            area: intent.area,
            priorityLevel: intent.priorityLevel,
            rank: intent.rank,
            rationale: intent.rationale,
            weeklyDayTarget: intent.weeklyDayTarget,
            weeklyExerciseTarget: reconciledExerciseTarget,
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

    /// The structured recovery decision for the next generation, read from the dated
    /// sleep state that SleepTrendStore maintains. Stale or missing state yields
    /// `.insufficientData` — never a silent adjustment.
    func sleepRecoveryDecision(now: Date = .now) -> RecoveryDecision {
        SleepRecoveryPolicy.decision(
            from: SleepRecoveryState.decodedJSON(
                UserDefaults.standard.string(forKey: AppSettingsKeys.derivedSleepRecoveryState)
            ),
            now: now
        )
    }

    /// Whole-set recovery cap anchored to the VOL-001 evidence bands:
    /// restricted -> band floor, constrained -> band midpoint, otherwise unchanged.
    /// EvidenceProfile.md SLEEP-002 [confidence: low-moderate].
    func recoveryCappedDirectTarget(_ target: Double, priorityLevel: String, tier: RecoveryTier) -> Double {
        let band = evidenceProfile.directSetTargetsByPriority[priorityLevel]
            ?? evidenceProfile.directSetTargetsByPriority["Medium"]
            ?? 5...8
        switch tier {
        case .restricted:
            return min(target, band.lowerBound)
        case .constrained:
            return min(target, (band.lowerBound + band.upperBound) / 2)
        case .ready, .insufficientData:
            return target
        }
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
