import XCTest
@testable import Transform

/// A card asked for "the sets logged today" and was handed that question for every day it
/// showed, including days trained weeks earlier. Those days reported "0/3", "Marked done with
/// no sets logged" and "Done · nothing logged" while their sets sat untouched in the database.
///
/// These pin the resolution that replaced it.
final class SessionLogResolutionTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    // MARK: - The reported bug

    /// THE regression. A day trained on the 11th, opened on the 17th, must resolve to the 11th's
    /// session — not to nothing.
    ///
    /// Deliberately NOT a single-candidate fixture. With one candidate the most-recent fallback
    /// returns it whatever the preference loop does, so the test would still pass with the
    /// preference loop deleted — it would assert nothing. The decoys make the loop load-bearing:
    /// the newest candidate here is the 14th, so anything other than a genuine match on the
    /// day's own stamp picks the wrong session.
    func testAFinishedDayResolvesToTheSessionTrainedOnIt() {
        let index = SessionLogResolution.indexOfSession(
            candidateDates: [date(4), date(14), date(11)],
            sessionDates: [date(11, hour: 19), date(11, hour: 18)],
            viewingDate: date(17),
            calendar: calendar
        )
        XCTAssertEqual(index, 2, "Expected the session trained on the 11th, not the newest log")
    }

    // MARK: - The live session must keep working

    /// A session being trained right now has stamps on today, so it resolves exactly as before.
    func testALiveSessionStillResolvesToTodaysLog() {
        let index = SessionLogResolution.indexOfSession(
            candidateDates: [date(3), date(17)],
            sessionDates: [date(17, hour: 17)],
            viewingDate: date(17),
            calendar: calendar
        )
        XCTAssertEqual(index, 1)
    }

    /// The very first set of a brand-new session is logged before any clock stamp exists, so
    /// the viewing date has to remain a fallback.
    func testAnUnstampedDayFallsBackToTheViewingDate() {
        let index = SessionLogResolution.indexOfSession(
            candidateDates: [date(17)],
            sessionDates: [],
            viewingDate: date(17),
            calendar: calendar
        )
        XCTAssertEqual(index, 0)
    }

    /// A day never trained must resolve to nothing. The most-recent fallback must not be able
    /// to invent a session out of another day's work.
    func testNoCandidatesResolvesToNothing() {
        XCTAssertNil(
            SessionLogResolution.indexOfSession(
                candidateDates: [],
                sessionDates: [date(11)],
                viewingDate: date(17),
                calendar: calendar
            )
        )
    }

    // MARK: - Edges the one-line version got wrong or could not express

    /// A session that runs past midnight ends on a different calendar day than it started, and
    /// its later sets carry the later date. The end stamp is consulted first for that reason.
    ///
    /// The decoy on the 11th is what gives this test teeth: consulting only the START stamp
    /// would pick it, and consulting neither would fall through to the newest candidate, which
    /// is the one on the 12th only by luck. Ordering the assertion against a real alternative
    /// is the difference between testing the preference order and restating it.
    func testASessionCrossingMidnightPrefersTheEndStamp() {
        let index = SessionLogResolution.indexOfSession(
            candidateDates: [date(11, hour: 23), date(12, hour: 0)],
            sessionDates: [date(12, hour: 0), date(11, hour: 23)],
            viewingDate: date(20),
            calendar: calendar
        )
        XCTAssertEqual(index, 1, "The set logged after midnight belongs to the session that ended then")
    }

    /// Days trained before the session clock existed carry no stamp. Their most recent recorded
    /// work is the only honest answer, and it beats reporting nothing.
    func testALegacyDayWithNoStampsUsesItsMostRecentLog() {
        let index = SessionLogResolution.indexOfSession(
            candidateDates: [date(2), date(9), date(5)],
            sessionDates: [],
            viewingDate: date(20),
            calendar: calendar
        )
        XCTAssertEqual(index, 1, "Expected the newest candidate (the 9th)")
    }

    /// The day's own stamps outrank the viewing date. Without this a day trained on the 11th,
    /// opened on a day that happens to hold another log for the same program day, would show
    /// the wrong session.
    func testTheDaysOwnStampWinsOverTheViewingDate() {
        let index = SessionLogResolution.indexOfSession(
            candidateDates: [date(17), date(11)],
            sessionDates: [date(11)],
            viewingDate: date(17),
            calendar: calendar
        )
        XCTAssertEqual(index, 1)
    }

    // MARK: - Session identity belongs to a program

    /// The collision the old "same calendar day as now" lookup hid by accident: `workoutDayNumber`
    /// is a bare integer, so day 11 of an archived program matches day 11 of the current one.
    func testALogFromBeforeTheProgramStartedIsNotItsSession() {
        XCTAssertFalse(
            SessionLogResolution.belongsToProgram(logDate: date(1), programStart: date(10))
        )
        XCTAssertTrue(
            SessionLogResolution.belongsToProgram(logDate: date(11), programStart: date(10))
        )
    }

    /// The program's own creation instant counts as inside it, not outside.
    func testTheProgramStartInstantItselfBelongs() {
        XCTAssertTrue(
            SessionLogResolution.belongsToProgram(logDate: date(10), programStart: date(10))
        )
    }

    /// Nothing to scope against — the answer has to be the one from before scoping existed.
    func testAnUnscopeableDayAcceptsEverything() {
        XCTAssertTrue(
            SessionLogResolution.belongsToProgram(logDate: date(1), programStart: nil)
        )
    }

    // MARK: - "Last session" anchoring

    /// On a day trained three weeks ago, "last" must mean before THAT session — not before
    /// today, which would show a session from that day's future under a suggestion derived
    /// from it.
    func testPreviousSessionCutoffFollowsTheSessionOnScreen() {
        let cutoff = SessionLogResolution.previousSessionCutoff(
            currentSessionDate: date(11, hour: 19),
            sessionDates: [date(11, hour: 19)],
            viewingDate: date(17)
        )
        XCTAssertEqual(cutoff, date(11, hour: 19))
        XCTAssertTrue(date(4) < cutoff, "A genuinely earlier session must still qualify")
        XCTAssertFalse(date(14) < cutoff, "A session from that day's future must not")
    }

    /// The cutoff must anchor on the session's EARLIEST marker, not the first element of an
    /// end-first array. Every single-stamp test here would pass either way — this is the one
    /// that catches it.
    ///
    /// A session running 23:45 → 00:10 anchored on its END would put its own pre-midnight sets
    /// before the cutoff, handing this session's work back as the PREVIOUS session.
    func testCutoffAnchorsOnTheSessionStartWhenItCrossedMidnight() {
        let start = date(17, hour: 23)
        let end = date(18, hour: 0)
        let cutoff = SessionLogResolution.previousSessionCutoff(
            currentSessionDate: end,
            sessionDates: [end, start],
            viewingDate: date(18, hour: 1)
        )
        XCTAssertEqual(cutoff, start)
        XCTAssertFalse(end < cutoff, "A set logged after midnight belongs to THIS session")
        XCTAssertTrue(date(16, hour: 18) < cutoff, "A genuinely earlier session must still qualify")
    }

    /// The cutoff is an INSTANT, and rounding it to the start of its day silently drops real
    /// history. The same exercise appears on more than one program day, so training it at 18:00
    /// and again in a session starting 23:45 that runs past midnight is a real shape — and for
    /// the second card the 18:00 work is a genuine previous session.
    ///
    /// Day-rounding does not blank the panel, which would at least be visible. It falls through
    /// to some older session instead, so the lifter is coached off numbers already beaten.
    func testAnEarlierSessionOnTheStartDayIsStillAPreviousSession() {
        let cutoff = SessionLogResolution.previousSessionCutoff(
            currentSessionDate: date(18, hour: 0),
            sessionDates: [date(18, hour: 0), date(17, hour: 23)],
            viewingDate: date(18, hour: 1)
        )
        XCTAssertTrue(
            date(17, hour: 18) < cutoff,
            "A session five hours before this one started is previous work, not part of it"
        )
        XCTAssertEqual(
            cutoff, date(17, hour: 23),
            "Rounding to startOfDay here would exclude the whole of the 17th"
        )
    }

    /// The other way the current session ends up billed as the previous one — the one that only
    /// appeared once past days could show their own sets at all.
    ///
    /// A day predating the session clock has NO stamps, so the anchor falls back to today while
    /// its session legitimately resolves to a log dated weeks ago. That log is then trivially
    /// "before today" and wins the previous-session lookup too: the same numbers rendered as
    /// this session's sets AND as the last session, for a day trained exactly once.
    func testCutoffAnchorsOnTheResolvedSessionWhenTheDayHasNoStamps() {
        let cutoff = SessionLogResolution.previousSessionCutoff(
            currentSessionDate: date(9),
            sessionDates: [],
            viewingDate: date(17)
        )
        XCTAssertEqual(cutoff, date(9))
        XCTAssertFalse(
            date(9) < cutoff,
            "The session being displayed must never also qualify as the session before it"
        )
        XCTAssertTrue(date(2) < cutoff, "A genuinely earlier session must still qualify")
    }

    /// With neither stamps nor a resolved session there is nothing to anchor on but the moment
    /// of viewing — a day never trained.
    func testCutoffFallsBackToTheViewingDateWhenNothingIsKnown() {
        XCTAssertEqual(
            SessionLogResolution.previousSessionCutoff(
                currentSessionDate: nil,
                sessionDates: [],
                viewingDate: date(17, hour: 18)
            ),
            date(17, hour: 18)
        )
    }

    /// A live session still excludes its own work and still admits yesterday's.
    func testPreviousSessionCutoffForALiveSession() {
        let cutoff = SessionLogResolution.previousSessionCutoff(
            currentSessionDate: date(17, hour: 9),
            sessionDates: [date(17, hour: 8)],
            viewingDate: date(17, hour: 18)
        )
        XCTAssertEqual(cutoff, date(17, hour: 8))
        XCTAssertFalse(date(17, hour: 9) < cutoff, "This session's own log is not previous work")
        XCTAssertTrue(date(16, hour: 23) < cutoff)
    }

    // MARK: - What counts as a live session

    /// The trap. `isSessionClosed` defaults to false and `feedbackSubmittedAt` stays nil for any
    /// day trained and never rated, so open-ness alone declares a three-week-old workout "in
    /// progress" forever — and a live session is allowed to restamp its work to now.
    func testAnOldUnratedDayIsNotLiveJustBecauseItWasNeverClosed() {
        XCTAssertFalse(
            SessionLogResolution.sessionIsLive(
                dayIsOpen: true,
                sessionDates: [date(11, hour: 19)],
                writeDate: date(17)
            ),
            "An unfinished day from six days ago must not be treated as the session in progress"
        )
    }

    /// ...and the case that rules out simply asking "is it today": a workout carrying on past
    /// midnight is still the same session while its stamps sit on yesterday.
    func testASessionIsStillLiveJustAfterMidnight() {
        XCTAssertTrue(
            SessionLogResolution.sessionIsLive(
                dayIsOpen: true,
                sessionDates: [date(17, hour: 23)],
                writeDate: date(18, hour: 0)
            )
        )
    }

    func testAFinishedOrRatedDayIsNeverLive() {
        XCTAssertFalse(
            SessionLogResolution.sessionIsLive(
                dayIsOpen: false,
                sessionDates: [date(17, hour: 17)],
                writeDate: date(17, hour: 18)
            )
        )
    }

    /// The state that genuinely exists and must stay live: the session clock is started BY the
    /// first logged set, so the first set of a workout is written before any marker exists.
    /// If this were false the clock would never start at all.
    func testAnOpenDayWithNoMarkersAtAllIsLive() {
        XCTAssertTrue(
            SessionLogResolution.sessionIsLive(dayIsOpen: true, sessionDates: [], writeDate: date(17))
        )
    }

    /// Pins the boundary so the window cannot be widened by accident into covering yesterday.
    func testLivenessWindowEndsWellShortOfAnotherDay() {
        let last = date(17, hour: 8)
        XCTAssertTrue(
            SessionLogResolution.sessionIsLive(
                dayIsOpen: true,
                sessionDates: [last],
                writeDate: last.addingTimeInterval(SessionLogResolution.maximumLiveSessionGap - 60)
            )
        )
        XCTAssertFalse(
            SessionLogResolution.sessionIsLive(
                dayIsOpen: true,
                sessionDates: [last],
                writeDate: last.addingTimeInterval(SessionLogResolution.maximumLiveSessionGap + 60)
            )
        )
        XCTAssertLessThan(
            SessionLogResolution.maximumLiveSessionGap, 24 * 60 * 60,
            "A window of a day or more would let a previous day's session claim today's work"
        )
    }

    // MARK: - Where the evidence of a session comes from

    /// Clock stamps are authoritative when they exist, and stay end-first — `stamp` reads
    /// `.first` and wants the end.
    func testClockStampsWinWhenTheyExist() {
        let end = date(17, hour: 19)
        let start = date(17, hour: 18)
        XCTAssertEqual(
            SessionLogResolution.sessionMarkers(
                clockStamps: [end, start],
                recordedLogDates: [date(11)]
            ),
            [end, start]
        )
    }

    /// THE gap this exists to close. The session clock is only ever written by set-logging done
    /// ON the day, so a day filled in afterwards through the bulk sheet has real logged work and
    /// no stamps. Without falling back to what was logged, such a day reads as brand new — and
    /// brand new is the one state allowed to restamp work to now.
    func testRecordedWorkStandsInWhenTheClockNeverRan() {
        XCTAssertEqual(
            SessionLogResolution.sessionMarkers(
                clockStamps: [],
                recordedLogDates: [date(11), date(9)]
            ),
            [date(11)],
            "The most recent recorded work is the evidence"
        )
    }

    /// A day with nothing at all is the only genuinely blank case — a session about to start.
    func testNoEvidenceAtAllProducesNoMarkers() {
        XCTAssertTrue(
            SessionLogResolution.sessionMarkers(clockStamps: [], recordedLogDates: []).isEmpty
        )
    }

    /// The composed behaviour, which is what actually broke: a backfilled day must not read as
    /// live even for an exercise that has never been logged on it.
    ///
    /// Evidence has to be DAY-level. Scoped per exercise, the first inline log on any untouched
    /// exercise of that day sees nothing, counts as live, files itself under today while its
    /// neighbours sit weeks earlier — and because that write starts the day's clock, the
    /// neighbours then become "live" too and the next correction overwrites their dates as well.
    func testABackfilledDayIsNotLiveEvenForAnExerciseNeverLoggedOnIt() {
        let markers = SessionLogResolution.sessionMarkers(
            clockStamps: [],
            recordedLogDates: [date(11)]   // a sibling exercise, backfilled to the 11th
        )
        XCTAssertFalse(
            SessionLogResolution.sessionIsLive(
                dayIsOpen: true,
                sessionDates: markers,
                writeDate: date(17)
            )
        )
        XCTAssertEqual(
            SessionLogResolution.stamp(
                existingDate: nil,
                sessionDates: markers,
                writeDate: date(17),
                sessionIsLive: false,
                calendar: calendar
            ),
            date(11),
            "The new log must join the day it belongs to, not split it across two dates"
        )
    }

    /// And the opposite composition: a second exercise during a real live session.
    func testASecondExerciseDuringALiveSessionIsStillLive() {
        let markers = SessionLogResolution.sessionMarkers(
            clockStamps: [date(17, hour: 17)],
            recordedLogDates: [date(17, hour: 17)]
        )
        XCTAssertTrue(
            SessionLogResolution.sessionIsLive(
                dayIsOpen: true,
                sessionDates: markers,
                writeDate: date(17, hour: 18)
            )
        )
    }

    // MARK: - Write stamping

    /// Filling in a day trained last week records it on that day, rather than opening a second
    /// session dated today against the same program day.
    func testANewLogForAPastDayIsStampedWithThatDay() {
        let stamp = SessionLogResolution.stamp(
            existingDate: nil,
            sessionDates: [date(11, hour: 19)],
            writeDate: date(17),
            sessionIsLive: false,
            calendar: calendar
        )
        XCTAssertEqual(stamp, date(11, hour: 19))
    }

    /// A session still being trained keeps advancing — `SessionLifecycle` derives the session
    /// clock from this stamp, so freezing it would stop the recorded duration ever growing.
    func testALiveSessionStampKeepsAdvancing() {
        let stamp = SessionLogResolution.stamp(
            existingDate: date(17, hour: 17),
            sessionDates: [date(17, hour: 17)],
            writeDate: date(17, hour: 18),
            sessionIsLive: true,
            calendar: calendar
        )
        XCTAssertEqual(stamp, date(17, hour: 18))
    }

    /// The case calendar-day comparison alone gets WRONG. A session starting 23:45 and running
    /// to 00:20 is still being trained while its stamp sits on the previous calendar day. Judged
    /// on dates it looks like a stale correction and freezes; judged on whether the session is
    /// open, it keeps advancing — which is what keeps the recorded duration growing through the
    /// second half of a late-night workout.
    func testALiveSessionKeepsAdvancingAcrossMidnight() {
        let stamp = SessionLogResolution.stamp(
            existingDate: date(17, hour: 23),
            sessionDates: [date(17, hour: 23)],
            writeDate: date(18, hour: 0),
            sessionIsLive: true,
            calendar: calendar
        )
        XCTAssertEqual(stamp, date(18, hour: 0), "A session that is still open must not freeze at midnight")
    }

    /// Correcting one set on an old session must not restamp that work as today's.
    func testCorrectingAnOldSessionDoesNotMoveItToToday() {
        let stamp = SessionLogResolution.stamp(
            existingDate: date(11, hour: 19),
            sessionDates: [date(11, hour: 19)],
            writeDate: date(17),
            sessionIsLive: false,
            calendar: calendar
        )
        XCTAssertEqual(stamp, date(11, hour: 19))
    }

    /// A closed session corrected later the SAME day still advances — the freeze is about
    /// reaching back to another day, not about the session being finished.
    func testCorrectingAClosedSessionOnItsOwnDayStillAdvances() {
        let stamp = SessionLogResolution.stamp(
            existingDate: date(17, hour: 9),
            sessionDates: [date(17, hour: 10)],
            writeDate: date(17, hour: 20),
            sessionIsLive: false,
            calendar: calendar
        )
        XCTAssertEqual(stamp, date(17, hour: 20))
    }

    /// The truth-table cell that was wrong: a live session, a day that already carries stamps,
    /// and an exercise being logged for the FIRST time. Reaching for the day's stamp there
    /// backdates the first set of every exercise started after a session crosses midnight —
    /// two lifts minutes apart in one continuous workout landing on two different dates, and
    /// the later one's personal best recorded against the earlier day.
    func testFirstLogOfAnExerciseInALiveSessionUsesTheMomentItHappened() {
        let stamp = SessionLogResolution.stamp(
            existingDate: nil,
            sessionDates: [date(17, hour: 23), date(17, hour: 22)],
            writeDate: date(18, hour: 0),
            sessionIsLive: true,
            calendar: calendar
        )
        XCTAssertEqual(stamp, date(18, hour: 0))
    }

    /// A brand-new session on a day with no stamps yet uses the write date.
    func testANewLogOnAnUnstampedLiveDayUsesTheWriteDate() {
        let stamp = SessionLogResolution.stamp(
            existingDate: nil,
            sessionDates: [],
            writeDate: date(17, hour: 9),
            sessionIsLive: true,
            calendar: calendar
        )
        XCTAssertEqual(stamp, date(17, hour: 9))
    }

    /// The remaining cell, pinned as a DELIBERATE limitation rather than left to be discovered:
    /// a finished day predating the session clock has no stamp of any kind, so a first log for
    /// one of its exercises can only be dated today. That files old work under the wrong date.
    /// It is the one case with no date information to do better with, and the bulk sheet's date
    /// picker is the correction path. If a stamp is ever backfilled onto such days, this test
    /// should change with it.
    func testAFinishedDayWithNoStampsAtAllCanOnlyUseTheWriteDate() {
        let stamp = SessionLogResolution.stamp(
            existingDate: nil,
            sessionDates: [],
            writeDate: date(17, hour: 9),
            sessionIsLive: false,
            calendar: calendar
        )
        XCTAssertEqual(stamp, date(17, hour: 9))
    }
}

/// The invariant every session lookup rests on, made explicit because it is easy to doubt.
///
/// `ExercisePerformanceLog.workoutDayNumber` is a bare integer, so it is fair to ask whether
/// "day 3" could mean week 1's day 3 in one row and week 3's day 3 in another — which would make
/// `(exercise, dayNumber)` ambiguous and let a lookup land on the wrong week entirely.
///
/// It cannot. Day numbers run 1...28 across the whole mesocycle and `weekNumber` is DERIVED from
/// them, so week 2's third session is day 10, not day 3 again. Within one program the pair is
/// unique, and the only remaining ambiguity — the same program day trained on two different
/// dates — is what the date preference in `indexOfSession` resolves. Across programs, day numbers
/// do repeat, which is what `belongsToProgram` exists for.
final class WorkoutDayNumberingTests: XCTestCase {

    /// Whole-program numbering: no week reuses another week's day numbers.
    func testDayNumbersAreUniqueAcrossTheWholeProgram() {
        var seen = Set<Int>()
        for dayNumber in 1...28 {
            XCTAssertTrue(seen.insert(dayNumber).inserted)
            let day = WorkoutDay(dayNumber: dayNumber, dayName: "Push", muscleGroups: "Chest")
            XCTAssertEqual(day.weekNumber, ((dayNumber - 1) / 7) + 1)
        }
    }

    /// The concrete claim: the third session of week 2 is day 10, not day 3.
    func testTheSameWeekdaySlotInALaterWeekIsADifferentDayNumber() {
        let weekOneThirdSession = WorkoutDay(dayNumber: 3, dayName: "Push", muscleGroups: "Chest")
        let weekTwoThirdSession = WorkoutDay(dayNumber: 10, dayName: "Push", muscleGroups: "Chest")
        XCTAssertEqual(weekOneThirdSession.weekNumber, 1)
        XCTAssertEqual(weekTwoThirdSession.weekNumber, 2)
        XCTAssertNotEqual(
            weekOneThirdSession.dayNumber, weekTwoThirdSession.dayNumber,
            "If these ever collide, every session lookup keyed on workoutDayNumber becomes ambiguous"
        )
    }
}

/// `WorkoutDay.sessionCalendarDates` is what feeds every rule above.
final class SessionCalendarDatesTests: XCTestCase {

    private func day() -> WorkoutDay {
        WorkoutDay(dayNumber: 11, dayName: "Push", muscleGroups: "Chest")
    }

    func testUntrainedDayOffersNoDates() {
        XCTAssertTrue(day().sessionCalendarDates.isEmpty)
    }

    /// End first: a session crossing midnight carries its later sets on the end date.
    func testEndStampIsOfferedBeforeStart() {
        let subject = day()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(3600)
        subject.sessionStartedAt = start
        subject.sessionEndedAt = end
        XCTAssertEqual(subject.sessionCalendarDates, [end, start])
    }

    /// A day opened but never finished still has something to match on.
    func testStartAloneIsEnough() {
        let subject = day()
        let start = Date(timeIntervalSince1970: 1_000_000)
        subject.sessionStartedAt = start
        XCTAssertEqual(subject.sessionCalendarDates, [start])
    }
}
