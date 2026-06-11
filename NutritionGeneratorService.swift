import Foundation

// MARK: - Nutrition Program Response Models

struct NutritionProgramResponse: Codable {
    let programName: String
    let programSummary: String
    let proteinCoverageNote: String
    let weekOne: NutritionWeekResponse
}

struct NutritionWeekResponse: Codable, Identifiable {
    let weekNumber: Int
    let weekSummary: String
    let phaseFocus: String
    let coachNotes: String
    let dailyCaloriesTraining: Int
    let dailyCaloriesRest: Int
    let dailyProteinG: Int
    let dailyCarbsGTraining: Int
    let dailyCarbsGRest: Int
    let dailyFatG: Int
    let trainingDay: DailyNutritionTemplate
    let restDay: DailyNutritionTemplate
    let weeklyGrocery: [NutritionGroceryCategory]

    var id: Int { weekNumber }
}

struct DailyNutritionTemplate: Codable {
    let label: String
    let totalCalories: Int
    let totalProteinG: Int
    let totalCarbsG: Int
    let totalFatG: Int
    let meals: [MealSlotResponse]
}

struct MealSlotResponse: Codable, Identifiable {
    let mealName: String
    let primaryOption: String
    let substitutions: [String]
    let approxCalories: Int
    let approxProteinG: Int
    let approxCarbsG: Int
    let approxFatG: Int
    let timingNote: String

    var id: String { mealName }
}

struct NutritionGroceryCategory: Codable, Identifiable {
    let category: String
    let items: [NutritionGroceryItem]

    var id: String { category }
}

struct NutritionGroceryItem: Codable, Identifiable {
    let name: String
    let quantity: String
    let substitutions: [String]
    let rationale: String

    var id: String { name }
}

// MARK: - Nutrition Generator Service

extension ClaudeService {

    private var nutritionGenerationAttempts: Int { 3 }
    private var nutritionAISourceLabel: String { "[AI Coach]" }
    private var nutritionFallbackSourceLabel: String { "[Recovery Engine]" }
    private var nutritionProgramToolName: String { "emit_nutrition_program" }
    private var nutritionWeekToolName: String { "emit_nutrition_week" }

    // MARK: - Generate Nutrition Week 1

    func generateNutritionWeekOne(from analysisResult: BodyAnalysisResult) async throws -> NutritionProgramResponse {
        let context = nutritionAnalysisContext(from: analysisResult)
        let macroLine = macroTargetLine(from: analysisResult.macroTargets)
        let config = nutritionWeekOneConfig
        let toolSchema = nutritionProgramToolSchema()
        let systemPrompt = nutritionWeekOneSystemPrompt()
        let userPrompt = nutritionWeekOneUserPrompt(context: context, macroLine: macroLine)

        var requestBody = nutritionStructuredRequestBody(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            toolName: nutritionProgramToolName,
            toolSchema: toolSchema
        )

        var lastIssues: [String] = []
        var lastPayload: String?

        for attempt in 1...nutritionGenerationAttempts {
            do {
                let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                    body: requestBody,
                    toolName: nutritionProgramToolName,
                    timeout: config.timeout
                )
                lastPayload = jsonString
                let decoded = try decodeNutritionPayload(NutritionProgramResponse.self, from: jsonString)
                let cleaned = sanitizeNutritionProgram(decoded)
                let issues = validateNutritionProgram(cleaned)
                if issues.isEmpty {
                    return labeledNutritionProgram(cleaned, sourceLabel: nutritionAISourceLabel)
                }
                lastIssues = issues
                if attempt < nutritionGenerationAttempts {
                    requestBody = nutritionCorrectionRequestBody(
                        config: config,
                        toolName: nutritionProgramToolName,
                        toolSchema: toolSchema,
                        issues: issues,
                        context: context,
                        originalUserPrompt: userPrompt,
                        previousPayload: lastPayload
                    )
                    continue
                }
            } catch {
                // Cancellation must propagate — converting it into more attempts or a
                // fallback build burns API credits after the user navigated away.
                if error is CancellationError { throw error }

                // Terminal failures (offline, auth, rate-limit exhaustion, truncation)
                // cannot be fixed by re-asking the model. Throw so the caller can keep
                // existing saved output instead of overwriting it with a generic fallback.
                guard error.isRecoverableStructuredOutputFailure else { throw error }

                lastIssues = ["Structured output issue (attempt \(attempt)): \(error.localizedDescription)"]
                if attempt < nutritionGenerationAttempts {
                    requestBody = nutritionCorrectionRequestBody(
                        config: config,
                        toolName: nutritionProgramToolName,
                        toolSchema: toolSchema,
                        issues: ["Previous call did not return a valid tool_use response: \(error.localizedDescription). Call the tool again with complete, valid fields."],
                        context: context,
                        originalUserPrompt: userPrompt,
                        previousPayload: lastPayload
                    )
                    continue
                }
            }
        }

        if !lastIssues.isEmpty {
            print("[NutritionGeneratorService] Week 1 fallback activated after issues: \(lastIssues.joined(separator: " | "))")
        }

        return buildFallbackNutritionProgram(
            from: analysisResult,
            diagnostic: lastIssues.joined(separator: " | ")
        )
    }

    // MARK: - Generate Nutrition Week 2/3/4

    func generateNutritionNextWeek(
        weekNumber: Int,
        previousWeekJSON: String,
        analysisResult: BodyAnalysisResult
    ) async throws -> NutritionWeekResponse {
        let context = nutritionAnalysisContext(from: analysisResult)
        let macroLine = macroTargetLine(from: analysisResult.macroTargets)
        let config = nutritionNextWeekConfig
        let toolSchema = nutritionWeekToolSchema(weekNumber: weekNumber)
        let systemPrompt = nutritionNextWeekSystemPrompt(weekNumber: weekNumber)
        let userPrompt = nutritionNextWeekUserPrompt(
            weekNumber: weekNumber,
            previousWeekJSON: previousWeekJSON,
            analysisContext: context,
            macroLine: macroLine
        )

        var requestBody = nutritionStructuredRequestBody(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            toolName: nutritionWeekToolName,
            toolSchema: toolSchema
        )

        var lastIssues: [String] = []
        var lastPayload: String?

        for attempt in 1...nutritionGenerationAttempts {
            do {
                let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                    body: requestBody,
                    toolName: nutritionWeekToolName,
                    timeout: config.timeout
                )
                lastPayload = jsonString
                let decoded = try decodeNutritionPayload(NutritionWeekResponse.self, from: jsonString)
                let cleaned = sanitizeNutritionWeek(decoded, expectedWeek: weekNumber)
                let issues = validateNutritionWeek(cleaned, expectedWeek: weekNumber)
                if issues.isEmpty {
                    return labeledNutritionWeek(cleaned, sourceLabel: nutritionAISourceLabel)
                }
                lastIssues = issues
                if attempt < nutritionGenerationAttempts {
                    requestBody = nutritionCorrectionRequestBody(
                        config: config,
                        toolName: nutritionWeekToolName,
                        toolSchema: toolSchema,
                        issues: issues,
                        context: context,
                        originalUserPrompt: userPrompt,
                        previousPayload: lastPayload
                    )
                    continue
                }
            } catch {
                // See generateNutritionWeekOne: cancellation propagates, terminal
                // failures throw, only structured-output issues earn a correction retry.
                if error is CancellationError { throw error }
                guard error.isRecoverableStructuredOutputFailure else { throw error }

                lastIssues = ["Structured output issue (attempt \(attempt)): \(error.localizedDescription)"]
                if attempt < nutritionGenerationAttempts {
                    requestBody = nutritionCorrectionRequestBody(
                        config: config,
                        toolName: nutritionWeekToolName,
                        toolSchema: toolSchema,
                        issues: ["Previous call did not return a valid tool_use response: \(error.localizedDescription). Call the tool again with complete, valid fields."],
                        context: context,
                        originalUserPrompt: userPrompt,
                        previousPayload: lastPayload
                    )
                    continue
                }
            }
        }

        if !lastIssues.isEmpty {
            print("[NutritionGeneratorService] Week \(weekNumber) fallback activated after issues: \(lastIssues.joined(separator: " | "))")
        }

        return buildFallbackNutritionWeek(
            weekNumber: weekNumber,
            from: analysisResult,
            diagnostic: lastIssues.joined(separator: " | ")
        )
    }

    // MARK: - Configs

    private struct NutritionGenerationConfig {
        let model: String
        let maxTokens: Int
        let timeout: TimeInterval
    }

    private var nutritionWeekOneConfig: NutritionGenerationConfig {
        NutritionGenerationConfig(model: Config.claudeModel, maxTokens: 8192, timeout: 240)
    }

    private var nutritionNextWeekConfig: NutritionGenerationConfig {
        NutritionGenerationConfig(model: Config.claudeModelLite, maxTokens: 8192, timeout: 180)
    }

    // MARK: - Request Builders

    private func nutritionStructuredRequestBody(
        config: NutritionGenerationConfig,
        systemPrompt: String,
        userPrompt: String,
        toolName: String,
        toolSchema: [String: Any]
    ) -> [String: Any] {
        let tool: [String: Any] = [
            "name": toolName,
            "description": "Emit the nutrition plan in the required structured shape. Always call this tool; never respond with free text.",
            "input_schema": toolSchema
        ]

        // No `temperature`: current Opus models reject sampling parameters with a 400.
        return [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "system": systemPrompt,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
    }

    private func nutritionCorrectionRequestBody(
        config: NutritionGenerationConfig,
        toolName: String,
        toolSchema: [String: Any],
        issues: [String],
        context: String,
        originalUserPrompt: String,
        previousPayload: String?
    ) -> [String: Any] {
        let issueBlock = issues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        You are the same nutrition expert panel as before. Your previous call to the tool did not
        satisfy the coaching intent. Call the tool again and fix ONLY the listed issues while
        preserving everything that was already good. Do not drift from the body analysis.
        """

        // The API is stateless — without the prior payload the model has no "before"
        // to preserve, and every correction becomes a blind full regeneration.
        let previousBlock: String
        if let previousPayload, !previousPayload.isEmpty {
            previousBlock = """

            Your previous output (fix only the listed issues; keep everything else):
            \(String(previousPayload.prefix(6000)))
            """
        } else {
            previousBlock = ""
        }

        let userPrompt = """
        Issues to correct (preserve everything else):
        \(issueBlock)
        \(previousBlock)

        Original assignment (for reference):
        \(originalUserPrompt)

        Analysis context (north star — do not drift from this):
        \(context)
        """

        return nutritionStructuredRequestBody(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            toolName: toolName,
            toolSchema: toolSchema
        )
    }

    // MARK: - Prompts

    private func nutritionWeekOneSystemPrompt() -> String {
        """
        You are a multi-disciplinary nutrition panel designing Week 1 of a personalized 4-week
        nutrition protocol for a specific individual. The panel includes:
        - a sports dietitian (Helms / McDonald school) who sets macros and meal architecture,
        - a metabolic-health specialist who adapts meal timing to the user's actual schedule and metabolic notes,
        - a behavioral coach who makes the plan realistic and sustainable.

        The user's Body Analysis is the north star of this entire 4-week protocol. Every choice
        you make — meal composition, protein allocation, carb timing, grocery items, rationales —
        must be directly traceable to something in the analysis (macro targets, priority muscles,
        top leverage change, metabolic health notes, diet recommendations, psychological insights).

        Structure:
        - Assume 5 training days, 2 rest days per week.
        - Build TWO daily templates: Training Day and Rest Day. Training Day gets more carbs
          (around workouts); Rest Day trims carbs, maintains protein, slight increase in healthy fats.
        - Each daily template must have EXACTLY 4 meals: Breakfast, Lunch, Dinner, Snack.
        - Each meal has: primaryOption (specific food + prep method), 2-3 substitutions, approx macros,
          timingNote (when to eat it and why for THIS person).
        - Weekly grocery list: aggregated quantities to cover 5 training + 2 rest days for ONE person.
          Items must have: name, quantity in US units, 2-3 substitutions, rationale tying the item to
          the body analysis (e.g., "high-leucine protein source for priority muscle recovery").

        Voice:
        - Write like a real coach talking to THIS person, not a generic meal-plan app.
        - coachNotes: 2-3 sentences on what this Week 1 is accomplishing for THIS user given the
          analysis. No template phrases.
        - timingNote on each meal: specific. "Post-training: lean protein + fast carbs to restart
          glycogen" is good; "Eat after workout" is bad.
        - rationale on each grocery item: tie back to the analysis. "Greek yogurt — leucine density
          matches priority shoulders/chest development noted in analysis" is good; "Good source of
          protein" is bad.

        Total plan quality bar:
        - Respect the provided macro targets within ~±10% for the daily totals.
        - Training Day carbs ≈ Rest Day carbs + 20-40%.
        - Protein stays roughly constant across Training/Rest days.
        - Weekly grocery list must be sufficient to execute BOTH templates across 7 days.
        - Keep choices practical for this user's stated schedule and lifestyle constraints
          (batch-prep friendly, quick reheats). Do not assume constraints the analysis does not state.

        Always call the emit_nutrition_program tool. Never respond with free text.
        """
    }

    private func nutritionWeekOneUserPrompt(context: String, macroLine: String) -> String {
        """
        Build Week 1 of this individual's 4-week nutrition protocol. Treat the analysis below as the
        north star — every meal, every grocery item, every rationale should be traceable back to it.

        --- Body Analysis ---
        \(context)
        --- end Body Analysis ---

        Daily macro targets from analysis: \(macroLine)

        Requirements:
        - Name the program meaningfully (reference the analysis, not a generic label).
        - programSummary: ONE sentence on what this 4-week arc is designed to accomplish for THIS
          person, referencing the analysis.
        - proteinCoverageNote: ONE sentence on how the protein architecture supports the priority
          muscles and goals from the analysis.
        - weekOne.phaseFocus: short phrase like "Week 1 — Establish baseline adherence and protein floor"
        - weekOne.coachNotes: 2-3 sentences from the expert panel about WHY this week looks the way
          it does for THIS user.
        - Training Day and Rest Day templates as specified above.
        - Weekly grocery list aggregated for one person over 7 days.

        Call the emit_nutrition_program tool with your answer.
        """
    }

    private func nutritionNextWeekSystemPrompt(weekNumber: Int) -> String {
        """
        You are the same multi-disciplinary nutrition panel that designed Week 1. You are now
        writing Week \(weekNumber) of the same 4-week nutrition protocol.

        CRITICAL: The Body Analysis is still the north star. The previous week is only a
        PROGRESSION REFERENCE — do not copy meals forward as templates. Use it to know what was
        established last week so you can apply appropriate phase-shift for THIS week.

        Structure, voice, quality bar: same as Week 1 (5 training days + 2 rest days, 2 templates
        × 4 meals, weekly grocery list, expert-panel voice, rationales tied to analysis).

        Phase guidance for Week \(weekNumber):
        \(nutritionPhaseGuidance(for: weekNumber))

        Always call the emit_nutrition_week tool. Never respond with free text.
        """
    }

    private func nutritionNextWeekUserPrompt(
        weekNumber: Int,
        previousWeekJSON: String,
        analysisContext: String,
        macroLine: String
    ) -> String {
        """
        Generate Week \(weekNumber) of the 4-week nutrition protocol.

        --- Body Analysis (north star — drives nutrition intent) ---
        \(analysisContext)
        --- end Body Analysis ---

        Daily macro targets from analysis: \(macroLine)

        --- Previous week (progression reference ONLY — don't copy) ---
        \(previousWeekJSON)
        --- end previous week ---

        Phase guidance for Week \(weekNumber):
        \(nutritionPhaseGuidance(for: weekNumber))

        Requirements:
        - weekNumber field MUST be \(weekNumber).
        - phaseFocus: short phrase describing this week's nutritional intent.
        - coachNotes: 2-3 sentences from the expert panel about WHY this week differs from last week
          for THIS user, referencing the analysis.
        - Training Day and Rest Day templates with 4 meals each. Rotate at least 50% of the meal
          primaryOptions vs. the previous week — keep familiar staples but introduce variety.
        - Weekly grocery list updated to match the new meals.

        Call the emit_nutrition_week tool with your answer.
        """
    }

    private func nutritionPhaseGuidance(for weekNumber: Int) -> String {
        switch weekNumber {
        case 2:
            return """
            Week 2 — Adherence lock-in + slight carb nudge. Modestly increase Training Day carbs
            (~5-10%) to support rising training volume. Rest Day macros hold. Rotate meal variety
            to prevent flavor fatigue while keeping prep simple.
            """
        case 3:
            return """
            Week 3 — Peak nutritional support. Highest Training Day carb allocation of the cycle,
            timed around sessions. Protein stays high to support peak training stress. Grocery
            list should reflect performance-oriented choices (fast carbs pre/post-session).
            """
        case 4:
            return """
            Week 4 — Recovery and consolidation. Pull Training Day carbs back toward Week 1
            levels. Slight emphasis on whole-food anti-inflammatory choices (fatty fish, berries,
            leafy greens). Use this week to cement sustainable habits, not chase performance.
            """
        default:
            return "Apply sensible weekly progression based on the previous week and the analysis priorities."
        }
    }

    // MARK: - Tool Schemas

    private func nStringProp(_ description: String? = nil) -> [String: Any] {
        var prop: [String: Any] = ["type": "string"]
        if let description { prop["description"] = description }
        return prop
    }

    private func nIntProp(minimum: Int? = nil, maximum: Int? = nil, allowedValues: [Int]? = nil) -> [String: Any] {
        var prop: [String: Any] = ["type": "integer"]
        if let minimum { prop["minimum"] = minimum }
        if let maximum { prop["maximum"] = maximum }
        if let allowedValues { prop["enum"] = allowedValues }
        return prop
    }

    private func nStringArrayProp(description: String? = nil) -> [String: Any] {
        var prop: [String: Any] = [
            "type": "array",
            "items": ["type": "string"] as [String: Any]
        ]
        if let description { prop["description"] = description }
        return prop
    }

    private func mealSchema() -> [String: Any] {
        let properties: [String: Any] = [
            "mealName": nStringProp("One of: Breakfast, Lunch, Dinner, Snack."),
            "primaryOption": nStringProp("Specific food + prep method, e.g., 'Grilled chicken breast (6oz) + jasmine rice (1 cup cooked) + steamed broccoli + olive oil drizzle'."),
            "substitutions": nStringArrayProp(description: "2-3 practical substitutes at similar macros."),
            "approxCalories": nIntProp(minimum: 50, maximum: 2000),
            "approxProteinG": nIntProp(minimum: 0, maximum: 150),
            "approxCarbsG": nIntProp(minimum: 0, maximum: 300),
            "approxFatG": nIntProp(minimum: 0, maximum: 120),
            "timingNote": nStringProp("When to eat + why for THIS person, tied to the body analysis.")
        ]
        let required = ["mealName", "primaryOption", "substitutions", "approxCalories", "approxProteinG", "approxCarbsG", "approxFatG", "timingNote"]
        return [
            "type": "object",
            "properties": properties,
            "required": required
        ] as [String: Any]
    }

    private func dailyTemplateSchema() -> [String: Any] {
        let mealsProp: [String: Any] = [
            "type": "array",
            "minItems": 4,
            "maxItems": 4,
            "items": mealSchema(),
            "description": "Exactly 4 meals in order: Breakfast, Lunch, Dinner, Snack."
        ]
        let properties: [String: Any] = [
            "label": nStringProp("Either 'Training Day' or 'Rest Day'."),
            "totalCalories": nIntProp(minimum: 1000, maximum: 5000),
            "totalProteinG": nIntProp(minimum: 60, maximum: 400),
            "totalCarbsG": nIntProp(minimum: 30, maximum: 600),
            "totalFatG": nIntProp(minimum: 20, maximum: 250),
            "meals": mealsProp
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": ["label", "totalCalories", "totalProteinG", "totalCarbsG", "totalFatG", "meals"]
        ] as [String: Any]
    }

    private func groceryItemSchema() -> [String: Any] {
        let properties: [String: Any] = [
            "name": nStringProp("Food item name."),
            "quantity": nStringProp("Quantity in US units (lb, oz, dozen, cups, bag, bottle, etc.)."),
            "substitutions": nStringArrayProp(description: "1-3 practical substitutes."),
            "rationale": nStringProp("Why this item is on the list for THIS person, tied to the body analysis.")
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": ["name", "quantity", "substitutions", "rationale"]
        ] as [String: Any]
    }

    private func groceryCategorySchema() -> [String: Any] {
        let itemsProp: [String: Any] = [
            "type": "array",
            "minItems": 1,
            "items": groceryItemSchema()
        ]
        return [
            "type": "object",
            "properties": [
                "category": nStringProp("e.g., 'Proteins', 'Carbs & Grains', 'Produce', 'Fats & Extras', 'Pantry'."),
                "items": itemsProp
            ] as [String: Any],
            "required": ["category", "items"]
        ] as [String: Any]
    }

    private func weekSchema(weekNumber: Int) -> [String: Any] {
        let grocerySchema: [String: Any] = [
            "type": "array",
            "minItems": 3,
            "items": groceryCategorySchema()
        ]
        let properties: [String: Any] = [
            "weekNumber": nIntProp(allowedValues: [weekNumber]),
            "weekSummary": nStringProp("One sentence describing what this week accomplishes for THIS person."),
            "phaseFocus": nStringProp("Short phrase e.g., 'Week 2 — Adherence lock-in + slight carb nudge'."),
            "coachNotes": nStringProp("2-3 sentences from the expert panel on WHY this week looks like this."),
            "dailyCaloriesTraining": nIntProp(minimum: 1000, maximum: 5000),
            "dailyCaloriesRest": nIntProp(minimum: 1000, maximum: 5000),
            "dailyProteinG": nIntProp(minimum: 60, maximum: 400),
            "dailyCarbsGTraining": nIntProp(minimum: 30, maximum: 600),
            "dailyCarbsGRest": nIntProp(minimum: 30, maximum: 600),
            "dailyFatG": nIntProp(minimum: 20, maximum: 250),
            "trainingDay": dailyTemplateSchema(),
            "restDay": dailyTemplateSchema(),
            "weeklyGrocery": grocerySchema
        ]
        let required = [
            "weekNumber", "weekSummary", "phaseFocus", "coachNotes",
            "dailyCaloriesTraining", "dailyCaloriesRest", "dailyProteinG",
            "dailyCarbsGTraining", "dailyCarbsGRest", "dailyFatG",
            "trainingDay", "restDay", "weeklyGrocery"
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": required
        ] as [String: Any]
    }

    private func nutritionProgramToolSchema() -> [String: Any] {
        let properties: [String: Any] = [
            "programName": nStringProp("Meaningful program name tied to the analysis."),
            "programSummary": nStringProp("ONE sentence on what this 4-week arc is designed to accomplish for THIS person."),
            "proteinCoverageNote": nStringProp("ONE sentence on how the protein architecture supports priority muscles / goals."),
            "weekOne": weekSchema(weekNumber: 1)
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": ["programName", "programSummary", "proteinCoverageNote", "weekOne"]
        ] as [String: Any]
    }

    private func nutritionWeekToolSchema(weekNumber: Int) -> [String: Any] {
        return weekSchema(weekNumber: weekNumber)
    }

    // MARK: - Decode & Sanitize

    private func decodeNutritionPayload<T: Decodable>(_ type: T.Type, from responseText: String) throws -> T {
        // The payload is locally re-serialized tool_use JSON — no fence stripping
        // needed (and global backtick removal would corrupt legitimate content).
        let cleaned = responseText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw ClaudeError.parseError("Tool payload decode failure: could not encode nutrition response as data.")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let short = String(String(describing: error).prefix(180))
            // "Tool payload decode failure" prefix marks this as recoverable, so the
            // generation loop spends a correction retry rather than aborting.
            throw ClaudeError.parseError("Tool payload decode failure: \(short)")
        }
    }

    private func sanitizeNutritionProgram(_ program: NutritionProgramResponse) -> NutritionProgramResponse {
        NutritionProgramResponse(
            programName: program.programName.nTrimmedOr("4-Week Nutrition Protocol"),
            programSummary: program.programSummary.nTrimmedOr("A 4-week nutrition protocol tied to your body analysis."),
            proteinCoverageNote: program.proteinCoverageNote.nTrimmedOr("Protein architecture supports your priority muscles."),
            weekOne: sanitizeNutritionWeek(program.weekOne, expectedWeek: 1)
        )
    }

    private func sanitizeNutritionWeek(_ week: NutritionWeekResponse, expectedWeek: Int) -> NutritionWeekResponse {
        NutritionWeekResponse(
            weekNumber: expectedWeek,
            weekSummary: week.weekSummary.nTrimmedOr("Week \(expectedWeek) nutrition plan."),
            phaseFocus: week.phaseFocus.nTrimmedOr("Week \(expectedWeek) — phase progression."),
            coachNotes: week.coachNotes.nTrimmedOr("Expert panel notes for this week."),
            dailyCaloriesTraining: max(1000, week.dailyCaloriesTraining),
            dailyCaloriesRest: max(1000, week.dailyCaloriesRest),
            dailyProteinG: max(60, week.dailyProteinG),
            dailyCarbsGTraining: max(30, week.dailyCarbsGTraining),
            dailyCarbsGRest: max(30, week.dailyCarbsGRest),
            dailyFatG: max(20, week.dailyFatG),
            trainingDay: sanitizeTemplate(week.trainingDay, defaultLabel: "Training Day"),
            restDay: sanitizeTemplate(week.restDay, defaultLabel: "Rest Day"),
            weeklyGrocery: week.weeklyGrocery.map { sanitizeCategory($0) }
        )
    }

    private func sanitizeTemplate(_ template: DailyNutritionTemplate, defaultLabel: String) -> DailyNutritionTemplate {
        DailyNutritionTemplate(
            label: template.label.nTrimmedOr(defaultLabel),
            totalCalories: max(800, template.totalCalories),
            totalProteinG: max(50, template.totalProteinG),
            totalCarbsG: max(20, template.totalCarbsG),
            totalFatG: max(15, template.totalFatG),
            meals: template.meals.map { meal in
                MealSlotResponse(
                    mealName: meal.mealName.nTrimmedOr("Meal"),
                    primaryOption: meal.primaryOption.nTrimmedOr("Primary meal option pending."),
                    substitutions: meal.substitutions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    approxCalories: max(0, meal.approxCalories),
                    approxProteinG: max(0, meal.approxProteinG),
                    approxCarbsG: max(0, meal.approxCarbsG),
                    approxFatG: max(0, meal.approxFatG),
                    timingNote: meal.timingNote.nTrimmedOr("Timing note pending.")
                )
            }
        )
    }

    private func sanitizeCategory(_ category: NutritionGroceryCategory) -> NutritionGroceryCategory {
        NutritionGroceryCategory(
            category: category.category.nTrimmedOr("Other"),
            items: category.items.map { item in
                NutritionGroceryItem(
                    name: item.name.nTrimmedOr("Item"),
                    quantity: item.quantity.nTrimmedOr("as needed"),
                    substitutions: item.substitutions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    rationale: item.rationale.nTrimmedOr("Supports plan macros.")
                )
            }
        )
    }

    // MARK: - Validation

    private func validateNutritionProgram(_ program: NutritionProgramResponse) -> [String] {
        var issues: [String] = []
        if program.programName.count < 3 {
            issues.append("programName is too short.")
        }
        if program.programSummary.count < 20 {
            issues.append("programSummary should be at least one full sentence.")
        }
        issues.append(contentsOf: validateNutritionWeek(program.weekOne, expectedWeek: 1))
        return issues
    }

    private func validateNutritionWeek(_ week: NutritionWeekResponse, expectedWeek: Int) -> [String] {
        var issues: [String] = []
        if week.weekNumber != expectedWeek {
            issues.append("weekNumber must be \(expectedWeek).")
        }
        if week.coachNotes.count < 30 {
            issues.append("coachNotes too short — at least 2 sentences from the expert panel required.")
        }
        issues.append(contentsOf: validateTemplate(week.trainingDay, expectedLabel: "Training"))
        issues.append(contentsOf: validateTemplate(week.restDay, expectedLabel: "Rest"))
        issues.append(contentsOf: validateTemplateArithmetic(
            week.trainingDay,
            expectedLabel: "Training",
            declaredCalories: week.dailyCaloriesTraining,
            declaredProteinG: week.dailyProteinG
        ))
        issues.append(contentsOf: validateTemplateArithmetic(
            week.restDay,
            expectedLabel: "Rest",
            declaredCalories: week.dailyCaloriesRest,
            declaredProteinG: week.dailyProteinG
        ))

        if week.weeklyGrocery.count < 3 {
            issues.append("weeklyGrocery must include at least 3 categories (e.g., Proteins, Carbs, Produce).")
        }

        let groceryItemCount = week.weeklyGrocery.reduce(0) { $0 + $1.items.count }
        if groceryItemCount < 8 {
            issues.append("weeklyGrocery has too few items to cover 7 days of meals.")
        }

        return issues
    }

    private func validateTemplate(_ template: DailyNutritionTemplate, expectedLabel: String) -> [String] {
        var issues: [String] = []
        if !template.label.localizedCaseInsensitiveContains(expectedLabel) {
            issues.append("Daily template label should contain '\(expectedLabel)'.")
        }
        if template.meals.count != 4 {
            issues.append("\(expectedLabel) template must have exactly 4 meals (Breakfast, Lunch, Dinner, Snack).")
        }
        let expectedNames = ["Breakfast", "Lunch", "Dinner", "Snack"]
        let actualNames = template.meals.map { $0.mealName }
        for name in expectedNames where !actualNames.contains(where: { $0.localizedCaseInsensitiveContains(name) }) {
            issues.append("\(expectedLabel) template missing \(name).")
        }
        for meal in template.meals {
            if meal.primaryOption.count < 10 {
                issues.append("\(expectedLabel) \(meal.mealName) primaryOption is too short.")
            }
            if meal.timingNote.count < 10 {
                issues.append("\(expectedLabel) \(meal.mealName) timingNote is too short.")
            }
        }
        return issues
    }

    /// Numeric coherence checks backing the prompt's stated quality bar — a week whose
    /// declared totals, meal sums, and 4/4/9 energy math contradict each other passes
    /// string-level validation but delivers self-contradictory coaching.
    private func validateTemplateArithmetic(
        _ template: DailyNutritionTemplate,
        expectedLabel: String,
        declaredCalories: Int,
        declaredProteinG: Int
    ) -> [String] {
        var issues: [String] = []

        func deviates(_ actual: Int, from expected: Int, by tolerance: Double) -> Bool {
            guard expected > 0 else { return false }
            return abs(Double(actual - expected)) > Double(expected) * tolerance
        }

        if deviates(template.totalCalories, from: declaredCalories, by: 0.10) {
            issues.append("\(expectedLabel) template totalCalories (\(template.totalCalories)) deviates more than 10% from the declared daily calories (\(declaredCalories)). Align them.")
        }
        if deviates(template.totalProteinG, from: declaredProteinG, by: 0.10) {
            issues.append("\(expectedLabel) template totalProteinG (\(template.totalProteinG)) deviates more than 10% from the declared daily protein (\(declaredProteinG)g). Align them.")
        }

        let macroKcal = template.totalProteinG * 4 + template.totalCarbsG * 4 + template.totalFatG * 9
        if deviates(macroKcal, from: template.totalCalories, by: 0.15) {
            issues.append("\(expectedLabel) template macros compute to ~\(macroKcal) kcal (4/4/9) but totalCalories is \(template.totalCalories). Make the macros and calories consistent.")
        }

        if !template.meals.isEmpty {
            let mealCalories = template.meals.reduce(0) { $0 + $1.approxCalories }
            let mealProtein = template.meals.reduce(0) { $0 + $1.approxProteinG }
            if deviates(mealCalories, from: template.totalCalories, by: 0.12) {
                issues.append("\(expectedLabel) meals sum to ~\(mealCalories) kcal but the template declares \(template.totalCalories). Scale meal portions to match the daily total.")
            }
            if deviates(mealProtein, from: template.totalProteinG, by: 0.12) {
                issues.append("\(expectedLabel) meals sum to ~\(mealProtein)g protein but the template declares \(template.totalProteinG)g. Rebalance per-meal protein.")
            }
        }

        return issues
    }

    // MARK: - Source Labels

    private func nWithSourceLabel(_ text: String, sourceLabel: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = nStripSourceLabel(from: cleaned)
        if let source = GeneratedContentSource.detect(in: sourceLabel) {
            return source.prefixing(base)
        }
        return "\(sourceLabel) \(base)"
    }

    private func nStripSourceLabel(from text: String) -> String {
        GeneratedContentSource.strip(from: text)
    }

    private func labeledNutritionProgram(_ program: NutritionProgramResponse, sourceLabel: String) -> NutritionProgramResponse {
        NutritionProgramResponse(
            programName: program.programName,
            programSummary: nWithSourceLabel(program.programSummary, sourceLabel: sourceLabel),
            proteinCoverageNote: program.proteinCoverageNote,
            weekOne: labeledNutritionWeek(program.weekOne, sourceLabel: sourceLabel)
        )
    }

    private func labeledNutritionWeek(_ week: NutritionWeekResponse, sourceLabel: String) -> NutritionWeekResponse {
        NutritionWeekResponse(
            weekNumber: week.weekNumber,
            weekSummary: nWithSourceLabel(week.weekSummary, sourceLabel: sourceLabel),
            phaseFocus: week.phaseFocus,
            coachNotes: week.coachNotes,
            dailyCaloriesTraining: week.dailyCaloriesTraining,
            dailyCaloriesRest: week.dailyCaloriesRest,
            dailyProteinG: week.dailyProteinG,
            dailyCarbsGTraining: week.dailyCarbsGTraining,
            dailyCarbsGRest: week.dailyCarbsGRest,
            dailyFatG: week.dailyFatG,
            trainingDay: week.trainingDay,
            restDay: week.restDay,
            weeklyGrocery: week.weeklyGrocery
        )
    }

    // MARK: - Context

    private func nutritionAnalysisContext(from analysis: BodyAnalysisResult) -> String {
        let priority = analysis.priorityMuscles.joined(separator: ", ")
        let dietRecs = analysis.dietRecommendations.joined(separator: " | ")
        let regions: String
        if analysis.regionBreakdown.isEmpty {
            regions = "(none provided)"
        } else {
            regions = analysis.regionBreakdown
                .map { region -> String in
                    let priorityPart = region.priority.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " [priority: \(region.priority)]"
                    return "• \(region.region)\(priorityPart): \(region.assessment)"
                }
                .joined(separator: "\n")
        }
        return """
        Overall assessment:
        \(analysis.overallAssessment.nTrimmedOr("(not provided)"))

        Top leverage change: \(analysis.topLeverageChange.nTrimmedOr("(not provided)"))

        Priority muscles (drive protein prioritization and leucine timing): \(priority.isEmpty ? "(none)" : priority)

        Region breakdown:
        \(regions)

        Postural / injury notes (may inform anti-inflammatory food choices): \(analysis.posturalNotes.nTrimmedOr("(none)")) / \(analysis.injuryRiskNotes.nTrimmedOr("(none)"))

        Metabolic health notes (schedule, insulin, glycemic — drive carb timing and fiber):
        \(analysis.metabolicHealthNotes.nTrimmedOr("(none)"))

        Psychological / behavioral insights (adherence + sustainability): \(analysis.psychologicalInsights.nTrimmedOr("(none)"))

        Estimated body fat: \(analysis.estimatedBodyFat.nTrimmedOr("(not provided)"))

        Diet recommendations from analysis (concrete guidance — must be honored):
        \(dietRecs.isEmpty ? "(none)" : dietRecs)
        """
    }

    private func macroTargetLine(from macros: AnalysisMacroTargets?) -> String {
        guard let m = macros else {
            // No analysis macros — fall back to the user's configured targets rather
            // than a hardcoded stranger's numbers.
            let resolved = MacroTargetResolver.resolve(from: nil)
            return "calories \(resolved.calories) kcal, protein \(Int(resolved.proteinG))g, carbs \(Int(resolved.carbsG))g, fat \(Int(resolved.fatG))g (from app settings — analysis did not provide macros)"
        }
        return "calories \(m.calories) kcal, protein \(Int(m.proteinG))g, carbs \(Int(m.carbsG))g, fat \(Int(m.fatG))g"
    }

    // MARK: - Fallback

    private func buildFallbackNutritionProgram(
        from analysis: BodyAnalysisResult,
        diagnostic: String
    ) -> NutritionProgramResponse {
        let weekOne = buildFallbackNutritionWeek(weekNumber: 1, from: analysis, diagnostic: diagnostic)
        let diagnosticLine = diagnostic.isEmpty ? "" : "\n\nWhy fallback fired: \(nTruncate(diagnostic))"
        return NutritionProgramResponse(
            programName: "Fallback Nutrition Protocol",
            programSummary: nWithSourceLabel(
                "Fallback protocol — the AI call did not complete cleanly.\(diagnosticLine)",
                sourceLabel: nutritionFallbackSourceLabel
            ),
            proteinCoverageNote: "Protein floor set to ~1g per lb bodyweight as a safe default.",
            weekOne: weekOne
        )
    }

    private func buildFallbackNutritionWeek(
        weekNumber: Int,
        from analysis: BodyAnalysisResult,
        diagnostic: String
    ) -> NutritionWeekResponse {
        // Resolve via MacroTargetResolver so the fallback honors the user's configured
        // targets (or clamped analysis macros) instead of hardcoded numbers.
        let resolved = MacroTargetResolver.resolve(from: analysis)
        let protein = Int(resolved.proteinG)
        let carbsTrain = Int(resolved.carbsG)
        let carbsRest = max(80, Int(resolved.carbsG * 0.75))
        let fatTrain = Int(resolved.fatG)
        let fatRest = fatTrain + 10

        // Declare calories from 4/4/9 of the macros so totals, meals, and energy
        // math agree — a fallback that contradicts its own numbers reads as broken.
        let trainCalories = protein * 4 + carbsTrain * 4 + fatTrain * 9
        let restCalories = protein * 4 + carbsRest * 4 + fatRest * 9

        let training = DailyNutritionTemplate(
            label: "Training Day",
            totalCalories: trainCalories,
            totalProteinG: protein,
            totalCarbsG: carbsTrain,
            totalFatG: fatTrain,
            meals: fallbackMeals(carbsHigh: true, proteinG: protein, carbsG: carbsTrain, fatG: fatTrain)
        )
        let rest = DailyNutritionTemplate(
            label: "Rest Day",
            totalCalories: restCalories,
            totalProteinG: protein,
            totalCarbsG: carbsRest,
            totalFatG: fatRest,
            meals: fallbackMeals(carbsHigh: false, proteinG: protein, carbsG: carbsRest, fatG: fatRest)
        )
        let grocery = fallbackGrocery()
        let diagnosticLine = diagnostic.isEmpty ? "" : "\n\nWhy fallback fired: \(nTruncate(diagnostic))"

        return NutritionWeekResponse(
            weekNumber: weekNumber,
            weekSummary: nWithSourceLabel(
                "Week \(weekNumber) fallback protocol — safe macro defaults, no body-analysis personalization.\(diagnosticLine)",
                sourceLabel: nutritionFallbackSourceLabel
            ),
            phaseFocus: "Week \(weekNumber) — Fallback defaults",
            coachNotes: "This week is a safe default protocol scaled to your macro targets. The AI generation did not complete — regenerate once you've resolved the issue shown in the week summary.",
            dailyCaloriesTraining: trainCalories,
            dailyCaloriesRest: restCalories,
            dailyProteinG: protein,
            dailyCarbsGTraining: carbsTrain,
            dailyCarbsGRest: carbsRest,
            dailyFatG: fatTrain,
            trainingDay: training,
            restDay: rest,
            weeklyGrocery: grocery
        )
    }

    /// Distributes the day's macro targets across the four meal slots and computes
    /// each meal's calories from 4/4/9, so meal labels always sum to the daily totals.
    private func fallbackMeals(carbsHigh: Bool, proteinG: Int, carbsG: Int, fatG: Int) -> [MealSlotResponse] {
        let carbLabel = carbsHigh ? "1 cup cooked rice / 1 medium potato" : "1/2 cup cooked rice / small potato"

        struct Slot {
            let name: String
            let proteinShare: Double
            let carbShare: Double
            let fatShare: Double
            let primary: String
            let subs: [String]
            let timing: String
        }

        // Shares per macro each sum to 1.0.
        let slots: [Slot] = [
            Slot(
                name: "Breakfast", proteinShare: 0.25, carbShare: 0.30, fatShare: 0.20,
                primary: "Eggs + egg whites + oats + berries (scale portions to the macros below)",
                subs: ["Greek yogurt + oats + whey", "Protein smoothie + banana + PB"],
                timing: "Within 60 min of waking. Anchors protein + carbs for the day."
            ),
            Slot(
                name: "Lunch", proteinShare: 0.30, carbShare: 0.30, fatShare: 0.20,
                primary: "Grilled chicken breast + \(carbLabel) + mixed vegetables",
                subs: ["Ground turkey bowl", "Tuna + pita + salad"],
                timing: carbsHigh ? "4-5 hrs before training." : "Mid-day anchor — leaner carbs."
            ),
            Slot(
                name: "Dinner", proteinShare: 0.25, carbShare: 0.25, fatShare: 0.40,
                primary: "Lean beef or salmon + \(carbLabel) + vegetables + olive oil",
                subs: ["Shrimp stir fry", "Turkey chili"],
                timing: "3-4 hrs before sleep. Favor slower carbs on rest days."
            ),
            Slot(
                name: "Snack", proteinShare: 0.20, carbShare: 0.15, fatShare: 0.20,
                primary: "Greek yogurt + whey + handful of nuts",
                subs: ["Cottage cheese + fruit", "Protein shake + almonds"],
                timing: carbsHigh ? "Post-workout or late evening." : "Before sleep — slow protein."
            )
        ]

        return slots.map { slot in
            let p = Int((Double(proteinG) * slot.proteinShare).rounded())
            let c = Int((Double(carbsG) * slot.carbShare).rounded())
            let f = Int((Double(fatG) * slot.fatShare).rounded())
            return MealSlotResponse(
                mealName: slot.name,
                primaryOption: slot.primary,
                substitutions: slot.subs,
                approxCalories: p * 4 + c * 4 + f * 9,
                approxProteinG: p,
                approxCarbsG: c,
                approxFatG: f,
                timingNote: slot.timing
            )
        }
    }

    private func fallbackGrocery() -> [NutritionGroceryCategory] {
        [
            NutritionGroceryCategory(
                category: "Proteins",
                items: [
                    NutritionGroceryItem(name: "Chicken breast", quantity: "3 lb", substitutions: ["Turkey breast", "Lean pork"], rationale: "Primary lean protein."),
                    NutritionGroceryItem(name: "Lean ground beef / salmon", quantity: "2 lb", substitutions: ["Shrimp", "Cod"], rationale: "Dinner rotation — iron and omega-3s."),
                    NutritionGroceryItem(name: "Eggs", quantity: "2 dozen", substitutions: ["Egg whites cartons"], rationale: "Fast breakfast protein."),
                    NutritionGroceryItem(name: "Greek yogurt (nonfat)", quantity: "8 cups", substitutions: ["Skyr", "Cottage cheese"], rationale: "Leucine-dense snack protein."),
                    NutritionGroceryItem(name: "Whey protein", quantity: "7 scoops", substitutions: ["Casein blend"], rationale: "Shake flexibility for busy days.")
                ]
            ),
            NutritionGroceryCategory(
                category: "Carbs & Grains",
                items: [
                    NutritionGroceryItem(name: "Jasmine or basmati rice", quantity: "6 cups dry", substitutions: ["Potatoes", "Quinoa"], rationale: "Training-day carb anchor."),
                    NutritionGroceryItem(name: "Rolled oats", quantity: "4 cups dry", substitutions: ["Whole-grain cereal"], rationale: "Breakfast base."),
                    NutritionGroceryItem(name: "Potatoes", quantity: "3 lb", substitutions: ["Sweet potatoes"], rationale: "Rotate with rice.")
                ]
            ),
            NutritionGroceryCategory(
                category: "Produce",
                items: [
                    NutritionGroceryItem(name: "Frozen mixed vegetables", quantity: "3 large bags", substitutions: ["Fresh broccoli / spinach"], rationale: "Fiber + micronutrients."),
                    NutritionGroceryItem(name: "Berries", quantity: "3 bags frozen", substitutions: ["Fresh berries"], rationale: "Antioxidants + breakfast topping."),
                    NutritionGroceryItem(name: "Bananas", quantity: "1 bunch", substitutions: ["Apples"], rationale: "Fast carbs pre/post training.")
                ]
            ),
            NutritionGroceryCategory(
                category: "Fats & Extras",
                items: [
                    NutritionGroceryItem(name: "Olive oil", quantity: "1 bottle", substitutions: ["Avocado oil"], rationale: "Cooking + drizzle fat."),
                    NutritionGroceryItem(name: "Nuts (almonds / walnuts)", quantity: "1 lb", substitutions: ["Nut butter"], rationale: "Snack fat + micronutrients."),
                    NutritionGroceryItem(name: "Avocados", quantity: "4-6", substitutions: ["Nut butter"], rationale: "Healthy fat rotation.")
                ]
            )
        ]
    }

    private func nTruncate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 400 { return trimmed }
        return String(trimmed.prefix(400)) + "…"
    }
}

private extension String {
    func nTrimmedOr(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
