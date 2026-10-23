import XCTest
@testable import Transform

/// Pins the rest countdown (`RestTimerClock`) and the rest-over alert that mirrors it
/// (`RestEndAlerts`). The alert exists so a locked phone, and through it a paired Apple Watch,
/// still signals the end of rest; the rule under test is that there is always exactly one
/// pending alert per running rest, at that rest's end time, and none otherwise.
@MainActor
final class RestEndAlertTests: XCTestCase {

    /// Behaves like the system center as far as these rules can see: one pending request per
    /// id (a new one replaces it), cancel removes it, and advancing time delivers what is due.
    final class FakeCenter: RestEndAlertCenter {
        var now: Date
        private(set) var pending: [String: Date] = [:]
        private(set) var delivered: [(id: String, at: Date)] = []
        private(set) var scheduleCalls = 0
        var lastBody: String?

        init(now: Date) { self.now = now }

        func schedule(id: String, title: String, body: String, after seconds: TimeInterval) {
            scheduleCalls += 1
            lastBody = body
            pending[id] = now.addingTimeInterval(seconds)
        }

        func cancel(ids: [String]) {
            ids.forEach { pending[$0] = nil }
        }

        func advance(to date: Date) {
            for (id, fire) in pending where fire <= date {
                delivered.append((id, fire))
                pending[id] = nil
            }
            now = date
        }
    }

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Clock: the rules the view used to hold, unchanged

    func testStartPauseResumeKeepsWhatIsLeft() {
        var clock = RestTimerClock(restSeconds: 90)
        XCTAssertTrue(clock.toggle(now: t0))
        XCTAssertEqual(clock.endDate, t0.addingTimeInterval(90))
        clock.tick(now: t0.addingTimeInterval(30.2))
        XCTAssertEqual(clock.remainingSeconds, 60, "ceil of 59.8")
        XCTAssertFalse(clock.toggle(now: t0.addingTimeInterval(30.2)), "second tap pauses")
        XCTAssertNil(clock.endDate)
        XCTAssertTrue(clock.isPausedPartWay)
        XCTAssertTrue(clock.toggle(now: t0.addingTimeInterval(100)))
        XCTAssertEqual(clock.endDate, t0.addingTimeInterval(160), "resumes with 60 s left, not 90")
    }

    func testALoggedSetLeavesARunningCountdownAlone() {
        var clock = RestTimerClock(restSeconds: 90)
        clock.toggle(now: t0)
        XCTAssertFalse(clock.startAfterLoggedSet(now: t0.addingTimeInterval(20)))
        XCTAssertEqual(clock.endDate, t0.addingTimeInterval(90))
    }

    func testALoggedSetStartsAFullRestFromPausedOrDone() {
        var clock = RestTimerClock(restSeconds: 90)
        clock.toggle(now: t0)
        clock.pause(now: t0.addingTimeInterval(50))
        XCTAssertTrue(clock.startAfterLoggedSet(now: t0.addingTimeInterval(60)))
        XCTAssertEqual(clock.endDate, t0.addingTimeInterval(150), "full 90 s, not the 40 left")
    }

    func testCompletionIsReportedExactlyOnce() {
        var clock = RestTimerClock(restSeconds: 60)
        clock.toggle(now: t0)
        XCTAssertFalse(clock.tick(now: t0.addingTimeInterval(59.5)))
        XCTAssertTrue(clock.tick(now: t0.addingTimeInterval(60)))
        XCTAssertFalse(clock.tick(now: t0.addingTimeInterval(61)))
        XCTAssertTrue(clock.didComplete)
        XCTAssertEqual(clock.remainingSeconds, 0)
        XCTAssertTrue(clock.toggle(now: t0.addingTimeInterval(70)), "a tap after completion starts a fresh rest")
        XCTAssertEqual(clock.endDate, t0.addingTimeInterval(130))
    }

    func testResetReturnsToTheFullRest() {
        var clock = RestTimerClock(restSeconds: 60)
        clock.toggle(now: t0)
        clock.reset(now: t0.addingTimeInterval(10))
        XCTAssertEqual(clock, RestTimerClock(restSeconds: 60))
    }

    // MARK: - Alert follows the clock

    func testAlertIsArmedAtTheEndOfRestAndClearedByPause() {
        let center = FakeCenter(now: t0)
        let alerts = RestEndAlerts(center: center)
        var clock = RestTimerClock(restSeconds: 90)
        clock.toggle(now: t0)
        alerts.sync(exerciseKey: "a", exerciseName: "Leg Press", clock: clock, now: t0)
        XCTAssertEqual(center.pending[RestEndAlerts.id(for: "a")], t0.addingTimeInterval(90))
        XCTAssertEqual(center.lastBody, "Time for your next set of Leg Press.")

        clock.tick(now: t0.addingTimeInterval(5))
        alerts.sync(exerciseKey: "a", exerciseName: "Leg Press", clock: clock, now: t0.addingTimeInterval(5))
        XCTAssertEqual(center.scheduleCalls, 1, "a tick does not move the end, so nothing is re-armed")

        clock.pause(now: t0.addingTimeInterval(10))
        alerts.sync(exerciseKey: "a", exerciseName: "Leg Press", clock: clock, now: t0.addingTimeInterval(10))
        XCTAssertTrue(center.pending.isEmpty, "a paused rest must not buzz")
    }

    func testBannerIsHiddenOnlyWhileTheTimerScreenIsBuzzingItself() {
        let alerts = RestEndAlerts(center: FakeCenter(now: t0))
        let id = RestEndAlerts.id(for: "a")
        XCTAssertTrue(alerts.shouldPresentWhileAppIsOpen(id: id))
        alerts.setTicking(true, exerciseKey: "a")
        XCTAssertFalse(alerts.shouldPresentWhileAppIsOpen(id: id))
        XCTAssertTrue(alerts.shouldPresentWhileAppIsOpen(id: RestEndAlerts.id(for: "b")))
        XCTAssertTrue(alerts.shouldPresentWhileAppIsOpen(id: "something.else"))
        alerts.setTicking(false, exerciseKey: "a")
        XCTAssertTrue(alerts.shouldPresentWhileAppIsOpen(id: id))
    }

    // MARK: - Stress: random workouts against the real rules

    /// Drives three exercise timers through 20,000 random taps, logged sets, ticks, leaving and
    /// returning to the screen, and jumps in time (including long gaps with no ticks, which is
    /// what a locked phone looks like). The alert is synced only when the clock changes, the
    /// same trigger the view uses (`onChange(of: clock)`), plus on appear.
    ///
    /// Checked after every step:
    ///   * a pending alert exists exactly when that card is on screen and its rest is running
    ///     with time left, and it fires at that rest's end;
    ///   * every delivered alert belongs to a rest that was still running to that same end
    ///     (nothing buzzes for a paused, reset or abandoned rest);
    ///   * no rest is delivered twice, and every on-screen rest that runs out is delivered.
    func testRandomWorkoutsNeverLeaveAWrongOrMissingAlert() {
        var rng = RestWalkGenerator(seed: 0x5EED_2026)
        var now = t0
        let center = FakeCenter(now: t0)
        let alerts = RestEndAlerts(center: center)
        let keys = ["a", "b", "c"]
        var clocks: [String: RestTimerClock] = [
            "a": RestTimerClock(restSeconds: 90),
            "b": RestTimerClock(restSeconds: 150),
            "c": RestTimerClock(restSeconds: 30)
        ]
        var onScreen: [String: Bool] = ["a": true, "b": true, "c": true]
        var deliveredEnds: Set<String> = []
        var completions = 0

        func syncIfChanged(_ key: String, from before: RestTimerClock) {
            guard onScreen[key] == true, clocks[key] != before else { return }
            alerts.sync(exerciseKey: key, exerciseName: key, clock: clocks[key]!, now: now)
        }

        for step in 0..<20_000 {
            let key = keys[Int.random(in: 0..<keys.count, using: &rng)]
            let before = clocks[key]!
            switch Int.random(in: 0..<100, using: &rng) {
            case 0..<15:
                clocks[key]!.toggle(now: now)
                syncIfChanged(key, from: before)
            case 15..<27:
                clocks[key]!.startAfterLoggedSet(now: now)
                syncIfChanged(key, from: before)
            case 27..<32:
                clocks[key]!.reset(now: now)
                syncIfChanged(key, from: before)
            case 32..<36:
                if onScreen[key] == true {
                    onScreen[key] = false
                    alerts.cancel(exerciseKey: key)
                }
            case 36..<40:
                if onScreen[key] == false {
                    onScreen[key] = true
                    alerts.sync(exerciseKey: key, exerciseName: key, clock: clocks[key]!, now: now)
                }
            case 40..<70:
                if clocks[key]!.tick(now: now) { completions += 1 }
                syncIfChanged(key, from: before)
            default:
                // Mostly short steps, sometimes a long locked-phone gap.
                let gap = Int.random(in: 0..<10, using: &rng) == 0
                    ? Double.random(in: 60...400, using: &rng)
                    : Double.random(in: 0.1...8, using: &rng)
                let previous = now
                now = now.addingTimeInterval(gap)
                // Rests that run out inside this gap while their card is on screen.
                let mustBuzz = keys.compactMap { k -> String? in
                    guard onScreen[k] == true, let end = clocks[k]!.endDate,
                          end > previous, end <= now else { return nil }
                    return "\(k)@\(end.timeIntervalSinceReferenceDate)"
                }
                let deliveredBefore = center.delivered.count
                center.advance(to: now)
                for delivery in center.delivered[deliveredBefore...] {
                    let k = String(delivery.id.dropFirst(RestEndAlerts.idPrefix.count))
                    let clock = clocks[k]!
                    XCTAssertTrue(clock.isActive, "step \(step): alert for a rest that is not running")
                    guard let end = clock.endDate else { continue }
                    // The center is told "in N seconds", so allow for floating-point rounding.
                    XCTAssertEqual(end.timeIntervalSinceReferenceDate, delivery.at.timeIntervalSinceReferenceDate,
                                   accuracy: 0.001, "step \(step): alert fired at the wrong time")
                    let tag = "\(k)@\(end.timeIntervalSinceReferenceDate)"
                    XCTAssertFalse(deliveredEnds.contains(tag), "step \(step): one rest buzzed twice")
                    deliveredEnds.insert(tag)
                    // The app only hears about a delivery when it is open; half the time it does not.
                    if Bool.random(using: &rng) { alerts.delivered(id: delivery.id) }
                }
                for tag in mustBuzz {
                    XCTAssertTrue(deliveredEnds.contains(tag), "step \(step): a rest ran out with no alert")
                }
            }

            for k in keys {
                let clock = clocks[k]!
                let shouldBePending = onScreen[k] == true && clock.isActive && clock.endDate! > now
                let pending = center.pending[RestEndAlerts.id(for: k)]
                if shouldBePending, let end = clock.endDate {
                    XCTAssertEqual(pending?.timeIntervalSinceReferenceDate ?? -1, end.timeIntervalSinceReferenceDate,
                                   accuracy: 0.001, "step \(step): \(k) running without the right alert")
                } else {
                    XCTAssertNil(pending, "step \(step): \(k) has an alert but no running rest")
                }
            }
            if testRun?.failureCount ?? 0 > 0 { return }
        }
        XCTAssertGreaterThan(deliveredEnds.count, 100, "the walk must actually exercise deliveries")
        XCTAssertGreaterThan(completions, 100, "the walk must actually exercise completions")
    }
}

/// Small deterministic generator so the stress walk is the same on every run.
struct RestWalkGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
