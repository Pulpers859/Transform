import Foundation

extension ClaudeService {
    // MARK: - Parsing and Cleanup

    func decodeJSONPayload<T: Decodable>(_ type: T.Type, from responseText: String) throws -> T {
        let cleaned = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidates = jsonCandidates(from: cleaned)
        var decodeError: Error?

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                decodeError = error
            }
        }

        if let decodeError {
            let short = String(String(describing: decodeError).prefix(180))
            throw ClaudeError.parseError("Tool payload decode failure: \(short)")
        }

        throw ClaudeError.parseError("Tool payload decode failure: no decodable JSON candidate found")
    }

    func jsonCandidates(from raw: String) -> [String] {
        guard !raw.isEmpty else { return [] }

        var values: [String] = []

        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !values.contains(trimmed) else { return }
            values.append(trimmed)
        }

        append(raw)
        append(ClaudeService.extractJSON(from: raw))

        if !raw.hasPrefix("{") && raw.contains(":") {
            append("{\(raw)")
            append("{\(raw)}")
        }

        if raw.hasPrefix("{") && !raw.hasSuffix("}") {
            append("\(raw)}")
        }

        return values
    }

    func sanitizeProgramResponse(_ program: WorkoutProgramResponse) -> WorkoutProgramResponse {
        WorkoutProgramResponse(
            programName: program.programName.trimmedOr(default: "Custom Program"),
            programSummary: program.programSummary.trimmedOr(default: "4-week hypertrophy mesocycle."),
            splitType: program.splitType.trimmedOr(default: "Custom Split"),
            daysPerWeek: max(1, min(7, program.daysPerWeek)),
            days: sanitizeDays(program.days)
        )
    }

    func sanitizeWeekResponse(_ week: WorkoutWeekResponse) -> WorkoutWeekResponse {
        WorkoutWeekResponse(
            weekSummary: week.weekSummary.trimmedOr(default: "Weekly progression update."),
            days: sanitizeDays(week.days)
        )
    }

    func sanitizeDays(_ days: [WorkoutDayResponse]) -> [WorkoutDayResponse] {
        days
            .sorted { $0.dayNumber < $1.dayNumber }
            .map { (day: WorkoutDayResponse) -> WorkoutDayResponse in
                autoreleasepool {
                    let weekNumber: Int = ((day.dayNumber - 1) / 7) + 1
                    let cleanedExercises: [WorkoutExerciseResponse] = day.exercises.enumerated().map { (entry: (offset: Int, element: WorkoutExerciseResponse)) -> WorkoutExerciseResponse in
                        let index: Int = entry.offset
                        let exercise: WorkoutExerciseResponse = entry.element
                        let cleanedName = canonicalExerciseName(
                            exercise.exerciseName,
                            muscleTarget: exercise.muscleTarget
                        )
                        let cleanedTarget = exercise.muscleTarget.trimmedOr(default: "Primary Target")
                        let cleanedNotes = polishedExerciseNotes(
                            rawNotes: exercise.notes,
                            exerciseName: cleanedName,
                            muscleTarget: cleanedTarget,
                            weekNumber: weekNumber,
                            exerciseIndex: index
                        )
                        let cleanedSets = polishedExerciseSets(
                            rawSets: exercise.sets,
                            exerciseName: cleanedName,
                            muscleTarget: cleanedTarget,
                            weekNumber: weekNumber
                        )
                        let cleanedReps = polishedExerciseRepRange(
                            rawReps: exercise.reps,
                            exerciseName: cleanedName,
                            muscleTarget: cleanedTarget,
                            weekNumber: weekNumber
                        )
                        let cleanedTempo = polishedExerciseTempo(
                            rawTempo: exercise.tempo,
                            exerciseName: cleanedName,
                            muscleTarget: cleanedTarget,
                            weekNumber: weekNumber,
                            reps: cleanedReps
                        )
                        let cleanedRestSeconds = polishedExerciseRestSeconds(
                            rawRestSeconds: exercise.restSeconds,
                            exerciseName: cleanedName,
                            muscleTarget: cleanedTarget,
                            weekNumber: weekNumber
                        )

                        return WorkoutExerciseResponse(
                            exerciseName: cleanedName,
                            sets: cleanedSets,
                            reps: cleanedReps,
                            tempo: cleanedTempo,
                            restSeconds: cleanedRestSeconds,
                            notes: cleanedNotes,
                            muscleTarget: cleanedTarget
                        )
                    }

                    let dayStyle = inferredDayStyle(dayName: day.dayName, muscleGroups: day.muscleGroups)
                    let cleanedDayNotes: String
                    if day.isRestDay {
                        cleanedDayNotes = day.notes.trimmedOr(default: "Active recovery, mobility work, and light cardio.")
                    } else {
                        cleanedDayNotes = polishedTrainingDayNotes(
                            rawNotes: day.notes,
                            dayStyle: dayStyle,
                            weekNumber: weekNumber,
                            exercises: cleanedExercises
                        )
                    }

                    return WorkoutDayResponse(
                        dayNumber: day.dayNumber,
                        dayName: day.dayName.trimmedOr(default: "Day \(day.dayNumber)"),
                        muscleGroups: day.muscleGroups.trimmedOr(default: day.isRestDay ? "Recovery" : "Primary Training"),
                        isRestDay: day.isRestDay,
                        notes: cleanedDayNotes,
                        exercises: day.isRestDay ? [WorkoutExerciseResponse]() : cleanedExercises
                    )
                }
            }
    }

    // MARK: - Validation

    func validateProgramResponse(_ program: WorkoutProgramResponse, blueprint: ProgramBlueprint) -> [String] {
        var issues: [String] = []
        let days = program.days

        issues.append(contentsOf: validateDaySet(days, dayStart: 1, dayEnd: 7))
        issues.append(contentsOf: validateBlueprint(days: days, blueprint: blueprint, dayStart: 1))

        if program.daysPerWeek < 4 || program.daysPerWeek > 6 {
            issues.append("daysPerWeek should be between 4 and 6.")
        }

        if program.programName.trimmedOr(default: "").isEmpty {
            issues.append("programName is empty.")
        }

        if program.programSummary.trimmedOr(default: "").isEmpty {
            issues.append("programSummary is empty.")
        }

        return issues
    }

    func validateWeekResponse(
        _ week: WorkoutWeekResponse,
        dayStart: Int,
        dayEnd: Int,
        previousWeekDays: [WorkoutDayResponse]?,
        blueprint: ProgramBlueprint
    ) -> [String] {
        var issues: [String] = []
        let days = week.days

        issues.append(contentsOf: validateDaySet(days, dayStart: dayStart, dayEnd: dayEnd))
        issues.append(contentsOf: validateBlueprint(days: days, blueprint: blueprint, dayStart: dayStart))

        if week.weekSummary.trimmedOr(default: "").isEmpty {
            issues.append("weekSummary is empty.")
        }

        if let previousWeekDays {
            let continuityIssues = validateContinuity(currentWeekDays: days, previousWeekDays: previousWeekDays)
            issues.append(contentsOf: continuityIssues)
        }

        return issues
    }

    func validateBlueprint(
        days: [WorkoutDayResponse],
        blueprint: ProgramBlueprint,
        dayStart: Int
    ) -> [String] {
        guard !blueprint.priorityAllocations.isEmpty else { return [] }

        var issues: [String] = []
        let trainingDayCount = days.filter { !$0.isRestDay }.count
        let stimulusReport = buildWeekStimulusReport(from: days)

        if trainingDayCount != blueprint.weeklyTrainingDays {
            issues.append(
                "Blueprint calls for \(blueprint.weeklyTrainingDays) training days, but the generated week has \(trainingDayCount)."
            )
        }

        for allocation in blueprint.priorityAllocations {
            let coverage = priorityCoverage(for: allocation, stimulusReport: stimulusReport)
            let peakDirectSession = peakDirectSession(for: allocation, stimulusReport: stimulusReport)
            let frequencyMiss = coverage.dayMatches < allocation.targetFrequency
            let directSetMiss = coverage.directSets + 1.0 < allocation.directSetTarget
            let slotMiss = coverage.exerciseMatches + 1 < allocation.targetExerciseSlots
                && coverage.directSets + 0.5 < allocation.directSetTarget
            let weightedStimulusMiss = coverage.weightedStimulus + 1.0 < allocation.weightedStimulusTarget
                && directSetMiss

            if frequencyMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' missed its frequency target (\(coverage.dayMatches)/\(allocation.targetFrequency) targeted days)."
                )
            }
            if directSetMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' missed its direct-set target (\(formatStimulusValue(coverage.directSets))/\(formatStimulusValue(allocation.directSetTarget)))."
                )
            }
            if slotMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' undershot its targeted exercise-slot goal (\(coverage.exerciseMatches)/\(allocation.targetExerciseSlots)), but may still be acceptable if the direct stimulus is strong."
                )
            }
            if weightedStimulusMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' undershot its weighted stimulus target (\(formatStimulusValue(coverage.weightedStimulus))/\(formatStimulusValue(allocation.weightedStimulusTarget)))."
                )
            }

            if coverage.peakSessionFatigue > maxSessionFatigue(for: allocation) {
                issues.append(
                    "Blueprint priority '\(coverage.label)' is concentrated into overly fatiguing sessions (peak fatigue \(coverage.peakSessionFatigue), limit \(maxSessionFatigue(for: allocation))). Spread the work more intelligently."
                )
            }

            if let peakDirectSession {
                let allowedCap = allowedPerSessionDirectSetCap(
                    for: allocation,
                    dayNumber: peakDirectSession.dayNumber,
                    blueprint: blueprint,
                    dayStart: dayStart
                )
                if peakDirectSession.directSets > allowedCap + 0.01 {
                    // EvidenceProfile.md FAT-001 / VOL-001 [confidence: low-moderate / moderate]
                    let capContext = isBlueprintFocusDay(
                        dayNumber: peakDirectSession.dayNumber,
                        for: allocation,
                        blueprint: blueprint,
                        dayStart: dayStart
                    ) ? "focus-day" : "per-session"
                    issues.append(
                        "Blueprint priority '\(coverage.label)' exceeds its \(capContext) direct-set cap on day \(peakDirectSession.dayNumber) (\(formatStimulusValue(peakDirectSession.directSets)) vs \(formatStimulusValue(allowedCap))). Distribute the work more intelligently across the week."
                    )
                }
            }
        }

        issues.append(contentsOf: validateDayPlans(days: days, blueprint: blueprint, dayStart: dayStart))

        for (dayNumber, fatigue) in stimulusReport.dailyFatigue where fatigue > maxDailyFatigueThreshold(for: days, dayNumber: dayNumber) {
            issues.append(
                "Day \(dayNumber) carries too much total fatigue load for a hypertrophy week (\(fatigue)). Reduce redundant compounds or redistribute work."
            )
        }

        return issues
    }

    func validateDaySet(_ days: [WorkoutDayResponse], dayStart: Int, dayEnd: Int) -> [String] {
        var issues: [String] = []

        if days.count != 7 {
            issues.append("Must contain exactly 7 days.")
        }

        let expected = Set(dayStart...dayEnd)
        let actual = Set(days.map { $0.dayNumber })
        if actual != expected {
            issues.append("dayNumber values must exactly match \(dayStart)-\(dayEnd).")
        }

        let duplicates = Dictionary(grouping: days, by: { $0.dayNumber }).filter { $0.value.count > 1 }.keys
        if !duplicates.isEmpty {
            issues.append("Duplicate dayNumber values found.")
        }

        let trainingDays = days.filter { !$0.isRestDay }
        let restDays = days.filter { $0.isRestDay }

        if trainingDays.count < 4 || trainingDays.count > 6 {
            issues.append("Training days must be between 4 and 6.")
        }

        if restDays.count < 1 || restDays.count > 3 {
            issues.append("Rest days must be between 1 and 3.")
        }

        var totalTrainingExercises = 0

        for day in trainingDays {
            if day.exercises.count < 5 || day.exercises.count > 8 {
                issues.append("Day \(day.dayNumber) must have 5-8 exercises.")
            }
            if day.dayName.trimmedOr(default: "").isEmpty {
                issues.append("Day \(day.dayNumber) has empty dayName.")
            }
            if isEmptyOrTooShortSessionNote(day.notes) {
                issues.append("Day \(day.dayNumber) session notes are empty or too short — rewrite with real coaching content tied to the analysis.")
            }

            totalTrainingExercises += day.exercises.count

            for exercise in day.exercises {
                if exercise.exerciseName.trimmedOr(default: "").isEmpty {
                    issues.append("Day \(day.dayNumber) has an exercise with empty exerciseName.")
                }
                if exercise.sets < 1 || exercise.sets > 8 {
                    issues.append("Day \(day.dayNumber) exercise \(exercise.exerciseName) has invalid sets.")
                }
                if exercise.restSeconds < 30 || exercise.restSeconds > 240 {
                    issues.append("Day \(day.dayNumber) exercise \(exercise.exerciseName) has invalid restSeconds.")
                }
                if exercise.reps.trimmedOr(default: "").isEmpty {
                    issues.append("Day \(day.dayNumber) exercise \(exercise.exerciseName) has empty reps.")
                }
                if isEmptyOrTooShortInsight(exercise.notes) {
                    issues.append("Day \(day.dayNumber) exercise \(exercise.exerciseName) notes are empty or too short.")
                }
            }

            issues.append(contentsOf: validatePrescriptionUniformity(on: day))
        }

        if totalTrainingExercises < 20 {
            issues.append("Total training exercises are too low.")
        }

        for day in restDays where !day.exercises.isEmpty {
            issues.append("Day \(day.dayNumber) is rest day but has exercises.")
        }

        if trainingDays.isEmpty {
            issues.append("All days are rest days.")
        }

        return Array(Set(issues)).sorted()
    }

    func shouldAcceptAIOutput(despite issues: [String]) -> Bool {
        guard !issues.isEmpty else { return false }
        return issues.allSatisfy(isHeuristicValidationIssue)
    }

    func isHeuristicValidationIssue(_ issue: String) -> Bool {
        issue.contains("undershot its targeted exercise-slot goal")
            || issue.contains("undershot its weighted stimulus target")
            || issue.contains("is concentrated into overly fatiguing sessions")
            || issue.contains("exceeds its focus-day direct-set cap")
            || issue.contains("exceeds its per-session direct-set cap")
            || issue.contains("carries too much total fatigue load")
            || issue.contains("was supposed to emphasize")
            || issue.contains("was planned for")
    }

    func validateContinuity(currentWeekDays: [WorkoutDayResponse], previousWeekDays: [WorkoutDayResponse]) -> [String] {
        guard previousWeekDays.count == 7 else { return [] }

        var comparableDayCount = 0
        var continuityDayCount = 0

        let currentByStyle = groupedTrainingDaysByStyle(currentWeekDays)
        let previousByStyle = groupedTrainingDaysByStyle(previousWeekDays)

        for (style, currentDays) in currentByStyle {
            guard let previousDays = previousByStyle[style] else { continue }

            for index in 0..<min(currentDays.count, previousDays.count) {
                comparableDayCount += 1

                let style = canonicalTrainingStyle(
                    inferredDayStyle(
                        dayName: currentDays[index].dayName,
                        muscleGroups: currentDays[index].muscleGroups
                    ) ?? "Unknown"
                )
                let currentSet = Set(
                    retainedAnchorExercises(from: currentDays[index].exercises, style: style)
                        .prefix(2)
                        .map { normalizeExerciseName($0.exerciseName) }
                )
                let previousSet = Set(
                    retainedAnchorExercises(from: previousDays[index].exercises, style: style)
                        .prefix(2)
                        .map { normalizeExerciseName($0.exerciseName) }
                )

                // EvidenceProfile.md CONT-001 [confidence: moderate]
                // Compare like-for-like sessions, not raw calendar positions. A shifted
                // rest day should not make a coherent progression look random.
                if currentSet.intersection(previousSet).count >= 1 {
                    continuityDayCount += 1
                }
            }
        }

        var issues: [String] = []
        if comparableDayCount >= 4 {
            // Allow up to half the days to rotate freely; only flag when barely any
            // anchor lifts carry over.
            if continuityDayCount < max(1, comparableDayCount / 3) {
                issues.append("Too few anchor lifts carried over from last week. Keep 1-2 anchor lifts per day for progression tracking.")
            }
        }

        return issues
    }

}
