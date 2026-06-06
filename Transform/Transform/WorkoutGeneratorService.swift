import Foundation
#if canImport(os)
import os
#endif

// MARK: - Workout Generator Service (Week-by-Week)

extension ClaudeService {

    var generationAttempts: Int { 3 }
    var aiSourceLabel: String { "[AI Coach]" }
    var fallbackSourceLabel: String { "[Recovery Engine]" }
    var evidenceProfile: HypertrophyEvidenceProfile { Self.evidenceProfileCache }
    static let evidenceProfileCache = HypertrophyEvidenceProfile(
        version: "hypertrophy_v1_5",
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
        var lines: [String] = [
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
            "Warnings:",
            warnings.isEmpty ? "No warnings." : warnings.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
            "",
            "Validator Issues:",
            warnings.isEmpty ? "No validator issues." : warnings.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
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

    func generateWeekOne(from analysisResult: BodyAnalysisResult, performanceHistory: String? = nil) async throws -> WorkoutProgramGenerationResult {
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
        let config = weekOneConfig
        let toolSchema = programToolSchema()
        let systemPrompt = weekOneSystemPrompt()
        let userPrompt = weekOneUserPrompt(context: context, performanceHistory: performanceHistory)
        let requestContext = workoutRequestContext(
            phase: "week_one",
            weekNumber: 1,
            analysisContext: context,
            previousWeekReference: nil,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        var requestBody = structuredRequestBody(
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

        for attempt in 1...generationAttempts {
            try Task.checkCancellation()
            do {
                WorkoutGenerationDiagnostics.markStage("requesting week 1 program from AI (attempt \(attempt))")
                let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                    body: requestBody,
                    toolName: programToolName,
                    timeout: config.timeout,
                    context: requestContext
                )

                WorkoutGenerationDiagnostics.markStage("decoding week 1 JSON (attempt \(attempt), \(jsonString.count) chars, \(Self.availableMemoryMB())MB free)")
                let decoded = try decodeJSONPayload(WorkoutProgramResponse.self, from: jsonString)
                WorkoutGenerationDiagnostics.markStage("sanitizing week 1 (attempt \(attempt), \(Self.payloadProfile(for: decoded.days)))")
                let cleaned = try await sanitizeProgramResponse(decoded)
                WorkoutGenerationDiagnostics.markStage("validating week 1 (attempt \(attempt))")
                let issues = validateProgramResponse(cleaned, blueprint: blueprint)

                if issues.isEmpty {
                    attemptTrace.append("Attempt \(attempt): Accepted — no issues")
                    let labeled = labeledProgramResponse(cleaned, sourceLabel: aiSourceLabel)
                    return WorkoutProgramGenerationResult(
                        response: labeled,
                        validatorWarnings: [],
                        bundleText: buildBundle(response: labeled, warnings: [], usedFallback: false)
                    )
                }

                if attempt >= generationAttempts {
                    let (trimmedDays, didTrim) = trimOvershootExercises(
                        days: cleaned.days,
                        blueprint: blueprint
                    )
                    if didTrim {
                        let trimmed = WorkoutProgramResponse(
                            programName: cleaned.programName,
                            programSummary: cleaned.programSummary,
                            splitType: cleaned.splitType,
                            daysPerWeek: cleaned.daysPerWeek,
                            days: trimmedDays
                        )
                        let trimmedIssues = validateProgramResponse(trimmed, blueprint: blueprint)
                        if trimmedIssues.isEmpty {
                            print("[WorkoutGeneratorService] Week 1 overshoot trimmed — all issues resolved")
                            attemptTrace.append("Attempt \(attempt): Accepted after overshoot trim — all issues resolved")
                            let labeled = labeledProgramResponse(trimmed, sourceLabel: aiSourceLabel)
                            return WorkoutProgramGenerationResult(
                                response: labeled,
                                validatorWarnings: [],
                                bundleText: buildBundle(response: labeled, warnings: [], usedFallback: false)
                            )
                        }
                        if shouldAcceptAIOutput(
                            despite: trimmedIssues,
                            attempt: attempt,
                            generationAttempts: generationAttempts
                        ) {
                            print("[WorkoutGeneratorService] Week 1 accepted after overshoot trim with warnings: \(trimmedIssues.joined(separator: " | "))")
                            attemptTrace.append("Attempt \(attempt): Accepted after overshoot trim with warnings\nIssues:\n\(trimmedIssues.map { "- \($0)" }.joined(separator: "\n"))")
                            let labeled = labeledProgramResponse(trimmed, sourceLabel: aiSourceLabel)
                            return WorkoutProgramGenerationResult(
                                response: labeled,
                                validatorWarnings: trimmedIssues,
                                bundleText: buildBundle(response: labeled, warnings: trimmedIssues, usedFallback: false)
                            )
                        }
                    }
                }

                if shouldAcceptAIOutput(
                    despite: issues,
                    attempt: attempt,
                    generationAttempts: generationAttempts
                ) {
                    print("[WorkoutGeneratorService] Week 1 accepted with heuristic validator warnings: \(issues.joined(separator: " | "))")
                    attemptTrace.append("Attempt \(attempt): Accepted with warnings\nIssues:\n\(issues.map { "- \($0)" }.joined(separator: "\n"))")
                    let labeled = labeledProgramResponse(cleaned, sourceLabel: aiSourceLabel)
                    return WorkoutProgramGenerationResult(
                        response: labeled,
                        validatorWarnings: issues,
                        bundleText: buildBundle(response: labeled, warnings: issues, usedFallback: false)
                    )
                }

                attemptTrace.append("Attempt \(attempt): Rejected by validator\nIssues:\n\(issues.map { "- \($0)" }.joined(separator: "\n"))")
                lastIssues = issues
                if attempt < generationAttempts {
                    requestBody = correctionRequestBody(
                        config: config,
                        toolName: programToolName,
                        toolSchema: toolSchema,
                        issues: issues,
                        context: context,
                        originalUserPrompt: userPrompt
                    )
                    continue
                }
            } catch {
                attemptTrace.append("Attempt \(attempt): API error — \(error.localizedDescription)")
                lastIssues = ["API error (attempt \(attempt)): \(error.localizedDescription)"]

                if shouldAbortFallback(for: error) {
                    throw terminalGenerationError(
                        while: "generating your initial workout program",
                        underlying: error
                    )
                }

                if attempt < generationAttempts {
                    requestBody = correctionRequestBody(
                        config: config,
                        toolName: programToolName,
                        toolSchema: toolSchema,
                        issues: [correctionIssue(for: error)],
                        context: context,
                        originalUserPrompt: userPrompt
                    )
                    continue
                }
            }
        }

        if !lastIssues.isEmpty {
            print("[WorkoutGeneratorService] Week 1 fallback activated after issues: \(lastIssues.joined(separator: " | "))")
        }

        WorkoutGenerationDiagnostics.markStage("building procedural week 1 fallback")
        let fallbackResponse = try validatedProceduralWeekOneProgram(
            from: analysisResult,
            trainingIntent: trainingIntent,
            blueprint: blueprint,
            diagnostic: lastIssues.joined(separator: " | ")
        )
        return WorkoutProgramGenerationResult(
            response: fallbackResponse,
            validatorWarnings: lastIssues,
            bundleText: buildBundle(response: fallbackResponse, warnings: lastIssues, usedFallback: true)
        )
    }

    static func availableMemoryMB() -> Int {
        #if canImport(os)
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
        performanceHistory: String? = nil
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
        let config = nextWeekConfig
        let toolSchema = weekToolSchema(dayStart: dayStart, dayEnd: dayEnd)
        let systemPrompt = nextWeekSystemPrompt(weekNumber: weekNumber, splitType: splitType, programName: programName)
        let userPrompt = nextWeekUserPrompt(
            weekNumber: weekNumber,
            dayStart: dayStart,
            dayEnd: dayEnd,
            previousWeekReference: previousWeekReference,
            analysisContext: context,
            performanceHistory: performanceHistory
        )
        let requestContext = workoutRequestContext(
            phase: "next_week",
            weekNumber: weekNumber,
            analysisContext: context,
            previousWeekReference: previousWeekReference,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )
        var requestBody = structuredRequestBody(
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

        for attempt in 1...generationAttempts {
            try Task.checkCancellation()
            do {
                WorkoutGenerationDiagnostics.markStage("requesting week \(weekNumber) program from AI (attempt \(attempt))")
                let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                    body: requestBody,
                    toolName: weekToolName,
                    timeout: config.timeout,
                    context: requestContext
                )
                WorkoutGenerationDiagnostics.markStage("decoding week \(weekNumber) JSON (attempt \(attempt), \(jsonString.count) chars, \(Self.availableMemoryMB())MB free)")
                let decoded = try decodeJSONPayload(WorkoutWeekResponse.self, from: jsonString)
                WorkoutGenerationDiagnostics.markStage("sanitizing week \(weekNumber) (attempt \(attempt), \(Self.payloadProfile(for: decoded.days)))")
                let cleaned = try await sanitizeWeekResponse(decoded)
                WorkoutGenerationDiagnostics.markStage("validating week \(weekNumber) (attempt \(attempt))")
                let issues = validateWeekResponse(
                    cleaned,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                    blueprint: blueprint
                )

                if issues.isEmpty {
                    attemptTrace.append("Attempt \(attempt): Accepted — no issues")
                    let labeled = labeledWeekResponse(cleaned, sourceLabel: aiSourceLabel)
                    return WorkoutWeekGenerationResult(
                        response: labeled,
                        validatorWarnings: [],
                        bundleText: buildWeekBundle(weekSummary: labeled.weekSummary, days: labeled.days, warnings: [], usedFallback: false)
                    )
                }

                if attempt >= generationAttempts {
                    let (trimmedDays, didTrim) = trimOvershootExercises(
                        days: cleaned.days,
                        blueprint: blueprint,
                        dayStart: dayStart
                    )
                    if didTrim {
                        let trimmed = WorkoutWeekResponse(
                            weekSummary: cleaned.weekSummary,
                            days: trimmedDays
                        )
                        let trimmedIssues = validateWeekResponse(
                            trimmed,
                            dayStart: dayStart,
                            dayEnd: dayEnd,
                            previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                            blueprint: blueprint
                        )
                        if trimmedIssues.isEmpty {
                            print("[WorkoutGeneratorService] Week \(weekNumber) overshoot trimmed — all issues resolved")
                            attemptTrace.append("Attempt \(attempt): Accepted after overshoot trim — all issues resolved")
                            let labeled = labeledWeekResponse(trimmed, sourceLabel: aiSourceLabel)
                            return WorkoutWeekGenerationResult(
                                response: labeled,
                                validatorWarnings: [],
                                bundleText: buildWeekBundle(weekSummary: labeled.weekSummary, days: labeled.days, warnings: [], usedFallback: false)
                            )
                        }
                        if shouldAcceptAIOutput(
                            despite: trimmedIssues,
                            attempt: attempt,
                            generationAttempts: generationAttempts
                        ) {
                            print("[WorkoutGeneratorService] Week \(weekNumber) accepted after overshoot trim with warnings: \(trimmedIssues.joined(separator: " | "))")
                            attemptTrace.append("Attempt \(attempt): Accepted after overshoot trim with warnings\nIssues:\n\(trimmedIssues.map { "- \($0)" }.joined(separator: "\n"))")
                            let labeled = labeledWeekResponse(trimmed, sourceLabel: aiSourceLabel)
                            return WorkoutWeekGenerationResult(
                                response: labeled,
                                validatorWarnings: trimmedIssues,
                                bundleText: buildWeekBundle(weekSummary: labeled.weekSummary, days: labeled.days, warnings: trimmedIssues, usedFallback: false)
                            )
                        }
                    }
                }

                if shouldAcceptAIOutput(
                    despite: issues,
                    attempt: attempt,
                    generationAttempts: generationAttempts
                ) {
                    print("[WorkoutGeneratorService] Week \(weekNumber) accepted with heuristic validator warnings: \(issues.joined(separator: " | "))")
                    attemptTrace.append("Attempt \(attempt): Accepted with warnings\nIssues:\n\(issues.map { "- \($0)" }.joined(separator: "\n"))")
                    let labeled = labeledWeekResponse(cleaned, sourceLabel: aiSourceLabel)
                    return WorkoutWeekGenerationResult(
                        response: labeled,
                        validatorWarnings: issues,
                        bundleText: buildWeekBundle(weekSummary: labeled.weekSummary, days: labeled.days, warnings: issues, usedFallback: false)
                    )
                }

                attemptTrace.append("Attempt \(attempt): Rejected by validator\nIssues:\n\(issues.map { "- \($0)" }.joined(separator: "\n"))")
                lastIssues = issues
                if attempt < generationAttempts {
                    requestBody = correctionRequestBody(
                        config: config,
                        toolName: weekToolName,
                        toolSchema: toolSchema,
                        issues: issues,
                        context: context,
                        originalUserPrompt: userPrompt
                    )
                    continue
                }
            } catch {
                attemptTrace.append("Attempt \(attempt): API error — \(error.localizedDescription)")
                lastIssues = ["API error (attempt \(attempt)): \(error.localizedDescription)"]

                if shouldAbortFallback(for: error) {
                    throw terminalGenerationError(
                        while: "generating week \(weekNumber)",
                        underlying: error
                    )
                }

                if attempt < generationAttempts {
                    requestBody = correctionRequestBody(
                        config: config,
                        toolName: weekToolName,
                        toolSchema: toolSchema,
                        issues: [correctionIssue(for: error)],
                        context: context,
                        originalUserPrompt: userPrompt
                    )
                    continue
                }
            }
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
            diagnostic: lastIssues.joined(separator: " | ")
        )
        return WorkoutWeekGenerationResult(
            response: fallbackResponse,
            validatorWarnings: lastIssues,
            bundleText: buildWeekBundle(weekSummary: fallbackResponse.weekSummary, days: fallbackResponse.days, warnings: lastIssues, usedFallback: true)
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
        let config = weekOneConfig
        let toolSchema = programToolSchema()
        let systemPrompt = weekOneSystemPrompt()
        let userPrompt = weekOneUserPrompt(context: context)
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
            let response = buildProceduralWeekOneProgram(
                from: analysisResult,
                trainingIntent: trainingIntent,
                blueprint: blueprint
            )
            let finalIssues = validateProgramResponse(response, blueprint: blueprint)
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
            let cleaned = try await sanitizeProgramResponse(decoded)
            let issues = validateProgramResponse(cleaned, blueprint: blueprint)
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
                        let cleaned = try await sanitizeProgramResponse(decoded)
                        let issues = validateProgramResponse(cleaned, blueprint: blueprint)
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

                        if attempt >= generationAttempts {
                            let (trimmedDays, didTrim) = trimOvershootExercises(
                                days: cleaned.days,
                                blueprint: blueprint
                            )
                            if didTrim {
                                let trimmedProgram = WorkoutProgramResponse(
                                    programName: cleaned.programName,
                                    programSummary: cleaned.programSummary,
                                    splitType: cleaned.splitType,
                                    daysPerWeek: cleaned.daysPerWeek,
                                    days: trimmedDays
                                )
                                let trimmedIssues = validateProgramResponse(trimmedProgram, blueprint: blueprint)
                                let trimmedPayload = try? encodeDebugJSONString(trimmedProgram)
                                if trimmedIssues.isEmpty || shouldAcceptAIOutput(
                                    despite: trimmedIssues,
                                    attempt: attempt,
                                    generationAttempts: generationAttempts
                                ) {
                                    attempts.append(
                                        WorkoutGeneratorDebugAttempt(
                                            attemptNumber: attempt,
                                            rawPayload: jsonString,
                                            sanitizedPayload: trimmedPayload,
                                            validatorIssues: trimmedIssues,
                                            outcome: trimmedIssues.isEmpty
                                                ? "Accepted after overshoot trim"
                                                : "Accepted after overshoot trim with warnings"
                                        )
                                    )
                                    let labeled = labeledProgramResponse(trimmedProgram, sourceLabel: aiSourceLabel)
                                    return try debugProgramReport(
                                        stage: .weekOne,
                                        mode: mode,
                                        weekNumber: 1,
                                        sourceLabel: aiSourceLabel,
                                        acceptedWithWarnings: !trimmedIssues.isEmpty,
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
                                        finalIssues: trimmedIssues,
                                        attempts: attempts,
                                        replayInputJSON: nil,
                                        response: labeled
                                    )
                                }
                            }
                        }

                        if shouldAcceptAIOutput(
                            despite: issues,
                            attempt: attempt,
                            generationAttempts: generationAttempts
                        ) {
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
                                toolName: programToolName,
                                toolSchema: toolSchema,
                                issues: issues,
                                context: context,
                                originalUserPrompt: userPrompt
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
                diagnostic: lastIssues.joined(separator: " | ")
            )
            let fallbackIssues = validateProgramResponse(fallback, blueprint: blueprint)
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
        let config = nextWeekConfig
        let toolSchema = weekToolSchema(dayStart: dayStart, dayEnd: dayEnd)
        let systemPrompt = nextWeekSystemPrompt(weekNumber: weekNumber, splitType: splitType, programName: programName)
        let userPrompt = nextWeekUserPrompt(
            weekNumber: weekNumber,
            dayStart: dayStart,
            dayEnd: dayEnd,
            previousWeekReference: previousWeekReference,
            analysisContext: context
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
            let response = buildProceduralWeek(
                weekNumber: weekNumber,
                dayStart: dayStart,
                dayEnd: dayEnd,
                splitType: splitType,
                programName: programName,
                trainingIntent: trainingIntent,
                blueprint: blueprint,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil
            )
            let finalIssues = validateWeekResponse(
                response,
                dayStart: dayStart,
                dayEnd: dayEnd,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                blueprint: blueprint
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
            let cleaned = try await sanitizeWeekResponse(decoded)
            let issues = validateWeekResponse(
                cleaned,
                dayStart: dayStart,
                dayEnd: dayEnd,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                blueprint: blueprint
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
                        let cleaned = try await sanitizeWeekResponse(decoded)
                        let issues = validateWeekResponse(
                            cleaned,
                            dayStart: dayStart,
                            dayEnd: dayEnd,
                            previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                            blueprint: blueprint
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

                        if attempt >= generationAttempts {
                            let (trimmedDays, didTrim) = trimOvershootExercises(
                                days: cleaned.days,
                                blueprint: blueprint,
                                dayStart: dayStart
                            )
                            if didTrim {
                                let trimmedWeek = WorkoutWeekResponse(
                                    weekSummary: cleaned.weekSummary,
                                    days: trimmedDays
                                )
                                let trimmedIssues = validateWeekResponse(
                                    trimmedWeek,
                                    dayStart: dayStart,
                                    dayEnd: dayEnd,
                                    previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                                    blueprint: blueprint
                                )
                                let trimmedPayload = try? encodeDebugJSONString(trimmedWeek)
                                if trimmedIssues.isEmpty || shouldAcceptAIOutput(
                                    despite: trimmedIssues,
                                    attempt: attempt,
                                    generationAttempts: generationAttempts
                                ) {
                                    attempts.append(
                                        WorkoutGeneratorDebugAttempt(
                                            attemptNumber: attempt,
                                            rawPayload: jsonString,
                                            sanitizedPayload: trimmedPayload,
                                            validatorIssues: trimmedIssues,
                                            outcome: trimmedIssues.isEmpty
                                                ? "Accepted after overshoot trim"
                                                : "Accepted after overshoot trim with warnings"
                                        )
                                    )
                                    let labeled = labeledWeekResponse(trimmedWeek, sourceLabel: aiSourceLabel)
                                    return try debugWeekReport(
                                        mode: mode,
                                        weekNumber: weekNumber,
                                        sourceLabel: aiSourceLabel,
                                        acceptedWithWarnings: !trimmedIssues.isEmpty,
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
                                        finalIssues: trimmedIssues,
                                        attempts: attempts,
                                        replayInputJSON: nil,
                                        response: labeled
                                    )
                                }
                            }
                        }

                        if shouldAcceptAIOutput(
                            despite: issues,
                            attempt: attempt,
                            generationAttempts: generationAttempts
                        ) {
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
                                toolName: weekToolName,
                                toolSchema: toolSchema,
                                issues: issues,
                                context: context,
                                originalUserPrompt: userPrompt
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
                diagnostic: lastIssues.joined(separator: " | ")
            )
            let fallbackIssues = validateWeekResponse(
                fallback,
                dayStart: dayStart,
                dayEnd: dayEnd,
                previousWeekDays: hasValidPreviousWeek ? previousWeekDays : nil,
                blueprint: blueprint
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
