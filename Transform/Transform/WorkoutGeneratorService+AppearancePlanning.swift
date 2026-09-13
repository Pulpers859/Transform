import Foundation

extension ClaudeService {
    // Shared by normal allocation and its whole-set observer. This preserves the existing
    // soft-ceiling policy, including its numerical tolerance; it does not round budgets up.
    // JointAppearancePlanningTests.testFractionalTargetIsAnExecutedAllocationCeiling pins it.
    func normalWeeklyPrioritySetCeiling(for allocation: BlueprintPriorityAllocation) -> Double {
        allocation.directSetTarget + 0.01
    }

    struct AppearanceReservation {
        let menus: [[PreSelectedExercise]]
        let outcome: WorkoutAppearancePlanner.Outcome
    }

    // Candidate selection still owns catalog/style/pain filtering. This boundary admits a
    // subset only after reserving all retained appearances together. No names are invented.
    // Integration coverage: JointAppearancePlanningTests and the user-journey evidence matrix.
    func reserveWeeklyAppearanceFloors(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        weekNumber: Int,
        lockedPrefixCounts: [Int] = []
    ) -> AppearanceReservation {
        guard menus.count == blueprint.dayPlans.count else {
            return AppearanceReservation(menus: menus, outcome: .infeasible(["Menu/day-plan count mismatch"]))
        }
        let locations = menus.indices.flatMap { day in menus[day].indices.map { (day, $0) } }
        let exercises = locations.map { menus[$0.0][$0.1] }
        let floors = exercises.map { minimumSetFloor(forExerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget) }
        let responses = exercises.indices.map { index in
            WorkoutExerciseResponse(exerciseName: exercises[index].exerciseName, sets: floors[index],
                reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: exercises[index].muscleTarget)
        }
        let tight = blueprint.calibration.recoveryConstrained || blueprint.calibration.poorNutritionAdherence
        var upper: [WorkoutAppearancePlanner.Constraint] = []
        var lower: [WorkoutAppearancePlanner.Constraint] = []
        var coverage: [WorkoutAppearancePlanner.Coverage] = []
        func keep(_ name: String, _ coefficients: [Double], atLeast requested: Double) {
            lower.append(.init(name: name, coefficients: coefficients, limit: requested))
        }
        for day in menus.indices where !blueprint.dayPlans[day].isRestDay {
            let members = locations.map { $0.0 == day ? 1.0 : 0.0 }
            keep("Day \(day + 1) exercise floor", members, atLeast: 5)
            upper.append(.init(name: "Day \(day + 1) fatigue", coefficients: responses.indices.map {
                locations[$0].0 == day ? Double(estimatedDayFatigue(for: [responses[$0]])) : 0
            }, limit: Double(blueprint.dayPlans[day].targetFatigueCap)))
        }
        for pattern in Set(exercises.map(\.movementPattern)).sorted() {
            keep("Weekly pattern \(pattern)", exercises.map { $0.movementPattern == pattern ? 1 : 0 }, atLeast: 1)
        }
        // Keep the last candidate for each displayed target as well as the broad major
        // group. Broad shoulder/back bookkeeping alone must not erase a regional slot.
        for target in Set(exercises.map(\.muscleTarget)).sorted() {
            keep("Weekly target \(target)", exercises.map { $0.muscleTarget == target ? 1 : 0 }, atLeast: 1)
        }
        for group in majorMuscleGroups {
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            let targets = exercises.map {
                exerciseDirectlyTargets(groupAliases: aliases, exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget)
            }
            let residue = isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint)
            upper.append(.init(name: "\(group.label) maintenance/residue", coefficients: exercises.indices.map { index in
                let priorityPaid = earnsDirectPriorityCredit(exerciseName: exercises[index].exerciseName,
                    muscleTarget: exercises[index].muscleTarget, blueprint: blueprint)
                return targets[index] && (!residue || !priorityPaid) ? Double(floors[index]) : 0
            }, limit: tight ? 8 : 10))
            let coveredDays = menus.indices.map { day in
                exercises.indices.filter { locations[$0].0 == day && targets[$0] }
            }.filter { !$0.isEmpty }
            coverage.append(.init(name: "\(group.label) baseline days", groups: coveredDays,
                minimumGroups: min(2, coveredDays.count)))
        }
        for allocation in blueprint.priorityAllocations {
            let direct = responses.map { stimulusCredit(for: $0, area: allocation.area).directSets }
            let prime = exercises.map { focusStimulusKind(exerciseName: $0.exerciseName,
                muscleTarget: $0.muscleTarget, focusArea: allocation.area) == .prime }
            upper.append(.init(name: "\(allocation.area) weekly direct sets", coefficients: direct,
                limit: allocation.directSetTarget * (tight ? 1.15 : 1.3) + (tight ? 0 : 0.5) - 0.02))
            keep("\(allocation.area) prime slots", prime.map { $0 ? 1 : 0 }, atLeast: Double(allocation.targetExerciseSlots))
            // A capacity bound is necessary, not proof that shared budgets can fund every
            // target simultaneously; final delivered coverage is checked separately.
            keep("\(allocation.area) direct capacity", exercises.indices.map { index in
                let ceiling = max(proceduralSets(for: weekNumber, exerciseName: exercises[index].exerciseName,
                    muscleTarget: exercises[index].muscleTarget), prime[index] ? 4 : 0)
                return direct[index] / Double(floors[index]) * Double(ceiling)
            }, atLeast: allocation.directSetTarget)
            for day in menus.indices {
                let focus = blueprint.dayPlans[day].focusArea.map {
                    normalizedPriorityText($0) == normalizedPriorityText(allocation.area)
                } ?? false
                upper.append(.init(name: "Day \(day + 1) \(allocation.area) direct sets",
                    coefficients: direct.indices.map { locations[$0].0 == day ? direct[$0] : 0 },
                    limit: focus ? allocation.maxFocusSessionDirectSets : allocation.maxPerSessionDirectSets))
                if focus {
                    keep("Day \(day + 1) \(allocation.area) focus exposure", prime.indices.map {
                        locations[$0].0 == day && prime[$0] ? 1 : 0
                    }, atLeast: 1)
                }
            }
            let primeDays = menus.indices.map { day in
                exercises.indices.filter { locations[$0].0 == day && prime[$0] }
            }.filter { !$0.isEmpty }
            coverage.append(.init(name: "\(allocation.area) prime days", groups: primeDays,
                minimumGroups: min(allocation.targetFrequency, primeDays.count)))
        }
        let protected = exercises.indices.map { index in
            let (day, slot) = locations[index]
            return exercises[index].role == .anchor || slot == 0
                || (canonicalTrainingStyle(blueprint.dayPlans[day].style) == "Lower" && exercises[index].role == .secondary)
                || (day < lockedPrefixCounts.count && slot < lockedPrefixCounts[day])
        }
        func focusValue(_ index: Int) -> Int {
            guard let area = blueprint.dayPlans[locations[index].0].focusArea else { return 0 }
            return focusStimulusKind(exerciseName: exercises[index].exerciseName,
                muscleTarget: exercises[index].muscleTarget, focusArea: area) == .prime ? 1 : 0
        }
        let order = exercises.indices.sorted {
            let lhs = focusValue($0), rhs = focusValue($1)
            if lhs != rhs { return lhs < rhs }
            // Prefer removing later optional slots, not the beginning of a session.
            if locations[$0].1 != locations[$1].1 { return locations[$0].1 > locations[$1].1 }
            return $0 < $1
        }
        let outcome = WorkoutAppearancePlanner.solve(.init(protected: protected,
            upperBounds: upper, lowerBounds: lower, removalOrder: order, coverage: coverage))
        guard case .admitted(let indices) = outcome else {
            return AppearanceReservation(menus: menus, outcome: outcome)
        }
        var admitted = menus.map { _ in [PreSelectedExercise]() }
        for index in indices {
            var exercise = exercises[index]
            exercise.prescribedSets = floors[index]
            admitted[locations[index].0].append(exercise)
        }
        return AppearanceReservation(menus: admitted, outcome: outcome)
    }
}
