import XCTest
@testable import Transform

@MainActor
final class JointAppearancePlanningTests: XCTestCase {
    private let service = ClaudeService.shared

    private func slot(_ name: String, _ target: String) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
              movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
              role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: 1)
    }

    func testOverfullEarlyArmsDayCannotSpendLateFocusReservation() {
        let allocation = ClaudeService.BlueprintPriorityAllocation(area: "Triceps", priorityLevel: "High",
            rationale: "", targetFrequency: 2, targetExerciseSlots: 3, directSetTarget: 12,
            weightedStimulusTarget: 12, maxPerSessionDirectSets: 6, maxFocusSessionDirectSets: 8,
            preferredStyles: ["Arms", "Push"], preferredMovementPatterns: [], volumeBias: "Moderate", directWorkBias: "High")
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "test", splitRecommendation: "Arms / Push",
            weeklyTrainingDays: 2, priorityAllocations: [allocation], dayPlans: [
                .init(dayIndex: 1, style: "Arms", focusArea: "Biceps", supportAreas: ["Triceps"],
                    targetFatigueCap: 34, targetSessionMinutes: 75, targetPrioritySlots: 2, emphasisPatterns: [], isRestDay: false),
                .init(dayIndex: 2, style: "Push", focusArea: "Triceps", supportAreas: [],
                    targetFatigueCap: 48, targetSessionMinutes: 75, targetPrioritySlots: 2, emphasisPatterns: [], isRestDay: false)
            ], topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: "(none)", programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        let menus = [
            [slot("EZ-Bar Curl", "Biceps"), slot("Incline Dumbbell Curl", "Biceps"),
             slot("Rope Triceps Pressdown", "Triceps"), slot("Overhead Cable Triceps Extension", "Triceps"),
             slot("EZ-Bar Skull Crusher", "Triceps"), slot("V-Bar Pressdown", "Triceps")],
            [slot("Incline Dumbbell Press", "Upper Chest"), slot("Rope Triceps Pressdown", "Triceps"),
             slot("Overhead Cable Triceps Extension", "Triceps"), slot("Cable Lateral Raise", "Lateral Deltoids"),
             slot("Cable Pallof Press", "Obliques")]
        ]
        let reservation = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1)
        guard case .admitted = reservation.outcome else {
            return XCTFail("Expected a jointly funded menu, got \(reservation.outcome)")
        }
        XCTAssertEqual(reservation.menus.map(\.count), [5, 5])
        XCTAssertEqual(reservation.menus[1].map(\.exerciseName), menus[1].map(\.exerciseName))
        let pinned = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint,
            weekNumber: 1, lockedPrefixCounts: [6, 5])
        if case .admitted = pinned.outcome {
            XCTFail("An over-budget pool with every slot retained cannot be declared funded")
        }
        XCTAssertEqual(pinned.menus.map { $0.map(\.exerciseName) }, menus.map { $0.map(\.exerciseName) })
        var reports: [String] = []
        let legacy = service.allocateWeeklySetPrescription(menus, blueprint: blueprint, weekNumber: 1,
            lockedPrefixCounts: [6, 5], appearancePlanningReport: { reports.append($0) })
        XCTAssertEqual(reports.count, 1)
        XCTAssertTrue(reports[0].contains("APPEARANCE PLANNING CONFLICT"))
        XCTAssertEqual(legacy.map { $0.map(\.exerciseName) }, menus.map { $0.map(\.exerciseName) })
        let funded = service.allocateWeeklySetPrescription(menus, blueprint: blueprint, weekNumber: 1)
        for day in funded {
            for exercise in day {
                XCTAssertGreaterThanOrEqual(exercise.prescribedSets,
                    service.minimumSetFloor(forExerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget))
            }
        }
        let tricepsByDay = funded.map { day in day.reduce(0.0) { total, exercise in
            total + service.stimulusCredit(for: WorkoutExerciseResponse(exerciseName: exercise.exerciseName,
                sets: exercise.prescribedSets, reps: "", tempo: "", restSeconds: 0, notes: "",
                muscleTarget: exercise.muscleTarget), area: "Triceps").directSets
        } }
        XCTAssertGreaterThanOrEqual(tricepsByDay[1], service.minimumMeaningfulPriorityExposureSets(for: "Triceps"))
        XCTAssertGreaterThanOrEqual(tricepsByDay.reduce(0, +) + 0.01, allocation.directSetTarget)
        XCTAssertLessThanOrEqual(tricepsByDay[0], allocation.maxPerSessionDirectSets + 0.01)
        XCTAssertLessThanOrEqual(tricepsByDay[1], allocation.maxFocusSessionDirectSets + 0.01)
    }
}
