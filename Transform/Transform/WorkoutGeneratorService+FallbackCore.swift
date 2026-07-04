import Foundation

extension ClaudeService {
    // MARK: - Local Fallback Generation (Always-valid output path)

    func validatedProceduralWeekOneProgram(
        from analysisResult: BodyAnalysisResult,
        trainingIntent: TrainingIntentPlan,
        blueprint: ProgramBlueprint,
        exerciseMenus: [[PreSelectedExercise]]? = nil,
        diagnostic: String = ""
    ) throws -> WorkoutProgramResponse {
        let fallback = buildProceduralWeekOneProgram(
            from: analysisResult,
            trainingIntent: trainingIntent,
            blueprint: blueprint,
            exerciseMenus: exerciseMenus,
            diagnostic: diagnostic
        )
        let issues = validateProgramResponse(fallback, blueprint: blueprint)
        let hasHardFailure = issues.contains { validationDisposition(for: $0) == .hardFailure }
        guard issues.isEmpty || !hasHardFailure else {
            throw ClaudeError.parseError(
                "Procedural fallback generated an invalid Week 1 program: \(issues.joined(separator: " | "))"
            )
        }

        if !issues.isEmpty {
            print("[WorkoutGeneratorService] Procedural Week 1 fallback accepted with heuristic warnings: \(issues.joined(separator: " | "))")
        }

        return fallback
    }

    func validatedProceduralWeek(
        weekNumber: Int,
        dayStart: Int,
        dayEnd: Int,
        splitType: String,
        programName: String,
        trainingIntent: TrainingIntentPlan,
        blueprint: ProgramBlueprint,
        previousWeekDays: [WorkoutDayResponse]?,
        exerciseMenus: [[PreSelectedExercise]]? = nil,
        diagnostic: String = ""
    ) throws -> WorkoutWeekResponse {
        let fallback = buildProceduralWeek(
            weekNumber: weekNumber,
            dayStart: dayStart,
            dayEnd: dayEnd,
            splitType: splitType,
            programName: programName,
            trainingIntent: trainingIntent,
            blueprint: blueprint,
            previousWeekDays: previousWeekDays,
            exerciseMenus: exerciseMenus,
            diagnostic: diagnostic
        )
        let issues = validateWeekResponse(
            fallback,
            dayStart: dayStart,
            dayEnd: dayEnd,
            previousWeekDays: previousWeekDays,
            blueprint: blueprint
        )
        let hasHardFailure = issues.contains { validationDisposition(for: $0) == .hardFailure }
        guard issues.isEmpty || !hasHardFailure else {
            throw ClaudeError.parseError(
                "Procedural fallback generated an invalid week \(weekNumber): \(issues.joined(separator: " | "))"
            )
        }

        if !issues.isEmpty {
            print("[WorkoutGeneratorService] Procedural week \(weekNumber) fallback accepted with heuristic warnings: \(issues.joined(separator: " | "))")
        }

        return fallback
    }

    func buildProceduralWeekOneProgram(
        from analysisResult: BodyAnalysisResult,
        trainingIntent: TrainingIntentPlan,
        blueprint: ProgramBlueprint,
        exerciseMenus: [[PreSelectedExercise]]? = nil,
        diagnostic: String = ""
    ) -> WorkoutProgramResponse {
        let splitRecommendation = trainingIntent.splitRecommendation.trimmedOr(default: "Adaptive Hypertrophy Split")
        let programName = trainingIntent.splitRecommendation.trimmedOr(default: "Adaptive Recomp Mesocycle")
        let generatedWeek = buildProceduralWeek(
            weekNumber: 1,
            dayStart: 1,
            dayEnd: 7,
            splitType: splitRecommendation,
            programName: programName,
            trainingIntent: trainingIntent,
            blueprint: blueprint,
            previousWeekDays: nil,
            exerciseMenus: exerciseMenus,
            diagnostic: diagnostic
        )

        let trainingDays = generatedWeek.days.filter { !$0.isRestDay }.count
        let focusLabel = trainingIntent.priorities.map(\.area).prefix(3).joined(separator: ", ")
        let summaryFocus = focusLabel.isEmpty ? "" : " Focus areas: \(focusLabel)."

        return WorkoutProgramResponse(
            programName: programName,
            programSummary: withSourceLabel(
                "Week 1 used analysis-driven progression logic to build complete programming.\(summaryFocus)",
                sourceLabel: fallbackSourceLabel
            ),
            splitType: splitRecommendation,
            daysPerWeek: trainingDays,
            days: generatedWeek.days
        )
    }

    func buildProceduralWeek(
        weekNumber: Int,
        dayStart: Int,
        dayEnd: Int,
        splitType: String,
        programName: String,
        trainingIntent: TrainingIntentPlan,
        blueprint: ProgramBlueprint,
        previousWeekDays: [WorkoutDayResponse]?,
        exerciseMenus: [[PreSelectedExercise]]? = nil,
        diagnostic: String = ""
    ) -> WorkoutWeekResponse {
        let previousExercisesByStyle = proceduralPreviousExercisesByStyle(from: previousWeekDays)
        var previousUsageByStyle: [String: Int] = [:]

        var days: [WorkoutDayResponse] = []
        for offset in 0..<7 {
            let dayNumber = dayStart + offset
            let plan = blueprint.dayPlans[offset]
            let shouldRest = plan.isRestDay

            if shouldRest {
                days.append(
                    WorkoutDayResponse(
                        dayNumber: dayNumber,
                        dayName: "Rest / Recovery",
                        muscleGroups: "Recovery",
                        isRestDay: true,
                        notes: "Active recovery, mobility work, and light cardio.",
                        exercises: []
                    )
                )
                continue
            }

            let style = plan.style
            let focusIntent = focusIntentForArea(plan.focusArea, within: trainingIntent)
            let supportIntents = plan.supportAreas.compactMap { focusIntentForArea($0, within: trainingIntent) }
            let focus = plan.focusArea ?? ""

            let menu = exerciseMenus.flatMap { offset < $0.count ? $0[offset] : nil }
            let hasMenu = menu != nil && !(menu!.isEmpty)

            let exercises: [WorkoutExerciseResponse]
            if hasMenu {
                exercises = programMenuExercises(
                    menu: menu!,
                    weekNumber: weekNumber,
                    style: style,
                    focus: focus,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents,
                    targetFatigueCap: plan.targetFatigueCap,
                    targetSessionMinutes: plan.targetSessionMinutes
                )
            } else {
                let styleKey = canonicalTrainingStyle(style)
                let styleUsage = previousUsageByStyle[styleKey, default: 0]
                let previousExercises: [WorkoutExerciseResponse] = previousExercisesByStyle[styleKey].flatMap { groupedExercises in
                    guard styleUsage < groupedExercises.count else { return nil }
                    return groupedExercises[styleUsage]
                } ?? [WorkoutExerciseResponse]()
                previousUsageByStyle[styleKey] = styleUsage + 1

                exercises = buildProceduralExercises(
                    style: style,
                    weekNumber: weekNumber,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents,
                    targetFatigueCap: plan.targetFatigueCap,
                    targetSessionMinutes: plan.targetSessionMinutes,
                    selectionContext: ExerciseSelectionContext(
                        calibration: blueprint.calibration,
                        injuryRiskFocus: blueprint.injuryRiskFocus,
                        targetSessionMinutes: plan.targetSessionMinutes,
                        style: style
                    ),
                    previousExercises: previousExercises
                )
            }

            let dayName = focus.isEmpty ? "\(style) Session" : "\(style) - \(focus) Focus"
            let groups = proceduralMuscleGroups(for: style)
            let notes = proceduralDayNotes(
                style: style,
                weekNumber: weekNumber,
                exercises: exercises,
                focus: focus,
                focusIntent: focusIntent,
                blueprint: blueprint
            )

            days.append(
                WorkoutDayResponse(
                    dayNumber: dayNumber,
                    dayName: dayName,
                    muscleGroups: groups,
                    isRestDay: false,
                    notes: notes,
                    exercises: exercises
                )
            )
        }

        days = repairedProceduralDays(
            days,
            weekNumber: weekNumber,
            blueprint: blueprint,
            dayStart: dayStart,
            menuLocked: exerciseMenus != nil
        )

        let summary = "Week \(weekNumber) for \(programName) (\(splitType)) applies phase-aware progression and shift-work-friendly session design."
        return WorkoutWeekResponse(
            weekSummary: withSourceLabel(summary, sourceLabel: fallbackSourceLabel),
            days: days
        )
    }

    func repairedProceduralDays(
        _ days: [WorkoutDayResponse],
        weekNumber: Int,
        blueprint: ProgramBlueprint,
        dayStart: Int,
        menuLocked: Bool = false
    ) -> [WorkoutDayResponse] {
        let repaired = repairProceduralPriorityCoverage(
            in: days,
            weekNumber: weekNumber,
            blueprint: blueprint,
            dayStart: dayStart,
            menuLocked: menuLocked
        )
        let budgeted = enforceProceduralSessionBudgets(
            repaired,
            weekNumber: weekNumber,
            blueprint: blueprint,
            dayStart: dayStart,
            menuLocked: menuLocked
        )

        return repairProceduralPriorityCoverage(
            in: budgeted,
            weekNumber: weekNumber,
            blueprint: blueprint,
            dayStart: dayStart,
            menuLocked: menuLocked
        )
    }

    func repairProceduralPriorityCoverage(
        in days: [WorkoutDayResponse],
        weekNumber: Int,
        blueprint: ProgramBlueprint,
        dayStart: Int,
        menuLocked: Bool = false
    ) -> [WorkoutDayResponse] {
        var repaired = days
        var passCount = 0
        var changed = true

        while changed && passCount < 6 {
            changed = false
            passCount += 1
            let stimulusReport = buildWeekStimulusReport(from: repaired)

            for allocation in blueprint.priorityAllocations {
                let coverage = priorityCoverage(for: allocation, stimulusReport: stimulusReport)
                var remainingDirectShortfall = max(0, allocation.directSetTarget - coverage.directSets)
                var remainingWeightedShortfall = max(0, allocation.weightedStimulusTarget - coverage.weightedStimulus)
                var remainingFrequencyShortfall = max(0, allocation.targetFrequency - coverage.dayMatches)
                guard remainingDirectShortfall > 0.01
                        || remainingWeightedShortfall > 0.01
                        || remainingFrequencyShortfall > 0 else {
                    continue
                }
                var directOvershootBudget = max(0, allocation.directSetTarget + 1.0 - coverage.directSets)

                if !menuLocked,
                   remainingFrequencyShortfall > 0,
                   coverage.directSets + 0.01 >= allocation.directSetTarget,
                   let redistributed = redistributePriorityVolumeForFrequency(
                        in: repaired,
                        allocation: allocation,
                        blueprint: blueprint,
                        dayStart: dayStart,
                        weekNumber: weekNumber
                   ) {
                    repaired = redistributed
                    changed = true
                    break
                }

                let candidateDays = repairCandidateDayNumbersExpanded(
                    for: allocation,
                    blueprint: blueprint,
                    dayStart: dayStart,
                    existingDays: repaired,
                    needsFrequencyExpansion: remainingFrequencyShortfall > 0
                )

                for dayNumber in candidateDays {
                    guard remainingDirectShortfall > 0.01
                            || remainingWeightedShortfall > 0.01
                            || remainingFrequencyShortfall > 0,
                          let dayIndex = repaired.firstIndex(where: { $0.dayNumber == dayNumber }) else {
                        continue
                    }

                    let day = repaired[dayIndex]
                    guard !day.isRestDay else { continue }

                    let allowedCap = allowedPerSessionDirectSetCap(
                        for: allocation,
                        dayNumber: dayNumber,
                        blueprint: blueprint,
                        dayStart: dayStart
                    )
                    let currentDirectSets = menuLocked
                        ? primeDirectSets(on: day, forFocusArea: allocation.area)
                        : directSets(on: day, forFocusArea: allocation.area)
                    var remainingSessionDirectCapacity = max(0, allowedCap - currentDirectSets)
                    guard remainingSessionDirectCapacity > 0.01 else { continue }

                    let targetFatigueCap = relativeBlueprintDayIndex(for: dayNumber, dayStart: dayStart)
                        .flatMap { relativeDayIndex in
                            blueprint.dayPlans.first(where: { $0.dayIndex == relativeDayIndex })?.targetFatigueCap
                        }
                        ?? maxDailyFatigueThreshold(for: repaired, dayNumber: dayNumber)
                    let targetSessionMinutes = relativeBlueprintDayIndex(for: dayNumber, dayStart: dayStart)
                        .flatMap { relativeDayIndex in
                            blueprint.dayPlans.first(where: { $0.dayIndex == relativeDayIndex })?.targetSessionMinutes
                        }
                    var exercises = day.exercises
                    var dayChanged = false
                    var startedWithoutExposure = currentDirectSets <= 0.01

                    let intent = priorityIntent(for: allocation)
                    let matchingIndices = exercises.indices.filter { index in
                        directPrioritySetContribution(
                            exerciseName: exercises[index].exerciseName,
                            muscleTarget: exercises[index].muscleTarget,
                            intent: intent,
                            sets: exercises[index].sets
                        ) > 0
                    }

                    let dayStyle = relativeBlueprintDayIndex(for: dayNumber, dayStart: dayStart)
                        .flatMap { idx in blueprint.dayPlans.first(where: { $0.dayIndex == idx })?.style }
                        ?? ""
                    let weeklyVariationKeys = priorityVariationNames(
                        for: allocation,
                        in: repaired,
                        overridingDayNumber: dayNumber,
                        exercises: exercises
                    )
                    let variationCap = maximumUsefulVariationCount(for: allocation)

                    let existingPotentialGain = additionalRepairPotentialGain(
                        for: exercises,
                        matchingIndices: matchingIndices,
                        intent: intent,
                        weekNumber: weekNumber,
                        remainingSessionDirectCapacity: remainingSessionDirectCapacity
                    )
                    let needsSupplementalExercise = matchingIndices.isEmpty
                        || remainingDirectShortfall > existingPotentialGain + 0.01
                        || remainingWeightedShortfall > existingPotentialGain + 0.01

                    if !menuLocked,
                       needsSupplementalExercise,
                       remainingDirectShortfall > 0.01
                            || remainingWeightedShortfall > 0.01 {
                        let minimumDirectGainNeeded = startedWithoutExposure && remainingFrequencyShortfall > 0
                            ? minimumMeaningfulPriorityExposureSets(for: allocation.area)
                            : 0
                        let injected = injectAccessoryExercise(
                            into: exercises,
                            for: allocation,
                            weekNumber: weekNumber,
                            targetFatigueCap: targetFatigueCap,
                            dayStyle: dayStyle,
                            targetSessionMinutes: targetSessionMinutes,
                            remainingSessionDirectCapacity: remainingSessionDirectCapacity,
                            minimumDirectGainNeeded: minimumDirectGainNeeded,
                            weeklyVariationKeys: weeklyVariationKeys,
                            variationCap: variationCap
                        )
                        if let injected {
                            exercises = injected.exercises
                            remainingDirectShortfall = max(0, remainingDirectShortfall - injected.directGain)
                            remainingWeightedShortfall = max(0, remainingWeightedShortfall - injected.directGain)
                            remainingSessionDirectCapacity = max(0, remainingSessionDirectCapacity - injected.directGain)
                            directOvershootBudget = max(0, directOvershootBudget - injected.directGain)
                            if startedWithoutExposure, injected.directGain > 0 {
                                remainingFrequencyShortfall = max(0, remainingFrequencyShortfall - 1)
                                startedWithoutExposure = false
                            }
                            dayChanged = true
                            changed = true
                        }
                    }

                    let updatedMatchingIndices = exercises.indices
                        .filter { index in
                            directPrioritySetContribution(
                                exerciseName: exercises[index].exerciseName,
                                muscleTarget: exercises[index].muscleTarget,
                                intent: intent,
                                sets: exercises[index].sets
                            ) > 0
                        }
                        .sorted { lhs, rhs in
                            priorityContributionPerSet(for: exercises[lhs], intent: intent)
                                > priorityContributionPerSet(for: exercises[rhs], intent: intent)
                        }

                    for exerciseIndex in updatedMatchingIndices {
                        let perSetGain = priorityContributionPerSet(
                            for: exercises[exerciseIndex],
                            intent: intent
                        )
                        guard perSetGain > 0 else { continue }

                        while (remainingDirectShortfall > 0.01 || remainingWeightedShortfall > 0.01),
                              remainingSessionDirectCapacity + 0.01 >= perSetGain,
                              directOvershootBudget + 0.01 >= perSetGain,
                              exercises[exerciseIndex].sets < repairSetCeiling(for: exercises[exerciseIndex], weekNumber: weekNumber) {
                            let updatedExercise = exerciseResponse(
                                exercises[exerciseIndex],
                                withSets: exercises[exerciseIndex].sets + 1
                            )
                            var updatedExercises = exercises
                            updatedExercises[exerciseIndex] = updatedExercise

                            if !canAccommodatePriorityRepair(
                                updatedExercises,
                                targetFatigueCap: targetFatigueCap,
                                targetSessionMinutes: targetSessionMinutes
                            ) {
                                if menuLocked,
                                   let trimIndex = focusBudgetTrimCandidate(
                                       in: updatedExercises,
                                       boostingIndex: exerciseIndex,
                                       focusArea: allocation.area
                                   ) {
                                    updatedExercises[trimIndex] = exerciseResponse(
                                        updatedExercises[trimIndex],
                                        withSets: updatedExercises[trimIndex].sets - 1
                                    )
                                    if canAccommodatePriorityRepair(
                                        updatedExercises,
                                        targetFatigueCap: targetFatigueCap,
                                        targetSessionMinutes: targetSessionMinutes
                                    ) {
                                        exercises = updatedExercises
                                        remainingDirectShortfall = max(0, remainingDirectShortfall - perSetGain)
                                        remainingWeightedShortfall = max(0, remainingWeightedShortfall - perSetGain)
                                        remainingSessionDirectCapacity = max(0, remainingSessionDirectCapacity - perSetGain)
                                        directOvershootBudget = max(0, directOvershootBudget - perSetGain)
                                        if startedWithoutExposure {
                                            remainingFrequencyShortfall = max(0, remainingFrequencyShortfall - 1)
                                            startedWithoutExposure = false
                                        }
                                        dayChanged = true
                                        changed = true
                                        continue
                                    }
                                }
                                break
                            }

                            exercises = updatedExercises
                            remainingDirectShortfall = max(0, remainingDirectShortfall - perSetGain)
                            remainingWeightedShortfall = max(0, remainingWeightedShortfall - perSetGain)
                            remainingSessionDirectCapacity = max(0, remainingSessionDirectCapacity - perSetGain)
                            directOvershootBudget = max(0, directOvershootBudget - perSetGain)
                            if startedWithoutExposure {
                                remainingFrequencyShortfall = max(0, remainingFrequencyShortfall - 1)
                                startedWithoutExposure = false
                            }
                            dayChanged = true
                            changed = true
                        }
                    }

                    if !menuLocked,
                       (remainingDirectShortfall > 0.01 || remainingWeightedShortfall > 0.01),
                       remainingSessionDirectCapacity > 0.01 {
                        let updatedWeeklyVariationKeys = priorityVariationNames(
                            for: allocation,
                            in: repaired,
                            overridingDayNumber: dayNumber,
                            exercises: exercises
                        )
                        let minimumDirectGainNeeded = startedWithoutExposure && remainingFrequencyShortfall > 0
                            ? minimumMeaningfulPriorityExposureSets(for: allocation.area)
                            : 0
                        let injected = injectAccessoryExercise(
                            into: exercises,
                            for: allocation,
                            weekNumber: weekNumber,
                            targetFatigueCap: targetFatigueCap,
                            dayStyle: dayStyle,
                            targetSessionMinutes: targetSessionMinutes,
                            remainingSessionDirectCapacity: remainingSessionDirectCapacity,
                            minimumDirectGainNeeded: minimumDirectGainNeeded,
                            weeklyVariationKeys: updatedWeeklyVariationKeys,
                            variationCap: variationCap
                        )
                        if let injected {
                            exercises = injected.exercises
                            remainingDirectShortfall = max(0, remainingDirectShortfall - injected.directGain)
                            remainingWeightedShortfall = max(0, remainingWeightedShortfall - injected.directGain)
                            remainingSessionDirectCapacity = max(0, remainingSessionDirectCapacity - injected.directGain)
                            directOvershootBudget = max(0, directOvershootBudget - injected.directGain)
                            if startedWithoutExposure, injected.directGain > 0 {
                                remainingFrequencyShortfall = max(0, remainingFrequencyShortfall - 1)
                                startedWithoutExposure = false
                            }
                            dayChanged = true
                            changed = true
                        }
                    }

                    if dayChanged {
                        repaired[dayIndex] = WorkoutDayResponse(
                            dayNumber: day.dayNumber,
                            dayName: day.dayName,
                            muscleGroups: day.muscleGroups,
                            isRestDay: day.isRestDay,
                            notes: day.notes,
                            exercises: exercises
                        )
                    }
                }
            }
        }

        return repaired
    }

    func enforceProceduralSessionBudgets(
        _ days: [WorkoutDayResponse],
        weekNumber: Int,
        blueprint: ProgramBlueprint,
        dayStart: Int,
        menuLocked: Bool = false
    ) -> [WorkoutDayResponse] {
        var updatedDays = days

        for index in updatedDays.indices {
            let day = updatedDays[index]
            guard !day.isRestDay,
                  let relativeDayIndex = relativeBlueprintDayIndex(for: day.dayNumber, dayStart: dayStart),
                  let plan = blueprint.dayPlans.first(where: { $0.dayIndex == relativeDayIndex }) else {
                continue
            }

            let focusIntent = plan.focusArea.flatMap { area in
                blueprint.priorityAllocations.first(where: {
                    normalizedPriorityText($0.area) == normalizedPriorityText(area)
                }).map(priorityIntent(for:))
            }
            let supportIntents = plan.supportAreas.compactMap { area in
                blueprint.priorityAllocations.first(where: {
                    normalizedPriorityText($0.area) == normalizedPriorityText(area)
                }).map(priorityIntent(for:))
            }
            let trimmedExercises: [WorkoutExerciseResponse]
            if menuLocked {
                trimmedExercises = setOnlyFatigueRebalance(
                    day.exercises,
                    weekNumber: weekNumber,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents,
                    targetFatigueCap: plan.targetFatigueCap,
                    targetSessionMinutes: plan.targetSessionMinutes
                )
            } else {
                trimmedExercises = rebalanceSessionTime(
                    in: day.exercises,
                    weekNumber: weekNumber,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents,
                    targetSessionMinutes: plan.targetSessionMinutes
                )
            }
            updatedDays[index] = WorkoutDayResponse(
                dayNumber: day.dayNumber,
                dayName: day.dayName,
                muscleGroups: day.muscleGroups,
                isRestDay: day.isRestDay,
                notes: day.notes,
                exercises: trimmedExercises
            )
        }

        return updatedDays
    }

    func redistributePriorityVolumeForFrequency(
        in days: [WorkoutDayResponse],
        allocation: BlueprintPriorityAllocation,
        blueprint: ProgramBlueprint,
        dayStart: Int,
        weekNumber: Int
    ) -> [WorkoutDayResponse]? {
        let intent = priorityIntent(for: allocation)
        let meaningfulThreshold = minimumMeaningfulPriorityExposureSets(for: allocation.area)
        var updatedDays = days

        let recipientDayNumbers = repairCandidateDayNumbersExpanded(
            for: allocation,
            blueprint: blueprint,
            dayStart: dayStart,
            existingDays: days,
            needsFrequencyExpansion: true
        ).filter { dayNumber in
            guard let day = updatedDays.first(where: { $0.dayNumber == dayNumber }), !day.isRestDay else {
                return false
            }
            return directSets(on: day, forFocusArea: allocation.area) <= 0.01
        }

        for recipientDayNumber in recipientDayNumbers {
            guard let recipientIndex = updatedDays.firstIndex(where: { $0.dayNumber == recipientDayNumber }) else {
                continue
            }
            let recipientDay = updatedDays[recipientIndex]
            guard let relativeRecipientIndex = relativeBlueprintDayIndex(for: recipientDayNumber, dayStart: dayStart),
                  let recipientPlan = blueprint.dayPlans.first(where: { $0.dayIndex == relativeRecipientIndex }) else {
                continue
            }

            let recipientCapacity = allowedPerSessionDirectSetCap(
                for: allocation,
                dayNumber: recipientDayNumber,
                blueprint: blueprint,
                dayStart: dayStart
            ) - directSets(on: recipientDay, forFocusArea: allocation.area)
            guard recipientCapacity > 0.01 else { continue }

            let donorCandidates = updatedDays.enumerated()
                .filter { index, day in
                    guard !day.isRestDay, day.dayNumber != recipientDayNumber else { return false }
                    return directSets(on: day, forFocusArea: allocation.area) > meaningfulThreshold + 0.01
                }
                .sorted { lhs, rhs in
                    let lhsDirect = directSets(on: lhs.element, forFocusArea: allocation.area)
                    let rhsDirect = directSets(on: rhs.element, forFocusArea: allocation.area)
                    if lhsDirect != rhsDirect { return lhsDirect > rhsDirect }
                    return lhs.element.dayNumber < rhs.element.dayNumber
                }

            for (donorIndex, donorDay) in donorCandidates {
                let donorDayDirectSets = directSets(on: donorDay, forFocusArea: allocation.area)
                let donorMatchingIndices = donorDay.exercises.indices
                    .filter { index in
                        directPrioritySetContribution(
                            exerciseName: donorDay.exercises[index].exerciseName,
                            muscleTarget: donorDay.exercises[index].muscleTarget,
                            intent: intent,
                            sets: donorDay.exercises[index].sets
                        ) > 0
                    }
                    .sorted { lhs, rhs in
                        priorityContributionPerSet(for: donorDay.exercises[lhs], intent: intent)
                            > priorityContributionPerSet(for: donorDay.exercises[rhs], intent: intent)
                    }

                for donorExerciseIndex in donorMatchingIndices {
                    let donorExercise = donorDay.exercises[donorExerciseIndex]
                    let perSetGain = priorityContributionPerSet(for: donorExercise, intent: intent)
                    guard perSetGain > 0 else { continue }
                    guard exerciseMatchesDayStyle(donorExercise, style: recipientPlan.style) else { continue }

                    let donorReducibleSets = donorExercise.sets - minimumSetFloor(for: donorExercise)
                    guard donorReducibleSets > 0 else { continue }

                    let maxRecipientSets = Int(floor((recipientCapacity + 0.01) / perSetGain))
                    let minimumMeaningfulSets = max(1, Int(ceil((meaningfulThreshold - 0.01) / perSetGain)))
                    let setsToShift = min(donorReducibleSets, maxRecipientSets)
                    guard setsToShift >= minimumMeaningfulSets else { continue }

                    let directGain = Double(setsToShift) * perSetGain
                    guard donorDayDirectSets - directGain + 0.01 >= meaningfulThreshold else { continue }

                    var donorExercises = donorDay.exercises
                    var recipientExercises = recipientDay.exercises

                    donorExercises[donorExerciseIndex] = exerciseResponse(
                        donorExercise,
                        withSets: donorExercise.sets - setsToShift
                    )

                    if let existingRecipientIndex = recipientExercises.firstIndex(where: { exercise in
                        normalizeExerciseName(exercise.exerciseName) == normalizeExerciseName(donorExercise.exerciseName)
                    }) {
                        recipientExercises[existingRecipientIndex] = exerciseResponse(
                            recipientExercises[existingRecipientIndex],
                            withSets: recipientExercises[existingRecipientIndex].sets + setsToShift
                        )
                    } else {
                        recipientExercises.append(
                            WorkoutExerciseResponse(
                                exerciseName: donorExercise.exerciseName,
                                sets: setsToShift,
                                reps: donorExercise.reps,
                                tempo: donorExercise.tempo,
                                restSeconds: donorExercise.restSeconds,
                                notes: proceduralExerciseNotes(
                                    weekNumber: weekNumber,
                                    exerciseName: donorExercise.exerciseName,
                                    muscleTarget: donorExercise.muscleTarget,
                                    index: recipientExercises.count,
                                    focus: allocation.area
                                ),
                                muscleTarget: donorExercise.muscleTarget
                            )
                        )
                    }

                    guard recipientExercises.count <= 8,
                          canAccommodatePriorityRepair(
                            recipientExercises,
                            targetFatigueCap: recipientPlan.targetFatigueCap,
                            targetSessionMinutes: recipientPlan.targetSessionMinutes
                          ) else {
                        continue
                    }

                    updatedDays[donorIndex] = WorkoutDayResponse(
                        dayNumber: donorDay.dayNumber,
                        dayName: donorDay.dayName,
                        muscleGroups: donorDay.muscleGroups,
                        isRestDay: donorDay.isRestDay,
                        notes: donorDay.notes,
                        exercises: donorExercises
                    )
                    updatedDays[recipientIndex] = WorkoutDayResponse(
                        dayNumber: recipientDay.dayNumber,
                        dayName: recipientDay.dayName,
                        muscleGroups: recipientDay.muscleGroups,
                        isRestDay: recipientDay.isRestDay,
                        notes: recipientDay.notes,
                        exercises: recipientExercises
                    )
                    return updatedDays
                }
            }
        }

        return nil
    }

    func repairCandidateDayNumbersExpanded(
        for allocation: BlueprintPriorityAllocation,
        blueprint: ProgramBlueprint,
        dayStart: Int,
        existingDays: [WorkoutDayResponse],
        needsFrequencyExpansion: Bool
    ) -> [Int] {
        var candidates = repairCandidateDayNumbers(
            for: allocation,
            blueprint: blueprint,
            dayStart: dayStart
        )

        guard needsFrequencyExpansion else { return candidates }

        let candidateSet = Set(candidates)
        let styleCompatible = allocation.preferredStyles.map { canonicalTrainingStyle($0) }

        let extraDays = blueprint.dayPlans.compactMap { plan -> Int? in
            guard !plan.isRestDay else { return nil }
            let dayNumber = blueprintDayNumber(plan.dayIndex, dayStart: dayStart)
            guard !candidateSet.contains(dayNumber) else { return nil }
            let canonical = canonicalTrainingStyle(plan.style)
            guard styleCompatible.contains(canonical) || canonical == "Upper" else { return nil }
            return dayNumber
        }

        candidates.append(contentsOf: extraDays)

        var seen = Set<Int>()
        let uniqueCandidates = candidates.filter { candidate in
            guard !seen.contains(candidate) else { return false }
            seen.insert(candidate)
            return true
        }
        return uniqueCandidates.sorted { lhs, rhs in
            let lhsDirectSets = existingDays.first(where: { $0.dayNumber == lhs })
                .map { directSets(on: $0, forFocusArea: allocation.area) }
                ?? 0
            let rhsDirectSets = existingDays.first(where: { $0.dayNumber == rhs })
                .map { directSets(on: $0, forFocusArea: allocation.area) }
                ?? 0
            let lhsHasExposure = lhsDirectSets > 0.01
            let rhsHasExposure = rhsDirectSets > 0.01

            if needsFrequencyExpansion, lhsHasExposure != rhsHasExposure {
                return !lhsHasExposure && rhsHasExposure
            }
            if lhsDirectSets != rhsDirectSets {
                return lhsDirectSets < rhsDirectSets
            }
            return lhs < rhs
        }
    }

    func injectAccessoryExercise(
        into exercises: [WorkoutExerciseResponse],
        for allocation: BlueprintPriorityAllocation,
        weekNumber: Int,
        targetFatigueCap: Int,
        dayStyle: String,
        targetSessionMinutes: Int?,
        remainingSessionDirectCapacity: Double,
        minimumDirectGainNeeded: Double,
        weeklyVariationKeys: Set<String>,
        variationCap: Int
    ) -> (exercises: [WorkoutExerciseResponse], directGain: Double)? {
        let intent = priorityIntent(for: allocation)
        let catalog = priorityAccessoryCatalog(for: intent)
        let usedKeys = Set(exercises.map { normalizeExerciseName($0.exerciseName) })
        let canonicalStyle = canonicalTrainingStyle(dayStyle)

        let candidates = catalog.filter { entry in
            guard !usedKeys.contains(normalizeExerciseName(entry.name)) else { return false }
            let probe = WorkoutExerciseResponse(
                exerciseName: entry.name, sets: 3, reps: "10-12",
                tempo: "2-0-1-0", restSeconds: 60, notes: "", muscleTarget: entry.target
            )
            return exerciseMatchesDayStyle(probe, style: canonicalStyle)
        }.sorted { lhs, rhs in
            let lhsExistingVariation = weeklyVariationKeys.contains(normalizeExerciseName(lhs.name))
            let rhsExistingVariation = weeklyVariationKeys.contains(normalizeExerciseName(rhs.name))
            if lhsExistingVariation != rhsExistingVariation {
                return lhsExistingVariation && !rhsExistingVariation
            }

            let lhsKind = focusStimulusKind(
                exerciseName: lhs.name,
                muscleTarget: lhs.target,
                focusArea: allocation.area
            )
            let rhsKind = focusStimulusKind(
                exerciseName: rhs.name,
                muscleTarget: rhs.target,
                focusArea: allocation.area
            )
            let lhsCredit = focusStimulusCredit(for: lhsKind)
            let rhsCredit = focusStimulusCredit(for: rhsKind)
            if lhsCredit != rhsCredit {
                return lhsCredit > rhsCredit
            }

            return normalizeExerciseName(lhs.name) < normalizeExerciseName(rhs.name)
        }

        for candidate in candidates {
            let candidateKey = normalizeExerciseName(candidate.name)
            let wouldIntroduceNewVariation = !weeklyVariationKeys.contains(candidateKey)
            if wouldIntroduceNewVariation && weeklyVariationKeys.count >= variationCap {
                continue
            }

            let defaultSets = proceduralSets(for: weekNumber, exerciseName: candidate.name, muscleTarget: candidate.target)
            let reps = proceduralRepRange(for: weekNumber, exerciseName: candidate.name, muscleTarget: candidate.target)
            let probeExercise = WorkoutExerciseResponse(
                exerciseName: candidate.name,
                sets: defaultSets,
                reps: reps,
                tempo: proceduralTempo(for: weekNumber, exerciseName: candidate.name, muscleTarget: candidate.target, reps: reps),
                restSeconds: proceduralRestSeconds(for: candidate.name, muscleTarget: candidate.target),
                notes: proceduralExerciseNotes(weekNumber: weekNumber, exerciseName: candidate.name, muscleTarget: candidate.target, index: exercises.count, focus: allocation.area),
                muscleTarget: candidate.target
            )
            let perSetGain = priorityContributionPerSet(for: probeExercise, intent: intent)
            guard perSetGain > 0,
                  remainingSessionDirectCapacity + 0.01 >= perSetGain else {
                continue
            }

            let maxInjectableSets = Int(floor((remainingSessionDirectCapacity + 0.01) / perSetGain))
            let cappedSets = min(defaultSets, maxInjectableSets)
            guard cappedSets >= minimumSetFloor(for: probeExercise) else { continue }

            let newExercise = exerciseResponse(probeExercise, withSets: cappedSets)
            let directGain = perSetGain * Double(cappedSets)
            guard directGain + 0.01 >= minimumDirectGainNeeded else { continue }
            guard directGain > 0 else { continue }

            var updated = exercises
            let appended = updated + [newExercise]
            if exercises.count < 8,
               canAccommodatePriorityRepair(
                    appended,
                    targetFatigueCap: targetFatigueCap,
                    targetSessionMinutes: targetSessionMinutes
               ) {
                updated.append(newExercise)
                return (exercises: updated, directGain: directGain)
            }

            guard let removalIndex = exercises.indices.reversed().first(where: { index in
                let contribution = directPrioritySetContribution(
                    exerciseName: exercises[index].exerciseName,
                    muscleTarget: exercises[index].muscleTarget,
                    intent: intent,
                    sets: exercises[index].sets
                )
                return contribution == 0
            }) else {
                continue
            }

            updated = exercises
            updated.remove(at: removalIndex)
            updated.append(newExercise)

            if canAccommodatePriorityRepair(
                updated,
                targetFatigueCap: targetFatigueCap,
                targetSessionMinutes: targetSessionMinutes
            ) {
                return (exercises: updated, directGain: directGain)
            }
        }

        return nil
    }

    func priorityVariationNames(
        for allocation: BlueprintPriorityAllocation,
        in days: [WorkoutDayResponse],
        overridingDayNumber: Int? = nil,
        exercises overrideExercises: [WorkoutExerciseResponse]? = nil
    ) -> Set<String> {
        let intent = priorityIntent(for: allocation)
        var names = Set<String>()

        for day in days where !day.isRestDay {
            let exercises = (day.dayNumber == overridingDayNumber && overrideExercises != nil)
                ? (overrideExercises ?? day.exercises)
                : day.exercises

            for exercise in exercises {
                let contribution = directPrioritySetContribution(
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget,
                    intent: intent,
                    sets: exercise.sets
                )
                guard contribution > 0 else { continue }
                names.insert(normalizeExerciseName(exercise.exerciseName))
            }
        }

        return names
    }

    func additionalRepairPotentialGain(
        for exercises: [WorkoutExerciseResponse],
        matchingIndices: [Int],
        intent: MusclePriorityIntent,
        weekNumber: Int,
        remainingSessionDirectCapacity: Double
    ) -> Double {
        guard remainingSessionDirectCapacity > 0.01 else { return 0 }

        var remainingCapacity = remainingSessionDirectCapacity
        var potentialGain = 0.0
        let orderedIndices = matchingIndices.sorted { lhs, rhs in
            priorityContributionPerSet(for: exercises[lhs], intent: intent)
                > priorityContributionPerSet(for: exercises[rhs], intent: intent)
        }

        for index in orderedIndices {
            let perSetGain = priorityContributionPerSet(for: exercises[index], intent: intent)
            guard perSetGain > 0 else { continue }

            let remainingSetRoom = max(
                0,
                repairSetCeiling(for: exercises[index], weekNumber: weekNumber) - exercises[index].sets
            )
            guard remainingSetRoom > 0 else { continue }

            var setsAvailable = remainingSetRoom
            while setsAvailable > 0 && remainingCapacity + 0.01 >= perSetGain {
                potentialGain += perSetGain
                remainingCapacity -= perSetGain
                setsAvailable -= 1
            }
        }

        return potentialGain
    }

    func priorityContributionPerSet(
        for exercise: WorkoutExerciseResponse,
        intent: MusclePriorityIntent
    ) -> Double {
        directPrioritySetContribution(
            exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget,
            intent: intent,
            sets: 1
        )
    }

    func canAccommodatePriorityRepair(
        _ exercises: [WorkoutExerciseResponse],
        targetFatigueCap: Int,
        targetSessionMinutes: Int?
    ) -> Bool {
        guard estimatedDayFatigue(for: exercises) <= targetFatigueCap else {
            return false
        }

        guard let targetSessionMinutes, targetSessionMinutes > 0 else {
            return true
        }

        return estimatedSessionMinutes(for: proceduralTrainingDay(from: exercises)) <= targetSessionMinutes + 3
    }

    func focusBudgetTrimCandidate(
        in exercises: [WorkoutExerciseResponse],
        boostingIndex: Int,
        focusArea: String
    ) -> Int? {
        let candidates = exercises.indices.filter { index in
            index != boostingIndex
            && exercises[index].sets > minimumSetFloor(for: exercises[index])
            && focusStimulusKind(
                exerciseName: exercises[index].exerciseName,
                muscleTarget: exercises[index].muscleTarget,
                focusArea: focusArea
            ) != .prime
        }
        return candidates.max { lhs, rhs in
            focusBudgetTrimScore(for: exercises[lhs], index: lhs, focusArea: focusArea)
                < focusBudgetTrimScore(for: exercises[rhs], index: rhs, focusArea: focusArea)
        }
    }

    func focusBudgetTrimScore(
        for exercise: WorkoutExerciseResponse,
        index: Int,
        focusArea: String
    ) -> Int {
        let kind = focusStimulusKind(
            exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget,
            focusArea: focusArea
        )
        var score = index
        switch kind {
        case .none: score += 20
        case .support: score += 10
        case .secondary: score += 0
        case .prime: return -1000
        }
        let role = proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
        switch role {
        case .accessory: score += 4
        case .core: score += 3
        case .secondary: score += 2
        case .anchor: score += 0
        }
        return score
    }

    func repairCandidateDayNumbers(
        for allocation: BlueprintPriorityAllocation,
        blueprint: ProgramBlueprint,
        dayStart: Int
    ) -> [Int] {
        let allocationAliases = Set(stimulusAreaAliases(for: allocation.area).map(normalizedPriorityText))

        let focusDays = blueprint.dayPlans.compactMap { plan -> Int? in
            guard let focusArea = plan.focusArea else { return nil }
            let focusAliases = Set(stimulusAreaAliases(for: focusArea).map(normalizedPriorityText))
            guard !allocationAliases.isDisjoint(with: focusAliases) else { return nil }
            return blueprintDayNumber(plan.dayIndex, dayStart: dayStart)
        }

        let supportDays = blueprint.dayPlans.compactMap { plan -> Int? in
            let supportAliases = Set(
                plan.supportAreas
                    .flatMap { stimulusAreaAliases(for: $0) }
                    .map(normalizedPriorityText)
            )
            guard !allocationAliases.isDisjoint(with: supportAliases) else { return nil }
            return blueprintDayNumber(plan.dayIndex, dayStart: dayStart)
        }

        var seen = Set<Int>()
        return (focusDays + supportDays).filter { dayNumber in
            guard !seen.contains(dayNumber) else { return false }
            seen.insert(dayNumber)
            return true
        }
    }

    func priorityIntent(for allocation: BlueprintPriorityAllocation) -> MusclePriorityIntent {
        MusclePriorityIntent(
            area: allocation.area,
            priorityLevel: allocation.priorityLevel,
            rank: 0,
            rationale: allocation.rationale,
            weeklyDayTarget: allocation.targetFrequency,
            weeklyExerciseTarget: allocation.targetExerciseSlots,
            weeklyDirectSetTarget: allocation.directSetTarget,
            weeklyStimulusTarget: allocation.weightedStimulusTarget,
            preferredStyles: allocation.preferredStyles,
            preferredMovementPatterns: allocation.preferredMovementPatterns,
            coverageKeywords: priorityCoverageKeywords(for: allocation.area),
            accessoryCatalog: priorityProfile(for: allocation.area).accessoryCatalog,
            volumeBias: allocation.volumeBias,
            directWorkBias: allocation.directWorkBias
        )
    }

    func repairSetCeiling(
        for exercise: WorkoutExerciseResponse,
        weekNumber: Int
    ) -> Int {
        switch proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget) {
        case .anchor:
            return weekNumber == 3 ? 6 : 5
        case .secondary:
            return 5
        case .accessory:
            return 5
        case .core:
            return 4
        }
    }

    func buildProceduralExercises(
        style: String,
        weekNumber: Int,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        targetFatigueCap: Int,
        targetSessionMinutes: Int,
        selectionContext: ExerciseSelectionContext,
        previousExercises: [WorkoutExerciseResponse]
    ) -> [WorkoutExerciseResponse] {
        let targetCount = weekNumber == 4 ? 5 : 6
        let focus = focusIntent?.area ?? ""

        var selected: [(name: String, target: String)] = []
        var used = Set<String>()

        let retained = retainedAnchorExercises(from: previousExercises, style: style)
            .filter { exercise in
                guard let focusIntent else { return true }
                return focusStimulusKind(
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget,
                    focusArea: focusIntent.area
                ) != .support
            }
            .prefix(2)
        for exercise in retained {
            let key = normalizeExerciseName(exercise.exerciseName)
            guard !used.contains(key) else { continue }
            used.insert(key)
            selected.append((exercise.exerciseName, exercise.muscleTarget))
        }
        let retainedCount = selected.count
        let lockedPrefixCount = focusIntent == nil ? retainedCount : 0

        let catalog = orderedExerciseCatalog(
            for: style,
            focusIntent: focusIntent,
            selectionContext: selectionContext
        )
        for candidate in catalog where selected.count < targetCount {
            let key = normalizeExerciseName(candidate.name)
            guard !used.contains(key) else { continue }
            used.insert(key)
            selected.append((candidate.name, candidate.target))
        }

        if selected.count < 5 {
            for candidate in orderedGenericExerciseCatalog(
                focusIntent: focusIntent,
                selectionContext: selectionContext
            ) where selected.count < 5 {
                let key = normalizeExerciseName(candidate.name)
                guard !used.contains(key) else { continue }
                used.insert(key)
                selected.append((candidate.name, candidate.target))
            }
        }

        if let focusIntent {
            selected = enforceFocusExerciseCoverage(
                selected,
                targetCount: focusExerciseTargetCount(for: focusIntent),
                focusIntent: focusIntent,
                selectionLimit: targetCount,
                protectedPrefixCount: retainedCount
            )
        }

        if !supportIntents.isEmpty {
            selected = enforceSupportExerciseCoverage(
                selected,
                focusIntent: focusIntent,
                supportIntents: supportIntents,
                selectionLimit: targetCount,
                protectedPrefixCount: retainedCount
            )
        }

        let arranged = arrangeProceduralSelection(
            Array(selected.prefix(targetCount)),
            lockedPrefixCount: lockedPrefixCount,
            focusIntent: focusIntent
        )

        let mapped = arranged.enumerated().map { index, item in
            let reps = proceduralRepRange(
                for: weekNumber,
                exerciseName: item.name,
                muscleTarget: item.target
            )

            return WorkoutExerciseResponse(
                exerciseName: item.name,
                sets: proceduralSets(for: weekNumber, exerciseName: item.name, muscleTarget: item.target),
                reps: reps,
                tempo: proceduralTempo(
                    for: weekNumber,
                    exerciseName: item.name,
                    muscleTarget: item.target,
                    reps: reps
                ),
                restSeconds: proceduralRestSeconds(for: item.name, muscleTarget: item.target),
                notes: proceduralExerciseNotes(
                    weekNumber: weekNumber,
                    exerciseName: item.name,
                    muscleTarget: item.target,
                    index: index,
                    focus: focus
                ),
                muscleTarget: item.target
            )
        }

        return balancedProceduralExercises(
            mapped,
            weekNumber: weekNumber,
            focusIntent: focusIntent,
            supportIntents: supportIntents,
            targetFatigueCap: targetFatigueCap,
            targetSessionMinutes: targetSessionMinutes
        )
    }

    func programMenuExercises(
        menu: [PreSelectedExercise],
        weekNumber: Int,
        style: String,
        focus: String,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        targetFatigueCap: Int,
        targetSessionMinutes: Int
    ) -> [WorkoutExerciseResponse] {
        let mapped = menu.enumerated().map { index, item in
            let reps = proceduralRepRange(
                for: weekNumber,
                exerciseName: item.exerciseName,
                muscleTarget: item.muscleTarget
            )
            return WorkoutExerciseResponse(
                exerciseName: item.exerciseName,
                sets: proceduralSets(for: weekNumber, exerciseName: item.exerciseName, muscleTarget: item.muscleTarget),
                reps: reps,
                tempo: proceduralTempo(
                    for: weekNumber,
                    exerciseName: item.exerciseName,
                    muscleTarget: item.muscleTarget,
                    reps: reps
                ),
                restSeconds: proceduralRestSeconds(for: item.exerciseName, muscleTarget: item.muscleTarget),
                notes: proceduralExerciseNotes(
                    weekNumber: weekNumber,
                    exerciseName: item.exerciseName,
                    muscleTarget: item.muscleTarget,
                    index: index,
                    focus: focus
                ),
                muscleTarget: item.muscleTarget
            )
        }

        return balancedProceduralExercises(
            mapped,
            weekNumber: weekNumber,
            focusIntent: focusIntent,
            supportIntents: supportIntents,
            targetFatigueCap: targetFatigueCap,
            targetSessionMinutes: targetSessionMinutes,
            menuLocked: true
        )
    }

    func exerciseCatalog(for style: String) -> [(name: String, target: String)] {
        switch style {
        case "Push":
            return [
                ("Incline Dumbbell Press", "Upper Chest"),
                ("Flat Barbell Bench Press", "Chest"),
                ("Machine Chest Press", "Chest"),
                ("Machine Incline Press", "Upper Chest"),
                ("Dumbbell Bench Press", "Chest"),
                ("Seated Dumbbell Shoulder Press", "Deltoids"),
                ("Cable Lateral Raise", "Lateral Deltoids"),
                ("Leaning Dumbbell Lateral Raise", "Lateral Deltoids"),
                ("Dip (Assisted or Weighted)", "Triceps"),
                ("Rope Triceps Pressdown", "Triceps"),
                ("Overhead Cable Triceps Extension", "Triceps"),
                ("V-Bar Pressdown", "Triceps")
            ]
        case "Pull":
            return [
                ("Pull-Up (Weighted or Assisted)", "Lats"),
                ("Lat Pulldown", "Lats"),
                ("Neutral-Grip Lat Pulldown", "Lats"),
                ("Chin-Up", "Lats"),
                ("Chest-Supported Row", "Upper Back"),
                ("Seated Cable Row", "Mid Back"),
                ("Single-Arm Dumbbell Row", "Lats"),
                ("Cable High Row", "Upper Back"),
                ("Reverse Pec Deck", "Rear Deltoids"),
                ("Face Pull", "Rear Deltoids"),
                ("Prone Incline Dumbbell Rear Delt Raise", "Rear Deltoids"),
                ("EZ-Bar Curl", "Biceps"),
                ("Incline Dumbbell Curl", "Biceps"),
                ("Bayesian Cable Curl", "Biceps")
            ]
        case "Lower":
            return [
                ("Back Squat", "Quads"),
                ("Front Squat", "Quads"),
                ("Romanian Deadlift", "Hamstrings"),
                ("Leg Press", "Quads"),
                ("Walking Lunge", "Glutes"),
                ("Reverse Lunge", "Glutes"),
                ("Leg Curl", "Hamstrings"),
                ("Seated Leg Curl", "Hamstrings"),
                ("Leg Extension", "Quads"),
                ("Hip Thrust", "Glutes"),
                ("Standing Calf Raise", "Calves"),
                ("Seated Calf Raise", "Calves")
            ]
        case "Upper":
            return [
                ("Incline Barbell Press", "Upper Chest"),
                ("Machine Incline Press", "Upper Chest"),
                ("Machine Shoulder Press", "Deltoids"),
                ("Chest-Supported Row", "Upper Back"),
                ("Lat Pulldown", "Lats"),
                ("Neutral-Grip Lat Pulldown", "Lats"),
                ("Cable Fly", "Chest"),
                ("Reverse Pec Deck", "Rear Deltoids"),
                ("Dumbbell Rear Delt Fly", "Rear Deltoids"),
                ("Cable Lateral Raise", "Lateral Deltoids"),
                ("Behind-the-Back Cable Lateral Raise", "Lateral Deltoids"),
                ("Cable Triceps Pressdown", "Triceps")
            ]
        case "Legs":
            return [
                ("Trap Bar Deadlift", "Posterior Chain"),
                ("Bulgarian Split Squat", "Quads/Glutes"),
                ("Hack Squat", "Quads"),
                ("Pendulum Squat", "Quads"),
                ("Seated Leg Curl", "Hamstrings"),
                ("Nordic Hamstring Curl", "Hamstrings"),
                ("Hip Thrust", "Glutes"),
                ("Single-Leg Hip Thrust", "Glutes"),
                ("Leg Extension", "Quads"),
                ("Seated Calf Raise", "Calves"),
                ("Cable Crunch", "Abs")
            ]
        case "Arms":
            return [
                ("EZ-Bar Curl", "Biceps"),
                ("Rope Triceps Pressdown", "Triceps"),
                ("Incline Dumbbell Curl", "Biceps"),
                ("Overhead Cable Triceps Extension", "Triceps"),
                ("Hammer Curl", "Brachialis"),
                ("Skull Crusher", "Triceps"),
                ("Cable Curl", "Biceps"),
                ("Spider Curl", "Biceps"),
                ("Bayesian Cable Curl", "Biceps"),
                ("V-Bar Pressdown", "Triceps"),
                ("Cable Kickback", "Triceps"),
                ("Concentration Curl", "Biceps")
            ]
        default:
            return genericExerciseCatalog()
        }
    }

    func genericExerciseCatalog() -> [(name: String, target: String)] {
        [
            ("Incline Dumbbell Press", "Chest"),
            ("Chest-Supported Row", "Upper Back"),
            ("Romanian Deadlift", "Hamstrings"),
            ("Leg Press", "Quads"),
            ("Lat Pulldown", "Lats"),
            ("Cable Lateral Raise", "Deltoids"),
            ("EZ-Bar Curl", "Biceps"),
            ("Cable Triceps Pressdown", "Triceps")
        ]
    }

    func coreExerciseCatalog() -> [(name: String, target: String)] {
        [
            ("Cable Crunch", "Abs"),
            ("Hanging Knee Raise", "Lower Abs"),
            ("Ab Wheel Rollout", "Anterior Core"),
            ("Pallof Press", "Obliques")
        ]
    }

    // EvidenceProfile.md DEL-001 / REST-001 [confidence: low-moderate / low-moderate]
    func proceduralSets(for weekNumber: Int, exerciseName: String, muscleTarget: String) -> Int {
        let phase = phasePrescription(for: weekNumber)
        switch proceduralExerciseRole(for: exerciseName, muscleTarget: muscleTarget) {
        case .anchor:
            return phase.anchorSets
        case .secondary:
            return phase.secondarySets
        case .accessory:
            return phase.accessorySets
        case .core:
            return phase.coreSets
        }
    }

    func polishedExerciseSets(
        rawSets: Int,
        exerciseName: String,
        muscleTarget: String,
        weekNumber: Int
    ) -> Int {
        guard rawSets >= 1 else {
            return proceduralSets(for: weekNumber, exerciseName: exerciseName, muscleTarget: muscleTarget)
        }
        return max(1, min(8, rawSets))
    }

    func proceduralRepRange(for weekNumber: Int, exerciseName: String, muscleTarget: String) -> String {
        let phase = phasePrescription(for: weekNumber)
        switch proceduralExerciseRole(for: exerciseName, muscleTarget: muscleTarget) {
        case .anchor:
            return phase.anchorRepRange
        case .secondary:
            return phase.secondaryRepRange
        case .accessory:
            return phase.accessoryRepRange
        case .core:
            return phase.coreRepRange
        }
    }

    func polishedExerciseRepRange(
        rawReps: String,
        exerciseName: String,
        muscleTarget: String,
        weekNumber: Int
    ) -> String {
        let cleaned = rawReps.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            return cleaned
        }
        return proceduralRepRange(for: weekNumber, exerciseName: exerciseName, muscleTarget: muscleTarget)
    }

    func proceduralRestSeconds(for exerciseName: String, muscleTarget: String) -> Int {
        let nameText = normalizedPriorityText(exerciseName)
        let role = proceduralExerciseRole(for: exerciseName, muscleTarget: muscleTarget)
        switch role {
        case .anchor:
            return evidenceProfile.restSecondsByRole[role.rawValue] ?? 150
        case .secondary:
            if containsAny(nameText, keywords: ["row", "pulldown", "pull up", "pull-up", "bench", "press", "squat", "deadlift", "romanian deadlift"]) {
                return 120
            }
            return 105
        case .accessory:
            if isSupportOrCorrectivePattern(nameText) {
                return 60
            }
            return containsAny(nameText, keywords: ["split squat", "walking lunge", "leg press", "hip thrust"]) ? 90 : 75
        case .core:
            return 60
        }
    }

    func polishedExerciseRestSeconds(
        rawRestSeconds: Int,
        exerciseName: String,
        muscleTarget: String,
        weekNumber: Int
    ) -> Int {
        guard rawRestSeconds >= 30 else {
            return proceduralRestSeconds(for: exerciseName, muscleTarget: muscleTarget)
        }
        return max(30, min(240, rawRestSeconds))
    }

    // EvidenceProfile.md TEMPO-001 [confidence: low]
    func proceduralTempo(
        for weekNumber: Int,
        exerciseName: String,
        muscleTarget: String,
        reps: String
    ) -> String {
        guard requiresExplicitTempo(
            exerciseName: exerciseName,
            muscleTarget: muscleTarget,
            reps: reps
        ) else {
            return ""
        }

        let nameText = normalizedPriorityText(exerciseName)
        switch proceduralExerciseRole(for: exerciseName, muscleTarget: muscleTarget) {
        case .anchor:
            return weekNumber == 3 ? "2-0-X-0" : "3-0-1-0"
        case .secondary:
            return weekNumber == 3 ? "2-0-X-0" : "2-0-1-0"
        case .accessory:
            return isSupportOrCorrectivePattern(nameText)
                ? "2-1-2-1"
                : (weekNumber == 3 ? "2-0-1-0" : "2-1-1-0")
        case .core:
            return "2-1-2-1"
        }
    }

    func phasePrescription(for weekNumber: Int) -> EvidencePhasePrescription {
        evidenceProfile.phasePrescriptionsByWeek[weekNumber]
            ?? evidenceProfile.phasePrescriptionsByWeek[1]
            ?? EvidencePhasePrescription(
                anchorSets: 4,
                secondarySets: 3,
                accessorySets: 3,
                coreSets: 3,
                anchorRepRange: "6-10",
                secondaryRepRange: "8-12",
                accessoryRepRange: "10-14",
                coreRepRange: "10-15"
            )
    }

    func polishedExerciseTempo(
        rawTempo: String,
        exerciseName: String,
        muscleTarget: String,
        weekNumber: Int,
        reps: String
    ) -> String {
        guard requiresExplicitTempo(
            exerciseName: exerciseName,
            muscleTarget: muscleTarget,
            reps: reps
        ) else {
            return ""
        }

        if let normalized = normalizedTempo(rawTempo) {
            return normalized
        }
        return proceduralTempo(
            for: weekNumber,
            exerciseName: exerciseName,
            muscleTarget: muscleTarget,
            reps: reps
        )
    }

    func normalizedTempo(_ rawTempo: String) -> String? {
        let trimmed = rawTempo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let upper = trimmed.uppercased().replacingOccurrences(of: " ", with: "")
        let parts: [String]
        if upper.contains("-") {
            parts = upper.split(separator: "-").map(String.init)
        } else if upper.count == 4 {
            parts = upper.map { String($0) }
        } else {
            return nil
        }

        guard parts.count == 4 else { return nil }
        let validCharacters = Set("0123456789X")
        guard parts.allSatisfy({ part in
            part.count == 1 && part.allSatisfy(validCharacters.contains)
        }) else {
            return nil
        }

        return parts.joined(separator: "-")
    }

    func proceduralExerciseNotes(
        weekNumber: Int,
        exerciseName: String,
        muscleTarget: String,
        index: Int,
        focus: String
    ) -> String {
        let technique = techniqueCue(for: muscleTarget, exerciseName: exerciseName, index: index)
        let progression = progressionCue(for: weekNumber, exerciseName: exerciseName, muscleTarget: muscleTarget)
        let intent = intentCue(muscleTarget: muscleTarget, focus: focus, exerciseName: exerciseName)
        return "\(technique) \(progression) \(intent)"
    }

    func proceduralMuscleGroups(for style: String) -> String {
        switch style {
        case "Push": return "Chest, Shoulders, Triceps"
        case "Pull": return "Back, Rear Delts, Biceps"
        case "Lower", "Legs": return "Quads, Hamstrings, Glutes"
        case "Upper": return "Chest, Back, Shoulders, Arms"
        case "Arms": return "Biceps, Triceps, Deltoids"
        default: return "Primary Training"
        }
    }

    func proceduralDayNotes(
        style: String,
        weekNumber: Int,
        exercises: [WorkoutExerciseResponse],
        focus: String,
        focusIntent: MusclePriorityIntent? = nil,
        blueprint: ProgramBlueprint? = nil
    ) -> String {
        let phase = phaseSentence(for: weekNumber)

        var purposeLine: String
        if let intent = focusIntent, !intent.rationale.isEmpty {
            purposeLine = "\(style) session with \(focus.lowercased()) emphasis — \(intent.rationale.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))."
        } else if !focus.isEmpty {
            purposeLine = "\(style) session with \(focus.lowercased()) emphasis."
        } else {
            purposeLine = "\(style) session."
        }

        let warmup = enrichedWarmupCue(style: style, exercises: exercises, blueprint: blueprint)
        let posturalLine = posturalPrepCue(style: style, blueprint: blueprint, exercises: exercises)

        var parts = [purposeLine, phase, "Warm-up: \(warmup)"]
        if !posturalLine.isEmpty {
            parts.append("Prep: \(posturalLine)")
        }
        return parts.joined(separator: " ")
    }

    func enrichedWarmupCue(
        style: String,
        exercises: [WorkoutExerciseResponse],
        blueprint: ProgramBlueprint?
    ) -> String {
        let anchorNames = exercises.prefix(2).map(\.exerciseName)
        let anchorTargets = Set(exercises.prefix(3).map { normalizedPriorityText($0.muscleTarget) })

        var items: [String] = []

        if anchorTargets.contains(where: { containsPriorityPhrase(in: $0, keywords: ["quad", "glute", "hamstring", "legs", "posterior chain"]) }) {
            items.append("5-7 min bike or incline walk")
        } else {
            items.append("3-5 min light cardio")
        }

        if anchorTargets.contains(where: { containsPriorityPhrase(in: $0, keywords: ["chest", "upper chest", "pec", "anterior deltoid"]) }) {
            items.append("band pull-aparts and pec stretch")
        }
        if anchorTargets.contains(where: { containsPriorityPhrase(in: $0, keywords: ["delt", "deltoid", "shoulder", "lateral deltoid"]) }) {
            items.append("shoulder external rotation and scapular activation")
        }
        if anchorTargets.contains(where: { containsPriorityPhrase(in: $0, keywords: ["lat", "back", "upper back", "mid back"]) }) {
            items.append("lat stretch and scapular setting drills")
        }
        if anchorTargets.contains(where: { containsPriorityPhrase(in: $0, keywords: ["quad", "glute", "hamstring"]) }) {
            items.append("hip flexor stretch and ankle dorsiflexion drills")
        }

        if items.count <= 1 {
            items.append("joint prep for primary movers")
        }

        let rampTarget = anchorNames.first ?? "your first compound"
        items.append("then 2-3 progressive ramp sets into \(rampTarget)")

        return items.joined(separator: ", ") + "."
    }

    func posturalPrepCue(
        style: String,
        blueprint: ProgramBlueprint?,
        exercises: [WorkoutExerciseResponse]
    ) -> String {
        guard let blueprint else { return "" }
        var cues: [String] = []

        let posturalText = normalizedPriorityText(blueprint.posturalFocus)
        let injuryText = normalizedPriorityText(blueprint.injuryRiskFocus)

        if containsPriorityPhrase(in: posturalText, keywords: ["thoracic", "kyphosis", "upper back"]) {
            let lowStyle = style.lowercased()
            if lowStyle == "push" || lowStyle == "upper" {
                cues.append("thoracic extension work before pressing")
            }
        }
        if containsPriorityPhrase(in: posturalText, keywords: ["anterior pelvic tilt", "hip flexor"]) {
            let lowStyle = style.lowercased()
            if lowStyle == "lower" || lowStyle == "legs" {
                cues.append("hip flexor stretch and glute activation")
            }
        }
        if containsPriorityPhrase(in: injuryText, keywords: ["shoulder", "rotator cuff", "impingement"]) {
            let lowStyle = style.lowercased()
            if lowStyle == "push" || lowStyle == "upper" || lowStyle == "pull" {
                cues.append("rotator cuff activation between warm-up sets")
            }
        }
        if containsPriorityPhrase(in: injuryText, keywords: ["lower back", "lumbar", "disc"]) {
            let lowStyle = style.lowercased()
            if lowStyle == "lower" || lowStyle == "legs" || lowStyle == "pull" {
                cues.append("brace practice with bodyweight hip hinges")
            }
        }

        return cues.joined(separator: ", ")
    }

    func inferredDayStyle(dayName: String, muscleGroups: String) -> String? {
        let nameText = normalizedPriorityText(dayName)
        let groupText = normalizedPriorityText(muscleGroups)

        if containsPriorityPhrase(in: nameText, keywords: ["push"]) { return "Push" }
        if containsPriorityPhrase(in: nameText, keywords: ["pull"]) { return "Pull" }
        if containsPriorityPhrase(in: nameText, keywords: ["lower"]) { return "Lower" }
        if containsPriorityPhrase(in: nameText, keywords: ["legs", "leg day"]) { return "Legs" }
        if containsPriorityPhrase(in: nameText, keywords: ["arms", "arm day"]) { return "Arms" }
        if containsPriorityPhrase(in: nameText, keywords: ["upper"]) { return "Upper" }

        let hasPushGroups = containsPriorityPhrase(
            in: groupText,
            keywords: ["chest", "upper chest", "pec", "triceps", "anterior deltoids", "lateral deltoids", "shoulders"]
        )
        let hasPullGroups = containsPriorityPhrase(
            in: groupText,
            keywords: ["back", "lats", "upper back", "mid back", "rear deltoids", "posterior deltoids", "biceps"]
        )
        let hasLowerGroups = containsPriorityPhrase(
            in: groupText,
            keywords: ["quads", "hamstrings", "glutes", "calves", "posterior chain"]
        )
        let hasArmGroups = containsPriorityPhrase(
            in: groupText,
            keywords: ["biceps", "triceps", "brachialis", "forearms"]
        )

        if hasPushGroups && hasPullGroups && !hasLowerGroups { return "Upper" }
        if hasLowerGroups {
            return containsPriorityPhrase(in: groupText, keywords: ["posterior chain", "hamstrings", "glutes"]) ? "Lower" : "Legs"
        }
        if hasPullGroups { return "Pull" }
        if hasPushGroups { return "Push" }
        if hasArmGroups { return "Arms" }
        return nil
    }

    func canonicalTrainingStyle(_ style: String) -> String {
        switch style.lowercased() {
        case "legs", "lower":
            return "Lower"
        case "push":
            return "Push"
        case "pull":
            return "Pull"
        case "upper":
            return "Upper"
        case "arms":
            return "Arms"
        case "recovery":
            return "Recovery"
        default:
            return style
        }
    }

}
