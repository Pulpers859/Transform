import Foundation
import XCTest
@testable import Transform

/// The session time budget used to come from the recovery tier alone. The app separately recorded
/// every movement the lifter abandoned for time — one of his had been skipped for time three
/// separate times — printed that count into the prompt, and then planned the next week to exactly
/// the same length as if it had never happened. A plan he cannot finish is not a plan he is
/// following, and the exercises that lose are always the ones at the end of the day.
///
/// The budget now answers to whether he actually finishes his sessions.
@MainActor
final class UnfinishedSessionBudgetTests: XCTestCase {

    private let service = ClaudeService.shared

    /// Copied verbatim from `RecoveryModulationTests` so the initialiser labels stay correct.
    private func blankAnalysis() -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: "", trainingAssessment: "", nutritionAssessment: "",
            recoveryRiskAssessment: "", adherenceAssessment: "", analysisLimitations: "",
            inputContext: nil, regionBreakdown: [], topLeverageChange: "",
            priorityMuscles: [], workoutRecommendations: [], dietRecommendations: [],
            posturalNotes: "", estimatedBodyFat: "", metabolicHealthNotes: "",
            psychologicalInsights: "", injuryRiskNotes: "", macroTargets: nil,
            structuredTrainingIntent: nil
        )
    }

    private func cap(unfinished: Int) -> Int {
        service.calibrationProfile(
            from: blankAnalysis(),
            unfinishedMovementCount: unfinished
        ).defaultSessionTimeCapMinutes
    }

    /// The baseline must be untouched when there is nothing to learn from, so a lifter who
    /// finishes his sessions sees no change at all.
    func testNoUnfinishedHistoryLeavesTheBudgetAlone() {
        let baseline = cap(unfinished: 0)
        XCTAssertGreaterThan(baseline, 0)
        XCTAssertEqual(cap(unfinished: 0), baseline)
    }

    func testOneRepeatedlyUnfinishedMovementTrimsTheBudget() {
        XCTAssertEqual(cap(unfinished: 1), cap(unfinished: 0) - 5)
    }

    func testTwoOrMoreUnfinishedMovementsTrimTheBudgetFurther() {
        XCTAssertEqual(cap(unfinished: 2), cap(unfinished: 0) - 10)
    }

    /// The point is a session he completes, not a program that shrinks every time a shift runs
    /// long. The trim must stop.
    func testTheTrimIsCappedRatherThanCompounding() {
        let floorOfTrim = cap(unfinished: 2)
        for many in [3, 5, 12, 40] {
            XCTAssertEqual(
                cap(unfinished: many),
                floorOfTrim,
                "\(many) unfinished movements must not keep shrinking the week"
            )
        }
    }

    /// A negative count is nonsense input; it must never EXTEND the session.
    func testANegativeCountCannotLengthenTheSession() {
        XCTAssertEqual(cap(unfinished: -3), cap(unfinished: 0))
    }

    /// Well clear of anything the trim loops could turn into a short-menu hard failure: they only
    /// reduce sets down to `minimumSetFloor`, and drop a movement solely while a day still holds
    /// more than five.
    func testTheBudgetNeverFallsBelowTheFloor() {
        for count in [0, 1, 2, 10, 100] {
            XCTAssertGreaterThanOrEqual(cap(unfinished: count), 45)
        }
    }

    /// The trim rides on top of the recovery tier rather than replacing it, so a badly-slept week
    /// that is also going unfinished gets both reductions.
    func testTheTrimStacksWithTheRecoveryTier() {
        let restricted = service.calibrationProfile(
            from: blankAnalysis(),
            recoveryDecision: SleepRecoveryPolicy.decision(from: restrictedSleepState()),
            unfinishedMovementCount: 2
        )
        let restrictedOnly = service.calibrationProfile(
            from: blankAnalysis(),
            recoveryDecision: SleepRecoveryPolicy.decision(from: restrictedSleepState()),
            unfinishedMovementCount: 0
        )

        XCTAssertEqual(restricted.recoveryTier, .restricted)
        XCTAssertEqual(restricted.defaultSessionTimeCapMinutes, restrictedOnly.defaultSessionTimeCapMinutes - 10)
    }

    /// Every per-style cap is derived from the same default, so the trim must reach all of them
    /// rather than only the days that happen to use the default directly.
    func testThePerStyleCapsInheritTheTrim() {
        let trimmed = service.calibrationProfile(from: blankAnalysis(), unfinishedMovementCount: 2)
        let baseline = service.calibrationProfile(from: blankAnalysis(), unfinishedMovementCount: 0)

        for style in ["Push", "Pull", "Upper", "Lower", "Legs"] {
            guard let trimmedCap = trimmed.sessionTimeCapsByStyle[style],
                  let baselineCap = baseline.sessionTimeCapsByStyle[style] else {
                XCTFail("Missing style cap for \(style)")
                continue
            }
            XCTAssertEqual(trimmedCap, baselineCap - 10, "\(style) did not inherit the trim")
        }
    }

    // MARK: - Helpers

    /// Acute restriction — a three-day average under 6h is a documented Restricted trigger
    /// (SLEEP-001). Field labels copied from `RecoveryModulationTests`.
    private func restrictedSleepState() -> SleepRecoveryState {
        SleepRecoveryState(
            builtAt: Date(),
            threeDayAverageHours: 5.2,
            sevenDayAverageHours: 5.4,
            acuteLoggedDays: 3,
            loggedDays: 7,
            daysUnderFive: 2,
            daysUnderSix: 3,
            variabilityHours: 1.1,
            recentPostCall: false
        )
    }
}
