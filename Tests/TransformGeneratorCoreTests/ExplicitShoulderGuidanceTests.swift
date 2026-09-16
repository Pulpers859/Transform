import Foundation
import XCTest
@testable import Transform

@MainActor
final class ExplicitShoulderGuidanceTests: XCTestCase {
    private let service = ClaudeService.shared
    private let report = "Left anterior shoulder pain during neutral-grip overhead pressing."

    private func press(_ notes: String) -> WorkoutExerciseResponse {
        .init(exerciseName: "Seated Dumbbell Shoulder Press", sets: 3, reps: "10-12",
              tempo: "2-0-1-0", restSeconds: 90, notes: notes, muscleTarget: "Anterior Deltoids")
    }

    func testConservativeAffirmativeInstructionContract() {
        for note in [service.explicitShoulderGuidance, "Use a neutral grip and stop short of any pinch.",
                     "Use a pain-free range.", "Do not push through pain.",
                     "Don't push through pain. Keep the movement pain free.",
                     "Don’t push through pain. Stop short of any pinch.",
                     "Follow your clinician's advice. Use a pain-free range."] {
            XCTAssertTrue(service.hasExplicitShoulderGuidance(note), note)
        }
        for note in ["neutral grip", "angled grip", "shoulder friendly", "pain free",
                     "This is not pain free.", "Do not keep the movement pain free.",
                     "Never stop if pain occurs.", "No need to stop if pain occurs.",
                     "Keep the movement pain free, but continue even if it hurts.",
                     "Keep the movement pain free. Ignore the pain.",
                     "Keep the movement pain free. Push through pain.",
                     "The old coach said to stop if pain occurs.",
                     "Avoid saying \"stop if pain occurs\".",
                     "Ignore 'keep the movement pain free'.", "Stop if pain goes away.",
                     "Stop if pain is absent.", "Keep the movement pain free is unnecessary.",
                     "Stop short of any pinch unless you want results.", "Stop if pain does not occur.",
                     "Use a pain free range only during warmup; push through shoulder pain during working sets.",
                     "Keep the movement pain free is not required.",
                     "Keep the movement pain free. Push through shoulder pain during working sets."] {
            XCTAssertFalse(service.hasExplicitShoulderGuidance(note), note)
        }
    }

    func testApplicabilityPreservesReportFamilyAndTargetOverride() {
        XCTAssertTrue(service.requiresExplicitShoulderGuidance(exerciseName: "Push Press",
            muscleTarget: "Triceps", injuryRiskFocus: report))
        for (name, target, risk) in [
            ("Seated Dumbbell Shoulder Press", "Anterior Deltoids", ""),
            ("Seated Dumbbell Shoulder Press", "Anterior Deltoids", "Right shoulder pain during rows."),
            ("Chest-Supported Row", "Upper Back", report),
            ("Landmine Shoulder Press", "Anterior Deltoids", report)
        ] {
            XCTAssertFalse(service.requiresExplicitShoulderGuidance(exerciseName: name,
                muscleTarget: target, injuryRiskFocus: risk))
        }
    }

    func testProceduralCuesAndEmptyAINotesShareContractWithoutChangingPrescription() {
        let original = press("")
        let output = service.withDayScopedCues([original], avoidEndRangeShoulder: true, injuryRiskFocus: report)
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output[0].exerciseName, original.exerciseName)
        XCTAssertEqual(output[0].muscleTarget, original.muscleTarget)
        XCTAssertEqual(output[0].sets, original.sets)
        XCTAssertEqual(output[0].reps, original.reps)
        XCTAssertEqual(output[0].tempo, original.tempo)
        XCTAssertEqual(output[0].restSeconds, original.restSeconds)
        XCTAssertEqual(output[0].targetRIR, original.targetRIR)
        XCTAssertTrue(service.hasExplicitShoulderGuidance(output[0].notes))
        let repaired = service.polishedExerciseNotes(rawNotes: "", exerciseName: original.exerciseName,
            muscleTarget: original.muscleTarget, weekNumber: 1, exerciseIndex: 0, injuryRiskFocus: report)
        XCTAssertTrue(service.hasExplicitShoulderGuidance(repaired))
        let unrelated = service.polishedExerciseNotes(rawNotes: "", exerciseName: "Chest-Supported Row",
            muscleTarget: "Upper Back", weekNumber: 1, exerciseIndex: 0, injuryRiskFocus: report)
        XCTAssertFalse(unrelated.contains(service.explicitShoulderGuidance))
    }

    func testUsableAINoteIsNotSilentlyRewritten() {
        let note = "Keep your torso upright throughout the press. Use a neutral grip and move smoothly."
        XCTAssertEqual(service.polishedExerciseNotes(rawNotes: note,
            exerciseName: "Seated Dumbbell Shoulder Press", muscleTarget: "Anterior Deltoids",
            weekNumber: 1, exerciseIndex: 0, injuryRiskFocus: report), note)
        XCTAssertFalse(service.hasExplicitShoulderGuidance(note))
    }

    func testLockedMenuProducerPreservesMenuAndGuidanceDoesNotDefeatCueUniqueness() {
        let exercise = press("")
        let menu: [ClaudeService.PreSelectedExercise] = [.init(exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget,
            movementPattern: service.exerciseMetadata(forExerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget).movementPattern,
            role: service.proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget),
            prescribedSets: 3)]
        let delivered = service.programMenuExercises(menu: menu, weekNumber: 1, focus: "",
            avoidEndRangeShoulder: true, injuryRiskFocus: report)
        XCTAssertEqual(delivered.map(\.exerciseName), menu.map(\.exerciseName))
        XCTAssertEqual(delivered.map(\.sets), menu.map(\.prescribedSets))
        XCTAssertEqual(delivered.map(\.muscleTarget), menu.map(\.muscleTarget))
        XCTAssertTrue(service.hasExplicitShoulderGuidance(delivered[0].notes))
        let first = service.polishedExerciseNotes(rawNotes: "", exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget, weekNumber: 1, exerciseIndex: 0, injuryRiskFocus: report)
        let second = service.polishedExerciseNotes(rawNotes: "", exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget, weekNumber: 1, exerciseIndex: 1,
            cuesAlreadyOnDay: [first], injuryRiskFocus: report)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(service.hasExplicitShoulderGuidance(second))
    }

    func testSanitizationThreadsReportIntoAbsentNotes() async throws {
        let day = WorkoutDayResponse(dayNumber: 1, dayName: "Push", muscleGroups: "Shoulders",
            isRestDay: false, notes: "Warm-up: external rotation.", exercises: [press("")])
        let week = WorkoutWeekResponse(weekSummary: "Week one.", days: [day])
        let cleaned = try await service.sanitizeWeekResponse(week, injuryRiskFocus: report)
        XCTAssertTrue(service.hasExplicitShoulderGuidance(cleaned.days[0].exercises[0].notes))
        XCTAssertEqual(cleaned.days[0].exercises[0].coachingSource, .substituted)
        XCTAssertTrue(service.validateInjuryRiskAlignment(on: cleaned.days[0], injuryRiskFocus: report).isEmpty)
        let program = WorkoutProgramResponse(programName: "Test", programSummary: "Test summary.",
            splitType: "Push", daysPerWeek: 1, days: [day])
        let cleanedProgram = try await service.sanitizeProgramResponse(program, injuryRiskFocus: report)
        XCTAssertTrue(service.hasExplicitShoulderGuidance(cleanedProgram.days[0].exercises[0].notes))
        XCTAssertEqual(cleanedProgram.days[0].exercises[0].coachingSource, .substituted)

        let procedural = service.withDayScopedCues([press("")], avoidEndRangeShoulder: true, injuryRiskFocus: report)
        let proceduralDay = WorkoutDayResponse(dayNumber: 1, dayName: "Push", muscleGroups: "Shoulders",
            isRestDay: false, notes: day.notes, exercises: procedural)
        let recleanedWeek = try await service.sanitizeWeekResponse(
            WorkoutWeekResponse(weekSummary: "Test", days: [proceduralDay]), injuryRiskFocus: report)
        let recleanedProgram = try await service.sanitizeProgramResponse(
            WorkoutProgramResponse(programName: "Test", programSummary: "Test", splitType: "Push",
                daysPerWeek: 1, days: [proceduralDay]), injuryRiskFocus: report)
        XCTAssertEqual(recleanedWeek.days[0].exercises[0].coachingSource, .procedural)
        XCTAssertEqual(recleanedProgram.days[0].exercises[0].coachingSource, .procedural)
    }

    func testContradictoryExerciseNoteRemainsFindingAndCorrectionHasAcceptedInstruction() async throws {
        let day = WorkoutDayResponse(dayNumber: 1, dayName: "Push", muscleGroups: "Shoulders",
            isRestDay: false, notes: "Warm-up: external rotation.",
            exercises: [press("Keep the movement pain free. Push through shoulder pain during working sets.")])
        let findings = service.validateInjuryRiskAlignment(on: day, injuryRiskFocus: report)
        XCTAssertEqual(findings.count, 1)
        let finding = try XCTUnwrap(findings.first)
        XCTAssertTrue(finding.contains("is not clearly adapted to the shoulder risk"))
        let cleaned = try await service.sanitizeWeekResponse(
            WorkoutWeekResponse(weekSummary: "Test", days: [day]), injuryRiskFocus: report)
        XCTAssertEqual(cleaned.days[0].exercises[0].notes, day.exercises[0].notes)
        XCTAssertEqual(cleaned.days[0].exercises[0].coachingSource, .aiCoach)
        XCTAssertEqual(service.validateInjuryRiskAlignment(on: cleaned.days[0], injuryRiskFocus: report), findings)
        XCTAssertEqual(service.validationDisposition(for: finding, menuLocked: true), .correctionPass)
        let correction = service.correctionTactics(for: findings)
        XCTAssertTrue(correction.lowercased().contains(service.explicitShoulderGuidance.lowercased()))
        XCTAssertTrue(service.hasExplicitShoulderGuidance(service.explicitShoulderGuidance))
        XCTAssertTrue(correction.contains("Preserve the locked names, order and sets"))
    }
}
