import Foundation

// Structured sleep-recovery state and the tier policy that modulates generator volume.
//
// WHY THIS EXISTS
// ---------------
// The calibration pass previously recovered sleep numbers by regex-matching the derived
// prompt SUMMARY STRING (and that string never expired, so a weeks-old "post-call recovery"
// sentence could keep constraining generation forever — a silent-staleness bug). This file
// makes the recovery signal structured and dated: SleepTrendStore writes these numbers
// alongside the prose summary, and the generator consumes the numbers directly. The prose
// summary remains for prompts/analysis display only.
//
// Foundation-only on purpose: this file is part of the headless generator test package.

/// Dated, structured recovery inputs derived from logged sleep episodes.
/// Day counts and averages use the same wake-date windows as `SleepTrendBuilder`
/// (acute = last 3 days, chronic = last 7 days).
struct SleepRecoveryState: Codable, Equatable {
    let builtAt: Date
    let threeDayAverageHours: Double
    let sevenDayAverageHours: Double
    /// Wake-days with any logged sleep in the last 3 days.
    let acuteLoggedDays: Int
    /// Wake-days with any logged sleep in the last 7 days.
    let loggedDays: Int
    /// Wake-days totaling under 5 hours in the 7-day window.
    let daysUnderFive: Int
    /// Wake-days totaling under 6 hours in the 7-day window.
    let daysUnderSix: Int
    let variabilityHours: Double
    /// A post-call / recovery-sleep episode occurred within the last 3 days.
    let recentPostCall: Bool

    func encodedJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodedJSON(_ string: String?) -> SleepRecoveryState? {
        guard let string, !string.isEmpty, let data = string.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SleepRecoveryState.self, from: data)
    }
}

/// How recovery modulates the next generated program. EvidenceProfile.md SLEEP-001/SLEEP-002.
enum RecoveryTier: String, Codable {
    /// Fresh data, adequate sleep: full evidence-band volume targets.
    case ready
    /// Chronic mild shortfall or high variability: priority set targets capped at the
    /// midpoint of their evidence band; maintenance uses its constrained ceiling.
    case constrained
    /// Acute restriction (or post-call): priority set targets capped at the bottom of
    /// their evidence band, cut taken from back-off/accessory hard-set exposure;
    /// loads are NOT reduced.
    case restricted
    /// No fresh logged sleep to justify any adjustment. Volume targets are unchanged
    /// and the app says so — stale or missing data must never silently modulate.
    case insufficientData
}

struct RecoveryDecision: Equatable {
    let tier: RecoveryTier
    /// Human-readable inputs-and-rule line surfaced on the dashboard card and in the
    /// Generator Workshop dump so every applied tier is auditable.
    let audit: String
}

enum SleepRecoveryPolicy {
    /// Beyond this age the stored acute/chronic windows no longer describe the present.
    static let maxStateAgeDays = 3.0

    static func decision(from state: SleepRecoveryState?, now: Date = .now) -> RecoveryDecision {
        guard let state else {
            return RecoveryDecision(tier: .insufficientData, audit: "no sleep episodes logged")
        }
        let ageDays = now.timeIntervalSince(state.builtAt) / 86_400
        guard ageDays <= maxStateAgeDays else {
            return RecoveryDecision(
                tier: .insufficientData,
                audit: String(format: "sleep data stale — last updated %.0f days ago", ageDays)
            )
        }
        guard state.acuteLoggedDays > 0 else {
            return RecoveryDecision(tier: .insufficientData, audit: "no sleep logged in the last 3 days")
        }

        // Acute signals first: they are meaningful even with few logged days.
        if state.threeDayAverageHours < 6.0 {
            return RecoveryDecision(
                tier: .restricted,
                audit: String(
                    format: "3-day average %.1fh (<6h) across %d logged day(s)",
                    state.threeDayAverageHours, state.acuteLoggedDays
                )
            )
        }
        if state.daysUnderFive >= 2 {
            return RecoveryDecision(
                tier: .restricted,
                audit: "\(state.daysUnderFive) day(s) under 5h in the last week"
            )
        }
        if state.recentPostCall {
            return RecoveryDecision(tier: .restricted, audit: "post-call recovery within the last 3 days")
        }

        // Chronic signals need enough of the week logged to be an honest claim.
        guard state.loggedDays >= 3 else {
            return RecoveryDecision(
                tier: .insufficientData,
                audit: "only \(state.loggedDays) day(s) logged this week — not enough for a chronic volume adjustment"
            )
        }
        if state.sevenDayAverageHours < 7.0 {
            return RecoveryDecision(
                tier: .constrained,
                audit: String(
                    format: "7-day average %.1fh (<7h) across %d logged days",
                    state.sevenDayAverageHours, state.loggedDays
                )
            )
        }
        if state.variabilityHours >= 1.5 {
            return RecoveryDecision(
                tier: .constrained,
                audit: String(format: "high sleep variability (±%.1fh)", state.variabilityHours)
            )
        }
        return RecoveryDecision(
            tier: .ready,
            audit: String(
                format: "7-day average %.1fh, 3-day %.1fh, variability ±%.1fh",
                state.sevenDayAverageHours, state.threeDayAverageHours, state.variabilityHours
            )
        )
    }
}
