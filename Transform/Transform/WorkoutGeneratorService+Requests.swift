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
        GenerationConfig(model: Config.claudeModel, maxTokens: 8192, timeout: 240)
    }

    var nextWeekConfig: GenerationConfig {
        // Weeks 2-4 progress the Week 1 foundation — Sonnet is fast and strong.
        GenerationConfig(model: Config.claudeModelLite, maxTokens: 8192, timeout: 180)
    }

    /// Tool names that the structured-output flow uses.
    var programToolName: String { "emit_workout_program" }
    var weekToolName: String { "emit_workout_week" }

    /// Anthropic caches a request PREFIX, and the prefix order is tools → system → messages.
    /// A breakpoint on the system block therefore already covers the tool schema; the extra
    /// breakpoint this used to carry on the tool itself only defined a shorter prefix that
    /// nothing ever requested on its own, and the tool block alone sits under the minimum
    /// cacheable length, so it was a cache write that could never be read.
    ///
    /// What the single remaining breakpoint can actually buy: within one generation the main
    /// request and its correction pass send identical tools and an identical system prompt, so
    /// the correction reads this entry seconds later instead of paying full price. That is the
    /// only read this flow can realistically get — the week tool schema pins `dayNumber` to the
    /// week's own day range, so the prefix differs from week to week by construction, and the
    /// parallel candidates fire simultaneously and cannot see each other's write. Keeping the
    /// schema exact is the right trade: a loose `dayNumber` would move a cheap schema guarantee
    /// into a paid validator correction.
    func structuredRequestBody(
        config: GenerationConfig,
        systemPrompt: String,
        userPrompt: String,
        toolName: String,
        toolSchema: [String: Any]
    ) -> [String: Any] {
        let tool: [String: Any] = [
            "name": toolName,
            "description": "Emit the workout program in the required structured shape. Always call this tool; never respond with free text.",
            "input_schema": toolSchema
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

    /// The correction pass reuses the ORIGINAL system prompt verbatim, with its own framing
    /// moved into the user message.
    ///
    /// Two reasons, and the cost one is the smaller of them. It used to substitute a four-line
    /// stand-in system prompt, which meant the repair call was asked to "preserve everything
    /// that was already good" while no longer being shown the coaching contract that defined
    /// good — the voice rules, the execution-only note policy, the menu lock, the postural
    /// guidance. Keeping the real system prompt means the correction is judged against the same
    /// standard that produced the payload. It also makes the request share a prefix with the
    /// call it is repairing, so this second request reads the cache the first one wrote instead
    /// of writing another entry of its own.
    func correctionRequestBody(
        config: GenerationConfig,
        systemPrompt: String,
        toolName: String,
        toolSchema: [String: Any],
        issues: [String],
        context: String,
        originalUserPrompt: String,
        previousPayloadJSON: String? = nil
    ) -> [String: Any] {
        let issueBlock = issues.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let tacticBlock = correctionTactics(for: issues)

        // Without the previous payload the model regenerates blind and "preserve everything
        // that was already good" is unenforceable — corrections drift instead of converging.
        let previousPayloadBlock = previousPayloadJSON
            .map { payload in
                """

                Your previous tool output (repair THIS payload — fix only the listed issues, keep everything else identical):
                \(payload)
                """
            } ?? ""

        let userPrompt = """
        CORRECTION PASS. Your previous call to \(toolName) did not satisfy the coaching intent.
        Every rule in your system instructions still applies unchanged. Call the tool again and
        fix ONLY the listed issues while preserving everything that was already good — do not
        change the overall programming logic or the ties to the user's body analysis.

        Issues to correct (preserve everything else):
        \(issueBlock)

        Repair rules for this correction pass:
        \(tacticBlock)
        \(previousPayloadBlock)

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
            toolSchema: toolSchema
        )
    }

    func correctionTactics(for issues: [String]) -> String {
        var rules: [String] = [
            "- Preserve the program's real strengths, but the listed validator issues are not optional."
        ]

        if issues.contains(where: { $0.contains("contradicts the app's logged progression verdict") }) {
            rules.append("- Rewrite only the flagged coaching cue text so it agrees with the app's logged progression verdict quoted in the issue. Do not change sets, reps, or exercises to resolve a cue contradiction.")
        }

        if issues.contains(where: { $0.contains("session budget") || $0.contains("too crowded") || $0.contains("fatigue load") }) {
            rules.append("- Set counts are locked. Bring the session inside its time budget by correcting excessive rest periods within the role-specific ranges.")
        }

        if issues.contains(where: { $0.contains("Pre-Selected Exercise Menu") }) {
            rules.append("- The Pre-Selected Exercise Menu is locked. Use the exact exercise names, order, and set counts for each listed day; only adjust reps, tempo, rest, and notes.")
        }

        return rules.joined(separator: "\n")
    }

    // MARK: - Exercise Menu Context

    func exerciseMenuContext(from menus: [[PreSelectedExercise]], blueprint: ProgramBlueprint, dayStart: Int = 1) -> String {
        var lines: [String] = []
        for (offset, dayPlan) in blueprint.dayPlans.enumerated() {
            guard !dayPlan.isRestDay, offset < menus.count else { continue }
            let exercises = menus[offset]
            guard !exercises.isEmpty else { continue }

            let dayNumber = dayStart + offset
            let focus = dayPlan.focusArea.map { ", focus: \($0)" } ?? ""
            lines.append("Day \(dayNumber) (\(dayPlan.style)\(focus)):")
            for (i, exercise) in exercises.enumerated() {
                lines.append("  \(i + 1). \(exercise.exerciseName) [\(exercise.muscleTarget)] — \(exercise.prescribedSets) sets, \(exercise.role.rawValue)")
            }
        }

        guard !lines.isEmpty else { return "" }

        return """
        --- Pre-Selected Exercise Menu (use these exact exercises and set counts; do not add, remove, substitute, or change sets) ---
        \(lines.joined(separator: "\n"))
        --- end Pre-Selected Exercise Menu ---
        """
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
        plan for split structure, day emphasis, exercise selection, set allocation, frequency, and weekly
        priorities. Every choice you make must still be directly traceable back to the underlying
        analysis.

        Voice and style:
        - Write like a real coach talking to THIS person, not a generic app.
        - Session Notes (the `notes` field on each training day) must sound curated and personal:
          open with a one-line framing of today's intent given the analysis, then on a NEW LINE
          write "Warm-up:" followed by specific warm-up and mobility items separated by commas
          (e.g. "Warm-up: band pull-aparts x15, thoracic rotations x10, light face pulls x12").
          The warm-up must be tied to THIS day's lifts and THIS person's posture/injury notes.
          Keep session notes concise: 2-3 short sentences, ideally under 70 words total.
          No template language. No phrases like "progressive overload session."
        - Exercise notes must be exactly 2 short sentences of real coaching, ideally under 45
          words total: (a) a form/technique cue for THIS movement and (b) a setup, ROM,
          control, or bracing cue. Fold in a brief "why this is here for you" phrase tied to
          the analysis only when it adds information that the day notes do not already state.
        - Exercise notes are EXECUTION-ONLY. Never write load- or rep-progression
          instructions in notes ("add weight", "next session", "when you clear X reps",
          "add a rep before adding load") — the app computes progression deterministically
          from logged performance and renders it beside your note; a second voice there
          contradicts it. State effort intent in the structured `targetRIR` field instead.
          Write numbers plainly; never use shorthand like "2-".
        - Use double progression as the default progression model when choosing each
          prescription: choose a load intent that lands in the rep range at the target RIR,
          prefer rep increases before load increases, and trim the lowest-priority isolation
          exposure when sleep, joint pain, or stress is poor.

        Programming constraints:
        - Exactly 7 days, dayNumber 1..7.
        - 4-6 training days, 1-3 rest days. Choose the split based on the priority muscles and
          region breakdown in the analysis — don't default.
        - Training days: exercises and set counts exactly as listed in the Pre-Selected Exercise Menu. Rest days: empty
          exercises array.
        - 60-75 minute sessions.
        - Day theme and exercises must align (an Arms day cannot include squats; a Legs day cannot
          include bench press).
        - Follow the Weekly Blueprint exactly when deciding split structure, session emphasis,
          and weekly priority allocation.
        - A Pre-Selected Exercise Menu is provided in the coaching inputs. It lists the exact
        exercises and set counts for each training day. Use them in the order given. Do not add,
        remove, substitute, or change set counts. Your job is to program reps, tempo, rest, and
        coaching notes for each one. Use the exercise names exactly as given.
        - Rest and tempo must match exercise role. Do not lazily assign one identical rest period
          or one identical tempo to every movement in a mixed session.
        - Tempo is only for rep-based lifts where eccentric/concentric cadence matters. For
          carries, distance- or time-based work, and similar bracing/isometric drills, leave
          tempo empty instead of inventing a fake 4-part prescription.
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

    func performanceHistorySection(from history: String?) -> String {
        guard let history, !history.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return """

        --- Logged performance (actual weights/reps from recent workouts — use for load cues) ---
        \(history)
        Use these actual loads when setting each exercise's rep prescription and `targetRIR` so
        the written intent matches reality. Where a line carries an "app verdict", that is the
        app's deterministic progression engine speaking from the actual log — set that
        exercise's rep range and targetRIR to agree with it, and never prescribe a rep range
        the logged reps already exceed at that load. Do NOT restate loads or write progression
        instructions in exercise notes — the app renders its live progression suggestion next
        to your note, and notes are execution-only. Do not change the output schema or add new
        fields.
        --- end logged performance ---
        """
    }

    func weekOneUserPrompt(context: String, exerciseMenuContext: String, performanceHistory: String? = nil, skipHistory: String? = nil) -> String {
        """
        Build Week 1 of this individual's 4-week mesocycle. Treat the coaching inputs below as
        the source of truth — every day, every exercise, and every note should be traceable back
        to the analysis and must satisfy the structured training intent.

        --- Coaching Inputs ---
        \(context)
        --- end Coaching Inputs ---
        \(exerciseMenuContext)
        \(performanceHistorySection(from: performanceHistory))
        \(skipHistorySection(from: skipHistory))
        Requirements:
        - Name the program and split meaningfully (reference the analysis, not a generic label).
        - In programSummary, state in ONE sentence what this 4-week arc is designed to accomplish
          for THIS person based on the analysis.
        - Each training day's `notes` must read like a real coach's briefing for that day — tie
          the intent back to the analysis and give warm-up / mobility guidance specific to the
          day's lifts and the user's posture/injury notes. Keep each day note compact.
        - Each exercise's `notes` must be concise execution coaching: one form cue and one
          setup/ROM/control cue. Add analysis personalization only when it gives new
          information that is not already stated in the day notes. No progression
          instructions in notes — set the structured `targetRIR` field instead; the app
          derives load/rep progression from logs and displays it itself.
        - Avoid repeating phase labels, week labels, or generic goal language in every exercise
          note. The workout screen already shows sets, reps, tempo, RIR/intensity, and deload
          guidance separately, so do not restate those unless needed for safety.

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

        Exercise selection and set allocation are locked by the Pre-Selected Exercise Menu — do
        not add, remove, substitute, or change set counts. Focus your coaching judgment on reps,
        tempo, rest, targetRIR, and execution notes.

        Session Notes still must be personal, specific, analysis-anchored, and include a "Warm-up:"
        line (on its own line) with specific warm-up and mobility items separated by commas, tied
        to this day's lifts AND the user's posture/injury notes. Exercise notes still must be
        execution-only: a form cue + a setup/ROM/control cue, with NO load- or rep-progression
        instructions (the app computes and displays progression from logs; state effort intent in
        the structured `targetRIR` field). Add a "why this is here for you" phrase only when it is
        specific and not already repeated in the day notes.
        Use double progression as the default progression model when choosing prescriptions: add
        reps before load, keep compounds inside the phase RPE cap, and hold load or trim the
        lowest-priority isolation set when sleep, joint pain, or stress is poor.

        Programming constraints:
        - Exactly 7 days for the requested dayNumber range.
        - 4-6 training days, 1-3 rest days.
        - Training days: exercises and set counts exactly as listed in the Pre-Selected Exercise Menu. Rest days: empty
          exercises array.
        - Day theme and exercises must align.
        - Follow the Weekly Blueprint exactly when deciding split structure, session emphasis,
          and weekly priority allocation.
        - A Pre-Selected Exercise Menu is provided in the coaching inputs. It lists the exact
          exercises and set counts for each training day. Use them in the order given. Do not add,
          remove, substitute, or change set counts. Your job is to program reps, tempo, rest, and
          coaching notes for each one. Use the exercise names exactly as given.
        - Rest and tempo must match exercise role. Do not lazily assign one identical rest period
          or one identical tempo to every movement in a mixed session.
        - Tempo is only for rep-based lifts where eccentric/concentric cadence matters. For
          carries, distance- or time-based work, and similar bracing/isometric drills, leave
          tempo empty instead of inventing a fake 4-part prescription.
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
        analysisContext: String,
        exerciseMenuContext: String,
        performanceHistory: String? = nil,
        sessionFeedbackSummary: String? = nil,
        skipHistory: String? = nil
    ) -> String {
        """
        Generate Week \(weekNumber) (days \(dayStart)-\(dayEnd)) of the mesocycle.

        --- Coaching Inputs (analysis + structured training intent) ---
        \(analysisContext)
        --- end Coaching Inputs ---
        \(exerciseMenuContext)

        --- Previous week (progression reference ONLY — don't copy) ---
        \(previousWeekReference)
        --- end previous week ---
        \(performanceHistorySection(from: performanceHistory))
        \(sessionFeedbackSection(from: sessionFeedbackSummary))
        \(skipHistorySection(from: skipHistory))
        Phase guidance for Week \(weekNumber):
        \(phaseGuidance(for: weekNumber))

        Requirements:
        - Use the Weekly Blueprint as the authoritative programming contract for this week. The
          generated training must satisfy those targets in a coherent way.
        - Every training day's `notes` must re-anchor to the analysis (don't drop the
          personalization just because it's week \(weekNumber)) and must include warm-up /
          mobility guidance tied to this day's lifts and the user's posture/injury notes.
        - Every exercise's `notes` must be concise execution coaching: one form cue and one
          setup/ROM/control cue appropriate for Week \(weekNumber). Add analysis
          personalization only when it gives new information that is not already stated in
          the day notes. No progression instructions in notes — set the structured
          `targetRIR` field instead; the app derives load/rep progression from logs.
        - Do not repeat phase labels or deload/recovery language in every exercise note. The app
          already shows intensity, RIR, tempo, and deload guidance as separate UI.
        - weekSummary: one sentence describing what THIS phase accomplishes for THIS person,
          referencing the analysis.

        Call the emit_workout_week tool with your answer.
        """
    }

    private func sessionFeedbackSection(from summary: String?) -> String {
        guard let summary,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return """

        --- Completed-session feedback ---
        \(summary)
        Use this as a conservative adjustment signal, not an instruction to rewrite the split.
        Repeated high effort, pain, worse performance, or poor stimulus should change exercise
        selection, progression, or the lowest-priority volume. Do not infer a diagnosis, and do
        not overreact to one session when the rest of the week was productive.
        --- end completed-session feedback ---
        """
    }

    private func skipHistorySection(from summary: String?) -> String {
        guard let summary,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        return """

        --- Recurring skip / substitution history (persistent across weeks and mesocycles) ---
        \(summary)
        These are movements the user has repeatedly skipped, substituted, or modified. Exercise
        selection is locked by the Pre-Selected Exercise Menu, so do not swap exercises here.
        Instead, use this history to adjust PROGRAMMING for flagged movements:
        - pain/discomfort: add specific warm-up/mobility cues in the day and exercise notes,
          reduce load or intensity prescription, and note the regression in the coaching cue.
        - equipment unavailable: note the constraint in the exercise coaching cue so the user
          knows to use the closest available setup.
        - ran out of time: prioritize the flagged movement earlier in the session notes and keep
          its set/rep prescription efficient.
        - substituted/modified: acknowledge the user's preferred variation in the exercise note
          and write the coaching cue for that variation.
        --- end recurring skip / substitution history ---
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
                let anchorWork = day.exercises.prefix(6).map { exercise in
                    let target = exercise.muscleTarget.trimmedOr(default: "primary work")
                    return "\(exercise.exerciseName) \(exercise.sets)x\(exercise.reps) (\(target))"
                }.joined(separator: "; ")
                let accessoryCount = max(day.exercises.count - 6, 0)
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

            // Inspect payload keys first: WorkoutProgramResponse decodes leniently
            // and would "succeed" on week-shaped JSON, returning the boilerplate
            // default summary instead of the real previous-week summary.
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            if object?["weekSummary"] != nil,
               let week = try? JSONDecoder().decode(WorkoutWeekResponse.self, from: data) {
                return week.weekSummary.trimmedOr(default: "")
            }

            if object?["programSummary"] != nil,
               let program = try? JSONDecoder().decode(WorkoutProgramResponse.self, from: data) {
                return program.programSummary.trimmedOr(default: "")
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
            "sets": [
                "type": "integer",
                "minimum": 1,
                "maximum": 8,
                "description": "Use the exact set count prescribed for this exercise in the Pre-Selected Exercise Menu."
            ],
            "reps": stringProp("Rep prescription, e.g., '8-10' or 'AMRAP'."),
            // EvidenceProfile.md TEMPO-001 [confidence: low]
            "tempo": stringProp("Optional. Use an explicit 4-part tempo for rep-based lifts when cadence matters, e.g., '3-1-1-0' or '2-0-X-1'. Omit or leave empty for carries, distance-based work, and similar drills where a 4-part tempo is not meaningful."),
            "restSeconds": integerProp(minimum: 30, maximum: 240),
            // Execution-only on purpose: the app computes load/rep progression
            // deterministically from logged performance, so a progression cue here
            // creates a second voice that can contradict the live suggestion.
            "notes": stringProp("Exactly 2 short sentences of execution coaching: a form/setup cue plus a control, ROM, or bracing cue. Add a brief analysis-tied 'why this is here for you' phrase only when it adds new information. Do NOT include load- or rep-progression instructions ('add weight', 'next session', 'when you clear X reps') — the app derives progression from logged performance. Write numbers plainly; never use shorthand like '2-'."),
            "muscleTarget": stringProp("Primary muscle target."),
            "targetRIR": [
                "type": "integer",
                "minimum": 0,
                "maximum": 4,
                "description": "Target reps in reserve for this exercise's working sets. Always include for rep-based lifts; effort intent belongs in this structured field, not in prose."
            ] as [String: Any]
        ]
        // targetRIR is required so effort intent is always structured; tempo stays
        // optional because carries/isometrics legitimately omit it.
        let required: [String] = ["exerciseName", "sets", "reps", "restSeconds", "notes", "muscleTarget", "targetRIR"]
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
            "description": "Training days: exactly the exercises and set counts listed in the Pre-Selected Exercise Menu for that day, in order. Rest days: empty array."
        ]
        let properties: [String: Any] = [
            "dayNumber": integerProp(allowedValues: dayNumbers),
            "dayName": stringProp(),
            "muscleGroups": stringProp(),
            "isRestDay": booleanProp(),
            "notes": stringProp("Session Notes: one-line intent framing, then on a new line 'Warm-up:' followed by comma-separated warm-up/mobility items for THIS day's lifts and THIS user's posture/injury. For rest days, a practical active-recovery note tailored to the user's shift-work schedule and postural needs."),
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
