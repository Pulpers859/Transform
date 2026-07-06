import Foundation

enum WorkoutGenerationDiagnostics {
    private static let defaults = UserDefaults.standard
    private static let activeKey = "workout_generation_active"
    private static let stageKey = "workout_generation_stage"
    private static let startedAtKey = "workout_generation_started_at"
    private static let featureKey = "workout_generation_feature"

    static var bypassSanitization = false

    static var isActive: Bool {
        defaults.bool(forKey: activeKey)
    }

    /// The stage the in-flight generation last reported, for live progress UI.
    static var currentStageDescription: String? {
        guard defaults.bool(forKey: activeKey) else { return nil }
        return defaults.string(forKey: stageKey)
    }

    static func start(feature: String) {
        defaults.set(true, forKey: activeKey)
        defaults.set(feature, forKey: featureKey)
        defaults.set(Date().timeIntervalSince1970, forKey: startedAtKey)
        defaults.set("starting", forKey: stageKey)
    }

    static func markStage(_ stage: String) {
        guard defaults.bool(forKey: activeKey) else { return }
        defaults.set(stage, forKey: stageKey)
    }

    static func finish() {
        defaults.removeObject(forKey: activeKey)
        defaults.removeObject(forKey: stageKey)
        defaults.removeObject(forKey: startedAtKey)
        defaults.removeObject(forKey: featureKey)
    }

    static func consumeUnexpectedTerminationMessage() -> String? {
        guard defaults.bool(forKey: activeKey) else { return nil }

        let stage = defaults.string(forKey: stageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "an unknown stage"
        let feature = defaults.string(forKey: featureKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "AI workout generation"
        let startedAt = defaults.double(forKey: startedAtKey)
        let ageSeconds = max(0, Int(Date().timeIntervalSince1970 - startedAt))

        finish()

        return """
        The last \(feature) run did not finish cleanly and the app appears to have closed while it was in stage: \(stage).

        Approximate elapsed time before the app closed: \(ageSeconds) second(s).
        """
    }
}
