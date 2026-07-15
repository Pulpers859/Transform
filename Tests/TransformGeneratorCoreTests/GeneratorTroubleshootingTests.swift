import Foundation
import Foundation
import XCTest
@testable import Transform

@MainActor
final class GeneratorTroubleshootingTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Expected: Decodable {
            let trainingDays: Int
            let recoveryConstrained: Bool
            let poorNutritionAdherence: Bool
            let recompositionGoal: Bool
            let validatorIssues: [String]
            let forbiddenIssueFragments: [String]
            let menuSignature: [String]
        }

        let schemaVersion: Int
        let id: String
        let stage: String
        let analysis: BodyAnalysisResult
        let expected: Expected
    }

    private let service = ClaudeService.shared

    func testFiveMaintenanceErrorFixtureStaysResolved() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.stage, "weekOne")
        let intent = service.trainingIntentPlan(from: fixture.analysis)
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        XCTAssertEqual(blueprint.calibration.recoveryConstrained, fixture.expected.recoveryConstrained)
        XCTAssertEqual(blueprint.calibration.poorNutritionAdherence, fixture.expected.poorNutritionAdherence)
        XCTAssertEqual(blueprint.calibration.recompositionGoal, fixture.expected.recompositionGoal)
        let menus = service.preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: intent,
            weekNumber: 1,
            previousWeekDays: nil
        )
        let program = try service.validatedProceduralWeekOneProgram(
            from: fixture.analysis,
            trainingIntent: intent,
            blueprint: blueprint,
            exerciseMenus: menus
        )
        let issues = service.validateProgramResponse(
            program,
            blueprint: blueprint,
            expectedExerciseMenus: menus
        )
        let signature = menuSignature(menus)

        XCTAssertEqual(program.days.count, 7, "Regression fixture must produce a complete calendar week")
        XCTAssertEqual(
            program.days.filter { !$0.isRestDay }.count,
            fixture.expected.trainingDays,
            "Regression fixture changed its training-day contract"
        )
        XCTAssertEqual(issues, fixture.expected.validatorIssues, "Validator verdict drifted for the captured failure class")
        XCTAssertTrue(
            service.allocationLedgerConsistencyIssues(menus, blueprint: blueprint).isEmpty,
            "Allocator and validator direct-set ledgers diverged"
        )
        XCTAssertTrue(
            service.weeklyVariationViolations(in: program.days, blueprint: blueprint).isEmpty,
            "Regression fixture exceeded the shared weekly variation policy"
        )
        for fragment in fixture.expected.forbiddenIssueFragments {
            XCTAssertFalse(
                issues.contains { $0.localizedCaseInsensitiveContains(fragment) },
                "Historical validator failure returned: \(fragment)"
            )
        }

        if !fixture.expected.menuSignature.isEmpty {
            XCTAssertEqual(signature, fixture.expected.menuSignature, "Allocated menu snapshot drifted")
        }
        try writeArtifactIfRequested(
            signature.joined(separator: "\n"),
            environmentKey: "TRANSFORM_FIXTURE_SNAPSHOT_OUTPUT"
        )
    }

    func testSanitizationRepairsMissingProgressionCueWithoutDiscardingFormCue() async throws {
        let response = WorkoutProgramResponse(
            programName: "Sanitization Test",
            programSummary: "A focused test response.",
            splitType: "Upper",
            daysPerWeek: 4,
            days: [
                WorkoutDayResponse(
                    dayNumber: 1,
                    dayName: "Upper",
                    muscleGroups: "Shoulders",
                    isRestDay: false,
                    notes: "Today's focus is controlled upper-body work. Warm-up: light cable raises and shoulder circles.",
                    exercises: [
                        WorkoutExerciseResponse(
                            exerciseName: "Cable Lateral Raise",
                            sets: 2,
                            reps: "12-15",
                            tempo: "2-0-1-0",
                            restSeconds: 75,
                            notes: "Keep a soft elbow bend and lift through the side delt.",
                            muscleTarget: "Lateral Deltoids"
                        )
                    ]
                )
            ]
        )

        let cleaned = try await service.sanitizeProgramResponse(response)
        let notes = try XCTUnwrap(cleaned.days.first?.exercises.first?.notes)

        XCTAssertTrue(notes.contains("soft elbow bend"), "Sanitization discarded the model's valid form cue")
        XCTAssertTrue(
            service.hasConcreteProgressionCue(notes),
            "Sanitization must repair a non-empty note that lacks a concrete progression cue"
        )
        XCTAssertTrue(notes.contains("Baseline target:"), "Week 1 repair should use the baseline progression guidance")
    }

    func testProgressionEngineUsesAllWorkingSetsInsteadOfSummaryTopSet() throws {
        let range = try XCTUnwrap(RepRange.parse("10–14"))
        let logs = [14, 10, 10].enumerated().map { index, reps in
            SetLogEntry(setNumber: index + 1, weightLbs: 70, repsCompleted: reps)
        }

        let decision = try XCTUnwrap(
            WorkoutProgressionEngine.evaluate(
                latestSetLogs: logs,
                summaryWeight: 70,
                summaryReps: 14,
                repRange: range
            )
        )

        XCTAssertEqual(decision.kind, .addRepsInRange)
        XCTAssertEqual(decision.workingSetCount, 3)
        XCTAssertEqual(decision.ceilingSetCount, 1)
        XCTAssertTrue(decision.usedPerSetEvidence)
    }

    func testProgressionEngineAddsLoadOnlyWhenWorkingSetsAreReady() throws {
        let range = try XCTUnwrap(RepRange.parse("8-12"))
        let completeLogs = [12, 12, 12].enumerated().map { index, reps in
            SetLogEntry(setNumber: index + 1, weightLbs: 100, repsCompleted: reps)
        }
        let incompleteLogs = [12, 7, 12].enumerated().map { index, reps in
            SetLogEntry(setNumber: index + 1, weightLbs: 100, repsCompleted: reps)
        }

        let complete = try XCTUnwrap(
            WorkoutProgressionEngine.evaluate(
                latestSetLogs: completeLogs,
                summaryWeight: 100,
                summaryReps: 12,
                repRange: range
            )
        )
        let incomplete = try XCTUnwrap(
            WorkoutProgressionEngine.evaluate(
                latestSetLogs: incompleteLogs,
                summaryWeight: 100,
                summaryReps: 12,
                repRange: range
            )
        )

        XCTAssertEqual(complete.kind, .addLoad)
        XCTAssertEqual(incomplete.kind, .holdBelowRange)
        XCTAssertEqual(WorkoutProgressionEngine.nextLoad(from: 70, exerciseName: "Cable Lateral Raise"), 75)
        XCTAssertEqual(WorkoutProgressionEngine.nextLoad(from: 100, exerciseName: "Barbell Row"), 102.5)
    }

    func testProgressionEngineFallsBackToLegacySummaryWithoutSetLogs() throws {
        let range = try XCTUnwrap(RepRange.parse("8-12"))
        let decision = try XCTUnwrap(
            WorkoutProgressionEngine.evaluate(
                latestSetLogs: [],
                summaryWeight: 80,
                summaryReps: 12,
                repRange: range
            )
        )

        XCTAssertEqual(decision.kind, .addLoad)
        XCTAssertEqual(decision.workingWeight, 80)
        XCTAssertEqual(decision.workingSetCount, 0)
        XCTAssertFalse(decision.usedPerSetEvidence)
    }

    func testProgressionEngineUsesLatestUsablePerformanceLog() throws {
        let key = "barbell-row"
        let older = WorkoutPerformanceLogSnapshot(
            canonicalExerciseKey: key,
            loggedAt: Date(timeIntervalSince1970: 100),
            setLogs: [SetLogEntry(setNumber: 1, weightLbs: 90, repsCompleted: 12)]
        )
        let newerMalformed = WorkoutPerformanceLogSnapshot(
            canonicalExerciseKey: key,
            loggedAt: Date(timeIntervalSince1970: 200),
            setLogs: []
        )
        let unrelated = WorkoutPerformanceLogSnapshot(
            canonicalExerciseKey: "bench-press",
            loggedAt: Date(timeIntervalSince1970: 300),
            setLogs: [SetLogEntry(setNumber: 1, weightLbs: 185, repsCompleted: 8)]
        )

        let logs = WorkoutProgressionEngine.latestUsableSetLogs(
            for: key,
            from: [older, newerMalformed, unrelated]
        )

        XCTAssertEqual(logs, older.setLogs)
    }

    func testEffortGovernanceRequiresRepeatedRecoverySignals() {
        let singleFlag = WorkoutSessionFeedbackSnapshot(
            effort: 5,
            stimulus: 3,
            jointPain: 0,
            performanceRawValue: "Same"
        )
        let painFlag = WorkoutSessionFeedbackSnapshot(
            effort: 3,
            stimulus: 2,
            jointPain: 3,
            performanceRawValue: "Same"
        )

        XCTAssertEqual(
            WorkoutEffortGovernance.signal(from: [singleFlag]),
            .neutral
        )
        XCTAssertEqual(
            WorkoutEffortGovernance.signal(from: [singleFlag, painFlag]),
            .protectRecovery
        )
        XCTAssertTrue(
            WorkoutEffortGovernance.guidance(for: .protectRecovery).contains("Hold load progression")
        )
    }

    func testEffortGovernanceRecognizesRepeatedProgressionHeadroom() {
        let headroom = WorkoutSessionFeedbackSnapshot(
            effort: 3,
            stimulus: 4,
            jointPain: 0,
            performanceRawValue: "Better"
        )

        XCTAssertEqual(
            WorkoutEffortGovernance.signal(from: [headroom, headroom]),
            .progressionHeadroom
        )
        XCTAssertTrue(
            WorkoutEffortGovernance.guidance(for: .progressionHeadroom).contains("add reps before load")
        )
    }

    func testLiveWeekOneStructuredContract() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TRANSFORM_RUN_LIVE_ANTHROPIC_SMOKE"] == "1" else {
            throw XCTSkip("Live Anthropic smoke test is manual and API-billed.")
        }
        guard let rawKey = environment["TRANSFORM_HEADLESS_ANTHROPIC_API_KEY"],
              !rawKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            XCTFail("TRANSFORM_HEADLESS_ANTHROPIC_API_KEY is required when the live smoke test is enabled.")
            return
        }

        let fixture = try loadFixture()
        do {
            let analysisSummary = service.analysisContext(from: fixture.analysis)
            let intent = service.trainingIntentPlan(from: fixture.analysis)
            let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
            let intentSummary = service.trainingIntentContext(from: intent)
            let blueprintSummary = service.blueprintContext(from: blueprint)
            let context = service.generationContext(
                analysisSummary: analysisSummary,
                trainingIntentSummary: intentSummary,
                blueprintSummary: blueprintSummary
            )
            let menus = service.preSelectedExerciseMenu(
                for: blueprint,
                trainingIntent: intent,
                weekNumber: 1,
                previousWeekDays: nil
            )
            let menuContext = service.exerciseMenuContext(from: menus, blueprint: blueprint)
            let config = ClaudeService.GenerationConfig(
                model: Config.claudeModelLite,
                maxTokens: 8192,
                timeout: 180
            )
            let systemPrompt = service.weekOneSystemPrompt()
            let userPrompt = service.weekOneUserPrompt(
                context: context,
                exerciseMenuContext: menuContext
            )
            let requestContext = service.workoutRequestContext(
                phase: "headless_live_smoke",
                weekNumber: 1,
                analysisContext: context,
                previousWeekReference: nil,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
            let requestBody = service.structuredRequestBody(
                config: config,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                toolName: service.programToolName,
                toolSchema: service.programToolSchema()
            )
            let rawJSON = try await AnthropicClient.shared.sendStructuredRequest(
                body: requestBody,
                toolName: service.programToolName,
                timeout: config.timeout,
                context: requestContext,
                attemptLimit: 1
            )
            let decoded = try service.decodeJSONPayload(WorkoutProgramResponse.self, from: rawJSON)
            let cleaned = service.applyingPreselectedSetPrescription(
                to: try await service.sanitizeProgramResponse(decoded),
                menus: menus
            )
            let issues = service.validateProgramResponse(
                cleaned,
                blueprint: blueprint,
                expectedExerciseMenus: menus
            )
            try writeArtifactIfRequested(
                liveSummary(fixtureID: fixture.id, program: cleaned, issues: issues),
                environmentKey: "TRANSFORM_LIVE_SMOKE_OUTPUT"
            )

            XCTAssertEqual(cleaned.days.count, 7, "Live generation did not return a complete week")
            XCTAssertEqual(
                cleaned.days.filter { !$0.isRestDay }.count,
                fixture.expected.trainingDays,
                "Live generation changed the requested training-day count"
            )
            XCTAssertEqual(issues, fixture.expected.validatorIssues, "Live model output did not pass the captured validator contract")
            for fragment in fixture.expected.forbiddenIssueFragments {
                XCTAssertFalse(
                    issues.contains { $0.localizedCaseInsensitiveContains(fragment) },
                    "Live generation reproduced a historical maintenance-volume failure: \(fragment)"
                )
            }
        } catch {
            try? writeArtifactIfRequested(
                "Live structured-contract smoke test failed: \(error.localizedDescription)\n",
                environmentKey: "TRANSFORM_LIVE_SMOKE_OUTPUT"
            )
            throw error
        }
    }

    func testMaintenanceVolumeGuardPositiveControls() throws {
        let fixture = try loadFixture()
        let intent = service.trainingIntentPlan(from: fixture.analysis)
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        let menus = service.preSelectedExerciseMenu(
            for: blueprint,
            trainingIntent: intent,
            weekNumber: 1,
            previousWeekDays: nil
        )
        let baseline = try service.validatedProceduralWeekOneProgram(
            from: fixture.analysis,
            trainingIntent: intent,
            blueprint: blueprint,
            exerciseMenus: menus
        )
        let controls = [
            (label: "Back", exercise: "Lat Pulldown", target: "Lats"),
            (label: "Triceps", exercise: "Rope Triceps Pressdown", target: "Triceps"),
            (label: "Quads", exercise: "Leg Extension", target: "Quads"),
            (label: "Hamstrings", exercise: "Leg Curl", target: "Hamstrings"),
            (label: "Glutes", exercise: "Hip Thrust", target: "Glutes")
        ]

        for control in controls {
            let inflated = appendingOvervolumeExercise(
                to: baseline,
                exerciseName: control.exercise,
                muscleTarget: control.target
            )
            let issues = service.validateProgramResponse(inflated, blueprint: blueprint)
            let expected = "Non-priority muscle group '\(control.label)' exceeds the maintenance weekly volume ceiling"
            XCTAssertTrue(
                issues.contains { $0.localizedCaseInsensitiveContains(expected) },
                "Maintenance validator failed its positive control for \(control.label): \(issues.joined(separator: " | "))"
            )
        }
    }

    private func loadFixture() throws -> Fixture {
        guard let url = Bundle.module.url(
            forResource: "five-maintenance-errors",
            withExtension: "json"
        ) else {
            XCTFail("Bundled generator regression fixture is missing")
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func menuSignature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [String] {
        menus.enumerated().map { offset, menu in
            let slots = menu.map {
                "\($0.exerciseName)#\($0.prescribedSets)#\($0.muscleTarget)"
            }.joined(separator: " | ")
            return "Day \(offset + 1): \(slots.isEmpty ? "REST" : slots)"
        }
    }

    private func liveSummary(
        fixtureID: String,
        program: WorkoutProgramResponse,
        issues: [String]
    ) -> String {
        let issueLines = issues.isEmpty
            ? ["- None"]
            : issues.enumerated().map { "- \($0.offset + 1): \($0.element)" }
        return ([
            "Fixture: \(fixtureID)",
            "Request count: 1 logical request, 1 maximum HTTP attempt",
            "Calendar days: \(program.days.count)",
            "Training days: \(program.days.filter { !$0.isRestDay }.count)",
            "Exercise count: \(program.days.reduce(0) { $0 + $1.exercises.count })",
            "Validator issues: \(issues.count)",
            "Issues:"
        ] + issueLines).joined(separator: "\n") + "\n"
    }

    private func appendingOvervolumeExercise(
        to program: WorkoutProgramResponse,
        exerciseName: String,
        muscleTarget: String
    ) -> WorkoutProgramResponse {
        var days = program.days
        guard let dayIndex = days.firstIndex(where: { !$0.isRestDay }) else {
            return program
        }
        let day = days[dayIndex]
        let extra = WorkoutExerciseResponse(
            exerciseName: exerciseName,
            sets: 12,
            reps: "8-12",
            tempo: "2-0-1-0",
            restSeconds: 90,
            notes: "Synthetic validator positive control only.",
            muscleTarget: muscleTarget
        )
        days[dayIndex] = WorkoutDayResponse(
            dayNumber: day.dayNumber,
            dayName: day.dayName,
            muscleGroups: day.muscleGroups,
            isRestDay: day.isRestDay,
            notes: day.notes,
            exercises: day.exercises + [extra]
        )
        return WorkoutProgramResponse(
            programName: program.programName,
            programSummary: program.programSummary,
            splitType: program.splitType,
            daysPerWeek: program.daysPerWeek,
            days: days
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
}
