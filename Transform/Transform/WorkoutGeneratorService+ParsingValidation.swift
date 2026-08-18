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
        // Report the failure from whichever candidate got FURTHEST, not a positional pick.
        // Reporting the last one blamed a synthetic repair candidate for a brace the model
        // never emitted; reporting the first one is just as wrong in the opposite direction —
        // when the model wraps valid JSON in prose, the raw candidate fails with a generic
        // "not JSON" while the extracted candidate carries the real schema mismatch. Rank by
        // how deep the decoder got: a key/type/value error means the JSON parsed and only the
        // shape was wrong, which is the actionable message.
        var decodeError: Error?
        var decodeErrorRank = Int.min

        // `if case` rather than a switch: DecodingError is a non-frozen stdlib enum, and an
        // exhaustive switch over it would need an `@unknown default` whose availability is a
        // detail of the toolchain rather than of this file.
        func informativeness(of error: Error) -> Int {
            guard let decodingError = error as? DecodingError else { return 1 }
            // .dataCorrupted is "this was not JSON at all"; keyNotFound / typeMismatch /
            // valueNotFound all mean the JSON parsed and only the shape was wrong, which is
            // the message that actually names the offending field.
            if case .dataCorrupted = decodingError { return 0 }
            return 3
        }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                let rank = informativeness(of: error)
                if rank > decodeErrorRank {
                    decodeErrorRank = rank
                    decodeError = error
                }
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

        // `"{" + raw` with no closing brace can never parse as an object; it only burned a
        // decode attempt and produced a misleading error. The balanced repair below is the
        // one that actually recovers an unwrapped payload.
        if !raw.hasPrefix("{") && raw.contains(":") {
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
                // Pass the cues already placed on THIS day. When the model returns an
                // unusable note, sanitization substitutes a procedural cue — and two
                // substitutions on one day would otherwise land on the same sentence, which
                // is the duplication the whole cue rewrite exists to make impossible. The
                // day-scoped guarantee has to hold on the AI path too, not just the
                // procedural one, because the AI path is the default.
                let cleaned = sanitizeExercise(
                    exercise,
                    weekNumber: weekNumber,
                    exerciseIndex: j,
                    tag: exTag,
                    cuesAlreadyOnDay: Set(cleanedExercises.map(\.notes))
                )
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
        tag: String,
        cuesAlreadyOnDay: Set<String> = []
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
        // Decided BEFORE polishing, because polishing is what erases the evidence: once a
        // procedural cue has been substituted the result is indistinguishable from a note the
        // model actually wrote. Program-level source labelling misses this case entirely — the
        // week still reads "[AI Coach]" while individual cues came from the engine.
        // The decode-time stand-in counts as "not written by the model" even though it clears
        // the length threshold — otherwise a response that simply omitted `notes` would be
        // reported as AI-authored coaching.
        let noteWasSubstituted = isEmptyOrTooShortInsight(exercise.notes)
            || exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines) == WorkoutExerciseResponse.absentNoteDefault
        let cleanedNotes = polishedExerciseNotes(
            rawNotes: exercise.notes,
            exerciseName: cleanedName,
            muscleTarget: cleanedTarget,
            weekNumber: weekNumber,
            exerciseIndex: exerciseIndex,
            cuesAlreadyOnDay: cuesAlreadyOnDay
        )
        // Keep any set-count the note cites in step with the (possibly polished) structured
        // count so prose and the SETS tile / log rows can't disagree.
        let reconciledNotes = reconciledSetCountNotes(cleanedNotes, toSetCount: cleanedSets)

        return WorkoutExerciseResponse(
            exerciseName: cleanedName,
            sets: cleanedSets,
            reps: cleanedReps,
            tempo: cleanedTempo,
            restSeconds: cleanedRestSeconds,
            notes: reconciledNotes,
            muscleTarget: cleanedTarget,
            targetRIR: exercise.targetRIR,
            // A procedurally-built day re-entering sanitization keeps its own provenance;
            // only a note that arrived from the model is classified here.
            coachingSource: exercise.coachingSource ?? (noteWasSubstituted ? .substituted : .aiCoach)
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
                muscleTarget: exercise.muscleTarget,
                targetRIR: exercise.targetRIR,
                // Carry provenance through every rebuild. This runs after sanitization has
                // already classified the note, so omitting it here would silently reset the
                // field to nil — the field would compile, ship, and always read "unknown".
                coachingSource: exercise.coachingSource
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

    func validateProgramResponse(
        _ program: WorkoutProgramResponse,
        blueprint: ProgramBlueprint,
        expectedExerciseMenus: [[PreSelectedExercise]]? = nil,
        progressionVerdicts: [ExerciseProgressionVerdict] = []
    ) -> [String] {
        var issues: [String] = []
        let days = program.days

        issues.append(contentsOf: validateDaySet(days, dayStart: 1, dayEnd: 7))
        issues.append(contentsOf: validateBlueprint(days: days, blueprint: blueprint, dayStart: 1))
        issues.append(contentsOf: validateCoachingCueConsistency(days: days, verdicts: progressionVerdicts))
        issues.append(contentsOf: validateBackPatternBalance(days: days))
        if let expectedExerciseMenus {
            issues.append(contentsOf: validateExerciseMenuAdherence(
                days: days,
                expectedExerciseMenus: expectedExerciseMenus,
                dayStart: 1
            ))
        }

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
        blueprint: ProgramBlueprint,
        expectedExerciseMenus: [[PreSelectedExercise]]? = nil,
        progressionVerdicts: [ExerciseProgressionVerdict] = []
    ) -> [String] {
        var issues: [String] = []
        let days = week.days

        issues.append(contentsOf: validateDaySet(days, dayStart: dayStart, dayEnd: dayEnd))
        issues.append(contentsOf: validateBlueprint(days: days, blueprint: blueprint, dayStart: dayStart))
        issues.append(contentsOf: validateCoachingCueConsistency(days: days, verdicts: progressionVerdicts))
        issues.append(contentsOf: validateBackPatternBalance(days: days))
        if let expectedExerciseMenus {
            issues.append(contentsOf: validateExerciseMenuAdherence(
                days: days,
                expectedExerciseMenus: expectedExerciseMenus,
                dayStart: dayStart
            ))
        }

        if week.weekSummary.trimmedOr(default: "").isEmpty {
            issues.append("weekSummary is empty.")
        }

        if let previousWeekDays {
            let continuityIssues = validateContinuity(currentWeekDays: days, previousWeekDays: previousWeekDays)
            issues.append(contentsOf: continuityIssues)
        }

        return issues
    }

    func validateExerciseMenuAdherence(
        days: [WorkoutDayResponse],
        expectedExerciseMenus: [[PreSelectedExercise]],
        dayStart: Int
    ) -> [String] {
        guard !expectedExerciseMenus.isEmpty else { return [] }

        var issues: [String] = []
        let daysByNumber = Dictionary(grouping: days, by: \.dayNumber)
            .compactMapValues { $0.first }

        for (offset, menu) in expectedExerciseMenus.enumerated() {
            guard !menu.isEmpty else { continue }
            let dayNumber = dayStart + offset
            guard let day = daysByNumber[dayNumber], !day.isRestDay else {
                issues.append("Day \(dayNumber) did not follow the Pre-Selected Exercise Menu: expected \(menu.count) locked exercises, but the generated day is missing or marked as rest.")
                continue
            }

            if day.exercises.count != menu.count {
                issues.append("Day \(dayNumber) did not follow the Pre-Selected Exercise Menu: expected \(menu.count) exercises but generated \(day.exercises.count).")
            }

            let maxComparable = min(day.exercises.count, menu.count)
            for index in 0..<maxComparable {
                let expected = menu[index]
                let actual = day.exercises[index]
                let expectedName = canonicalExerciseName(expected.exerciseName, muscleTarget: expected.muscleTarget)
                let actualName = canonicalExerciseName(actual.exerciseName, muscleTarget: actual.muscleTarget)
                if normalizeExerciseName(expectedName) != normalizeExerciseName(actualName) {
                    issues.append("Day \(dayNumber) did not follow the Pre-Selected Exercise Menu at slot \(index + 1): expected \(expected.exerciseName), but generated \(actual.exerciseName).")
                    continue
                }
                if actual.sets != expected.prescribedSets {
                    issues.append("Day \(dayNumber) did not follow the Pre-Selected Exercise Menu at slot \(index + 1): \(expected.exerciseName) requires \(expected.prescribedSets) sets, but generated \(actual.sets).")
                }
            }
        }

        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
    }

    /// The deterministic menu owns weekly dosage. Claude supplies reps, tempo, rest, and
    /// coaching prose; this projection keeps its structured payload on the planned set budget
    /// before scoring, so a model formatting deviation cannot trigger a paid correction pass.
    func applyingPreselectedSetPrescription(
        to days: [WorkoutDayResponse],
        menus: [[PreSelectedExercise]],
        dayStart: Int
    ) -> [WorkoutDayResponse] {
        var updated = days
        for (offset, menu) in menus.enumerated() where !menu.isEmpty {
            let dayNumber = dayStart + offset
            guard let dayIndex = updated.firstIndex(where: { $0.dayNumber == dayNumber && !$0.isRestDay }) else {
                continue
            }
            var exercises = updated[dayIndex].exercises
            let comparableCount = min(exercises.count, menu.count)
            for index in 0..<comparableCount {
                let expected = menu[index]
                let actualName = canonicalExerciseName(
                    exercises[index].exerciseName,
                    muscleTarget: exercises[index].muscleTarget
                )
                let expectedName = canonicalExerciseName(
                    expected.exerciseName,
                    muscleTarget: expected.muscleTarget
                )
                guard normalizeExerciseName(actualName) == normalizeExerciseName(expectedName) else { continue }
                let exercise = exercises[index]
                exercises[index] = WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: expected.prescribedSets,
                    reps: exercise.reps,
                    tempo: exercise.tempo,
                    restSeconds: exercise.restSeconds,
                    notes: reconciledSetCountNotes(
                        exercise.notes,
                        toSetCount: expected.prescribedSets
                    ),
                    muscleTarget: exercise.muscleTarget,
                    targetRIR: exercise.targetRIR,
                    // Set-count reconciliation rewrites prose, not authorship.
                    coachingSource: exercise.coachingSource
                )
            }
            let day = updated[dayIndex]
            updated[dayIndex] = WorkoutDayResponse(
                dayNumber: day.dayNumber,
                dayName: day.dayName,
                muscleGroups: day.muscleGroups,
                isRestDay: day.isRestDay,
                notes: day.notes,
                exercises: exercises
            )
        }
        return updated
    }

    func applyingPreselectedSetPrescription(
        to response: WorkoutProgramResponse,
        menus: [[PreSelectedExercise]]
    ) -> WorkoutProgramResponse {
        WorkoutProgramResponse(
            programName: response.programName,
            programSummary: response.programSummary,
            splitType: response.splitType,
            daysPerWeek: response.daysPerWeek,
            days: applyingPreselectedSetPrescription(to: response.days, menus: menus, dayStart: 1)
        )
    }

    func applyingPreselectedSetPrescription(
        to response: WorkoutWeekResponse,
        menus: [[PreSelectedExercise]],
        dayStart: Int
    ) -> WorkoutWeekResponse {
        WorkoutWeekResponse(
            weekSummary: response.weekSummary,
            days: applyingPreselectedSetPrescription(to: response.days, menus: menus, dayStart: dayStart)
        )
    }

    func validateBlueprint(
        days: [WorkoutDayResponse],
        blueprint: ProgramBlueprint,
        dayStart: Int
    ) -> [String] {
        guard !blueprint.priorityAllocations.isEmpty else {
            print("[WorkoutGeneratorService] validateBlueprint skipped: blueprint has no priorityAllocations (degenerate/empty training intent).")
            return []
        }

        var issues: [String] = []
        let trainingDayCount = days.filter { !$0.isRestDay }.count
        let stimulusReport = buildWeekStimulusReport(from: days)
        let variationViolations = weeklyVariationViolations(in: days, blueprint: blueprint)

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
            for violation in variationViolations where normalizedPriorityText(violation.area) == normalizedPriorityText(allocation.area) {
                let scope = normalizedPriorityText(violation.bucket) == normalizedPriorityText(violation.area)
                    ? ""
                    : " sub-region '\(violation.bucket)'"
                issues.append(
                    "Blueprint priority '\(coverage.label)'\(scope) uses too many weekly exercise variations (\(violation.count) vs cap \(violation.cap)). Keep repeatable main lifts and rotate additional catalog options across mesocycles instead of within one week."
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

        issues.append(contentsOf: validateNonPriorityMuscleVolume(
            days: days,
            blueprint: blueprint,
            recoveryTight: recoveryTight
        ))

        issues.append(contentsOf: validateDayPlans(days: days, blueprint: blueprint, dayStart: dayStart))

        // Sorted, not raw dictionary order: this list is rendered to the owner in the validator
        // banner and the generation bundle, and it seeds the correction prompt. Dictionary
        // iteration order is unspecified, so the same week produced a differently-ordered issue
        // list run to run — which makes bundles non-comparable and the correction pass
        // non-reproducible.
        for dayNumber in stimulusReport.dailyFatigue.keys.sorted() {
            let fatigue = stimulusReport.dailyFatigue[dayNumber] ?? 0
            guard fatigue > maxDailyFatigueThreshold(for: days, dayNumber: dayNumber) else { continue }
            issues.append(
                "Day \(dayNumber) carries too much total fatigue load for a hypertrophy week (\(fatigue)). Reduce redundant compounds or redistribute work."
            )
        }

        return issues
    }

    /// 2026-07-14 audit fixes 3 + 4: the blueprint checks above police priority muscles
    /// only, which let ~98 unbounded weekly sets and a zero-hamstring week pass silently.
    /// Maintenance now has a ceiling and BASE-001 has a visible floor.
    func validateNonPriorityMuscleVolume(
        days: [WorkoutDayResponse],
        blueprint: ProgramBlueprint,
        recoveryTight: Bool
    ) -> [String] {
        var issues: [String] = []
        // EvidenceProfile.md MAINT-001 [confidence: low-moderate]
        let maintenanceCeiling = recoveryTight ? 8.0 : 10.0
        // The band has always had a bottom; only the top was ever enforced. This rule read
        // "zero is a violation, ten is a violation, everything between is fine", so a week
        // shipped Triceps on 2 weekly sets — one Dip — beside Calves on 6, and reported no
        // issues at all. Calves appear nowhere in that lifter's analysis.
        //
        // The floor sits deliberately BELOW the 6-10 band MAINT-001 describes. Six is the
        // target; four is the point past which the word "maintenance" stops meaning anything.
        // A rule that fired on every group merely sitting low would fire on almost every honest
        // week and teach the owner to skim past the list, which costs more than it catches.
        // Constrained recovery lowers the whole band, floor included, per SLEEP-002.
        let maintenanceFloor = recoveryTight ? 3.0 : 4.0

        // Prioritized groups stay exempt here ON PURPOSE, even though `allocateWeeklySetPrescription`
        // now keeps a residue ledger for them (see `exerciseCountsTowardMaintenance`). The allocator
        // enforces the residue ceiling while building the locked menu, so a validator rule would be
        // a second opinion on a number the planner already owns — and this rule's finding is on the
        // menu-locked HARD-FAILURE list, so a disagreement would discard a week the owner paid for
        // rather than repair anything. Deliberate silence, not an oversight.
        for group in majorMuscleGroups {
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            guard !isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint) else { continue }

            let directSets = weeklyDirectSets(forGroupAliases: aliases, days: days)
            if directSets > maintenanceCeiling + 0.5 {
                issues.append(
                    "Non-priority muscle group '\(group.label)' exceeds the maintenance weekly volume ceiling (\(formatStimulusValue(directSets)) sets vs \(formatStimulusValue(maintenanceCeiling))). Maintenance means roughly 6-10 quality sets per week — trim redundant filler instead of stacking volume the recovery budget cannot pay for."
                )
            } else if directSets <= 0.01 {
                // EvidenceProfile.md BASE-001 [confidence: high]
                issues.append(
                    "Muscle group '\(group.label)' receives zero direct sets this week. BASE-001 requires every major muscle group to keep at least a minimal weekly exposure — even maintenance is not zero."
                )
            } else if directSets + 0.01 < maintenanceFloor {
                // EvidenceProfile.md MAINT-001 / BASE-001 [confidence: low-moderate]
                issues.append(
                    "Non-priority muscle group '\(group.label)' falls below the maintenance weekly volume floor (\(formatStimulusValue(directSets)) sets vs \(formatStimulusValue(maintenanceFloor))). MAINT-001 puts maintenance near 6-10 quality sets per week, and the allocator can only fill an exercise to its role default — so a group this low is short of exercise SLOTS, not sets, and needs a second weekly exposure rather than more sets on the one it already has."
                )
            }
        }

        return issues
    }

    // MARK: - Back Pattern Balance (BASE-001, pattern half)

    /// Flags a week that trains the back exclusively from overhead.
    ///
    /// BASE-001 accounting keeps ONE "back" ledger whose aliases span Lats, Upper Back and Mid
    /// Back together, so a single pulldown marks the whole bucket covered and no volume rule ever
    /// asks where the sets came from. A five-day week shipped `Lat Pulldown`, `Neutral-Grip Lat
    /// Pulldown` and `Pull-Up` — eight back sets, every one of them vertical, no row anywhere —
    /// and validated clean.
    ///
    /// Directional on purpose. Rows still load the lats through a full range, so a week built on
    /// rowing is not flagged for lacking a pulldown; nothing in a vertical pull trains the
    /// rhomboids and mid-traps at their shortened position, so the reverse IS a real gap.
    /// Claiming symmetry here would look tidier and would not be supported.
    ///
    /// `enforceHorizontalPullCoverage` repairs this while the menu is being built. This rule is
    /// what makes it visible on a week where the menu genuinely had no room.
    func validateBackPatternBalance(days: [WorkoutDayResponse]) -> [String] {
        let exercises = days.filter { !$0.isRestDay }.flatMap(\.exercises)
        guard !exercises.isEmpty else { return [] }

        let backAliases = normalizedGroupAliases(forSeed: "back")
        let trainsBack = exercises.contains { exercise in
            exerciseDirectlyTargets(
                groupAliases: backAliases,
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            )
        }
        guard trainsBack else { return [] }

        let hasHorizontalPull = exercises.contains { exercise in
            guard let pattern = menuMovementPattern(
                forExerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            ) else { return false }
            return horizontalPullPatterns.contains(pattern)
        }
        guard !hasHorizontalPull else { return [] }

        return [
            "The week trains the back with no horizontal pull at all — every back movement pulls down from overhead. Vertical pulling does not load the rhomboids and mid-traps in their shortened position, so this needs a rowing movement, not another pulldown variation."
        ]
    }

    // MARK: - Coaching Cue vs Logged History (enforcement half of 98349db)

    /// The prompt already injects the deterministic progression verdict and requires the
    /// AI cue to agree; nothing verified the model obeyed. Two history-contradicting cues
    /// still shipped in the 2026-07-14 dump. This rule checks the two hard contradictions
    /// only — "hold" cues against an add-load verdict and "add load" cues against a
    /// below-range verdict. Mid-range (add-reps) verdicts are deliberately not policed:
    /// "add reps before adding load" phrasing overlaps both vocabularies and false
    /// positives there would erode trust in real findings.
    func validateCoachingCueConsistency(
        days: [WorkoutDayResponse],
        verdicts: [ExerciseProgressionVerdict]
    ) -> [String] {
        guard !verdicts.isEmpty else { return [] }
        let verdictsByKey = Dictionary(
            verdicts.map { ($0.canonicalKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var issues: [String] = []

        for day in days where !day.isRestDay {
            for exercise in day.exercises {
                let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                guard let verdict = verdictsByKey[key] else { continue }
                guard let conflictSentence = coachingCueConflict(notes: exercise.notes, verdict: verdict.kind) else { continue }

                let weight = formatStimulusValue(verdict.weightLbs)
                let expected: String
                switch verdict.kind {
                case .addLoad:
                    expected = "ADD LOAD (rep ceiling beaten at \(weight) lb)"
                case .addRepsInRange:
                    expected = "ADD REPS before load (inside the rep range at \(weight) lb)"
                case .holdBelowRange:
                    expected = "HOLD \(weight) lb and build reps (fell below the rep floor)"
                case .holdForRecovery:
                    expected = "HOLD \(weight) lb (repeated low RIR indicates recovery protection)"
                }
                issues.append(
                    "Day \(day.dayNumber) exercise \(exercise.exerciseName): the coaching cue '\(conflictSentence)' contradicts the app's logged progression verdict — \(expected). Rewrite the cue to agree with the logged history; if the program is deliberately overriding the progression ladder, the cue must say so explicitly."
                )
            }
        }

        return issues
    }

    /// Returns the first non-conditional sentence that contradicts the verdict, nil when
    /// the note is consistent. Conditional coaching ("if sleep is poor, hold the load")
    /// is sanctioned by the prompt's progression model and never flagged.
    func coachingCueConflict(notes: String, verdict: ProgressionVerdictKind) -> String? {
        guard !notes.isEmpty else { return nil }

        let holdPatterns = [
            #"hold(ing)?\s+(at\s+)?\d+(\.\d+)?\s*(lb|lbs|pound)"#,
            #"hold\s+(the|this|that|your)\s+(current\s+)?(load|weight)"#,
            #"stay(ing)?\s+(at|with)\s+\d+"#,
            #"stay(ing)?\s+(at|with)\s+(the|this)\s+(load|weight)"#,
            #"keep\s+(the|this|your)\s+(same\s+)?(load|weight)"#,
            #"same\s+(load|weight)"#,
            #"(don't|do not)\s+add\s+(load|weight)"#
        ]
        let addLoadPatterns = [
            #"add\s+(load|weight|a\s+plate)"#,
            #"increase\s+(the\s+)?(load|weight)"#,
            #"go\s+up\s+(in|to)\s+(load|weight)"#,
            #"move\s+up\s+to\s+\d+(\.\d+)?\s*(lb|lbs)"#,
            #"heavier\s+(load|weight|dumbbell|pair)"#,
            #"load\s+increase"#
        ]
        let conditionalMarkers = ["if ", "when ", "once ", "after ", "unless "]

        func matches(_ sentence: String, _ patterns: [String]) -> Bool {
            patterns.contains {
                sentence.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
            }
        }

        // Splitting on every "." used to cut "hold at 22.5 lb" into "hold at 22" and "5 lb",
        // which made the numeric hold/add patterns above unmatchable for ANY decimal load —
        // and 2.5 lb increments are routine here. Semicolons still separate clauses.
        let sentences = notes
            .split(separator: ";")
            .flatMap { CoachingProse.sentences(in: String($0)) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for sentence in sentences {
            let lowered = sentence.lowercased()
            guard !conditionalMarkers.contains(where: { lowered.contains($0) }) else { continue }

            switch verdict {
            case .addLoad:
                if matches(sentence, holdPatterns) && !matches(sentence, addLoadPatterns) {
                    return sentence
                }
            case .holdBelowRange:
                if matches(sentence, addLoadPatterns) {
                    return sentence
                }
            case .holdForRecovery:
                if matches(sentence, addLoadPatterns) {
                    return sentence
                }
            case .addRepsInRange:
                continue
            }
        }

        return nil
    }

    /// Why the procedurally-built days could not be trained at all — `nil` when they can.
    ///
    /// The procedural generator is the LAST resort. When `validatedProceduralWeek*` throws, the
    /// owner does not get a degraded program; they get no program and an engineering string in
    /// place of a workout. That gate used to reuse `validationDisposition`, which answers a
    /// different question — "is this worth another paid AI call?" — and whose default arm is
    /// `.hardFailure`. So every validator finding not explicitly listed as acceptable or
    /// correction-worthy erased the week, including findings the deterministic builder cannot
    /// repair, and including any rule added to the validator later. Fail-closed is right for
    /// paid AI output, where a retry exists; it is wrong here, where nothing comes next.
    ///
    /// This asks the only question the last resort should ask, and asks it of the data rather
    /// than of message text, so a reworded or newly-added validator rule cannot silently change
    /// what counts as unusable.
    ///
    /// This is only safe because the findings it stops blocking on still REACH the owner, so that
    /// path is named here rather than left to be re-derived: the caller re-validates the accepted
    /// fallback and returns the findings as `validatorWarnings`
    /// (`generateWeekOne` / `generateNextWeek`), `WorkoutView` persists
    /// them onto `WorkoutProgram.validatorWarnings`, and `validatorWarningsBanner` renders them
    /// through `WorkoutValidatorNotice`, which states each one in plain language. A coverage gap
    /// therefore arrives as "Hamstrings has no direct work this week" above a usable program,
    /// instead of as a parse error in place of one. If that chain is ever broken, this check
    /// becomes silent tolerance and must be revisited.
    func proceduralOutputBlockingDefect(in days: [WorkoutDayResponse]) -> String? {
        let trainingDays = days.filter { !$0.isRestDay }
        guard !trainingDays.isEmpty else { return "no training days were produced" }

        for day in trainingDays {
            guard !day.exercises.isEmpty else {
                return "day \(day.dayNumber) is a training day with no exercises"
            }
            for exercise in day.exercises {
                if exercise.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "day \(day.dayNumber) contains an exercise with no name"
                }
                if exercise.sets <= 0 {
                    return "day \(day.dayNumber) prescribes \(exercise.sets) sets for \(exercise.exerciseName)"
                }
                if exercise.reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "day \(day.dayNumber) prescribes no reps for \(exercise.exerciseName)"
                }
            }
        }

        return nil
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
            } else if !day.isRestDay && isGenericSessionNote(day.notes, exercises: day.exercises) {
                let sampleExercise = day.exercises.first?.exerciseName ?? "the primary compound"
                issues.append("Day \(day.dayNumber) session notes are generic — rewrite with an analysis-anchored intent line and a 'Warm-up:' section with specific prep items tied to this day's lifts (e.g. ramp sets into \(sampleExercise), relevant mobility).")
            }
            // The same execution-only rule the exercise notes have always had. Day notes were
            // exempt from it, so the briefing at the top of the screen could carry a load
            // instruction that contradicted the deterministic banner on every card below it.
            // Phrased to contain the exercise-note wording so it shares that issue's
            // correction-pass disposition — rewriting a sentence, not restructuring a day.
            if notesContainProgressionInstruction(dayBriefingProse(in: day.notes)) {
                issues.append("Day \(day.dayNumber) session notes contain load/rep progression instructions — session notes are for intent and warm-up; the app derives progression from logged performance.")
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
                // Notes are execution-only; effort intent belongs in the structured
                // targetRIR field and progression belongs to the app's deterministic
                // engine. (This check replaced its exact opposite — the validator
                // used to REQUIRE a progression cue in notes, which forced the
                // two-voices contradiction with the live progression banner.)
                if RepRange.parse(exercise.reps) != nil, exercise.targetRIR == nil {
                    issues.append("Day \(day.dayNumber) exercise \(exercise.exerciseName) is missing targetRIR — state working-set effort in the structured field, not in prose.")
                }
                if notesContainProgressionInstruction(exercise.notes) {
                    issues.append("Day \(day.dayNumber) exercise \(exercise.exerciseName) notes contain load/rep progression instructions — notes must be execution-only coaching; the app derives progression from logged performance.")
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

    /// The briefing prose of a session note, with the warm-up checklist removed.
    ///
    /// The execution-only rule is about the BRIEFING — the sentence that frames the day. The
    /// warm-up section is a list of ramp sets and mobility drills that the prompt explicitly
    /// asks for ("2-3 progressive ramp sets into Back Squat"), and ramping load is what a warm-up
    /// IS. Checking it for load language would burn a correction pass on a note that did exactly
    /// what it was told.
    ///
    /// Split on the same markers the card's `SessionNoteSections` uses, so the validator polices
    /// precisely the text the lifter reads as the briefing.
    func dayBriefingProse(in notes: String) -> String {
        var briefing = notes
        for marker in CoachingProse.warmupSectionMarkers {
            if let range = briefing.range(of: marker, options: .caseInsensitive) {
                briefing = String(briefing[..<range.lowerBound])
            }
        }
        return briefing.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shouldAcceptAIOutput(despite issues: [String], menuLocked: Bool = false) -> Bool {
        guard !issues.isEmpty else { return false }
        return issues.allSatisfy { validationDisposition(for: $0, menuLocked: menuLocked) == .acceptableWarning }
    }

    func validationDisposition(for issue: String, menuLocked: Bool = false) -> ValidationIssueDisposition {
        let isPrimeHypertrophyMiss = issue.contains("targets") && issue.contains("but never includes a prime")

        if menuLocked {
            // Only two kinds of finding may discard a locked-menu week — see
            // `lockedMenuHardFailurePatterns`. Everything below that line is a quality verdict,
            // and the ordering here answers one question: can the layer being judged actually
            // act on it?
            //
            // This check stays FIRST, ahead of `acceptableWarningIssuePatterns`, so the allow-list
            // is genuinely authoritative. Putting the warning list first made it the real
            // authority: any future finding whose wording matched both lists would resolve to
            // `.acceptableWarning`, and a structurally broken or over-volume week would ship. The
            // two lists do not overlap today, and this ordering is what keeps that from being a
            // fact anyone has to re-verify by hand.
            if matchesValidationIssue(issue, patterns: lockedMenuHardFailurePatterns) {
                return .hardFailure
            }
            if matchesValidationIssue(issue, patterns: acceptableWarningIssuePatterns) {
                return .acceptableWarning
            }
            if matchesValidationIssue(issue, patterns: menuLockedDemotionPatterns) || isPrimeHypertrophyMiss {
                return .acceptableWarning
            }
            if matchesValidationIssue(issue, patterns: correctionWorthyIssuePatterns) {
                return .correctionPass
            }
            // The inverted default, and the point of this whole branch.
            //
            // This used to fall through to `.hardFailure`, which meant every quality rule anyone
            // wrote was a coin flip: if its wording was not already listed above, it set
            // `hasPlannerOrStructuralFailure`, skipped the correction pass, and discarded every
            // paid candidate — and the only way to discover that was to pay for a generation and
            // watch it happen. That is how the BASE-001 zero-coverage finding and the
            // lower-body-balance finding each cost a full week of paid candidates before being
            // added to the demotion list by hand.
            //
            // An unclassified finding is by definition one nobody has reasoned about, so we
            // cannot claim the AI is able to fix it. `.correctionPass` is not the safe guess
            // either: a finding that survives the correction pass still fails
            // `shouldAcceptAIOutput` and discards the week, so guessing wrong there costs an
            // extra paid call AND the candidates. Shipping it as a visible warning — it reaches
            // `validatorWarnings` and the Generator Lab either way — is the honest failure mode.
            // A new rule that IS repairable belongs in `correctionWorthyIssuePatterns`; that is
            // now an opt-in for spending money rather than the default.
            return .acceptableWarning
        }

        // Unlocked path, unchanged: the generator can still change exercise selection here, so a
        // finding nobody has classified stays strict.
        if matchesValidationIssue(issue, patterns: acceptableWarningIssuePatterns) {
            return .acceptableWarning
        }
        if matchesValidationIssue(issue, patterns: correctionWorthyIssuePatterns) || isPrimeHypertrophyMiss {
            return .correctionPass
        }
        return .hardFailure
    }

    /// The only findings allowed to throw away a locked-menu week. Deliberately an ALLOW-list.
    ///
    /// Two kinds qualify:
    ///
    ///  * **Shape** — the response is not a usable program at all (wrong day count, duplicate day
    ///    numbers, empty required fields, invalid sets/reps/rest). Accepting these ships something
    ///    broken rather than something mediocre, and they are genuinely the AI's output.
    ///  * **Safety** — the deterministic allocator OVER-delivered volume or fatigue. Too much work
    ///    is a real risk to the lifter, and it means the planner itself produced a bad week, so
    ///    falling back to the procedural build is the right answer rather than shipping it.
    ///
    /// Priority UNDER-delivery is deliberately absent: the allocator already funds priorities to
    /// its feasible maximum, no downstream consumer may add locked sets, and hard-failing there
    /// only denies the owner a program he paid for.
    var lockedMenuHardFailurePatterns: [String] {
        [
            // Safety — the planner over-delivered.
            "severely overshot its direct-set target",
            "overshot its direct-set target enough to create avoidable fatigue",
            "exceeds its focus-day direct-set cap",
            "exceeds its per-session direct-set cap",
            "exceeds the maintenance weekly volume ceiling",

            // Shape — not a usable week.
            "Must contain exactly 7 days.",
            "dayNumber values must exactly match",
            "Duplicate dayNumber values found.",
            "Training days must be between 4 and 6.",
            "Rest days must be between 1 and 3.",
            "daysPerWeek should be between 4 and 6.",
            "must have 5-8 exercises.",
            "has empty dayName.",
            "has an exercise with empty exerciseName.",
            "has invalid sets.",
            "has invalid restSeconds.",
            "has empty reps.",
            "Total training exercises are too low.",
            "is rest day but has exercises.",
            "All days are rest days.",
            "programName is empty.",
            "programSummary is empty.",
            "weekSummary is empty.",
            // Anchored to the template's unique opening rather than the mid-sentence fragment
            // "but the generated week has" — that phrasing is generic enough that an unrelated
            // count-mismatch message could pick it up and hard-fail a week this list exists to
            // protect. Every other blueprint finding starts "Blueprint priority '...'".
            "Blueprint calls for"
        ]
    }

    func matchesValidationIssue(_ issue: String, patterns: [String]) -> Bool {
        patterns.contains { issue.contains($0) }
    }

    var acceptableWarningIssuePatterns: [String] {
        [
            "undershot its targeted exercise-slot goal",
            "undershot its weighted stimulus target",
            "Too few anchor lifts carried over",
            "substitution significantly increases shoulder risk",
            // Both of the following are pure EXERCISE-SELECTION verdicts, and they are listed
            // here rather than left to fall through because the two paths disagree by default:
            // an unclassified finding is an acceptable warning under menu-lock and a HARD FAILURE
            // unlocked. Neither layer being judged can act on either one. Under menu-lock the AI
            // is forbidden from adding a movement, and on the procedural path the planner's own
            // best-effort placement (`enforceHorizontalPullCoverage`,
            // `enforceMaintenanceExposureBreadth`) has already run and found no room. Discarding
            // a week over a slot that provably could not be placed repairs nothing and denies the
            // owner a program he paid for — the same reasoning that demoted zero-coverage.
            "no horizontal pull at all",
            "falls below the maintenance weekly volume floor",
        ]
    }

    var correctionWorthyIssuePatterns: [String] {
        [
            "is concentrated into overly fatiguing sessions",
            "exceeds its focus-day direct-set cap",
            "exceeds its per-session direct-set cap",
            "carries too much total fatigue load",
            "overshot its direct-set target enough to create avoidable fatigue",
            "exceeds the maintenance weekly volume ceiling",
            "contradicts the app's logged progression verdict",
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
            "stacks too many",
            "Trim redundant focus work",
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
            "session notes are generic",
            // Rewriting one sentence is the textbook correction-pass repair: it touches no
            // set, exercise, or day structure, and `correctionTactics` scopes the edit to the
            // offending note. It used to fall through to .hardFailure, which sets
            // hasPlannerOrStructuralFailure and SKIPS the correction pass outright — so a
            // single stray phrase in one note out of ~30 discarded every paid candidate for
            // the week and dropped to the procedural generator without ever attempting the
            // cheap fix. Structural invariants deserve that treatment; a sentence does not.
            "notes contain load/rep progression instructions",
            "notes are empty or too short",
            // A missing targetRIR is squarely AI-owned — it is a field the model writes and the
            // menu lock does not touch — so it earns the cheap repair. Listed explicitly because
            // the locked-menu default is now `.acceptableWarning`: without this it would ship as
            // a warning rather than be fixed.
            "is missing targetRIR",
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
            "substitution significantly increases fatigue",
            "did not follow the Pre-Selected Exercise Menu"
        ]
    }

    var menuLockedDemotionPatterns: [String] {
        [
            // Priority UNDER-delivery in a locked-menu flow. The deterministic allocator owns
            // set counts and always funds priorities to its feasible maximum, so a residual
            // shortfall cannot be repaired by another AI call or by the procedural fallback
            // (which shares this validator). It is also not dangerous. Surface it as an honest
            // warning instead of a hard failure that would leave the user with no program at
            // all. The upstream priority-coverage pass is what keeps these shortfalls rare.
            "missed its direct-set target",
            "missed its frequency target",
            "minimum viable stimulus threshold",
            "uses too many weekly exercise variations",
            "was supposed to emphasize",
            "but never includes a prime",
            "opens its",
            "is supposed to emphasize quads",
            "stacks too many",
            "the generated day reads as",
            // Lower-body balance. Like its two siblings above (both already demoted), this is a
            // verdict on WHICH EXERCISES the day contains — the one thing a locked menu forbids
            // every downstream consumer from touching. The AI cannot swap in a squat, and the
            // procedural fallback reads the same menu, so as a correction-worthy issue it
            // survived the retry AND the correction pass and then failed the whole candidate
            // set. Live cost on one Week 1: two paid candidates plus a paid correction pass,
            // all scoring 5 on this identical finding, all discarded, week shipped from the
            // fallback with generic cues.
            //
            // `enforceLowerSessionKneeAnchor` now repairs this at the menu, where exercise
            // selection is actually allowed to happen, so reaching here means the repair found
            // no affordable, non-avoided, unused quad anchor at all. That is an honest warning
            // — `WorkoutValidatorNotice` already carries the plain-language copy for it — not a
            // reason to throw away work the user paid for and cannot get repaired.
            "reads as a broad lower-body session",
            // BASE-001 zero-coverage. This is a property of the MENU, and in a locked-menu flow
            // the menu is already final: the AI is forbidden from changing it and the procedural
            // fallback consumes the same one, so no downstream consumer can add the missing
            // movement. `enforceBaselineMuscleCoverage` is the pass that owns this floor, and it
            // gives up honestly when no style-compatible, non-avoided candidate fits — usually
            // because the lifter's pain flags removed every direct option for that muscle.
            //
            // Leaving it a hard failure cost the owner twice over: it set
            // hasPlannerOrStructuralFailure (discarding every paid candidate AND skipping the
            // correction pass that would have fixed the week's other, repairable findings), and
            // then it made `validatedProceduralWeek*` throw, so the week ended as a raw parse
            // error instead of a program. `WorkoutValidatorNotice` already carries the
            // plain-language `.attention` notice for this exact string — a notice that could
            // never be reached while the finding hard-failed.
            "receives zero direct sets this week"
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

    func scoreValidationIssues(_ issues: [String], menuLocked: Bool = false) -> Int {
        issues.reduce(0) { total, issue in
            switch validationDisposition(for: issue, menuLocked: menuLocked) {
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

        // Same reasoning as the daily-fatigue loop: substitute-quality findings reach the user
        // and the correction prompt, so they must not be ordered by dictionary hashing.
        for style in currentByStyle.keys.sorted() {
            guard let currentDays = currentByStyle[style],
                  let previousDays = previousByStyle[style] else { continue }

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

                // Set iteration order is unspecified; sort so repeated runs emit the same
                // substitute findings in the same order.
                let droppedKeys = previousKeys.subtracting(currentKeys).sorted()
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

    /// Align any explicit per-exercise set-count claim in a coaching note with the
    /// structured `sets` value. Deterministic set projection (and set polishing) can change an
    /// exercise's set count after the note was written, leaving prose like "all 4 sets" /
    /// "complete 4 clean sets" contradicting a now-smaller structured count — which both
    /// shows the wrong number of log rows and makes the in-app progression cue greenlight a
    /// load increase the note says to hold. This rewrite is deliberately narrow: it only
    /// touches numbers that quantify THIS exercise's sets ("all N sets", "N clean sets",
    /// "complete N sets", "do/across/over N sets", "N sets of …"). Weekly-volume references
    /// such as "the 10 direct sets the blueprint prescribes", rep counts, and loads are
    /// never rewritten.
    func reconciledSetCountNotes(_ notes: String, toSetCount sets: Int) -> String {
        guard sets > 0, !notes.isEmpty else { return notes }
        let n = String(sets)
        let rules: [(pattern: String, template: String)] = [
            (#"(?i)\b(all\s+)\d+(\s+(?:clean\s+|quality\s+|working\s+|hard\s+)?sets)\b"#, "$1\(n)$2"),
            (#"(?i)\b(complete\s+)\d+(\s+(?:clean\s+|quality\s+|working\s+|hard\s+)?sets)\b"#, "$1\(n)$2"),
            (#"(?i)\b\d+(\s+(?:clean|quality|working|hard)\s+sets)\b"#, "\(n)$1"),
            (#"(?i)\b(across|over|do|perform)\s+\d+(\s+sets)\b"#, "$1 \(n)$2"),
            (#"(?i)\b\d+(\s+sets\s+of)\b"#, "\(n)$1"),
        ]
        var result = notes
        for rule in rules {
            result = result.replacingOccurrences(of: rule.pattern, with: rule.template, options: .regularExpression)
        }
        return result
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
