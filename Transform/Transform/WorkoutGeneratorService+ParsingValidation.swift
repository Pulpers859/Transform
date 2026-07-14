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
                guard normalizeExerciseName(expectedName) != normalizeExerciseName(actualName) else { continue }

                issues.append("Day \(dayNumber) did not follow the Pre-Selected Exercise Menu at slot \(index + 1): expected \(expected.exerciseName), but generated \(actual.exerciseName).")
            }
        }

        var seen = Set<String>()
        return issues.filter { seen.insert($0).inserted }
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

        issues.append(contentsOf: validateNonPriorityMuscleVolume(
            days: days,
            blueprint: blueprint,
            recoveryTight: recoveryTight
        ))

        issues.append(contentsOf: validateDayPlans(days: days, blueprint: blueprint, dayStart: dayStart))

        for (dayNumber, fatigue) in stimulusReport.dailyFatigue where fatigue > maxDailyFatigueThreshold(for: days, dayNumber: dayNumber) {
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
        let priorityAliases = priorityAliasUnion(for: blueprint)
        // EvidenceProfile.md MAINT-001 [confidence: low-moderate]
        let maintenanceCeiling = recoveryTight ? 8.0 : 10.0

        for group in majorMuscleGroups {
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            guard aliases.isDisjoint(with: priorityAliases) else { continue }

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
            }
        }

        return issues
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

        let sentences = notes
            .split(whereSeparator: { ".;!?".contains($0) })
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
            case .addRepsInRange:
                continue
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

    func shouldAcceptAIOutput(despite issues: [String], menuLocked: Bool = false) -> Bool {
        guard !issues.isEmpty else { return false }
        return issues.allSatisfy { validationDisposition(for: $0, menuLocked: menuLocked) == .acceptableWarning }
    }

    func validationDisposition(for issue: String, menuLocked: Bool = false) -> ValidationIssueDisposition {
        if matchesValidationIssue(issue, patterns: acceptableWarningIssuePatterns) {
            return .acceptableWarning
        }
        if menuLocked && matchesValidationIssue(issue, patterns: menuLockedDemotionPatterns) {
            return .acceptableWarning
        }
        let isPrimeHypertrophyMiss = issue.contains("targets") && issue.contains("but never includes a prime")
        if menuLocked && isPrimeHypertrophyMiss {
            return .acceptableWarning
        }
        if matchesValidationIssue(issue, patterns: correctionWorthyIssuePatterns)
            || isPrimeHypertrophyMiss {
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
            "substitution significantly increases shoulder risk",
            // BASE-001 floor: with a locked menu the AI cannot add a missing exercise,
            // so this must never trigger a retry — the menu builder's coverage pass is
            // the enforcement; this line is the observability net.
            "receives zero direct sets this week"
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
            "substitution significantly increases fatigue",
            "did not follow the Pre-Selected Exercise Menu"
        ]
    }

    var menuLockedDemotionPatterns: [String] {
        [
            "missed its frequency target",
            "minimum viable stimulus threshold",
            "uses too many weekly exercise variations",
            "was supposed to emphasize",
            "but never includes a prime",
            "opens its",
            "is supposed to emphasize quads",
            "stacks too many",
            "the generated day reads as"
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

                let newSets = exercise.sets - setsToTrim
                let newExercise = WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: newSets,
                    reps: exercise.reps,
                    tempo: exercise.tempo,
                    restSeconds: exercise.restSeconds,
                    notes: reconciledSetCountNotes(exercise.notes, toSetCount: newSets),
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

                let trimmedSets = exercise.sets - 1
                let trimmedExercise = WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: trimmedSets,
                    reps: exercise.reps,
                    tempo: exercise.tempo,
                    restSeconds: exercise.restSeconds,
                    notes: reconciledSetCountNotes(exercise.notes, toSetCount: trimmedSets),
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

        // Third pass — non-priority maintenance ceiling (EvidenceProfile.md MAINT-001,
        // 2026-07-14 audit fix 3). This is
        // deterministic set reduction so the correction loop does not spend an API call on
        // filler volume the app can trim itself. Exercises crediting any priority area are
        // untouchable here so this pass can never fight the blueprint targets above.
        let maintenanceCeiling = recoveryTight ? 8.0 : 10.0
        let priorityAliases = priorityAliasUnion(for: blueprint)
        for group in majorMuscleGroups {
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            guard aliases.isDisjoint(with: priorityAliases) else { continue }

            var guardRail = 24
            while weeklyDirectSets(forGroupAliases: aliases, days: mutableDays) > maintenanceCeiling + 0.5,
                  guardRail > 0 {
                guardRail -= 1

                var candidate: (dayIndex: Int, exerciseIndex: Int, sets: Int)?
                for (di, day) in mutableDays.enumerated() where !day.isRestDay {
                    for (ei, exercise) in day.exercises.enumerated() {
                        guard exercise.sets > 2 else { continue }
                        guard exerciseDirectlyTargets(
                            groupAliases: aliases,
                            exerciseName: exercise.exerciseName,
                            muscleTarget: exercise.muscleTarget
                        ) else { continue }
                        let creditsPriority = blueprint.priorityAllocations.contains {
                            directSetCredit(for: exercise, area: $0.area) > 0
                        }
                        guard !creditsPriority else { continue }
                        if candidate == nil || exercise.sets > candidate!.sets {
                            candidate = (di, ei, exercise.sets)
                        }
                    }
                }

                guard let target = candidate else { break }
                let day = mutableDays[target.dayIndex]
                let exercise = day.exercises[target.exerciseIndex]
                let trimmedSets = exercise.sets - 1
                var updatedExercises = day.exercises
                updatedExercises[target.exerciseIndex] = WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: trimmedSets,
                    reps: exercise.reps,
                    tempo: exercise.tempo,
                    restSeconds: exercise.restSeconds,
                    notes: reconciledSetCountNotes(exercise.notes, toSetCount: trimmedSets),
                    muscleTarget: exercise.muscleTarget
                )
                mutableDays[target.dayIndex] = WorkoutDayResponse(
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

    /// Align any explicit per-exercise set-count claim in a coaching note with the
    /// structured `sets` value. The over-volume trimmer (and set polishing) can lower an
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
