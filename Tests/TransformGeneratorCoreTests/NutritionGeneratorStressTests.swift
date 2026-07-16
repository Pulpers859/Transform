import XCTest
@testable import Transform

/// Network-free nutrition quality and fallback stress tests.
///
/// These tests intentionally exercise malformed, low, high, and internally inconsistent
/// macro targets. A nutrition response that merely decodes is not good enough: meal math,
/// day-level totals, safety floors, meal identity, and grocery usability must agree.
@MainActor
final class NutritionGeneratorStressTests: XCTestCase {
    private let service = ClaudeService.shared

    func testFallbackStressMatrixPreservesSafetyAndArithmetic() {
        let cases: [(String, AnalysisMacroTargets)] = [
            ("low", AnalysisMacroTargets(calories: 1000, proteinG: 40, carbsG: 10, fatG: 10)),
            ("inconsistent", AnalysisMacroTargets(calories: 2000, proteinG: 300, carbsG: 400, fatG: 150)),
            ("standard", AnalysisMacroTargets(calories: 2200, proteinG: 190, carbsG: 220, fatG: 65)),
            ("high", AnalysisMacroTargets(calories: 3600, proteinG: 260, carbsG: 420, fatG: 110)),
            ("upper-bound", AnalysisMacroTargets(calories: 5000, proteinG: 350, carbsG: 600, fatG: 150)),
            ("macro-ceiling", AnalysisMacroTargets(calories: 5000, proteinG: 400, carbsG: 600, fatG: 250))
        ]

        for (label, macros) in cases {
            let analysis = nutritionAnalysis(macros: macros)
            let week = service.buildFallbackNutritionWeek(weekNumber: 1, from: analysis, diagnostic: "stress \(label)")
            let targets = service.effectiveNutritionTargets(from: analysis)
            let macroCalories = Int((targets.proteinG * 4 + targets.carbsG * 4 + targets.fatG * 9).rounded())

            XCTAssertTrue((1000...5000).contains(week.dailyCaloriesTraining), label)
            XCTAssertTrue((60...400).contains(week.dailyProteinG), label)
            XCTAssertTrue((20...250).contains(week.dailyFatG), label)
            XCTAssertTrue((30...600).contains(week.dailyCarbsGTraining), label)
            XCTAssertGreaterThan(week.dailyCarbsGTraining, week.dailyCarbsGRest, label)
            XCTAssertEqual(targets.carbsG, targets.carbsG.rounded(), label)
            XCTAssertEqual(targets.calories, macroCalories, label)

            assertTemplateArithmetic(week.trainingDay, label: "\(label) training")
            assertTemplateArithmetic(week.restDay, label: "\(label) rest")
            XCTAssertEqual(week.trainingDay.meals.reduce(0) { $0 + $1.approxProteinG }, week.trainingDay.totalProteinG, label)
            XCTAssertEqual(week.restDay.meals.reduce(0) { $0 + $1.approxProteinG }, week.restDay.totalProteinG, label)

            let issues = service.validateNutritionWeek(week, expectedWeek: 1, macroTargets: targets)
            XCTAssertTrue(issues.isEmpty, "Fallback \(label) should be internally valid: \(issues)")
        }
    }

    func testMissingMacrosUseConfiguredSafeTargetAndSourceSurvivesPersistence() throws {
        let analysis = nutritionAnalysis(macros: nil)
        let week = service.buildFallbackNutritionWeek(weekNumber: 1, from: analysis, diagnostic: "missing macros")
        let targets = service.effectiveNutritionTargets(from: analysis)

        XCTAssertEqual(week.source, .recoveryEngine)
        XCTAssertTrue((1000...5000).contains(week.dailyCaloriesTraining))
        XCTAssertEqual(week.dailyProteinG, Int(targets.proteinG.rounded()))
        XCTAssertEqual(week.dailyFatG, Int(targets.fatG.rounded()))

        let data = try JSONEncoder().encode(week)
        let decoded = try JSONDecoder().decode(NutritionWeekResponse.self, from: data)
        XCTAssertEqual(decoded.source, .recoveryEngine)
        XCTAssertEqual(decoded.weekNumber, week.weekNumber)
    }

    func testValidatorCatchesCarbFatAndMacroMathDrift() {
        let analysis = nutritionAnalysis(
            macros: AnalysisMacroTargets(calories: 2200, proteinG: 190, carbsG: 220, fatG: 65)
        )
        let baseline = service.buildFallbackNutritionWeek(weekNumber: 1, from: analysis, diagnostic: "baseline")
        let firstMeal = baseline.trainingDay.meals[0]
        let badFirstMeal = MealSlotResponse(
            mealName: firstMeal.mealName,
            primaryOption: firstMeal.primaryOption,
            substitutions: firstMeal.substitutions,
            approxCalories: firstMeal.approxCalories,
            approxProteinG: firstMeal.approxProteinG,
            approxCarbsG: firstMeal.approxCarbsG + 100,
            approxFatG: firstMeal.approxFatG + 20,
            timingNote: firstMeal.timingNote
        )
        let badTraining = DailyNutritionTemplate(
            label: baseline.trainingDay.label,
            totalCalories: baseline.trainingDay.totalCalories,
            totalProteinG: baseline.trainingDay.totalProteinG,
            totalCarbsG: baseline.trainingDay.totalCarbsG,
            totalFatG: baseline.trainingDay.totalFatG,
            meals: [badFirstMeal] + Array(baseline.trainingDay.meals.dropFirst())
        )
        let badWeek = NutritionWeekResponse(
            weekNumber: baseline.weekNumber,
            weekSummary: baseline.weekSummary,
            phaseFocus: baseline.phaseFocus,
            coachNotes: baseline.coachNotes,
            dailyCaloriesTraining: baseline.dailyCaloriesTraining,
            dailyCaloriesRest: baseline.dailyCaloriesRest,
            dailyProteinG: baseline.dailyProteinG,
            dailyCarbsGTraining: baseline.dailyCarbsGTraining,
            dailyCarbsGRest: baseline.dailyCarbsGRest,
            dailyFatG: baseline.dailyFatG,
            trainingDay: badTraining,
            restDay: baseline.restDay,
            weeklyGrocery: baseline.weeklyGrocery
        )

        let issues = service.validateNutritionWeek(
            badWeek,
            expectedWeek: 1,
            macroTargets: service.effectiveNutritionTargets(from: analysis)
        )

        XCTAssertTrue(issues.contains { $0.contains("meal carb sum") })
        XCTAssertTrue(issues.contains { $0.contains("meal fat sum") })
        XCTAssertTrue(issues.contains { $0.contains("macro-derived calories") })
    }

    func testValidatorRequiresOrderedMealsAndUsableSubstitutions() {
        let analysis = nutritionAnalysis(
            macros: AnalysisMacroTargets(calories: 2200, proteinG: 190, carbsG: 220, fatG: 65)
        )
        let baseline = service.buildFallbackNutritionWeek(weekNumber: 1, from: analysis, diagnostic: "baseline")
        let meals = baseline.restDay.meals.enumerated().map { index, meal in
            MealSlotResponse(
                mealName: index == 0 ? "Dinner" : meal.mealName,
                primaryOption: meal.primaryOption,
                substitutions: [],
                approxCalories: meal.approxCalories,
                approxProteinG: meal.approxProteinG,
                approxCarbsG: meal.approxCarbsG,
                approxFatG: meal.approxFatG,
                timingNote: meal.timingNote
            )
        }
        let badRest = DailyNutritionTemplate(
            label: baseline.restDay.label,
            totalCalories: baseline.restDay.totalCalories,
            totalProteinG: baseline.restDay.totalProteinG,
            totalCarbsG: baseline.restDay.totalCarbsG,
            totalFatG: baseline.restDay.totalFatG,
            meals: meals
        )
        let badWeek = NutritionWeekResponse(
            weekNumber: baseline.weekNumber,
            weekSummary: baseline.weekSummary,
            phaseFocus: baseline.phaseFocus,
            coachNotes: baseline.coachNotes,
            dailyCaloriesTraining: baseline.dailyCaloriesTraining,
            dailyCaloriesRest: baseline.dailyCaloriesRest,
            dailyProteinG: baseline.dailyProteinG,
            dailyCarbsGTraining: baseline.dailyCarbsGTraining,
            dailyCarbsGRest: baseline.dailyCarbsGRest,
            dailyFatG: baseline.dailyFatG,
            trainingDay: baseline.trainingDay,
            restDay: badRest,
            weeklyGrocery: baseline.weeklyGrocery
        )

        let issues = service.validateNutritionWeek(
            badWeek,
            expectedWeek: 1,
            macroTargets: service.effectiveNutritionTargets(from: analysis)
        )

        XCTAssertTrue(issues.contains { $0.contains("position 1 should be Breakfast") })
        XCTAssertGreaterThanOrEqual(issues.filter { $0.contains("must include 2-3 practical substitutions") }.count, 4)
    }

    private func assertTemplateArithmetic(_ template: DailyNutritionTemplate, label: String) {
        XCTAssertEqual(template.meals.reduce(0) { $0 + $1.approxCalories }, template.totalCalories, label)
        XCTAssertEqual(template.meals.reduce(0) { $0 + $1.approxProteinG }, template.totalProteinG, label)
        XCTAssertEqual(template.meals.reduce(0) { $0 + $1.approxCarbsG }, template.totalCarbsG, label)
        XCTAssertEqual(template.meals.reduce(0) { $0 + $1.approxFatG }, template.totalFatG, label)
    }

    private func nutritionAnalysis(macros: AnalysisMacroTargets?) -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: "Synthetic nutrition stress fixture.",
            trainingAssessment: "Maintain recoverable resistance training.",
            nutritionAssessment: "Nutrition target stress case.",
            recoveryRiskAssessment: "No additional risk supplied.",
            adherenceAssessment: "Adherence is unknown.",
            analysisLimitations: "Synthetic test input.",
            inputContext: nil,
            regionBreakdown: [],
            topLeverageChange: "Follow the resolved plan consistently.",
            priorityMuscles: ["Upper Chest"],
            workoutRecommendations: [],
            dietRecommendations: ["Use simple repeatable meals."],
            posturalNotes: "",
            estimatedBodyFat: "",
            metabolicHealthNotes: "",
            psychologicalInsights: "",
            injuryRiskNotes: "",
            macroTargets: macros,
            structuredTrainingIntent: nil
        )
    }
}
