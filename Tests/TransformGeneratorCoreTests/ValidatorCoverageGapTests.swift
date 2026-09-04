import Foundation
import XCTest
@testable import Transform

/// Four confirmed validator coverage gaps, each traced to a real shipped Week 1 that the
/// validator said nothing about:
///
///  1. A single-set exercise below its own role floor (`minimumSetFloor`) was structurally
///     "valid" (>=1 set) and invisible. The owner's Day 5 shipped `Cable Crunch` at ONE set.
///  2. `validateNoteContradictions`'s low-fatigue/recovery keyword list caught the literal
///     phrasing but missed a paraphrase ("without adding fatigue") over two fatigueCost-3
///     compounds — the exact ACCEPTED candidate from a real generation.
///  3. `validateBlueprint` only ever checked frequency UNDER-delivery. The owner's Core/Abs
///     shipped 3 real exposures against a planned 1 with nothing noticing the overshoot.
///  4. `validateDayPlans`'s three day-SHAPE messages (missing day, rest-that-became-training,
///     training-that-became-rest) matched no pattern in `validationDisposition` and had no
///     `WorkoutValidatorNotice` copy — so a planned rest day silently becoming a training
///     session (a real recovery-budget risk) rendered as "A plan check didn't pass" to the owner.
///
/// Every finding here is asserted three ways: it fires on the shape that actually shipped, it
/// stays quiet on a legitimate week, and it carries a deliberate `validationDisposition` (both
/// `menuLocked` states) plus real `WorkoutValidatorNotice` copy rather than the unclassified
/// fallback.
@MainActor
final class ValidatorCoverageGapTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Shared helpers (shapes copied from GeneratorBalanceFixTests / InjuryTimeAndSessionBudgetTests)

    private func exercise(
        _ name: String,
        _ target: String,
        sets: Int,
        reps: String = "10-12",
        restSeconds: Int = 90,
        notes: String = "Keep your core braced and move with control through the full range.",
        targetRIR: Int? = 2
    ) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: name,
            sets: sets,
            reps: reps,
            tempo: "2-0-1-1",
            restSeconds: restSeconds,
            notes: notes,
            muscleTarget: target,
            targetRIR: targetRIR
        )
    }

    private func day(
        _ dayNumber: Int,
        exercises: [WorkoutExerciseResponse],
        isRestDay: Bool = false,
        notes: String = "Push session. Warm-up: 3-5 min light cardio, band pull-aparts, "
            + "then 2-3 progressive ramp sets into the first lift."
    ) -> WorkoutDayResponse {
        WorkoutDayResponse(
            dayNumber: dayNumber,
            dayName: isRestDay ? "Rest" : "Training",
            muscleGroups: isRestDay ? "" : "Chest, Shoulders",
            isRestDay: isRestDay,
            notes: isRestDay ? "Active recovery and mobility work." : notes,
            exercises: exercises
        )
    }

    /// A full 7-day week carrying `exercises` on Day 1 only, every other day a rest day. Good
    /// enough for `validateDaySet`, which is what GAP 1 lives in — other structural findings
    /// (day count, rest-day count) may also appear, but every assertion here checks for a
    /// specific substring rather than exact array equality, so they don't interfere.
    private func weekWithOneTrainingDay(_ exercises: [WorkoutExerciseResponse]) -> [WorkoutDayResponse] {
        (1...7).map { number in
            number == 1
                ? day(1, exercises: exercises)
                : day(number, exercises: [], isRestDay: true)
        }
    }

    private func minimalBlueprint(
        priorityAllocations: [ClaudeService.BlueprintPriorityAllocation] = [],
        dayPlans: [ClaudeService.BlueprintDayPlan] = []
    ) -> ClaudeService.ProgramBlueprint {
        ClaudeService.ProgramBlueprint(
            evidenceVersion: "test",
            splitRecommendation: "Upper/Lower",
            weeklyTrainingDays: 5,
            priorityAllocations: priorityAllocations,
            dayPlans: dayPlans,
            topLeverageChange: "(not provided)",
            posturalFocus: "(none)",
            injuryRiskFocus: "(none)",
            programmingNotes: [],
            calibration: service.neutralCalibrationProfile()
        )
    }

    private func assertNotFallbackNotice(_ issue: String, file: StaticString = #filePath, line: UInt = #line) {
        let notices = WorkoutValidatorNotice.notices(from: [issue])
        guard let notice = notices.first, notices.count == 1 else {
            XCTFail("Expected exactly one notice for '\(issue)', got \(notices.count)", file: file, line: line)
            return
        }
        XCTAssertNotEqual(
            notice.headline, "A plan check didn't pass",
            "'\(issue)' must not fall back to the unclassified notice", file: file, line: line
        )
    }

    // MARK: - GAP 1: single-set / below-role-floor exercise

    func testExerciseBelowItsRoleFloorIsFlagged() {
        let exercises = [
            exercise("Incline Barbell Press", "Upper Chest", sets: 3),
            exercise("Cable Fly", "Chest", sets: 3),
            exercise("Cable Lateral Raise", "Lateral Deltoids", sets: 3),
            // The real shipped defect: Cable Crunch (role .core, floor 2) at one set.
            exercise("Cable Crunch", "Abs", sets: 1),
            exercise("Rope Triceps Pressdown", "Triceps", sets: 3)
        ]
        let issues = service.validateDaySet(weekWithOneTrainingDay(exercises), dayStart: 1, dayEnd: 7)

        XCTAssertTrue(
            issues.contains { $0.contains("below its role-based minimum of") && $0.contains("Cable Crunch") },
            "A single-set exercise below its own role floor must be named and flagged: \(issues)"
        )
    }

    func testExerciseAtItsRoleFloorStaysQuiet() {
        let exercises = [
            exercise("Incline Barbell Press", "Upper Chest", sets: 3),
            exercise("Cable Fly", "Chest", sets: 3),
            exercise("Cable Lateral Raise", "Lateral Deltoids", sets: 3),
            exercise("Cable Crunch", "Abs", sets: 2),
            exercise("Rope Triceps Pressdown", "Triceps", sets: 3)
        ]
        let issues = service.validateDaySet(weekWithOneTrainingDay(exercises), dayStart: 1, dayEnd: 7)

        XCTAssertFalse(
            issues.contains { $0.contains("below its role-based minimum of") },
            "An exercise sitting exactly at its own role floor must not be flagged: \(issues)"
        )
    }

    func testBelowRoleFloorFindingIsAnAcceptableWarningBothLockedAndUnlockedAndGetsPlainLanguageCopy() {
        let exercises = [
            exercise("Incline Barbell Press", "Upper Chest", sets: 3),
            exercise("Cable Crunch", "Abs", sets: 1)
        ]
        let issues = service.validateDaySet(weekWithOneTrainingDay(exercises), dayStart: 1, dayEnd: 7)
        guard let issue = issues.first(where: { $0.contains("below its role-based minimum of") }) else {
            XCTFail("Expected a below-role-floor finding: \(issues)")
            return
        }

        // The deterministic allocator owns set counts under menu lock; the AI cannot fix a
        // stranded single-set exercise, so this is reachable, not repairable — the same
        // reasoning already applied to the maintenance-volume floor finding.
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .acceptableWarning)
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: false), .acceptableWarning)

        assertNotFallbackNotice(issue)
    }

    // MARK: - GAP 2: paraphrased low-fatigue claims over heavy compounds

    /// The exact accepted-candidate shape from the real generation this gap was found in:
    /// Back Squat + Barbell Romanian Deadlift (both fatigueCost 3) under a note that never says
    /// "low fatigue" or "recovery" but claims the same thing in different words.
    func testParaphrasedLowFatigueClaimOverHeavyCompoundsIsFlagged() {
        let heavyDay = day(
            1,
            exercises: [
                exercise("Back Squat", "Quads", sets: 3),
                exercise("Barbell Romanian Deadlift", "Hamstrings", sets: 3)
            ],
            notes: "A balanced lower session to maintain leg mass without adding fatigue "
                + "that would steal from your priority areas."
        )
        let issues = service.validateNoteContradictions(on: heavyDay, blueprint: minimalBlueprint(), dayStart: 1)

        XCTAssertTrue(
            issues.contains { $0.contains("notes describe a low-fatigue") },
            "The accepted candidate's exact paraphrase must trip the contradiction rule: \(issues)"
        )
    }

    /// The false-positive guard: a note that correctly WARNS a session will be fatiguing must
    /// not be mistaken for a claim that it won't be.
    func testWarningThatADayWillBeFatiguingIsNotMistakenForALowFatigueClaim() {
        let heavyDay = day(
            1,
            exercises: [
                exercise("Back Squat", "Quads", sets: 3),
                exercise("Barbell Romanian Deadlift", "Hamstrings", sets: 3)
            ],
            notes: "This session will be fatiguing, so pace yourself and rest fully between the heavy sets."
        )
        let issues = service.validateNoteContradictions(on: heavyDay, blueprint: minimalBlueprint(), dayStart: 1)

        XCTAssertFalse(
            issues.contains { $0.contains("notes describe a low-fatigue") },
            "A note warning about fatigue, not promising a light session, must stay quiet: \(issues)"
        )
    }

    func testLowFatigueParaphraseKeepsItsExistingCorrectionPassDispositionAndCopy() {
        let heavyDay = day(
            1,
            exercises: [
                exercise("Back Squat", "Quads", sets: 3),
                exercise("Barbell Romanian Deadlift", "Hamstrings", sets: 3)
            ],
            notes: "A balanced lower session to maintain leg mass without adding fatigue "
                + "that would steal from your priority areas."
        )
        let issues = service.validateNoteContradictions(on: heavyDay, blueprint: minimalBlueprint(), dayStart: 1)
        guard let issue = issues.first(where: { $0.contains("notes describe a low-fatigue") }) else {
            XCTFail("Expected a low-fatigue contradiction finding: \(issues)")
            return
        }

        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .correctionPass)
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: false), .correctionPass)

        assertNotFallbackNotice(issue)
    }

    // MARK: - GAP 3: priority frequency OVERSHOOT

    private func frequencyAllocation(area: String, targetFrequency: Int) -> ClaudeService.BlueprintPriorityAllocation {
        ClaudeService.BlueprintPriorityAllocation(
            area: area,
            priorityLevel: "Medium",
            rationale: "",
            targetFrequency: targetFrequency,
            targetExerciseSlots: 6,
            directSetTarget: 20,
            weightedStimulusTarget: 25,
            maxPerSessionDirectSets: 20,
            maxFocusSessionDirectSets: 20,
            preferredStyles: ["Upper", "Lower"],
            preferredMovementPatterns: [],
            volumeBias: "Moderate",
            directWorkBias: "Maintenance"
        )
    }

    /// A full week with direct Core/Abs work landing on exactly the given day numbers, every
    /// other day a rest day. Generous per-session/focus/direct-set caps above keep the
    /// unrelated over-volume rules quiet so only the frequency finding is under test.
    private func daysWithAbsWork(on dayNumbers: Set<Int>) -> [WorkoutDayResponse] {
        (1...7).map { number in
            guard dayNumbers.contains(number) else {
                return day(number, exercises: [], isRestDay: true)
            }
            return day(number, exercises: [
                exercise("Cable Crunch", "Abs", sets: 2),
                exercise("Incline Barbell Press", "Upper Chest", sets: 3),
                exercise("Leg Press", "Quads", sets: 3)
            ])
        }
    }

    /// The real shipped shape: Core/Abs planned for 1 day, delivered on 3.
    func testPriorityOvershotByTwoOrMoreDaysIsFlagged() {
        let blueprint = minimalBlueprint(priorityAllocations: [frequencyAllocation(area: "Core/Abs", targetFrequency: 1)])
        let issues = service.validateBlueprint(days: daysWithAbsWork(on: [1, 2, 4]), blueprint: blueprint, dayStart: 1)

        XCTAssertTrue(
            issues.contains { $0.contains("overshot its frequency target") && $0.contains("Core/Abs") },
            "A priority trained on 3 days against a plan of 1 must be flagged as a real overshoot: \(issues)"
        )
    }

    /// One incidental extra day (2 delivered against a plan of 1) is common and usually
    /// harmless — the +2 threshold must not fire on it.
    func testOneIncidentalExtraDayStaysQuiet() {
        let blueprint = minimalBlueprint(priorityAllocations: [frequencyAllocation(area: "Core/Abs", targetFrequency: 1)])
        let issues = service.validateBlueprint(days: daysWithAbsWork(on: [1, 2]), blueprint: blueprint, dayStart: 1)

        XCTAssertFalse(
            issues.contains { $0.contains("overshot its frequency target") },
            "A single incidental extra exposure day must not be treated as a real overshoot: \(issues)"
        )
    }

    func testFrequencyOvershootIsAnAcceptableWarningBothLockedAndUnlockedAndGetsPlainLanguageCopy() {
        let blueprint = minimalBlueprint(priorityAllocations: [frequencyAllocation(area: "Core/Abs", targetFrequency: 1)])
        let issues = service.validateBlueprint(days: daysWithAbsWork(on: [1, 2, 4]), blueprint: blueprint, dayStart: 1)
        guard let issue = issues.first(where: { $0.contains("overshot its frequency target") }) else {
            XCTFail("Expected a frequency-overshoot finding: \(issues)")
            return
        }

        // Which days carry a priority's menu slots is decided when the locked menu is built;
        // neither the AI (menu locked) nor the procedural fallback (reads the same menu) can
        // move a day's worth of exercises elsewhere once this runs.
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .acceptableWarning)
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: false), .acceptableWarning)

        assertNotFallbackNotice(issue)
    }

    // MARK: - GAP 4: blueprint day-SHAPE violations

    private func dayPlan(
        _ index: Int,
        style: String = "Push",
        isRestDay: Bool = false
    ) -> ClaudeService.BlueprintDayPlan {
        ClaudeService.BlueprintDayPlan(
            dayIndex: index,
            style: style,
            focusArea: nil,
            supportAreas: [],
            targetFatigueCap: 20,
            targetSessionMinutes: 70,
            targetPrioritySlots: 1,
            emphasisPatterns: [],
            isRestDay: isRestDay
        )
    }

    func testPlannedRestDayThatShippedAsTrainingIsFlagged() {
        let blueprint = minimalBlueprint(dayPlans: [dayPlan(1, isRestDay: true)])
        let actualDays = [day(1, exercises: [exercise("Incline Barbell Press", "Upper Chest", sets: 3)])]
        let issues = service.validateDayPlans(days: actualDays, blueprint: blueprint, dayStart: 1)

        XCTAssertTrue(
            issues.contains { $0.contains("turned it into a training session.") },
            "A planned rest day that shipped as a training day must be flagged: \(issues)"
        )
    }

    func testPlannedTrainingDayThatShippedAsRestIsFlagged() {
        let blueprint = minimalBlueprint(dayPlans: [dayPlan(1, style: "Push", isRestDay: false)])
        let actualDays = [day(1, exercises: [], isRestDay: true)]
        let issues = service.validateDayPlans(days: actualDays, blueprint: blueprint, dayStart: 1)

        XCTAssertTrue(
            issues.contains { $0.contains("generated output made it a rest day.") },
            "A planned training day that shipped as a rest day must be flagged: \(issues)"
        )
    }

    func testMissingBlueprintDayIsFlagged() {
        let blueprint = minimalBlueprint(dayPlans: [dayPlan(1, style: "Push"), dayPlan(2, style: "Pull")])
        // Day 2 has no counterpart in the response at all.
        let actualDays = [day(1, exercises: [exercise("Incline Barbell Press", "Upper Chest", sets: 3)])]
        let issues = service.validateDayPlans(days: actualDays, blueprint: blueprint, dayStart: 1)

        XCTAssertTrue(
            issues.contains { $0.contains("is missing from the generated output.") },
            "A blueprint day with no matching day in the response must be flagged: \(issues)"
        )
    }

    func testMatchingRestAndTrainingDaysStayQuiet() {
        let blueprint = minimalBlueprint(dayPlans: [dayPlan(1, style: "Push"), dayPlan(2, isRestDay: true)])
        let actualDays = [
            day(1, exercises: [exercise("Incline Barbell Press", "Upper Chest", sets: 3)]),
            day(2, exercises: [], isRestDay: true)
        ]
        let issues = service.validateDayPlans(days: actualDays, blueprint: blueprint, dayStart: 1)

        XCTAssertFalse(issues.contains {
            $0.contains("turned it into a training session.")
                || $0.contains("generated output made it a rest day.")
                || $0.contains("is missing from the generated output.")
        }, "A response that matches its blueprint's day shape exactly must not be flagged: \(issues)")
    }

    func testRestToTrainingFlipIsACorrectionPassBothLockedAndUnlockedAndGetsPlainLanguageCopy() {
        let blueprint = minimalBlueprint(dayPlans: [dayPlan(1, isRestDay: true)])
        let actualDays = [day(1, exercises: [exercise("Incline Barbell Press", "Upper Chest", sets: 3)])]
        let issues = service.validateDayPlans(days: actualDays, blueprint: blueprint, dayStart: 1)
        guard let issue = issues.first(where: { $0.contains("turned it into a training session.") }) else {
            XCTFail("Expected a rest-to-training flip finding: \(issues)")
            return
        }

        // Rest-vs-training is a decision the model makes for itself when it writes `isRestDay`
        // — the prompt tells it to follow the blueprint's split exactly — so this is a
        // prompt-adherence slip the model can correct, unlike locked menu content.
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .correctionPass)
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: false), .correctionPass)

        assertNotFallbackNotice(issue)
    }

    func testTrainingToRestFlipIsACorrectionPassBothLockedAndUnlockedAndGetsPlainLanguageCopy() {
        let blueprint = minimalBlueprint(dayPlans: [dayPlan(1, style: "Push", isRestDay: false)])
        let actualDays = [day(1, exercises: [], isRestDay: true)]
        let issues = service.validateDayPlans(days: actualDays, blueprint: blueprint, dayStart: 1)
        guard let issue = issues.first(where: { $0.contains("generated output made it a rest day.") }) else {
            XCTFail("Expected a training-to-rest flip finding: \(issues)")
            return
        }

        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .correctionPass)
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: false), .correctionPass)

        assertNotFallbackNotice(issue)
    }

    func testMissingDayIsAHardFailureBothLockedAndUnlockedAndGetsPlainLanguageCopy() {
        let blueprint = minimalBlueprint(dayPlans: [dayPlan(1, style: "Push"), dayPlan(2, style: "Pull")])
        let actualDays = [day(1, exercises: [exercise("Incline Barbell Press", "Upper Chest", sets: 3)])]
        let issues = service.validateDayPlans(days: actualDays, blueprint: blueprint, dayStart: 1)
        guard let issue = issues.first(where: { $0.contains("is missing from the generated output.") }) else {
            XCTFail("Expected a missing-day finding: \(issues)")
            return
        }

        // Shape — not a usable 7-day program — is one of the two kinds of finding allowed to
        // discard a locked-menu week.
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: true), .hardFailure)
        XCTAssertEqual(service.validationDisposition(for: issue, menuLocked: false), .hardFailure)

        assertNotFallbackNotice(issue)
    }
}
