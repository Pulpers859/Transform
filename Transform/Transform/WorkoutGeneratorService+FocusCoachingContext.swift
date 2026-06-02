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
            if containsAny(combinedText, keywords: ["incline press", "incline dumbbell press", "incline barbell press", "low incline", "incline fly", "reverse grip", "machine incline"]) {
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
            qualityDirectSets += Double(exercise.sets) * focusStimulusCredit(for: kind)

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

    func techniqueCue(for muscleTarget: String, exerciseName: String, index: Int) -> String {
        let target = normalizedPriorityText(muscleTarget)

        let cues: [String]
        if containsPriorityPhrase(in: target, keywords: ["chest", "upper chest", "pec"]) {
            cues = [
                "Lock your upper back down and use a 2-3 second eccentric so the pecs stay loaded through the full stretch.",
                "Keep shoulder blades retracted and drive the bar path slightly down-and-back to maximize chest tension."
            ]
        } else if containsPriorityPhrase(in: target, keywords: ["delt", "deltoid", "shoulder", "lateral deltoids", "rear deltoids", "anterior deltoids"]) {
            cues = [
                "Keep ribs down and raise through the scapular plane so delts stay loaded without shrugging.",
                "Control top-end positioning with a brief pause to remove momentum from each repetition."
            ]
        } else if containsPriorityPhrase(in: target, keywords: ["lat", "lats", "latissimus dorsi", "latissimus", "back", "upper back", "mid back"]) {
            cues = [
                "Initiate each rep by setting the scapula first, then pull with elbows to keep the lats doing the work.",
                "Control the lowering phase and avoid torso swing so tension stays in the back instead of momentum."
            ]
        } else if containsPriorityPhrase(in: target, keywords: ["quad", "quads", "hamstring", "hamstrings", "glute", "glutes", "legs", "posterior chain"]) {
            cues = [
                "Brace before every rep and keep a controlled eccentric to maintain joint position under load.",
                "Use full available range with stable foot pressure so target leg musculature carries the set."
            ]
        } else if containsPriorityPhrase(in: target, keywords: ["biceps", "triceps", "arms", "brachialis", "forearms"]) {
            cues = [
                "Keep elbows fixed and control the eccentric so tension stays on the arm musculature throughout.",
                "Use strict body position and a smooth tempo to prevent torso swing from stealing work."
            ]
        } else {
            cues = [
                "Use a controlled eccentric and stable setup to keep tension on the target muscle.",
                "Prioritize full range and repeatable rep mechanics before chasing heavier load."
            ]
        }

        let normalizedName = normalizeExerciseName(exerciseName)
        let rawOffset: Int = index + normalizedName.count
        let safeOffset: Int = rawOffset >= 0 ? rawOffset : -rawOffset
        let rotatedIndex: Int = safeOffset % max(1, cues.count)
        return cues[rotatedIndex]
    }

    // EvidenceProfile.md PROG-001 [confidence: low-moderate]
    func progressionCue(for weekNumber: Int, exerciseName: String, muscleTarget: String) -> String {
        let role = proceduralExerciseRole(for: exerciseName, muscleTarget: muscleTarget)
        switch weekNumber {
        case 2:
            return role == .anchor || role == .secondary
                ? "Progression target: add 2.5-5 lb or 1 rep versus last week while holding RPE around 7-8."
                : "Progression target: beat last week by at least one quality rep before increasing load."
        case 3:
            return role == .anchor || role == .secondary
                ? "Progression target: push top sets to RPE 8-9 with no breakdown in rep quality."
                : "Progression target: match or slightly beat Week 2 reps at the same load while keeping 1-2 reps in reserve."
        case 4:
            return "Deload target: reduce hard-set fatigue, keep bar speed crisp, and stop with 3-4 reps in reserve."
        default:
            return "Baseline target: finish sets with 2-3 reps in reserve and log a load you can reliably progress."
        }
    }

    func intentCue(muscleTarget: String, focus: String, exerciseName: String) -> String {
        let cleanedTarget = muscleTarget.trimmedOr(default: "target musculature").lowercased()
        let cleanedFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedFocus.isEmpty || !focusMatchesExercise(cleanedFocus, muscleTarget: cleanedTarget, exerciseName: exerciseName) {
            return "Intent: bias force into \(cleanedTarget) and keep execution consistent across all sets of \(exerciseName)."
        }
        return "Intent: bias the rep toward \(cleanedFocus.lowercased()) while maintaining continuous tension on \(cleanedTarget)."
    }

    func focusMatchesExercise(_ focus: String, muscleTarget: String, exerciseName: String) -> Bool {
        let focusFamilies = movementFamilies(in: focus)
        let exerciseFamilies = movementFamilies(in: "\(muscleTarget) \(exerciseName)")
        if !focusFamilies.isEmpty && !exerciseFamilies.isEmpty {
            return !focusFamilies.intersection(exerciseFamilies).isEmpty
        }

        let loweredFocus = focus.lowercased()
        let loweredExercise = "\(muscleTarget) \(exerciseName)".lowercased()
        return loweredExercise.contains(loweredFocus) || loweredFocus.contains(muscleTarget.lowercased())
    }

    func movementFamilies(in text: String) -> Set<String> {
        let lower = text.lowercased()
        var families: Set<String> = []
        if containsAny(lower, keywords: ["chest", "pec", "bench", "fly"]) { families.insert("chest") }
        if containsAny(lower, keywords: ["delt", "shoulder", "lateral raise"]) { families.insert("shoulders") }
        if containsAny(lower, keywords: ["tricep", "pressdown", "extension", "dip"]) { families.insert("triceps") }
        if containsAny(lower, keywords: ["bicep", "curl", "brachialis"]) { families.insert("biceps") }
        if containsPriorityPhrase(in: lower, keywords: ["lat", "lats", "latissimus dorsi", "row", "back", "pulldown", "pull-up", "pull up"]) {
            families.insert("back")
        }
        if containsAny(lower, keywords: ["quad", "hamstring", "glute", "calf", "squat", "lunge", "deadlift", "leg press"]) { families.insert("legs") }
        if containsAny(lower, keywords: ["core", "abs", "oblique", "crunch"]) { families.insert("core") }
        if containsAny(lower, keywords: ["press"]) && !containsAny(lower, keywords: ["leg press"]) {
            families.insert("chest")
            families.insert("shoulders")
            families.insert("triceps")
        }
        if containsAny(lower, keywords: ["row", "pulldown", "pull-up", "pull up"]) {
            families.insert("back")
            families.insert("biceps")
        }
        if containsAny(lower, keywords: ["squat", "deadlift", "lunge", "leg press", "hip thrust"]) {
            families.insert("legs")
            families.insert("core")
        }
        return families
    }

    func polishedExerciseNotes(
        rawNotes: String,
        exerciseName: String,
        muscleTarget: String,
        weekNumber: Int,
        exerciseIndex: Int
    ) -> String {
        let trimmed = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Trust the AI. Only fall back to procedural content when the note is empty or
        // truly unusable (a few words). Previously we replaced perfectly good personalized
        // notes with templated cues whenever they didn't match keyword heuristics — that
        // was the "generic AI slop" users were seeing.
        if isEmptyOrTooShortInsight(trimmed) {
            return evidenceTunedCoachingLanguage(
                proceduralExerciseNotes(
                weekNumber: weekNumber,
                exerciseName: exerciseName,
                muscleTarget: muscleTarget,
                index: exerciseIndex,
                focus: ""
                )
            )
        }

        let tuned = evidenceTunedCoachingLanguage(trimmed)
        guard !hasConcreteProgressionCue(tuned) else {
            return tuned
        }

        return evidenceTunedCoachingLanguage(
            "\(tuned) \(progressionCue(for: weekNumber, exerciseName: exerciseName, muscleTarget: muscleTarget))"
        )
    }

    func isEmptyOrTooShortInsight(_ notes: String) -> Bool {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let wordCount = trimmed.split { $0.isWhitespace || $0.isNewline }.count
        return wordCount < 5
    }

    func hasConcreteProgressionCue(_ notes: String) -> Bool {
        let normalized = normalizedPriorityText(notes)
        return containsAny(
            normalized,
            keywords: [
                "rpe",
                "rir",
                "reps in reserve",
                "rep in reserve",
                "add reps",
                "add one rep",
                "add 1 rep",
                "add load",
                "increase load",
                "increase weight",
                "beat last week",
                "same load",
                "hold load",
                "top of the rep range",
                "top of range",
                "before increasing load",
                "progression target",
                "deload target",
                "baseline target"
            ]
        )
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
