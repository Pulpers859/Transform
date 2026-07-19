import XCTest
@testable import Transform

/// Pins the body-analysis validation/safety contract after the macro-floor audit:
///  * the validator audits macros against the SAME bodyweight-scaled floors that
///    MacroTargetResolver actually enforces — the report card can no longer say
///    "macros fine" while the macro card silently clamps them (finding #1);
///  * a sub-floor macro is a WARNING, not a save-blocking critical, because the
///    resolver clamps it up safely — an otherwise-good analysis stays saveable,
///    and only genuinely unusable output (empty overall assessment) blocks the
///    save (finding #2);
///  * region priority matching is case-insensitive (finding #5);
///  * the diagnostic-language net catches assertive diagnoses without tripping on
///    the cautious hedged wording the prompt requires (finding #6).
@MainActor
final class BodyAnalysisValidationTests: XCTestCase {

    private let bodyweightLbs = 200.0  // kg ≈ 90.7 → protein floor ≈ 127 g, fat floor ≈ 32 g, cal floor = 2000

    // MARK: - Builders

    private func macros(calories: Int, protein: Double, carbs: Double, fat: Double) -> AnalysisMacroTargets {
        AnalysisMacroTargets(calories: calories, proteinG: protein, carbsG: carbs, fatG: fat,
                             macroRationale: "Test rationale.")
    }

    private func result(
        overall: String = "Lean, developed physique with an upper-chest bottleneck. Confidence: medium-high.",
        regions: [RegionAssessment] = [RegionAssessment(region: "Upper Chest", assessment: "Underdeveloped clavicular head.", priority: "High")],
        postural: String = "Ribcage sits slightly forward; cue bracing on presses.",
        macros: AnalysisMacroTargets?
    ) -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: overall,
            trainingAssessment: "Prioritize incline pressing.",
            nutritionAssessment: "Hold maintenance.",
            recoveryRiskAssessment: "No major flags.",
            adherenceAssessment: "Consistency looks reasonable.",
            analysisLimitations: "Photo-only; no labs.",
            inputContext: nil,
            regionBreakdown: regions,
            topLeverageChange: "Add a second weekly incline session.",
            priorityMuscles: ["Upper Chest", "Rear Delts"],
            workoutRecommendations: ["Low incline press 3x6-10"],
            dietRecommendations: ["Keep protein high"],
            posturalNotes: postural,
            estimatedBodyFat: "14-16%",
            metabolicHealthNotes: "Energy management is fine.",
            psychologicalInsights: "Sustainable plan matters.",
            injuryRiskNotes: "Watch shoulder setup.",
            macroTargets: macros,
            structuredTrainingIntent: StructuredTrainingIntent(
                splitRecommendation: "Upper/Lower",
                weeklyTrainingDays: 5,
                priorities: [StructuredTrainingPriority(
                    area: "Upper Chest", priorityLevel: "High", rationale: "Lagging",
                    weeklyDayTarget: 2, weeklyExerciseTarget: 3,
                    preferredStyles: ["Push"], preferredMovementPatterns: ["incline press"],
                    volumeBias: "High", directWorkBias: "Direct emphasis")],
                programmingNotes: ["Manage press fatigue"])
        )
    }

    private func validate(_ result: BodyAnalysisResult, angles: [String] = ["Front", "Back", "Side (Left)", "Side (Right)"]) -> AnalysisValidationReport {
        BodyAnalysisValidator.validate(result, photoAngles: angles, bodyweightLbs: bodyweightLbs)
    }

    private func issues(_ report: AnalysisValidationReport, field: String) -> [AnalysisValidationIssue] {
        report.issues.filter { $0.field == field }
    }

    // MARK: - #1 Validator floors == resolver floors (anti-drift)

    func testMacroWarningsMatchTheFloorsTheResolverActuallyEnforces() {
        let floors = MacroTargetResolver.safetyFloors(bodyweightLbs: bodyweightLbs)
        // Each macro exactly one unit under its real floor.
        let m = macros(calories: floors.calories - 1,
                       protein: floors.proteinG - 1,
                       carbs: 40,               // below the 50 g carb floor too
                       fat: floors.fatG - 1)
        let r = result(macros: m)
        let report = validate(r)

        // The audit surface flags all three below-floor macros...
        XCTAssertFalse(issues(report, field: "macroTargets.calories").isEmpty, "calories below floor must be flagged")
        XCTAssertFalse(issues(report, field: "macroTargets.proteinG").isEmpty, "protein below floor must be flagged")
        XCTAssertFalse(issues(report, field: "macroTargets.fatG").isEmpty, "fat below floor must be flagged")

        // ...and the resolver actually clamps every one of them to those same floors,
        // including carbs (finding #6 — the carb raise used to be invisible).
        let resolved = MacroTargetResolver.resolve(from: r, bodyweightLbs: bodyweightLbs)
        XCTAssertEqual(resolved.calories, floors.calories)
        XCTAssertEqual(resolved.proteinG, floors.proteinG, accuracy: 0.001)
        XCTAssertEqual(resolved.fatG, floors.fatG, accuracy: 0.001)
        XCTAssertEqual(resolved.carbsG, floors.carbsG, accuracy: 0.001)
        XCTAssertTrue(resolved.floorAdjustments.contains { $0.contains("Carbs raised") },
                      "carb floor adjustment must be surfaced, not applied silently")
    }

    func testMacrosBetweenAbsoluteConstantsAndRealFloorAreStillFlagged() {
        // 1600 kcal / 100 g protein clears the OLD absolute constants (1200 / 60) but
        // is under this bodyweight's real floors (2000 / ~127). The old validator went
        // silent here while the resolver clamped anyway — that drift is the bug.
        let r = result(macros: macros(calories: 1600, protein: 100, carbs: 180, fat: 60))
        let report = validate(r)
        XCTAssertFalse(issues(report, field: "macroTargets.calories").isEmpty,
                       "1600 kcal is under the 2000 kcal bodyweight floor and must warn")
        XCTAssertFalse(issues(report, field: "macroTargets.proteinG").isEmpty,
                       "100 g protein is under the ~127 g bodyweight floor and must warn")
    }

    func testGoodMacrosProduceNoFloorWarnings() {
        // 2600 / 190p / 250c / 80f: above every floor, macro math within ~6%.
        let r = result(macros: macros(calories: 2600, protein: 190, carbs: 250, fat: 80))
        let report = validate(r)
        XCTAssertTrue(issues(report, field: "macroTargets.calories").isEmpty)
        XCTAssertTrue(issues(report, field: "macroTargets.proteinG").isEmpty)
        XCTAssertTrue(issues(report, field: "macroTargets.fatG").isEmpty)
    }

    // MARK: - #2 Sub-floor macros warn but never block the save

    func testLowMacrosAreWarningsNotSaveBlockingCriticals() {
        let r = result(macros: macros(calories: 900, protein: 40, carbs: 30, fat: 15))
        let report = validate(r)
        XCTAssertTrue(report.isUsable, "auto-clamped low macros must not block saving a good analysis")
        XCTAssertFalse(report.issues.contains { $0.severity == .critical },
                       "no macro value should ever be critical — the resolver clamps all of them")
        // But they are still surfaced so the user understands the clamp happened.
        XCTAssertFalse(issues(report, field: "macroTargets.calories").isEmpty)
    }

    func testEmptyOverallAssessmentStillBlocksSave() {
        let r = result(overall: "   ", macros: macros(calories: 2600, protein: 190, carbs: 250, fat: 80))
        let report = validate(r)
        XCTAssertFalse(report.isUsable, "empty overall assessment is genuinely unusable and must block the save")
        XCTAssertTrue(report.issues.contains { $0.severity == .critical && $0.field == "overallAssessment" })
    }

    // MARK: - #5 Case-insensitive priority matching

    func testLowercaseHighPriorityStillTriggersMissingBackPhotoWarning() {
        let backRegion = RegionAssessment(region: "Lats", assessment: "Width needs work.", priority: "high")
        let r = result(regions: [backRegion], macros: macros(calories: 2600, protein: 190, carbs: 250, fat: 80))
        // Front + side only — no back photo.
        let report = validate(r, angles: ["Front", "Side (Left)"])
        XCTAssertTrue(
            report.issues.contains { $0.field == "regionBreakdown" && $0.message.contains("Lats") },
            "a lowercase 'high' back region without a back photo must still warn"
        )
    }

    func testNonHighRegionDoesNotTriggerMissingAngleWarning() {
        let backRegion = RegionAssessment(region: "Lats", assessment: "Fine.", priority: "Low")
        let r = result(regions: [backRegion], macros: macros(calories: 2600, protein: 190, carbs: 250, fat: 80))
        let report = validate(r, angles: ["Front", "Side (Left)"])
        XCTAssertFalse(
            report.issues.contains { $0.field == "regionBreakdown" && $0.message.contains("Lats") },
            "a Low-priority region must not raise a missing-angle warning"
        )
    }

    // MARK: - #6 Diagnostic language net

    func testAssertiveDiagnosisIsFlagged() {
        let r = result(postural: "You clearly have scoliosis and need correction.",
                       macros: macros(calories: 2600, protein: 190, carbs: 250, fat: 80))
        let report = validate(r)
        XCTAssertTrue(
            report.issues.contains { $0.field == "posturalNotes" && $0.message.contains("Diagnostic language") },
            "an assertive diagnosis must be flagged"
        )
    }

    func testCautiousHedgedWordingIsNotFlagged() {
        let r = result(postural: "This may visually suggest a scoliosis-like curve; confirm with a professional if concerned.",
                       macros: macros(calories: 2600, protein: 190, carbs: 250, fat: 80))
        let report = validate(r)
        XCTAssertFalse(
            report.issues.contains { $0.field == "posturalNotes" && $0.message.contains("Diagnostic language") },
            "cautious hedged wording (which the prompt requires) must not be a false positive"
        )
    }
}
