import XCTest
@testable import Transform

/// Pins the day-anchoring rules of SleepAggregationCore (EvidenceProfile SLEEP-001
/// boundaries): a nap can never masquerade as a night, and the quick log's
/// after-midnight wake-day crediting stays honest.
final class SleepAggregationTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Builders

    private func wakeTime(daysAgo: Int, hour: Int = 7) -> Date {
        let today = calendar.startOfDay(for: Date())
        let base = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        return calendar.date(byAdding: .hour, value: hour, to: base) ?? base
    }

    private func sample(
        endDaysAgo: Int,
        wakeHour: Int = 7,
        duration: Double,
        kind: SleepSampleKind = .main,
        quality: Int = 3,
        postCallShift: Bool = false
    ) -> SleepEpisodeSample {
        let end = wakeTime(daysAgo: endDaysAgo, hour: wakeHour)
        return SleepEpisodeSample(
            start: end.addingTimeInterval(-duration * 3600),
            end: end,
            durationHours: duration,
            quality: quality,
            kind: kind,
            isPostCallShift: postCallShift
        )
    }

    private func recoveryState(from core: SleepAggregateSnapshot) -> SleepRecoveryState {
        SleepRecoveryState(
            builtAt: .now,
            threeDayAverageHours: core.threeDayAverageHours,
            sevenDayAverageHours: core.sevenDayAverageHours,
            acuteLoggedDays: core.acuteLoggedDays,
            loggedDays: core.days.count,
            daysUnderFive: core.underFiveHours,
            daysUnderSix: core.underSixHours,
            variabilityHours: core.variabilityHours,
            recentPostCall: core.hasRecentPostCallRecovery
        )
    }

    // MARK: - Nap-only day exclusion (the false-restriction bug)

    func testNapOnlyDayCannotDragTheAcuteAverageIntoRestricted() throws {
        // Three good nights, then a 1.5h nap logged today before tonight's main
        // sleep exists. Pre-fix this read as a 1.5h night: (7.5+7.5+1.5)/3 = 5.5h
        // -> RESTRICTED. The nap must not create a day.
        let core = try XCTUnwrap(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 3, duration: 8.0),
            sample(endDaysAgo: 2, duration: 7.5),
            sample(endDaysAgo: 1, duration: 7.5),
            sample(endDaysAgo: 0, wakeHour: 16, duration: 1.5, kind: .nap)
        ]))

        XCTAssertEqual(core.days.count, 3, "The nap-only day must not appear as a logged day")
        XCTAssertEqual(core.napOnlyDayCount, 1)
        XCTAssertEqual(core.threeDayAverageHours, 7.5, accuracy: 0.001)
        XCTAssertEqual(core.acuteLoggedDays, 2)
        XCTAssertEqual(core.underFiveHours, 0, "A 1.5h nap day is not a day under 5h of sleep")

        let decision = SleepRecoveryPolicy.decision(from: recoveryState(from: core))
        XCTAssertEqual(decision.tier, .ready, "Good sleep plus a logged nap must stay ready: \(decision.audit)")
    }

    func testTwoNapOnlyDaysDoNotCountAsDaysUnderFiveHours() throws {
        // Pre-fix, two nap-only days matched the ">=2 days under 5h" restricted rule.
        let core = try XCTUnwrap(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 6, duration: 7.5),
            sample(endDaysAgo: 5, duration: 7.5),
            sample(endDaysAgo: 4, duration: 7.5),
            sample(endDaysAgo: 2, duration: 7.5),
            sample(endDaysAgo: 1, wakeHour: 15, duration: 1.0, kind: .nap),
            sample(endDaysAgo: 0, wakeHour: 15, duration: 1.5, kind: .nap)
        ]))

        XCTAssertEqual(core.underFiveHours, 0)
        XCTAssertEqual(core.napOnlyDayCount, 2)
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: recoveryState(from: core)).tier, .ready,
            "Napping on unlogged days must never read as sleep restriction"
        )
    }

    func testNapStillAddsHoursToAnAnchoredDay() throws {
        let core = try XCTUnwrap(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 0, duration: 6.0),
            sample(endDaysAgo: 0, wakeHour: 16, duration: 1.5, kind: .nap)
        ]))
        let day = try XCTUnwrap(core.days.last)
        XCTAssertEqual(day.totalHours, 7.5, accuracy: 0.001)
        XCTAssertEqual(day.mainSleepHours, 6.0, accuracy: 0.001)
        XCTAssertEqual(day.napHours, 1.5, accuracy: 0.001)
        XCTAssertEqual(core.napOnlyDayCount, 0)
    }

    func testRecoveryEpisodeAnchorsItsDayAndFlagsPostCall() throws {
        // A post-call recovery sleep IS the night record for that wake-day: it
        // anchors the day (short total counts as under-5h) and trips the
        // post-call restricted signal — that restriction is intended.
        let core = try XCTUnwrap(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 0, wakeHour: 13, duration: 4.0, kind: .recovery)
        ]))
        XCTAssertEqual(core.days.count, 1)
        XCTAssertEqual(core.underFiveHours, 1)
        XCTAssertTrue(core.hasRecentPostCallRecovery)
        XCTAssertEqual(core.napOnlyDayCount, 0)
    }

    func testPostCallShiftContextSurvivesOnANapOnlyDay() throws {
        // Post-call context is real even when only a nap carries the tag.
        let core = try XCTUnwrap(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 1, duration: 7.5),
            sample(endDaysAgo: 2, duration: 7.5),
            sample(endDaysAgo: 3, duration: 7.5),
            sample(endDaysAgo: 0, wakeHour: 15, duration: 2.0, kind: .nap, postCallShift: true)
        ]))
        XCTAssertTrue(core.hasRecentPostCallRecovery)
        XCTAssertEqual(core.napOnlyDayCount, 1)
    }

    func testAllNapWindowYieldsNoSnapshot() {
        XCTAssertNil(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 0, wakeHour: 15, duration: 1.0, kind: .nap),
            sample(endDaysAgo: 1, wakeHour: 15, duration: 1.5, kind: .nap)
        ]), "Naps alone are not a sleep trend")
    }

    // MARK: - Unrated (imported) nights

    func testUnratedNightDoesNotCountAsAQualityDurationMismatch() throws {
        // A HealthKit-imported 8h night has quality 0 (unrated). Pre-fix this tripped the
        // "slept >=7h but quality <=2" mismatch on every imported night.
        let core = try XCTUnwrap(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 1, duration: 8.0, quality: 0),
            sample(endDaysAgo: 0, duration: 7.5, quality: 0)
        ]))
        XCTAssertEqual(core.qualityDurationMismatchDays, 0)
    }

    func testUnratedNightsAreExcludedFromTheQualityAverage() throws {
        // One rated night (4/5) and one unrated import: the average must be the rated
        // value, not dragged toward zero by the 0.
        let core = try XCTUnwrap(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 1, duration: 7.5, quality: 4),
            sample(endDaysAgo: 0, duration: 7.5, quality: 0)
        ]))
        XCTAssertEqual(core.averageQuality, 4, accuracy: 0.001)
    }

    func testMixedRatedAndUnratedEpisodesOnADayWeightOnlyTheRatedOne() throws {
        // An anchored day with a rated main sleep plus an unrated imported nap keeps the
        // day's quality equal to the rated episode.
        let core = try XCTUnwrap(SleepAggregationCore.build(from: [
            sample(endDaysAgo: 0, duration: 6.0, quality: 5),
            sample(endDaysAgo: 0, wakeHour: 16, duration: 1.5, kind: .nap, quality: 0)
        ]))
        let day = try XCTUnwrap(core.days.last)
        XCTAssertEqual(day.averageQuality, 5, accuracy: 0.001)
    }

    // MARK: - Quick-log wake-day crediting

    func testQuickLogAfterMidnightCreditsThePreviousWakeDay() throws {
        let today = calendar.startOfDay(for: Date())
        let halfPastMidnight = today.addingTimeInterval(30 * 60)
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))

        let end = SleepQuickLogPolicy.quickLogEnd(loggedAt: halfPastMidnight, calendar: calendar)
        XCTAssertLessThan(end, today, "The episode must end before midnight to group into yesterday")
        XCTAssertEqual(
            SleepQuickLogPolicy.creditedWakeDayStart(loggedAt: halfPastMidnight, calendar: calendar),
            yesterday
        )
    }

    func testQuickLogInTheMorningEndsNowOnToday() {
        let today = calendar.startOfDay(for: Date())
        let sevenAM = today.addingTimeInterval(7 * 3600)
        XCTAssertEqual(SleepQuickLogPolicy.quickLogEnd(loggedAt: sevenAM, calendar: calendar), sevenAM)
        XCTAssertEqual(
            SleepQuickLogPolicy.creditedWakeDayStart(loggedAt: sevenAM, calendar: calendar),
            today
        )
    }

    func testQuickLogCutoffBoundaryBelongsToToday() throws {
        // Exactly at the cutoff hour the log is today's; one minute earlier it is not.
        // Built with calendar hour-adding (like the policy) so DST days can't skew it.
        let today = calendar.startOfDay(for: Date())
        let cutoff = try XCTUnwrap(
            calendar.date(byAdding: .hour, value: SleepQuickLogPolicy.previousWakeDayCutoffHour, to: today)
        )
        XCTAssertEqual(SleepQuickLogPolicy.quickLogEnd(loggedAt: cutoff, calendar: calendar), cutoff)
        XCTAssertLessThan(
            SleepQuickLogPolicy.quickLogEnd(loggedAt: cutoff.addingTimeInterval(-60), calendar: calendar),
            today
        )
    }
}
