import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Whether the phone should be kept from auto-locking while a workout day is on screen.
///
/// Owner, 2026-11-21: the screen went to sleep between sets, so every set started with an
/// unlock. Keeping it awake for as long as a session is merely "open" would be wrong the
/// other way: a day is open from its first set until it is finished, and a lifter who walks
/// away without tapping Finish would leave the screen lit, draining the battery, for as long
/// as the day stays on screen. So the screen stays awake only while the session has seen
/// activity recently: its latest stamp (`sessionStartedAt`, or `sessionEndedAt`, which every
/// logged set pushes forward in `SessionLifecycle.noteSetLogged`) is within `idleLimit` of now.
/// Pinned by ScreenAwakePolicyTests.
enum ScreenAwakePolicy {
    /// Far longer than any rest the app accepts (the fallback plan uses up to 150 s and the
    /// validator accepts AI rest up to 240 s) plus a long set and a chat; short enough that a
    /// forgotten session stops holding the screen within the half hour. Heuristic, not measured.
    static let idleLimit: TimeInterval = 20 * 60

    static func shouldKeepAwake(
        dayIsCompleted: Bool,
        sessionIsClosed: Bool,
        sessionStartedAt: Date?,
        sessionEndedAt: Date?,
        now: Date
    ) -> Bool {
        guard !dayIsCompleted, !sessionIsClosed, let start = sessionStartedAt else { return false }
        let lastActivity = max(start, sessionEndedAt ?? start)
        let idle = now.timeIntervalSince(lastActivity)
        // A stamp in the future (clock change, edited times) is not "recent activity".
        return idle >= -60 && idle <= idleLimit
    }

    /// Applies the decision to the device. UIKit only; not covered by a test.
    @MainActor
    static func apply(_ keepAwake: Bool) {
        #if canImport(UIKit)
        if UIApplication.shared.isIdleTimerDisabled != keepAwake {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        #endif
    }
}
