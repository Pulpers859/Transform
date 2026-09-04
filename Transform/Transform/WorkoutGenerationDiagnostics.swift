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

    // MARK: - Durable request log

    /// A bounded, on-device history of Anthropic request events.
    ///
    /// `AnthropicClient.logRequest` was a bare `print`. On the owner's phone nothing is attached to
    /// read stdout, so every diagnostic it emitted — the request profile, each retry with its
    /// reason and backoff, the failure category, the app-lifecycle state at the moment it broke —
    /// existed only for the instant it was written and then was gone. That is precisely the
    /// evidence needed to explain a generation failure after the fact, and the app was discarding
    /// all of it. A failure the owner reported could not be investigated, only guessed at.
    ///
    /// Writing here does NOT replace the `print`: in Xcode the console is still the fastest way to
    /// watch a live run. This is the copy that survives.
    ///
    /// Safe to persist, checked rather than assumed: `requestProfile` records the model name, byte
    /// and character COUNTS, timeout, feature/phase/week and tool name; the retry and failure
    /// events record attempt number, error category, normalized error text, backoff and lifecycle
    /// phase. No prompt text, no response content, no API key, and nothing the lifter typed.
    ///
    /// `UserDefaults` matches how the rest of this type already stores state, and the cap keeps it
    /// small — a few hundred short lines, trimmed oldest-first. It is diagnostics, not an audit
    /// trail: losing the tail on a crash is acceptable, silently losing everything is not.
    private static let requestLogKey = "workout_generation_request_log"

    /// Enough to hold several full generations including retries, since the interesting failures
    /// are the ones with a long attempt history behind them.
    static let requestLogCapacity = 300

    /// One event can carry a long normalized error string; bound it so a pathological message
    /// cannot crowd out the history around it, which is usually the more useful part.
    private static let requestLogLineLimit = 600

    /// Serialises the read-modify-write. Under the app's default MainActor isolation these calls
    /// already serialise, but the package build compiles this type without that isolation, and an
    /// append that loses entries under concurrency would quietly defeat the point of keeping them.
    private static let requestLogLock = NSLock()

    /// Where the log is stored. Production uses the standard domain; tests point it at a private
    /// suite instead.
    ///
    /// This seam exists because of a lesson already written down in this repo:
    /// `RecoveryModulationTests` notes that `swift test --parallel` runs test classes in SEPARATE
    /// PROCESSES that share one defaults plist, so a test writing stored state can race another
    /// test's fixture mid-run. An `NSLock` does nothing about that — it serialises one process's
    /// address space, not two. The first version of this log's tests wrote straight to
    /// `UserDefaults.standard` and re-made exactly the mistake that comment warns against.
    static var requestLogStore: UserDefaults = .standard

    static func recordRequestEvent(_ line: String) {
        // Newlines are flattened, not just trimmed at the edges. `requestLogText` joins entries
        // with "\n" and the log is explicitly meant to be pasted into a bug report, so one entry
        // must stay one line. Anthropic's HTTP error `message` is passed through only edge-trimmed
        // and can legitimately contain a newline, which would otherwise silently split one event
        // into two rows that each look like a separate request.
        let flattened = line
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let trimmed = flattened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let bounded = trimmed.count > requestLogLineLimit
            ? String(trimmed.prefix(requestLogLineLimit)) + "…"
            : trimmed

        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(bounded)"

        requestLogLock.lock()
        defer { requestLogLock.unlock() }

        var entries = requestLogStore.stringArray(forKey: requestLogKey) ?? []
        entries.append(stamped)
        if entries.count > requestLogCapacity {
            entries.removeFirst(entries.count - requestLogCapacity)
        }
        requestLogStore.set(entries, forKey: requestLogKey)
    }

    /// Oldest first, so the list reads as a timeline.
    static var recentRequestEvents: [String] {
        requestLogLock.lock()
        defer { requestLogLock.unlock() }
        return requestLogStore.stringArray(forKey: requestLogKey) ?? []
    }

    /// Ready to paste into a bug report.
    static var requestLogText: String {
        recentRequestEvents.joined(separator: "\n")
    }

    static func clearRequestLog() {
        requestLogLock.lock()
        defer { requestLogLock.unlock() }
        requestLogStore.removeObject(forKey: requestLogKey)
    }
}
