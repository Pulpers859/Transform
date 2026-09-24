import Foundation

extension ClaudeService {
    /// Appearance reservation status, NOT a claim that all final volume targets were met.
    enum RoleFloorAdmission: Equatable {
        case unassessed, deloadPolicy, admitted
        case infeasible([String])
        case searchLimit([String])
    }

    // Compare plans before the locked menu reaches AI/fallback. A maintenance improvement
    // must not silently choose which priority target loses when budgets cannot fit both.
    func allocateWeeklySetPrescription(
        _ menus: [[PreSelectedExercise]], blueprint: ProgramBlueprint, weekNumber: Int,
        lockedPrefixCounts: [Int] = [], appearancePlanningReport: ((String) -> Void)? = nil,
        setFundingReport: (([SetFundingObservation]) -> Void)? = nil,
        maximumAppearanceStates: Int = 512,
        roleFloorAdmissionReport: ((RoleFloorAdmission) -> Void)? = nil,
        publishConflictLogs: Bool = true
    ) -> [[PreSelectedExercise]] {
        var baselineMessages: [String] = []
        var baselineReceipts: [SetFundingObservation] = []
        let baselineObserver: (([SetFundingObservation]) -> Void)? = setFundingReport == nil ? nil : { baselineReceipts = $0 }
        let baseline = allocateSetPrescriptionCandidate(menus, blueprint: blueprint, weekNumber: weekNumber,
            reserveMaintenanceMinimum: false, lockedPrefixCounts: lockedPrefixCounts,
            appearancePlanningReport: { baselineMessages.append($0) }, setFundingReport: baselineObserver,
            maximumAppearanceStates: maximumAppearanceStates, publishConflictLogs: publishConflictLogs)
        guard baseline.floorReserved else {
            baselineMessages.forEach { appearancePlanningReport?($0) }
            setFundingReport?(baselineReceipts)
            roleFloorAdmissionReport?(baseline.roleFloorAdmission)
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
        var admission = baseline.roleFloorAdmission
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
                appearancePlanningReport: { candidateMessages.append($0) }, setFundingReport: observer,
                maximumAppearanceStates: maximumAppearanceStates, publishConflictLogs: publishConflictLogs)
            if candidate.floorReserved && minimumDoseCandidatePreservesPlan(candidate.menus,
                baseline: baseline.menus, blueprint: blueprint, weekNumber: weekNumber) {
                chosen = candidate.menus
                messages = candidateMessages + ["minimum dose plan accepted: priority delivery preserved"]
                receipts = candidateReceipts
                admission = candidate.roleFloorAdmission
            } else {
                messages.append("minimum dose plan rejected: no safe improvement over priority-first plan")
            }
        }
        for group in groups where groupSets(chosen, group) + 0.01 < minimum {
            messages.append("minimum dose unresolved: \(accounting.groups[group].label); delivered=\(groupSets(chosen, group)); required=\(minimum)")
        }
        messages.forEach { appearancePlanningReport?($0) }
        setFundingReport?(receipts)
        roleFloorAdmissionReport?(admission)
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
        guard case .dosePreserved(let improvesMinimum) = compareAllocatedDoseOnly(candidate,
            baseline: baseline, blueprint: blueprint, weekNumber: weekNumber) else { return false }
        return improvesMinimum
    }

    enum AllocatedPlanDoseFailure: Equatable {
        case calendarShape
        case fatigue(day: Int)
        case roleDose(day: Int, exercise: Int)
        case weeklyPriority(area: String)
        case sessionPriority(day: Int, area: String)
        case maintenanceCeiling(group: String)
        case maintenanceLoss(group: String)
    }

    enum AllocatedPlanDoseComparison: Equatable {
        case rejected(AllocatedPlanDoseFailure)
        case dosePreserved(improvesMaintenanceMinimum: Bool)
    }

    enum ExactFundedDoseFailure: Equatable {
        case invalidContext
        case baselineNotAdmitted
        case unsupportedWeek
        case unknownExercise(day: Int, exercise: Int)
        case dose(AllocatedPlanDoseFailure)
        case weeklyPriorityCeiling(area: String)
        case primaryRegionLoss(region: String, baselineSets: Int, candidateSets: Int)
    }

    enum ExactFundedDoseVerification: Equatable {
        case verified
        case refused(ExactFundedDoseFailure)
    }

    /// Quantitative check of the supplied sets, NOT allocation or authorization to
    /// adopt a placement. Identity/history/symptom protection, ordering, spacing,
    /// selection quality and delivered prescriptions require separate checks.
    /// ExactFundedDoseTests pins immutable inputs and the refusal boundaries.
    func verifyExactFundedDose(_ candidate: [[PreSelectedExercise]],
        baseline: SubstitutionPlanningBaseline) -> ExactFundedDoseVerification {
        let menus = baseline.menus, blueprint = baseline.blueprint
        guard (1...3).contains(baseline.weekNumber) else { return .refused(.unsupportedWeek) }
        guard baseline.roleFloorAdmission == .admitted else { return .refused(.baselineNotAdmitted) }
        guard menus.count == 7, candidate.count == 7, blueprint.dayPlans.count == 7,
              blueprint.dayPlans.filter({ !$0.isRestDay }).count == blueprint.weeklyTrainingDays,
              menus.indices.allSatisfy({ day in
                  let plan = blueprint.dayPlans[day]
                  return plan.dayIndex == day + 1
                      && (plan.isRestDay ? menus[day].isEmpty && candidate[day].isEmpty
                          : !menus[day].isEmpty && (5...6).contains(candidate[day].count))
                      && menus[day].allSatisfy { $0.prescribedSets > 0 }
                      && candidate[day].allSatisfy { $0.prescribedSets > 0 }
              }) else { return .refused(.invalidContext) }

        // Regional preservation must use known catalog regions, not a target label
        // or inferred metadata. Locked-menu callers supply canonical identities.
        for plan in [menus, candidate] {
            for day in plan.indices {
                for slot in plan[day].indices {
                    let item = plan[day][slot], name = item.exerciseName
                    guard let known = exerciseMetadataCatalog[normalizeExerciseName(name)],
                          known.canonicalName == name else {
                        return .refused(.unknownExercise(day: day, exercise: slot))
                    }
                    // Reject malformed counts before fatigue/credit arithmetic. This
                    // is the allocator's widest role ceiling (including prime work),
                    // not a new funding allowance; the comparison still applies each
                    // candidate's actual, potentially lower ceiling below.
                    let widestCeiling = max(proceduralSets(for: baseline.weekNumber,
                        exerciseName: name, muscleTarget: item.muscleTarget), 4)
                    guard item.prescribedSets <= widestCeiling else {
                        return .refused(.invalidContext)
                    }
                }
            }
        }
        let dose = compareAllocatedDoseOnly(candidate, baseline: menus,
            blueprint: blueprint, weekNumber: baseline.weekNumber)
        if case .rejected(let reason) = dose {
            return .refused(.dose(reason))
        }
        let accounting = weeklyExerciseAccounting(for: candidate, blueprint: blueprint)
        let limits = setBudgetLimits(for: blueprint)
        // The comparison above permits inherited weekly overage. New exact-funded
        // candidates must independently fit the normal funding ceiling; they do
        // not inherit the legacy allocator's exceptional role-floor allowance.
        for allocation in blueprint.priorityAllocations.indices {
            let direct = candidate.indices.reduce(0.0) { total, day in
                total + candidate[day].indices.reduce(0.0) { sum, slot in
                    sum + Double(candidate[day][slot].prescribedSets)
                        * accounting.exercises[day][slot].unitDirect[allocation]
                }
            }
            guard direct <= limits.normalWeeklyPriority[allocation] else {
                return .refused(.weeklyPriorityCeiling(area: blueprint.priorityAllocations[allocation].area))
            }
        }
        func regionalSets(_ plan: [[PreSelectedExercise]]) -> [String: Int] {
            var totals: [String: Int] = [:]
            for item in plan.joined() {
                guard let info = exerciseMetadataCatalog[normalizeExerciseName(item.exerciseName)] else { continue }
                for region in Set(info.primaryAreas.map(normalizedPriorityText)) {
                    totals[region, default: 0] += item.prescribedSets
                }
            }
            return totals
        }
        let original = regionalSets(menus), proposed = regionalSets(candidate)
        for region in original.keys.sorted() {
            let old = original[region, default: 0], new = proposed[region, default: 0]
            if new < old {
                return .refused(.primaryRegionLoss(region: region, baselineSets: old, candidateSets: new))
            }
        }
        return .verified
    }

    /// Dose-only comparison, not authorization to substitute exercises. Callers must separately
    /// enforce identity/eligibility, locked slots, rest-day shape, movement/focus quality and their
    /// improvement objective. In particular, the minimum-dose caller above retains its identity lock.
    /// Returns the first failing check in policy order, not an exhaustive defect list. Day/slot
    /// indices are zero-based. Existing tolerances and maintenance-minimum objective are unchanged.
    func compareAllocatedDoseOnly(_ candidate: [[PreSelectedExercise]],
        baseline: [[PreSelectedExercise]], blueprint: ProgramBlueprint, weekNumber: Int) -> AllocatedPlanDoseComparison {
        guard candidate.count == baseline.count, candidate.count == blueprint.dayPlans.count else {
            return .rejected(.calendarShape)
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
            guard estimatedDayFatigue(for: newDays[day].exercises) <= limits.fatigue[day] else {
                return .rejected(.fatigue(day: day))
            }
            for index in candidate[day].indices {
                let slot = candidate[day][index], cost = accounting.exercises[day][index]
                let prime = blueprint.priorityAllocations.indices.contains { cost.unitDirect[$0] > 0 && cost.qualityScore[$0] == 30 }
                let ceiling = max(proceduralSets(for: weekNumber, exerciseName: slot.exerciseName,
                    muscleTarget: slot.muscleTarget), prime ? 4 : 0)
                guard slot.prescribedSets >= cost.setFloor, slot.prescribedSets <= ceiling else {
                    return .rejected(.roleDose(day: day, exercise: index))
                }
            }
        }
        for index in blueprint.priorityAllocations.indices {
            let allocation = blueprint.priorityAllocations[index]
            let old = priorityCoverage(for: allocation, stimulusReport: oldReport)
            let new = priorityCoverage(for: allocation, stimulusReport: newReport)
            guard new.directSets + 0.01 >= old.directSets, new.weightedStimulus + 0.01 >= old.weightedStimulus,
                  new.meaningfulDayMatches >= old.meaningfulDayMatches,
                  new.directSets <= max(old.directSets, limits.normalWeeklyPriority[index]) + 0.001 else {
                return .rejected(.weeklyPriority(area: allocation.area))
            }
            for day in candidate.indices {
                let oldCredits = oldDays[day].exercises.map { stimulusCredit(for: $0, area: allocation.area) }
                let newCredits = newDays[day].exercises.map { stimulusCredit(for: $0, area: allocation.area) }
                let direct = newCredits.reduce(0.0) { $0 + $1.directSets }
                let weighted = newCredits.reduce(0.0) { $0 + $1.weightedStimulus }
                guard direct + 0.01 >= oldCredits.reduce(0.0, { $0 + $1.directSets }),
                      weighted + 0.01 >= oldCredits.reduce(0.0, { $0 + $1.weightedStimulus }),
                      direct <= limits.sessionFundingCeiling(day: day, allocation: index) else {
                    return .rejected(.sessionPriority(day: day, area: allocation.area))
                }
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
            guard debit <= limits.maintenanceFundingCeiling else {
                return .rejected(.maintenanceCeiling(group: item.label))
            }
            guard !item.residueOnly else { continue }
            let old = weeklyDirectSets(forGroupAliases: item.aliases, days: oldDays)
            let new = weeklyDirectSets(forGroupAliases: item.aliases, days: newDays)
            guard new + 0.01 >= old else { return .rejected(.maintenanceLoss(group: item.label)) }
            improved = improved || min(new, minimum) > min(old, minimum) + 0.01
        }
        return .dosePreserved(improvesMaintenanceMinimum: improved)
    }
}
