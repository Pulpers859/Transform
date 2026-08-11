import XCTest
@testable import Transform

/// Coverage for the exercise-card state resolver.
///
/// Every case here was a real contradiction visible on one screen in a live Day 11 session.
/// The card assembled itself from four sources on different time windows and nothing
/// reconciled them, so it could crown a personal best and question that same number four
/// lines apart, or show a lift with zero logged sets wearing the completed treatment.
@MainActor
final class ExerciseSessionSummaryTests: XCTestCase {

    // MARK: - Builders

    private func set(_ number: Int, weight: Double = 100, reps: Int, rir: Double? = nil) -> SetLogEntry {
        SetLogEntry(setNumber: number, weightLbs: weight, repsCompleted: reps, rir: rir)
    }

    private func resolve(
        isCompleted: Bool = false,
        status: ExerciseCompletionStatus? = nil,
        plannedSets: Int = 3,
        reps: String = "8-12",
        targetRIR: Int? = 2,
        today: [SetLogEntry] = [],
        previous: [SetLogEntry] = [],
        bestWeight: Double? = nil,
        bestReps: Int? = nil,
        bestLoggedAt: Date? = nil,
        now: Date = .now
    ) -> ExerciseSessionSummary {
        ExerciseSessionSummary.resolve(
            isCompleted: isCompleted,
            completionStatus: status,
            plannedSets: plannedSets,
            reps: reps,
            targetRIR: targetRIR,
            todaysSets: today,
            previousSets: previous,
            bestWeightLbs: bestWeight,
            bestReps: bestReps,
            bestLoggedAt: bestLoggedAt,
            now: now
        )
    }

    // MARK: - State

    /// The live contradiction: Dumbbell Bench Press showed a green completed check beside an
    /// orange "Log sets 0/2", and the day header counted it toward 6/6.
    func testCompletedWithNothingLoggedIsNotACleanCompletion() {
        let summary = resolve(isCompleted: true, plannedSets: 2, today: [])

        XCTAssertEqual(summary.state, .completedModified(logged: 0, planned: 2))
        XCTAssertFalse(summary.state.isCleanCompletion)
        XCTAssertTrue(summary.state.isCompletedWithoutWork)
        XCTAssertTrue(summary.needsLoggingPrompt, "Nothing from this lift reaches history — the card must offer a way to fix that")
        XCTAssertEqual(summary.state.qualifierLabel, "Done · nothing logged")
    }

    func testCompletedWithEverySetLoggedIsClean() {
        let summary = resolve(isCompleted: true, plannedSets: 2, today: [set(1, reps: 10), set(2, reps: 9)])

        XCTAssertEqual(summary.state, .completedAsPlanned(logged: 2))
        XCTAssertTrue(summary.state.isCleanCompletion)
        XCTAssertNil(summary.state.qualifierLabel, "A lift done as written needs no qualifier")
        XCTAssertEqual(summary.adherence, [], "Work matching the prescription raises nothing")
    }

    func testPartiallyLoggedCompletionIsQualified() {
        let summary = resolve(isCompleted: true, plannedSets: 3, today: [set(1, reps: 10)])

        XCTAssertEqual(summary.state, .completedModified(logged: 1, planned: 3))
        XCTAssertEqual(summary.state.qualifierLabel, "Done · modified")
        XCTAssertTrue(summary.adherence.contains(.setsIncomplete(logged: 1, planned: 3)))
    }

    /// Skips set `isCompleted = true` at the call site, so checking completion first would
    /// read a skipped lift as a finished one.
    func testSkipWinsOverTheCompletionFlag() {
        for status: ExerciseCompletionStatus in [.skippedTime, .skippedEquipment, .skippedPain] {
            let summary = resolve(isCompleted: true, status: status, today: [])

            XCTAssertEqual(summary.state, .skipped(status))
            XCTAssertFalse(summary.state.isCleanCompletion)
            XCTAssertTrue(summary.state.isResolved, "A skip is finished business for today")
        }
    }

    /// A substitution is work the lifter still performs, so it must not read as resolved.
    func testSubstitutionIsNotResolved() {
        let summary = resolve(isCompleted: false, status: .substituted)

        XCTAssertEqual(summary.state, .substituted)
        XCTAssertFalse(summary.state.isResolved)
    }

    func testUntouchedAndInProgressAreDistinct() {
        XCTAssertEqual(resolve().state, .notStarted)
        XCTAssertEqual(resolve(today: [set(1, reps: 10)]).state, .inProgress(logged: 1, planned: 3))
    }

    // MARK: - Best record

    /// The headline fix. "Last" excludes today and "Best" includes it, which is defensible
    /// individually and incoherent stacked in one box: the card showed "Last 40 lb x 15" above
    /// "Best 50 lb · 14 reps" where the 50 lb was logged minutes earlier, while a warning
    /// below asked the lifter to confirm that same 50 lb was not a mis-log.
    func testBestKnowsWhenItWasSetToday() {
        let now = Date()
        let summary = resolve(
            today: [set(2, weight: 50, reps: 14)],
            previous: [set(1, weight: 40, reps: 15)],
            bestWeight: 50, bestReps: 14, bestLoggedAt: now, now: now
        )

        XCTAssertEqual(summary.best?.wasSetToday, true)
        XCTAssertEqual(summary.previous?.setCount, 1)
    }

    func testHistoricalBestIsNotClaimedAsToday() {
        let now = Date()
        let summary = resolve(
            bestWeight: 90, bestReps: 10,
            bestLoggedAt: now.addingTimeInterval(-8 * 86_400), now: now
        )

        XCTAssertEqual(summary.best?.wasSetToday, false)
    }

    /// Older summary rows predate best-date tracking. Claiming "today" on missing evidence is
    /// the worse error, because it is the claim that changes what the lifter is told.
    func testBestWithNoTimestampIsTreatedAsHistorical() {
        let summary = resolve(bestWeight: 90, bestReps: 10, bestLoggedAt: nil)

        XCTAssertEqual(summary.best?.wasSetToday, false)
    }

    // MARK: - Adherence (observability only)

    /// Live: Machine Lateral Raise Set 1 logged 15 reps at RIR 4 against a 10-14 / RIR 2
    /// prescription, counted toward "2/2 complete" and toward progression, flagged by nothing.
    func testRepsPastTheRangeAreFlagged() {
        let summary = resolve(reps: "10-14", targetRIR: 2, today: [set(1, weight: 40, reps: 15, rir: 4)])

        XCTAssertTrue(summary.adherence.contains(.repsAboveRange(setNumber: 1, reps: 15, high: 14)))
        XCTAssertTrue(summary.adherence.contains(.effortUnderTarget(setNumber: 1, rir: 4, target: 2)))
    }

    func testRepsUnderTheRangeAreFlagged() {
        let summary = resolve(reps: "8-12", today: [set(1, reps: 6)])

        XCTAssertTrue(summary.adherence.contains(.repsBelowRange(setNumber: 1, reps: 6, low: 8)))
    }

    /// One RIR of drift is self-report noise, not a different kind of set.
    func testEffortWithinOneRIROfTargetIsNotFlagged() {
        let summary = resolve(reps: "8-12", targetRIR: 2, today: [set(1, reps: 10, rir: 3)])

        XCTAssertEqual(summary.adherence, [])
    }

    /// `rir` is optional by design so legacy sessions never acquire invented effort data. An
    /// absent value must not be read as zero.
    func testMissingEffortIsNeverInventedAsAFlag() {
        let summary = resolve(reps: "8-12", targetRIR: 2, today: [set(1, reps: 10, rir: nil)])

        XCTAssertEqual(summary.adherence, [])
    }

    /// An unparseable rep string ("AMRAP", "8-12 per side") must not manufacture flags.
    func testUnparseableRepRangeRaisesNothing() {
        let summary = resolve(reps: "AMRAP", targetRIR: nil, today: [set(1, reps: 25)])

        XCTAssertNil(summary.repRange)
        XCTAssertEqual(summary.adherence, [])
    }

    /// Notices describe what happened; they never tell the lifter what to load. The
    /// progression banner is the single voice that owns that, and a second voice here would
    /// recreate the contradiction the display filter exists to strip.
    func testNoticeTextNeverGivesLoadAdvice() {
        let notices = [
            ExerciseSessionSummary.AdherenceFlag.repsAboveRange(setNumber: 1, reps: 15, high: 14),
            .repsBelowRange(setNumber: 2, reps: 6, low: 8),
            .effortUnderTarget(setNumber: 1, rir: 4, target: 2),
            .setsIncomplete(logged: 0, planned: 2),
            .setsIncomplete(logged: 1, planned: 3)
        ].map(\.noticeText)

        for notice in notices {
            XCTAssertEqual(CoachingVoiceAudit.violations(in: notice), [], "Notice strays into progression advice: \(notice)")
        }
    }

    // MARK: - Plan vs history

    /// Live: a "3 sets" prescription displayed above "Last 75 lb x 12, 12, 12, 10" — four
    /// numbers. The history is real; the card just never said which count was which.
    func testPlannedSetsAndPreviousSetCountAreBothAvailable() {
        let summary = resolve(
            plannedSets: 3,
            previous: [set(1, reps: 12), set(2, reps: 12), set(3, reps: 12), set(4, reps: 10)]
        )

        XCTAssertEqual(summary.plannedSets, 3)
        XCTAssertEqual(summary.previous?.setCount, 4)
    }

    func testNoHistoryResolvesToNilRatherThanAnEmptyShell() {
        let summary = resolve()

        XCTAssertNil(summary.previous)
        XCTAssertNil(summary.best)
    }
}
