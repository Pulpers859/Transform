import XCTest
@testable import Transform

/// Council review of 2026-11-23 (owner-approved items 1 and 2).
///
/// 1. `WeightTrendBuilder.weeklyChangeLbs` compared the current 7-day average with the newest
///    point on or before 7 days earlier, however old that point was, and called the whole
///    difference "per week". 200 lb on Oct 1 and 194 lb on Oct 31 read "-6.0 lb / week".
/// 2. `MeasurementTrendSnapshotBuilder` judged a waist change measured across EVERY entry ever
///    logged against a ONE-WEEK weight change, and labelled it "over 90 days" whatever the real
///    span was. A steady 10-week gain read "Stable"; a 3 lb loss followed by a two-week stall
///    read "Likely Recomposition" (which tells the body-analysis prompt to keep macros).
final class BodyTrendHonestyTests: XCTestCase {
    private let calendar = Calendar.current
    private lazy var base: Date = {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 1; parts.day = 5; parts.hour = 12
        return calendar.date(from: parts)!
    }()

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func weights(_ pairs: [(Int, Double)]) -> [AnalysisLoggedWeightPoint] {
        pairs.map { AnalysisLoggedWeightPoint(date: day($0.0), weightLbs: $0.1) }
    }

    private func entry(_ offset: Int, waist: Double?) -> MeasurementTrendInput {
        MeasurementTrendInput(
            date: day(offset),
            waistIn: waist,
            neckIn: nil,
            hipsIn: nil,
            chestIn: nil,
            rightArmIn: nil,
            leftArmIn: nil,
            rightThighIn: nil,
            leftThighIn: nil,
            isStandard: true,
            bodyweightLbs: nil
        )
    }

    // MARK: - 1. Weekly weight change

    /// Daily weigh-ins: unchanged behaviour (the comparison point is exactly 7 days back).
    func testDailyWeighInsGiveTheTrueWeeklyRate() throws {
        let points = weights((0...14).map { ($0, 200 - 0.2 * Double($0)) })
        let trend = WeightTrendBuilder.build(from: points)
        XCTAssertEqual(try XCTUnwrap(trend.weeklyChangeLbs), -1.4, accuracy: 0.01)
    }

    /// The owner's case: a few missed days. The comparison point is 10 days back, so the
    /// change is scaled to a week instead of being reported as one.
    func testMissedDaysScaleTheChangeToAWeek() throws {
        let points = weights((0...6).map { ($0, 200.0) } + (10...16).map { ($0, 198.0) })
        let trend = WeightTrendBuilder.build(from: points)
        XCTAssertEqual(try XCTUnwrap(trend.weeklyChangeLbs), -2.0 / 10.0 * 7.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(trend.weeklyChangePct), (-1.4 / 198.0) * 100, accuracy: 0.01)
    }

    /// A month between weigh-ins is not a weekly rate at all.
    func testAMonthGapGivesNoWeeklyRate() {
        let trend = WeightTrendBuilder.build(from: weights([(0, 200), (30, 194)]))
        XCTAssertNil(trend.weeklyChangeLbs)
        XCTAssertNil(trend.weeklyChangePct)
    }

    func testAComparisonMoreThanTwoWeeksBackGivesNoWeeklyRate() {
        let before = (0...6).map { ($0, 200.0) }
        let after = (15...21).map { ($0, 198.0) }
        // Newest point on or before day 14 is day 6: 15 days back.
        XCTAssertNil(WeightTrendBuilder.build(from: weights(before + after)).weeklyChangeLbs)
    }

    /// A "7-day average" holding one or two weigh-ins is a raw reading, not a trend.
    func testSparseWindowsGiveNoWeeklyRate() {
        let everyFourthDay = stride(from: 0, through: 16, by: 4).map { ($0, 200 - Double($0) * 0.2) }
        XCTAssertNil(WeightTrendBuilder.build(from: weights(everyFourthDay)).weeklyChangeLbs)
    }

    // MARK: - 2. Waist-versus-weight verdict

    private func dailyWeights(through last: Int, _ value: (Int) -> Double) -> [AnalysisLoggedWeightPoint] {
        weights((0...last).map { ($0, value($0)) })
    }

    /// Steady lean gain, 0.45 lb a week for 10 weeks, waist +0.6 in.
    func testSteadyGainReadsAsMassGain() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 32.0), entry(35, waist: 32.3), entry(70, waist: 32.6)],
            weightPoints: dailyWeights(through: 70) { 180 + 0.45 / 7 * Double($0) }
        )
        XCTAssertEqual(snapshot.interpretation, .likelyMassGain)
        // Change of the smoothed trend between the first and last measurement days.
        XCTAssertEqual(try XCTUnwrap(snapshot.weightChangeLbs), 0.45 / 7 * 67, accuracy: 0.05)
        XCTAssertEqual(snapshot.lookbackDays, 70)
    }

    func testSlowGainReadsAsMassGain() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 32.0), entry(35, waist: 32.3), entry(70, waist: 32.6)],
            weightPoints: dailyWeights(through: 70) { 180 + 0.2 / 7 * Double($0) }
        )
        XCTAssertEqual(snapshot.interpretation, .likelyMassGain)
    }

    /// Lost 3 lb over 8 weeks, then held for 2: fat loss, not recomposition.
    func testLossThenStallReadsAsFatLoss() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 34.0), entry(35, waist: 33.6), entry(70, waist: 33.2)],
            weightPoints: dailyWeights(through: 70) { $0 <= 56 ? 200 - 3.0 * Double($0) / 56 : 197 }
        )
        XCTAssertEqual(snapshot.interpretation, .likelyFatLoss)
        XCTAssertEqual(try XCTUnwrap(snapshot.weightChangeLbs), -3.0, accuracy: 0.05)
        XCTAssertEqual(snapshot.waistToWeightRatio, "Both decreasing — fat loss pattern")
    }

    /// The real thing: weight about level, waist down 0.6 in over 8 weeks.
    func testRecompositionStillReadsAsRecomposition() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0), entry(28, waist: 32.7), entry(56, waist: 32.4)],
            weightPoints: dailyWeights(through: 56) { 180 + 0.4 * Double($0) / 56 }
        )
        XCTAssertEqual(snapshot.interpretation, .likelyRecomposition)
        // The sentence must agree with the badge: +0.38 lb is "stable", not "weight up".
        XCTAssertEqual(snapshot.waistToWeightRatio, "Waist decreasing while weight stable — recomposition signal")
    }

    /// The badge and the sentence must never disagree: a 0.38 lb loss is "stable" weight.
    func testSmallLossWithWaistDownSentenceAgreesWithBadge() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0), entry(28, waist: 32.7), entry(56, waist: 32.4)],
            weightPoints: dailyWeights(through: 56) { 180 - 0.4 * Double($0) / 56 }
        )
        XCTAssertEqual(snapshot.interpretation, .likelyRecomposition)
        XCTAssertEqual(snapshot.waistToWeightRatio, "Waist decreasing while weight stable — recomposition signal")
    }

    /// No weigh-ins over the measured span: unknown, not "no change".
    func testMissingWeightIsUnknownNotZero() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0), entry(28, waist: 32.7), entry(56, waist: 32.4)],
            weightPoints: []
        )
        XCTAssertNil(snapshot.weightChangeLbs)
        XCTAssertEqual(snapshot.interpretation, .insufficientData)
        XCTAssertNil(snapshot.waistToWeightRatio)
    }

    /// Entries older than 90 days before the latest are not part of the current trend, and the
    /// label states the real span.
    func testOldEntriesAreLeftOutAndTheSpanIsReal() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(-200, waist: 36.0), entry(-30, waist: 33.0), entry(0, waist: 33.1)],
            weightPoints: []
        )
        XCTAssertEqual(snapshot.sessionsCount, 2)
        XCTAssertEqual(try XCTUnwrap(snapshot.waistChangeIn), 0.1, accuracy: 0.001)
        XCTAssertEqual(snapshot.lookbackDays, 30)
    }

    /// Measuring rarely still gives a comparison with the previous entry, labelled honestly.
    func testRareMeasurementsCompareWithThePreviousEntry() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(-300, waist: 34.0), entry(-150, waist: 33.5), entry(0, waist: 33.0)],
            weightPoints: []
        )
        XCTAssertEqual(snapshot.sessionsCount, 2)
        XCTAssertEqual(try XCTUnwrap(snapshot.waistChangeIn), -0.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.lookbackDays, 150)
    }
}
