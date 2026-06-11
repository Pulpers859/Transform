import Foundation

extension ClaudeService {
    // MARK: - Local Fallback Generation (Always-valid output path)

    func validatedProceduralWeekOneProgram(
        from analysisResult: BodyAnalysisResult,
        trainingIntent: TrainingIntentPlan,
        blueprint: ProgramBlueprint,
        diagnostic: String = ""
    ) throws -> WorkoutProgramResponse {
        let fallback = buildProceduralWeekOneProgram(
            from: analysisResult,
            trainingIntent: trainingIntent,
            blueprint: blueprint,
            diagnostic: diagnostic
        )
        let issues = validateProgramResponse(fallback, blueprint: blueprint)
        guard issues.isEmpty || shouldAcceptAIOutput(despite: issues) else {
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
            diagnostic: diagnostic
        )
        let issues = validateWeekResponse(
            fallback,
            dayStart: dayStart,
            dayEnd: dayEnd,
            previousWeekDays: previousWeekDays,
            blueprint: blueprint
        )
        guard issues.isEmpty || shouldAcceptAIOutput(despite: issues) else {
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
            diagnostic: diagnostic
        )

        let trainingDays = generatedWeek.days.filter { !$0.isRestDay }.count
        let focusLabel = trainingIntent.priorities.map(\.area).prefix(3).joined(separator: ", ")
        let summaryFocus = focusLabel.isEmpty ? "" : " Focus areas: \(focusLabel)."
        let diagnosticLine = diagnostic.isEmpty ? "" : "\n\nWhy fallback fired: \(truncatedDiagnostic(diagnostic))"

        return WorkoutProgramResponse(
            programName: programName,
            programSummary: withSourceLabel(
                "Week 1 used analysis-driven progression logic to build complete programming.\(summaryFocus)\(diagnosticLine)",
                sourceLabel: fallbackSourceLabel
            ),
            splitType: splitRecommendation,
            daysPerWeek: trainingDays,
            days: generatedWeek.days
        )
    }

    func truncatedDiagnostic(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 400 { return trimmed }
        return String(trimmed.prefix(400)) + "…"
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
            let styleKey = canonicalTrainingStyle(style)
            let styleUsage = previousUsageByStyle[styleKey, default: 0]
            let previousExercises: [WorkoutExerciseResponse] = previousExercisesByStyle[styleKey].flatMap { groupedExercises in
                guard styleUsage < groupedExercises.count else { return nil }
                return groupedExercises[styleUsage]
            } ?? [WorkoutExerciseResponse]()
            previousUsageByStyle[styleKey] = styleUsage + 1

            let exercises = buildProceduralExercises(
                style: style,
                weekNumber: weekNumber,
                focusIntent: focusIntent,
                supportIntents: supportIntents,
                targetFatigueCap: plan.targetFatigueCap,
                previousExercises: previousExercises
            )

            let dayName = focus.isEmpty ? "\(style) Session" : "\(style) - \(focus) Focus"
            let groups = proceduralMuscleGroups(for: style)
            let notes = proceduralDayNotes(style: style, weekNumber: weekNumber, exercises: exercises, focus: focus)

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
            dayStart: dayStart
        )

        let diagnosticLine = diagnostic.isEmpty ? "" : "\n\nWhy fallback fired: \(truncatedDiagnostic(diagnostic))"
        let summary = "Week \(weekNumber) for \(programName) (\(splitType)) applies phase-aware progression and fatigue-managed session design.\(diagnosticLine)"
        return WorkoutWeekResponse(
            weekSummary: withSourceLabel(summary, sourceLabel: fallbackSourceLabel),
            days: days
        )
    }

    func repairedProceduralDays(
        _ days: [WorkoutDayResponse],
        weekNumber: Int,
        blueprint: ProgramBlueprint,
        dayStart: Int
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
                var remainingShortfall = Int(ceil(allocation.directSetTarget - coverage.directSets - 0.01))
                guard remainingShortfall > 0 else { continue }

                for dayNumber in repairCandidateDayNumbers(
                    for: allocation,
                    blueprint: blueprint,
                    dayStart: dayStart
                ) {
                    guard remainingShortfall > 0,
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
                    let currentDirectSets = directSets(on: day, forFocusArea: allocation.area)
                    var remainingSessionRoom = Int(floor(allowedCap - currentDirectSets + 0.01))
                    guard remainingSessionRoom > 0 else { continue }

                    let targetFatigueCap = relativeBlueprintDayIndex(for: dayNumber, dayStart: dayStart)
                        .flatMap { relativeDayIndex in
                            blueprint.dayPlans.first(where: { $0.dayIndex == relativeDayIndex })?.targetFatigueCap
                        }
                        ?? maxDailyFatigueThreshold(for: repaired, dayNumber: dayNumber)
                    var exercises = day.exercises
                    var dayChanged = false

                    let matchingIndices = exercises.indices.filter { index in
                        directPrioritySetContribution(
                            exerciseName: exercises[index].exerciseName,
                            muscleTarget: exercises[index].muscleTarget,
                            intent: priorityIntent(for: allocation),
                            sets: exercises[index].sets
                        ) > 0
                    }

                    for exerciseIndex in matchingIndices {
                        while remainingShortfall > 0,
                              remainingSessionRoom > 0,
                              exercises[exerciseIndex].sets < repairSetCeiling(for: exercises[exerciseIndex], weekNumber: weekNumber) {
                            let updatedExercise = exerciseResponse(
                                exercises[exerciseIndex],
                                withSets: exercises[exerciseIndex].sets + 1
                            )
                            var updatedExercises = exercises
                            updatedExercises[exerciseIndex] = updatedExercise

                            if estimatedDayFatigue(for: updatedExercises) > targetFatigueCap {
                                break
                            }

                            exercises = updatedExercises
                            remainingShortfall -= 1
                            remainingSessionRoom -= 1
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
        let lockedPrefixCount = focusIntent == nil ? selected.count : 0

        let catalog = orderedExerciseCatalog(for: style, focusIntent: focusIntent)
        for candidate in catalog where selected.count < targetCount {
            let key = normalizeExerciseName(candidate.name)
            guard !used.contains(key) else { continue }
            used.insert(key)
            selected.append((candidate.name, candidate.target))
        }

        if selected.count < 5 {
            for candidate in orderedGenericExerciseCatalog(focusIntent: focusIntent) where selected.count < 5 {
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
                selectionLimit: targetCount
            )
        }

        if !supportIntents.isEmpty {
            selected = enforceSupportExerciseCoverage(
                selected,
                focusIntent: focusIntent,
                supportIntents: supportIntents,
                selectionLimit: targetCount
            )
        }

        let arranged = arrangeProceduralSelection(
            Array(selected.prefix(8)),
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
            targetFatigueCap: targetFatigueCap
        )
    }

    func exerciseCatalog(for style: String) -> [(name: String, target: String)] {
        switch style {
        case "Push":
            return [
                ("Incline Dumbbell Press", "Upper Chest"),
                ("Flat Barbell Bench Press", "Chest"),
                ("Machine Chest Press", "Chest"),
                ("Seated Dumbbell Shoulder Press", "Deltoids"),
                ("Cable Lateral Raise", "Lateral Deltoids"),
                ("Dip (Assisted or Weighted)", "Triceps"),
                ("Rope Triceps Pressdown", "Triceps"),
                ("Overhead Cable Triceps Extension", "Triceps")
            ]
        case "Pull":
            return [
                ("Pull-Up (Weighted or Assisted)", "Lats"),
                ("Lat Pulldown", "Lats"),
                ("Chest-Supported Row", "Upper Back"),
                ("Seated Cable Row", "Mid Back"),
                ("Single-Arm Dumbbell Row", "Lats"),
                ("Reverse Pec Deck", "Rear Deltoids"),
                ("Face Pull", "Rear Deltoids"),
                ("EZ-Bar Curl", "Biceps"),
                ("Incline Dumbbell Curl", "Biceps")
            ]
        case "Lower":
            return [
                ("Back Squat", "Quads"),
                ("Front Squat", "Quads"),
                ("Romanian Deadlift", "Hamstrings"),
                ("Leg Press", "Quads"),
                ("Walking Lunge", "Glutes"),
                ("Leg Curl", "Hamstrings"),
                ("Leg Extension", "Quads"),
                ("Standing Calf Raise", "Calves")
            ]
        case "Upper":
            return [
                ("Incline Barbell Press", "Upper Chest"),
                ("Machine Shoulder Press", "Deltoids"),
                ("Chest-Supported Row", "Upper Back"),
                ("Lat Pulldown", "Lats"),
                ("Cable Fly", "Chest"),
                ("Cable Lateral Raise", "Lateral Deltoids"),
                ("Hammer Curl", "Biceps"),
                ("Cable Triceps Pressdown", "Triceps")
            ]
        case "Legs":
            return [
                ("Trap Bar Deadlift", "Posterior Chain"),
                ("Bulgarian Split Squat", "Quads/Glutes"),
                ("Hack Squat", "Quads"),
                ("Seated Leg Curl", "Hamstrings"),
                ("Hip Thrust", "Glutes"),
                ("Leg Extension", "Quads"),
                ("Seated Calf Raise", "Calves"),
                ("Cable Crunch", "Abs")
            ]
        case "Arms":
            return [
                ("EZ-Bar Curl", "Biceps"),
                ("Incline Dumbbell Curl", "Biceps"),
                ("Hammer Curl", "Brachialis"),
                ("Cable Curl", "Biceps"),
                ("Close-Grip Bench Press", "Triceps"),
                ("Skull Crusher", "Triceps"),
                ("Rope Triceps Pressdown", "Triceps"),
                ("Overhead Cable Triceps Extension", "Triceps")
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
        focus: String
    ) -> String {
        let phase: String
        switch weekNumber {
        case 2: phase = "Volume build (RPE 7-8)."
        case 3: phase = "Peak week (RPE 8-9)."
        case 4: phase = "Deload week with reduced volume."
        default: phase = "Baseline week (RPE 6-7)."
        }

        let primaryLift = exercises.first?.exerciseName ?? "your first compound movement"
        let warmup = warmupCue(for: style, primaryLift: primaryLift)
        let mobility = mobilityCue(for: style)
        let focusLine = focus.isEmpty ? "" : " Emphasis today: \(focus.lowercased())."
        return "\(style) session. \(phase) Warm-up: \(warmup) Mobility/activation: \(mobility)\(focusLine)"
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
