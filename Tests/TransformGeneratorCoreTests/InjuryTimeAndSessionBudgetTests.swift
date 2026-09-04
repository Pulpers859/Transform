import Foundation
import XCTest
@testable import Transform

/// Three planner defects found auditing a real Week 1, all of the same shape: the app collected a
/// signal, and every consumer that could have acted on it either failed to recognise it or was
/// never given it.
///
///  1. `hasShoulderRisk` matched five named conditions, so the owner's actual analysis text —
///     "Left anterior shoulder pain during neutral-grip overhead pressing is the key flag" —
///     turned shoulder caution OFF for exercise scoring, the fallback's cues, AND the validator.
///  2. Repeated "ran out of time" skips were printed into the prompt and consumed by nothing. The
///     menu is locked before the model runs, so the prompt's "prioritize it earlier" instruction
///     asked the AI to change something it is forbidden to change.
///  3. `estimatedSessionMinutes` counted no time between exercises, and the same function both
///     builds the day and grades it — so it packed a session and then certified it as short.
@MainActor
final class InjuryTimeAndSessionBudgetTests: XCTestCase {

    private let service = ClaudeService.shared

    private func exercise(
        _ name: String,
        _ target: String,
        sets: Int,
        restSeconds: Int = 90,
        notes: String = "Cue."
    ) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: name,
            sets: sets,
            reps: "10-12",
            tempo: "2-0-1-1",
            restSeconds: restSeconds,
            notes: notes,
            muscleTarget: target
        )
    }

    private func day(
        _ exercises: [WorkoutExerciseResponse],
        notes: String = "Work hard.",
        dayNumber: Int = 1
    ) -> WorkoutDayResponse {
        WorkoutDayResponse(
            dayNumber: dayNumber,
            dayName: "Training",
            muscleGroups: "",
            isRestDay: false,
            notes: notes,
            exercises: exercises
        )
    }

    // MARK: - 1. Shoulder risk is recognised from how analyses actually write

    /// The exact sentence from the owner's Week 1. It names no diagnosis, which is why the old
    /// keyword list missed it entirely.
    private let ownersInjuryText = """
    Left anterior shoulder pain during neutral-grip overhead pressing is the key flag: this \
    pattern warrants modifying pressing angle, reducing overhead range temporarily, and \
    monitoring rather than pushing through.
    """

    func testDescriptiveShoulderPainIsRecognisedAsShoulderRisk() {
        XCTAssertTrue(
            service.hasShoulderRisk(injuryRiskFocus: ownersInjuryText),
            "A real analysis describes symptoms, not diagnoses — this is the phrasing that shipped"
        )
    }

    /// The named conditions must keep working; widening the gate must not trade one blind spot
    /// for another.
    func testNamedShoulderConditionsStillRegister() {
        for text in [
            "Shoulder impingement noted on the left side.",
            "Internally rotated shoulders with upper crossed posture.",
            "Rotator cuff irritation limits overhead work.",
            "Prior labral repair — avoid end-range overhead positions.",
            "Shoulder health is a priority this block."
        ] {
            XCTAssertTrue(service.hasShoulderRisk(injuryRiskFocus: text), text)
        }
    }

    /// The descriptive arm needs BOTH halves. A joint with no complaint, and a complaint in a
    /// different joint, must both stay quiet — otherwise every analysis would trip shoulder
    /// caution and the signal would mean nothing.
    func testUnrelatedOrPainFreeTextDoesNotTripShoulderCaution() {
        for text in [
            "",
            "No injuries reported; training history is clean.",
            "Left knee pain during deep squatting; reduce depth temporarily.",
            "Lower back tightness after long shifts.",
            "Good shoulder mobility and overhead position."
        ] {
            XCTAssertFalse(service.hasShoulderRisk(injuryRiskFocus: text), text)
        }
    }

    /// The rule this gate guards. With the owner's phrasing it now actually evaluates the day
    /// instead of returning early.
    func testUnadaptedOverheadPressingIsFlaggedForDescriptiveShoulderPain() {
        let issues = service.validateInjuryRiskAlignment(
            on: day([
                exercise("Incline Barbell Press", "Upper Chest", sets: 3),
                exercise("Seated Dumbbell Shoulder Press", "Anterior Deltoids", sets: 3)
            ]),
            injuryRiskFocus: ownersInjuryText
        )

        XCTAssertEqual(issues.count, 1, "\(issues)")
        XCTAssertTrue(issues[0].contains("is not clearly adapted to the shoulder risk"), issues[0])
        XCTAssertTrue(issues[0].contains("Seated Dumbbell Shoulder Press"), issues[0])
    }

    /// A press the coaching has actually adapted must still pass, or the rule becomes noise the
    /// owner learns to ignore.
    func testAdaptedOverheadPressingIsNotFlagged() {
        let issues = service.validateInjuryRiskAlignment(
            on: day([
                exercise(
                    "Seated Dumbbell Shoulder Press",
                    "Anterior Deltoids",
                    sets: 3,
                    notes: "Use a neutral grip and stop short of any pinch."
                )
            ]),
            injuryRiskFocus: ownersInjuryText
        )

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    func testANonShoulderInjuryStillSkipsTheShoulderRule() {
        let issues = service.validateInjuryRiskAlignment(
            on: day([exercise("Seated Dumbbell Shoulder Press", "Anterior Deltoids", sets: 3)]),
            injuryRiskFocus: "Left knee pain during deep squatting."
        )

        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    /// The message's anchor substring moved when the wording widened, and three places key off it.
    /// If they drift apart the finding silently changes tier and loses its plain-language copy.
    func testTheShoulderFindingKeepsItsTierAndItsPlainLanguageCopy() {
        let issues = service.validateInjuryRiskAlignment(
            on: day([exercise("Seated Dumbbell Shoulder Press", "Anterior Deltoids", sets: 3)]),
            injuryRiskFocus: ownersInjuryText
        )
        guard let finding = issues.first else {
            XCTFail("Expected a shoulder finding to classify")
            return
        }

        XCTAssertEqual(
            service.validationDisposition(for: finding, menuLocked: true),
            .acceptableWarning,
            "Under menu-lock the AI cannot swap the press, so this must not discard a paid week"
        )

        let notices = WorkoutValidatorNotice.notices(from: [finding])
        XCTAssertEqual(notices.count, 1)
        XCTAssertNotEqual(
            notices[0].headline,
            "A plan check didn't pass",
            "The shoulder finding fell through to the unrecognized notice"
        )
        XCTAssertEqual(notices[0].severity, .attention, "A flagged joint is not a tuning note")
    }

    // MARK: - 2. A repeatedly unfinished movement is actually acted on

    /// `applyHistoryFilters` is the one place a deprioritized movement changes anything: it sinks
    /// to the back of the catalogue so an equivalent movement is preferred. Time skips now reach
    /// it; before this they reached nothing at all.
    func testARepeatedlyTimedOutAccessorySinksBehindItsAlternatives() {
        let catalog = [
            (name: "Cable Crunch", target: "Abs"),
            (name: "Hanging Knee Raise", target: "Lower Abs"),
            (name: "Cable Pallof Press", target: "Obliques")
        ]
        let timedOut: Set<String> = [ExerciseWeightEntry.canonicalLookupKey("Cable Crunch")]

        let ordered = service.applyHistoryFilters(
            catalog,
            avoidedExercises: [],
            deprioritizedExercises: timedOut,
            catalogOffset: 0,
            weekNumber: 1,
            priorMesocycleExercises: []
        )

        XCTAssertEqual(ordered.count, catalog.count, "Deprioritizing must not drop the movement")
        XCTAssertEqual(
            ordered.last?.name,
            "Cable Crunch",
            "A movement the lifter keeps running out of time for must be picked last, not first"
        )
    }

    /// Deprioritizing is not banning. Running out of time says nothing about safety, so the
    /// movement must still be reachable when nothing else covers the muscle.
    func testATimedOutMovementIsStillAvailableWhenItIsTheOnlyOption() {
        let ordered = service.applyHistoryFilters(
            [(name: "Cable Crunch", target: "Abs")],
            avoidedExercises: [],
            deprioritizedExercises: [ExerciseWeightEntry.canonicalLookupKey("Cable Crunch")],
            catalogOffset: 0,
            weekNumber: 1,
            priorMesocycleExercises: []
        )

        // Closure, not a key path: `applyHistoryFilters` returns tuples and Swift has no key
        // paths into tuple elements.
        XCTAssertEqual(ordered.map { $0.name }, ["Cable Crunch"])
    }

    func testHistoryContextDefaultsToNoTimeSkips() {
        let context = ClaudeService.ExerciseHistoryContext(
            painExercises: [],
            equipmentSkipExercises: [],
            priorMesocycleExercises: [],
            mesocycleIndex: 0
        )

        XCTAssertTrue(
            context.timeSkipExercises.isEmpty,
            "The new field must default empty so an un-updated construction site cannot invent skips"
        )
    }

    // MARK: - 3. The clock counts the walk between machines

    func testSessionEstimateChargesForEveryChangeover() {
        let exercises = [
            exercise("Incline Barbell Press", "Upper Chest", sets: 3, restSeconds: 150),
            exercise("Cable Lateral Raise", "Lateral Deltoids", sets: 4, restSeconds: 75),
            exercise("Neutral-Grip Lat Pulldown", "Lats", sets: 2),
            exercise("Chest-Supported Row", "Upper Back", sets: 2),
            exercise("Cable Crunch", "Abs", sets: 2, restSeconds: 60)
        ]
        let subject = day(exercises)

        let workMinutes = exercises.reduce(0.0) { $0 + service.estimatedExerciseMinutes(for: $1) }
        let warmupMinutes = 8.0
        let expectedTransitions = Double(exercises.count - 1) * 1.5

        XCTAssertEqual(
            service.estimatedSessionMinutes(for: subject),
            Int(ceil(warmupMinutes + workMinutes + expectedTransitions)),
            "Five movements means four changeovers, and none of them were being counted"
        )
    }

    /// The estimate must grow with the number of movements even when total work is unchanged —
    /// that is the whole defect: six short movements are not the same session as three long ones.
    func testMoreMovementsCostMoreTimeThanTheSameWorkStackedOnFewer() {
        let spread = day([
            exercise("Cable Lateral Raise", "Lateral Deltoids", sets: 1),
            exercise("Machine Lateral Raise", "Lateral Deltoids", sets: 1),
            exercise("Dumbbell Lateral Raise", "Lateral Deltoids", sets: 1),
            exercise("Reverse Pec Deck", "Rear Deltoids", sets: 1)
        ])
        let concentrated = day([exercise("Cable Lateral Raise", "Lateral Deltoids", sets: 4)])

        XCTAssertGreaterThan(
            service.estimatedSessionMinutes(for: spread),
            service.estimatedSessionMinutes(for: concentrated)
        )
    }

    func testARestDayCostsNoTime() {
        let rest = WorkoutDayResponse(
            dayNumber: 3,
            dayName: "Rest",
            muscleGroups: "",
            isRestDay: true,
            notes: "",
            exercises: []
        )

        XCTAssertEqual(service.estimatedSessionMinutes(for: rest), 0)
    }

    /// A single-movement day has no changeovers, so the new term must contribute nothing rather
    /// than quietly adding a fixed penalty to every session.
    func testASingleMovementDayIsChargedNoTransitionTime() {
        let single = day([exercise("Back Squat", "Quads", sets: 3, restSeconds: 180)])
        let expected = 8.0 + service.estimatedExerciseMinutes(for: single.exercises[0])

        XCTAssertEqual(service.estimatedSessionMinutes(for: single), Int(ceil(expected)))
    }
}
