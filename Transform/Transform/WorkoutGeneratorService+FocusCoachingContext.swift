import Foundation

extension ClaudeService {
    func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { (keyword: String) -> Bool in
            text.contains(keyword)
        }
    }

    func isSupportOrCorrectivePattern(_ normalizedName: String) -> Bool {
        containsAny(
            normalizedName,
            keywords: ["y raise", "trap 3", "scaption", "external rotation", "pull apart", "wall slide", "serratus"]
        )
    }

    func focusOrderingPriority(exerciseName: String, muscleTarget: String, focusArea: String) -> Int {
        switch focusStimulusKind(exerciseName: exerciseName, muscleTarget: muscleTarget, focusArea: focusArea) {
        case .prime:
            return 0
        case .secondary:
            return 1
        case .support:
            return 2
        case .none:
            return 3
        }
    }

    func focusStimulusKind(exerciseName: String, muscleTarget: String, focusArea: String) -> FocusStimulusKind {
        let metadata = exerciseMetadata(forExerciseName: exerciseName, muscleTarget: muscleTarget)
        let focus = normalizedPriorityText(focusArea)
        let nameText = normalizedPriorityText(exerciseName)
        let combinedText = "\(nameText) \(normalizedPriorityText(muscleTarget))"
        let focusAliases = Set(stimulusAreaAliases(for: focusArea).map(normalizedPriorityText))
        let primaryAliases = Set(metadata.primaryAreas.flatMap { stimulusAreaAliases(for: $0) }.map(normalizedPriorityText))
        let secondaryAliases = Set(metadata.secondaryAreas.flatMap { stimulusAreaAliases(for: $0) }.map(normalizedPriorityText))

        let touchesFocus = !focusAliases.isDisjoint(with: primaryAliases)
            || !focusAliases.isDisjoint(with: secondaryAliases)
            || containsAny(combinedText, keywords: priorityCoverageKeywords(for: focusArea))
        guard touchesFocus else { return .none }

        let coreFocusAliases = Set(
            ["Core/Abs", "Abs", "Lower Abs", "Anterior Core", "Obliques", "Serratus"]
                .map(normalizedPriorityText)
        )
        if metadata.movementPattern == "Carry",
           !focusAliases.isDisjoint(with: coreFocusAliases) {
            return .support
        }

        if containsAny(combinedText, keywords: ["y raise", "trap 3", "scaption", "external rotation", "pull apart", "wall slide"]) {
            return .support
        }

        switch focus {
        case let value where value.contains("posterior delt") || value.contains("rear delt"):
            if containsAny(combinedText, keywords: ["reverse pec deck", "reverse fly", "rear delt fly", "rear delt row", "cable rear delt", "rear delt raise", "reverse cable crossover"]) {
                return .prime
            }
            if containsAny(combinedText, keywords: ["face pull"]) {
                return .secondary
            }
        case let value where value.contains("lateral delt") || value.contains("side delt"):
            if containsAny(combinedText, keywords: ["lateral raise"]) {
                return .prime
            }
            if containsAny(combinedText, keywords: ["upright row"]) {
                return .secondary
            }
            if containsAny(combinedText, keywords: ["press", "arnold"]) {
                return .support
            }
        case let value where value.contains("upper chest") || value.contains("clavicular"):
            if containsAny(combinedText, keywords: ["incline press", "incline dumbbell press", "incline barbell press", "low incline", "incline fly", "incline cable fly", "incline machine fly", "reverse grip", "machine incline"]) {
                return .prime
            }
            if containsAny(combinedText, keywords: ["bench press", "chest press", "pec deck", "fly", "dip"]) {
                return .secondary
            }
        case let value where value.contains("bicep"):
            if containsAny(combinedText, keywords: ["curl", "bayesian curl", "preacher"]) {
                return .prime
            }
        case let value where value.contains("tricep"):
            if containsAny(combinedText, keywords: ["pressdown", "extension", "skull crusher", "jm press", "kickback"]) {
                return .prime
            }
            if containsAny(combinedText, keywords: ["close-grip", "dip"]) {
                return .secondary
            }
        case let value where containsPriorityPhrase(in: value, keywords: ["lat", "lats", "latissimus dorsi", "latissimus"]):
            if containsAny(combinedText, keywords: ["pulldown", "pull-up", "pull up", "pullup", "chinup", "chin up", "chin-up", "straight-arm pulldown", "pullover"]) {
                return .prime
            }
            if containsAny(combinedText, keywords: ["row"]) {
                return .secondary
            }
        case let value where value.contains("upper back") || value.contains("mid back"):
            if containsAny(combinedText, keywords: ["row", "chest-supported row", "machine row", "t bar row", "t-bar row"]) {
                return .prime
            }
            if containsAny(combinedText, keywords: ["face pull", "reverse pec deck", "reverse fly"]) {
                return .secondary
            }
        case let value where value == "shoulders" || value.contains("deltoid") || value.contains("delt"):
            if containsAny(combinedText, keywords: ["lateral raise", "reverse pec deck", "reverse fly", "rear delt row", "shoulder press", "overhead press", "arnold press"]) {
                return .prime
            }
            if containsAny(combinedText, keywords: ["face pull"]) {
                return .secondary
            }
        case let value where value == "arms":
            if containsAny(combinedText, keywords: ["curl", "pressdown", "extension", "skull crusher", "close-grip", "jm press", "hammer curl"]) {
                return .prime
            }
        default:
            break
        }

        if !focusAliases.isDisjoint(with: primaryAliases) {
            return .prime
        }
        if !focusAliases.isDisjoint(with: secondaryAliases) {
            return .secondary
        }
        return .support
    }

    func focusStimulusCredit(for kind: FocusStimulusKind) -> Double {
        switch kind {
        case .prime:
            return 1.0
        case .secondary:
            return 0.7
        case .support:
            return 0.35
        case .none:
            return 0
        }
    }

    func focusDirectSetCredit(for kind: FocusStimulusKind) -> Double {
        switch kind {
        case .prime:
            return 1.0
        case .secondary:
            return 0.7
        case .support, .none:
            return 0
        }
    }

    func focusStimulusSummary(for day: WorkoutDayResponse, focusArea: String) -> FocusStimulusSummary {
        var matchedExercises = 0
        var primeExercises = 0
        var supportExercises = 0
        var qualityDirectSets = 0.0
        var firstMatchedKind: FocusStimulusKind = .none
        var firstPrimeIndex: Int?

        for (index, exercise) in day.exercises.enumerated() {
            let kind = focusStimulusKind(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                focusArea: focusArea
            )
            guard kind != .none else { continue }

            matchedExercises += 1
            qualityDirectSets += Double(exercise.sets) * focusDirectSetCredit(for: kind)

            if firstMatchedKind == .none {
                firstMatchedKind = kind
            }
            if kind == .prime {
                primeExercises += 1
                if firstPrimeIndex == nil {
                    firstPrimeIndex = index
                }
            } else if kind == .support {
                supportExercises += 1
            }
        }

        return FocusStimulusSummary(
            matchedExercises: matchedExercises,
            primeExercises: primeExercises,
            supportExercises: supportExercises,
            qualityDirectSets: qualityDirectSets,
            firstMatchedKind: firstMatchedKind,
            firstPrimeIndex: firstPrimeIndex
        )
    }

    // EvidenceProfile.md PROG-001 [confidence: low-moderate]
    /// Structured week-phase effort target for procedurally built exercises — the
    /// numeric replacement for the retired prose "progression cue" sentence (whose
    /// "2-3 reps in reserve" text the note cleaner once mangled into a literal
    /// on-screen "finish sets with 2-"). Week 1-2 accumulate at RIR 2, week 3
    /// peaks at RIR 1, week 4 deloads at RIR 3.
    func proceduralTargetRIR(for weekNumber: Int) -> Int {
        switch weekNumber {
        case 3: return 1
        case 4: return 3
        default: return 2
        }
    }

    /// Narrow, high-precision detector for load/rep-progression prose in EXERCISE
    /// notes. The validator uses it to keep notes execution-only, so keep fragments
    /// unambiguous — a false positive here burns a paid retry.
    func notesContainProgressionInstruction(_ notes: String) -> Bool {
        let normalized = normalizedPriorityText(notes)
        return containsAny(normalized, keywords: ProgressionProseFragments.validatorBanned)
    }

    func polishedExerciseNotes(
        rawNotes: String,
        exerciseName: String,
        muscleTarget: String,
        weekNumber: Int,
        exerciseIndex: Int,
        cuesAlreadyOnDay: Set<String> = []
    ) -> String {
        let trimmed = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Trust the AI. Only fall back to procedural content when the note is empty or
        // truly unusable (a few words). Previously we replaced perfectly good personalized
        // notes with templated cues whenever they didn't match keyword heuristics — that
        // was the "generic AI slop" users were seeing.
        // The decode stand-in is treated as absent, not as content. It clears the length
        // threshold, so without this every exercise whose response omitted `notes` would keep
        // the same hard-coded sentence — reintroducing, from a different direction, exactly
        // the duplicate-cue problem this system was built to remove.
        if isEmptyOrTooShortInsight(trimmed) || trimmed == WorkoutExerciseResponse.absentNoteDefault {
            // This is the AI-repair path: the model returned nothing usable for THIS
            // exercise, so a procedural cue stands in. It previously always took the most
            // generic template branch (focus was hardcoded empty), which is why substituted
            // cues read as the most obviously machine-written text in the app.
            //
            // `cuesAlreadyOnDay` carries the notes already placed on this day, so two
            // substitutions in one session cannot land on the same sentence. Without it the
            // day-scoped uniqueness guarantee held only for fully procedural days — and the
            // AI path is the default, so the guarantee would have been mostly theoretical.
            //
            // `coachingSource` separately records that this cue was substituted, so a mixed
            // day stays auditable rather than silently indistinguishable from AI output.
            return evidenceTunedCoachingLanguage(
                CoachingVoice.cue(
                    forName: exerciseName,
                    muscleTarget: muscleTarget,
                    avoiding: cuesAlreadyOnDay
                )
            )
        }

        // Execution-only notes: the deterministic progression banner owns load/rep
        // advice. (This used to APPEND a templated progression cue whenever a note
        // lacked one — manufacturing the exact two-voices contradiction the banner
        // filter then had to strip.)
        return evidenceTunedCoachingLanguage(trimmed)
    }

    func isEmptyOrTooShortInsight(_ notes: String) -> Bool {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let wordCount = trimmed.split { $0.isWhitespace || $0.isNewline }.count
        return wordCount < 5
    }


    func withSourceLabel(_ summary: String, sourceLabel: String) -> String {
        let cleaned = summary.trimmedOr(default: "Weekly progression update.")
        let withoutExistingLabel = stripSourceLabel(from: cleaned)
        let trimmedSourceLabel = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSourceLabel.hasPrefix(aiSourceLabel) {
            return "\(aiSourceLabel) \(withoutExistingLabel)"
        }
        if trimmedSourceLabel.hasPrefix(fallbackSourceLabel) {
            return "\(fallbackSourceLabel) \(withoutExistingLabel)"
        }
        return "\(trimmedSourceLabel) \(withoutExistingLabel)"
    }

    func stripSourceLabel(from summary: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(aiSourceLabel) {
            return String(trimmed.dropFirst(aiSourceLabel.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix(fallbackSourceLabel) {
            return String(trimmed.dropFirst(fallbackSourceLabel.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    func labeledProgramResponse(_ program: WorkoutProgramResponse, sourceLabel: String) -> WorkoutProgramResponse {
        WorkoutProgramResponse(
            programName: program.programName,
            programSummary: withSourceLabel(program.programSummary, sourceLabel: sourceLabel),
            splitType: program.splitType,
            daysPerWeek: program.daysPerWeek,
            days: program.days
        )
    }

    func labeledWeekResponse(_ week: WorkoutWeekResponse, sourceLabel: String) -> WorkoutWeekResponse {
        WorkoutWeekResponse(
            weekSummary: withSourceLabel(week.weekSummary, sourceLabel: sourceLabel),
            days: week.days
        )
    }

    func polishGenericDayNotes(
        _ days: [WorkoutDayResponse],
        weekNumber: Int,
        trainingIntent: TrainingIntentPlan,
        blueprint: ProgramBlueprint
    ) -> [WorkoutDayResponse] {
        days.enumerated().map { offset, day in
            guard !day.isRestDay else { return day }
            guard isGenericSessionNote(day.notes, exercises: day.exercises) else { return day }

            let plan = offset < blueprint.dayPlans.count ? blueprint.dayPlans[offset] : nil
            let style = plan?.style ?? inferredDayStyle(dayName: day.dayName, muscleGroups: day.muscleGroups) ?? "Training"
            let focus = plan?.focusArea ?? ""
            let focusIntent = plan.flatMap { focusIntentForArea($0.focusArea, within: trainingIntent) }

            let enrichedNotes = proceduralDayNotes(
                style: style,
                weekNumber: weekNumber,
                exercises: day.exercises,
                focus: focus,
                focusIntent: focusIntent,
                blueprint: blueprint
            )

            return WorkoutDayResponse(
                dayNumber: day.dayNumber,
                dayName: day.dayName,
                muscleGroups: day.muscleGroups,
                isRestDay: day.isRestDay,
                notes: enrichedNotes,
                exercises: day.exercises
            )
        }
    }

    func polishGenericProgramNotes(
        _ program: WorkoutProgramResponse,
        weekNumber: Int,
        trainingIntent: TrainingIntentPlan,
        blueprint: ProgramBlueprint
    ) -> WorkoutProgramResponse {
        let polished = polishGenericDayNotes(program.days, weekNumber: weekNumber, trainingIntent: trainingIntent, blueprint: blueprint)
        return WorkoutProgramResponse(
            programName: program.programName,
            programSummary: program.programSummary,
            splitType: program.splitType,
            daysPerWeek: program.daysPerWeek,
            days: polished
        )
    }

    func polishGenericWeekNotes(
        _ week: WorkoutWeekResponse,
        weekNumber: Int,
        trainingIntent: TrainingIntentPlan,
        blueprint: ProgramBlueprint
    ) -> WorkoutWeekResponse {
        let polished = polishGenericDayNotes(week.days, weekNumber: weekNumber, trainingIntent: trainingIntent, blueprint: blueprint)
        return WorkoutWeekResponse(
            weekSummary: week.weekSummary,
            days: polished
        )
    }

    func debugProgramReport(
        stage: WorkoutGeneratorDebugStage,
        mode: WorkoutGeneratorDebugMode,
        weekNumber: Int,
        sourceLabel: String,
        acceptedWithWarnings: Bool,
        usedFallback: Bool,
        displayTitle: String,
        splitType: String,
        analysisSummary: String,
        trainingIntentSummary: String,
        blueprintSummary: String,
        previousWeekReference: String?,
        systemPrompt: String,
        userPrompt: String,
        warnings: [String],
        finalIssues: [String],
        attempts: [WorkoutGeneratorDebugAttempt],
        replayInputJSON: String?,
        response: WorkoutProgramResponse
    ) throws -> WorkoutGeneratorDebugReport {
        WorkoutGeneratorDebugReport(
            stage: stage,
            mode: mode,
            weekNumber: weekNumber,
            usedAPI: mode.usesAPI,
            sourceLabel: sourceLabel,
            acceptedWithWarnings: acceptedWithWarnings,
            usedFallback: usedFallback,
            displayTitle: displayTitle,
            splitType: splitType,
            analysisSummary: analysisSummary,
            trainingIntentSummary: trainingIntentSummary,
            blueprintSummary: blueprintSummary,
            previousWeekReference: previousWeekReference,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            warnings: warnings,
            finalIssues: finalIssues,
            attempts: attempts,
            replayInputJSON: replayInputJSON,
            terminalError: nil,
            finalJSON: try encodeDebugJSONString(response),
            previewSummary: response.programSummary,
            previewDays: response.days
        )
    }

    func debugWeekReport(
        mode: WorkoutGeneratorDebugMode,
        weekNumber: Int,
        sourceLabel: String,
        acceptedWithWarnings: Bool,
        usedFallback: Bool,
        displayTitle: String,
        splitType: String,
        analysisSummary: String,
        trainingIntentSummary: String,
        blueprintSummary: String,
        previousWeekReference: String?,
        systemPrompt: String,
        userPrompt: String,
        warnings: [String],
        finalIssues: [String],
        attempts: [WorkoutGeneratorDebugAttempt],
        replayInputJSON: String?,
        response: WorkoutWeekResponse
    ) throws -> WorkoutGeneratorDebugReport {
        WorkoutGeneratorDebugReport(
            stage: .nextWeek,
            mode: mode,
            weekNumber: weekNumber,
            usedAPI: mode.usesAPI,
            sourceLabel: sourceLabel,
            acceptedWithWarnings: acceptedWithWarnings,
            usedFallback: usedFallback,
            displayTitle: displayTitle,
            splitType: splitType,
            analysisSummary: analysisSummary,
            trainingIntentSummary: trainingIntentSummary,
            blueprintSummary: blueprintSummary,
            previousWeekReference: previousWeekReference,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            warnings: warnings,
            finalIssues: finalIssues,
            attempts: attempts,
            replayInputJSON: replayInputJSON,
            terminalError: nil,
            finalJSON: try encodeDebugJSONString(response),
            previewSummary: response.weekSummary,
            previewDays: response.days
        )
    }

    func debugProgramFailureReport(
        stage: WorkoutGeneratorDebugStage,
        mode: WorkoutGeneratorDebugMode,
        weekNumber: Int,
        displayTitle: String,
        splitType: String,
        analysisSummary: String,
        trainingIntentSummary: String,
        blueprintSummary: String,
        previousWeekReference: String?,
        systemPrompt: String,
        userPrompt: String,
        warnings: [String],
        attempts: [WorkoutGeneratorDebugAttempt],
        terminalError: String
    ) -> WorkoutGeneratorDebugReport {
        WorkoutGeneratorDebugReport(
            stage: stage,
            mode: mode,
            weekNumber: weekNumber,
            usedAPI: mode.usesAPI,
            sourceLabel: "[AI Request Failed]",
            acceptedWithWarnings: false,
            usedFallback: false,
            displayTitle: displayTitle,
            splitType: splitType,
            analysisSummary: analysisSummary,
            trainingIntentSummary: trainingIntentSummary,
            blueprintSummary: blueprintSummary,
            previousWeekReference: previousWeekReference,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            warnings: warnings,
            finalIssues: [],
            attempts: attempts,
            replayInputJSON: nil,
            terminalError: terminalError,
            finalJSON: "",
            previewSummary: "Live AI did not return a usable program. Review the attempt trace and terminal error details below.",
            previewDays: []
        )
    }

    func debugWeekFailureReport(
        weekNumber: Int,
        displayTitle: String,
        splitType: String,
        analysisSummary: String,
        trainingIntentSummary: String,
        blueprintSummary: String,
        previousWeekReference: String?,
        systemPrompt: String,
        userPrompt: String,
        warnings: [String],
        attempts: [WorkoutGeneratorDebugAttempt],
        terminalError: String
    ) -> WorkoutGeneratorDebugReport {
        WorkoutGeneratorDebugReport(
            stage: .nextWeek,
            mode: .liveAI,
            weekNumber: weekNumber,
            usedAPI: true,
            sourceLabel: "[AI Request Failed]",
            acceptedWithWarnings: false,
            usedFallback: false,
            displayTitle: displayTitle,
            splitType: splitType,
            analysisSummary: analysisSummary,
            trainingIntentSummary: trainingIntentSummary,
            blueprintSummary: blueprintSummary,
            previousWeekReference: previousWeekReference,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            warnings: warnings,
            finalIssues: [],
            attempts: attempts,
            replayInputJSON: nil,
            terminalError: terminalError,
            finalJSON: "",
            previewSummary: "Live AI did not return a usable week. Review the attempt trace and terminal error details below.",
            previewDays: []
        )
    }

    func sourceLabel(from summary: String, fallback: String) -> String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(aiSourceLabel) {
            return aiSourceLabel
        }
        if trimmed.hasPrefix(fallbackSourceLabel) {
            return fallbackSourceLabel
        }
        return fallback
    }

    func encodeDebugJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ClaudeError.parseError("Could not convert debug JSON into UTF-8 text.")
        }
        return text
    }

    // MARK: - Context Helpers

    func analysisContext(from analysis: BodyAnalysisResult) -> String {
        let priority = analysis.programmingPriorityAreas.joined(separator: ", ")
        let workoutRecs = analysis.workoutRecommendations.joined(separator: " | ")
        let dietRecs = analysis.dietRecommendations.joined(separator: " | ")
        let inputContextSummary = analysis.inputContext?.generationSummary.trimmedOr(default: "") ?? ""

        // Region breakdown — rich, per-region signal the AI can tie exercises to.
        let regions: String
        if analysis.regionBreakdown.isEmpty {
            regions = "(none provided)"
        } else {
            regions = analysis.regionBreakdown
                .map { region -> String in
                    let name = region.region.trimmedOr(default: "Region")
                    let assessment = region.assessment.trimmedOr(default: "")
                    let priority = region.priority.trimmedOr(default: "")
                    let priorityPart = priority.isEmpty ? "" : " [priority: \(priority)]"
                    return "• \(name)\(priorityPart): \(assessment)"
                }
                .joined(separator: "\n")
        }

        // Macro targets (if provided, surface them for context only — not for programming).
        let macros: String
        if let m = analysis.macroTargets {
            macros = "calories \(m.calories), protein \(m.proteinG)g, carbs \(m.carbsG)g, fat \(m.fatG)g"
        } else {
            macros = "(none provided)"
        }

        return """
        Overall assessment:
        \(analysis.overallAssessment.trimmedOr(default: "(not provided)"))

        Top leverage change: \(analysis.topLeverageChange.trimmedOr(default: "(not provided)"))

        Priority muscles (these drive weekly volume allocation): \(priority.isEmpty ? "(none)" : priority)

        User profile, check-in, and recent progress context:
        \(inputContextSummary.isEmpty ? "(none saved with this analysis)" : inputContextSummary)

        Region breakdown:
        \(regions)

        Workout recommendations from analysis: \(workoutRecs.isEmpty ? "(none)" : workoutRecs)

        Postural notes (must be addressed in warm-ups): \(analysis.posturalNotes.trimmedOr(default: "(none)"))

        Injury risk notes (must shape exercise selection & mobility work): \(analysis.injuryRiskNotes.trimmedOr(default: "(none)"))

        Metabolic health notes: \(analysis.metabolicHealthNotes.trimmedOr(default: "(none)"))

        Psychological / behavioral insights (may influence session framing): \(analysis.psychologicalInsights.trimmedOr(default: "(none)"))

        Estimated body fat: \(analysis.estimatedBodyFat.trimmedOr(default: "(not provided)"))

        Macro targets (context): \(macros)

        Diet recommendations (context): \(dietRecs.isEmpty ? "(none)" : dietRecs)
        """
    }

    func analysisContext(from analysisJSON: String) -> String {
        let cleaned = cleanedJSONText(analysisJSON)

        if let analysis = decodedAnalysisResult(from: cleaned) {
            return analysisContext(from: analysis)
        }

        return cleaned.isEmpty ? "No analysis context provided." : cleaned
    }

    func priorityMuscles(from analysisJSON: String) -> [String] {
        let cleaned = cleanedJSONText(analysisJSON)

        if let analysis = decodedAnalysisResult(from: cleaned) {
            return analysis.programmingPriorityAreas.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        return []
    }

    func decodePreviousWeekDays(from previousWeekJSON: String) -> [WorkoutDayResponse] {
        let cleaned = cleanedJSONText(previousWeekJSON)

        for candidate in jsonCandidates(from: cleaned) {
            guard let data = candidate.data(using: .utf8) else { continue }

            if let program = try? JSONDecoder().decode(WorkoutProgramResponse.self, from: data), !program.days.isEmpty {
                return program.days.sorted { $0.dayNumber < $1.dayNumber }
            }

            if let week = try? JSONDecoder().decode(WorkoutWeekResponse.self, from: data), !week.days.isEmpty {
                return week.days.sorted { $0.dayNumber < $1.dayNumber }
            }
        }

        return []
    }

    func cleanedJSONText(_ rawJSON: String) -> String {
        rawJSON
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decodedAnalysisResult(from cleanedAnalysisJSON: String) -> BodyAnalysisResult? {
        for candidate in jsonCandidates(from: cleanedAnalysisJSON) {
            guard let data = candidate.data(using: .utf8),
                  let analysis = try? JSONDecoder().decode(BodyAnalysisResult.self, from: data) else {
                continue
            }
            return analysis
        }

        return nil
    }

    func decodedAnalysisResultWithWarning(from cleanedAnalysisJSON: String) -> AnalysisDecodeResult {
        if let analysis = decodedAnalysisResult(from: cleanedAnalysisJSON) {
            return AnalysisDecodeResult(analysis: analysis, warning: nil)
        }

        let trimmed = cleanedAnalysisJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let warning = "Structured analysis JSON was empty, so the generator used text fallback context only."
            print("[WorkoutGeneratorService] \(warning)")
            return AnalysisDecodeResult(analysis: nil, warning: warning)
        }

        let warning = "Structured analysis JSON could not be decoded, so the generator fell back to text-derived intent instead of full structured analysis."
        print("[WorkoutGeneratorService] \(warning)")
        return AnalysisDecodeResult(analysis: nil, warning: warning)
    }

    func shouldAbortFallback(for error: Error) -> Bool {
        if error.isTransientNetworkFailure || error.isStructuredResponseEnvelopeFailure {
            return true
        }

        guard let claudeError = error as? ClaudeError else { return true }

        switch claudeError {
        case .apiError:
            return true
        case .emptyResponse, .parseError:
            return !error.isRecoverableStructuredOutputFailure
        default:
            return true
        }
    }

    func correctionIssue(for error: Error) -> String {
        if let claudeError = error as? ClaudeError {
            switch claudeError {
            case .parseError(let detail):
                return "Previous structured response was unusable (\(detail)). Call the tool again with complete, valid fields."
            case .emptyResponse:
                return "Previous structured response was empty. Call the tool again with complete, valid fields."
            default:
                break
            }
        }

        return "Previous structured response was unusable (\(error.localizedDescription)). Call the tool again with complete, valid fields."
    }

    func terminalGenerationError(while action: String, underlying error: Error) -> Error {
        if error.isTransientNetworkFailure || error.isStructuredResponseEnvelopeFailure {
            return networkFailureError(while: action, underlying: error)
        }

        return error
    }

    func networkFailureError(while action: String, underlying error: Error) -> ClaudeError {
        ClaudeError.apiError("\(networkFailureSummary(for: error)) while \(action). No recovery-engine week was applied, so you can safely retry.")
    }

    private func networkFailureSummary(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The AI request timed out before Anthropic returned a complete structured response"
            case .networkConnectionLost:
                return "The network connection dropped before Anthropic returned a complete structured response"
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "The AI request could not reach Anthropic reliably"
            case .cancelled:
                return "The AI request was cancelled before completion"
            default:
                return "The AI request hit a transport error (\(urlError.code.rawValue))"
            }
        }

        if error.isStructuredResponseEnvelopeFailure {
            return "Anthropic returned an incomplete or malformed structured response envelope"
        }

        return "The AI request did not complete cleanly"
    }

    static func normalizedExerciseNameKey(_ name: String) -> String {
        let lower = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let allowed = lower.map { char -> Character in
            if char.isLetter || char.isNumber || char == " " {
                return char
            }
            return " "
        }

        return String(allowed)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func normalizeExerciseName(_ name: String) -> String {
        Self.normalizedExerciseNameKey(name)
    }
}

extension String {
    func trimmedOr(default fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
