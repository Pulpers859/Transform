import Foundation

/// The rest countdown's rules, lifted out of `ExerciseRestTimerView` so they run headlessly.
///
/// Behavior is unchanged from the view-local `@State` it replaced: the same start, pause,
/// resume, reset and "a logged set starts rest only if the clock is sitting still" rules,
/// with `now` passed in instead of read from the wall clock. It was extracted because the
/// rest-over alert below must mirror this state exactly, and "exactly" is only provable by
/// driving the real transitions. Pinned by RestEndAlertTests.
struct RestTimerClock: Equatable {
    let restSeconds: Int
    private(set) var isActive = false
    private(set) var remainingSeconds: Int
    private(set) var didComplete = false
    /// Non-nil exactly while the clock is running.
    private(set) var endDate: Date?

    init(restSeconds: Int) {
        self.restSeconds = max(0, restSeconds)
        self.remainingSeconds = self.restSeconds
    }

    /// Paused part-way, or sitting at zero without having completed.
    var isPausedPartWay: Bool { !isActive && !didComplete && remainingSeconds != restSeconds }

    /// Pause when running, otherwise start (or resume) from what is left.
    /// Returns true when the tap started the clock.
    @discardableResult
    mutating func toggle(now: Date) -> Bool {
        if isActive {
            pause(now: now)
            return false
        }
        if didComplete {
            didComplete = false
            remainingSeconds = restSeconds
        }
        if remainingSeconds <= 0 || remainingSeconds > restSeconds {
            remainingSeconds = restSeconds
        }
        run(from: now)
        return true
    }

    mutating func pause(now: Date) {
        if let endDate {
            remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSince(now))))
        }
        endDate = nil
        isActive = false
    }

    mutating func reset(now: Date) {
        pause(now: now)
        didComplete = false
        remainingSeconds = restSeconds
    }

    /// A confirmed set starts a full rest only if the clock is sitting still. A countdown the
    /// lifter already started by hand is left alone; restarting it from the top was a bug.
    @discardableResult
    mutating func startAfterLoggedSet(now: Date) -> Bool {
        guard !isActive else { return false }
        didComplete = false
        remainingSeconds = restSeconds
        run(from: now)
        return true
    }

    /// Returns true exactly once per rest: on the tick that finds the end date passed.
    @discardableResult
    mutating func tick(now: Date) -> Bool {
        guard isActive, let endDate else { return false }
        let remaining = Int(ceil(endDate.timeIntervalSince(now)))
        if remaining > 0 {
            remainingSeconds = remaining
            return false
        }
        pause(now: now)
        remainingSeconds = 0
        didComplete = true
        return true
    }

    private mutating func run(from now: Date) {
        endDate = now.addingTimeInterval(Double(remainingSeconds))
        isActive = true
    }
}

/// Where a rest-over alert is actually delivered. The app passes the system notification
/// center (`RestEndNotificationCenter`); tests pass a recording fake.
protocol RestEndAlertCenter: AnyObject {
    func schedule(id: String, title: String, body: String, after seconds: TimeInterval)
    func cancel(ids: [String])
}

/// Keeps at most one pending "rest over" alert per exercise, always matching that exercise's
/// running clock.
///
/// Why it exists: the in-app buzz comes from a loop that iOS suspends when the phone locks, so
/// a locked phone used to give no signal at all. A scheduled local notification fires anyway,
/// and iOS forwards it to a paired Apple Watch while the phone is locked.
///
/// While the timer's own card is showing and ticking, the in-app buzz already covers the
/// moment, so the foreground banner is suppressed (`shouldPresentWhileAppIsOpen`). Leaving the
/// card (another tab, collapsing it, backing out) keeps the alert, because the rest is still
/// real; off the card the banner shows, because nothing else would.
///
/// A finished exercise never buzzes: logging its last set removes the card in the same pass
/// that starts its rest, and there is no next set to rest for.
@MainActor
final class RestEndAlerts {
    static let idPrefix = "transform.rest-end."
    static let title = "Rest over"

    private let center: RestEndAlertCenter
    /// End date of the alert currently pending for each id, so an unchanged clock never
    /// re-schedules (each schedule would otherwise replace the request needlessly).
    private(set) var pending: [String: Date] = [:]
    private var ticking: Set<String> = []
    private var finished: Set<String> = []

    init(center: RestEndAlertCenter) {
        self.center = center
    }

    static func id(for exerciseKey: String) -> String { idPrefix + exerciseKey }

    static func body(for exerciseName: String) -> String {
        let name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Time for your next set." : "Time for your next set of \(name)."
    }

    /// Make the pending alert match the clock: one alert at `clock.endDate` while running,
    /// none otherwise.
    func sync(exerciseKey: String, exerciseName: String, clock: RestTimerClock, now: Date) {
        let id = Self.id(for: exerciseKey)
        guard !finished.contains(exerciseKey), clock.isActive, let end = clock.endDate, end > now else {
            cancel(id)
            return
        }
        guard pending[id] != end else { return }
        pending[id] = end
        center.schedule(id: id, title: Self.title, body: Self.body(for: exerciseName),
                        after: end.timeIntervalSince(now))
    }

    func cancel(exerciseKey: String) {
        cancel(Self.id(for: exerciseKey))
    }

    /// The exercise was ticked off: clear its alert and refuse to re-arm it, whatever order
    /// the card's last state changes arrive in.
    func exerciseFinished(exerciseKey: String) {
        finished.insert(exerciseKey)
        cancel(exerciseKey: exerciseKey)
    }

    /// Un-ticked again (undo, or a reopened session); its timer may arm alerts again.
    func exerciseReopened(exerciseKey: String) {
        finished.remove(exerciseKey)
    }

    /// The system delivered (or is about to deliver) this alert; it is no longer pending.
    func delivered(id: String) {
        pending[id] = nil
    }

    func setTicking(_ isTicking: Bool, exerciseKey: String) {
        if isTicking { ticking.insert(exerciseKey) } else { ticking.remove(exerciseKey) }
    }

    /// Banner and sound only when the timer's own screen is not already buzzing for it.
    func shouldPresentWhileAppIsOpen(id: String) -> Bool {
        guard id.hasPrefix(Self.idPrefix) else { return true }
        return !ticking.contains(String(id.dropFirst(Self.idPrefix.count)))
    }

    private func cancel(_ id: String) {
        guard pending.removeValue(forKey: id) != nil else { return }
        center.cancel(ids: [id])
    }
}
