import Foundation

extension ClaudeService {
    // MARK: - Request Builders (tool_use / structured output)

    func workoutRequestContext(
        phase: String,
        weekNumber: Int,
        analysisContext: String,
        previousWeekReference: String?,
        systemPrompt: String,
        userPrompt: String
    ) -> AnthropicRequestContext {
        var metrics: [String: Int] = [
            "analysis_chars": analysisContext.count,
            "system_chars": systemPrompt.count,
            "user_chars": userPrompt.count
        ]

        if let previousWeekReference {
            metrics["previous_reference_chars"] = previousWeekReference.count
        }

        return AnthropicRequestContext(
            feature: "workout",
            phase: phase,
            weekNumber: weekNumber,
            metrics: metrics
        )
    }

    /// Model + token + timeout configuration per generation phase.
    struct GenerationConfig {
        let model: String
        let maxTokens: Int
        let timeout: TimeInterval
    }

    var weekOneConfig: GenerationConfig {
        // Week 1 is the highest-leverage planning pass, so keep Opus for deeper reasoning.
        // The latency fix comes from tighter prompt/output budgets, not from downgrading the model.
        GenerationConfig(model: Config.claudeModel, maxTokens: 6144, timeout: 240)
    }

    var nextWeekConfig: GenerationConfig {
        // Weeks 2-4 progress the Week 1 foundation — Sonnet is fast and strong.
        GenerationConfig(model: Config.claudeModelLite, maxTokens: 8192, timeout: 180)
    }

    /// Tool names that the structured-output flow uses.
    var programToolName: String { "emit_workout_program" }
    var weekToolName: String { "emit_workout_week" }

    func structuredRequestBody(
        config: GenerationConfig,
        systemPrompt: String,
        userPrompt: String,
        toolName: String,
        toolSchema: [String: Any],
        temperature: Double
    ) -> [String: Any] {
        let tool: [String: Any] = [
            "name": toolName,
            "description": "Emit the workout program in the required structured shape. Always call this tool; never respond with free text.",
            "input_schema": toolSchema
        ]

        return [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "temperature": temperature,
            "system": systemPrompt,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]
    }

    func correctionRequestBody(
        config: GenerationConfig,
        toolName: String,
        toolSchema: [String: Any],
        issues: [String],
        context: String,
        originalUserPrompt: String
    ) -> [String: Any] {
        let issueBlock = issues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let systemPrompt = """
        You are the same expert coaching panel as before. Your previous call to the tool did not
        satisfy the coaching intent. Call the tool again and fix ONLY the listed issues while
        preserving everything that was already good. Do not change the overall programming logic
        or the ties to the user's body analysis.
        """

        let userPrompt = """
        Issues to correct (preserve everything else):
        \(issueBlock)

        Original assignment (for reference):
        \(originalUserPrompt)

        Analysis context (north star — do not drift from this):
        \(context)
        """

        return structuredRequestBody(
            config: config,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            toolName: toolName,
            toolSchema: toolSchema,
            temperature: 0
        )
    }

    // MARK: - Prompts

    func weekOneSystemPrompt() -> String {
        """
        You are a multi-disciplinary coaching panel designing Week 1 of a personalized 4-week
        hypertrophy mesocycle for a specific individual. The panel includes:
        - an exercise physiologist who writes programming,
        - a physical therapist who handles postural/injury considerations,
        - a strength coach who writes the in-session coaching cues (form, progression, intent),
        - a behavioral coach who writes the Session Notes at the top of each day.

        The user's Body Analysis is the north star of this entire mesocycle. You will also be
        given a Structured Training Intent derived from that analysis and a Deterministic Weekly
        Blueprint generated from the evidence profile. Treat the Weekly Blueprint as the execution
        plan for split structure, day emphasis, exercise selection, frequency, and weekly
        priorities. Every choice you make must still be directly traceable back to the underlying
        analysis.

        Voice and style:
        - Write like a real coach talking to THIS person, not a generic app.
        - Session Notes (the `notes` field on each training day) must sound curated and personal:
          open with a one-line framing of today's intent given the analysis, then give SPECIFIC
          warm-up and mobility guidance tied to THIS day's lifts and THIS person's posture/injury
          notes. Keep session notes concise: 2-3 short sentences, ideally under 70 words total.
          No template language. No phrases like "progressive overload session."
        - Exercise notes must be 2-4 sentences of real coaching. Include (a) a form/technique cue
          for THIS movement, (b) a progression cue appropriate for Week 1 (RIR/RPE or load/rep
          intent), and (c) a "why this is here for you" sentence that references the analysis
          (e.g., the priority muscle, the postural imbalance, the leverage change). Keep exercise
          notes concise: exactly 2 short sentences, ideally under 45 words total.

        Programming constraints:
        - Exactly 7 days, dayNumber 1..7.
        - 4-6 training days, 1-3 rest days. Choose the split based on the priority muscles and
          region breakdown in the analysis — don't default.
        - Training days: 5-8 exercises. Rest days: empty exercises array.
        - 60-75 minute sessions.
        - Day theme and exercises must align (an Arms day cannot include squats; a Legs day cannot
          include bench press).
        - Follow the Weekly Blueprint exactly when deciding split structure, session emphasis,
          exercise families, and weekly priority allocation.
        - Use standardized exercise naming. Prefer canonical names such as Face Pull, Rope
          Triceps Pressdown, Cable Triceps Pressdown, Hammer Curl, Barbell Curl, Lying Leg Curl,
          Band Pull-Apart, Farmer's Walk, and Incline Smith Machine Press instead of casual
          variants or pluralized duplicates.
        - On a specific focus day, lead with a prime hypertrophy movement for that focus. Do not
          open the session with a corrective/primer movement if a true growth-focused option for
          that muscle appears later.
        - Do not treat support or scapular-control work (for example Y-raises, external-rotation
          drills, or similar corrective patterns) as the main hypertrophy slot for rear delts or
          shoulders.
        - Avoid stacking multiple near-duplicate accessories for the same small muscle unless they
          create a clearly different stimulus profile.
        - Avoid filler late-session add-ons that do not clearly serve the day's style, the
          blueprint priorities, or the injury-management goal.
        - In a shift-work recomposition block, especially on Lower days, prefer 5-6 high-value
          movements over bloated 7-8 exercise sessions unless every slot clearly earns its place.
        - Avoid back-to-back shoulder-intensive days when a lower-body or less-overlapping session
          can separate them.
        - If the analysis flags shoulder impingement risk, internal rotation, or upper-crossed
          posture, bias pressing choices toward landmine press, high-incline dumbbell press,
          cable/machine press options, or neutral-grip setups instead of defaulting to generic
          vertical pressing.
        - Rest and tempo must match exercise role. Do not lazily assign one identical rest period
          or one identical tempo to every movement in a mixed session.
        - Tempo is only for rep-based lifts where eccentric/concentric cadence matters. For
          carries, distance- or time-based work, and similar bracing/isometric drills, leave
          tempo empty instead of inventing a fake 4-part prescription.
        - Loaded carries can support trunk stiffness and grip, but they do not replace a true
          direct-core slot when the blueprint is asking for dedicated core work.
        - On broad Lower or Legs sessions that are not explicitly glute- or hamstring-focused,
          keep real quad stimulus in the plan and avoid piling up multiple glute/posterior-chain
          patterns that all solve the same problem.
        - Do not write posture language with fake certainty. Frame pelvic-tilt and posture work
          as improving setup, bracing, hip control, and tolerance rather than claiming you are
          "fixing" a diagnosis.
        - Any injury or postural note from the analysis must be addressed explicitly in the
          warm-up/mobility guidance of the relevant day.
        - Session Notes must match the actual session. Do not mention pressing, pulling, or hinge
          prep if that lift family is not meaningfully present that day.

        Example of a GOOD Session Note (do not copy verbatim, match the style):
        "Today's focus is posterior chain — your analysis flagged weak glute engagement and a
         hip-position issue, so we're leading with hinge-pattern work and glute/bracing prep to
         improve your setup first. Warm-up: 5 min bike, then hip 90/90 openers and glute bridges
         2x10 before your first working set of Romanian Deadlifts. Keep ribs stacked over pelvis
         on every rep."

        Example of a BAD Session Note (never write like this):
        "Training session. Progressive overload. Warm-up: light cardio. Mobility: stretch."

        Always call the emit_workout_program tool. Never respond with free text.
        """
    }

    func weekOneUserPrompt(context: String) -> String {
        """
        Build Week 1 of this individual's 4-week mesocycle. Treat the coaching inputs below as
        the source of truth — every day, every exercise, and every note should be traceable back
        to the analysis and must satisfy the structured training intent.

        --- Coaching Inputs ---
        \(context)
        --- end Coaching Inputs ---

        Requirements:
        - Name the program and split meaningfully (reference the analysis, not a generic label).
        - In programSummary, state in ONE sentence what this 4-week arc is designed to accomplish
          for THIS person based on the analysis.
        - Each training day's `notes` must read like a real coach's briefing for that day — tie
          the intent back to the analysis and give warm-up / mobility guidance specific to the
          day's lifts and the user's posture/injury notes. Keep each day note compact.
        - Each exercise's `notes` must include a form cue, a Week 1 progression cue, and a
          personalization sentence referencing the analysis (priority muscle, leverage change,
          postural issue, etc.). Keep each exercise note to two short sentences.

        Call the emit_workout_program tool with your answer.
        """
    }

    func nextWeekSystemPrompt(weekNumber: Int, splitType: String, programName: String) -> String {
        """
        You are the same multi-disciplinary coaching panel that designed Week 1. You are now
        writing Week \(weekNumber) of the same 4-week mesocycle.

        Program: \(programName)
        Split: \(splitType)

        CRITICAL: The Body Analysis is still the north star. The Structured Training Intent
        explains why the plan exists, and the Weekly Blueprint is the execution contract for this
        week. Do NOT treat the previous week as a template to copy forward. The previous week is
        only a PROGRESSION REFERENCE — use it to know what load/volume was achieved last week so
        you can apply appropriate overload or deload for THIS phase.

        Keep reasonable exercise continuity (1-3 anchor lifts per day should carry over for
        progression tracking), but feel free to rotate accessories based on what the analysis
        calls for.

        Session Notes still must be personal, specific, analysis-anchored, and include warm-up /
        mobility guidance tied to this day's lifts AND the user's posture/injury notes. Exercise
        notes still must include form cue + phase-appropriate progression cue + a "why this is
        here for you" sentence tied to the analysis.

        Programming constraints:
        - Exactly 7 days for the requested dayNumber range.
        - 4-6 training days, 1-3 rest days.
        - Training days: 5-8 exercises. Rest days: empty exercises array.
        - Day theme and exercises must align.
        - Follow the Weekly Blueprint exactly when deciding split structure, session emphasis,
          exercise families, and weekly priority allocation.
        - Use standardized exercise naming. Prefer canonical names such as Face Pull, Rope
          Triceps Pressdown, Cable Triceps Pressdown, Hammer Curl, Barbell Curl, Lying Leg Curl,
          Band Pull-Apart, Farmer's Walk, and Incline Smith Machine Press instead of casual
          variants or pluralized duplicates.
        - On a specific focus day, lead with a prime hypertrophy movement for that focus. Do not
          open the session with a corrective/primer movement if a true growth-focused option for
          that muscle appears later.
        - Do not treat support or scapular-control work (for example Y-raises, external-rotation
          drills, or similar corrective patterns) as the main hypertrophy slot for rear delts or
          shoulders.
        - Avoid stacking multiple near-duplicate accessories for the same small muscle unless they
          create a clearly different stimulus profile.
        - Avoid filler late-session add-ons that do not clearly serve the day's style, the
          blueprint priorities, or the injury-management goal.
        - In a shift-work recomposition block, especially on Lower days, prefer 5-6 high-value
          movements over bloated 7-8 exercise sessions unless every slot clearly earns its place.
        - Avoid back-to-back shoulder-intensive days when a lower-body or less-overlapping session
          can separate them.
        - If the analysis flags shoulder impingement risk, internal rotation, or upper-crossed
          posture, bias pressing choices toward landmine press, high-incline dumbbell press,
          cable/machine press options, or neutral-grip setups instead of defaulting to generic
          vertical pressing.
        - Rest and tempo must match exercise role. Do not lazily assign one identical rest period
          or one identical tempo to every movement in a mixed session.
        - Tempo is only for rep-based lifts where eccentric/concentric cadence matters. For
          carries, distance- or time-based work, and similar bracing/isometric drills, leave
          tempo empty instead of inventing a fake 4-part prescription.
        - Loaded carries can support trunk stiffness and grip, but they do not replace a true
          direct-core slot when the blueprint is asking for dedicated core work.
        - On broad Lower or Legs sessions that are not explicitly glute- or hamstring-focused,
          keep real quad stimulus in the plan and avoid piling up multiple glute/posterior-chain
          patterns that all solve the same problem.
        - Do not write posture language with fake certainty. Frame pelvic-tilt and posture work
          as improving setup, bracing, hip control, and tolerance rather than claiming you are
          "fixing" a diagnosis.
        - Postural/injury notes from the analysis continue to drive warm-up and mobility choices.
        - Session Notes must match the actual session. Do not mention pressing, pulling, or hinge
          prep if that lift family is not meaningfully present that day.

        Always call the emit_workout_week tool. Never respond with free text.
        """
    }

    func nextWeekUserPrompt(
        weekNumber: Int,
        dayStart: Int,
        dayEnd: Int,
        previousWeekReference: String,
        analysisContext: String
    ) -> String {
        """
        Generate Week \(weekNumber) (days \(dayStart)-\(dayEnd)) of the mesocycle.

        --- Coaching Inputs (analysis + structured training intent) ---
        \(analysisContext)
        --- end Coaching Inputs ---

        --- Previous week (progression reference ONLY — don't copy) ---
        \(previousWeekReference)
        --- end previous week ---

        Phase guidance for Week \(weekNumber):
        \(phaseGuidance(for: weekNumber))

        Requirements:
        - Use the Weekly Blueprint as the authoritative programming contract for this week. The
          generated training must satisfy those targets in a coherent way.
        - Every training day's `notes` must re-anchor to the analysis (don't drop the
          personalization just because it's week \(weekNumber)) and must include warm-up /
          mobility guidance tied to this day's lifts and the user's posture/injury notes.
        - Every exercise's `notes` must include a form cue, a Week \(weekNumber)-appropriate
          progression cue, and a personalization sentence referencing the analysis.
        - weekSummary: one sentence describing what THIS phase accomplishes for THIS person,
          referencing the analysis.

        Call the emit_workout_week tool with your answer.
        """
    }

    func compactPreviousWeekReference(from previousWeekDays: [WorkoutDayResponse], weekSummary: String?) -> String {
        let daysReference = previousWeekDays
            .sorted { $0.dayNumber < $1.dayNumber }
            .map { day in
                if day.isRestDay {
                    let recoveryFocus = coachingReference(
                        from: day.notes,
                        fallback: "Rest / recovery."
                    )
                    return "Day \(day.dayNumber) - \(day.dayName): \(recoveryFocus)"
                }

                let sessionFocus = coachingReference(
                    from: day.notes,
                    fallback: "\(day.muscleGroups) focus."
                )
                let anchorWork = day.exercises.prefix(4).map { exercise in
                    let target = exercise.muscleTarget.trimmedOr(default: "primary work")
                    return "\(exercise.exerciseName) \(exercise.sets)x\(exercise.reps) (\(target))"
                }.joined(separator: "; ")
                let accessoryCount = max(day.exercises.count - 4, 0)
                let accessoryNote = accessoryCount > 0 ? " +\(accessoryCount) accessory movements" : ""

                return "Day \(day.dayNumber) - \(day.dayName) [\(day.muscleGroups)]: Focus \(sessionFocus) Anchors: \(anchorWork)\(accessoryNote)."
            }
            .joined(separator: "\n\n")

        guard let weekSummary,
              !weekSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return daysReference
        }

        return """
        Previous week summary: \(coachingReference(from: weekSummary, fallback: weekSummary.trimmingCharacters(in: .whitespacesAndNewlines)))

        \(daysReference)
        """
    }

    func decodePreviousWeekSummary(from previousWeekJSON: String) -> String? {
        let cleaned = cleanedJSONText(previousWeekJSON)

        for candidate in jsonCandidates(from: cleaned) {
            guard let data = candidate.data(using: .utf8) else { continue }

            if let program = try? JSONDecoder().decode(WorkoutProgramResponse.self, from: data) {
                return program.programSummary.trimmedOr(default: "")
            }

            if let week = try? JSONDecoder().decode(WorkoutWeekResponse.self, from: data) {
                return week.weekSummary.trimmedOr(default: "")
            }
        }

        return nil
    }

    func decodePreviousWeekContext(from previousWeekJSON: String) -> PreviousWeekDecodeResult {
        let days = decodePreviousWeekDays(from: previousWeekJSON)
        let summary = decodePreviousWeekSummary(from: previousWeekJSON)
        let trimmed = previousWeekJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        guard days.isEmpty && summary == nil && !trimmed.isEmpty else {
            return PreviousWeekDecodeResult(days: days, weekSummary: summary, warning: nil)
        }

        let warning = "Previous week context could not be decoded cleanly, so progression continuity may be limited for this generation."
        print("[WorkoutGeneratorService] \(warning)")
        return PreviousWeekDecodeResult(days: [], weekSummary: nil, warning: warning)
    }

    func coachingReference(from notes: String, fallback: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let firstSentence = trimmed
            .components(separatedBy: ". ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed

        let cleaned = firstSentence.hasSuffix(".") ? firstSentence : "\(firstSentence)."
        if cleaned.count <= 140 {
            return cleaned
        }

        return String(cleaned.prefix(137)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    func phaseGuidance(for weekNumber: Int) -> String {
        switch weekNumber {
        case 2:
            return """
            Week 2 — Volume accumulation. Add ~15-25% productive sets to the priority muscles
            identified in the analysis (not evenly across everything). Target RPE 7-8. Use the
            previous week's performance to pick loads that let the user beat last week's reps.
            """
        case 3:
            return """
            Week 3 — Peak training stress. Highest productive volume of the mesocycle for the
            priority muscles. Top sets at RPE 8-9. Keep postural/injury-driven warm-ups non-
            negotiable — this is the week form breaks down first.
            """
        case 4:
            return """
            Week 4 — Deload / realization. Reduce hard-set volume by ~35-45%. Keep the movements
            familiar; drop sets, not technique quality. Use this week to cement the postural /
            mobility work from the analysis rather than pushing load.
            """
        default:
            return "Apply sensible progressive overload based on the previous week's performance and the analysis priorities."
        }
    }

    // MARK: - Tool Schemas (JSON Schema for Anthropic tool_use)
    //
    // Every nested dictionary literal is explicitly typed as `[String: Any]` so the Swift
    // compiler doesn't have to infer heterogeneous dict types from context — nested JSON
    // Schema structures mix String, Int, Array, and Dict values, and the inference can
    // otherwise fail with "Heterogeneous collection literal" errors.

    func stringProp(_ description: String? = nil) -> [String: Any] {
        var prop: [String: Any] = ["type": "string"]
        if let description {
            prop["description"] = description
        }
        return prop
    }

    func integerProp(minimum: Int? = nil, maximum: Int? = nil, allowedValues: [Int]? = nil) -> [String: Any] {
        var prop: [String: Any] = ["type": "integer"]
        if let minimum { prop["minimum"] = minimum }
        if let maximum { prop["maximum"] = maximum }
        if let allowedValues { prop["enum"] = allowedValues }
        return prop
    }

    func booleanProp() -> [String: Any] {
        ["type": "boolean"]
    }

    func exerciseSchema() -> [String: Any] {
        let properties: [String: Any] = [
            "exerciseName": stringProp("Specific lift name, e.g., 'Incline Dumbbell Press'."),
            "sets": integerProp(minimum: 1, maximum: 8),
            "reps": stringProp("Rep prescription, e.g., '8-10' or 'AMRAP'."),
            // EvidenceProfile.md TEMPO-001 [confidence: low]
            "tempo": stringProp("Optional. Use an explicit 4-part tempo for rep-based lifts when cadence matters, e.g., '3-1-1-0' or '2-0-X-1'. Omit or leave empty for carries, distance-based work, and similar drills where a 4-part tempo is not meaningful."),
            "restSeconds": integerProp(minimum: 30, maximum: 240),
            "notes": stringProp("2-4 sentences: form cue + phase-appropriate progression cue + 'why this is here for you' sentence tied to the body analysis."),
            "muscleTarget": stringProp("Primary muscle target.")
        ]
        let required: [String] = ["exerciseName", "sets", "reps", "restSeconds", "notes", "muscleTarget"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
        return schema
    }

    func daySchema(dayNumbers: [Int]) -> [String: Any] {
        let exercisesProp: [String: Any] = [
            "type": "array",
            "items": exerciseSchema(),
            "description": "5-8 entries on training days; empty array on rest days."
        ]
        let properties: [String: Any] = [
            "dayNumber": integerProp(allowedValues: dayNumbers),
            "dayName": stringProp(),
            "muscleGroups": stringProp(),
            "isRestDay": booleanProp(),
            "notes": stringProp("Session Notes: intent framing tied to the body analysis + warm-up + mobility guidance for THIS day's lifts and THIS user's posture/injury. For rest days, a short active-recovery note."),
            "exercises": exercisesProp
        ]
        let required: [String] = ["dayNumber", "dayName", "muscleGroups", "isRestDay", "notes", "exercises"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
        return schema
    }

    func programToolSchema() -> [String: Any] {
        let dayNumbers = Array(1...7)
        let daysProp: [String: Any] = [
            "type": "array",
            "minItems": 7,
            "maxItems": 7,
            "items": daySchema(dayNumbers: dayNumbers)
        ]
        let properties: [String: Any] = [
            "programName": stringProp(),
            "programSummary": stringProp("One sentence: what the 4-week arc is designed to accomplish for this specific user, referencing the analysis."),
            "splitType": stringProp(),
            "daysPerWeek": integerProp(minimum: 4, maximum: 6),
            "days": daysProp
        ]
        let required: [String] = ["programName", "programSummary", "splitType", "daysPerWeek", "days"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
        return schema
    }

    func weekToolSchema(dayStart: Int, dayEnd: Int) -> [String: Any] {
        let dayNumbers = Array(dayStart...dayEnd)
        let daysProp: [String: Any] = [
            "type": "array",
            "minItems": 7,
            "maxItems": 7,
            "items": daySchema(dayNumbers: dayNumbers)
        ]
        let properties: [String: Any] = [
            "weekSummary": stringProp("One sentence: what THIS phase accomplishes for THIS user, referencing the analysis."),
            "days": daysProp
        ]
        let required: [String] = ["weekSummary", "days"]
        let schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
        return schema
    }

}
