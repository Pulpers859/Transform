import Foundation

extension ClaudeService {
    enum ValidationIssueDisposition {
        case acceptableWarning
        case correctionPass
        case hardFailure
    }

    // MARK: - Parsing and Cleanup

    nonisolated func decodeJSONPayload<T: Decodable>(_ type: T.Type, from responseText: String) throws -> T {
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

    nonisolated func jsonCandidates(from raw: String) -> [String] {
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

    // MARK: - Sanitization (async pipeline with per-exercise diagnostics)

    func sanitizeProgramResponse(_ program: WorkoutProgramResponse) async throws -> WorkoutProgramResponse {
        if WorkoutGenerationDiagnostics.bypassSanitization {
            WorkoutGenerationDiagnostics.markStage("BYPASS: returning raw decoded program")
            return program
        }

        let sortedDays = program.days.sorted { $0.dayNumber < $1.dayNumber }
        var cleanedDays = [WorkoutDayResponse]()
        cleanedDays.reserveCapacity(sortedDays.count)

        for (i, day) in sortedDays.enumerated() {
            try Task.checkCancellation()
            let tag = "d\(i + 1)/\(sortedDays.count)"
            WorkoutGenerationDiagnostics.markStage("sanitize \(tag)")
            let cleaned = sanitizeDay(day, tag: tag)
            cleanedDays.append(cleaned)
        }

        WorkoutGenerationDiagnostics.markStage("sanitize assembly")
        return WorkoutProgramResponse(
            programName: normalizedDisplayText(program.programName, fallback: "Custom Program"),
            programSummary: normalizedCoachingText(program.programSummary, fallback: "4-week hypertrophy mesocycle."),
            splitType: normalizedDisplayText(program.splitType, fallback: "Custom Split"),
            daysPerWeek: max(1, min(7, program.daysPerWeek)),
            days: cleanedDays
        )
    }

    func sanitizeWeekResponse(_ week: WorkoutWeekResponse) async throws -> WorkoutWeekResponse {
        if WorkoutGenerationDiagnostics.bypassSanitization {
            WorkoutGenerationDiagnostics.markStage("BYPASS: returning raw decoded week")
            return week
        }

        let sortedDays = week.days.sorted { $0.dayNumber < $1.dayNumber }
        var cleanedDays = [WorkoutDayResponse]()
        cleanedDays.reserveCapacity(sortedDays.count)

        for (i, day) in sortedDays.enumerated() {
            try Task.checkCancellation()
            let tag = "d\(i + 1)/\(sortedDays.count)"
            WorkoutGenerationDiagnostics.markStage("sanitize \(tag)")
            let cleaned = sanitizeDay(day, tag: tag)
            cleanedDays.append(cleaned)
        }

        WorkoutGenerationDiagnostics.markStage("sanitize assembly")
        return WorkoutWeekResponse(
            weekSummary: normalizedCoachingText(week.weekSummary, fallback: "Weekly progression update."),
            days: cleanedDays
        )
    }

    private func sanitizeDay(_ day: WorkoutDayResponse, tag: String) -> WorkoutDayResponse {
        let weekNumber = ((day.dayNumber - 1) / 7) + 1
        let cleanedDayName = normalizedDisplayText(day.dayName, fallback: "Day \(day.dayNumber)")
        let cleanedMuscleGroups = normalizedDisplayText(
            day.muscleGroups,
            fallback: day.isRestDay ? "Recovery" : "Primary Training"
        )

        var cleanedExercises = [WorkoutExerciseResponse]()
        if !day.isRestDay {
            cleanedExercises.reserveCapacity(day.exercises.count)
            for (j, exercise) in day.exercises.enumerated() {
                let exTag = "\(tag).e\(j + 1)/\(day.exercises.count)"
                let cleaned = sanitizeExercise(exercise, weekNumber: weekNumber, exerciseIndex: j, tag: exTag)
                cleanedExercises.append(cleaned)
            }
            cleanedExercises = rebalanceUniformPrescriptionsIfNeeded(
                cleanedExercises,
                weekNumber: weekNumber
            )
        }

        WorkoutGenerationDiagnostics.markStage("sanitize \(tag) dayNotes")
        let cleanedDayNotes: String
        if day.isRestDay {
            cleanedDayNotes = normalizedCoachingText(
                day.notes,
                fallback: "Active recovery, mobility work, and light cardio."
            )
        } else {
            let fallbackStyle = inferredDayStyle(dayName: cleanedDayName, muscleGroups: cleanedMuscleGroups) ?? "Training"
            let fallbackFocus = cleanedExercises.first?.muscleTarget ?? ""
            let fallback = proceduralDayNotes(
                style: fallbackStyle,
                weekNumber: weekNumber,
                exercises: cleanedExercises,
                focus: fallbackFocus
            )
            cleanedDayNotes = normalizedCoachingText(day.notes, fallback: fallback)
        }

        return WorkoutDayResponse(
            dayNumber: day.dayNumber,
            dayName: cleanedDayName,
            muscleGroups: cleanedMuscleGroups,
            isRestDay: day.isRestDay,
            notes: cleanedDayNotes,
            exercises: cleanedExercises
        )
    }

    private func sanitizeExercise(
        _ exercise: WorkoutExerciseResponse,
        weekNumber: Int,
        exerciseIndex: Int,
        tag: String
    ) -> WorkoutExerciseResponse {
        WorkoutGenerationDiagnostics.markStage("sanitize \(tag) name")
        let cleanedTarget = normalizedDisplayText(exercise.muscleTarget, fallback: "Primary Target")
        let cleanedName = canonicalExerciseName(
            normalizedDisplayText(exercise.exerciseName, fallback: "Exercise"),
            muscleTarget: cleanedTarget
        )

        WorkoutGenerationDiagnostics.markStage("sanitize \(tag) sets")
        let cleanedSets = polishedExerciseSets(
            rawSets: exercise.sets,
            exerciseName: cleanedName,
            muscleTarget: cleanedTarget,
            weekNumber: weekNumber
        )

        WorkoutGenerationDiagnostics.markStage("sanitize \(tag) reps")
        let cleanedReps = polishedExerciseRepRange(
            rawReps: normalizedDisplayText(exercise.reps, fallback: ""),
            exerciseName: cleanedName,
            muscleTarget: cleanedTarget,
            weekNumber: weekNumber
        )

        WorkoutGenerationDiagnostics.markStage("sanitize \(tag) tempo")
        let cleanedTempo = polishedExerciseTempo(
            rawTempo: normalizedDisplayText(exercise.tempo, fallback: ""),
            exerciseName: cleanedName,
            muscleTarget: cleanedTarget,
            weekNumber: weekNumber,
            reps: cleanedReps
        )

        WorkoutGenerationDiagnostics.markStage("sanitize \(tag) rest")
        let cleanedRestSeconds = polishedExerciseRestSeconds(
            rawRestSeconds: exercise.restSeconds,
            exerciseName: cleanedName,
            muscleTarget: cleanedTarget,
            weekNumber: weekNumber
        )

        WorkoutGenerationDiagnostics.markStage("sanitize \(tag) notes")
        let fallbackNotes = proceduralExerciseNotes(
            weekNumber: weekNumber,
            exerciseName: cleanedName,
            muscleTarget: cleanedTarget,
            index: exerciseIndex,
            focus: cleanedTarget
        )
        let cleanedNotes = normalizedExerciseCoachingText(exercise.notes, fallback: fallbackNotes)

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

    private func rebalanceUniformPrescriptionsIfNeeded(
        _ exercises: [WorkoutExerciseResponse],
        weekNumber: Int
    ) -> [WorkoutExerciseResponse] {
        guard exercises.count >= 4 else { return exercises }

        let roles = exercises.map {
            proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget)
        }
        let roleSet = Set(roles.map(\.rawValue))
        let hasCompoundRole = roles.contains(.anchor) || roles.contains(.secondary)
        let hasAccessoryRole = roles.contains(.accessory)
        guard roleSet.count >= 2, hasCompoundRole, hasAccessoryRole else {
            return exercises
        }

        let shouldRebalanceRest = Set(exercises.map(\.restSeconds)).count == 1
        let tempoApplicableIndices = exercises.indices.filter { index in
            let exercise = exercises[index]
            return requiresExplicitTempo(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                reps: exercise.reps
            )
        }
        let normalizedTempos = Set(tempoApplicableIndices.map { index in
            normalizedTempo(exercises[index].tempo) ?? exercises[index].tempo
        })
        let shouldRebalanceTempo = tempoApplicableIndices.count >= 2 && normalizedTempos.count == 1

        guard shouldRebalanceRest || shouldRebalanceTempo else { return exercises }

        return exercises.map { exercise in
            let updatedTempo: String
            if shouldRebalanceTempo,
               requiresExplicitTempo(
                   exerciseName: exercise.exerciseName,
                   muscleTarget: exercise.muscleTarget,
                   reps: exercise.reps
               ) {
                updatedTempo = proceduralTempo(
                    for: weekNumber,
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget,
                    reps: exercise.reps
                )
            } else if shouldRebalanceTempo {
                updatedTempo = ""
            } else {
                updatedTempo = exercise.tempo
            }

            let updatedRestSeconds = shouldRebalanceRest
                ? proceduralRestSeconds(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
                : exercise.restSeconds

            return WorkoutExerciseResponse(
                exerciseName: exercise.exerciseName,
                sets: exercise.sets,
                reps: exercise.reps,
                tempo: updatedTempo,
                restSeconds: updatedRestSeconds,
                notes: exercise.notes,
                muscleTarget: exercise.muscleTarget
            )
        }
    }

    func normalizedDisplayText(_ rawValue: String, fallback: String) -> String {
        let collapsed = collapseWhitespace(in: rawValue)
        return collapsed.isEmpty ? fallback : collapsed
    }

    func normalizedCoachingText(_ rawValue: String, fallback: String) -> String {
        let collapsed = collapseWhitespace(in: rawValue)
        guard !collapsed.isEmpty else { return fallback }
        let wordCount = collapsed.split(separator: " ").count
        return wordCount >= 6 ? collapsed : fallback
    }

    func normalizedExerciseCoachingText(_ rawValue: String, fallback: String) -> String {
        let collapsed = collapseWhitespace(in: rawValue)
        guard !collapsed.isEmpty else { return fallback }
        let wordCount = collapsed.split(separator: " ").count
        return wordCount >= 5 ? collapsed : fallback
    }

    func collapseWhitespace(in rawValue: String) -> String {
        rawValue
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

        let recoveryTight = blueprint.calibration.recoveryConstrained || blueprint.calibration.poorNutritionAdherence
        let severeMultiplier = recoveryTight ? 1.35 : 1.6
        let moderateMultiplier = recoveryTight ? 1.15 : 1.3
        let moderateBuffer = recoveryTight ? 0.0 : 0.5

        for allocation in blueprint.priorityAllocations {
            let coverage = priorityCoverage(for: allocation, stimulusReport: stimulusReport)
            let peakDirectSession = peakDirectSession(for: allocation, stimulusReport: stimulusReport)
            let frequencyMiss = coverage.dayMatches < allocation.targetFrequency
            let meaningfulFrequencyMiss = coverage.meaningfulDayMatches < allocation.targetFrequency
            let directSetMiss = coverage.directSets + 1.0 < allocation.directSetTarget
            let severeOverDirectSetMiss = coverage.directSets > allocation.directSetTarget * severeMultiplier + 1.0
            let overDirectSetMiss = !severeOverDirectSetMiss && coverage.directSets > allocation.directSetTarget * moderateMultiplier + moderateBuffer
            let slotMiss = coverage.exerciseMatches + 1 < allocation.targetExerciseSlots
                && coverage.directSets + 0.5 < allocation.directSetTarget
            let weightedStimulusMiss = coverage.weightedStimulus + 1.0 < allocation.weightedStimulusTarget
                && directSetMiss
            let variationCap = maximumUsefulVariationCount(for: allocation)

            if frequencyMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' missed its frequency target (\(coverage.dayMatches)/\(allocation.targetFrequency) targeted days)."
                )
            }
            if meaningfulFrequencyMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' only delivered \(coverage.meaningfulDayMatches)/\(allocation.targetFrequency) meaningful exposures that met the minimum viable stimulus threshold. Avoid counting token 1-set touches as real priority frequency."
                )
            }
            if directSetMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' missed its direct-set target (\(formatStimulusValue(coverage.directSets))/\(formatStimulusValue(allocation.directSetTarget)))."
                )
            }
            if severeOverDirectSetMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' severely overshot its direct-set target (\(formatStimulusValue(coverage.directSets))/\(formatStimulusValue(allocation.directSetTarget))). The weekly volume is dangerously above the evidence-based range and must be restructured."
                )
            } else if overDirectSetMiss {
                issues.append(
                    "Blueprint priority '\(coverage.label)' overshot its direct-set target enough to create avoidable fatigue (\(formatStimulusValue(coverage.directSets))/\(formatStimulusValue(allocation.directSetTarget))). Trim redundant work instead of stacking junk volume."
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
            if coverage.variationCount > variationCap {
                issues.append(
                    "Blueprint priority '\(coverage.label)' uses too many weekly exercise variations (\(coverage.variationCount) vs cap \(variationCap)). Keep 1-2 repeatable main lifts and trim redundant rotation so progression stays trackable."
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
                if !hasConcreteProgressionCue(exercise.notes) {
                    issues.append("Day \(day.dayNumber) exercise \(exercise.exerciseName) notes do not include a concrete progression cue.")
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

        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
    }

    func shouldAcceptAIOutput(despite issues: [String]) -> Bool {
        guard !issues.isEmpty else { return false }
        return issues.allSatisfy { validationDisposition(for: $0) == .acceptableWarning }
    }

    func shouldAcceptAIOutput(
        despite issues: [String],
        attempt: Int,
        generationAttempts: Int
    ) -> Bool {
        guard !issues.isEmpty else { return false }
        if issues.allSatisfy({ validationDisposition(for: $0) == .acceptableWarning }) {
            return true
        }
        if attempt >= generationAttempts {
            if issues.contains(where: { validationDisposition(for: $0) == .hardFailure }) {
                return false
            }
            if hasCompoundPriorityViolation(in: issues) {
                return false
            }
            if issues.contains(where: { $0.contains("substitution changes the primary muscle target") }) {
                return false
            }
            return true
        }
        return false
    }

    func hasCompoundPriorityViolation(in issues: [String]) -> Bool {
        let overshootLabels = Set(issues.compactMap {
            extractPriorityLabel(from: $0, keyword: "overshot its direct-set target")
        })
        let variationLabels = Set(issues.compactMap {
            extractPriorityLabel(from: $0, keyword: "uses too many weekly exercise variations")
        })
        return !overshootLabels.isDisjoint(with: variationLabels)
    }

    func extractPriorityLabel(from issue: String, keyword: String) -> String? {
        guard issue.contains(keyword) else { return nil }
        guard let openQuote = issue.firstIndex(of: "'") else { return nil }
        let afterOpen = issue.index(after: openQuote)
        guard let closeQuote = issue[afterOpen...].firstIndex(of: "'") else { return nil }
        return String(issue[afterOpen..<closeQuote])
    }

    func validationDisposition(for issue: String) -> ValidationIssueDisposition {
        if matchesValidationIssue(issue, patterns: acceptableWarningIssuePatterns) {
            return .acceptableWarning
        }
        if matchesValidationIssue(issue, patterns: correctionWorthyIssuePatterns)
            || (issue.contains("targets") && issue.contains("but never includes a prime")) {
            return .correctionPass
        }
        return .hardFailure
    }

    func matchesValidationIssue(_ issue: String, patterns: [String]) -> Bool {
        patterns.contains { issue.contains($0) }
    }

    var acceptableWarningIssuePatterns: [String] {
        [
            "undershot its targeted exercise-slot goal",
            "undershot its weighted stimulus target",
            "Too few anchor lifts carried over",
            "substitution significantly increases shoulder risk"
        ]
    }

    var correctionWorthyIssuePatterns: [String] {
        [
            "is concentrated into overly fatiguing sessions",
            "exceeds its focus-day direct-set cap",
            "exceeds its per-session direct-set cap",
            "carries too much total fatigue load",
            "overshot its direct-set target enough to create avoidable fatigue",
            "was supposed to emphasize",
            "was planned for",
            "missed its direct-set target",
            "missed its frequency target",
            "low-value filler",
            "too crowded for a fatigue-managed",
            "one identical rest prescription",
            "one identical tempo prescription",
            "does not clearly support",
            "reads as a broad lower-body session",
            "stacks too many glute",
            "uses shoulder-intensive pressing on an Arms/Lateral focus day",
            "session notes talk about",
            "opens its",
            "spends too many",
            "never includes a prime hypertrophy movement",
            "is not clearly adapted to the impingement",
            "minimum viable stimulus threshold",
            "uses too many weekly exercise variations",
            "session budget",
            "session notes are empty or too short",
            "notes are empty or too short",
            "notes do not include a concrete progression cue",
            "the generated day reads as",
            "is supposed to emphasize quads",
            "excessive shoulder joint stress",
            "excessive elbow joint stress",
            "excessive lower-back stress",
            "excessive knee joint stress",
            "already reached its weekly target",
            "notes describe a low-fatigue",
            "notes describe a shoulder-friendly",
            "notes claim",
            "notes contradict the actual programming",
            "was replaced with a poor substitute",
            "substitution changes the primary muscle target",
            "substitution significantly increases fatigue"
        ]
    }

    func isAcceptableWarningIssue(_ issue: String) -> Bool {
        validationDisposition(for: issue) == .acceptableWarning
    }

    func isCorrectionWorthyHeuristicIssue(_ issue: String) -> Bool {
        validationDisposition(for: issue) == .correctionPass
    }

    func isHeuristicValidationIssue(_ issue: String) -> Bool {
        validationDisposition(for: issue) != .hardFailure
    }

    func scoreValidationIssues(_ issues: [String]) -> Int {
        issues.reduce(0) { total, issue in
            switch validationDisposition(for: issue) {
            case .acceptableWarning: return total + 1
            case .correctionPass: return total + 5
            case .hardFailure: return total + 20
            }
        }
    }

    func validateContinuity(currentWeekDays: [WorkoutDayResponse], previousWeekDays: [WorkoutDayResponse]) -> [String] {
        guard previousWeekDays.count == 7 else { return [] }

        var comparableDayCount = 0
        var continuityDayCount = 0
        var substituteIssues: [String] = []

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
                let currentAnchors = retainedAnchorExercises(from: currentDays[index].exercises, style: style).prefix(3)
                let previousAnchors = retainedAnchorExercises(from: previousDays[index].exercises, style: style).prefix(3)

                let currentKeys = Set(currentAnchors.map { normalizeExerciseName($0.exerciseName) })
                let previousKeys = Set(previousAnchors.map { normalizeExerciseName($0.exerciseName) })

                if currentKeys.intersection(previousKeys).count >= 1 {
                    continuityDayCount += 1
                }

                let droppedKeys = previousKeys.subtracting(currentKeys)
                for droppedKey in droppedKeys {
                    guard let previousExercise = previousAnchors.first(where: {
                        normalizeExerciseName($0.exerciseName) == droppedKey
                    }) else { continue }

                    let previousMeta = exerciseMetadata(for: previousExercise)
                    let bestReplacement = currentDays[index].exercises
                        .filter { !previousKeys.contains(normalizeExerciseName($0.exerciseName)) }
                        .min { lhs, rhs in
                            substituteDistance(from: previousMeta, to: exerciseMetadata(for: lhs))
                                < substituteDistance(from: previousMeta, to: exerciseMetadata(for: rhs))
                        }

                    if let replacement = bestReplacement {
                        let replacementMeta = exerciseMetadata(for: replacement)
                        let distance = substituteDistance(from: previousMeta, to: replacementMeta)
                        if distance < 8.0 {
                            substituteIssues.append(contentsOf: validateSubstituteQuality(
                                original: previousExercise,
                                replacement: replacement,
                                originalMeta: previousMeta,
                                replacementMeta: replacementMeta,
                                dayNumber: currentDays[index].dayNumber
                            ))
                        }
                    }
                }
            }
        }

        var issues: [String] = []
        if comparableDayCount >= 4 {
            if continuityDayCount < max(1, comparableDayCount / 3) {
                issues.append("Too few anchor lifts carried over from last week. Keep 1-2 anchor lifts per day for progression tracking.")
            }
        }
        issues.append(contentsOf: substituteIssues)

        return issues
    }

    func substituteDistance(from original: ExerciseMetadata, to candidate: ExerciseMetadata) -> Double {
        var distance = 0.0

        let origPrimary = Set(original.primaryAreas.map(normalizedPriorityText))
        let candPrimary = Set(candidate.primaryAreas.map(normalizedPriorityText))
        if origPrimary.isDisjoint(with: candPrimary) {
            distance += 10.0
        }

        if normalizedPriorityText(original.movementPattern) != normalizedPriorityText(candidate.movementPattern) {
            distance += 3.0
        }

        distance += abs(Double(original.fatigueCost - candidate.fatigueCost)) * 2.0
        distance += abs(Double(original.shoulderRisk - candidate.shoulderRisk))

        return distance
    }

    func validateSubstituteQuality(
        original: WorkoutExerciseResponse,
        replacement: WorkoutExerciseResponse,
        originalMeta: ExerciseMetadata,
        replacementMeta: ExerciseMetadata,
        dayNumber: Int
    ) -> [String] {
        var issues: [String] = []

        let origPrimary = Set(originalMeta.primaryAreas.map(normalizedPriorityText))
        let replPrimary = Set(replacementMeta.primaryAreas.map(normalizedPriorityText))
        if origPrimary.isDisjoint(with: replPrimary) {
            issues.append(
                "Day \(dayNumber): '\(original.exerciseName)' was replaced with '\(replacement.exerciseName)', but the substitution changes the primary muscle target from \(originalMeta.primaryAreas.joined(separator: "/")) to \(replacementMeta.primaryAreas.joined(separator: "/")). Keep substitutes within the same muscle group."
            )
        }

        let fatigueDelta = replacementMeta.fatigueCost - originalMeta.fatigueCost
        if fatigueDelta >= 2 {
            issues.append(
                "Day \(dayNumber): '\(original.exerciseName)' was replaced with '\(replacement.exerciseName)', but the substitution significantly increases fatigue cost (\(originalMeta.fatigueCost) → \(replacementMeta.fatigueCost)). Prefer similar or lower fatigue alternatives."
            )
        }

        let riskDelta = replacementMeta.shoulderRisk - originalMeta.shoulderRisk
        if riskDelta >= 2 {
            issues.append(
                "Day \(dayNumber): '\(original.exerciseName)' was replaced with '\(replacement.exerciseName)', but the substitution significantly increases shoulder risk (\(originalMeta.shoulderRisk) → \(replacementMeta.shoulderRisk)). Prefer lower-risk alternatives."
            )
        }

        return issues
    }

    // MARK: - Overshoot Trim Correction

    func trimOvershootExercises(
        days: [WorkoutDayResponse],
        blueprint: ProgramBlueprint,
        dayStart: Int = 1
    ) -> (days: [WorkoutDayResponse], didTrim: Bool) {
        var mutableDays = days
        var didTrim = false
        let recoveryTight = blueprint.calibration.recoveryConstrained || blueprint.calibration.poorNutritionAdherence
        let trimMultiplier = recoveryTight ? 1.15 : 1.3
        let trimBuffer = recoveryTight ? 0.0 : 0.5

        for allocation in blueprint.priorityAllocations {
            let report = buildWeekStimulusReport(from: mutableDays)
            let coverage = priorityCoverage(for: allocation, stimulusReport: report)
            let ceiling = allocation.directSetTarget * trimMultiplier + trimBuffer
            guard coverage.directSets > ceiling else { continue }

            var excess = coverage.directSets - ceiling
            let allocatedDays = allocatedDayNumbers(for: allocation, blueprint: blueprint, dayStart: dayStart)

            var targets: [(dayIndex: Int, exerciseIndex: Int, creditPerSet: Double, sets: Int, onAllocatedDay: Bool)] = []
            for (di, day) in mutableDays.enumerated() where !day.isRestDay {
                for (ei, exercise) in day.exercises.enumerated() {
                    let credit = directSetCredit(for: exercise, area: allocation.area)
                    guard credit > 0 else { continue }
                    targets.append((
                        dayIndex: di,
                        exerciseIndex: ei,
                        creditPerSet: credit / Double(max(1, exercise.sets)),
                        sets: exercise.sets,
                        onAllocatedDay: allocatedDays.contains(day.dayNumber)
                    ))
                }
            }

            targets.sort { lhs, rhs in
                if lhs.onAllocatedDay != rhs.onAllocatedDay { return !lhs.onAllocatedDay }
                return lhs.sets > rhs.sets
            }

            for target in targets {
                guard excess > 0 else { break }
                let day = mutableDays[target.dayIndex]
                let exercise = day.exercises[target.exerciseIndex]
                guard exercise.sets > 2 else { continue }

                let setsToTrim = min(exercise.sets - 2, Int(ceil(excess / target.creditPerSet)))
                guard setsToTrim > 0 else { continue }

                let newExercise = WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: exercise.sets - setsToTrim,
                    reps: exercise.reps,
                    tempo: exercise.tempo,
                    restSeconds: exercise.restSeconds,
                    notes: exercise.notes,
                    muscleTarget: exercise.muscleTarget
                )
                var newExercises = day.exercises
                newExercises[target.exerciseIndex] = newExercise
                mutableDays[target.dayIndex] = WorkoutDayResponse(
                    dayNumber: day.dayNumber,
                    dayName: day.dayName,
                    muscleGroups: day.muscleGroups,
                    isRestDay: day.isRestDay,
                    notes: day.notes,
                    exercises: newExercises
                )
                excess -= Double(setsToTrim) * target.creditPerSet
                didTrim = true
            }
        }

        for allocation in blueprint.priorityAllocations {
            let maxPasses = 4
            for _ in 0..<maxPasses {
                let report = buildWeekStimulusReport(from: mutableDays)
                guard let peak = peakDirectSession(for: allocation, stimulusReport: report) else { break }
                let allowedCap = allowedPerSessionDirectSetCap(
                    for: allocation,
                    dayNumber: peak.dayNumber,
                    blueprint: blueprint,
                    dayStart: dayStart
                )
                guard peak.directSets > allowedCap + 0.01 else { break }
                guard let dayIndex = mutableDays.firstIndex(where: { $0.dayNumber == peak.dayNumber }) else { break }
                let day = mutableDays[dayIndex]

                var sessionTargets: [(exerciseIndex: Int, creditPerSet: Double, sets: Int)] = []
                for (ei, exercise) in day.exercises.enumerated() {
                    let credit = directSetCredit(for: exercise, area: allocation.area)
                    guard credit > 0, exercise.sets > 2 else { continue }
                    sessionTargets.append((
                        exerciseIndex: ei,
                        creditPerSet: credit / Double(max(1, exercise.sets)),
                        sets: exercise.sets
                    ))
                }

                sessionTargets.sort { lhs, rhs in
                    if lhs.creditPerSet != rhs.creditPerSet { return lhs.creditPerSet < rhs.creditPerSet }
                    return lhs.sets > rhs.sets
                }

                guard let target = sessionTargets.first else { break }
                let exercise = day.exercises[target.exerciseIndex]

                let trimmedExercise = WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: exercise.sets - 1,
                    reps: exercise.reps,
                    tempo: exercise.tempo,
                    restSeconds: exercise.restSeconds,
                    notes: exercise.notes,
                    muscleTarget: exercise.muscleTarget
                )
                var updatedExercises = day.exercises
                updatedExercises[target.exerciseIndex] = trimmedExercise
                mutableDays[dayIndex] = WorkoutDayResponse(
                    dayNumber: day.dayNumber,
                    dayName: day.dayName,
                    muscleGroups: day.muscleGroups,
                    isRestDay: day.isRestDay,
                    notes: day.notes,
                    exercises: updatedExercises
                )
                didTrim = true
            }
        }

        return (mutableDays, didTrim)
    }

    func allocatedDayNumbers(
        for allocation: BlueprintPriorityAllocation,
        blueprint: ProgramBlueprint,
        dayStart: Int
    ) -> Set<Int> {
        let aliases = Set(stimulusAreaAliases(for: allocation.area).map(normalizedPriorityText))
        var dayNumbers = Set<Int>()

        for plan in blueprint.dayPlans where !plan.isRestDay {
            let dayNumber = blueprintDayNumber(plan.dayIndex, dayStart: dayStart)

            if let focusArea = plan.focusArea {
                let focusAliases = Set(stimulusAreaAliases(for: focusArea).map(normalizedPriorityText))
                if !aliases.isDisjoint(with: focusAliases) {
                    dayNumbers.insert(dayNumber)
                    continue
                }
            }

            for supportArea in plan.supportAreas {
                let supportAliases = Set(stimulusAreaAliases(for: supportArea).map(normalizedPriorityText))
                if !aliases.isDisjoint(with: supportAliases) {
                    dayNumbers.insert(dayNumber)
                    break
                }
            }
        }

        return dayNumbers
    }

}
