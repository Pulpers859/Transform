import XCTest
@testable import Transform

/// Pins the arithmetic that decides what the lifter is told to pick up when the PRESCRIPTION
/// changes — the gap that let the app say "add load" in the same week it handed over a rep
/// range needing less weight.
///
/// Every expected number here was computed independently before the Swift was written, so a
/// passing suite means the implementation matches the model rather than the model having been
/// reverse-engineered from whatever the code happened to do.
@MainActor
final class LoadTranslationTests: XCTestCase {

    private let service = ClaudeService.shared

    private func reference(_ load: Double, _ reps: Int, reserve: Double = 1, censored: Bool = false)
    -> WorkoutLoadTranslation.Reference {
        .init(loadLbs: load, repsAchieved: reps, reserveReps: reserve, hitPrescribedCeiling: censored)
    }

    private func target(_ sets: Int, floor: Int, rir: Double = 1) -> WorkoutLoadTranslation.Target {
        .init(sets: sets, repFloor: floor, targetRIR: rir)
    }

    private func translate(
        _ load: Double, _ reps: Int, sets: Int, floor: Int,
        decay: Double = WorkoutLoadTranslation.defaultFatigueDecayPerSet, increment: Double = 2.5
    ) throws -> WorkoutLoadTranslation.Outcome {
        try XCTUnwrap(WorkoutLoadTranslation.translate(
            reference: reference(load, reps),
            target: target(sets, floor: floor),
            fatigueDecayPerSet: decay,
            incrementLbs: increment
        ))
    }

    // MARK: - The scenario that started this

    /// 35 lb for 14 reps under a 10-14 target, then handed 3x15-20. The old engine said
    /// "add load" and would have recommended 37.5-40 lb.
    func testMoreRepsAndMoreSetsMeansLessWeightNotMore() throws {
        let outcome = try translate(35, 14, sets: 3, floor: 15)
        XCTAssertEqual(outcome.recommendedLoadLbs, 30.0, accuracy: 0.001)
        XCTAssertEqual(outcome.rawLoadLbs, 31.656, accuracy: 0.01)
        XCTAssertLessThan(outcome.recommendedLoadLbs, 35,
                          "The whole failure was recommending MORE weight for a harder prescription")
        XCTAssertFalse(outcome.isImplausibleSwing)
    }

    func testTheThirdSetIsWhatTheLoadIsChosenFor() throws {
        let outcome = try translate(35, 14, sets: 3, floor: 15)
        XCTAssertEqual(outcome.requiredFirstSetCapacity, 19.753, accuracy: 0.01,
                       "Set one must carry ~20 reps for set three to still reach 15")
    }

    // MARK: - Direction and magnitude in every case

    func testFewerRepsMeansMoreWeight() throws {
        let outcome = try translate(47, 20, sets: 3, floor: 8)
        XCTAssertEqual(outcome.recommendedLoadLbs, 57.5, accuracy: 0.001)
        XCTAssertGreaterThan(outcome.fractionOfReferenceLoad, 1)
    }

    /// The most important safety property: doing nothing when nothing changed.
    func testAnUnchangedPrescriptionLeavesTheLoadAlone() throws {
        let outcome = try translate(50, 20, sets: 3, floor: 15)
        XCTAssertEqual(outcome.recommendedLoadLbs, 50.0, accuracy: 0.001,
                       "Translation must never fight ordinary week-to-week progression")
        XCTAssertEqual(outcome.fractionOfReferenceLoad, 1.0, accuracy: 0.001)
    }

    func testAddingSetsAloneStillCostsWeight() throws {
        let outcome = try translate(50, 20, sets: 4, floor: 15)
        XCTAssertEqual(outcome.recommendedLoadLbs, 47.5, accuracy: 0.001,
                       "More sets is more fatigue even when the rep range is untouched")
    }

    func testASingleSetNeedsNoFatigueAllowance() throws {
        let outcome = try translate(35, 14, sets: 1, floor: 15)
        XCTAssertEqual(outcome.requiredFirstSetCapacity, 16.0, accuracy: 0.001)
        XCTAssertEqual(outcome.recommendedLoadLbs, 32.5, accuracy: 0.001)
    }

    // MARK: - The red flag

    func testAnEnormousSwingIsFlaggedRatherThanSilentlyObeyed() throws {
        let outcome = try translate(100, 5, sets: 3, floor: 20)
        XCTAssertTrue(outcome.isImplausibleSwing,
                      "A drop past a third means the jump is wrong, not that the load is")
        XCTAssertEqual(outcome.recommendedLoadLbs, 62.5, accuracy: 0.001,
                       "It still returns its honest answer — flagging is not clamping")
    }

    func testAnOrdinaryAdjustmentIsNotFlagged() throws {
        XCTAssertFalse(try translate(35, 14, sets: 3, floor: 15).isImplausibleSwing)
        XCTAssertFalse(try translate(47, 20, sets: 3, floor: 8).isImplausibleSwing)
    }

    // MARK: - Rounding and guards

    func testRoundingIsAlwaysDownToARealIncrement() throws {
        let outcome = try translate(35, 14, sets: 3, floor: 15)
        XCTAssertLessThanOrEqual(outcome.recommendedLoadLbs, outcome.rawLoadLbs,
                                 "Entering a block light costs one session; entering heavy costs weeks")
        XCTAssertEqual(outcome.recommendedLoadLbs.truncatingRemainder(dividingBy: 2.5), 0, accuracy: 0.001)
    }

    func testAVeryLightLiftNeverRoundsDownToNothing() throws {
        let outcome = try translate(5, 8, sets: 4, floor: 20, increment: 2.5)
        XCTAssertGreaterThanOrEqual(outcome.recommendedLoadLbs, 2.5,
                                    "A recommendation of zero pounds is not a recommendation")
    }

    func testNonsenseInputsReturnNothingRatherThanAGuess() {
        let t = target(3, floor: 15)
        XCTAssertNil(WorkoutLoadTranslation.translate(reference: reference(0, 14), target: t, incrementLbs: 2.5))
        XCTAssertNil(WorkoutLoadTranslation.translate(reference: reference(35, 0), target: t, incrementLbs: 2.5))
        XCTAssertNil(WorkoutLoadTranslation.translate(reference: reference(35, 14), target: t, incrementLbs: 0))
        XCTAssertNil(WorkoutLoadTranslation.translate(
            reference: reference(35, 14), target: target(0, floor: 15), incrementLbs: 2.5))
    }

    func testCensoringIsCarriedThroughSoConfidenceCanBeReported() throws {
        let outcome = try XCTUnwrap(WorkoutLoadTranslation.translate(
            reference: reference(35, 14, censored: true), target: target(3, floor: 15), incrementLbs: 2.5))
        XCTAssertTrue(outcome.referenceWasCensored,
                      "Hitting the top of a range is a lower bound on capacity, not a measurement")
    }

    // MARK: - Learning the lifter's own fatigue

    private func session(_ daysAgo: Int, weight: Double, reps: [Int], key: String = "face pull")
    -> WorkoutPerformanceLogSnapshot {
        .init(canonicalExerciseKey: key,
              loggedAt: Date(timeIntervalSince1970: 1_000_000 - Double(daysAgo) * 86_400),
              setLogs: reps.enumerated().map {
                  SetLogEntry(setNumber: $0.offset + 1, weightLbs: weight, repsCompleted: $0.element)
              })
    }

    private func decay(_ snaps: [WorkoutPerformanceLogSnapshot]) -> Double {
        WorkoutLoadTranslation.estimatedFatigueDecayPerSet(for: "face pull", from: snaps)
    }

    /// His real June 15 session: 47 lb for 20, 20, 15.
    func testFatigueIsMeasuredFromTheLiftersOwnSessions() {
        XCTAssertEqual(decay([session(0, weight: 47, reps: [20, 20, 15])]), 0.8887, accuracy: 0.001)
    }

    func testASessionWithNoDropStillShrinksTowardThePopulationValue() {
        XCTAssertEqual(decay([session(0, weight: 47, reps: [20, 20, 20])]), 0.9333, accuracy: 0.001,
                       "One flawless session is not proof this lifter never fatigues")
    }

    func testSessionsAreCombinedByMedian() {
        XCTAssertEqual(
            decay([session(0, weight: 47, reps: [20, 20, 15]), session(7, weight: 47, reps: [20, 20, 20])]),
            0.9165, accuracy: 0.001)
    }

    func testNoUsableSessionsFallsBackToThePopulationValue() {
        XCTAssertEqual(decay([]), WorkoutLoadTranslation.defaultFatigueDecayPerSet, accuracy: 0.001)
        XCTAssertEqual(decay([session(0, weight: 47, reps: [20])]),
                       WorkoutLoadTranslation.defaultFatigueDecayPerSet, accuracy: 0.001,
                       "A single-set session says nothing about fatigue across sets")
    }

    func testAnAbandonedSetCannotDragFatigueBelowThePlausibleFloor() {
        XCTAssertEqual(decay([session(0, weight: 47, reps: [20, 4])]),
                       WorkoutLoadTranslation.minimumFatigueDecayPerSet, accuracy: 0.001)
    }

    func testAnotherExercisesFatigueIsNotBorrowed() {
        XCTAssertEqual(decay([session(0, weight: 47, reps: [20, 20, 15], key: "lateral raise")]),
                       WorkoutLoadTranslation.defaultFatigueDecayPerSet, accuracy: 0.001)
    }

    // MARK: - Rep bands

    func testBandJumpsMeasureHowFarAPrescriptionMoved() {
        let r = { (lo: Int, hi: Int) in RepRange(low: lo, high: hi) }
        XCTAssertEqual(WorkoutLoadTranslation.bandJump(from: r(10, 14), to: r(15, 20)), 1,
                       "10-14 -> 15-20 is one band and is allowed")
        XCTAssertEqual(WorkoutLoadTranslation.bandJump(from: r(6, 8), to: r(15, 20)), 2,
                       "6-8 -> 15-20 is two bands and must be flagged")
        XCTAssertEqual(WorkoutLoadTranslation.bandJump(from: r(15, 20), to: r(15, 20)), 0)
        XCTAssertEqual(WorkoutLoadTranslation.bandJump(from: r(1, 5), to: r(20, 25)), 3)
        XCTAssertEqual(WorkoutLoadTranslation.bandJump(from: r(15, 20), to: r(6, 8)), 2,
                       "Distance is symmetric — leaping down is the same leap")
    }

    func testBandsAreClassifiedByMidpointNotEndpoints() {
        XCTAssertEqual(WorkoutLoadTranslation.band(for: RepRange(low: 10, high: 14)), .moderate)
        XCTAssertEqual(WorkoutLoadTranslation.band(for: RepRange(low: 15, high: 20)), .endurance)
        XCTAssertEqual(WorkoutLoadTranslation.band(for: RepRange(low: 3, high: 5)), .strength)
        XCTAssertEqual(WorkoutLoadTranslation.band(for: RepRange(low: 8, high: 12)), .heavy)
    }

    // MARK: - The validator backstop

    private func day(_ name: String, reps: String) -> WorkoutDayResponse {
        WorkoutDayResponse(
            dayNumber: 1, dayName: "Push", muscleGroups: "Shoulders", isRestDay: false, notes: "",
            exercises: [WorkoutExerciseResponse(
                exerciseName: name, sets: 3, reps: reps, tempo: "2-1-1-1",
                restSeconds: 75, notes: "Control the eccentric.", muscleTarget: "Rear Deltoids", targetRIR: 1)])
    }

    private func verdict(_ name: String, previous: RepRange?) -> ClaudeService.ExerciseProgressionVerdict {
        .init(canonicalKey: ExerciseWeightEntry.canonicalLookupKey(name),
              exerciseName: name, kind: .addLoad, weightLbs: 35, previousRepRange: previous)
    }

    func testATwoBandLeapIsReported() {
        let issues = service.validateRepRangeTransitions(
            days: [day("Cable Face Pull", reps: "15-20")],
            verdicts: [verdict("Cable Face Pull", previous: RepRange(low: 6, high: 8))])
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("2 rep bands"), issues[0])
    }

    func testAOneBandMoveIsLeftAlone() {
        XCTAssertTrue(service.validateRepRangeTransitions(
            days: [day("Cable Face Pull", reps: "15-20")],
            verdicts: [verdict("Cable Face Pull", previous: RepRange(low: 10, high: 14))]).isEmpty,
            "Deliberate phase changes are the AI's call and must not be nagged")
    }

    func testAnExerciseWithNoHistoryIsNotJudged() {
        XCTAssertTrue(service.validateRepRangeTransitions(
            days: [day("Cable Face Pull", reps: "15-20")],
            verdicts: [verdict("Cable Face Pull", previous: nil)]).isEmpty)
        XCTAssertTrue(service.validateRepRangeTransitions(
            days: [day("Cable Face Pull", reps: "15-20")], verdicts: []).isEmpty)
    }

    /// A guardrail that spends money to enforce a preference is worse than one that reports.
    ///
    /// Pinned on BOTH paths deliberately. An unclassified finding is an acceptable warning under
    /// menu-lock but a HARD FAILURE unlocked, so relying on every call site happening to pass
    /// `menuLocked: true` would make this rule safe only by accident — one new caller with the
    /// default argument would start discarding paid weeks with nothing to catch it.
    func testTheGuardrailNeverDiscardsAPaidWeekOnEitherPath() {
        let issue = service.validateRepRangeTransitions(
            days: [day("Cable Face Pull", reps: "15-20")],
            verdicts: [verdict("Cable Face Pull", previous: RepRange(low: 6, high: 8))])[0]
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .acceptableWarning)
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: false), .acceptableWarning,
                       "Unlocked, an unclassified finding would be a hard failure and discard the week")
        XCTAssertEqual(service.scoreValidationIssues([issue], menuLocked: true), 1)
        XCTAssertEqual(service.scoreValidationIssues([issue], menuLocked: false), 1)
    }

    /// The owner must get a sentence he can act on, not "this one isn't recognized".
    func testTheGuardrailExplainsItselfInPlainLanguage() {
        let issue = service.validateRepRangeTransitions(
            days: [day("Cable Face Pull", reps: "15-20")],
            verdicts: [verdict("Cable Face Pull", previous: RepRange(low: 6, high: 8))])[0]
        let notices = WorkoutValidatorNotice.notices(from: [issue])
        XCTAssertFalse(notices.contains { $0.headline == "A plan check didn't pass" },
                       "A finding this code CAN explain must never reach the unclassified fallback")
        XCTAssertTrue(notices.contains { $0.headline == "A rep range jumped further than usual" })
    }
}
