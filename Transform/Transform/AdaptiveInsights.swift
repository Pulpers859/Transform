import Foundation

enum WeightTrendDataQuality: String {
    case insufficient = "Insufficient"
    case limited = "Limited"
    case moderate = "Moderate"
    case good = "Good"
}

struct SmoothedWeightPoint: Identifiable {
    let date: Date
    let rawWeightLbs: Double
    let trendWeightLbs: Double

    var id: Date { date }
}

struct WeightTrendSnapshot {
    let points: [SmoothedWeightPoint]
    let loggedDays: Int
    let elapsedDays: Int
    let currentRawWeightLbs: Double?
    let currentTrendWeightLbs: Double?
    let weeklyChangeLbs: Double?
    let weeklyChangePct: Double?
    let dataQuality: WeightTrendDataQuality

    var hasReliableTrend: Bool {
        dataQuality == .moderate || dataQuality == .good
    }
}

enum WeightTrendBuilder {
    static func build(from input: [AnalysisLoggedWeightPoint], calendar: Calendar = .current) -> WeightTrendSnapshot {
        let daily = Dictionary(grouping: input.filter { $0.weightLbs > 0 }) {
            calendar.startOfDay(for: $0.date)
        }
        .compactMap { day, points -> AnalysisLoggedWeightPoint? in
            guard let latest = points.max(by: { $0.date < $1.date }) else { return nil }
            return AnalysisLoggedWeightPoint(date: day, weightLbs: latest.weightLbs)
        }
        .sorted { $0.date < $1.date }

        let smoothed = daily.map { point in
            let windowStart = calendar.date(byAdding: .day, value: -6, to: point.date) ?? point.date
            let window = daily.filter { $0.date >= windowStart && $0.date <= point.date }
            let average = window.reduce(0.0) { $0 + $1.weightLbs } / Double(max(window.count, 1))
            return SmoothedWeightPoint(
                date: point.date,
                rawWeightLbs: point.weightLbs,
                trendWeightLbs: average
            )
        }

        let elapsedDays: Int
        if let first = daily.first, let last = daily.last {
            elapsedDays = max(calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0, 0)
        } else {
            elapsedDays = 0
        }

        let current = smoothed.last
        let comparisonDate = current.flatMap {
            calendar.date(byAdding: .day, value: -7, to: $0.date)
        }
        let prior = comparisonDate.flatMap { target in
            smoothed.last(where: { $0.date <= target })
        }
        let weeklyChange: Double? = if let current, let prior {
            current.trendWeightLbs - prior.trendWeightLbs
        } else {
            nil
        }
        let weeklyPct: Double? = if let weeklyChange, let current, current.trendWeightLbs > 0 {
            weeklyChange / current.trendWeightLbs * 100
        } else {
            nil
        }

        let quality: WeightTrendDataQuality
        if daily.count < 3 || elapsedDays < 3 {
            quality = .insufficient
        } else if daily.count < 6 || elapsedDays < 7 {
            quality = .limited
        } else if daily.count < 10 || elapsedDays < 14 {
            quality = .moderate
        } else {
            quality = .good
        }

        return WeightTrendSnapshot(
            points: smoothed,
            loggedDays: daily.count,
            elapsedDays: elapsedDays,
            currentRawWeightLbs: current?.rawWeightLbs,
            currentTrendWeightLbs: current?.trendWeightLbs,
            weeklyChangeLbs: weeklyChange,
            weeklyChangePct: weeklyPct,
            dataQuality: quality
        )
    }
}

struct AdaptiveMacroOverride: Codable {
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

enum AdaptiveMacroRecommendation: String, Codable, CaseIterable {
    case maintain = "Maintain"
    case reduceCalories = "Reduce calories"
    case increaseCalories = "Increase calories"
    case proteinFirst = "Protein first"
    case carbTiming = "Carb timing"
    case adherenceFirst = "Adherence first"
}

struct AdaptiveMacroReview: Codable {
    let recommendation: AdaptiveMacroRecommendation
    let headline: String
    let rationale: String
    let proposedCalories: Int
    let proposedProteinG: Double
    let proposedCarbsG: Double
    let proposedFatG: Double
    let confidence: String

    var proposedOverride: AdaptiveMacroOverride {
        AdaptiveMacroOverride(
            calories: proposedCalories,
            proteinG: proposedProteinG,
            carbsG: proposedCarbsG,
            fatG: proposedFatG
        )
    }
}

struct AdaptiveMacroReviewGate {
    let isEligible: Bool
    let unmetRequirements: [String]

    static func evaluate(
        weightTrend: WeightTrendSnapshot,
        adherence: NutritionAdherenceMetrics,
        measurementTrend: MeasurementTrendSnapshot?,
        lastReviewDate: Date? = nil,
        now: Date = .now
    ) -> AdaptiveMacroReviewGate {
        var unmet: [String] = []
        if let lastReviewDate {
            let daysSinceReview = Calendar.current.dateComponents(
                [.day],
                from: lastReviewDate,
                to: now
            ).day ?? 0
            if daysSinceReview < 7 {
                unmet.append("7 days since the previous macro review")
            }
        }
        if weightTrend.elapsedDays < 14 { unmet.append("14 days of weight trend history") }
        if weightTrend.loggedDays < 8 { unmet.append("8 weight-log days") }
        if adherence.validDays < 7 { unmet.append("7 complete nutrition-log days") }
        if (adherence.calorieHitRate ?? 0) < 0.5 { unmet.append("reasonable calorie adherence") }
        if measurementTrend?.progressConfidence != .moderate && measurementTrend?.progressConfidence != .high {
            unmet.append("moderate-confidence measurements")
        }
        return AdaptiveMacroReviewGate(isEligible: unmet.isEmpty, unmetRequirements: unmet)
    }
}

extension ClaudeService {
    func generateAdaptiveMacroReview(
        currentTargets: DailyMacroTargets,
        weightTrend: WeightTrendSnapshot,
        adherence: NutritionAdherenceMetrics,
        measurementTrend: MeasurementTrendSnapshot
    ) async throws -> AdaptiveMacroReview {
        let toolName = "emit_macro_review"
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "recommendation": [
                    "type": "string",
                    "enum": AdaptiveMacroRecommendation.allCases.map(\.rawValue)
                ],
                "headline": ["type": "string"],
                "rationale": ["type": "string"],
                "proposedCalories": ["type": "integer", "minimum": 1000, "maximum": 5000],
                "proposedProteinG": ["type": "number", "minimum": 60, "maximum": 400],
                "proposedCarbsG": ["type": "number", "minimum": 50, "maximum": 600],
                "proposedFatG": ["type": "number", "minimum": 20, "maximum": 250],
                "confidence": ["type": "string", "enum": ["Moderate", "High"]]
            ],
            "required": [
                "recommendation", "headline", "rationale", "proposedCalories",
                "proposedProteinG", "proposedCarbsG", "proposedFatG", "confidence"
            ]
        ]
        let system = """
        You are a conservative sports-nutrition review panel. Review established trend data,
        not single weigh-ins. Never reward poor adherence with false precision. Recommend either
        no change, an adherence/protein/carb-timing intervention, or a small calorie change.
        Any calorie adjustment must be 100-150 kcal. Preserve protein unless it is clearly low.
        Call the tool and do not return free text.
        """
        let user = """
        Current targets: \(currentTargets.calories) kcal, \(Int(currentTargets.proteinG)) g protein,
        \(Int(currentTargets.carbsG)) g carbs, \(Int(currentTargets.fatG)) g fat.
        Smoothed weight: \(weightTrend.currentTrendWeightLbs.map { String(format: "%.1f", $0) } ?? "unknown") lb.
        Weekly trend: \(weightTrend.weeklyChangeLbs.map { String(format: "%+.2f", $0) } ?? "unknown") lb/week.
        Weight data: \(weightTrend.loggedDays) days over \(weightTrend.elapsedDays) elapsed days; quality \(weightTrend.dataQuality.rawValue).
        Nutrition: \(adherence.validDays) valid days, calorie hit rate \(Int((adherence.calorieHitRate ?? 0) * 100))%,
        protein hit rate \(Int((adherence.proteinHitRate ?? 0) * 100))%.
        Measurements: \(measurementTrend.interpretation.rawValue), confidence \(measurementTrend.progressConfidence.rawValue),
        waist change \(measurementTrend.waistChangeIn.map { String(format: "%+.2f", $0) } ?? "unknown") in.
        """
        let body: [String: Any] = [
            "model": Config.claudeModelLite,
            "max_tokens": 1400,
            "system": system,
            "tools": [[
                "name": toolName,
                "description": "Emit a conservative adaptive macro review.",
                "input_schema": schema
            ]],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [["role": "user", "content": user]]
        ]
        let json = try await AnthropicClient.shared.sendStructuredRequest(
            body: body,
            toolName: toolName,
            timeout: 90
        )
        let decoded = try JSONDecoder().decode(AdaptiveMacroReview.self, from: Data(json.utf8))
        return try validateAdaptiveMacroReview(decoded, currentTargets: currentTargets)
    }

    private func validateAdaptiveMacroReview(
        _ review: AdaptiveMacroReview,
        currentTargets: DailyMacroTargets
    ) throws -> AdaptiveMacroReview {
        let calorieDelta = review.proposedCalories - currentTargets.calories
        let changesCalories = review.recommendation == .reduceCalories || review.recommendation == .increaseCalories
        if changesCalories && !(100...150).contains(abs(calorieDelta)) {
            throw ClaudeError.parseError("Macro review proposed an unsafe calorie adjustment.")
        }
        if !changesCalories && abs(calorieDelta) > 25 {
            throw ClaudeError.parseError("Macro review changed calories despite a non-calorie recommendation.")
        }
        if abs(review.proposedProteinG - currentTargets.proteinG) > 25 {
            throw ClaudeError.parseError("Macro review changed protein too aggressively.")
        }
        if abs(review.proposedCarbsG - currentTargets.carbsG) > 40 {
            throw ClaudeError.parseError("Macro review changed carbohydrates too aggressively.")
        }
        if abs(review.proposedFatG - currentTargets.fatG) > 15 {
            throw ClaudeError.parseError("Macro review changed fat too aggressively.")
        }
        let macroCalories = review.proposedProteinG * 4
            + review.proposedCarbsG * 4
            + review.proposedFatG * 9
        if abs(macroCalories - Double(review.proposedCalories)) > 150 {
            throw ClaudeError.parseError("Macro review calories and macros are internally inconsistent.")
        }
        return review
    }
}
