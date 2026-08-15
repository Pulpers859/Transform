import Foundation
#if canImport(os)
import os
#endif

// MARK: - Workout Generator Service (Week-by-Week)

extension ClaudeService {

    var generationAttempts: Int { 3 }
    /// Clamped to the client's connection ceiling. Above it URLSession queues the surplus while
    /// its resource timer is already running, so an over-wide fan-out degrades into candidates
    /// that fail with a transport timeout they never actually spent on the wire.
    ///
    /// The clamp is announced when it bites. Silently dropping from candidate racing to a
    /// single serial request is exactly the invisible regression the connection-pool fix above
    /// exists to remove; it must not come back through this door.
    var parallelCandidates: Int {
        let desired = 2
        let allowed = min(desired, AnthropicClient.maxConcurrentRequests)
        if allowed < desired {
            print("[WorkoutGeneratorService] Parallel candidates clamped \(desired) -> \(allowed) by AnthropicClient.maxConcurrentRequests.")
        }
        return max(1, allowed)
    }
    var aiSourceLabel: String { "[AI Coach]" }
    var fallbackSourceLabel: String { "[Recovery Engine]" }
    var evidenceProfile: HypertrophyEvidenceProfile { Self.evidenceProfileCache }
    static let evidenceProfileCache = HypertrophyEvidenceProfile(
        version: "hypertrophy_v1_7",
        defaultTrainingDays: 5,
        allowedStyles: ["Push", "Pull", "Legs", "Lower", "Upper", "Arms"],
        // EvidenceProfile.md FREQ-001 / SLOT-001 [confidence: moderate]
        frequencyTargetsByPriority: [
            "High": 2,
            "Medium": 1,
            "Low": 1
        ],
        exerciseSlotTargetsByPriority: [
            "High": 3,
            "Medium": 2,
            "Low": 1
        ],
        // EvidenceProfile.md VOL-001 [confidence: moderate]
        directSetTargetsByPriority: [
            "High": 8...12,
            "Medium": 5...8,
            "Low": 3...5
        ],
        directSetTargetsByVolumeBias: [
            "high": 1.5,
            "moderate": 0,
            "low": -1
        ],
        directWorkBiasAdjustments: [
            "direct emphasis": 1,
            "primary hypertrophy emphasis": 0.5,
            "targeted emphasis": 0.5,
            "mixed emphasis": 0,
            "indirect emphasis": -0.5
        ],
        // EvidenceProfile.md DEL-001 / PROG-001 / TEMPO-001 [confidence: low-moderate / low]
        phasePrescriptionsByWeek: [
            1: EvidencePhasePrescription(anchorSets: 4, secondarySets: 3, accessorySets: 3, coreSets: 3, anchorRepRange: "6-10", secondaryRepRange: "8-12", accessoryRepRange: "10-14", coreRepRange: "10-15"),
            2: EvidencePhasePrescription(anchorSets: 5, secondarySets: 4, accessorySets: 4, coreSets: 3, anchorRepRange: "6-10", secondaryRepRange: "8-12", accessoryRepRange: "10-14", coreRepRange: "10-15"),
            3: EvidencePhasePrescription(anchorSets: 5, secondarySets: 5, accessorySets: 4, coreSets: 3, anchorRepRange: "5-8", secondaryRepRange: "6-10", accessoryRepRange: "10-15", coreRepRange: "10-15"),
            4: EvidencePhasePrescription(anchorSets: 3, secondarySets: 3, accessorySets: 3, coreSets: 2, anchorRepRange: "8-10", secondaryRepRange: "8-12", accessoryRepRange: "10-15", coreRepRange: "10-15")
        ],
        // EvidenceProfile.md REST-001 [confidence: low-moderate]
        restSecondsByRole: [
            "anchor": 150,
            "secondary": 120,
            "accessory": 75,
            "core": 60
        ],
        sessionFatigueCapsByStyle: [
            "push": 19,
            "pull": 19,
            "upper": 19,
            "legs": 22,
            "lower": 22,
            "arms": 16
        ],
        maxSessionPriorityFatigue: 18,
        // EvidenceProfile.md CONC-001 [confidence: low-moderate]
        focusSessionDirectSetShareByPriority: [
            "High": 0.75,
            "Medium": 0.7,
            "Low": 0.65
        ],
        weightedStimulusBonusDirect: 1.5,
        weightedStimulusBonusIndirect: 3.0
    )

    // MARK: - Production Bundle Text

    func productionBundleText(
        weekNumber: Int,
        sourceLabel: String,
        acceptedWithWarnings: Bool,
        usedFallback: Bool,
        displayTitle: String,
        splitType: String,
        analysisSummary: String,
        trainingIntentSummary: String,
        blueprintSummary: String,
        systemPrompt: String,
        userPrompt: String,
        warnings: [String],
        attemptTrace: [String],
        finalJSON: String
    ) -> String {
        let lines: [String] = [
            "Stage: Week \(weekNumber)",
            "Mode: Live AI",
            "Week: \(weekNumber)",
            "Used API: Yes",
            "Source: \(sourceLabel)",
            "Accepted With Warnings: \(acceptedWithWarnings ? "Yes" : "No")",
            "Used Fallback: \(usedFallback ? "Yes" : "No")",
            "Title: \(displayTitle)",
            "Split: \(splitType)",
            "",
            "Validator Issues:",
            warnings.isEmpty ? "None." : warnings.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
            "",
            "Analysis Summary:",
            analysisSummary,
            "",
            "Training Intent:",
            trainingIntentSummary,
            "",
            "Blueprint:",
            blueprintSummary,
            "",
            "System Prompt:",
            systemPrompt,
            "",
            "User Prompt:",
            userPrompt,
            "",
            "Attempt Trace:",
            attemptTrace.isEmpty ? "Clean pass — no correction attempts needed." : attemptTrace.joined(separator: "\n\n"),
            "",
            "Final JSON:",
            finalJSON
        ]
        return lines.joined(separator: "\n")
    }

    // MARK: - Generate Week 1 (Initial)

    func generateWeekOne(from analysisResult: BodyAnalysisResult, performanceHistory: String? = nil, skipHistory: String? = nil, exerciseHistory: ExerciseHistoryContext? = nil, progressionVerdicts: [ExerciseProgressionVerdict] = []) async throws -> WorkoutProgramGenerationResult {
        WorkoutGenerationDiagnostics.markStage("building week 1 analysis context")
        let analysisSummary = analysisContext(from: analysisResult)
        let trainingIntent = trainingIntentPlan(from: analysisResult)
        let blueprint = programBlueprint(for: trainingIntent, weekNumber: 1)
        let intentSummary = trainingIntentContext(from: trainingIntent)
        let blueprintSummary = blueprintContext(from: blueprint)
        let context = generationContext(
            analysisSummary: analysisSummary,
            trainingIntentSummary: intentSummary,
            blueprintSummary: blueprintSummary
        )
        let exerciseMenus = preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: trainingIntent,
            weekNumber: 1,
            previousWeekDays: nil,
            exerciseHistory: exerciseHistory
        )
        let menuContext = exerciseMenuContext(from: exerciseMenus, blueprint: blueprint)

        let config = weekOneConfig
        let toolSchema = programToolSchema()
        let systemPrompt = weekOneSystemPrompt()
        let userPrompt = weekOneUserPrompt(context: context, exerciseMenuContext: menuContext, performanceHistory: performanceHistory, skipHistory: skipHistory)
        let requestContext = workoutRequestContext(
            phase: "week_one",
            weekNumber: 1,
            analysisContext: context,
            previousWeekReference: nil,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        let requestBody = structuredRequestBody(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            toolName: programToolName,
            toolSchema: toolSchema
        )

        var lastIssues: [String] = []
        var attemptTrace: [String] = []

        func buildBundle(response: WorkoutProgramResponse, warnings: [String], usedFallback: Bool) -> String {
            let json = (try? encodeDebugJSONString(response)) ?? ""
            return productionBundleText(
                weekNumber: 1,
                sourceLabel: usedFallback ? fallbackSourceLabel : aiSourceLabel,
                acceptedWithWarnings: !warnings.isEmpty,
                usedFallback: usedFallback,
                displayTitle: response.programName,
                splitType: response.splitType,
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                warnings: warnings,
                attemptTrace: attemptTrace,
                finalJSON: json
            )
        }

        func labelAndPolish(_ response: WorkoutProgramResponse) -> WorkoutProgramResponse {
            polishGenericProgramNotes(
                labeledProgramResponse(response, sourceLabel: aiSourceLabel),
                weekNumber: 1,
                trainingIntent: trainingIntent,
                blueprint: blueprint
            )
        }

        // Phase 1: Fire parallel candidates and pick the best
        try Task.checkCancellation()
        WorkoutGenerationDiagnostics.markStage("requesting week 1 parallel candidates from AI")

        let candidateResults = await withTaskGroup(of: (Int, Result<WorkoutProgramResponse, Error>).self) { group in
            for i in 1...parallelCandidates {
                group.addTask { [requestBody, config, requestContext] in
                    do {
                        let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                            body: requestBody,
                            toolName: self.programToolName,
                            timeout: config.timeout,
                            context: requestContext
                        )
                        let decoded = try self.decodeJSONPayload(WorkoutProgramResponse.self, from: jsonString)
                        let cleaned = try await self.sanitizeProgramResponse(decoded)
                        return (i, .success(cleaned))
                    } catch {
                        return (i, .failure(error))
                    }
                }
            }
            var results: [(Int, Result<WorkoutProgramResponse, Error>)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }

        try Task.checkCancellation()
        WorkoutGenerationDiagnostics.markStage("scoring week 1 parallel candidates")

        var scoredCandidates: [(response: WorkoutProgramResponse, issues: [String], score: Int)] = []
        var candidateErrors: [Error] = []

        for (i, result) in candidateResults {
            switch result {
            case .success(let cleaned):
                let prescribed = applyingPreselectedSetPrescription(
                    to: cleaned,
                    menus: exerciseMenus
                )
                let issues = validateProgramResponse(prescribed, blueprint: blueprint, expectedExerciseMenus: exerciseMenus, progressionVerdicts: progressionVerdicts)
                let score = issues.isEmpty ? 0 : scoreValidationIssues(issues, menuLocked: true)
                scoredCandidates.append((response: prescribed, issues: issues, score: score))
                if issues.isEmpty {
                    attemptTrace.append("Candidate \(i): Accepted — no issues")
                } else {
                    attemptTrace.append("Candidate \(i): Score \(score)\nIssues:\n\(issues.map { "- \($0)" }.joined(separator: "\n"))")
                }
            case .failure(let error):
                candidateErrors.append(error)
                attemptTrace.append("Candidate \(i): API error — \(error.localizedDescription)")
            }
        }

        // Abort (so the user can retry instead of silently degrading) only when NO
        // candidate produced a usable payload. A transient failure on one parallel
        // candidate must not throw away its successful sibling.
        if scoredCandidates.isEmpty,
           let abortError = candidateErrors.first(where: { shouldAbortFallback(for: $0) }) {
            throw terminalGenerationError(
                while: "generating your initial workout program",
                underlying: abortError
            )
        }

        scoredCandidates.sort { $0.score < $1.score }

        // Accept the best candidate if it's clean or has only acceptable warnings
        if let best = scoredCandidates.first {
            if best.issues.isEmpty {
                let labeled = labelAndPolish(best.response)
                return WorkoutProgramGenerationResult(
                    response: labeled,
                    validatorWarnings: [],
                    bundleText: buildBundle(response: labeled, warnings: [], usedFallback: false)
                )
            }

            if best.issues.allSatisfy({ validationDisposition(for: $0, menuLocked: true) == .acceptableWarning }) {
                print("[WorkoutGeneratorService] Week 1 best candidate accepted with acceptable warnings: \(best.issues.joined(separator: " | "))")
                attemptTrace.append("Best candidate accepted with acceptable warnings")
                let labeled = labelAndPolish(best.response)
                return WorkoutProgramGenerationResult(
                    response: labeled,
                    validatorWarnings: best.issues,
                    bundleText: buildBundle(response: labeled, warnings: best.issues, usedFallback: false)
                )
            }

            lastIssues = best.issues
            let hasPlannerOrStructuralFailure = best.issues.contains {
                validationDisposition(for: $0, menuLocked: true) == .hardFailure
            }
            if hasPlannerOrStructuralFailure {
                attemptTrace.append("Correction pass skipped: locked planning or structural invariant failed")
            } else {
                // Phase 2: One targeted correction pass on AI-owned fields only.
                try Task.checkCancellation()
                WorkoutGenerationDiagnostics.markStage("correction pass for week 1 best candidate")
                attemptTrace.append("Correction pass targeting: \(best.issues.map { "- \($0)" }.joined(separator: "\n"))")

                let correctionBody = correctionRequestBody(
                    config: config,
                    systemPrompt: systemPrompt,
                    toolName: programToolName,
                    toolSchema: toolSchema,
                    issues: best.issues,
                    context: context,
                    originalUserPrompt: userPrompt,
                    previousPayloadJSON: try? encodeDebugJSONString(best.response)
                )

                do {
                    let correctedJSON = try await AnthropicClient.shared.sendStructuredRequest(
                        body: correctionBody,
                        toolName: programToolName,
                        timeout: config.timeout,
                        context: requestContext
                    )
                    let correctedDecoded = try decodeJSONPayload(WorkoutProgramResponse.self, from: correctedJSON)
                    let correctedCleaned = applyingPreselectedSetPrescription(
                        to: try await sanitizeProgramResponse(correctedDecoded),
                        menus: exerciseMenus
                    )
                    let correctedIssues = validateProgramResponse(correctedCleaned, blueprint: blueprint, expectedExerciseMenus: exerciseMenus, progressionVerdicts: progressionVerdicts)

                    if correctedIssues.isEmpty {
                        attemptTrace.append("Correction pass: Accepted — no issues")
                        let labeled = labelAndPolish(correctedCleaned)
                        return WorkoutProgramGenerationResult(
                            response: labeled,
                            validatorWarnings: [],
                            bundleText: buildBundle(response: labeled, warnings: [], usedFallback: false)
                        )
                    }

                    // Accept correction if permissible on final attempt
                    if shouldAcceptAIOutput(despite: correctedIssues, menuLocked: true) {
                        attemptTrace.append("Correction pass: Accepted with warnings (score \(scoreValidationIssues(correctedIssues, menuLocked: true)))")
                        let labeled = labelAndPolish(correctedCleaned)
                        return WorkoutProgramGenerationResult(
                            response: labeled,
                            validatorWarnings: correctedIssues,
                            bundleText: buildBundle(response: labeled, warnings: correctedIssues, usedFallback: false)
                        )
                    }

                    lastIssues = correctedIssues
                    attemptTrace.append("Correction pass: Rejected (score \(scoreValidationIssues(correctedIssues, menuLocked: true)))\nIssues:\n\(correctedIssues.map { "- \($0)" }.joined(separator: "\n"))")
                } catch {
                    attemptTrace.append("Correction pass: API error — \(error.localizedDescription)")
                    if shouldAbortFallback(for: error) {
                        throw terminalGenerationError(while: "generating your initial workout program", underlying: error)
                    }
                }
            }
        } else if let firstError = candidateErrors.first {
            lastIssues = ["All parallel candidates failed: \(firstError.localizedDescription)"]
            attemptTrace.append("All candidates failed — falling back to procedural generator")
        }

        if !lastIssues.isEmpty {
            print("[WorkoutGeneratorService] Week 1 fallback activated after issues: \(lastIssues.joined(separator: " | "))")
        }

        WorkoutGenerationDiagnostics.markStage("building procedural week 1 fallback")
        let fallbackResponse = try validatedProceduralWeekOneProgram(
            from: analysisResult,
            trainingIntent: trainingIntent,
            blueprint: blueprint,
            exerciseMenus: exerciseMenus,
            diagnostic: lastIssues.joined(separator: " | ")
        )
        let fallbackIssues = validateProgramResponse(fallbackResponse, blueprint: blueprint, expectedExerciseMenus: exerciseMenus, progressionVerdicts: progressionVerdicts)
        return WorkoutProgramGenerationResult(
            response: fallbackResponse,
            validatorWarnings: fallbackIssues,
            bundleText: buildBundle(response: fallbackResponse, warnings: fallbackIssues, usedFallback: true)
        )
    }

    static func availableMemoryMB() -> Int {
        // os_proc_available_memory() is API_UNAVAILABLE(macos) — it exists only on
        // iOS/tvOS/watchOS. Guard on platform, not canImport(os) (os imports fine on
        // macOS), so the generator core builds for the headless test harness. Device
        // behavior is unchanged (os(iOS) is true there).
        #if os(iOS) || os(tvOS) || os(watchOS)
        return Int(os_proc_available_memory() / (1024 * 1024))
        #else
        return -1
        #endif
    }

    static func payloadProfile(for days: [WorkoutDayResponse]) -> String {
        let exerciseCount = days.reduce(0) { $0 + $1.exercises.count }
        let noteChars = days.reduce(0) { partial, day in
            partial + day.notes.count + day.exercises.reduce(0) { $0 + $1.notes.count }
        }
        return "\(days.count) days, \(exerciseCount) exercises, \(noteChars) note chars, \(Self.availableMemoryMB())MB free"
    }

    // MARK: - Generate Next Week (2, 3, or 4)

    func generateNextWeek(
        weekNumber: Int,
        previousWeekJSON: String,
        analysisJSON: String,
        splitType: String,
        programName: String,
        performanceHistory: String? = nil,
        sessionFeedbackSummary: String? = nil,
        skipHistory: String? = nil,
        exerciseHistory: ExerciseHistoryContext? = nil,
        progressionVerdicts: [ExerciseProgressionVerdict] = []
    ) async throws -> WorkoutWeekGenerationResult {
        let dayStart = ((weekNumber - 1) * 7) + 1
        let dayEnd = weekNumber * 7

        let previousWeekDecode = decodePreviousWeekContext(from: previousWeekJSON)
        let previousWeekDays = previousWeekDecode.days
        let hasValidPreviousWeek = previousWeekDays.count == 7
        let previousWeekSummary = previousWeekDecode.weekSummary
        let previousWeekReference = hasValidPreviousWeek
            ? compactPreviousWeekReference(from: previousWeekDays, weekSummary: previousWeekSummary)
            : previousWeekDecode.warning ?? "No valid previous week context available."

        let cleanedAnalysisJSON = cleanedJSONText(analysisJSON)
        let analysisDecode = decodedAnalysisResultWithWarning(from: cleanedAnalysisJSON)
        let decodedAnalysis = analysisDecode.analysis
        let baseAnalysisSummary = decodedAnalysis.map(analysisContext(from:)) ?? analysisContext(from: analysisJSON)
        let analysisSummary = analysisDecode.warning.map {
            "\(baseAnalysisSummary)\nDecoding note: \($0)"
        } ?? baseAnalysisSummary
        let trainingIntent = decodedAnalysis.map(trainingIntentPlan(from:))
            ?? fallbackTrainingIntentPlan(from: priorityMuscles(from: analysisJSON))
        let blueprint = programBlueprint(for: trainingIntent, weekNumber: weekNumber)
        let intentSummary = trainingIntentContext(from: trainingIntent)
        let blueprintSummary = blueprintContext(from: blueprint)
        let context = generationContext(
            analysisSummary: analysisSummary,
            trainingIntentSummary: intentSummary,
            blueprintSummary: blueprintSummary
        )
        let exerciseMenus = preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: trainingIntent,
            weekNumber: weekNumber,
            previousWeekDays: previousWeekDays.isEmpty ? nil : previousWeekDays,
            exerciseHistory: exerciseHistory
        )
        let menuContext = exerciseMenuContext(from: exerciseMenus, blueprint: blueprint, dayStart: dayStart)

        let config = nextWeekConfig
        let toolSchema = weekToolSchema(dayStart: dayStart, dayEnd: dayEnd)
        let systemPrompt = nextWeekSystemPrompt(weekNumber: weekNumber, splitType: splitType, programName: programName)
        let userPrompt = nextWeekUserPrompt(
            weekNumber: weekNumber,
            dayStart: dayStart,
            dayEnd: dayEnd,
            previousWeekReference: previousWeekReference,
            analysisContext: context,
            exerciseMenuContext: menuContext,
            performanceHistory: performanceHistory,
            sessionFeedbackSummary: sessionFeedbackSummary,
            skipHistory: skipHistory
        )
        let requestContext = workoutRequestContext(
            phase: "next_week",
            weekNumber: weekNumber,
            analysisContext: context,
            previousWeekReference: previousWeekReference,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
        let requestBody = structuredRequestBody(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            toolName: weekToolName,
            toolSchema: toolSchema
        )

        var lastIssues: [String] = []
        var attemptTrace: [String] = []

        func buildWeekBundle(weekSummary: String, days: [WorkoutDayResponse], warnings: [String], usedFallback: Bool) -> String {
            let fakeProgram = WorkoutProgramResponse(
                programName: programName,
                programSummary: weekSummary,
                splitType: splitType,
                daysPerWeek: days.filter { !$0.isRestDay }.count,
                days: days
            )
            let json = (try? encodeDebugJSONString(fakeProgram)) ?? ""
            return productionBundleText(
                weekNumber: weekNumber,
                sourceLabel: usedFallback ? fallbackSourceLabel : aiSourceLabel,
                acceptedWithWarnings: !warnings.isEmpty,
                usedFallback: usedFallback,
                displayTitle: programName,
                splitType: splitType,
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                warnings: warnings,
                attemptTrace: attemptTrace,
                finalJSON: json
            )
        }

        func labelAndPolishWeek(_ response: WorkoutWeekResponse) -> WorkoutWeekResponse {
            polishGenericWeekNotes(
                labeledWeekResponse(response, sourceLabel: aiSourceLabel),
                weekNumber: weekNumber,
                trainingIntent: trainingIntent,
                blueprint: blueprint
            )
        }

        // Phase 1: Fire parallel candidates and pick the best
        try Task.checkCancellation()
        WorkoutGenerationDiagnostics.markStage("requesting week \(weekNumber) parallel candidates from AI")

        let candidateResults = await withTaskGroup(of: (Int, Result<WorkoutWeekResponse, Error>).self) { group in
            for i in 1...parallelCandidates {
                group.addTask { [requestBody, config, requestContext] in
                    do {
                        let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                            body: requestBody,
                            toolName: self.weekToolName,
                            timeout: config.timeout,
                            context: requestContext
                        )
                        let decoded = try self.decodeJSONPayload(WorkoutWeekResponse.self, from: jsonString)
                        let cleaned = try await self.sanitizeWeekResponse(decoded)
                        return (i, .success(cleaned))
                    } catch {
                        return (i, .failure(error))
                    }
                }
            }
            var results: [(Int, Result<WorkoutWeekResponse, Error>)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }

        try Task.checkCancellation()
        WorkoutGenerationDiagnostics.markStage("scoring week \(weekNumber) parallel candidates")

        var scoredCandidates: [(response: WorkoutWeekResponse, issues: [String], score: Int)] = []
        var candidateErrors: [Error] = []

        for (i, result) in candidateResults {
            switch result {
            case .success(let cleaned):
                let prescribed = applyingPreselectedSetPrescription(
                    to: cleaned,
                    menus: exerciseMenus,
                    dayStart: dayStart
                )
                let issues = validateWeekResponse(
                    prescribed,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                    blueprint: blueprint,
                    expectedExerciseMenus: exerciseMenus,
                    progressionVerdicts: progressionVerdicts
                )
                let score = issues.isEmpty ? 0 : scoreValidationIssues(issues, menuLocked: true)
                scoredCandidates.append((response: prescribed, issues: issues, score: score))
                if issues.isEmpty {
                    attemptTrace.append("Candidate \(i): Accepted — no issues")
                } else {
                    attemptTrace.append("Candidate \(i): Score \(score)\nIssues:\n\(issues.map { "- \($0)" }.joined(separator: "\n"))")
                }
            case .failure(let error):
                candidateErrors.append(error)
                attemptTrace.append("Candidate \(i): API error — \(error.localizedDescription)")
            }
        }

        // Abort (so the user can retry instead of silently degrading) only when NO
        // candidate produced a usable payload. A transient failure on one parallel
        // candidate must not throw away its successful sibling.
        if scoredCandidates.isEmpty,
           let abortError = candidateErrors.first(where: { shouldAbortFallback(for: $0) }) {
            throw terminalGenerationError(
                while: "generating week \(weekNumber)",
                underlying: abortError
            )
        }

        scoredCandidates.sort { $0.score < $1.score }

        // Accept the best candidate if it's clean or has only acceptable warnings
        if let best = scoredCandidates.first {
            if best.issues.isEmpty {
                let labeled = labelAndPolishWeek(best.response)
                return WorkoutWeekGenerationResult(
                    response: labeled,
                    validatorWarnings: [],
                    bundleText: buildWeekBundle(weekSummary: labeled.weekSummary, days: labeled.days, warnings: [], usedFallback: false)
                )
            }

            if best.issues.allSatisfy({ validationDisposition(for: $0, menuLocked: true) == .acceptableWarning }) {
                print("[WorkoutGeneratorService] Week \(weekNumber) best candidate accepted with acceptable warnings: \(best.issues.joined(separator: " | "))")
                attemptTrace.append("Best candidate accepted with acceptable warnings")
                let labeled = labelAndPolishWeek(best.response)
                return WorkoutWeekGenerationResult(
                    response: labeled,
                    validatorWarnings: best.issues,
                    bundleText: buildWeekBundle(weekSummary: labeled.weekSummary, days: labeled.days, warnings: best.issues, usedFallback: false)
                )
            }

            lastIssues = best.issues
            let hasPlannerOrStructuralFailure = best.issues.contains {
                validationDisposition(for: $0, menuLocked: true) == .hardFailure
            }
            if hasPlannerOrStructuralFailure {
                attemptTrace.append("Correction pass skipped: locked planning or structural invariant failed")
            } else {
                // Phase 2: One targeted correction pass on AI-owned fields only.
                try Task.checkCancellation()
                WorkoutGenerationDiagnostics.markStage("correction pass for week \(weekNumber) best candidate")
                attemptTrace.append("Correction pass targeting: \(best.issues.map { "- \($0)" }.joined(separator: "\n"))")

                let correctionBody = correctionRequestBody(
                    config: config,
                    systemPrompt: systemPrompt,
                    toolName: weekToolName,
                    toolSchema: toolSchema,
                    issues: best.issues,
                    context: context,
                    originalUserPrompt: userPrompt,
                    previousPayloadJSON: try? encodeDebugJSONString(best.response)
                )

                do {
                    let correctedJSON = try await AnthropicClient.shared.sendStructuredRequest(
                        body: correctionBody,
                        toolName: weekToolName,
                        timeout: config.timeout,
                        context: requestContext
                    )
                    let correctedDecoded = try decodeJSONPayload(WorkoutWeekResponse.self, from: correctedJSON)
                    let correctedCleaned = applyingPreselectedSetPrescription(
                        to: try await sanitizeWeekResponse(correctedDecoded),
                        menus: exerciseMenus,
                        dayStart: dayStart
                    )
                    let correctedIssues = validateWeekResponse(
                        correctedCleaned,
                        dayStart: dayStart,
                        dayEnd: dayEnd,
                        previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                        blueprint: blueprint,
                        expectedExerciseMenus: exerciseMenus,
                        progressionVerdicts: progressionVerdicts
                    )

                    if correctedIssues.isEmpty {
                        attemptTrace.append("Correction pass: Accepted — no issues")
                        let labeled = labelAndPolishWeek(correctedCleaned)
                        return WorkoutWeekGenerationResult(
                            response: labeled,
                            validatorWarnings: [],
                            bundleText: buildWeekBundle(weekSummary: labeled.weekSummary, days: labeled.days, warnings: [], usedFallback: false)
                        )
                    }

                    // Accept correction result if it's better than the parallel best
                    let correctedScore = scoreValidationIssues(correctedIssues, menuLocked: true)
                    if shouldAcceptAIOutput(despite: correctedIssues, menuLocked: true) {
                        attemptTrace.append("Correction pass: Accepted with warnings (score \(correctedScore))")
                        let labeled = labelAndPolishWeek(correctedCleaned)
                        return WorkoutWeekGenerationResult(
                            response: labeled,
                            validatorWarnings: correctedIssues,
                            bundleText: buildWeekBundle(weekSummary: labeled.weekSummary, days: labeled.days, warnings: correctedIssues, usedFallback: false)
                        )
                    }

                    lastIssues = correctedIssues
                    attemptTrace.append("Correction pass: Rejected (score \(correctedScore))\nIssues:\n\(correctedIssues.map { "- \($0)" }.joined(separator: "\n"))")
                } catch {
                    attemptTrace.append("Correction pass: API error — \(error.localizedDescription)")
                    if shouldAbortFallback(for: error) {
                        throw terminalGenerationError(while: "generating week \(weekNumber)", underlying: error)
                    }
                }
            }
        } else if let firstError = candidateErrors.first {
            lastIssues = ["All parallel candidates failed: \(firstError.localizedDescription)"]
            attemptTrace.append("All candidates failed — falling back to procedural generator")
        }

        if !lastIssues.isEmpty {
            print("[WorkoutGeneratorService] Week \(weekNumber) fallback activated after issues: \(lastIssues.joined(separator: " | "))")
        }

        let fallbackResponse = try validatedProceduralWeek(
            weekNumber: weekNumber,
            dayStart: dayStart,
            dayEnd: dayEnd,
            splitType: splitType,
            programName: programName,
            trainingIntent: trainingIntent,
            blueprint: blueprint,
            previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
            exerciseMenus: exerciseMenus,
            diagnostic: lastIssues.joined(separator: " | ")
        )
        let fallbackIssues = validateWeekResponse(
            fallbackResponse,
            dayStart: dayStart,
            dayEnd: dayEnd,
            previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
            blueprint: blueprint,
            expectedExerciseMenus: exerciseMenus,
            progressionVerdicts: progressionVerdicts
        )
        return WorkoutWeekGenerationResult(
            response: fallbackResponse,
            validatorWarnings: fallbackIssues,
            bundleText: buildWeekBundle(weekSummary: fallbackResponse.weekSummary, days: fallbackResponse.days, warnings: fallbackIssues, usedFallback: true)
        )
    }

    // MARK: - Debug Generator Lab

    func debugGenerateWeekOne(
        from analysisResult: BodyAnalysisResult,
        mode: WorkoutGeneratorDebugMode,
        replayJSON: String? = nil
    ) async throws -> WorkoutGeneratorDebugReport {
        try Task.checkCancellation()
        let analysisSummary = analysisContext(from: analysisResult)
        let trainingIntent = trainingIntentPlan(from: analysisResult)
        let blueprint = programBlueprint(for: trainingIntent, weekNumber: 1)
        let intentSummary = trainingIntentContext(from: trainingIntent)
        let blueprintSummary = blueprintContext(from: blueprint)
        let context = generationContext(
            analysisSummary: analysisSummary,
            trainingIntentSummary: intentSummary,
            blueprintSummary: blueprintSummary
        )
        let exerciseMenus = preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: trainingIntent,
            weekNumber: 1,
            previousWeekDays: nil
        )
        let menuContext = exerciseMenuContext(from: exerciseMenus, blueprint: blueprint)
        let config = weekOneConfig
        let toolSchema = programToolSchema()
        let systemPrompt = weekOneSystemPrompt()
        let userPrompt = weekOneUserPrompt(context: context, exerciseMenuContext: menuContext)
        let requestContext = workoutRequestContext(
            phase: "week_one_debug",
            weekNumber: 1,
            analysisContext: context,
            previousWeekReference: nil,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        switch mode {
        case .lastGeneration:
            throw ClaudeError.parseError("Last Generation mode is handled by the Lab view and does not use the generator service.")

        case .procedural:
            // Production fallback consumes the locked menu (INC-3 / INC-8). The Lab must build
            // and score the SAME week, or the owner audits a procedural week the app can never
            // actually ship — different exercises, different set counts, and a validator run
            // that skips menu adherence entirely.
            let response = buildProceduralWeekOneProgram(
                from: analysisResult,
                trainingIntent: trainingIntent,
                blueprint: blueprint,
                exerciseMenus: exerciseMenus
            )
            let finalIssues = validateProgramResponse(
                response,
                blueprint: blueprint,
                expectedExerciseMenus: exerciseMenus
            )
            return try debugProgramReport(
                stage: .weekOne,
                mode: mode,
                weekNumber: 1,
                sourceLabel: fallbackSourceLabel,
                acceptedWithWarnings: false,
                usedFallback: true,
                displayTitle: response.programName,
                splitType: response.splitType,
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary,
                previousWeekReference: nil,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                warnings: [],
                finalIssues: finalIssues,
                attempts: [],
                replayInputJSON: nil,
                response: response
            )

        case .validatorReplay:
            let candidate = replayJSON?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !candidate.isEmpty else {
                throw ClaudeError.parseError("Paste a Week 1 program JSON payload to run validator replay.")
            }

            let decoded = try decodeJSONPayload(WorkoutProgramResponse.self, from: candidate)
            let cleaned = applyingPreselectedSetPrescription(
                to: try await sanitizeProgramResponse(decoded),
                menus: exerciseMenus
            )
            let issues = validateProgramResponse(cleaned, blueprint: blueprint, expectedExerciseMenus: exerciseMenus)
            let attempt = WorkoutGeneratorDebugAttempt(
                attemptNumber: 1,
                rawPayload: candidate,
                sanitizedPayload: try? encodeDebugJSONString(cleaned),
                validatorIssues: issues,
                outcome: issues.isEmpty ? "Replay passed validator" : "Replay flagged validator issues"
            )

            return try debugProgramReport(
                stage: .weekOne,
                mode: mode,
                weekNumber: 1,
                sourceLabel: sourceLabel(from: cleaned.programSummary, fallback: "[Replay]"),
                acceptedWithWarnings: false,
                usedFallback: false,
                displayTitle: cleaned.programName,
                splitType: cleaned.splitType,
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary,
                previousWeekReference: nil,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                warnings: [],
                finalIssues: issues,
                attempts: [attempt],
                replayInputJSON: candidate,
                response: cleaned
            )

        case .liveAI:
            var requestBody = structuredRequestBody(
                config: config,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                toolName: programToolName,
                toolSchema: toolSchema
            )

            var attempts: [WorkoutGeneratorDebugAttempt] = []
            var lastIssues: [String] = []

            for attempt in 1...generationAttempts {
                try Task.checkCancellation()
                do {
                    let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                        body: requestBody,
                        toolName: programToolName,
                        timeout: config.timeout,
                        context: requestContext
                    )

                    do {
                        try Task.checkCancellation()
                        let decoded = try decodeJSONPayload(WorkoutProgramResponse.self, from: jsonString)
                        let cleaned = applyingPreselectedSetPrescription(
                            to: try await sanitizeProgramResponse(decoded),
                            menus: exerciseMenus
                        )
                        let issues = validateProgramResponse(cleaned, blueprint: blueprint, expectedExerciseMenus: exerciseMenus)
                        let sanitizedPayload = try? encodeDebugJSONString(cleaned)

                        if issues.isEmpty {
                            attempts.append(
                                WorkoutGeneratorDebugAttempt(
                                    attemptNumber: attempt,
                                    rawPayload: jsonString,
                                    sanitizedPayload: sanitizedPayload,
                                    validatorIssues: [],
                                    outcome: "Accepted"
                                )
                            )
                            let labeled = labeledProgramResponse(cleaned, sourceLabel: aiSourceLabel)
                            return try debugProgramReport(
                                stage: .weekOne,
                                mode: mode,
                                weekNumber: 1,
                                sourceLabel: aiSourceLabel,
                                acceptedWithWarnings: false,
                                usedFallback: false,
                                displayTitle: labeled.programName,
                                splitType: labeled.splitType,
                                analysisSummary: analysisSummary,
                                trainingIntentSummary: intentSummary,
                                blueprintSummary: blueprintSummary,
                                previousWeekReference: nil,
                                systemPrompt: systemPrompt,
                                userPrompt: userPrompt,
                                warnings: [],
                                finalIssues: [],
                                attempts: attempts,
                                replayInputJSON: nil,
                                response: labeled
                            )
                        }

                        if shouldAcceptAIOutput(despite: issues, menuLocked: true) {
                            attempts.append(
                                WorkoutGeneratorDebugAttempt(
                                    attemptNumber: attempt,
                                    rawPayload: jsonString,
                                    sanitizedPayload: sanitizedPayload,
                                    validatorIssues: issues,
                                    outcome: "Accepted with heuristic validator warnings"
                                )
                            )
                            let labeled = labeledProgramResponse(cleaned, sourceLabel: aiSourceLabel)
                            return try debugProgramReport(
                                stage: .weekOne,
                                mode: mode,
                                weekNumber: 1,
                                sourceLabel: aiSourceLabel,
                                acceptedWithWarnings: true,
                                usedFallback: false,
                                displayTitle: labeled.programName,
                                splitType: labeled.splitType,
                                analysisSummary: analysisSummary,
                                trainingIntentSummary: intentSummary,
                                blueprintSummary: blueprintSummary,
                                previousWeekReference: nil,
                                systemPrompt: systemPrompt,
                                userPrompt: userPrompt,
                                warnings: [],
                                finalIssues: issues,
                                attempts: attempts,
                                replayInputJSON: nil,
                                response: labeled
                            )
                        }

                        attempts.append(
                            WorkoutGeneratorDebugAttempt(
                                attemptNumber: attempt,
                                rawPayload: jsonString,
                                sanitizedPayload: sanitizedPayload,
                                validatorIssues: issues,
                                outcome: "Rejected by validator"
                            )
                        )
                        lastIssues = issues

                        if attempt < generationAttempts {
                            requestBody = correctionRequestBody(
                                config: config,
                                systemPrompt: systemPrompt,
                                toolName: programToolName,
                                toolSchema: toolSchema,
                                issues: issues,
                                context: context,
                                originalUserPrompt: userPrompt,
                                previousPayloadJSON: sanitizedPayload ?? jsonString
                            )
                        }
                    } catch {
                        let issue = "Payload decode failed: \(error.localizedDescription)"
                        attempts.append(
                            WorkoutGeneratorDebugAttempt(
                                attemptNumber: attempt,
                                rawPayload: jsonString,
                                sanitizedPayload: nil,
                                validatorIssues: [issue],
                                outcome: "Decode failure"
                            )
                        )
                        lastIssues = [issue]

                        if attempt < generationAttempts {
                            requestBody = correctionRequestBody(
                                config: config,
                                systemPrompt: systemPrompt,
                                toolName: programToolName,
                                toolSchema: toolSchema,
                                issues: [issue],
                                context: context,
                                originalUserPrompt: userPrompt
                            )
                        }
                    }
                } catch {
                    let issue = "API error (attempt \(attempt)): \(error.localizedDescription)"
                    attempts.append(
                        WorkoutGeneratorDebugAttempt(
                            attemptNumber: attempt,
                            rawPayload: nil,
                            sanitizedPayload: nil,
                            validatorIssues: [issue],
                            outcome: "Request failure"
                        )
                    )
                    lastIssues = [issue]

                    if shouldAbortFallback(for: error) {
                        return debugProgramFailureReport(
                            stage: .weekOne,
                            mode: mode,
                            weekNumber: 1,
                            displayTitle: "Week 1 Live AI Debug Failure",
                            splitType: trainingIntent.splitRecommendation,
                            analysisSummary: analysisSummary,
                            trainingIntentSummary: intentSummary,
                            blueprintSummary: blueprintSummary,
                            previousWeekReference: nil,
                            systemPrompt: systemPrompt,
                            userPrompt: userPrompt,
                            warnings: [
                                "Recovery Engine was not applied because the request failed before the lab had a trustworthy AI payload to validate."
                            ],
                            attempts: attempts,
                            terminalError: terminalGenerationError(
                                while: "running live Week 1 generator debug",
                                underlying: error
                            ).localizedDescription
                        )
                    }

                    if attempt < generationAttempts {
                        requestBody = correctionRequestBody(
                            config: config,
                            systemPrompt: systemPrompt,
                            toolName: programToolName,
                            toolSchema: toolSchema,
                            issues: [correctionIssue(for: error)],
                            context: context,
                            originalUserPrompt: userPrompt
                        )
                    }
                }
            }

            try Task.checkCancellation()
            let fallback = buildProceduralWeekOneProgram(
                from: analysisResult,
                trainingIntent: trainingIntent,
                blueprint: blueprint,
                exerciseMenus: exerciseMenus,
                diagnostic: lastIssues.joined(separator: " | ")
            )
            let fallbackIssues = validateProgramResponse(
                fallback,
                blueprint: blueprint,
                expectedExerciseMenus: exerciseMenus
            )
            let warning = lastIssues.isEmpty
                ? "Live AI exited into procedural fallback without a specific issue trace."
                : "Live AI fell back after: \(lastIssues.joined(separator: " | "))"

            return try debugProgramReport(
                stage: .weekOne,
                mode: mode,
                weekNumber: 1,
                sourceLabel: fallbackSourceLabel,
                acceptedWithWarnings: false,
                usedFallback: true,
                displayTitle: fallback.programName,
                splitType: fallback.splitType,
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary,
                previousWeekReference: nil,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                warnings: [warning],
                finalIssues: fallbackIssues,
                attempts: attempts,
                replayInputJSON: nil,
                response: fallback
            )
        }
    }

    func debugGenerateNextWeek(
        weekNumber: Int,
        previousWeekJSON: String,
        analysisJSON: String,
        splitType: String,
        programName: String,
        mode: WorkoutGeneratorDebugMode,
        replayJSON: String? = nil
    ) async throws -> WorkoutGeneratorDebugReport {
        try Task.checkCancellation()
        let dayStart = ((weekNumber - 1) * 7) + 1
        let dayEnd = weekNumber * 7

        let previousWeekDecode = decodePreviousWeekContext(from: previousWeekJSON)
        let previousWeekDays = previousWeekDecode.days
        let hasValidPreviousWeek = previousWeekDays.count == 7
        let previousWeekSummary = previousWeekDecode.weekSummary
        let previousWeekReference = hasValidPreviousWeek
            ? compactPreviousWeekReference(from: previousWeekDays, weekSummary: previousWeekSummary)
            : previousWeekDecode.warning ?? "No valid previous week context available."

        let cleanedAnalysisJSON = cleanedJSONText(analysisJSON)
        let analysisDecode = decodedAnalysisResultWithWarning(from: cleanedAnalysisJSON)
        let decodedAnalysis = analysisDecode.analysis
        let baseAnalysisSummary = decodedAnalysis.map(analysisContext(from:)) ?? analysisContext(from: analysisJSON)
        let analysisSummary = analysisDecode.warning.map {
            "\(baseAnalysisSummary)\nDecoding note: \($0)"
        } ?? baseAnalysisSummary
        let trainingIntent = decodedAnalysis.map(trainingIntentPlan(from:))
            ?? fallbackTrainingIntentPlan(from: priorityMuscles(from: analysisJSON))
        let blueprint = programBlueprint(for: trainingIntent, weekNumber: weekNumber)
        let intentSummary = trainingIntentContext(from: trainingIntent)
        let blueprintSummary = blueprintContext(from: blueprint)
        let context = generationContext(
            analysisSummary: analysisSummary,
            trainingIntentSummary: intentSummary,
            blueprintSummary: blueprintSummary
        )
        let exerciseMenus = preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: trainingIntent,
            weekNumber: weekNumber,
            previousWeekDays: previousWeekDays.isEmpty ? nil : previousWeekDays
        )
        let menuContext = exerciseMenuContext(from: exerciseMenus, blueprint: blueprint, dayStart: dayStart)
        let config = nextWeekConfig
        let toolSchema = weekToolSchema(dayStart: dayStart, dayEnd: dayEnd)
        let systemPrompt = nextWeekSystemPrompt(weekNumber: weekNumber, splitType: splitType, programName: programName)
        let userPrompt = nextWeekUserPrompt(
            weekNumber: weekNumber,
            dayStart: dayStart,
            dayEnd: dayEnd,
            previousWeekReference: previousWeekReference,
            analysisContext: context,
            exerciseMenuContext: menuContext
        )
        let requestContext = workoutRequestContext(
            phase: "next_week_debug",
            weekNumber: weekNumber,
            analysisContext: context,
            previousWeekReference: previousWeekReference,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        var warnings: [String] = []
        if let previousWarning = previousWeekDecode.warning {
            warnings.append(previousWarning)
        }
        if let analysisWarning = analysisDecode.warning {
            warnings.append(analysisWarning)
        }

        switch mode {
        case .lastGeneration:
            throw ClaudeError.parseError("Last Generation mode is handled by the Lab view and does not use the generator service.")

        case .procedural:
            // Same menu-locked parity as Week 1: audit the week production would really build.
            let response = buildProceduralWeek(
                weekNumber: weekNumber,
                dayStart: dayStart,
                dayEnd: dayEnd,
                splitType: splitType,
                programName: programName,
                trainingIntent: trainingIntent,
                blueprint: blueprint,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                exerciseMenus: exerciseMenus
            )
            let finalIssues = validateWeekResponse(
                response,
                dayStart: dayStart,
                dayEnd: dayEnd,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                blueprint: blueprint,
                expectedExerciseMenus: exerciseMenus
            )

            return try debugWeekReport(
                mode: mode,
                weekNumber: weekNumber,
                sourceLabel: fallbackSourceLabel,
                acceptedWithWarnings: false,
                usedFallback: true,
                displayTitle: programName,
                splitType: splitType,
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary,
                previousWeekReference: previousWeekReference,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                warnings: warnings,
                finalIssues: finalIssues,
                attempts: [],
                replayInputJSON: nil,
                response: response
            )

        case .validatorReplay:
            let candidate = replayJSON?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !candidate.isEmpty else {
                throw ClaudeError.parseError("Paste a follow-up week JSON payload to run validator replay.")
            }

            let decoded = try decodeJSONPayload(WorkoutWeekResponse.self, from: candidate)
            let cleaned = applyingPreselectedSetPrescription(
                to: try await sanitizeWeekResponse(decoded),
                menus: exerciseMenus,
                dayStart: dayStart
            )
            let issues = validateWeekResponse(
                cleaned,
                dayStart: dayStart,
                dayEnd: dayEnd,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                blueprint: blueprint,
                expectedExerciseMenus: exerciseMenus
            )
            let attempt = WorkoutGeneratorDebugAttempt(
                attemptNumber: 1,
                rawPayload: candidate,
                sanitizedPayload: try? encodeDebugJSONString(cleaned),
                validatorIssues: issues,
                outcome: issues.isEmpty ? "Replay passed validator" : "Replay flagged validator issues"
            )

            return try debugWeekReport(
                mode: mode,
                weekNumber: weekNumber,
                sourceLabel: sourceLabel(from: cleaned.weekSummary, fallback: "[Replay]"),
                acceptedWithWarnings: false,
                usedFallback: false,
                displayTitle: programName,
                splitType: splitType,
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary,
                previousWeekReference: previousWeekReference,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                warnings: warnings,
                finalIssues: issues,
                attempts: [attempt],
                replayInputJSON: candidate,
                response: cleaned
            )

        case .liveAI:
            var requestBody = structuredRequestBody(
                config: config,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                toolName: weekToolName,
                toolSchema: toolSchema
            )

            var attempts: [WorkoutGeneratorDebugAttempt] = []
            var lastIssues: [String] = []

            for attempt in 1...generationAttempts {
                try Task.checkCancellation()
                do {
                    let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                        body: requestBody,
                        toolName: weekToolName,
                        timeout: config.timeout,
                        context: requestContext
                    )

                    do {
                        try Task.checkCancellation()
                        let decoded = try decodeJSONPayload(WorkoutWeekResponse.self, from: jsonString)
                        let cleaned = applyingPreselectedSetPrescription(
                            to: try await sanitizeWeekResponse(decoded),
                            menus: exerciseMenus,
                            dayStart: dayStart
                        )
                        let issues = validateWeekResponse(
                            cleaned,
                            dayStart: dayStart,
                            dayEnd: dayEnd,
                            previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                            blueprint: blueprint,
                            expectedExerciseMenus: exerciseMenus
                        )
                        let sanitizedPayload = try? encodeDebugJSONString(cleaned)

                        if issues.isEmpty {
                            attempts.append(
                                WorkoutGeneratorDebugAttempt(
                                    attemptNumber: attempt,
                                    rawPayload: jsonString,
                                    sanitizedPayload: sanitizedPayload,
                                    validatorIssues: [],
                                    outcome: "Accepted"
                                )
                            )
                            let labeled = labeledWeekResponse(cleaned, sourceLabel: aiSourceLabel)
                            return try debugWeekReport(
                                mode: mode,
                                weekNumber: weekNumber,
                                sourceLabel: aiSourceLabel,
                                acceptedWithWarnings: false,
                                usedFallback: false,
                                displayTitle: programName,
                                splitType: splitType,
                                analysisSummary: analysisSummary,
                                trainingIntentSummary: intentSummary,
                                blueprintSummary: blueprintSummary,
                                previousWeekReference: previousWeekReference,
                                systemPrompt: systemPrompt,
                                userPrompt: userPrompt,
                                warnings: warnings,
                                finalIssues: [],
                                attempts: attempts,
                                replayInputJSON: nil,
                                response: labeled
                            )
                        }

                        if shouldAcceptAIOutput(despite: issues, menuLocked: true) {
                            attempts.append(
                                WorkoutGeneratorDebugAttempt(
                                    attemptNumber: attempt,
                                    rawPayload: jsonString,
                                    sanitizedPayload: sanitizedPayload,
                                    validatorIssues: issues,
                                    outcome: "Accepted with heuristic validator warnings"
                                )
                            )
                            let labeled = labeledWeekResponse(cleaned, sourceLabel: aiSourceLabel)
                            return try debugWeekReport(
                                mode: mode,
                                weekNumber: weekNumber,
                                sourceLabel: aiSourceLabel,
                                acceptedWithWarnings: true,
                                usedFallback: false,
                                displayTitle: programName,
                                splitType: splitType,
                                analysisSummary: analysisSummary,
                                trainingIntentSummary: intentSummary,
                                blueprintSummary: blueprintSummary,
                                previousWeekReference: previousWeekReference,
                                systemPrompt: systemPrompt,
                                userPrompt: userPrompt,
                                warnings: warnings,
                                finalIssues: issues,
                                attempts: attempts,
                                replayInputJSON: nil,
                                response: labeled
                            )
                        }

                        attempts.append(
                            WorkoutGeneratorDebugAttempt(
                                attemptNumber: attempt,
                                rawPayload: jsonString,
                                sanitizedPayload: sanitizedPayload,
                                validatorIssues: issues,
                                outcome: "Rejected by validator"
                            )
                        )
                        lastIssues = issues

                        if attempt < generationAttempts {
                            requestBody = correctionRequestBody(
                                config: config,
                                systemPrompt: systemPrompt,
                                toolName: weekToolName,
                                toolSchema: toolSchema,
                                issues: issues,
                                context: context,
                                originalUserPrompt: userPrompt,
                                previousPayloadJSON: sanitizedPayload ?? jsonString
                            )
                        }
                    } catch {
                        let issue = "Payload decode failed: \(error.localizedDescription)"
                        attempts.append(
                            WorkoutGeneratorDebugAttempt(
                                attemptNumber: attempt,
                                rawPayload: jsonString,
                                sanitizedPayload: nil,
                                validatorIssues: [issue],
                                outcome: "Decode failure"
                            )
                        )
                        lastIssues = [issue]

                        if attempt < generationAttempts {
                            requestBody = correctionRequestBody(
                                config: config,
                                systemPrompt: systemPrompt,
                                toolName: weekToolName,
                                toolSchema: toolSchema,
                                issues: [issue],
                                context: context,
                                originalUserPrompt: userPrompt
                            )
                        }
                    }
                } catch {
                    let issue = "API error (attempt \(attempt)): \(error.localizedDescription)"
                    attempts.append(
                        WorkoutGeneratorDebugAttempt(
                            attemptNumber: attempt,
                            rawPayload: nil,
                            sanitizedPayload: nil,
                            validatorIssues: [issue],
                            outcome: "Request failure"
                        )
                    )
                    lastIssues = [issue]

                    if shouldAbortFallback(for: error) {
                        return debugWeekFailureReport(
                            weekNumber: weekNumber,
                            displayTitle: "Week \(weekNumber) Live AI Debug Failure",
                            splitType: splitType,
                            analysisSummary: analysisSummary,
                            trainingIntentSummary: intentSummary,
                            blueprintSummary: blueprintSummary,
                            previousWeekReference: previousWeekReference,
                            systemPrompt: systemPrompt,
                            userPrompt: userPrompt,
                            warnings: warnings + [
                                "Recovery Engine was not applied because the request failed before the lab had a trustworthy AI payload to validate."
                            ],
                            attempts: attempts,
                            terminalError: terminalGenerationError(
                                while: "running live week \(weekNumber) generator debug",
                                underlying: error
                            ).localizedDescription
                        )
                    }

                    if attempt < generationAttempts {
                        requestBody = correctionRequestBody(
                            config: config,
                            systemPrompt: systemPrompt,
                            toolName: weekToolName,
                            toolSchema: toolSchema,
                            issues: [correctionIssue(for: error)],
                            context: context,
                            originalUserPrompt: userPrompt
                        )
                    }
                }
            }

            try Task.checkCancellation()
            let fallback = buildProceduralWeek(
                weekNumber: weekNumber,
                dayStart: dayStart,
                dayEnd: dayEnd,
                splitType: splitType,
                programName: programName,
                trainingIntent: trainingIntent,
                blueprint: blueprint,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                exerciseMenus: exerciseMenus,
                diagnostic: lastIssues.joined(separator: " | ")
            )
            let fallbackIssues = validateWeekResponse(
                fallback,
                dayStart: dayStart,
                dayEnd: dayEnd,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                blueprint: blueprint,
                expectedExerciseMenus: exerciseMenus
            )
            let fallbackWarning = lastIssues.isEmpty
                ? "Live AI exited into procedural fallback without a specific issue trace."
                : "Live AI fell back after: \(lastIssues.joined(separator: " | "))"

            warnings.append(fallbackWarning)

            return try debugWeekReport(
                mode: mode,
                weekNumber: weekNumber,
                sourceLabel: fallbackSourceLabel,
                acceptedWithWarnings: false,
                usedFallback: true,
                displayTitle: programName,
                splitType: splitType,
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary,
                previousWeekReference: previousWeekReference,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                warnings: warnings,
                finalIssues: fallbackIssues,
                attempts: attempts,
                replayInputJSON: nil,
                response: fallback
            )
        }
    }

}
