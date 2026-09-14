import Foundation

extension ClaudeService {
    struct SetBudgetLimits {
        // maintenance/sessionPriority are raw; use their funding wrappers for +0.01.
        // normalWeeklyPriority already includes +0.01. floorWeeklyPriority includes
        // its historical buffer/margin, but NO added funding tolerance.
        let maintenance: Double
        let normalWeeklyPriority: [Double]
        let floorWeeklyPriority: [Double]
        let sessionPriority: [[Double]]
        let focusMatch: [[Bool]]
        let fatigue: [Int]

        var maintenanceFundingCeiling: Double { maintenance + WorkoutSetBudgetPolicy.fundingTolerance }
        func sessionFundingCeiling(day: Int, allocation: Int) -> Double {
            sessionPriority[day][allocation] + WorkoutSetBudgetPolicy.fundingTolerance
        }
    }

    func setBudgetLimits(for blueprint: ProgramBlueprint) -> SetBudgetLimits {
        let tight = blueprint.calibration.recoveryConstrained || blueprint.calibration.poorNutritionAdherence
        let allocations = blueprint.priorityAllocations
        let focusMatch = blueprint.dayPlans.map { day in
            allocations.map { allocation in
                day.focusArea.map { normalizedPriorityText($0) == normalizedPriorityText(allocation.area) } ?? false
            }
        }
        return SetBudgetLimits(
            maintenance: WorkoutSetBudgetPolicy.maintenanceCeiling(recoveryTight: tight),
            normalWeeklyPriority: allocations.map {
                WorkoutSetBudgetPolicy.normalWeeklyPriorityCeiling(target: $0.directSetTarget)
            },
            floorWeeklyPriority: allocations.map {
                WorkoutSetBudgetPolicy.floorWeeklyPriorityCeiling(target: $0.directSetTarget, recoveryTight: tight)
            },
            sessionPriority: blueprint.dayPlans.indices.map { day in
                allocations.indices.map { index in
                    WorkoutSetBudgetPolicy.sessionPriorityCeiling(ordinary: allocations[index].maxPerSessionDirectSets,
                        focused: allocations[index].maxFocusSessionDirectSets, isFocus: focusMatch[day][index])
                }
            }, focusMatch: focusMatch, fatigue: blueprint.dayPlans.map(\.targetFatigueCap))
    }

    struct MaintenanceAccountingGroup {
        let label: String
        let aliases: Set<String>
        let residueOnly: Bool
    }

    struct ExerciseAccounting {
        let unitDirect: [Double]
        let unitWeighted: [Double]
        let qualityScore: [Int]
        // Physical coverage and maintenance debit are different: priority-paid work
        // still covers its muscle group even when excluded from that group's residue.
        let directlyTargetsGroup: [Bool]
        let groupTargets: [Bool]
        let setFloor: Int
    }

    struct WeeklyExerciseAccounting {
        let groups: [MaintenanceAccountingGroup]
        let exercises: [[ExerciseAccounting]]
    }

    // Shared appearance-cost model for floor reservation and optional-set funding.
    // WeeklySetAccountingTests compares it with the canonical credit/membership APIs.
    // One record per appearance, not per distinct name; existing set counts are ignored.
    func weeklyExerciseAccounting(
        for menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint
    ) -> WeeklyExerciseAccounting {
        let groups = majorMuscleGroups.map { group in
            MaintenanceAccountingGroup(label: group.label,
                aliases: normalizedGroupAliases(forSeed: group.seed),
                residueOnly: isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint))
        }
        let accounting = menus.map { day in
            day.map { exercise in
                let unit = WorkoutExerciseResponse(exerciseName: exercise.exerciseName, sets: 1,
                    reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: exercise.muscleTarget)
                let credits = blueprint.priorityAllocations.map { stimulusCredit(for: unit, area: $0.area) }
                let direct = credits.map(\.directSets)
                let quality = blueprint.priorityAllocations.map { allocation -> Int in
                    switch focusStimulusKind(exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget, focusArea: allocation.area) {
                    case .prime: return 30
                    case .secondary: return 20
                    case .support: return 10
                    case .none: return 0
                    }
                }
                let targets = groups.map { group in
                    exerciseDirectlyTargets(groupAliases: group.aliases,
                        exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
                }
                // ANY direct-paying priority exempts work from a prioritized group's
                // residue. Weighted/support credit must never trigger that exemption.
                // ResidueMuscleDoseTests.testAllocatorAndCanonicalPriorityCreditChecksAgree
                // and WeeklySetAccountingTests pin this distinction.
                let paid = direct.contains { $0 > 0 }
                let debits = groups.indices.map { targets[$0] && (!groups[$0].residueOnly || !paid) }
                return ExerciseAccounting(unitDirect: direct,
                    unitWeighted: credits.map(\.weightedStimulus), qualityScore: quality,
                    directlyTargetsGroup: targets, groupTargets: debits,
                    setFloor: minimumSetFloor(for: unit))
            }
        }
        return WeeklyExerciseAccounting(groups: groups, exercises: accounting)
    }
}
