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
        let trend = WeightTrendBuilder.build(from: points, now: day(14))
        XCTAssertEqual(try XCTUnwrap(trend.weeklyChangeLbs), -1.4, accuracy: 0.01)
    }

    /// The owner's case: a few missed days. The comparison point is 10 days back, so the
    /// change is scaled to a week instead of being reported as one.
    func testMissedDaysScaleTheChangeToAWeek() throws {
        let points = weights((0...6).map { ($0, 200.0) } + (10...16).map { ($0, 198.0) })
        let trend = WeightTrendBuilder.build(from: points, now: day(16))
        XCTAssertEqual(try XCTUnwrap(trend.weeklyChangeLbs), -2.0 / 10.0 * 7.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(trend.weeklyChangePct), (-1.4 / 198.0) * 100, accuracy: 0.01)
    }

    /// A month between weigh-ins is not a weekly rate at all.
    func testAMonthGapGivesNoWeeklyRate() {
        let trend = WeightTrendBuilder.build(from: weights([(0, 200), (30, 194)]), now: day(30))
        XCTAssertNil(trend.weeklyChangeLbs)
        XCTAssertNil(trend.weeklyChangePct)
    }

    func testAComparisonMoreThanTwoWeeksBackGivesNoWeeklyRate() {
        let before = (0...6).map { ($0, 200.0) }
        let after = (15...21).map { ($0, 198.0) }
        // Newest point on or before day 14 is day 6: 15 days back.
        XCTAssertNil(WeightTrendBuilder.build(from: weights(before + after), now: day(21)).weeklyChangeLbs)
    }

    /// A "7-day average" holding one or two weigh-ins is a raw reading, not a trend.
    func testSparseWindowsGiveNoWeeklyRate() {
        let everyFourthDay = stride(from: 0, through: 16, by: 4).map { ($0, 200 - Double($0) * 0.2) }
        XCTAssertNil(WeightTrendBuilder.build(from: weights(everyFourthDay), now: day(16)).weeklyChangeLbs)
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
        // Change of the smoothed trend between the first and last measurement days. Each end
        // needs a 7-day average of at least 3 weigh-ins (follow-up review 2026-11-24), so the
        // start is day 2's average (days 0-2, centre day 1) and the end day 70's (days 64-70,
        // centre day 67): 66 days of 0.45/7 lb.
        XCTAssertEqual(try XCTUnwrap(snapshot.weightChangeLbs), 0.45 / 7 * 66, accuracy: 0.01)
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
        // Start: day 2's average of days 0-2 (200 - 3/56); end: 197.
        XCTAssertEqual(try XCTUnwrap(snapshot.weightChangeLbs), -(3.0 - 3.0 / 56), accuracy: 0.01)
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

    // MARK: - Follow-up review 2026-11-24 (scientist and auditor findings)

    private func entry(_ offset: Int, waist: Double, standard: Bool) -> MeasurementTrendInput {
        MeasurementTrendInput(date: day(offset), waistIn: waist, neckIn: nil, hipsIn: nil, chestIn: nil,
                              rightArmIn: nil, leftArmIn: nil, rightThighIn: nil, leftThighIn: nil,
                              isStandard: standard, bodyweightLbs: nil)
    }

    /// Waist up 0.6 in with weight flat used to read "Stable — No Meaningful Change".
    func testWaistUpWeightFlatHasItsOwnVerdict() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 32.0), entry(28, waist: 32.3), entry(56, waist: 32.6)],
            weightPoints: dailyWeights(through: 56) { _ in 180 }
        )
        XCTAssertEqual(snapshot.interpretation, .waistUpWeightSteady)
    }

    /// A half-inch tape step lands exactly on the threshold, and must count.
    func testExactlyHalfAnInchCounts() {
        let down = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 32.5), entry(28, waist: 32.2), entry(56, waist: 32.0)],
            weightPoints: dailyWeights(through: 56) { _ in 180 }
        )
        XCTAssertEqual(down.interpretation, .likelyRecomposition)
        // 32.3 - 31.8 is just under 0.5 in floating point; rounding to 0.01 in makes it 0.5.
        let up = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 31.8), entry(28, waist: 32.0), entry(56, waist: 32.3)],
            weightPoints: dailyWeights(through: 56) { _ in 180 }
        )
        XCTAssertEqual(up.interpretation, .waistUpWeightSteady)
    }

    /// The first weigh-in alone must not stand in for a 7-day average.
    func testASingleEarlyWeighInIsNotTheStartingTrend() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0), entry(28, waist: 32.7), entry(56, waist: 32.4)],
            weightPoints: weights([(0, 181)] + (1...56).map { ($0, 180.0) })
        )
        XCTAssertEqual(snapshot.interpretation, .likelyRecomposition)
    }

    /// With two or more standard entries, a non-standard one does not decide the trend.
    func testNonStandardEntriesStayOutWhenTwoStandardOnesExist() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 34.0, standard: true), entry(28, waist: 34.0, standard: true),
                      entry(56, waist: 35.0, standard: false)],
            weightPoints: dailyWeights(through: 56) { _ in 180 }
        )
        XCTAssertEqual(snapshot.sessionsCount, 2)
        XCTAssertEqual(try XCTUnwrap(snapshot.waistChangeIn), 0, accuracy: 0.001)
    }

    /// Measurements older than 30 days stop being presented as the current trend.
    func testATrendGoesStaleAfterThirtyDays() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0), entry(28, waist: 32.7), entry(56, waist: 32.4)],
            weightPoints: dailyWeights(through: 56) { _ in 180 }
        )
        XCTAssertEqual(snapshot.latestEntryDate, day(56))
        XCTAssertFalse(snapshot.isStale(now: day(56 + 29)))
        XCTAssertTrue(snapshot.isStale(now: day(56 + 31)))
        XCTAssertNil(BodyTrendHeadline.headline(for: snapshot, proteinCaveat: nil, now: day(56 + 31)))
        XCTAssertNotNil(BodyTrendHeadline.headline(for: snapshot, proteinCaveat: nil, now: day(56)))
    }

    /// No weekly rate when the last weigh-in is more than a week old.
    func testWeeklyRateNeedsARecentWeighIn() {
        let points = weights((0...14).map { ($0, 200 - 0.2 * Double($0)) })
        XCTAssertNotNil(WeightTrendBuilder.build(from: points, now: day(21)).weeklyChangeLbs)
        XCTAssertNil(WeightTrendBuilder.build(from: points, now: day(22)).weeklyChangeLbs)
    }

    // MARK: - The Dashboard headline says what the verdict says

    func testFatLossWithASteadyWaistDoesNotClaimBothDown() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0), entry(28, waist: 33.0), entry(56, waist: 32.9)],
            weightPoints: dailyWeights(through: 56) { 182 - 2.0 * Double($0) / 56 }
        )
        XCTAssertEqual(snapshot.interpretation, .likelyFatLoss)
        let headline = try XCTUnwrap(BodyTrendHeadline.headline(for: snapshot, proteinCaveat: nil, now: day(56)))
        XCTAssertFalse(headline.message.contains("both down"), headline.message)
    }

    func testRecompositionWithWeightUpDoesNotClaimWeightStable() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0), entry(28, waist: 32.7), entry(56, waist: 32.4)],
            weightPoints: dailyWeights(through: 56) { 180 + 1.5 * Double($0) / 56 }
        )
        XCTAssertEqual(snapshot.interpretation, .likelyRecomposition)
        let headline = try XCTUnwrap(BodyTrendHeadline.headline(for: snapshot, proteinCaveat: nil, now: day(56)))
        XCTAssertFalse(headline.message.contains("weight stable"), headline.message)
    }

    func testMassGainWithASteadyWaistSaysSo() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0), entry(28, waist: 33.0), entry(56, waist: 33.1)],
            weightPoints: dailyWeights(through: 56) { 180 + 2.0 * Double($0) / 56 }
        )
        XCTAssertEqual(snapshot.interpretation, .likelyMassGain)
        let headline = try XCTUnwrap(BodyTrendHeadline.headline(for: snapshot, proteinCaveat: nil, now: day(56)))
        XCTAssertEqual(headline.message, "Weight up, waist steady — check your lifts before changing anything")
    }

    func testWaistUpWeightSteadyHeadlineAsksForARemeasure() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 32.0), entry(28, waist: 32.3), entry(56, waist: 32.6)],
            weightPoints: dailyWeights(through: 56) { _ in 180 }
        )
        let headline = try XCTUnwrap(BodyTrendHeadline.headline(for: snapshot, proteinCaveat: nil, now: day(56)))
        XCTAssertEqual(headline.message, "Waist up, weight steady — re-measure at your usual time before changing anything")
        XCTAssertEqual(headline.tone, .attention)
    }

    // MARK: - Round 3 (scientist consult 2026-11-24)

    /// Waist up while weight fell is its own verdict, worded as a likely measuring difference.
    func testWaistUpWhileWeightFellIsNotCalledSteady() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 32.0), entry(28, waist: 32.3), entry(56, waist: 32.6)],
            weightPoints: dailyWeights(through: 56) { 183 - 3.0 * Double($0) / 56 }
        )
        XCTAssertEqual(snapshot.interpretation, .waistUpWeightDown)
        let headline = try XCTUnwrap(BodyTrendHeadline.headline(for: snapshot, proteinCaveat: nil, now: day(56)))
        XCTAssertFalse(headline.message.contains("weight steady"), headline.message)
        XCTAssertEqual(headline.message, "Waist up while weight fell — likely a measuring difference; re-measure at your usual time")
    }

    // MARK: - Round 3 checks (scientist and design reviews)

    /// The AI line must not read "fell -2.79 lb".
    func testTheAILineHasNoDoubleMinus() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 32.0), entry(28, waist: 32.3), entry(56, waist: 32.6)],
            weightPoints: dailyWeights(through: 56) { 183 - 3.0 * Double($0) / 56 }
        )
        let prompt = AnalysisMeasurementSnapshot(trend: snapshot).promptDescription
        XCTAssertFalse(prompt.contains("fell -"), prompt)
    }

    /// Two weight averages only days apart are not a change over the span.
    func testWeightEndsMustBeAWeekApart() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 32.0), entry(7, waist: 32.3), entry(14, waist: 32.6)],
            weightPoints: weights([(5, 180), (6, 179.5), (7, 179), (8, 178.5), (9, 178)])
        )
        XCTAssertNil(snapshot.weightChangeLbs)
        XCTAssertNotEqual(snapshot.interpretation, .waistUpWeightSteady)
    }

    /// With no waist comparison the headline must not claim the waist was steady.
    func testNoWaistComparisonIsNotCalledSteady() throws {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: nil), entry(28, waist: 33.0), entry(56, waist: 33.0)],
            weightPoints: dailyWeights(through: 56) { 182 - 2.0 * Double($0) / 56 }
        )
        XCTAssertNil(snapshot.waistChangeIn)
        let headline = try XCTUnwrap(BodyTrendHeadline.headline(for: snapshot, proteinCaveat: nil, now: day(56)))
        XCTAssertFalse(headline.message.contains("waist steady"), headline.message)
    }

    /// A measurement taken today keeps the trend current even when it is non-standard and so
    /// left out of the trend's span (devil's advocate, round 3 check).
    func testAFreshNonStandardEntryKeepsTheTrendCurrent() {
        let snapshot = MeasurementTrendSnapshotBuilder.build(
            entries: [entry(0, waist: 33.0, standard: true), entry(40, waist: 32.8, standard: true),
                      entry(80, waist: 33.5, standard: false)],
            weightPoints: dailyWeights(through: 80) { _ in 180 }
        )
        XCTAssertFalse(snapshot.isStale(now: day(80)))
    }
}
