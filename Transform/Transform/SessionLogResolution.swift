import Foundation

/// Which recorded session belongs to the workout card being looked at.
///
/// WHY THIS IS ITS OWN TYPE
/// -----------------------
/// The decision lived as one line inside `SetLoggingService`: match the log whose `loggedAt`
/// falls on the same calendar day as `.now`. That silently meant "the session being trained
/// right now", so opening a day already trained matched nothing and the card reported that
/// nothing had been logged — while the sets sat untouched in the database and rendered, one
/// panel lower, as "Last".
///
/// `SetLoggingService` lives in a SwiftUI file that the headless generator harness cannot
/// compile, and its inputs are SwiftData models. Pulling the choice out as arithmetic over
/// plain dates is what lets the rule that broke be pinned by a test at all.
enum SessionLogResolution {

    /// Index into `candidateDates` of the log holding this card's session, or `nil` when there
    /// are no candidates.
    ///
    /// - Parameters:
    ///   - candidateDates: `loggedAt` for each log already narrowed to this exercise and this
    ///     program day, in any order.
    ///   - sessionDates: the day's own session stamps, most authoritative first (end, then
    ///     start). Empty for a day that was never opened.
    ///   - viewingDate: the moment the card is being looked at — the last resort, and the only
    ///     one that applies while a brand-new session is being trained.
    ///
    /// Preference order is deliberate. The day's own stamps come first so a finished day
    /// resolves to the work done ON it. `viewingDate` follows, which is what makes a session
    /// being logged right now resolve before the clock has been stamped. Two stamps are
    /// consulted rather than one because a session running past midnight ends on a different
    /// calendar day than it started, and its later sets carry the later date.
    ///
    /// The final fallback — the most recent candidate — covers a day trained before the session
    /// clock existed, which has no date to match on. Showing that day's most recent recorded
    /// work beats reporting nothing, which is the failure this type exists to end. It is only
    /// reached when candidates exist but none lands on any preferred day, so it can never
    /// invent a session for a day that was never trained.
    static func indexOfSession(
        candidateDates: [Date],
        sessionDates: [Date],
        viewingDate: Date,
        calendar: Calendar = .current
    ) -> Int? {
        guard !candidateDates.isEmpty else { return nil }

        for preferred in sessionDates + [viewingDate] {
            if let hit = candidateDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: preferred) }) {
                return hit
            }
        }

        return candidateDates.indices.max { candidateDates[$0] < candidateDates[$1] }
    }

    /// The instant a card's "previous session" must fall strictly before: when THIS session
    /// began.
    ///
    /// Anchored to the session on screen, not to now. Anchoring to now was harmless only while a
    /// past day could not show its own sets: now that it can, a day trained three weeks ago
    /// would otherwise show last week's session as what came "last" — a reference from that
    /// day's future, sitting directly under a progression suggestion derived from it.
    ///
    /// EARLIEST marker, never a later one, because both later edges put this session's own sets
    /// back on screen as the previous session:
    ///
    ///  * `sessionDates` is ordered END-first, for `indexOfSession`, which wants the most
    ///    authoritative match. Anchoring here on the end stamp breaks a session that crossed
    ///    midnight — sets logged at 23:50 fall before the following day's midnight.
    ///  * A day predating the session clock has NO stamps, so the anchor would fall back to
    ///    today while its session legitimately resolves to a log dated weeks ago — which is
    ///    then, trivially, "before today". `currentSessionDate` is the truest marker of when
    ///    this session happened, and it exists precisely when the stamps do not.
    ///
    /// An INSTANT, and callers must compare instants. Rounding this to the start of its day —
    /// as an earlier version did — excludes the whole calendar date the session began on, not
    /// just the session itself. The same exercise legitimately appears on more than one program
    /// day, so a session trained at 18:00 and a second one starting at 23:45 that runs past
    /// midnight is a real shape, and the 18:00 session is a real previous session for the
    /// second card. Dropping it does not blank the panel — `.max` simply returns some older
    /// session instead — so the lifter is coached off numbers they have already beaten, which
    /// is the exact failure this chain of fixes exists to prevent.
    static func previousSessionCutoff(
        currentSessionDate: Date?,
        sessionDates: [Date],
        viewingDate: Date
    ) -> Date {
        (sessionDates + [currentSessionDate].compactMap { $0 }).min() ?? viewingDate
    }

    /// When work being recorded actually happened.
    ///
    /// Whether a log recorded at `logDate` can belong to the program a day is part of.
    ///
    /// `ExercisePerformanceLog.workoutDayNumber` is a bare integer with no program identity, so
    /// "day 11" of an archived program matches "day 11" of the current one. While sessions were
    /// resolved by "same calendar day as now" that collision was hidden by accident; once a day
    /// is matched by its own date it has to be excluded on purpose.
    ///
    /// A day carrying no program is unscopeable, and everything qualifies — the same answer as
    /// before program scoping existed, which is the only honest one when there is nothing to
    /// scope against.
    ///
    /// SCOPING TO A PROGRAM IS FOR SESSION IDENTITY ONLY. Exercise HISTORY is deliberately
    /// global: `ExerciseWeightStore.summary` and the previous-session lookup both key on the
    /// canonical exercise name alone, so a bench press from the last mesocycle still counts as
    /// what was lifted last time. Applying this filter there would break progression continuity
    /// across programs, which is the opposite of the goal.
    static func belongsToProgram(logDate: Date, programStart: Date?) -> Bool {
        guard let programStart else { return true }
        return logDate >= programStart
    }

    /// How far a session's last recorded activity can sit from a write and still count as the
    /// same session. Twelve hours covers any real workout, including one that runs past
    /// midnight, while staying far short of the gap to a day trained on another date.
    static let maximumLiveSessionGap: TimeInterval = 12 * 60 * 60

    /// Whether the day's session is the one happening right now, rather than a record being
    /// looked back at.
    ///
    /// Being open is necessary but NOT sufficient, which is the trap here: `isSessionClosed`
    /// defaults to false and `feedbackSubmittedAt` stays nil for any day that was trained and
    /// simply never rated or finished. Judged on open-ness alone, a workout from three weeks ago
    /// reads as "in progress" forever, and correcting one of its sets would restamp that work as
    /// today's — the exact corruption the live/finished distinction exists to prevent.
    ///
    /// Recency is what separates them, and it has to be recency rather than "is it today":
    /// a session that starts at 23:45 and runs past midnight is still the same workout while its
    /// stamps sit on yesterday's date.
    ///
    /// Genuinely absent evidence — no markers at all — means a session just beginning, which is
    /// a state that really does exist: the session clock is started BY the first logged set, so
    /// the first set of a workout is written before any stamp exists. Callers must therefore
    /// build `sessionDates` with `sessionMarkers(clockStamps:recordedLogDates:)`, not from the
    /// clock stamps alone, or a day whose clock never ran reads as brand new forever.
    static func sessionIsLive(
        dayIsOpen: Bool,
        sessionDates: [Date],
        writeDate: Date
    ) -> Bool {
        guard dayIsOpen else { return false }
        guard let lastActivity = sessionDates.max() else { return true }
        return abs(writeDate.timeIntervalSince(lastActivity)) <= maximumLiveSessionGap
    }

    /// Everything known about when a day's session actually happened, most authoritative first.
    ///
    /// The session clock is only ever written by set-logging done ON the day, so a day filled in
    /// afterwards through the bulk sheet ends up with real logged work and NO clock stamps. Read
    /// from the stamps alone such a day looks brand new forever — and "brand new" is the one
    /// state allowed to restamp work to now.
    ///
    /// The evidence has to be DAY-level, not per-exercise, which is the trap here. Protecting
    /// only the exercise being written leaves every OTHER exercise on that day unprotected: the
    /// first inline log on one of them sees no evidence, counts as live, files itself under
    /// today while its neighbours sit weeks earlier, and — because that write starts the day's
    /// clock — stamps today onto the day, at which point the neighbours become "live" too and
    /// the next correction to any of them overwrites their correct dates as well.
    ///
    /// `recordedLogDates` is consulted only when the clock said nothing. When stamps exist they
    /// describe the session's real window and stay authoritative, end-first.
    static func sessionMarkers(clockStamps: [Date], recordedLogDates: [Date]) -> [Date] {
        guard clockStamps.isEmpty else { return clockStamps }
        return recordedLogDates.max().map { [$0] } ?? []
    }

    /// `sessionIsLive` is the first question, before any date is compared. Work being done right now is stamped with the moment it happened, full
    /// stop. Only a session that has already finished reaches back to the day it was trained.
    ///
    /// With that settled, the remaining cases are:
    /// - `existingDate` nil — no log yet, so stamp it with the day's own session date. Filling
    ///   in a day trained last week records it on that day instead of opening a second session
    ///   dated today. With no session date either — a finished day predating the session clock —
    ///   `writeDate` is the last resort, and it is genuinely the only date available: nothing
    ///   recorded when that day was trained. It files old work under today, which is wrong but
    ///   unavoidable here; the bulk sheet's date picker is the way to correct it.
    /// - `existingDate` on `writeDate`'s own day — a correction to work done today. Advance.
    /// - otherwise — keep the existing stamp. Correcting one set must not restamp that work as
    ///   today's, which would falsify the history and make the "last session" panel treat an
    ///   old session as the current one.
    ///
    /// Calendar-day equality alone cannot stand in for `sessionIsLive`, in either branch. A
    /// session that starts at 23:45 and runs to 00:20 is STILL BEING TRAINED while its stamps
    /// sit on the previous calendar day: judged on dates, every set after midnight looks like a
    /// stale correction. An exercise already started would freeze — stalling the recorded
    /// duration halfway through the workout — and an exercise begun for the FIRST time after
    /// midnight would be stamped with the session's start day, landing two lifts from one
    /// continuous session on two different dates and backdating the later one's personal best.
    static func stamp(
        existingDate: Date?,
        sessionDates: [Date],
        writeDate: Date,
        sessionIsLive: Bool,
        calendar: Calendar = .current
    ) -> Date {
        if sessionIsLive { return writeDate }
        guard let existingDate else {
            return sessionDates.first ?? writeDate
        }
        return calendar.isDate(existingDate, inSameDayAs: writeDate) ? writeDate : existingDate
    }
}
