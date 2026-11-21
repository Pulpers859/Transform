import XCTest
@testable import Transform

/// Owner, 2026-11-21: keep the screen on between sets, but never hold it on for a session
/// that has gone quiet (a forgotten, unfinished day).
final class ScreenAwakePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func awake(started: TimeInterval?, ended: TimeInterval? = nil,
                       completed: Bool = false, closed: Bool = false) -> Bool {
        ScreenAwakePolicy.shouldKeepAwake(
            dayIsCompleted: completed, sessionIsClosed: closed,
            sessionStartedAt: started.map { now.addingTimeInterval(-$0) },
            sessionEndedAt: ended.map { now.addingTimeInterval(-$0) },
            now: now)
    }

    func testNoSessionMeansNormalLocking() {
        XCTAssertFalse(awake(started: nil))
    }

    func testActiveSessionKeepsTheScreenOn() {
        // Started 40 min ago, last set logged 2 min ago.
        XCTAssertTrue(awake(started: 40 * 60, ended: 2 * 60))
    }

    func testJustStartedTimerKeepsTheScreenOn() {
        XCTAssertTrue(awake(started: 30))
    }

    func testQuietSessionReleasesTheScreen() {
        XCTAssertTrue(awake(started: 60 * 60, ended: ScreenAwakePolicy.idleLimit))
        XCTAssertFalse(awake(started: 60 * 60, ended: ScreenAwakePolicy.idleLimit + 1))
    }

    func testFinishedOrClosedSessionReleasesTheScreen() {
        XCTAssertFalse(awake(started: 40 * 60, ended: 60, completed: true))
        XCTAssertFalse(awake(started: 40 * 60, ended: 60, closed: true))
    }

    func testAStampFarInTheFutureIsNotActivity() {
        XCTAssertFalse(awake(started: -3600))
    }
}
