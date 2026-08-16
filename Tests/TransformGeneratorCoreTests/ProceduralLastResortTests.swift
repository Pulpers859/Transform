import XCTest
@testable import Transform

/// The procedural generator is the last resort in the generation chain. When it throws, the
/// owner does not get a simpler program — they get NO program, and `ClaudeError.parseError`
/// renders the raw validator text as the failure message.
///
/// It used to throw whenever any validator finding fell through `validationDisposition` to its
/// `.hardFailure` default. That default is the correct answer for paid AI output, where a retry
/// exists; it is the wrong answer here, where nothing comes next.
@MainActor
final class ProceduralLastResortTests: XCTestCase {

    private let service = ClaudeService.shared

    private func exercise(
        _ name: String = "Incline Dumbbell Press",
        sets: Int = 3,
        reps: String = "8-10"
    ) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: name,
            sets: sets,
            reps: reps,
            tempo: "3-0-1-0",
            restSeconds: 90,
            notes: "Keep the shoulders pulled away from your ears at the bottom of every rep.",
            muscleTarget: "Upper Chest"
        )
    }

    private func day(
        _ number: Int,
        isRestDay: Bool = false,
        exercises: [WorkoutExerciseResponse]? = nil
    ) -> WorkoutDayResponse {
        WorkoutDayResponse(
            dayNumber: number,
            dayName: isRestDay ? "Rest" : "Push",
            muscleGroups: isRestDay ? "" : "Chest, Shoulders, Triceps",
            isRestDay: isRestDay,
            notes: isRestDay ? "" : "Upper-body push emphasis.",
            exercises: isRestDay ? [] : (exercises ?? [exercise(), exercise("Cable Lateral Raise")])
        )
    }

    private var trainableWeek: [WorkoutDayResponse] {
        (1...7).map { day($0, isRestDay: $0 == 3 || $0 == 7) }
    }

    // MARK: - What the last resort is allowed to reject

    func testATrainableWeekIsNeverBlocked() {
        XCTAssertNil(service.proceduralOutputBlockingDefect(in: trainableWeek))
    }

    /// A week with nothing to do is the case the throw actually exists for.
    func testAllRestDaysIsBlocked() {
        let days = (1...7).map { day($0, isRestDay: true) }
        XCTAssertNotNil(service.proceduralOutputBlockingDefect(in: days))
    }

    func testTrainingDayWithNoExercisesIsBlocked() {
        var days = trainableWeek
        days[0] = WorkoutDayResponse(
            dayNumber: 1, dayName: "Push", muscleGroups: "Chest",
            isRestDay: false, notes: "Push.", exercises: []
        )
        XCTAssertEqual(service.proceduralOutputBlockingDefect(in: days), "day 1 is a training day with no exercises")
    }

    func testZeroSetPrescriptionIsBlocked() {
        var days = trainableWeek
        days[0] = day(1, exercises: [exercise("Incline Dumbbell Press", sets: 0)])
        XCTAssertNotNil(service.proceduralOutputBlockingDefect(in: days))
    }

    func testEmptyExerciseNameIsBlocked() {
        var days = trainableWeek
        days[0] = day(1, exercises: [exercise("   ")])
        XCTAssertEqual(service.proceduralOutputBlockingDefect(in: days), "day 1 contains an exercise with no name")
    }

    func testEmptyRepPrescriptionIsBlocked() {
        var days = trainableWeek
        days[0] = day(1, exercises: [exercise("Incline Dumbbell Press", reps: " ")])
        XCTAssertNotNil(service.proceduralOutputBlockingDefect(in: days))
    }

    // MARK: - What the last resort must NOT reject

    /// The whole point of the change, stated as the property that actually differs.
    ///
    /// This week is missing `targetRIR` and has a blank day name. Both raise validator findings
    /// that fall through `validationDisposition` to its `.hardFailure` default — under the old
    /// gate the run ended here and the owner got an error string. Neither makes the week
    /// untrainable, so the last resort must hand it over and let the findings travel as
    /// warnings. Asserted through the real validator so the premise cannot rot: if these stop
    /// producing hard-failing findings, the first two assertions fail and this test stops
    /// silently proving nothing.
    func testAWeekWithHardFailingFindingsStillShipsWhenItCanBeTrained() {
        var days = trainableWeek
        days[0] = WorkoutDayResponse(
            dayNumber: 1,
            dayName: "",
            muscleGroups: "Chest, Shoulders, Triceps",
            isRestDay: false,
            notes: "Upper-body push emphasis.",
            exercises: [exercise(), exercise("Cable Lateral Raise")]
        )

        let findings = service.validateDaySet(days, dayStart: 1, dayEnd: 7)
        XCTAssertTrue(
            findings.contains { $0.contains("has empty dayName") },
            "Premise broken — expected a hard-failing finding to exist: \(findings)"
        )
        XCTAssertTrue(
            findings.contains { service.validationDisposition(for: $0, menuLocked: true) == .hardFailure },
            "Premise broken — none of these findings would have erased the week: \(findings)"
        )

        XCTAssertNil(
            service.proceduralOutputBlockingDefect(in: days),
            "A trainable week must survive the last resort no matter what the findings say"
        )
    }

    /// A rest day legitimately has no exercises; only TRAINING days are checked.
    func testRestDaysAreNotTreatedAsEmptyTrainingDays() {
        XCTAssertNil(service.proceduralOutputBlockingDefect(in: trainableWeek))
        let mostlyRest = (1...7).map { day($0, isRestDay: $0 != 1) }
        XCTAssertNil(
            service.proceduralOutputBlockingDefect(in: mostlyRest),
            "Too few training days is a programming finding for the validator, not an unusable week"
        )
    }
}

/// BASE-001 (a major muscle group with zero direct sets) is a property of the locked exercise
/// MENU. In a menu-locked flow nothing downstream can add the missing movement: the AI is
/// forbidden from changing the menu and the procedural fallback consumes the same menu.
///
/// Treating it as a hard failure therefore cost the owner twice — it discarded every paid AI
/// candidate and skipped the correction pass that would have repaired the week's OTHER findings,
/// and then it made the fallback throw, so the week ended as an error string.
@MainActor
final class BaselineCoverageDispositionTests: XCTestCase {

    private let service = ClaudeService.shared

    private let baselineGap = "Muscle group 'Hamstrings' receives zero direct sets this week. BASE-001 requires every major muscle group to keep at least a minimal weekly exposure — even maintenance is not zero."

    func testBaselineGapShipsAsAWarningWhenTheMenuIsLocked() {
        XCTAssertEqual(
            service.validationDisposition(for: baselineGap, menuLocked: true),
            .acceptableWarning
        )
    }

    /// Without a locked menu the generator genuinely could still add the movement, so the strict
    /// disposition is kept there. This asserts the demotion is scoped, not blanket.
    func testBaselineGapStaysStrictWhenNoMenuIsLocked() {
        XCTAssertNotEqual(
            service.validationDisposition(for: baselineGap, menuLocked: false),
            .acceptableWarning
        )
    }

    /// The demotion must not become a way for the AI to quietly drop a menu exercise: a week
    /// that deviates from the locked menu carries a second, correction-worthy finding, and
    /// acceptance requires EVERY finding to be acceptable.
    func testMenuDeviationStillBlocksAcceptanceAlongsideABaselineGap() {
        let deviation = "Day 2 did not follow the Pre-Selected Exercise Menu at slot 3: expected Seated Leg Curl, but generated Leg Extension."
        XCTAssertEqual(service.validationDisposition(for: deviation, menuLocked: true), .correctionPass)
        XCTAssertFalse(
            service.shouldAcceptAIOutput(despite: [baselineGap, deviation], menuLocked: true)
        )
        XCTAssertTrue(
            service.shouldAcceptAIOutput(despite: [baselineGap], menuLocked: true),
            "A gap the menu owns and nothing downstream can fix must not deny the owner a program"
        )
    }

    /// The demotion's safety rests on a claim that has to be tested, not assumed: that when the
    /// AI causes the gap rather than inheriting it from the menu, a SECOND, correction-worthy
    /// finding always fires. Substitution is the easy case. This is the hard one — the AI simply
    /// DROPS the menu's only hamstring slot, so the day is a strict subset of the menu and a
    /// naive "does each produced exercise match a slot" check would find nothing wrong.
    ///
    /// Driven through the real `validateExerciseMenuAdherence` rather than a hand-written string,
    /// so it fails if that check ever stops catching omission.
    func testDroppingAMenuExerciseStillRaisesACorrectionWorthyFinding() {
        func menuItem(_ name: String, _ target: String, sets: Int) -> ClaudeService.PreSelectedExercise {
            ClaudeService.PreSelectedExercise(
                exerciseName: name,
                muscleTarget: target,
                movementPattern: "hinge",
                role: .accessory,
                prescribedSets: sets
            )
        }
        func produced(_ name: String, _ target: String, sets: Int) -> WorkoutExerciseResponse {
            WorkoutExerciseResponse(
                exerciseName: name, sets: sets, reps: "10-12", tempo: "3-0-1-0",
                restSeconds: 90, notes: "Control the lowering phase.", muscleTarget: target
            )
        }

        let menu = [
            menuItem("Romanian Deadlift", "Hamstrings", sets: 3),
            menuItem("Seated Leg Curl", "Hamstrings", sets: 3),
            menuItem("Leg Extension", "Quads", sets: 3)
        ]
        // The generated day keeps the first slot and silently drops the rest.
        let day = WorkoutDayResponse(
            dayNumber: 1, dayName: "Lower", muscleGroups: "Hamstrings, Quads",
            isRestDay: false, notes: "Posterior chain emphasis.",
            exercises: [produced("Romanian Deadlift", "Hamstrings", sets: 3)]
        )

        let findings = service.validateExerciseMenuAdherence(
            days: [day],
            expectedExerciseMenus: [menu],
            dayStart: 1
        )
        XCTAssertTrue(
            findings.contains { $0.contains("did not follow the Pre-Selected Exercise Menu") },
            "Omitting menu slots must be caught: \(findings)"
        )
        XCTAssertTrue(
            findings.contains { service.validationDisposition(for: $0, menuLocked: true) == .correctionPass },
            "The omission finding must remain correction-worthy so acceptance is still blocked: \(findings)"
        )
        XCTAssertFalse(
            service.shouldAcceptAIOutput(despite: findings + [baselineGap], menuLocked: true),
            "A gap the AI created by dropping a slot must never ride out on the menu-owned demotion"
        )
    }

    /// The plain-language notice for this finding already existed and was unreachable while the
    /// finding hard-failed. Pins the pairing so a future reword breaks visibly.
    func testTheOwnerFacingNoticeForThisFindingIsReachable() {
        let notices = WorkoutValidatorNotice.notices(from: [baselineGap])
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].severity, .attention)
        XCTAssertTrue(notices[0].headline.contains("has no direct work"), notices[0].headline)
    }
}
