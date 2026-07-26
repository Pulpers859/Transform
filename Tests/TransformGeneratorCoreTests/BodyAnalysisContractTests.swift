import XCTest
@testable import Transform

/// Deterministic (free, no-network, no-UIKit) contract test for the body-analysis
/// pipeline's decode + validate stages. It replays a captured well-formed analysis
/// response through the SAME code the live path uses — `ClaudeService.extractJSON`
/// -> `JSONDecoder().decode(BodyAnalysisResult.self)` -> `BodyAnalysisValidator` —
/// and pins the professional-analyzer contract:
///   * schema completeness (assessment, regions, priorities, macros, intent),
///   * macro arithmetic self-consistency (the standard the system prompt now states),
///   * training-intent realism caps and allowed split styles,
///   * priorityMuscles mirroring the structured priority areas,
///   * a fully clean validator verdict on a good analysis.
/// It also locks in the resilient-decoder behavior added in the hardening pass, so a
/// single missing sub-field can never again silently discard a region or the whole
/// structured training contract.
///
/// The live-API equivalent (real key + a synthetic image fixture, mirroring
/// testLiveWeekOneStructuredContract) is intentionally NOT here: the photo request path
/// is behind `#if canImport(UIKit)` and is excluded from this headless macOS target.
@MainActor
final class BodyAnalysisContractTests: XCTestCase {

    private let allAngles = ["Front", "Back", "Side (Left)", "Side (Right)"]

    // MARK: - Helpers

    private func loadFixtureString(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            XCTFail("Missing bundled fixture \(name).json")
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func decode(_ raw: String) throws -> BodyAnalysisResult {
        let json = ClaudeService.extractJSON(from: raw)
        return try JSONDecoder().decode(BodyAnalysisResult.self, from: Data(json.utf8))
    }

    // MARK: - Golden contract

    func testGoldenAnalysisFixtureDecodesAndValidatesClean() throws {
        let result = try decode(loadFixtureString("body-analysis-week-one"))

        // Schema completeness.
        XCTAssertFalse(result.overallAssessment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertGreaterThanOrEqual(result.regionBreakdown.count, 1)
        XCTAssertFalse(result.priorityMuscles.isEmpty)
        XCTAssertFalse(result.estimatedBodyFat.isEmpty)
        XCTAssertFalse(result.workoutRecommendations.isEmpty)
        XCTAssertFalse(result.dietRecommendations.isEmpty)

        // Macro arithmetic must be self-consistent within 5% (the rule the prompt states).
        let macros = try XCTUnwrap(result.macroTargets, "contract requires macroTargets")
        let computed = macros.proteinG * 4 + macros.carbsG * 4 + macros.fatG * 9
        let deviation = abs(computed - Double(macros.calories)) / Double(macros.calories)
        XCTAssertLessThanOrEqual(deviation, 0.05,
            "macro math must land within 5%: \(Int(computed)) kcal computed vs \(macros.calories) stated")
        XCTAssertFalse((macros.macroRationale ?? "").isEmpty, "macroRationale must explain the target")

        // Training-intent realism caps + allowed styles.
        let intent = try XCTUnwrap(result.structuredTrainingIntent, "contract requires structuredTrainingIntent")
        XCTAssertTrue((4...6).contains(intent.weeklyTrainingDays), "weeklyTrainingDays must be 4-6")
        XCTAssertFalse(intent.priorities.isEmpty)
        let validStyles: Set<String> = ["Push", "Pull", "Legs", "Lower", "Upper", "Arms"]
        for p in intent.priorities {
            XCTAssertLessThanOrEqual(p.weeklyDayTarget, 3, "\(p.area) weeklyDayTarget exceeds cap")
            XCTAssertLessThanOrEqual(p.weeklyExerciseTarget, 5, "\(p.area) weeklyExerciseTarget exceeds cap")
            XCTAssertFalse(p.preferredMovementPatterns.isEmpty, "\(p.area) needs movement patterns")
            XCTAssertTrue(p.preferredStyles.allSatisfy { validStyles.contains($0) },
                          "\(p.area) uses a style outside the allowed set")
        }

        // priorityMuscles must name the same areas as the structured priorities.
        let priorityAreas = Set(intent.priorities.map { $0.area.lowercased() })
        let namedMuscles = Set(result.priorityMuscles.map { $0.lowercased() })
        XCTAssertEqual(priorityAreas, namedMuscles,
            "priorityMuscles should mirror structuredTrainingIntent.priorities areas")

        // The full validator must pass a good analysis with no errors or criticals.
        let report = BodyAnalysisValidator.validate(result, photoAngles: allAngles, bodyweightLbs: 185)
        XCTAssertTrue(report.isUsable, "golden analysis must be saveable (no critical issues)")
        let blocking = report.issues.filter { $0.severity >= .error }
        XCTAssertTrue(blocking.isEmpty,
            "golden analysis must produce no error/critical issues, got: \(blocking.map { "[\($0.severity.rawValue)] \($0.field): \($0.message)" })")
    }

    // MARK: - extractJSON robustness (the retry path relies on this)

    func testExtractJSONStripsPreambleAndCodeFences() throws {
        let inner = ClaudeService.extractJSON(from: try loadFixtureString("body-analysis-week-one"))
        let wrapped = "Here is the analysis you requested:\n```json\n\(inner)\n```\nLet me know if you'd like adjustments."
        let result = try decode(wrapped)
        XCTAssertFalse(result.overallAssessment.isEmpty, "preamble + code fences must be stripped before decoding")
        XCTAssertNotNil(result.structuredTrainingIntent)
    }

    // MARK: - Resilient decode (locks in the hardening-pass behavior)

    func testResilientDecodeSurvivesMissingSubfields() throws {
        // A region missing "priority" and a priority missing "directWorkBias" (plus the
        // intent missing splitRecommendation + programmingNotes) previously threw and
        // discarded either the whole analysis or the whole structured contract. They must
        // now decode with safe defaults instead.
        let json = """
        {
          "overallAssessment": "Solid base with an upper-chest lag.",
          "regionBreakdown": [
            { "region": "Upper Chest", "assessment": "Clavicular head lags." }
          ],
          "priorityMuscles": ["Upper Chest"],
          "structuredTrainingIntent": {
            "weeklyTrainingDays": 5,
            "priorities": [
              { "area": "Upper Chest", "priorityLevel": "High", "rationale": "Lags", "weeklyDayTarget": 2, "weeklyExerciseTarget": 3, "preferredStyles": ["Push"], "preferredMovementPatterns": ["incline press"], "volumeBias": "High" }
            ]
          }
        }
        """
        let result = try JSONDecoder().decode(BodyAnalysisResult.self, from: Data(json.utf8))

        let region = try XCTUnwrap(result.regionBreakdown.first, "region with a name must survive")
        XCTAssertEqual(region.region, "Upper Chest")
        XCTAssertFalse(region.priority.isEmpty, "missing region priority must default, not throw the decode")

        let intent = try XCTUnwrap(result.structuredTrainingIntent,
            "a partial structuredTrainingIntent must not be dropped to nil")
        XCTAssertEqual(intent.priorities.count, 1)
        XCTAssertEqual(intent.priorities.first?.area, "Upper Chest")
        XCTAssertEqual(intent.priorities.first?.directWorkBias, "", "missing sub-field defaults to empty")
    }

    func testResilientDecodeDropsEmptyAreaPriority() throws {
        // A priority with no usable area is noise to the generator — it must be filtered
        // out while the real priority survives, rather than throwing the whole intent.
        let json = """
        {
          "overallAssessment": "Base.",
          "structuredTrainingIntent": {
            "splitRecommendation": "Upper/Lower",
            "weeklyTrainingDays": 5,
            "priorities": [
              { "area": "  ", "priorityLevel": "High", "rationale": "", "weeklyDayTarget": 2, "weeklyExerciseTarget": 3, "preferredStyles": ["Push"], "preferredMovementPatterns": ["incline press"], "volumeBias": "High", "directWorkBias": "Direct emphasis" },
              { "area": "Rear Deltoids", "priorityLevel": "High", "rationale": "Lags", "weeklyDayTarget": 3, "weeklyExerciseTarget": 4, "preferredStyles": ["Pull"], "preferredMovementPatterns": ["reverse pec deck"], "volumeBias": "High", "directWorkBias": "Direct emphasis" }
            ],
            "programmingNotes": []
          }
        }
        """
        let result = try JSONDecoder().decode(BodyAnalysisResult.self, from: Data(json.utf8))
        let intent = try XCTUnwrap(result.structuredTrainingIntent)
        XCTAssertEqual(intent.priorities.map { $0.area }, ["Rear Deltoids"],
            "empty-area priority must be filtered while the real one is kept")
    }
}
