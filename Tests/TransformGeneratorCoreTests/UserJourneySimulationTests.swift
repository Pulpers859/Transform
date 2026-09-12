import XCTest
@testable import Transform

/// A trial run of the app, driven the way an athlete actually uses it.
///
/// Every other test in this suite asks a narrow question about one rule. This one plays five
/// realistic people through the FULL mesocycle — week 1, then weeks 2, 3 and 4 each carrying
/// the previous week forward — and checks the things a person would notice: that a day is not
/// half empty, that the same lift is not prescribed twice in one session, that a week does not
/// silently lose a training day, and that running the same analysis twice gives the same
/// program.
///
/// It drives the PROCEDURAL path, which is network-free and therefore the only end-to-end path
/// a headless runner can execute. That path is not a lesser one: it consumes the same locked
/// menu, the same weekly set allocation and the same validator as the AI path, and it is what
/// the athlete actually receives whenever generation falls back.
///
/// Structural invariants below are hard assertions. Quality observations are PRINTED rather
/// than asserted, because a quality verdict belongs to a human reading the report — turning a
/// heuristic into a red test is how a suite starts lying. Read the printed report in the CI
/// log when changing planning code.
@MainActor
final class UserJourneySimulationTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Personas

    private struct Persona {
        let name: String
        let days: Int
        let priorities: [(area: String, level: String, styles: [String])]
        let injuryNotes: String
        let posturalNotes: String
    }

    private var personas: [Persona] {
        [
            Persona(
                name: "Six-day push/pull/legs, back focus, no injuries",
                days: 6,
                priorities: [
                    ("Back", "High", ["Pull", "Upper"]),
                    ("Rear Deltoids", "Medium", ["Pull", "Upper"])
                ],
                injuryNotes: "",
                posturalNotes: "Mild forward head posture."
            ),
            Persona(
                name: "Four-day beginner with a shoulder that hurts overhead",
                days: 4,
                priorities: [
                    ("Chest", "High", ["Push", "Upper"]),
                    ("Quads", "Medium", ["Legs", "Lower"])
                ],
                injuryNotes: "Right shoulder pain with overhead pressing. No pain on rows.",
                posturalNotes: "Rounded shoulders."
            ),
            Persona(
                name: "Five-day lifter reporting lumbar-extension pain",
                days: 5,
                priorities: [
                    ("Hamstrings", "High", ["Legs", "Lower"]),
                    ("Lats", "Medium", ["Pull", "Upper"])
                ],
                injuryNotes: "Lower back pain with lumbar extension.",
                posturalNotes: "Anterior pelvic tilt."
            ),
            Persona(
                name: "Compound priority area, small muscles",
                days: 5,
                priorities: [
                    ("Lateral Deltoids", "High", ["Push", "Upper"]),
                    ("Calves", "Medium", ["Legs", "Lower"])
                ],
                injuryNotes: "",
                posturalNotes: ""
            ),
            Persona(
                name: "Arms specialisation on four days",
                days: 4,
                priorities: [
                    ("Biceps", "High", ["Pull", "Arms"]),
                    ("Triceps", "High", ["Push", "Arms"])
                ],
                injuryNotes: "Occasional elbow discomfort on skull crushers.",
                posturalNotes: ""
            )
        ]
    }

    private func analysis(for persona: Persona) -> BodyAnalysisResult {
        let structured = StructuredTrainingIntent(
            splitRecommendation: persona.days >= 6 ? "Push / Pull / Legs" : "Upper / Lower",
            weeklyTrainingDays: persona.days,
            priorities: persona.priorities.map { entry in
                StructuredTrainingPriority(
                    area: entry.area,
                    priorityLevel: entry.level,
                    rationale: "Simulation rationale for \(entry.area).",
                    weeklyDayTarget: entry.level == "High" ? 2 : 1,
                    weeklyExerciseTarget: entry.level == "High" ? 3 : 2,
                    preferredStyles: entry.styles,
                    preferredMovementPatterns: [],
                    volumeBias: entry.level == "High" ? "High" : "Moderate",
                    directWorkBias: "Direct emphasis"
                )
            },
            programmingNotes: ["Simulation persona: \(persona.name)."]
        )
        return BodyAnalysisResult(
            overallAssessment: "Simulated athlete.",
            trainingAssessment: "",
            nutritionAssessment: "",
            recoveryRiskAssessment: "",
            adherenceAssessment: "",
            analysisLimitations: "",
            inputContext: nil,
            regionBreakdown: [],
            topLeverageChange: "",
            priorityMuscles: persona.priorities.map(\.area),
            workoutRecommendations: [],
            dietRecommendations: [],
            posturalNotes: persona.posturalNotes,
            estimatedBodyFat: "",
            metabolicHealthNotes: "",
            psychologicalInsights: "",
            injuryRiskNotes: persona.injuryNotes,
            macroTargets: nil,
            structuredTrainingIntent: structured
        )
    }

    // MARK: - The journey

    /// Runs one persona through all four weeks and returns every week's days in order.
    /// One week as the athlete receives it, plus what the validator says about it.
    private struct SimulatedWeek {
        let days: [WorkoutDayResponse]
        let findings: [String]
    }

    private func fullMesocycle(for persona: Persona) throws -> [SimulatedWeek] {
        let result = analysis(for: persona)
        let intent = service.trainingIntentPlan(from: result)
        var weeks: [SimulatedWeek] = []
        var previous: [WorkoutDayResponse]?

        for weekNumber in 1...4 {
            let blueprint = service.programBlueprint(for: intent, weekNumber: weekNumber)
            let menus = service.preSelectedExerciseMenu(
                for: blueprint,
                trainingIntent: intent,
                weekNumber: weekNumber,
                previousWeekDays: previous
            )
            let days: [WorkoutDayResponse]
            if weekNumber == 1 {
                days = try service.validatedProceduralWeekOneProgram(
                    from: result,
                    trainingIntent: intent,
                    blueprint: blueprint,
                    exerciseMenus: menus
                ).days
            } else {
                days = try service.validatedProceduralWeek(
                    weekNumber: weekNumber,
                    dayStart: ((weekNumber - 1) * 7) + 1,
                    dayEnd: weekNumber * 7,
                    splitType: intent.splitRecommendation,
                    programName: "Simulation",
                    trainingIntent: intent,
                    blueprint: blueprint,
                    previousWeekDays: previous,
                    exerciseMenus: menus
                ).days
            }
            // Run the same validator the shipping path runs. The procedural week is what the
            // athlete actually receives whenever generation falls back, so a finding here is a
            // finding against a real delivered program — and several rules are heuristic counts
            // that no structural assertion in this file would ever notice.
            let findings: [String]
            if weekNumber == 1 {
                findings = service.validateProgramResponse(
                    WorkoutProgramResponse(
                        programName: "Simulation",
                        programSummary: "Simulation",
                        splitType: intent.splitRecommendation,
                        daysPerWeek: days.filter { !$0.isRestDay }.count,
                        days: days
                    ),
                    blueprint: blueprint,
                    expectedExerciseMenus: menus
                )
            } else {
                findings = service.validateWeekResponse(
                    WorkoutWeekResponse(weekSummary: "Simulation", days: days),
                    dayStart: ((weekNumber - 1) * 7) + 1,
                    dayEnd: weekNumber * 7,
                    previousWeekDays: previous,
                    blueprint: blueprint,
                    expectedExerciseMenus: menus
                )
            }

            weeks.append(SimulatedWeek(days: days, findings: findings))
            previous = days
        }
        return weeks
    }

    /// The whole trial run. Structural failures are assertions; everything else is reported.
    func testEveryPersonaReceivesAUsableFourWeekProgram() throws {
        var report: [String] = ["", "=== USER JOURNEY SIMULATION ==="]

        for persona in personas {
            let weeks = try fullMesocycle(for: persona)
            report.append("")
            report.append("PERSONA: \(persona.name)")

            for (index, week) in weeks.enumerated() {
                let days = week.days
                let weekNumber = index + 1
                let dayStart = ((weekNumber - 1) * 7) + 1
                let trainingDays = days.filter { !$0.isRestDay }
                let totalSets = trainingDays.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
                let exerciseCount = trainingDays.reduce(0) { $0 + $1.exercises.count }

                // --- Structural invariants: a person would call any of these broken. ---

                XCTAssertEqual(days.count, 7, "\(persona.name) week \(weekNumber): not 7 days")

                XCTAssertEqual(
                    Set(days.map(\.dayNumber)),
                    Set(dayStart...(dayStart + 6)),
                    "\(persona.name) week \(weekNumber): day numbers are wrong"
                )

                for day in days where day.isRestDay {
                    XCTAssertTrue(
                        day.exercises.isEmpty,
                        "\(persona.name) week \(weekNumber) day \(day.dayNumber): rest day carries exercises"
                    )
                }

                for day in trainingDays {
                    XCTAssertFalse(
                        day.exercises.isEmpty,
                        "\(persona.name) week \(weekNumber) day \(day.dayNumber): training day with no exercises"
                    )

                    let names = day.exercises.map { service.normalizeExerciseName($0.exerciseName) }
                    XCTAssertEqual(
                        Set(names).count,
                        names.count,
                        "\(persona.name) week \(weekNumber) day \(day.dayNumber): the same lift appears twice — "
                            + day.exercises.map(\.exerciseName).joined(separator: ", ")
                    )

                    for exercise in day.exercises {
                        let label = "\(persona.name) week \(weekNumber) day \(day.dayNumber) "
                            + "\(exercise.exerciseName)"
                        XCTAssertFalse(
                            exercise.exerciseName.trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(label): empty exercise name"
                        )
                        XCTAssertTrue(
                            (1...8).contains(exercise.sets),
                            "\(label): \(exercise.sets) sets is outside 1-8"
                        )
                        XCTAssertFalse(
                            exercise.reps.trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(label): empty rep prescription"
                        )
                        XCTAssertTrue(
                            (30...240).contains(exercise.restSeconds),
                            "\(label): \(exercise.restSeconds)s rest is outside 30-240"
                        )
                        XCTAssertFalse(
                            exercise.notes.trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(label): no coaching note at all"
                        )
                    }
                }

                // --- Reported, not asserted. ---
                report.append(
                    "  week \(weekNumber): \(trainingDays.count) training days, "
                        + "\(exerciseCount) exercises, \(totalSets) total sets"
                )
                // Validator findings, tiered the way the shipping path tiers them. Reported
                // rather than asserted for now: a quality verdict belongs to a human reading
                // this, and several of these rules are heuristic counts. A HARD FAILURE here
                // would be different in kind — it means the procedural week the athlete
                // actually receives is one the app considers structurally broken — so those
                // are called out separately and loudly.
                for finding in week.findings {
                    let tier: String
                    switch service.validationDisposition(for: finding, menuLocked: true) {
                    case .hardFailure: tier = "HARD FAILURE"
                    case .correctionPass: tier = "repairable"
                    case .acceptableWarning: tier = "warning"
                    }
                    report.append("      [\(tier)] \(finding)")
                }
                if week.findings.isEmpty {
                    report.append("      (no validator findings)")
                }

                // Promoted to an assertion on the evidence of the first run, which reported
                // zero across all five personas and all four weeks. A hard failure here is not
                // a quality opinion: it means the procedural week the athlete actually receives
                // is one the app itself classifies as structurally broken, with no further
                // fallback behind it.
                let hardFailures = week.findings.filter {
                    service.validationDisposition(for: $0, menuLocked: true) == .hardFailure
                }
                XCTAssertTrue(
                    hardFailures.isEmpty,
                    "\(persona.name) week \(weekNumber) ships a structurally broken week: "
                        + hardFailures.joined(separator: " | ")
                )
            }

            // The deload must actually deload: week 4 carries less work than week 3.
            let week3Sets = weeks[2].days.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
            let week4Sets = weeks[3].days.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
            XCTAssertLessThan(
                week4Sets,
                week3Sets,
                "\(persona.name): week 4 is the deload and must carry fewer sets than week 3 "
                    + "(\(week4Sets) vs \(week3Sets))"
            )
            report.append("  deload check: week 3 \(week3Sets) sets -> week 4 \(week4Sets) sets")
        }

        // Written to a file rather than printed. `swift test --parallel` swallows test stdout,
        // so the first run of this simulation produced a report nobody could read; the workflow
        // uploads this path as an artifact instead.
        try writeArtifactIfRequested(
            report.joined(separator: "\n"),
            environmentKey: "TRANSFORM_JOURNEY_REPORT_OUTPUT"
        )
    }

    private func writeArtifactIfRequested(_ contents: String, environmentKey: String) throws {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Same analysis in, same program out. A person who regenerates without changing anything
    /// should not get a different week, and the menu is supposed to be deterministic.
    ///
    /// KNOWN LIMIT, stated so this is not over-trusted: both runs happen in ONE process, and
    /// Swift seeds its hasher per process — so a Dictionary-ordering bug produces the same
    /// wrong answer twice here and passes. This catches ordering that varies WITHIN a run; it
    /// cannot catch the launch-to-launch class. That class is addressed by sorting at the
    /// sites that feed output (`peakDirectSession`, the pattern-stacking loop,
    /// `priorityProfileSpecificitySort`, candidate scoring), and those are what to re-check
    /// when this area changes. A cross-process version would need the suite to re-exec itself.
    func testTheSameAnalysisProducesTheSameProgramTwice() throws {
        for persona in personas {
            let first = try fullMesocycle(for: persona)
            let second = try fullMesocycle(for: persona)

            for (index, weeks) in zip(first, second).enumerated() {
                let lhs = weeks.0.days.map { day in
                    "\(day.dayNumber)|\(day.isRestDay)|"
                        + day.exercises.map { "\($0.exerciseName):\($0.sets):\($0.reps)" }
                            .joined(separator: ",")
                }
                let rhs = weeks.1.days.map { day in
                    "\(day.dayNumber)|\(day.isRestDay)|"
                        + day.exercises.map { "\($0.exerciseName):\($0.sets):\($0.reps)" }
                            .joined(separator: ",")
                }
                XCTAssertEqual(
                    lhs,
                    rhs,
                    "\(persona.name) week \(index + 1) differed between two identical runs"
                )
            }
        }
    }

    /// The blueprint and the week it produced must agree about how many sessions there are.
    /// This is the contradiction that made every six-day deload week a hard failure.
    func testNoWeekSilentlyLosesATrainingDayAgainstItsBlueprint() throws {
        for persona in personas {
            let result = analysis(for: persona)
            let intent = service.trainingIntentPlan(from: result)

            for weekNumber in 1...4 {
                let blueprint = service.programBlueprint(for: intent, weekNumber: weekNumber)
                XCTAssertEqual(
                    blueprint.weeklyTrainingDays,
                    blueprint.dayPlans.filter { !$0.isRestDay }.count,
                    "\(persona.name) week \(weekNumber): blueprint contradicts its own day plans"
                )
            }
        }
    }
}
