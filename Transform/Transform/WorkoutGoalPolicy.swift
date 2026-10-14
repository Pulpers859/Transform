import Foundation

/// Saved with the analysis, not re-read from today's settings during continuation.
/// GOAL-001: the set-phase choice is a conservative app heuristic, not a clinical rule.
nonisolated struct WorkoutGoalPolicy: Codable, Equatable {
    static let currentVersion = "resistance_goals_v1"
    let version: String
    let modeID: String

    enum Mode: String {
        case muscleGain = "muscle_gain"
        case fatLoss = "fat_loss"
    }

    init(mode: Mode) {
        version = Self.currentVersion
        modeID = mode.rawValue
    }

    private enum CodingKeys: String, CodingKey { case version, modeID }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        version = (try? container?.decode(String.self, forKey: .version)) ?? "unreadable"
        modeID = (try? container?.decode(String.self, forKey: .modeID)) ?? "unreadable"
    }

    var mode: Mode? {
        guard version == Self.currentVersion else { return nil }
        return Mode(rawValue: modeID)
    }

    // Match only the explicit category written by composedGoalString, never words in
    // an assessment ("avoid a deficit" must not become a fat-loss instruction).
    static func capture(primaryGoal: String) -> Self? {
        let category = primaryGoal.components(separatedBy: " — ").first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch category {
        case "muscle gain": return Self(mode: .muscleGain)
        case "fat loss": return Self(mode: .fatLoss)
        default: return nil
        }
    }

    func setPhaseWeek(_ week: Int) -> Int {
        mode == .fatLoss && (2...3).contains(week) ? 1 : week
    }

    var auditDescription: String {
        guard let mode else { return "unsupported saved goal policy; legacy rules retained" }
        return "\(mode.rawValue) / \(Self.currentVersion)"
    }

    var coachingGuidance: String {
        switch mode {
        case .fatLoss:
            return "Fat-loss goal: retain muscle and training performance. Keep starting priority targets; Weeks 2-3 retain Week 1 role-set allowances instead of calendar-only additions. This does not guarantee identical weekly totals when exercises change. Keep exercise-appropriate reps, rest and performance-earned load progression; do not turn lifting into light-weight circuits. Maintaining performance can be a useful outcome. A goal is not proof of a calorie deficit or poor recovery."
        case .muscleGain:
            return "Muscle-building goal: pursue recoverable hypertrophy with the existing phased set allowances inside the shared budgets. Load and rep increases remain earned through logged performance, not guaranteed by the calendar or a calorie surplus."
        case nil:
            return "Unrecognized saved goal policy; retain legacy programming rather than inventing a new mode."
        }
    }

    var nutritionGuidance: String {
        guard mode != nil else { return "" }
        return "Saved training goal: \(auditDescription). " + (mode == .fatLoss
            ? "Support muscle retention and sustainable fat loss; lifting is not a substitute for nutrition. "
            : mode == .muscleGain ? "Support muscle growth without assuming a larger surplus is better. " : "")
        + "Honor the resolved calorie/protein targets and their source. Do not invent a deficit or surplus from the goal label or silently replace those targets."
    }
}
