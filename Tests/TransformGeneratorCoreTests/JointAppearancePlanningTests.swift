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

    func testFractionalTargetIsAnExecutedAllocationCeiling() {
        let allocation = ClaudeService.BlueprintPriorityAllocation(area: "Core/Abs", priorityLevel: "Medium",
            rationale: "", targetFrequency: 2, targetExerciseSlots: 2, directSetTarget: 7.5,
            weightedStimulusTarget: 7.5, maxPerSessionDirectSets: 4, maxFocusSessionDirectSets: 4,
            preferredStyles: ["Upper", "Lower"], preferredMovementPatterns: [], volumeBias: "Moderate", directWorkBias: "High")
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "test", splitRecommendation: "Upper / Lower",
            weeklyTrainingDays: 2, priorityAllocations: [allocation], dayPlans: (1...2).map { day in
                .init(dayIndex: day, style: day == 1 ? "Upper" : "Lower", focusArea: "Core/Abs", supportAreas: [],
                    targetFatigueCap: 48, targetSessionMinutes: 75, targetPrioritySlots: 1, emphasisPatterns: [], isRestDay: false)
            }, topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: "(none)", programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        let menus = [
            [slot("Cable Crunch", "Abs"), slot("Standing Calf Raise", "Calves"),
             slot("Machine Chest Press", "Chest"), slot("Rope Triceps Pressdown", "Triceps"), slot("EZ-Bar Curl", "Biceps")],
            [slot("Cable Crunch", "Abs"), slot("Seated Calf Raise", "Calves"),
             slot("Seated Cable Row", "Mid Back"), slot("Cable Lateral Raise", "Lateral Deltoids"), slot("Seated Leg Curl", "Hamstrings")]
        ]
        var reports: [String] = []
        let funded = service.allocateWeeklySetPrescription(menus, blueprint: blueprint, weekNumber: 1,
            appearancePlanningReport: { reports.append($0) })
        XCTAssertTrue(reports.contains { $0.hasPrefix("reserved role floors") })
        let coreSets = funded.joined().filter { $0.exerciseName == "Cable Crunch" }.map(\.prescribedSets)
        XCTAssertEqual(coreSets.reduce(0, +), 7, "The real allocator cannot buy an eighth set under its 7.5-set ceiling")
        XCTAssertTrue(coreSets.allSatisfy { $0 >= 2 })
        XCTAssertEqual(service.normalWeeklyPrioritySetCeiling(for: allocation), 7.51, accuracy: 0.0001)
        XCTAssertGreaterThan(8, service.normalWeeklyPrioritySetCeiling(for: allocation))
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
        var receipts: [SetFundingObservation] = []
        var receiptCalls = 0
        let observed = service.allocateWeeklySetPrescription(menus, blueprint: blueprint, weekNumber: 1,
            setFundingReport: { receipts = $0; receiptCalls += 1 })
        XCTAssertEqual(receiptCalls, 1)
        XCTAssertEqual(observed.map { $0.map(\.exerciseName) }, funded.map { $0.map(\.exerciseName) })
        XCTAssertEqual(observed.map { $0.map(\.muscleTarget) }, funded.map { $0.map(\.muscleTarget) })
        XCTAssertEqual(observed.map { $0.map(\.prescribedSets) }, funded.map { $0.map(\.prescribedSets) })
        XCTAssertEqual(receipts.map { "\($0.dayIndex):\($0.exerciseIndex)" },
            observed.indices.flatMap { day in observed[day].indices.map { "\(day):\($0)" } })
        XCTAssertLessThan(receipts.count, menus.joined().count, "Receipts index admitted appearances, not removed candidates")
        XCTAssertEqual(receipts.map(\.exerciseName), observed.flatMap { $0.map(\.exerciseName) })
        XCTAssertEqual(receipts.map(\.prescribedSets), observed.flatMap { $0.map(\.prescribedSets) })
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
