import Foundation
import XCTest
@testable import Transform

@MainActor
final class GeneratorTroubleshootingTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Expected: Decodable {
            let trainingDays: Int
            let validatorIssues: [String]
            let forbiddenIssueFragments: [String]
            let menuSignature: String
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
        try writeArtifactIfRequested(signature, environmentKey: "TRANSFORM_FIXTURE_SNAPSHOT_OUTPUT")
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

    private func menuSignature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> String {
        menus.enumerated().map { offset, menu in
            let slots = menu.map {
                "\($0.exerciseName)#\($0.prescribedSets)#\($0.muscleTarget)"
            }.joined(separator: " | ")
            return "Day \(offset + 1): \(slots.isEmpty ? "REST" : slots)"
        }.joined(separator: "\n")
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
