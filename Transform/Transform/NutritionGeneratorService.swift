import Foundation

// MARK: - Shift-Work Nutrition Modes

enum ShiftWorkNutritionMode: String, CaseIterable, Identifiable {
    case normal = "normal"
    case nightShift = "night_shift"
    case sleepRestricted = "sleep_restricted"
    case postShiftRecovery = "post_shift_recovery"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal Day"
        case .nightShift: return "Night Shift"
        case .sleepRestricted: return "Sleep Restricted"
        case .postShiftRecovery: return "Post-Shift Recovery"
        }
    }

    var mealTimingGuidance: String {
        switch self {
        case .normal:
            return "Standard waking schedule. Anchor meals around training — pre-workout carbs/protein 2-3 hours before, post-workout protein within 60 minutes."
        case .nightShift:
            return "Night-shift schedule. Anchor protein meals around waking, pre-shift, mid-shift, and post-shift. Avoid high glycemic-index meals in the final 2 hours before planned sleep. Batch-prep all shift meals. Keep an emergency protein option (shake, tuna packet) in your bag."
        case .sleepRestricted:
            return "Sleep-restricted day. Front-load protein and slow carbs at the first meal. Avoid large meals before any recovery nap. Prioritize hydration and electrolytes. No aggressive deficit — keep calories near maintenance. Caffeine cut-off 6 hours before planned sleep."
        case .postShiftRecovery:
            return "Post-shift recovery day. Prioritize hydration, protein within 60 min of waking, moderate carbs, anti-inflammatory food choices (fatty fish, berries, leafy greens). No training-day carb loading. Keep meals easy to digest and batch-prep friendly."
        }
    }
}

// MARK: - Nutrition Program Response Models

nonisolated struct NutritionProgramResponse: Codable {
    let programName: String
    let programSummary: String
    let proteinCoverageNote: String
    let weekOne: NutritionWeekResponse
}

nonisolated struct NutritionWeekResponse: Codable, Identifiable {
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

nonisolated struct DailyNutritionTemplate: Codable {
    let label: String
    let totalCalories: Int
    let totalProteinG: Int
    let totalCarbsG: Int
    let totalFatG: Int
    let meals: [MealSlotResponse]
}

nonisolated struct MealSlotResponse: Codable, Identifiable {
    let mealName: String
    let primaryOption: String
    let substitutions: [String]
    let approxCalories: Int
    let approxProteinG: Int
    let approxCarbsG: Int
    let approxFatG: Int
    let timingNote: String

    let id: UUID

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mealName = try container.decode(String.self, forKey: .mealName)
        primaryOption = (try? container.decode(String.self, forKey: .primaryOption)) ?? ""
        substitutions = (try? container.decode([String].self, forKey: .substitutions)) ?? []
        approxCalories = (try? container.decode(Int.self, forKey: .approxCalories)) ?? 0
        approxProteinG = (try? container.decode(Int.self, forKey: .approxProteinG)) ?? 0
        approxCarbsG = (try? container.decode(Int.self, forKey: .approxCarbsG)) ?? 0
        approxFatG = (try? container.decode(Int.self, forKey: .approxFatG)) ?? 0
        timingNote = (try? container.decode(String.self, forKey: .timingNote)) ?? ""
        id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mealName, forKey: .mealName)
        try container.encode(primaryOption, forKey: .primaryOption)
        try container.encode(substitutions, forKey: .substitutions)
        try container.encode(approxCalories, forKey: .approxCalories)
        try container.encode(approxProteinG, forKey: .approxProteinG)
        try container.encode(approxCarbsG, forKey: .approxCarbsG)
        try container.encode(approxFatG, forKey: .approxFatG)
        try container.encode(timingNote, forKey: .timingNote)
    }

    private enum CodingKeys: String, CodingKey {
        case mealName, primaryOption, substitutions
        case approxCalories, approxProteinG, approxCarbsG, approxFatG, timingNote
    }
}

nonisolated struct NutritionGroceryCategory: Codable, Identifiable {
    let category: String
    let items: [NutritionGroceryItem]

    let id: UUID

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(String.self, forKey: .category)
        items = (try? container.decode([NutritionGroceryItem].self, forKey: .items)) ?? []
        id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(items, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey {
        case category, items
    }
}

nonisolated struct NutritionGroceryItem: Codable, Identifiable {
    let name: String
    let quantity: String
    let substitutions: [String]
    let rationale: String

    let id: UUID

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        quantity = (try? container.decode(String.self, forKey: .quantity)) ?? ""
        substitutions = (try? container.decode([String].self, forKey: .substitutions)) ?? []
        rationale = (try? container.decode(String.self, forKey: .rationale)) ?? ""
        id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(substitutions, forKey: .substitutions)
        try container.encode(rationale, forKey: .rationale)
    }

    private enum CodingKeys: String, CodingKey {
        case name, quantity, substitutions, rationale
    }
}

// MARK: - Nutrition Generator Service

extension ClaudeService {

    private var nutritionGenerationAttempts: Int { 3 }
    private var nutritionAISourceLabel: String { "[AI Coach]" }
    private var nutritionFallbackSourceLabel: String { "[Recovery Engine]" }
    private var nutritionProgramToolName: String { "emit_nutrition_program" }
    private var nutritionWeekToolName: String { "emit_nutrition_week" }

    // MARK: - Generate Nutrition Week 1

    func generateNutritionWeekOne(
        from analysisResult: BodyAnalysisResult,
        adherenceMetrics: NutritionAdherenceMetrics? = nil,
        shiftWorkMode: ShiftWorkNutritionMode = .normal
    ) async throws -> NutritionProgramResponse {
        let context = nutritionAnalysisContext(from: analysisResult)
        let macroLine = macroTargetLine(from: analysisResult.macroTargets)
        let config = nutritionGenerationConfig
        let toolSchema = nutritionProgramToolSchema()

        let useAdherenceFirst = adherenceMetrics?.isAdherenceFirst == true
        let systemPrompt = useAdherenceFirst
            ? nutritionAdherenceFocusedSystemPrompt()
            : nutritionWeekOneSystemPrompt()
        let adherenceBlock = adherenceContextBlock(from: adherenceMetrics)
        let shiftBlock = shiftWorkContextBlock(mode: shiftWorkMode)
        let userPrompt = useAdherenceFirst
            ? nutritionAdherenceFocusedUserPrompt(context: context, macroLine: macroLine, adherenceBlock: adherenceBlock, shiftBlock: shiftBlock)
            : nutritionWeekOneUserPrompt(context: context, macroLine: macroLine, adherenceBlock: adherenceBlock, shiftBlock: shiftBlock)

        var requestBody = nutritionStructuredRequestBody(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            toolName: nutritionProgramToolName,
            toolSchema: toolSchema
        )

        var lastIssues: [String] = []

        for attempt in 1...nutritionGenerationAttempts {
            try Task.checkCancellation()
            do {
                let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                    body: requestBody,
                    toolName: nutritionProgramToolName,
                    timeout: config.timeout
                )
                let decoded = try decodeNutritionPayload(NutritionProgramResponse.self, from: jsonString)
                let cleaned = sanitizeNutritionProgram(decoded)
                let issues = validateNutritionProgram(cleaned, macroTargets: analysisResult.macroTargets)
                if issues.isEmpty {
                    return labeledNutritionProgram(cleaned, sourceLabel: nutritionAISourceLabel)
                }
                lastIssues = issues
                if attempt < nutritionGenerationAttempts {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                    requestBody = nutritionCorrectionRequestBody(
                        config: config,
                        toolName: nutritionProgramToolName,
                        toolSchema: toolSchema,
                        issues: issues,
                        context: context,
                        originalUserPrompt: userPrompt
                    )
                    continue
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastIssues = ["API error (attempt \(attempt)): \(error.localizedDescription)"]
                if attempt < nutritionGenerationAttempts {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                    requestBody = nutritionCorrectionRequestBody(
                        config: config,
                        toolName: nutritionProgramToolName,
                        toolSchema: toolSchema,
                        issues: ["Previous call did not return a valid tool_use response: \(error.localizedDescription). Call the tool again with complete, valid fields."],
                        context: context,
                        originalUserPrompt: userPrompt
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
        analysisResult: BodyAnalysisResult,
        adherenceMetrics: NutritionAdherenceMetrics? = nil,
        shiftWorkMode: ShiftWorkNutritionMode = .normal
    ) async throws -> NutritionWeekResponse {
        let context = nutritionAnalysisContext(from: analysisResult)
        let macroLine = macroTargetLine(from: analysisResult.macroTargets)
        let config = nutritionGenerationConfig
        let toolSchema = nutritionWeekToolSchema(weekNumber: weekNumber)
        let systemPrompt = nutritionNextWeekSystemPrompt(weekNumber: weekNumber)
        let adherenceBlock = adherenceContextBlock(from: adherenceMetrics)
        let shiftBlock = shiftWorkContextBlock(mode: shiftWorkMode)
        let userPrompt = nutritionNextWeekUserPrompt(
            weekNumber: weekNumber,
            previousWeekJSON: previousWeekJSON,
            analysisContext: context,
            macroLine: macroLine,
            adherenceBlock: adherenceBlock,
            shiftBlock: shiftBlock
        )

        var requestBody = nutritionStructuredRequestBody(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            toolName: nutritionWeekToolName,
            toolSchema: toolSchema
        )

        var lastIssues: [String] = []

        for attempt in 1...nutritionGenerationAttempts {
            try Task.checkCancellation()
            do {
                let jsonString = try await AnthropicClient.shared.sendStructuredRequest(
                    body: requestBody,
                    toolName: nutritionWeekToolName,
                    timeout: config.timeout
                )
                let decoded = try decodeNutritionPayload(NutritionWeekResponse.self, from: jsonString)
                let cleaned = sanitizeNutritionWeek(decoded, expectedWeek: weekNumber)
                let issues = validateNutritionWeek(cleaned, expectedWeek: weekNumber, macroTargets: analysisResult.macroTargets)
                if issues.isEmpty {
                    return labeledNutritionWeek(cleaned, sourceLabel: nutritionAISourceLabel)
                }
                lastIssues = issues
                if attempt < nutritionGenerationAttempts {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                    requestBody = nutritionCorrectionRequestBody(
                        config: config,
                        toolName: nutritionWeekToolName,
                        toolSchema: toolSchema,
                        issues: issues,
                        context: context,
                        originalUserPrompt: userPrompt
                    )
                    continue
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastIssues = ["API error (attempt \(attempt)): \(error.localizedDescription)"]
                if attempt < nutritionGenerationAttempts {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                    requestBody = nutritionCorrectionRequestBody(
                        config: config,
                        toolName: nutritionWeekToolName,
                        toolSchema: toolSchema,
                        issues: ["Previous call did not return a valid tool_use response: \(error.localizedDescription). Call the tool again with complete, valid fields."],
                        context: context,
                        originalUserPrompt: userPrompt
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

    private var nutritionGenerationConfig: NutritionGenerationConfig {
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
            "input_schema": toolSchema,
            "cache_control": ["type": "ephemeral"]
        ]

        let cachedSystem: [[String: Any]] = [
            [
                "type": "text",
                "text": systemPrompt,
                "cache_control": ["type": "ephemeral"]
            ]
        ]

        return [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "system": cachedSystem,
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
        originalUserPrompt: String
    ) -> [String: Any] {
        let issueBlock = issues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        You are the same nutrition expert panel as before. Your previous call to the tool did not
        satisfy the coaching intent. Call the tool again and fix ONLY the listed issues while
        preserving everything that was already good. Do not drift from the body analysis.
        """

        let userPrompt = """
        Issues to correct (preserve everything else):
        \(issueBlock)

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
        - a metabolic-health specialist who handles shift-work circadian concerns,
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
        - timingNote on each meal: specific. "Post-shift: lean protein + fast carbs to restart
          glycogen" is good; "Eat after workout" is bad.
        - rationale on each grocery item: tie back to the analysis. "Greek yogurt — leucine density
          matches priority shoulders/chest development noted in analysis" is good; "Good source of
          protein" is bad.

        Total plan quality bar:
        - Respect the provided macro targets within ~±10% for the daily totals.
        - Training Day carbs ≈ Rest Day carbs + 20-40%.
        - Protein stays roughly constant across Training/Rest days.
        - Fat must not drop below ~40g/day (hormonal and satiety floor).
        - Weekly grocery list must be sufficient to execute BOTH templates across 7 days.
        - Keep choices practical and shift-work friendly (batch-prep friendly, quick reheats).
        - Meal calorie and protein sums must approximately match the daily template totals.

        Fiber guidance:
        - Target: ~14g per 1000 kcal, minimum 30g floor.
        - If the adherence context indicates current fiber is under 20g, ramp by ~5g/week
          from current level. Do NOT jump to 30g+ from a low baseline — it causes GI distress.

        Decision rules — include 2-3 of these in coachNotes as "if/then" contingency rules:
        - "If you miss a meal: hit 40-50g protein at the next feeding and keep calories controlled.
          Do not try to 'make up' the full missed meal later."
        - "If you are starving after a shift: eat protein + high-volume carbs first, then decide
          if you still need extra food."
        - "If sleep was under 5 hours: do not attempt an aggressive deficit that day. Hit protein
          and eat at roughly maintenance."
        - "If a shift runs long and you miss your meal prep window: use your emergency stack
          (protein shake, tuna packet, Greek yogurt)."

        Always call the emit_nutrition_program tool. Never respond with free text.
        """
    }

    private func nutritionWeekOneUserPrompt(context: String, macroLine: String, adherenceBlock: String, shiftBlock: String) -> String {
        """
        Build Week 1 of this individual's 4-week nutrition protocol. Treat the analysis below as the
        north star — every meal, every grocery item, every rationale should be traceable back to it.

        --- Body Analysis ---
        \(context)
        --- end Body Analysis ---

        Daily macro targets from analysis: \(macroLine)
        \(adherenceBlock)
        \(shiftBlock)

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

        Quality constraints:
        - Respect macro targets within ~±10% for daily totals.
        - Training Day carbs must be higher than Rest Day carbs.
        - Fat must not drop below ~40g/day.
        - Meal calorie and protein sums must approximately match daily template totals.

        Fiber guidance:
        - If adherence context indicates fiber is low, ramp by ~5g/week from previous week's
          level. Do NOT jump to high targets in a single week.

        Decision rules — include 1-2 contingency rules in coachNotes relevant to this week's phase:
        - Miss a meal → hit protein at the next feeding, do not over-compensate.
        - Short sleep → eat at maintenance, prioritize protein.
        - Missed meal prep → use emergency stack.

        Phase guidance for Week \(weekNumber):
        \(nutritionPhaseGuidance(for: weekNumber))

        Always call the emit_nutrition_week tool. Never respond with free text.
        """
    }

    private func nutritionNextWeekUserPrompt(
        weekNumber: Int,
        previousWeekJSON: String,
        analysisContext: String,
        macroLine: String,
        adherenceBlock: String,
        shiftBlock: String
    ) -> String {
        """
        Generate Week \(weekNumber) of the 4-week nutrition protocol.

        --- Body Analysis (north star — drives nutrition intent) ---
        \(analysisContext)
        --- end Body Analysis ---

        Daily macro targets from analysis: \(macroLine)
        \(adherenceBlock)
        \(shiftBlock)

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

    // MARK: - Adherence-Focused Prompts

    private func nutritionAdherenceFocusedSystemPrompt() -> String {
        """
        You are a multi-disciplinary nutrition panel designing Week 1 of a personalized 4-week
        nutrition protocol for a specific individual whose nutrition LOGGING IS POOR. The panel includes:
        - a sports dietitian (Helms / McDonald school) who sets macros and meal architecture,
        - a metabolic-health specialist who handles shift-work circadian concerns,
        - a behavioral coach who makes the plan realistic and sustainable.

        CRITICAL CONTEXT: This user's nutrition logging data is very limited. You CANNOT trust
        calorie averages or macro compliance rates because too few days were logged. The primary
        intervention is behavioral — build a system that makes consistent eating and logging possible,
        not one that optimizes macros the user won't track.

        Adherence-first hierarchy for this protocol:
        1. Consistent food logging (every meal, every day — even rough estimates)
        2. Protein floor (~1g per lb bodyweight, distributed across 4 meals)
        3. Pre-planned work/shift meals (batch-prep, low-friction options)
        4. Emergency protein options always available (shake, tuna packet, Greek yogurt)
        5. Regular weigh-ins (3-7 mornings per week)
        6. Do NOT adjust calories aggressively until 10+ valid logging days exist

        Structure:
        - Assume 5 training days, 2 rest days per week.
        - Build TWO daily templates: Training Day and Rest Day.
        - Each daily template must have EXACTLY 4 meals: Breakfast, Lunch, Dinner, Snack.
        - Keep meals SIMPLE, batch-prep friendly, and repeatable. Templates beat variety when
          adherence is the bottleneck.
        - Each meal should be dead-simple to log (clear portions, countable items).
        - timingNote should focus on WHEN and HOW to prep/pack, not complex periodization.
        - Weekly grocery list: simple, minimal variety, high-protein staples.

        Voice:
        - Be direct about why this is an adherence-focused plan, not a performance-optimized one.
        - coachNotes should explain: "We are starting with logging consistency and protein because
          that is the current bottleneck. Advanced macro adjustments come after tracking is reliable."
        - No sugarcoating, but no shaming either.

        Total plan quality bar:
        - Respect the provided macro targets within ~±15% for daily totals (wider tolerance for
          adherence-first plans).
        - Protein stays roughly constant across Training/Rest days.
        - Fat must not drop below ~40g/day (hormonal and satiety floor).
        - Keep choices practical: fewer unique ingredients, more repeatable meals.
        - Meal calorie and protein sums must approximately match the daily template totals.

        Fiber guidance:
        - If the adherence context shows low fiber (<20g), do NOT set a high fiber target yet.
          Start with current level + 5g and ramp weekly. GI distress kills adherence.

        Decision rules — include 2-3 of these in coachNotes as simple "if/then" contingency rules:
        - "If you miss a meal: hit protein at the next feeding. Do not try to make up the full
          meal later."
        - "If starving after a shift: eat protein + volume first, then reassess."
        - "If sleep was under 5 hours: hit protein and eat at roughly maintenance."
        - "If you miss meal prep: use your emergency stack (shake, tuna packet, yogurt)."

        Always call the emit_nutrition_program tool. Never respond with free text.
        """
    }

    private func nutritionAdherenceFocusedUserPrompt(context: String, macroLine: String, adherenceBlock: String, shiftBlock: String) -> String {
        """
        Build Week 1 of this individual's 4-week nutrition protocol. This person's nutrition logging
        is very limited, so this must be an ADHERENCE-FIRST plan — simple, repeatable, easy to log.

        --- Body Analysis ---
        \(context)
        --- end Body Analysis ---

        Daily macro targets from analysis: \(macroLine)
        \(adherenceBlock)
        \(shiftBlock)

        Requirements:
        - Name the program to reflect the adherence-first approach (e.g., "Adherence Foundation Protocol").
        - programSummary: ONE sentence explaining this is an adherence-focused protocol because
          nutrition logging is the current bottleneck.
        - proteinCoverageNote: ONE sentence on hitting the protein floor with simple, repeatable meals.
        - weekOne.phaseFocus: "Week 1 — Build logging habit and protein floor"
        - weekOne.coachNotes: 2-3 sentences explaining WHY this plan is simpler than a full macro
          protocol and what the user needs to do before earning more advanced adjustments.
        - Training Day and Rest Day templates: simple, batch-prep meals. Fewer unique ingredients.
        - Weekly grocery list: minimal, high-protein staples.

        Call the emit_nutrition_program tool with your answer.
        """
    }

    private func adherenceContextBlock(from metrics: NutritionAdherenceMetrics?) -> String {
        guard let m = metrics else { return "" }
        var lines: [String] = [
            "--- Nutrition Adherence Context ---",
            "Data quality: \(m.dataQuality.rawValue) (\(m.loggedDays) logged, \(m.validDays) valid of \(m.lookbackDays) days, \(Int((m.loggedDayRatio * 100).rounded()))%)"
        ]
        if m.incompleteDays > 0 {
            lines.append("Incomplete days detected: \(m.incompleteDays) days with <1000 kcal or <2 meals — likely missing meals.")
        }
        if let avg = m.averageCalories { lines.append("Average calories (valid days only): \(avg) kcal") }
        if let rate = m.calorieHitRate { lines.append("Calorie hit rate (within ±10%): \(Int((rate * 100).rounded()))%") }
        if let avg = m.averageProteinG { lines.append("Average protein (valid days only): \(Int(avg.rounded()))g") }
        if let rate = m.proteinHitRate { lines.append("Protein hit rate (≥90% target): \(Int((rate * 100).rounded()))%") }
        if let fiber = m.averageFiberG {
            lines.append("Estimated average fiber: ~\(Int(fiber.rounded()))g/day")
            if fiber < 20 {
                lines.append("Fiber is low — ramp gradually (+5g/week) to avoid GI distress. Do NOT jump straight to 30g+.")
            }
        }
        if let change = m.weeklyWeightChangeLbs {
            let direction = m.weightTrendDirection.rawValue.lowercased()
            lines.append("Weight trend: \(direction), ~\(String(format: "%.1f", abs(change))) lb/week")
        }
        if let bottleneck = m.primaryBottleneck { lines.append("Primary bottleneck: \(bottleneck)") }
        lines.append("--- end Adherence Context ---")
        return "\n" + lines.joined(separator: "\n")
    }

    private func shiftWorkContextBlock(mode: ShiftWorkNutritionMode) -> String {
        guard mode != .normal else { return "" }
        return """

        --- Current Schedule Mode ---
        Mode: \(mode.displayName)
        Meal timing guidance: \(mode.mealTimingGuidance)
        Adapt all meal timingNotes to reflect this schedule mode.
        --- end Schedule Mode ---
        """
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

    nonisolated private func decodeNutritionPayload<T: Decodable>(_ type: T.Type, from responseText: String) throws -> T {
        // Brace-match the JSON object rather than blindly stripping ``` fences,
        // which can corrupt a backtick sequence inside a string value.
        let cleaned = ClaudeService.extractJSON(from: responseText)

        guard let data = cleaned.data(using: .utf8) else {
            throw ClaudeError.parseError("Could not encode nutrition response as data.")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let short = String(String(describing: error).prefix(180))
            throw ClaudeError.parseError("Could not decode nutrition response. \(short)")
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

    private func validateNutritionProgram(_ program: NutritionProgramResponse, macroTargets: AnalysisMacroTargets?) -> [String] {
        var issues: [String] = []
        if program.programName.count < 3 {
            issues.append("programName is too short.")
        }
        if program.programSummary.count < 20 {
            issues.append("programSummary should be at least one full sentence.")
        }
        issues.append(contentsOf: validateNutritionWeek(program.weekOne, expectedWeek: 1, macroTargets: macroTargets))
        return issues
    }

    private func validateNutritionWeek(_ week: NutritionWeekResponse, expectedWeek: Int, macroTargets: AnalysisMacroTargets?) -> [String] {
        var issues: [String] = []
        if week.weekNumber != expectedWeek {
            issues.append("weekNumber must be \(expectedWeek).")
        }
        if week.coachNotes.count < 30 {
            issues.append("coachNotes too short — at least 2 sentences from the expert panel required.")
        }
        issues.append(contentsOf: validateTemplate(week.trainingDay, expectedLabel: "Training"))
        issues.append(contentsOf: validateTemplate(week.restDay, expectedLabel: "Rest"))

        if week.weeklyGrocery.count < 3 {
            issues.append("weeklyGrocery must include at least 3 categories (e.g., Proteins, Carbs, Produce).")
        }

        let groceryItemCount = week.weeklyGrocery.reduce(0) { $0 + $1.items.count }
        if groceryItemCount < 8 {
            issues.append("weeklyGrocery has too few items to cover 7 days of meals.")
        }

        // Nutrition-specific validators
        if let targets = macroTargets {
            let calTarget = targets.calories
            let proTarget = Int(targets.proteinG.rounded())
            let fatTarget = Int(targets.fatG.rounded())

            let trainCalDrift = abs(week.dailyCaloriesTraining - calTarget)
            if trainCalDrift > Int(Double(calTarget) * 0.20) {
                issues.append("Training-day calories (\(week.dailyCaloriesTraining)) are >20% off target (\(calTarget)).")
            }

            let restCalDrift = abs(week.dailyCaloriesRest - calTarget)
            if restCalDrift > Int(Double(calTarget) * 0.25) {
                issues.append("Rest-day calories (\(week.dailyCaloriesRest)) are >25% off target (\(calTarget)).")
            }

            let proDrift = abs(week.dailyProteinG - proTarget)
            if proDrift > Int(Double(proTarget) * 0.15) {
                issues.append("Daily protein (\(week.dailyProteinG)g) is >15% off target (\(proTarget)g).")
            }

            let fatFloor = max(40, Int(Double(fatTarget) * 0.60))
            if week.dailyFatG < fatFloor {
                issues.append("Daily fat (\(week.dailyFatG)g) is below safe floor (\(fatFloor)g) — hormonal and satiety concerns.")
            }

            if week.dailyCarbsGTraining <= week.dailyCarbsGRest {
                issues.append("Training-day carbs (\(week.dailyCarbsGTraining)g) should be higher than rest-day carbs (\(week.dailyCarbsGRest)g).")
            }
        }

        issues.append(contentsOf: validateTemplateMacroConsistency(week.trainingDay, weekMacros: (cal: week.dailyCaloriesTraining, pro: week.dailyProteinG), label: "Training"))
        issues.append(contentsOf: validateTemplateMacroConsistency(week.restDay, weekMacros: (cal: week.dailyCaloriesRest, pro: week.dailyProteinG), label: "Rest"))

        return issues
    }

    private func validateTemplateMacroConsistency(_ template: DailyNutritionTemplate, weekMacros: (cal: Int, pro: Int), label: String) -> [String] {
        var issues: [String] = []
        let mealCalTotal = template.meals.reduce(0) { $0 + $1.approxCalories }
        let mealProTotal = template.meals.reduce(0) { $0 + $1.approxProteinG }

        if abs(mealCalTotal - template.totalCalories) > Int(Double(template.totalCalories) * 0.15) {
            issues.append("\(label) template: meal calorie sum (\(mealCalTotal)) doesn't match totalCalories (\(template.totalCalories)) within 15%.")
        }

        if abs(mealProTotal - template.totalProteinG) > Int(Double(template.totalProteinG) * 0.15) {
            issues.append("\(label) template: meal protein sum (\(mealProTotal)g) doesn't match totalProteinG (\(template.totalProteinG)g) within 15%.")
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
        let priority = analysis.programmingPriorityAreas.joined(separator: ", ")
        let dietRecs = analysis.dietRecommendations.joined(separator: " | ")
        let inputContextSummary = analysis.inputContext?.generationSummary
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentSleepContext = UserDefaults.standard
            .string(forKey: AppSettingsKeys.derivedSleepTrendSummary)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

        User profile, check-in, and progress context:
        \(inputContextSummary.isEmpty ? "(none saved with this analysis)" : inputContextSummary)

        Current sleep context from dated episode logs:
        \(currentSleepContext.isEmpty ? "(no recent sleep episodes logged)" : currentSleepContext)

        Region breakdown:
        \(regions)

        Postural / injury notes (may inform anti-inflammatory food choices): \(analysis.posturalNotes.nTrimmedOr("(none)")) / \(analysis.injuryRiskNotes.nTrimmedOr("(none)"))

        Metabolic health notes (shift-work, insulin, glycemic — drive carb timing and fiber):
        \(analysis.metabolicHealthNotes.nTrimmedOr("(none)"))

        Psychological / behavioral insights (adherence + sustainability): \(analysis.psychologicalInsights.nTrimmedOr("(none)"))

        Estimated body fat: \(analysis.estimatedBodyFat.nTrimmedOr("(not provided)"))

        Diet recommendations from analysis (concrete guidance — must be honored):
        \(dietRecs.isEmpty ? "(none)" : dietRecs)
        """
    }

    private func macroTargetLine(from macros: AnalysisMacroTargets?) -> String {
        guard let m = macros else {
            // Fall back to the user's configured targets rather than fixed numbers.
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
        let macros = analysis.macroTargets
        let calories = macros?.calories ?? 2300
        let protein = Int(macros?.proteinG ?? 200)
        let carbsTrain = Int(macros?.carbsG ?? 220)
        let carbsRest = max(80, Int((macros?.carbsG ?? 220) * 0.7))
        let fat = Int(macros?.fatG ?? 70)

        let training = DailyNutritionTemplate(
            label: "Training Day",
            totalCalories: calories,
            totalProteinG: protein,
            totalCarbsG: carbsTrain,
            totalFatG: fat,
            meals: fallbackMeals(carbsHigh: true)
        )
        let rest = DailyNutritionTemplate(
            label: "Rest Day",
            totalCalories: max(1600, calories - 200),
            totalProteinG: protein,
            totalCarbsG: carbsRest,
            totalFatG: fat + 10,
            meals: fallbackMeals(carbsHigh: false)
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
            coachNotes: "This week is a safe default protocol. The AI generation did not complete — regenerate once you've resolved the issue shown in the week summary.",
            dailyCaloriesTraining: calories,
            dailyCaloriesRest: max(1600, calories - 200),
            dailyProteinG: protein,
            dailyCarbsGTraining: carbsTrain,
            dailyCarbsGRest: carbsRest,
            dailyFatG: fat,
            trainingDay: training,
            restDay: rest,
            weeklyGrocery: grocery
        )
    }

    private func fallbackMeals(carbsHigh: Bool) -> [MealSlotResponse] {
        let carbLabel = carbsHigh ? "1 cup cooked rice / 1 medium potato" : "1/2 cup cooked rice / small potato"
        return [
            MealSlotResponse(
                mealName: "Breakfast",
                primaryOption: "3 whole eggs + 3 egg whites + 1 cup oats + berries",
                substitutions: ["Greek yogurt + oats + whey", "Protein smoothie + banana + PB"],
                approxCalories: 550, approxProteinG: 45, approxCarbsG: 60, approxFatG: 15,
                timingNote: "Within 60 min of waking. Anchors protein + carbs for the day."
            ),
            MealSlotResponse(
                mealName: "Lunch",
                primaryOption: "6 oz grilled chicken breast + \(carbLabel) + mixed vegetables",
                substitutions: ["Ground turkey bowl", "Tuna + pita + salad"],
                approxCalories: 600, approxProteinG: 55, approxCarbsG: carbsHigh ? 65 : 40, approxFatG: 12,
                timingNote: carbsHigh ? "4-5 hrs before training." : "Mid-day anchor — leaner carbs."
            ),
            MealSlotResponse(
                mealName: "Dinner",
                primaryOption: "6 oz lean beef or salmon + \(carbLabel) + vegetables + olive oil",
                substitutions: ["Shrimp stir fry", "Turkey chili"],
                approxCalories: 650, approxProteinG: 50, approxCarbsG: carbsHigh ? 55 : 35, approxFatG: 22,
                timingNote: "3-4 hrs before sleep. Favor slower carbs on rest days."
            ),
            MealSlotResponse(
                mealName: "Snack",
                primaryOption: "Greek yogurt + whey + handful of nuts",
                substitutions: ["Cottage cheese + fruit", "Protein shake + almonds"],
                approxCalories: 350, approxProteinG: 40, approxCarbsG: carbsHigh ? 25 : 15, approxFatG: 12,
                timingNote: carbsHigh ? "Post-workout or late evening." : "Before sleep — slow protein."
            )
        ]
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
                    NutritionGroceryItem(name: "Whey protein", quantity: "7 scoops", substitutions: ["Casein blend"], rationale: "Shake flexibility around shifts.")
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
