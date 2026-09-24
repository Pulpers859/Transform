import Foundation

extension ClaudeService {
    struct JointDoseOption {
        let day: Int
        let slot: Int
        let sets: Int
    }

    struct JointDoseProjection {
        let problem: WorkoutAppearancePlanner.ChoiceProblem
        let options: [JointDoseOption]
        let slotCapacityShortfalls: [String]
        // Existing allocator pursues these only while hard budgets allow. A
        // weighted bonus must not make adequate direct work mathematically illegal.
        // Keep raw demand visible; these are NOT silently recut admission bounds.
        let weightedGoals: [WorkoutAppearancePlanner.Constraint]
    }

    /// Diagnostic quantitative projection of a supplied candidate pool, NOT a
    /// workout-adoption gate. Caller supplies eligible identities and actual
    /// history commitments. Input placeholder sets do not become requirements.
    /// Does not encode style, symptoms, spacing, variation, ordering or full
    /// regional quality. Those must be verified before any production use.
    /// An explicit funded baseline adds conservative daily priority and weekly
    /// regional/maintenance non-loss requirements. Never infer those requirements
    /// from provisional candidate placeholders. This still is NOT adoption.
    func jointDoseProjection(for menus: [[PreSelectedExercise]], blueprint: ProgramBlueprint,
        weekNumber: Int, requiredKeysByDay: [Set<String>],
        preservingDoseOf baseline: [[PreSelectedExercise]]? = nil) -> JointDoseProjection? {
        guard (1...3).contains(weekNumber), menus.count == 7, blueprint.dayPlans.count == 7,
              requiredKeysByDay.count == 7,
              blueprint.dayPlans.filter({ !$0.isRestDay }).count == blueprint.weeklyTrainingDays,
              menus.indices.allSatisfy({ day in
                  let keys = menus[day].map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) }
                  return blueprint.dayPlans[day].dayIndex == day + 1
                      && (!blueprint.dayPlans[day].isRestDay || menus[day].isEmpty)
                      && Set(keys).count == keys.count
                      && requiredKeysByDay[day].isSubset(of: Set(keys))
              }) else { return nil }
        for item in menus.joined() {
            guard let known = exerciseMetadataCatalog[normalizeExerciseName(item.exerciseName)],
                  known.canonicalName == item.exerciseName,
                  item.movementPattern == known.movementPattern,
                  item.role == proceduralExerciseRole(for: item.exerciseName, muscleTarget: item.muscleTarget) else {
                return nil
            }
        }
        if let baseline {
            guard baseline.count == 7, baseline.indices.allSatisfy({ day in
                blueprint.dayPlans[day].isRestDay ? baseline[day].isEmpty : !baseline[day].isEmpty
            }) else { return nil }
            for item in baseline.joined() {
                guard let known = exerciseMetadataCatalog[normalizeExerciseName(item.exerciseName)],
                      known.canonicalName == item.exerciseName, known.movementPattern == item.movementPattern,
                      item.role == proceduralExerciseRole(for: item.exerciseName, muscleTarget: item.muscleTarget),
                      item.prescribedSets > 0,
                      item.prescribedSets <= max(proceduralSets(for: weekNumber,
                          exerciseName: item.exerciseName, muscleTarget: item.muscleTarget), 4) else { return nil }
            }
        }
        let accounting = weeklyExerciseAccounting(for: menus, blueprint: blueprint)
        let limits = setBudgetLimits(for: blueprint)
        var options: [JointDoseOption] = [], domains: [[Int]] = []
        for day in menus.indices {
            for slot in menus[day].indices {
                let item = menus[day][slot], cost = accounting.exercises[day][slot]
                let prime = blueprint.priorityAllocations.indices.contains {
                    cost.unitDirect[$0] > 0 && cost.qualityScore[$0] == 30
                }
                let ceiling = max(proceduralSets(for: weekNumber, exerciseName: item.exerciseName,
                    muscleTarget: item.muscleTarget), prime ? 4 : 0)
                guard cost.setFloor > 0, cost.setFloor <= ceiling else { return nil }
                let start = options.count
                // Within one identity, prefer the legal phase/priority ceiling, then lower
                // meaningful doses, then omission. This is deterministic search
                // ordering only, not a claim of optimal training quality.
                for sets in stride(from: ceiling, through: cost.setFloor, by: -1) {
                    options.append(.init(day: day, slot: slot, sets: sets))
                }
                if !requiredKeysByDay[day].contains(ExerciseWeightEntry.canonicalLookupKey(item.exerciseName)) {
                    options.append(.init(day: day, slot: slot, sets: 0))
                }
                domains.append(Array(start..<options.count))
            }
        }
        var upper: [WorkoutAppearancePlanner.Constraint] = []
        var lower: [WorkoutAppearancePlanner.Constraint] = []
        var coverage: [WorkoutAppearancePlanner.Coverage] = []
        var thresholdCoverage: [WorkoutAppearancePlanner.ThresholdCoverage] = []
        var slotCapacityShortfalls: [String] = []
        var weightedGoals: [WorkoutAppearancePlanner.Constraint] = []
        func vector(_ value: (JointDoseOption) -> Double) -> [Double] { options.map(value) }
        for day in menus.indices where !blueprint.dayPlans[day].isRestDay {
            let slots = vector { $0.day == day && $0.sets > 0 ? 1 : 0 }
            lower.append(.init(name: "Day \(day + 1) exercise floor", coefficients: slots, limit: 5))
            upper.append(.init(name: "Day \(day + 1) exercise ceiling", coefficients: slots, limit: 6))
            upper.append(.init(name: "Day \(day + 1) fatigue", coefficients: vector { option in
                guard option.day == day, option.sets > 0 else { return 0 }
                let item = menus[day][option.slot]
                let response = WorkoutExerciseResponse(exerciseName: item.exerciseName, sets: option.sets,
                    reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: item.muscleTarget)
                return Double(estimatedDayFatigue(for: [response]))
            }, limit: Double(limits.fatigue[day])))
        }
        for index in blueprint.priorityAllocations.indices {
            let allocation = blueprint.priorityAllocations[index]
            let direct = vector { Double($0.sets) * accounting.exercises[$0.day][$0.slot].unitDirect[index] }
            let weighted = vector { Double($0.sets) * accounting.exercises[$0.day][$0.slot].unitWeighted[index] }
            lower.append(.init(name: "\(allocation.area) direct target", coefficients: direct,
                limit: allocation.directSetTarget - WorkoutSetBudgetPolicy.fundingTolerance))
            weightedGoals.append(.init(name: "\(allocation.area) weighted target", coefficients: weighted,
                limit: allocation.weightedStimulusTarget))
            upper.append(.init(name: "\(allocation.area) weekly ceiling", coefficients: direct,
                limit: limits.normalWeeklyPriority[index]))
            let prime = options.map { $0.sets > 0 && accounting.exercises[$0.day][$0.slot].qualityScore[index] == 30 }
            // Match the existing placement policy, not a stricter raw-slot demand.
            // The requested figure remains visible; direct/weighted dose and meaningful
            // frequency targets below are NOT reduced to excuse an unfundable slot.
            let trainingDays = menus.indices.filter { !blueprint.dayPlans[$0].isRestDay && !menus[$0].isEmpty }
            let preferredDays = trainingDays.filter { allocationPrefersStyle(allocation, blueprint.dayPlans[$0].style) }
            let candidateDays = preferredDays.isEmpty ? trainingDays : preferredDays
            let capacity = candidateDays.reduce(0) { total, day in
                total + fundablePrioritySlotsPerSession(for: allocation, isFocusDay: limits.focusMatch[day][index])
            }
            let requiredSlots = min(allocation.targetExerciseSlots, capacity)
            if requiredSlots < allocation.targetExerciseSlots {
                slotCapacityShortfalls.append("\(allocation.area): requested \(allocation.targetExerciseSlots) prime slots; existing placement capacity \(capacity)")
            }
            lower.append(.init(name: "\(allocation.area) prime slots", coefficients: prime.map { $0 ? 1 : 0 },
                limit: Double(requiredSlots)))
            thresholdCoverage.append(.init(name: "\(allocation.area) meaningful days", groups: menus.indices.map { day in
                .init(name: "Day \(day + 1) \(allocation.area) meaningful dose",
                    coefficients: options.indices.map { options[$0].day == day ? direct[$0] : 0 },
                    limit: minimumMeaningfulPriorityExposureSets(for: allocation.area) - 0.01)
            }, minimumGroups: allocation.targetFrequency))
            for day in menus.indices where !blueprint.dayPlans[day].isRestDay {
                upper.append(.init(name: "Day \(day + 1) \(allocation.area) ceiling",
                    coefficients: options.indices.map { options[$0].day == day ? direct[$0] : 0 },
                    limit: limits.sessionFundingCeiling(day: day, allocation: index)))
                if limits.focusMatch[day][index] {
                    lower.append(.init(name: "Day \(day + 1) \(allocation.area) focus",
                        coefficients: options.indices.map { options[$0].day == day && prime[$0] ? 1 : 0 }, limit: 1))
                }
            }
        }
        let minimum = WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight:
            blueprint.calibration.recoveryConstrained || blueprint.calibration.poorNutritionAdherence)
        for index in accounting.groups.indices {
            let group = accounting.groups[index]
            upper.append(.init(name: "\(group.label) maintenance/residue ceiling", coefficients: vector {
                accounting.exercises[$0.day][$0.slot].groupTargets[index] ? Double($0.sets) : 0
            }, limit: limits.maintenanceFundingCeiling))
            if !group.residueOnly {
                lower.append(.init(name: "\(group.label) maintenance floor", coefficients: vector {
                    accounting.exercises[$0.day][$0.slot].directlyTargetsGroup[index] ? Double($0.sets) : 0
                }, limit: minimum))
            }
            let coveredDays = menus.indices.map { day in
                options.indices.filter { options[$0].day == day && options[$0].sets > 0
                    && accounting.exercises[day][options[$0].slot].directlyTargetsGroup[index] }
            }.filter { !$0.isEmpty }
            coverage.append(.init(name: "\(group.label) baseline days", groups: coveredDays,
                minimumGroups: min(2, coveredDays.count)))
        }
        if let baseline {
            let old = weeklyExerciseAccounting(for: baseline, blueprint: blueprint)
            for index in blueprint.priorityAllocations.indices {
                let area = blueprint.priorityAllocations[index].area
                var weeklyDirect = 0.0, weeklyWeighted = 0.0, meaningfulDays = 0
                let threshold = minimumMeaningfulPriorityExposureSets(for: area)
                for day in baseline.indices {
                    let direct = baseline[day].indices.reduce(0.0) {
                        $0 + Double(baseline[day][$1].prescribedSets) * old.exercises[day][$1].unitDirect[index]
                    }
                    let weighted = baseline[day].indices.reduce(0.0) {
                        $0 + Double(baseline[day][$1].prescribedSets) * old.exercises[day][$1].unitWeighted[index]
                    }
                    weeklyDirect += direct
                    weeklyWeighted += weighted
                    if direct + 0.01 >= threshold { meaningfulDays += 1 }
                    lower.append(.init(name: "Day \(day + 1) \(area) baseline direct", coefficients: vector {
                        $0.day == day ? Double($0.sets) * accounting.exercises[$0.day][$0.slot].unitDirect[index] : 0
                    }, limit: direct - WorkoutSetBudgetPolicy.fundingTolerance))
                    lower.append(.init(name: "Day \(day + 1) \(area) baseline weighted", coefficients: vector {
                        $0.day == day ? Double($0.sets) * accounting.exercises[$0.day][$0.slot].unitWeighted[index] : 0
                    }, limit: weighted - WorkoutSetBudgetPolicy.fundingTolerance))
                }
                lower.append(.init(name: "\(area) baseline weekly direct", coefficients: vector {
                    Double($0.sets) * accounting.exercises[$0.day][$0.slot].unitDirect[index]
                }, limit: weeklyDirect - WorkoutSetBudgetPolicy.fundingTolerance))
                lower.append(.init(name: "\(area) baseline weekly weighted", coefficients: vector {
                    Double($0.sets) * accounting.exercises[$0.day][$0.slot].unitWeighted[index]
                }, limit: weeklyWeighted - WorkoutSetBudgetPolicy.fundingTolerance))
                thresholdCoverage.append(.init(name: "\(area) baseline meaningful days", groups: menus.indices.map { day in
                    .init(name: "Day \(day + 1) \(area) baseline meaningful dose", coefficients: vector {
                        $0.day == day ? Double($0.sets) * accounting.exercises[$0.day][$0.slot].unitDirect[index] : 0
                    }, limit: threshold - 0.01)
                }, minimumGroups: meaningfulDays))
            }
            var regions: [String: Double] = [:]
            for item in baseline.joined() {
                // The canonical catalog check above is mandatory before region arithmetic.
                let known = exerciseMetadataCatalog[normalizeExerciseName(item.exerciseName)]!
                for region in Set(known.primaryAreas.map(normalizedPriorityText)) {
                    regions[region, default: 0] += Double(item.prescribedSets)
                }
            }
            for region in regions.keys.sorted() {
                lower.append(.init(name: "\(region) baseline region", coefficients: vector {
                    let item = menus[$0.day][$0.slot]
                    let known = exerciseMetadataCatalog[normalizeExerciseName(item.exerciseName)]!
                    return Set(known.primaryAreas.map(normalizedPriorityText)).contains(region) ? Double($0.sets) : 0
                }, limit: regions[region]!))
            }
            for index in old.groups.indices where !old.groups[index].residueOnly {
                let total = baseline.indices.reduce(0.0) { sum, day in
                    sum + baseline[day].indices.reduce(0.0) {
                        $0 + (old.exercises[day][$1].directlyTargetsGroup[index] ? Double(baseline[day][$1].prescribedSets) : 0)
                    }
                }
                lower.append(.init(name: "\(old.groups[index].label) baseline maintenance", coefficients: vector {
                    accounting.exercises[$0.day][$0.slot].directlyTargetsGroup[index] ? Double($0.sets) : 0
                }, limit: total - WorkoutSetBudgetPolicy.fundingTolerance))
            }
        }
        return .init(problem: .init(domains: domains, upperBounds: upper, lowerBounds: lower, coverage: coverage,
            thresholdCoverage: thresholdCoverage),
            options: options, slotCapacityShortfalls: slotCapacityShortfalls, weightedGoals: weightedGoals)
    }

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
