import XCTest
@testable import Transform

/// Pins the reconciliation core that turns raw HealthKit sleep segments into SleepEntry
/// insert/update/skip decisions: fragmented segments coalesce into one night, blips and
/// implausible spans are rejected, a hand-logged night is never overwritten, and a
/// re-sync updates its own row in place instead of duplicating.
final class SleepHealthImportCoreTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Builders

    private func date(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let today = calendar.startOfDay(for: Date())
        let base = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        return calendar.date(byAdding: .minute, value: hour * 60 + minute, to: base) ?? base
    }

    private func seg(
        _ startDaysAgo: Int, _ startHour: Int,
        _ endDaysAgo: Int, _ endHour: Int,
        _ stage: HealthSleepStage,
        startMinute: Int = 0,
        endMinute: Int = 0
    ) -> HealthSleepSegment {
        HealthSleepSegment(
            start: date(daysAgo: startDaysAgo, hour: startHour, minute: startMinute),
            end: date(daysAgo: endDaysAgo, hour: endHour, minute: endMinute),
            stage: stage
        )
    }

    private func plan(
        _ segments: [HealthSleepSegment],
        existing: [ExistingSleepProjection<Int>] = []
    ) -> [SleepImportPlan<Int>] {
        SleepHealthImportCore.plan(segments: segments, existing: existing, calendar: calendar)
    }

    private func inserts(_ plan: [SleepImportPlan<Int>]) -> [SleepImportCandidate] {
        plan.compactMap { if case .insert(let c) = $0 { return c } else { return nil } }
    }

    private func assertSameInstant(_ lhs: Date, _ rhs: Date, _ message: String = "") {
        XCTAssertEqual(lhs.timeIntervalSince(rhs), 0, accuracy: 1, message)
    }

    // MARK: - Coalescing

    func testFragmentedAsleepStagesCoalesceIntoOneNight() {
        // A real night arrives as several per-stage rows; they must become one night
        // spanning the earliest start to the latest end, not four short "nights".
        let result = plan([
            seg(1, 23, 1, 23, .asleep, endMinute: 40),     // 23:00 -> 23:40
            seg(1, 23, 0, 3, .asleep, startMinute: 40),    // 23:40 -> 03:00
            seg(0, 3, 0, 5, .asleep),                      // 03:00 -> 05:00
            seg(0, 5, 0, 7, .asleep)                       // 05:00 -> 07:00
        ])
        let nights = inserts(result)
        XCTAssertEqual(nights.count, 1)
        guard let night = nights.first else { return XCTFail("Expected one coalesced night") }
        assertSameInstant(night.start, date(daysAgo: 1, hour: 23))
        assertSameInstant(night.end, date(daysAgo: 0, hour: 7))
    }

    func testShortAwakeGapIsBridgedIntoTheSameNight() {
        // A mid-night awakening splits the asleep rows but must not split the night:
        // the two asleep segments are 30 min apart (< 60 min tolerance).
        let result = plan([
            seg(1, 23, 0, 2, .asleep),                 // 23:00 -> 02:00
            seg(0, 2, 0, 2, .awake, endMinute: 30),    // awake 02:00 -> 02:30 (ignored)
            seg(0, 2, 0, 7, .asleep, startMinute: 30)  // 02:30 -> 07:00
        ])
        let nights = inserts(result)
        XCTAssertEqual(nights.count, 1)
        assertSameInstant(nights[0].start, date(daysAgo: 1, hour: 23))
        assertSameInstant(nights[0].end, date(daysAgo: 0, hour: 7))
        XCTAssertEqual(nights[0].durationHours, 8, accuracy: 0.01)
    }

    func testAsleepExtentPreferredOverInBed() {
        // iPhone can record a wide "in bed" window plus a tighter "asleep" span. The
        // night should be the asleep extent, trimming lie-awake in-bed time.
        let result = plan([
            seg(1, 23, 0, 7, .inBed, endMinute: 30),                    // in bed 23:00 -> 07:30
            seg(1, 23, 0, 7, .asleep, startMinute: 20, endMinute: 10)   // asleep 23:20 -> 07:10
        ])
        let nights = inserts(result)
        XCTAssertEqual(nights.count, 1)
        assertSameInstant(nights[0].start, date(daysAgo: 1, hour: 23, minute: 20))
        assertSameInstant(nights[0].end, date(daysAgo: 0, hour: 7, minute: 10))
    }

    func testInBedOnlyFallsBackToInBedExtent() {
        // iPhone-only schedule data with no asleep classification still yields a night.
        let result = plan([
            seg(1, 23, 0, 7, .inBed)
        ])
        let nights = inserts(result)
        XCTAssertEqual(nights.count, 1)
        assertSameInstant(nights[0].start, date(daysAgo: 1, hour: 23))
        assertSameInstant(nights[0].end, date(daysAgo: 0, hour: 7))
    }

    // MARK: - Plausibility guards

    func testShortBlipIsNotImportedAsMainSleep() {
        // A 40-minute in-bed blip (a 2 a.m. phone check) must not become a night that
        // anchors a phantom restricted day.
        let result = plan([
            seg(0, 2, 0, 2, .inBed, endMinute: 40)
        ])
        XCTAssertTrue(inserts(result).isEmpty, "A sub-2.5h blip must never be a main sleep")
        XCTAssertEqual(result.count, 1)
        if case .skip(let reason, _) = result[0] {
            XCTAssertEqual(reason, .noPlausibleMainSleep)
        } else {
            XCTFail("Expected a skip for the implausible night, got \(result[0])")
        }
    }

    func testImplausiblyLongSpanIsSkipped() {
        // 18h "in bed" is overlapping sources or bad data, not a night.
        let result = plan([
            seg(1, 13, 0, 7, .inBed)
        ])
        XCTAssertTrue(inserts(result).isEmpty)
    }

    func testLongestPlausibleClusterWinsWhenADayAlsoHasANap() {
        // Same wake-day: an 8h night plus a 1.5h afternoon nap. Only the night is
        // imported as the main sleep; the nap is left to manual logging.
        let result = plan([
            seg(1, 23, 0, 7, .asleep),                  // night: 8h
            seg(0, 14, 0, 15, .asleep, endMinute: 30)   // nap: 1.5h
        ])
        let nights = inserts(result)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].durationHours, 8, accuracy: 0.01)
    }

    func testShortOnCallNightAboveFloorIsKept() {
        // A genuine 3h on-call core sleep sits above the 2.5h floor and must import.
        let result = plan([
            seg(0, 2, 0, 5, .asleep)   // 02:00 -> 05:00, 3h
        ])
        let nights = inserts(result)
        XCTAssertEqual(nights.count, 1)
        XCTAssertEqual(nights[0].durationHours, 3, accuracy: 0.01)
    }

    func testMultipleNightsProduceMultipleInserts() {
        let result = plan([
            seg(2, 23, 1, 7, .asleep),
            seg(1, 23, 0, 7, .asleep)
        ])
        XCTAssertEqual(inserts(result).count, 2)
    }

    // MARK: - Reconciliation

    private func existing(
        id: Int,
        wakeDaysAgo: Int,
        start: Date,
        end: Date,
        isMainSleep: Bool = true,
        source: SleepEntrySource
    ) -> ExistingSleepProjection<Int> {
        ExistingSleepProjection(
            id: id,
            wakeDayStart: calendar.startOfDay(for: date(daysAgo: wakeDaysAgo, hour: 0)),
            start: start,
            end: end,
            isMainSleep: isMainSleep,
            source: source
        )
    }

    func testManualNightIsNeverOverwritten() {
        let manual = existing(
            id: 1, wakeDaysAgo: 0,
            start: date(daysAgo: 1, hour: 23),
            end: date(daysAgo: 0, hour: 8),
            source: .manual
        )
        let result = plan([seg(1, 22, 0, 6, .asleep)], existing: [manual])
        XCTAssertTrue(inserts(result).isEmpty, "A hand-logged night must win outright")
        XCTAssertEqual(result.count, 1)
        if case .skip(let reason, _) = result[0] {
            XCTAssertEqual(reason, .manualEntryPresent)
        } else {
            XCTFail("Expected manual-present skip, got \(result[0])")
        }
    }

    func testImportedNightIsUpdatedInPlaceWhenItMoves() {
        // A previously imported night whose interval shifted (Health revised it) updates
        // the same row rather than inserting a duplicate.
        let imported = existing(
            id: 42, wakeDaysAgo: 0,
            start: date(daysAgo: 1, hour: 23),
            end: date(daysAgo: 0, hour: 6),
            source: .healthKit
        )
        let result = plan([seg(1, 23, 0, 7, .asleep)], existing: [imported])
        XCTAssertEqual(result.count, 1)
        if case .update(let id, let candidate) = result[0] {
            XCTAssertEqual(id, 42)
            assertSameInstant(candidate.end, date(daysAgo: 0, hour: 7))
        } else {
            XCTFail("Expected an update of the existing imported row, got \(result[0])")
        }
    }

    func testImportedNightUnchangedWithinToleranceIsLeftAlone() {
        // Re-syncing the identical night (within 5 min) must not churn the store.
        let imported = existing(
            id: 7, wakeDaysAgo: 0,
            start: date(daysAgo: 1, hour: 23),
            end: date(daysAgo: 0, hour: 7),
            source: .healthKit
        )
        let result = plan([
            seg(1, 23, 0, 7, .asleep, startMinute: 2, endMinute: 1)  // 2 min / 1 min drift
        ], existing: [imported])
        XCTAssertTrue(inserts(result).isEmpty)
        if case .skip(let reason, _) = result[0] {
            XCTAssertEqual(reason, .alreadyUpToDate)
        } else {
            XCTFail("Expected up-to-date skip, got \(result[0])")
        }
    }

    func testManualNapDoesNotBlockAnImportedMainSleep() {
        // A manual *nap* on the day is not a main sleep, so it must not suppress the
        // imported night.
        let manualNap = existing(
            id: 3, wakeDaysAgo: 0,
            start: date(daysAgo: 0, hour: 14),
            end: date(daysAgo: 0, hour: 15),
            isMainSleep: false,
            source: .manual
        )
        let result = plan([seg(1, 23, 0, 7, .asleep)], existing: [manualNap])
        XCTAssertEqual(inserts(result).count, 1, "A manual nap must not block the night import")
    }

    func testEmptyInputProducesNoPlan() {
        XCTAssertTrue(plan([]).isEmpty)
    }

    // MARK: - Never stack on stored sleep (bug audit 2026-11-18)

    private func skipReason(_ result: [SleepImportPlan<Int>]) -> SleepImportSkipReason? {
        guard result.count == 1, case .skip(let reason, _) = result[0] else { return nil }
        return reason
    }

    /// Owner path: a post-call recovery sleep logged by hand, 08:00-13:00. Apple Health saw the
    /// same five hours as a night. Importing it as a main sleep counted those hours twice.
    func testHandLoggedRecoverySleepIsNotImportedAgainAsANight() {
        let recovery = existing(
            id: 5, wakeDaysAgo: 0,
            start: date(daysAgo: 0, hour: 8),
            end: date(daysAgo: 0, hour: 13),
            isMainSleep: false,
            source: .manual
        )
        let result = plan([seg(0, 8, 0, 13, .asleep)], existing: [recovery])
        XCTAssertTrue(inserts(result).isEmpty, "The same hours must not be stored twice")
        XCTAssertEqual(skipReason(result), .overlapsExistingEntry)
    }

    /// A hand-logged nap that overlaps what Health records as a night blocks it too; a nap at
    /// another time of day still does not (testManualNapDoesNotBlockAnImportedMainSleep).
    func testOverlappingHandLoggedNapBlocksTheImportedNight() {
        let nap = existing(
            id: 6, wakeDaysAgo: 0,
            start: date(daysAgo: 0, hour: 14),
            end: date(daysAgo: 0, hour: 17),
            isMainSleep: false,
            source: .manual
        )
        let result = plan([seg(0, 14, 0, 17, .inBed)], existing: [nap])
        XCTAssertTrue(inserts(result).isEmpty)
        XCTAssertEqual(skipReason(result), .overlapsExistingEntry)
    }

    /// The imported row a re-sync updates overlaps the new candidate by definition; that must
    /// still update in place, not be refused as an overlap.
    func testOverlapRuleStillUpdatesTheSameImportedNight() {
        let imported = existing(
            id: 42, wakeDaysAgo: 0,
            start: date(daysAgo: 1, hour: 23),
            end: date(daysAgo: 0, hour: 6),
            source: .healthKit
        )
        let result = plan([seg(1, 23, 0, 7, .asleep)], existing: [imported])
        guard result.count == 1, case .update(let id, _) = result[0] else {
            return XCTFail("Expected an in-place update, got \(result)")
        }
        XCTAssertEqual(id, 42)
    }

    /// The quick log stores invented times; logged just after midnight it ends at 23:59 the
    /// day before. The following real night grazes that window by about an hour and must
    /// still import: a graze is not the same sleep.
    func testQuickLogWindowGrazingTheNextNightDoesNotBlockIt() {
        let quickLog = existing(
            id: 9, wakeDaysAgo: 1,
            start: date(daysAgo: 1, hour: 15, minute: 59),
            end: date(daysAgo: 1, hour: 23, minute: 59),
            source: .manual
        )
        let result = plan([seg(1, 23, 0, 7, .asleep)], existing: [quickLog])
        XCTAssertEqual(inserts(result).count, 1, "A 59-minute graze must not drop a real 8-hour night")
    }

    // MARK: - A deleted imported night stays deleted (bug audit 2026-11-18)

    /// Owner path: delete a wrong night that Apple Health supplied. The next sync, any night
    /// in the 14-day window, put it straight back.
    func testDeletedImportedNightIsNotImportedAgain() {
        let declined: Set<Date> = [calendar.startOfDay(for: date(daysAgo: 0, hour: 7))]
        let result = SleepHealthImportCore.plan(
            segments: [seg(1, 23, 0, 7, .asleep)],
            existing: [ExistingSleepProjection<Int>](),
            declinedWakeDays: declined,
            calendar: calendar
        )
        XCTAssertTrue(inserts(result).isEmpty)
        XCTAssertEqual(skipReason(result), .declinedByUser)
        // Another night is unaffected.
        let other = SleepHealthImportCore.plan(
            segments: [seg(2, 23, 1, 7, .asleep)],
            existing: [ExistingSleepProjection<Int>](),
            declinedWakeDays: declined,
            calendar: calendar
        )
        XCTAssertEqual(inserts(other).count, 1)
    }

    /// The remembered deletions survive a reload, and old ones are dropped.
    func testDeclinedNightsAreRememberedAndOldOnesPruned() throws {
        let name = "SleepHealthImportCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let now = date(daysAgo: 0, hour: 12)
        let old = date(daysAgo: SleepImportDeclines.retentionDays + 5, hour: 7)
        SleepImportDeclines.record(wakeDayOf: old, now: old, calendar: calendar, defaults: defaults)
        SleepImportDeclines.record(wakeDayOf: date(daysAgo: 0, hour: 7), now: now, calendar: calendar, defaults: defaults)
        let loaded = SleepImportDeclines.load(defaults)
        XCTAssertTrue(loaded.contains(calendar.startOfDay(for: date(daysAgo: 0, hour: 7))))
        XCTAssertFalse(loaded.contains(calendar.startOfDay(for: old)), "Older than the retention window")
        XCTAssertEqual(loaded.count, 1)
    }
}
