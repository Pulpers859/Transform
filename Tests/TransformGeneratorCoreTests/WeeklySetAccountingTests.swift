import XCTest
@testable import Transform

@MainActor
final class WeeklySetAccountingTests: XCTestCase {
    private let service = ClaudeService.shared

    private func blueprint(_ areas: [String]) -> ClaudeService.ProgramBlueprint {
        .init(evidenceVersion: "test", splitRecommendation: "Upper / Lower", weeklyTrainingDays: 2,
            priorityAllocations: areas.map {
                .init(area: $0, priorityLevel: "Medium", rationale: "", targetFrequency: 2,
                    targetExerciseSlots: 2, directSetTarget: 7.5, weightedStimulusTarget: 7.5,
                    maxPerSessionDirectSets: 4, maxFocusSessionDirectSets: 4,
                    preferredStyles: ["Upper", "Lower"], preferredMovementPatterns: [],
                    volumeBias: "Moderate", directWorkBias: "High")
            },
            dayPlans: (1...2).map {
                .init(dayIndex: $0, style: "Upper", focusArea: areas.first, supportAreas: [],
                    targetFatigueCap: 48, targetSessionMinutes: 75, targetPrioritySlots: 1,
                    emphasisPatterns: [], isRestDay: false)
            }, topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: "(none)",
            programmingNotes: [], calibration: service.neutralCalibrationProfile())
    }

    private func slot(_ name: String, _ target: String, sets: Int = 1) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
            movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
            role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: sets)
    }

    private func response(_ exercise: ClaudeService.PreSelectedExercise, sets: Int) -> WorkoutExerciseResponse {
        .init(exerciseName: exercise.exerciseName, sets: sets, reps: "", tempo: "",
            restSeconds: 0, notes: "", muscleTarget: exercise.muscleTarget)
    }

    func testSharedAccountingMatchesCanonicalAPIsAcrossPriorityCombinations() {
        let probes = [
            slot("Incline Barbell Press", "Upper Chest"), slot("Cable Fly", "Chest"),
            slot("Cable Lateral Raise", "Lateral Deltoids"), slot("Reverse Pec Deck", "Rear Deltoids"),
            slot("Cable Face Pull", "Rear Deltoids"), slot("Lat Pulldown", "Lats"),
            slot("Dumbbell Hammer Curl", "Brachialis"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("Barbell Romanian Deadlift", "Hamstrings"), slot("Cable Crunch", "Abs")
        ]
        let combinations: [[String]] = [[], ["Upper Chest"], ["Lateral Deltoids"], ["Biceps"],
            ["Back"], ["Core/Abs"], ["Hamstrings", "Glutes"], ["Upper Chest", "Triceps"]]
        for areas in combinations {
            let plan = blueprint(areas)
            let shared = service.weeklyExerciseAccounting(for: [probes, []], blueprint: plan)
            XCTAssertEqual(shared.exercises.map(\.count), [probes.count, 0])
            XCTAssertEqual(shared.groups.map(\.label), service.majorMuscleGroups.map { $0.label })
            for index in probes.indices {
                let exercise = probes[index]
                let record = shared.exercises[0][index]
                XCTAssertEqual(record.setFloor, service.minimumSetFloor(for: response(exercise, sets: 1)))
                XCTAssertEqual(record.setFloor, service.minimumSetFloor(
                    forExerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget),
                    "Reservation previously used the name/target overload; both contracts must agree")
                for allocation in areas.indices {
                    for sets in Set(Array(1...5) + [record.setFloor]).sorted() {
                        let canonical = service.stimulusCredit(for: response(exercise, sets: sets), area: areas[allocation])
                        XCTAssertEqual(record.unitDirect[allocation] * Double(sets), canonical.directSets, accuracy: 0.000001)
                        XCTAssertEqual(record.unitWeighted[allocation] * Double(sets), canonical.weightedStimulus, accuracy: 0.000001)
                    }
                    let quality: Int
                    switch service.focusStimulusKind(exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget, focusArea: areas[allocation]) {
                    case .prime: quality = 30
                    case .secondary: quality = 20
                    case .support: quality = 10
                    case .none: quality = 0
                    }
                    XCTAssertEqual(record.qualityScore[allocation], quality)
                }
                for groupIndex in service.majorMuscleGroups.indices {
                    let group = service.majorMuscleGroups[groupIndex]
                    let aliases = service.normalizedGroupAliases(forSeed: group.seed)
                    XCTAssertEqual(record.directlyTargetsGroup[groupIndex],
                        service.exerciseDirectlyTargets(groupAliases: aliases,
                            exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget))
                    XCTAssertEqual(record.groupTargets[groupIndex],
                        service.exerciseCountsTowardMaintenance(groupSeed: group.seed, groupAliases: aliases,
                            exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget, blueprint: plan))
                }
            }
        }
    }

    func testPriorityPaidCoverageAndUnpaidResidueStaySeparate() throws {
        let plan = blueprint(["Lateral Deltoids"])
        let probes = [slot("Cable Lateral Raise", "Lateral Deltoids"), slot("Reverse Pec Deck", "Rear Deltoids")]
        let shared = service.weeklyExerciseAccounting(for: [probes], blueprint: plan)
        let shoulders = try XCTUnwrap(service.majorMuscleGroups.firstIndex { $0.seed == "shoulders" })
        XCTAssertGreaterThan(shared.exercises[0][0].unitDirect[0], 0)
        XCTAssertTrue(shared.exercises[0][0].directlyTargetsGroup[shoulders])
        XCTAssertFalse(shared.exercises[0][0].groupTargets[shoulders])
        XCTAssertEqual(shared.exercises[0][1].unitDirect[0], 0)
        XCTAssertTrue(shared.exercises[0][1].directlyTargetsGroup[shoulders])
        XCTAssertTrue(shared.exercises[0][1].groupTargets[shoulders])

        let weightedOnly = slot("Dumbbell Arnold Press", "Anterior Deltoids")
        let weightedRecord = service.weeklyExerciseAccounting(for: [[weightedOnly]], blueprint: plan).exercises[0][0]
        XCTAssertEqual(weightedRecord.unitDirect[0], 0, "Premise: Arnold press is not direct lateral-delt work")
        XCTAssertGreaterThan(weightedRecord.unitWeighted[0], 0, "Premise: it does receive weighted credit")
        XCTAssertTrue(shared.groups[shoulders].residueOnly)
        XCTAssertTrue(weightedRecord.directlyTargetsGroup[shoulders])
        XCTAssertTrue(weightedRecord.groupTargets[shoulders], "Weighted credit must not exempt prioritized-group residue")
    }

    func testOneAppearanceCanDebitTwoPriorityBudgets() throws {
        let plan = blueprint(["Chest", "Triceps"])
        let shared = service.weeklyExerciseAccounting(
            for: [[slot("Dip (Assisted or Weighted)", "Chest")]], blueprint: plan)
        let record = shared.exercises[0][0]
        XCTAssertEqual(record.unitDirect, [1, 1])
        for seed in ["chest", "triceps"] {
            let group = try XCTUnwrap(service.majorMuscleGroups.firstIndex { $0.seed == seed })
            XCTAssertTrue(shared.groups[group].residueOnly)
            XCTAssertTrue(record.directlyTargetsGroup[group])
            XCTAssertFalse(record.groupTargets[group])
        }
    }

    func testRepeatedAppearancesIgnoreInputSetsAndStoredRoleForAccounting() {
        let canonical = slot("Cable Crunch", "Abs", sets: 2)
        // Deliberately inconsistent: canonical name/target still owns the dose floor.
        let first = ClaudeService.PreSelectedExercise(exerciseName: canonical.exerciseName,
            muscleTarget: canonical.muscleTarget, movementPattern: canonical.movementPattern,
            role: .anchor, prescribedSets: 2)
        let second = slot("Cable Crunch", "Abs", sets: 4)
        let plan = blueprint(["Core/Abs"])
        let shared = service.weeklyExerciseAccounting(for: [[first], [second]], blueprint: plan)
        XCTAssertEqual(shared.exercises.map(\.count), [1, 1])
        XCTAssertEqual(shared.exercises[0][0].setFloor, 2)
        XCTAssertEqual(shared.exercises[0][0].unitDirect, shared.exercises[1][0].unitDirect)
        let actual = shared.exercises[0][0].unitDirect[0] * Double(first.prescribedSets)
            + shared.exercises[1][0].unitDirect[0] * Double(second.prescribedSets)
        let expected = service.directSetCredit(for: response(first, sets: 2), area: "Core/Abs")
            + service.directSetCredit(for: response(second, sets: 4), area: "Core/Abs")
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual, 6)
    }
}
