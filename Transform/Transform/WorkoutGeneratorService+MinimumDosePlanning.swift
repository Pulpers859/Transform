import Foundation

extension ClaudeService {
    // Compare plans before the locked menu reaches AI/fallback. A maintenance improvement
    // must not silently choose which priority target loses when budgets cannot fit both.
    func allocateWeeklySetPrescription(
        _ menus: [[PreSelectedExercise]], blueprint: ProgramBlueprint, weekNumber: Int,
        lockedPrefixCounts: [Int] = [], appearancePlanningReport: ((String) -> Void)? = nil,
        setFundingReport: (([SetFundingObservation]) -> Void)? = nil
    ) -> [[PreSelectedExercise]] {
        var baselineMessages: [String] = []
        var baselineReceipts: [SetFundingObservation] = []
        let baselineObserver: (([SetFundingObservation]) -> Void)? = setFundingReport == nil ? nil : { baselineReceipts = $0 }
        let baseline = allocateSetPrescriptionCandidate(menus, blueprint: blueprint, weekNumber: weekNumber,
            reserveMaintenanceMinimum: false, lockedPrefixCounts: lockedPrefixCounts,
            appearancePlanningReport: { baselineMessages.append($0) }, setFundingReport: baselineObserver)
        guard baseline.floorReserved else {
            baselineMessages.forEach { appearancePlanningReport?($0) }
            setFundingReport?(baselineReceipts)
            return baseline.menus
        }

        let accounting = weeklyExerciseAccounting(for: baseline.menus, blueprint: blueprint)
        let minimum = WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight:
            blueprint.calibration.recoveryConstrained || blueprint.calibration.poorNutritionAdherence)
        func groupSets(_ plan: [[PreSelectedExercise]], _ group: Int) -> Double {
            plan.indices.reduce(0) { total, day in
                total + plan[day].indices.reduce(0) { sum, index in
                    sum + (accounting.exercises[day][index].directlyTargetsGroup[group]
                        ? Double(plan[day][index].prescribedSets) : 0)
                }
            }
        }
        let groups = accounting.groups.indices.filter { !accounting.groups[$0].residueOnly }
        var chosen = baseline.menus
        var messages = baselineMessages
        var receipts = baselineReceipts
        // Do not pay for a second allocation when only absent candidates are missing.
        let deficient = groups.filter { groupSets(chosen, $0) > 0 && groupSets(chosen, $0) + 0.01 < minimum }
        if !deficient.isEmpty {
            var candidateMessages: [String] = []
            var candidateReceipts: [SetFundingObservation] = []
            let observer: (([SetFundingObservation]) -> Void)? = setFundingReport == nil ? nil : { candidateReceipts = $0 }
            let candidate = allocateSetPrescriptionCandidate(menus, blueprint: blueprint, weekNumber: weekNumber,
                reserveMaintenanceMinimum: true,
                minimumReservationGroups: Set(deficient.map { accounting.groups[$0].label }),
                lockedPrefixCounts: lockedPrefixCounts,
                appearancePlanningReport: { candidateMessages.append($0) }, setFundingReport: observer)
            if candidate.floorReserved && minimumDoseCandidatePreservesPlan(candidate.menus,
                baseline: baseline.menus, blueprint: blueprint, weekNumber: weekNumber) {
                chosen = candidate.menus
                messages = candidateMessages + ["minimum dose plan accepted: priority delivery preserved"]
                receipts = candidateReceipts
            } else {
                messages.append("minimum dose plan rejected: no safe improvement over priority-first plan")
            }
        }
        for group in groups where groupSets(chosen, group) + 0.01 < minimum {
            messages.append("minimum dose unresolved: \(accounting.groups[group].label); delivered=\(groupSets(chosen, group)); required=\(minimum)")
        }
        messages.forEach { appearancePlanningReport?($0) }
        setFundingReport?(receipts)
        return chosen
    }

    func minimumDoseCandidatePreservesPlan(_ candidate: [[PreSelectedExercise]],
        baseline: [[PreSelectedExercise]], blueprint: ProgramBlueprint, weekNumber: Int) -> Bool {
        guard candidate.count == baseline.count, candidate.count == blueprint.dayPlans.count else { return false }
        for day in baseline.indices {
            guard candidate[day].count == baseline[day].count else { return false }
            for index in baseline[day].indices {
                let lhs = baseline[day][index], rhs = candidate[day][index]
                guard lhs.exerciseName == rhs.exerciseName, lhs.muscleTarget == rhs.muscleTarget,
                      lhs.role == rhs.role, lhs.movementPattern == rhs.movementPattern else { return false }
            }
        }
        func days(_ plan: [[PreSelectedExercise]]) -> [WorkoutDayResponse] {
            plan.indices.map { day in
                WorkoutDayResponse(dayNumber: day + 1, dayName: "Planning", muscleGroups: "Planning",
                    isRestDay: blueprint.dayPlans[day].isRestDay, notes: "", exercises: plan[day].map {
                        WorkoutExerciseResponse(exerciseName: $0.exerciseName, sets: $0.prescribedSets,
                            reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: $0.muscleTarget)
                    })
            }
        }
        let oldDays = days(baseline), newDays = days(candidate)
        let oldReport = buildWeekStimulusReport(from: oldDays), newReport = buildWeekStimulusReport(from: newDays)
        let limits = setBudgetLimits(for: blueprint)
        let accounting = weeklyExerciseAccounting(for: candidate, blueprint: blueprint)
        for day in candidate.indices {
            guard estimatedDayFatigue(for: newDays[day].exercises) <= limits.fatigue[day] else { return false }
            for index in candidate[day].indices {
                let slot = candidate[day][index], cost = accounting.exercises[day][index]
                let prime = blueprint.priorityAllocations.indices.contains { cost.unitDirect[$0] > 0 && cost.qualityScore[$0] == 30 }
                let ceiling = max(proceduralSets(for: weekNumber, exerciseName: slot.exerciseName,
                    muscleTarget: slot.muscleTarget), prime ? 4 : 0)
                guard slot.prescribedSets >= cost.setFloor, slot.prescribedSets <= ceiling else { return false }
            }
        }
        for index in blueprint.priorityAllocations.indices {
            let allocation = blueprint.priorityAllocations[index]
            let old = priorityCoverage(for: allocation, stimulusReport: oldReport)
            let new = priorityCoverage(for: allocation, stimulusReport: newReport)
            guard new.directSets + 0.01 >= old.directSets, new.weightedStimulus + 0.01 >= old.weightedStimulus,
                  new.meaningfulDayMatches >= old.meaningfulDayMatches,
                  new.directSets <= max(old.directSets, limits.normalWeeklyPriority[index]) + 0.001 else { return false }
            for day in candidate.indices {
                let oldCredits = oldDays[day].exercises.map { stimulusCredit(for: $0, area: allocation.area) }
                let newCredits = newDays[day].exercises.map { stimulusCredit(for: $0, area: allocation.area) }
                let direct = newCredits.reduce(0.0) { $0 + $1.directSets }
                let weighted = newCredits.reduce(0.0) { $0 + $1.weightedStimulus }
                guard direct + 0.01 >= oldCredits.reduce(0.0, { $0 + $1.directSets }),
                      weighted + 0.01 >= oldCredits.reduce(0.0, { $0 + $1.weightedStimulus }),
                      direct <= limits.sessionFundingCeiling(day: day, allocation: index) else { return false }
            }
        }
        let minimum = WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight:
            blueprint.calibration.recoveryConstrained || blueprint.calibration.poorNutritionAdherence)
        var improved = false
        for group in accounting.groups.indices {
            let item = accounting.groups[group]
            let debit = candidate.indices.reduce(0.0) { total, day in
                total + candidate[day].indices.reduce(0.0) { sum, index in
                    sum + (accounting.exercises[day][index].groupTargets[group] ? Double(candidate[day][index].prescribedSets) : 0)
                }
            }
            guard debit <= limits.maintenanceFundingCeiling else { return false }
            guard !item.residueOnly else { continue }
            let old = weeklyDirectSets(forGroupAliases: item.aliases, days: oldDays)
            let new = weeklyDirectSets(forGroupAliases: item.aliases, days: newDays)
            guard new + 0.01 >= old else { return false }
            improved = improved || min(new, minimum) > min(old, minimum) + 0.01
        }
        return improved
    }
}
