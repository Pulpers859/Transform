import XCTest
@testable import Transform

/// Gated, API-billed live contract test for the body-analysis vision pipeline — the
/// analogue of testLiveWeekOneStructuredContract (workout) and
/// testLiveNutritionWeekOneStructuredContract (nutrition), but for photo analysis.
///
/// It sends ONE real Anthropic vision request through the Foundation-only
/// `ClaudeService.analyzeBody(encodedPhotos:...)` core (added so this path no longer
/// requires UIKit), using a synthetic silhouette PNG fixture and a realistic profile
/// context, then asserts the pipeline returns a schema-valid, saveable analysis and that
/// the validator raises no critical issue.
///
/// Because the image is a synthetic silhouette (not a real physique photo), the hard
/// assertions are deliberately about the CONTRACT — the request/response/decode/validate
/// plumbing and usability — not about analysis richness. The full picture (region count,
/// structured intent, macros, validator issues) is written to the redacted report
/// artifact for a human to eyeball.
///
/// Skips unless BOTH TRANSFORM_RUN_LIVE_ANTHROPIC_SMOKE=1 and a key are set, so it is a
/// no-op in the free generator-tests.yml run and only executes in the manual, gated
/// live-body-analysis-contract job.
@MainActor
final class BodyAnalysisLiveContractTests: XCTestCase {

    func testLiveBodyAnalysisContract() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TRANSFORM_RUN_LIVE_ANTHROPIC_SMOKE"] == "1" else {
            throw XCTSkip("Live Anthropic smoke test is manual and API-billed.")
        }
        guard let rawKey = environment["TRANSFORM_HEADLESS_ANTHROPIC_API_KEY"],
              !rawKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            XCTFail("TRANSFORM_HEADLESS_ANTHROPIC_API_KEY is required when the live smoke test is enabled.")
            return
        }

        let base64 = try loadFixtureBase64("analysis-silhouette-front", ext: "png")
        let context = AnalysisInputContext(
            profile: AnalysisProfileSnapshot(
                age: "31",
                sex: "Male",
                build: "Athletic",
                height: "5 ft 11 in",
                currentWeight: "185 lb",
                occupation: "Physician on rotating shifts",
                trainingFrequency: "5 days per week",
                trainingAge: "6+ years",
                equipmentAccess: "Full commercial gym",
                averageSleep: "6-7 hours, variable with shifts",
                painHistory: "Occasional right-shoulder tightness on pressing",
                activityLevel: "Moderately active",
                primaryGoal: "Lean recomposition",
                lifestyleConstraints: "Shift work with inconsistent meal timing"
            ),
            checkIn: nil,
            progress: nil
        )

        do {
            let result = try await ClaudeService.shared.analyzeBody(
                encodedPhotos: [(pose: "Front", base64: base64)],
                mediaType: "image/png",
                inputContext: context
            )
            let report = BodyAnalysisValidator.validate(
                result,
                photoAngles: ["Front"],
                bodyweightLbs: 185
            )

            writeReportIfRequested(summary(result: result, report: report))

            // Contract: the live vision pipeline returns a schema-valid, saveable analysis.
            XCTAssertFalse(
                result.overallAssessment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "Live analysis returned an empty overall assessment"
            )
            XCTAssertTrue(
                report.isUsable,
                "Live analysis produced a critical validation issue: \(report.issues.map { "[\($0.severity.rawValue)] \($0.field): \($0.message)" })"
            )
        } catch {
            writeReportIfRequested("Live body-analysis contract test failed: \(error.localizedDescription)\n")
            throw error
        }
    }

    // MARK: - Helpers

    private func loadFixtureBase64(_ name: String, ext: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            XCTFail("Missing bundled fixture \(name).\(ext)")
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url).base64EncodedString()
    }

    private func writeReportIfRequested(_ contents: String) {
        guard let path = ProcessInfo.processInfo.environment["TRANSFORM_BODY_ANALYSIS_LIVE_SMOKE_OUTPUT"],
              !path.isEmpty else { return }
        try? contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func summary(result: BodyAnalysisResult, report: AnalysisValidationReport) -> String {
        let intent = result.structuredTrainingIntent
        let issueLines = report.issues.isEmpty
            ? ["- None"]
            : report.issues.map { "- [\($0.severity.rawValue)] \($0.field): \($0.message)" }
        return ([
            "Fixture: analysis-silhouette-front (synthetic PNG, Front angle)",
            "Overall assessment present: \(result.overallAssessment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "no" : "yes")",
            "Estimated body fat: \(result.estimatedBodyFat.isEmpty ? "(none)" : result.estimatedBodyFat)",
            "Region breakdown count: \(result.regionBreakdown.count)",
            "Priority muscles: \(result.priorityMuscles.isEmpty ? "(none)" : result.priorityMuscles.joined(separator: ", "))",
            "Structured intent present: \(intent == nil ? "no" : "yes (days \(intent!.weeklyTrainingDays), \(intent!.priorities.count) priorities)")",
            "Macro targets present: \(result.macroTargets == nil ? "no" : "yes")",
            "Validator usable (no critical): \(report.isUsable ? "yes" : "no")",
            "Validator issues: \(report.issues.count)",
            "Issues:"
        ] + issueLines).joined(separator: "\n") + "\n"
    }
}
