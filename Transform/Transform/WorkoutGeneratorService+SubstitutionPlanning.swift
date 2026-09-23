import Foundation

extension ClaudeService {
    /// One Week 1 removal and one fresh allocation. Only existing, editable work for
    /// the same nonpriority region may gain sets; every surviving prescription is monotonic.
    func finalizeSameRegionPressdownConsolidation(_ baseline: SubstitutionPlanningBaseline,
        day: Int, donor: Int, trainingIntent: TrainingIntentPlan,
        baselineMessages: [String], baselineReceipts: [SetFundingObservation], collectFunding: Bool = false
    ) -> PressdownFinalization {
        func refused(_ reason: String) -> PressdownFinalization {
            .init(plan: baseline, messages: baselineMessages, receipts: baselineReceipts,
                decision: .consolidationRefused(reason))
        }
        let menus = baseline.menus, blueprint = baseline.blueprint
        guard baseline.roleFloorAdmission == .admitted,
              baseline.weekNumber == 1,
              menus.count == 7, blueprint.dayPlans.count == 7,
              blueprint.dayPlans.filter({ !$0.isRestDay }).count == blueprint.weeklyTrainingDays,
              baseline.lockedPrefixCounts.count == 7, baseline.retainedKeysByDay.count == 7,
              baseline.selectionFocusIntents.count == 7,
              menus.indices.contains(day), menus[day].indices.contains(donor),
              menus.indices.allSatisfy({ index in
                  blueprint.dayPlans[index].dayIndex == index + 1
                      && baseline.lockedPrefixCounts[index] >= 0
                      && baseline.lockedPrefixCounts[index] <= menus[index].count
                      && (blueprint.dayPlans[index].isRestDay ? menus[index].isEmpty : (5...6).contains(menus[index].count))
                      && menus[index].allSatisfy { $0.prescribedSets > 0 }
              }), menus[day].count == 6 else { return refused("invalid consolidation context") }
        let removed = menus[day][donor]
        guard pressdownRedundancyFamily.contains(removed.exerciseName),
              excessPressdownsByDay(in: menus)[day] > 0 else { return refused("no redundant pressdown") }
        func editable(_ index: Int, _ slot: Int) -> Bool {
            let item = menus[index][slot]
            let key = ExerciseWeightEntry.canonicalLookupKey(item.exerciseName)
            return !isProtectedAppearance(role: item.role, slot: slot, style: blueprint.dayPlans[index].style,
                       lockedPrefixCount: baseline.lockedPrefixCounts[index])
                && !isProtectedAppearance(role: proceduralExerciseRole(for: item.exerciseName, muscleTarget: item.muscleTarget),
                    slot: slot, style: blueprint.dayPlans[index].style, lockedPrefixCount: baseline.lockedPrefixCounts[index])
                && !baseline.retainedKeysByDay[index].contains(key)
                && !(baseline.exerciseHistory?.painExercises.contains(key) ?? false)
                && !(baseline.exerciseHistory?.equipmentSkipExercises.contains(key) ?? false)
                && !reportedShoulderPainImplicates(exerciseName: item.exerciseName, muscleTarget: item.muscleTarget,
                    injuryRiskFocus: blueprint.injuryRiskFocus)
        }
        guard editable(day, donor) else { return refused("protected consolidation donor") }
        func regions(_ item: PreSelectedExercise) -> Set<String> {
            Set(exerciseMetadata(forExerciseName: item.exerciseName, muscleTarget: item.muscleTarget)
                .primaryAreas.map(normalizedPriorityText))
        }
        let targetRegions = regions(removed)
        guard !targetRegions.isEmpty else { return refused("unknown donor region") }
        let receivers = menus[day].indices.filter { $0 != donor && editable(day, $0) && regions(menus[day][$0]) == targetRegions }
        guard !receivers.isEmpty else { return refused("no same-region receiver") }
        let accounting = weeklyExerciseAccounting(for: menus, blueprint: blueprint)
        guard accounting.exercises[day][donor].unitDirect.allSatisfy({ $0 == 0 }) else {
            return refused("priority-region consolidation is outside this boundary")
        }
        func ceiling(_ slot: Int) -> Int {
            let item = menus[day][slot], cost = accounting.exercises[day][slot]
            let prime = blueprint.priorityAllocations.indices.contains { cost.unitDirect[$0] > 0 && cost.qualityScore[$0] == 30 }
            return max(proceduralSets(for: baseline.weekNumber, exerciseName: item.exerciseName,
                muscleTarget: item.muscleTarget), prime ? 4 : 0)
        }
        var proposed = menus
        var remaining = removed.prescribedSets
        // Bounded by the removed prescription, never enlarge a per-exercise ceiling.
        while remaining > 0 {
            var moved = false
            for slot in receivers where remaining > 0 && proposed[day][slot].prescribedSets < ceiling(slot) {
                proposed[day][slot].prescribedSets += 1
                remaining -= 1
                moved = true
            }
            guard moved else { return refused("same-region receivers lack set capacity") }
        }
        proposed[day].remove(at: donor)
        guard case .dosePreserved = compareAllocatedDoseOnly(proposed, baseline: menus,
            blueprint: blueprint, weekNumber: baseline.weekNumber) else { return refused("proposed dose refused") }
        var admission: RoleFloorAdmission = .unassessed
        var messages: [String] = []
        var receipts: [SetFundingObservation] = []
        let observer: (([SetFundingObservation]) -> Void)? = collectFunding ? { receipts = $0 } : nil
        let allocated = allocateWeeklySetPrescription(proposed, blueprint: blueprint,
            weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
            appearancePlanningReport: { messages.append($0) }, setFundingReport: observer,
            roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
        func signature(_ plan: [[PreSelectedExercise]]) -> [[String]] {
            plan.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
        }
        guard admission == .admitted, allocated.count == proposed.count,
              zip(allocated, proposed).allSatisfy({ actual, expected in
                  actual.count == expected.count && zip(actual, expected).allSatisfy { lhs, rhs in
                      lhs.exerciseName == rhs.exerciseName && lhs.muscleTarget == rhs.muscleTarget
                          && lhs.role == rhs.role && lhs.movementPattern == rhs.movementPattern
                  }
              }) else { return refused("fresh allocation changed consolidation identities") }
        for index in menus.indices {
            for slot in menus[index].indices where !(index == day && slot == donor) {
                let old = menus[index][slot]
                let newSlot = index == day && slot > donor ? slot - 1 : slot
                let new = allocated[index][newSlot]
                guard new.prescribedSets >= old.prescribedSets else { return refused("surviving prescription lost sets") }
                if new.prescribedSets != old.prescribedSets {
                    guard editable(index, slot), regions(old) == targetRegions,
                          accounting.exercises[index][slot].unitDirect.allSatisfy({ $0 == 0 }) else {
                        return refused("allocation changed protected or unrelated work")
                    }
                }
            }
        }
        func regionalSets(_ plan: [[PreSelectedExercise]]) -> [String: Int] {
            var totals: [String: Int] = [:]
            for item in plan.joined() { for region in regions(item) { totals[region, default: 0] += item.prescribedSets } }
            return totals
        }
        guard regionalSets(allocated) == regionalSets(menus),
              case .dosePreserved = compareAllocatedDoseOnly(allocated, baseline: menus,
                blueprint: blueprint, weekNumber: baseline.weekNumber) else {
            return refused("allocated regional dose refused")
        }
        let ordered = reorderedMenusForSessionFlow(allocated, blueprint: blueprint,
            trainingIntent: trainingIntent, lockedPrefixCounts: baseline.lockedPrefixCounts)
        guard signature(ordered) == signature(allocated) else { return refused("consolidation order changed") }
        func findings(_ plan: [[PreSelectedExercise]]) -> [String] {
            let output = buildProceduralWeek(weekNumber: 1, dayStart: 1, dayEnd: 7,
                splitType: trainingIntent.splitRecommendation, programName: "Consolidation verification",
                trainingIntent: trainingIntent, blueprint: blueprint, previousWeekDays: nil, exerciseMenus: plan)
            return validateWeekResponse(output, dayStart: 1, dayEnd: 7, previousWeekDays: nil,
                blueprint: blueprint, expectedExerciseMenus: plan)
        }
        let oldCounts = Dictionary(grouping: findings(menus), by: { $0 }).mapValues(\.count)
        let newCounts = Dictionary(grouping: findings(allocated), by: { $0 }).mapValues(\.count)
        guard newCounts.allSatisfy({ message, count in count <= oldCounts[message, default: 0] }) else {
            return refused("consolidation introduced validator findings")
        }
        let plan = SubstitutionPlanningBaseline(menus: allocated, blueprint: blueprint,
            weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
            retainedKeysByDay: baseline.retainedKeysByDay, exerciseHistory: baseline.exerciseHistory,
            selectionFocusIntents: baseline.selectionFocusIntents, roleFloorAdmission: admission)
        return .init(plan: plan, messages: messages, receipts: receipts,
            decision: .consolidated(day: day, removed: removed.exerciseName))
    }

    struct CapacityShoulderRegionLoss: Equatable {
        let region: String
        let baselineSets: Int
        let candidateSets: Int
    }

    /// Capacity-specific protection: broad shoulder totals cannot replace direct work
    /// for another deltoid region. Weekly comparison permits across-day redistribution.
    /// This is a conservative planning rule, not a biological equivalence or safety claim.
    func capacityShoulderRegionLoss(_ candidate: [[PreSelectedExercise]],
        baseline: [[PreSelectedExercise]]) -> CapacityShoulderRegionLoss? {
        for bucket in weeklyVariationBuckets(for: "Shoulders") {
            func sets(_ menus: [[PreSelectedExercise]]) -> Int {
                menus.joined().reduce(0) { total, exercise in
                    total + (exerciseDirectlyTargets(groupAliases: bucket.primaryAreas,
                        exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
                        ? exercise.prescribedSets : 0)
                }
            }
            let old = sets(baseline), new = sets(candidate)
            if new < old {
                return .init(region: bucket.label, baselineSets: old, candidateSets: new)
            }
        }
        return nil
    }

    struct SessionCapacityFinalization {
        let plan: SubstitutionPlanningBaseline
        let messages: [String]
        let receipts: [SetFundingObservation]
        let decision: String
    }

    /// Bounded capacity planning. The subset and optional relocation stages each
    /// permit at most one fresh allocation; neither may lose complete-plan dose.
    func finalizeSessionCapacity(_ baseline: SubstitutionPlanningBaseline,
        trainingIntent: TrainingIntentPlan, baselineMessages: [String],
        baselineReceipts: [SetFundingObservation], collectFunding: Bool,
        previousWeekDays: [WorkoutDayResponse]? = nil) -> SessionCapacityFinalization {
        let subset = finalizeSessionCapacitySubset(baseline, trainingIntent: trainingIntent,
            baselineMessages: baselineMessages, baselineReceipts: baselineReceipts, collectFunding: collectFunding)
        guard !subset.decision.hasPrefix("adopted"), baseline.menus.contains(where: { $0.count > 6 }) else {
            return subset
        }
        let placement = finalizeFirstAccessoryRelocation(baseline, trainingIntent: trainingIntent,
            previousWeekDays: previousWeekDays, baselineMessages: baselineMessages,
            baselineReceipts: baselineReceipts, collectFunding: collectFunding)
        // Keep the existing refusal and its reports unless the whole placement passes.
        return placement.decision.hasPrefix("adopted") ? placement : subset
    }

    private func finalizeSessionCapacitySubset(_ baseline: SubstitutionPlanningBaseline,
        trainingIntent: TrainingIntentPlan, baselineMessages: [String],
        baselineReceipts: [SetFundingObservation], collectFunding: Bool) -> SessionCapacityFinalization {
        func retained(_ reason: String) -> SessionCapacityFinalization {
            .init(plan: baseline, messages: baselineMessages, receipts: baselineReceipts, decision: reason)
        }
        guard baseline.roleFloorAdmission == .admitted else { return retained("baseline not admitted") }
        let menus = baseline.menus, blueprint = baseline.blueprint
        guard menus.count == 7, blueprint.dayPlans.count == 7,
              baseline.lockedPrefixCounts.count == 7, baseline.retainedKeysByDay.count == 7,
              baseline.selectionFocusIntents.count == 7, baseline.weekNumber > 0,
              blueprint.dayPlans.filter({ !$0.isRestDay }).count == blueprint.weeklyTrainingDays,
              menus.indices.allSatisfy({ day in
                  blueprint.dayPlans[day].dayIndex == day + 1
                      && baseline.lockedPrefixCounts[day] >= 0
                      && baseline.lockedPrefixCounts[day] <= menus[day].count
                      && (blueprint.dayPlans[day].isRestDay ? menus[day].isEmpty : menus[day].count >= 5)
                      && menus[day].allSatisfy { $0.prescribedSets > 0 }
              }) else { return retained("invalid planning context") }
        guard menus.contains(where: { $0.count > 6 }) else { return retained("already within six exercises") }

        func sameIdentity(_ lhs: PreSelectedExercise, _ rhs: PreSelectedExercise) -> Bool {
            lhs.exerciseName == rhs.exerciseName && lhs.muscleTarget == rhs.muscleTarget
                && lhs.movementPattern == rhs.movementPattern && lhs.role == rhs.role
        }
        func sameIdentities(_ lhs: [[PreSelectedExercise]], _ rhs: [[PreSelectedExercise]]) -> Bool {
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { left, right in
                left.count == right.count && zip(left, right).allSatisfy { sameIdentity($0, $1) }
            }
        }
        func fitsCapacity(_ candidate: [[PreSelectedExercise]]) -> Bool {
            candidate.count == menus.count && candidate.indices.allSatisfy { day in
                blueprint.dayPlans[day].isRestDay ? candidate[day].isEmpty : (5...6).contains(candidate[day].count)
            }
        }
        let reservation = reserveWeeklyAppearanceFloors(menus, blueprint: blueprint,
            weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
            maximumExercisesPerDay: 6)
        switch reservation.outcome {
        case .infeasible(let conflicts): return retained("six-slot reservation infeasible: \(conflicts)")
        case .searchLimit(let conflicts): return retained("six-slot reservation search limit: \(conflicts)")
        case .admitted: break
        }
        let proposed = reservation.menus
        guard fitsCapacity(proposed) else { return retained("reservation did not satisfy six-slot capacity") }
        for day in menus.indices {
            // Match the subset in its original order; names alone cannot conceal relabeled
            // targets, movement patterns or roles. Removed historic identities are inert.
            var cursor = 0
            for slot in menus[day].indices {
                let old = menus[day][slot]
                if cursor < proposed[day].count, sameIdentity(old, proposed[day][cursor]) {
                    cursor += 1
                } else {
                    let actualRole = proceduralExerciseRole(for: old.exerciseName, muscleTarget: old.muscleTarget)
                    guard !isProtectedAppearance(role: old.role, slot: slot, style: blueprint.dayPlans[day].style,
                              lockedPrefixCount: baseline.lockedPrefixCounts[day]),
                          !isProtectedAppearance(role: actualRole, slot: slot, style: blueprint.dayPlans[day].style,
                              lockedPrefixCount: baseline.lockedPrefixCounts[day]),
                          !baseline.retainedKeysByDay[day].contains(ExerciseWeightEntry.canonicalLookupKey(old.exerciseName)) else {
                        return retained("reservation removed protected or retained appearance")
                    }
                }
            }
            guard cursor == proposed[day].count else { return retained("reservation changed identity or order") }
            let locked = baseline.lockedPrefixCounts[day]
            guard proposed[day].count >= locked,
                  (0..<locked).allSatisfy({ sameIdentity(menus[day][$0], proposed[day][$0]) }) else {
                return retained("reservation changed locked prefix")
            }
        }

        var admission: RoleFloorAdmission = .unassessed
        var messages: [String] = []
        var receipts: [SetFundingObservation] = []
        let observer: (([SetFundingObservation]) -> Void)? = collectFunding ? { receipts = $0 } : nil
        let allocated = allocateWeeklySetPrescription(proposed, blueprint: blueprint,
            weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
            appearancePlanningReport: { messages.append($0) }, setFundingReport: observer,
            roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
        guard admission == .admitted else { return retained("fresh allocation not admitted: \(admission)") }
        guard fitsCapacity(allocated), sameIdentities(allocated, proposed) else {
            return retained("fresh allocation changed candidate identity, order or capacity")
        }
        for day in menus.indices {
            guard (0..<baseline.lockedPrefixCounts[day]).allSatisfy({
                allocated[day][$0].prescribedSets == menus[day][$0].prescribedSets
            }) else { return retained("fresh allocation changed locked prefix dose") }
        }
        let dose = compareAllocatedDoseOnly(allocated, baseline: menus, blueprint: blueprint, weekNumber: baseline.weekNumber)
        guard case .dosePreserved = dose else { return retained("fresh allocation dose refused: \(dose)") }
        if let loss = capacityShoulderRegionLoss(allocated, baseline: menus) {
            return retained("fresh allocation shoulder region refused: \(loss.region) \(loss.baselineSets)->\(loss.candidateSets)")
        }
        let oldBackFindings = Dictionary(grouping: plannedBackBalanceFindings(menus, blueprint: blueprint), by: { $0 })
            .mapValues(\.count)
        let newBackFindings = Dictionary(grouping: plannedBackBalanceFindings(allocated, blueprint: blueprint), by: { $0 })
            .mapValues(\.count)
        guard newBackFindings.allSatisfy({ message, count in count <= oldBackFindings[message, default: 0] }) else {
            return retained("fresh allocation introduced a back-balance finding")
        }
        let ordered = reorderedMenusForSessionFlow(allocated, blueprint: blueprint,
            trainingIntent: trainingIntent, lockedPrefixCounts: baseline.lockedPrefixCounts)
        guard sameIdentities(ordered, allocated), zip(ordered, allocated).allSatisfy({ left, right in
            zip(left, right).allSatisfy { $0.prescribedSets == $1.prescribedSets }
        }) else { return retained("session ordering changed the funded candidate") }
        let plan = SubstitutionPlanningBaseline(menus: allocated, blueprint: blueprint,
            weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
            retainedKeysByDay: baseline.retainedKeysByDay, exerciseHistory: baseline.exerciseHistory,
            selectionFocusIntents: baseline.selectionFocusIntents, roleFloorAdmission: admission)
        return .init(plan: plan, messages: messages, receipts: receipts,
            decision: "adopted six-slot subset with complete-plan dose preserved")
    }

    struct RowBalanceFinalization {
        let plan: SubstitutionPlanningBaseline
        let messages: [String]
        let receipts: [SetFundingObservation]
        let decision: String
    }

    func plannedBackBalanceFindings(_ menus: [[PreSelectedExercise]], blueprint: ProgramBlueprint) -> [String] {
        guard menus.count == blueprint.dayPlans.count else { return ["Menu/day-plan count mismatch"] }
        return validateBackPatternBalance(days: menus.indices.map { day in
            WorkoutDayResponse(dayNumber: day + 1, dayName: blueprint.dayPlans[day].style,
                muscleGroups: "", isRestDay: blueprint.dayPlans[day].isRestDay, notes: "",
                exercises: menus[day].map {
                    WorkoutExerciseResponse(exerciseName: $0.exerciseName, sets: $0.prescribedSets,
                        reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: $0.muscleTarget)
                })
        })
    }

    /// Evaluate actual funded dose before locking the menu for generation. Reuse the complete
    /// substitution contract; at most one eligible proposal receives a fresh allocation.
    func finalizeRowBalance(_ baseline: SubstitutionPlanningBaseline,
        trainingIntent: TrainingIntentPlan, baselineMessages: [String],
        baselineReceipts: [SetFundingObservation], collectFunding: Bool) -> RowBalanceFinalization {
        func retained(_ reason: String) -> RowBalanceFinalization {
            .init(plan: baseline, messages: baselineMessages, receipts: baselineReceipts, decision: reason)
        }
        guard baseline.roleFloorAdmission == .admitted else { return retained("baseline not admitted") }
        guard baseline.menus.count == baseline.blueprint.dayPlans.count,
              baseline.lockedPrefixCounts.count == baseline.menus.count,
              baseline.retainedKeysByDay.count == baseline.menus.count,
              baseline.selectionFocusIntents.count == baseline.menus.count else {
            return retained("invalid planning context")
        }
        guard !plannedBackBalanceFindings(baseline.menus, blueprint: baseline.blueprint).isEmpty else {
            return retained("already balanced")
        }
        func signature(_ menus: [[PreSelectedExercise]]) -> [[String]] {
            menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role.rawValue)|\($0.prescribedSets)" } }
        }
        for day in baseline.menus.indices {
            for slot in baseline.menus[day].indices {
                let old = baseline.menus[day][slot]
                guard verticalPullPatterns.contains(old.movementPattern) else { continue }
                for alternative in exerciseCatalog(for: baseline.blueprint.dayPlans[day].style) {
                    let metadata = exerciseMetadata(forExerciseName: alternative.name, muscleTarget: alternative.target)
                    guard alternative.target == old.muscleTarget,
                          horizontalPullPatterns.contains(metadata.movementPattern) else { continue }
                    var proposed = baseline.menus
                    proposed[day][slot] = .init(exerciseName: alternative.name, muscleTarget: alternative.target,
                        movementPattern: metadata.movementPattern,
                        role: proceduralExerciseRole(for: alternative.name, muscleTarget: alternative.target),
                        prescribedSets: old.prescribedSets)
                    guard preflightFixedDoseSubstitution(proposed, plannedBaseline: baseline) == .structurallyEligible,
                          plannedBackBalanceFindings(proposed, blueprint: baseline.blueprint).isEmpty else { continue }
                    guard case .dosePreserved = compareAllocatedDoseOnly(proposed, baseline: baseline.menus,
                        blueprint: baseline.blueprint, weekNumber: baseline.weekNumber) else { continue }
                    let ordered = reorderedMenusForSessionFlow(proposed, blueprint: baseline.blueprint,
                        trainingIntent: trainingIntent, lockedPrefixCounts: baseline.lockedPrefixCounts)
                    guard signature(ordered) == signature(proposed) else { continue }
                    var admission: RoleFloorAdmission = .unassessed
                    var messages: [String] = []
                    var receipts: [SetFundingObservation] = []
                    let observer: (([SetFundingObservation]) -> Void)? = collectFunding ? { receipts = $0 } : nil
                    let allocated = allocateWeeklySetPrescription(proposed, blueprint: baseline.blueprint,
                        weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
                        appearancePlanningReport: { messages.append($0) }, setFundingReport: observer,
                        roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
                    guard admission == .admitted, signature(allocated) == signature(proposed) else {
                        return retained("first eligible proposal changed during allocation; alternatives unassessed")
                    }
                    let plan = SubstitutionPlanningBaseline(menus: allocated, blueprint: baseline.blueprint,
                        weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
                        retainedKeysByDay: baseline.retainedKeysByDay, exerciseHistory: baseline.exerciseHistory,
                        selectionFocusIntents: baseline.selectionFocusIntents, roleFloorAdmission: admission)
                    return .init(plan: plan, messages: messages, receipts: receipts,
                        decision: "adopted day \(day + 1): \(old.exerciseName) -> \(alternative.name)")
                }
            }
        }
        return retained("no eligible fixed-dose row substitution")
    }

    enum CoreRelocationDecision: Equatable {
        case noEligiblePlacement, unsupportedWeek
        case proposal(CoreRelocationRefusal)
        case invalidPreviousWeek, boundarySpacing, allocationChanged, deliveryMismatch, findingsNotImproved
        case finalNotAdmitted(RoleFloorAdmission)
        case adopted
    }

    struct CoreRelocationFinalization {
        let plan: SubstitutionPlanningBaseline
        let messages: [String]
        let receipts: [SetFundingObservation]
        let decision: CoreRelocationDecision
    }

    // Deterministic, bounded placement search. Only the first qualifying proposal gets
    // fresh allocation; a later refusal leaves other placements unassessed, not exhausted.
    func finalizeFirstCoreRelocation(_ baseline: SubstitutionPlanningBaseline,
        trainingIntent: TrainingIntentPlan, previousWeekDays: [WorkoutDayResponse]?,
        baselineMessages: [String], baselineReceipts: [SetFundingObservation], collectFunding: Bool
    ) -> CoreRelocationFinalization {
        func retained(_ decision: CoreRelocationDecision) -> CoreRelocationFinalization {
            .init(plan: baseline, messages: baselineMessages, receipts: baselineReceipts, decision: decision)
        }
        guard (1...3).contains(baseline.weekNumber) else { return retained(.unsupportedWeek) }
        guard baseline.roleFloorAdmission == .admitted else {
            return retained(.proposal(.baselineNotAdmitted))
        }
        guard baseline.menus.count == 7, baseline.blueprint.dayPlans.count == 7,
              baseline.lockedPrefixCounts.count == 7, baseline.retainedKeysByDay.count == 7,
              baseline.selectionFocusIntents.count == 7,
              baseline.menus.indices.allSatisfy({ day in
                  baseline.lockedPrefixCounts[day] >= 0 && baseline.lockedPrefixCounts[day] <= baseline.menus[day].count
                      && baseline.blueprint.dayPlans[day].dayIndex == day + 1
                      && (baseline.blueprint.dayPlans[day].isRestDay ? baseline.menus[day].isEmpty : !baseline.menus[day].isEmpty)
              }) else {
            return retained(.proposal(.invalidContext))
        }
        for source in baseline.menus.indices {
            guard baseline.menus[source].count == 7,
                  canonicalTrainingStyle(baseline.blueprint.dayPlans[source].style) == "Lower",
                  let slot = baseline.menus[source].indices.last else { continue }
            for destination in baseline.menus.indices {
                guard baseline.menus[destination].count == 5,
                      canonicalTrainingStyle(baseline.blueprint.dayPlans[destination].style) == "Pull" else { continue }
                guard case .candidate = proposeCoreRelocationTrial(baseline, sourceDay: source,
                    sourceSlot: slot, destinationDay: destination, trainingIntent: trainingIntent) else { continue }
                return finalizeCoreRelocation(baseline, sourceDay: source, sourceSlot: slot,
                    destinationDay: destination, trainingIntent: trainingIntent,
                    previousWeekDays: previousWeekDays, baselineMessages: baselineMessages,
                    baselineReceipts: baselineReceipts, collectFunding: collectFunding)
            }
        }
        return retained(.noEligiblePlacement)
    }

    // A narrow verification seam, not an allocator override. A fresh reservation must
    // preserve every proposed appearance and prescription before its receipts can publish.
    func verifyCoreRelocationAllocation(_ allocated: [[PreSelectedExercise]],
        admission: RoleFloorAdmission, proposed: SubstitutionPlanningBaseline) -> CoreRelocationDecision? {
        guard admission == .admitted else { return .finalNotAdmitted(admission) }
        guard allocated.count == proposed.menus.count,
              zip(allocated, proposed.menus).allSatisfy({ actual, expected in
                  actual.count == expected.count && zip(actual, expected).allSatisfy { lhs, rhs in
                      lhs.exerciseName == rhs.exerciseName && lhs.muscleTarget == rhs.muscleTarget
                          && lhs.movementPattern == rhs.movementPattern && lhs.role == rhs.role
                          && lhs.prescribedSets == rhs.prescribedSets
                  }
              }) else { return .allocationChanged }
        return nil
    }

    func verifyCoreRelocationDelivery(original: WorkoutWeekResponse, candidate: WorkoutWeekResponse,
        baseline: SubstitutionPlanningBaseline, proposed: SubstitutionPlanningBaseline,
        previousWeekDays: [WorkoutDayResponse]?) -> CoreRelocationDecision? {
        let dayStart = (baseline.weekNumber - 1) * 7 + 1
        func matches(_ output: WorkoutWeekResponse, _ menus: [[PreSelectedExercise]]) -> Bool {
            output.days.count == 7 && menus.count == 7
                && output.days.map(\.dayNumber) == Array(dayStart...(dayStart + 6))
                && zip(output.days, menus).allSatisfy { day, menu in
                    day.exercises.count == menu.count && zip(day.exercises, menu).allSatisfy { lhs, rhs in
                        lhs.exerciseName == rhs.exerciseName && lhs.muscleTarget == rhs.muscleTarget
                            && lhs.sets == rhs.prescribedSets
                    }
                }
        }
        guard matches(original, baseline.menus), matches(candidate, proposed.menus) else {
            return .deliveryMismatch
        }
        func findings(_ output: WorkoutWeekResponse, _ plan: SubstitutionPlanningBaseline) -> [String] {
            validateWeekResponse(output, dayStart: dayStart, dayEnd: dayStart + 6,
                previousWeekDays: previousWeekDays, blueprint: plan.blueprint, expectedExerciseMenus: plan.menus)
        }
        let oldIssues = findings(original, baseline), newIssues = findings(candidate, proposed)
        let oldCounts = Dictionary(grouping: oldIssues, by: { $0 }).mapValues(\.count)
        let newCounts = Dictionary(grouping: newIssues, by: { $0 }).mapValues(\.count)
        guard newIssues.count < oldIssues.count,
              newCounts.allSatisfy({ message, count in count <= oldCounts[message, default: 0] }) else {
            return .findingsNotImproved
        }
        return nil
    }

    // Complete-plan boundary used by the bounded placement wrapper.
    // All speculative messages/receipts remain private until the entire candidate passes.
    func finalizeCoreRelocation(_ baseline: SubstitutionPlanningBaseline,
        sourceDay: Int, sourceSlot: Int, destinationDay: Int,
        trainingIntent: TrainingIntentPlan, previousWeekDays: [WorkoutDayResponse]?,
        baselineMessages: [String], baselineReceipts: [SetFundingObservation], collectFunding: Bool
    ) -> CoreRelocationFinalization {
        func retained(_ decision: CoreRelocationDecision) -> CoreRelocationFinalization {
            .init(plan: baseline, messages: baselineMessages, receipts: baselineReceipts, decision: decision)
        }
        let trial = proposeCoreRelocationTrial(baseline, sourceDay: sourceDay, sourceSlot: sourceSlot,
            destinationDay: destinationDay, trainingIntent: trainingIntent)
        guard case .candidate(let proposed) = trial else {
            if case .refused(let reason) = trial { return retained(.proposal(reason)) }
            return retained(.proposal(.invalidContext))
        }
        let week = baseline.weekNumber
        let dayStart = (week - 1) * 7 + 1
        let previous: [WorkoutDayResponse]?
        if week == 1 {
            guard previousWeekDays?.isEmpty ?? true else { return retained(.invalidPreviousWeek) }
            previous = nil
        } else {
            guard let days = previousWeekDays, days.count == 7,
                  days.map(\.dayNumber) == Array((dayStart - 7)..<dayStart),
                  days.allSatisfy({ $0.isRestDay == $0.exercises.isEmpty }) else {
                return retained(.invalidPreviousWeek)
            }
            previous = days
        }
        func firstCore(_ menus: [[PreSelectedExercise]]) -> Int? {
            menus.indices.first { day in menus[day].contains {
                proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
            } }.map { dayStart + $0 }
        }
        if let previousLast = previous?.last(where: { day in day.exercises.contains {
            proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
        } })?.dayNumber {
            // Relative nonregression only: previousLast cancels algebraically. Moving
            // the prior session cannot change this verdict. No minimum recovery gap
            // is imposed or established by preserving the unchanged plan's interval.
            guard let oldFirst = firstCore(baseline.menus), let newFirst = firstCore(proposed.menus),
                  newFirst - previousLast >= oldFirst - previousLast else { return retained(.boundarySpacing) }
        }

        var messages: [String] = []
        var receipts: [SetFundingObservation] = []
        var admission: RoleFloorAdmission = .unassessed
        let observer: (([SetFundingObservation]) -> Void)? = collectFunding ? { receipts = $0 } : nil
        let allocated = allocateWeeklySetPrescription(proposed.menus, blueprint: proposed.blueprint,
            weekNumber: week, lockedPrefixCounts: proposed.lockedPrefixCounts,
            appearancePlanningReport: { messages.append($0) }, setFundingReport: observer,
            roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
        if let refusal = verifyCoreRelocationAllocation(allocated, admission: admission, proposed: proposed) {
            return retained(refusal)
        }
        func delivered(_ menus: [[PreSelectedExercise]], _ blueprint: ProgramBlueprint) -> WorkoutWeekResponse {
            // Explicit menus bypass legacy repair and do not invoke menu planning again.
            buildProceduralWeek(weekNumber: week, dayStart: dayStart, dayEnd: dayStart + 6,
                splitType: trainingIntent.splitRecommendation, programName: "Core relocation verification",
                trainingIntent: trainingIntent, blueprint: blueprint, previousWeekDays: previous,
                exerciseMenus: menus)
        }
        let originalOutput = delivered(baseline.menus, baseline.blueprint)
        let candidateOutput = delivered(allocated, proposed.blueprint)
        if let refusal = verifyCoreRelocationDelivery(original: originalOutput, candidate: candidateOutput,
            baseline: baseline, proposed: proposed, previousWeekDays: previous) { return retained(refusal) }
        let plan = SubstitutionPlanningBaseline(menus: allocated, blueprint: proposed.blueprint,
            weekNumber: week, lockedPrefixCounts: proposed.lockedPrefixCounts,
            retainedKeysByDay: proposed.retainedKeysByDay, exerciseHistory: proposed.exerciseHistory,
            selectionFocusIntents: proposed.selectionFocusIntents, roleFloorAdmission: admission)
        return .init(plan: plan, messages: messages, receipts: receipts, decision: .adopted)
    }

    enum CoreRelocationRefusal: Equatable {
        case invalidContext, unsupportedWeek, baselineNotAdmitted, sourcePlacement, receiverCeiling, receiverSize
        case protectedSource, painExcluded, duplicateIdentity, exposureLoss, spacingChange, doseChange, orderChange
    }

    enum CoreRelocationTrial {
        case refused(CoreRelocationRefusal)
        case candidate(SubstitutionPlanningBaseline)
    }

    // Non-adopting pilot: a candidate still needs independent allocation, delivery and
    // validation. The six-exercise receiver ceiling is the owner's explicit trial limit.
    func proposeCoreRelocationTrial(_ baseline: SubstitutionPlanningBaseline,
        sourceDay: Int, sourceSlot: Int, destinationDay: Int,
        trainingIntent: TrainingIntentPlan) -> CoreRelocationTrial {
        let menus = baseline.menus, blueprint = baseline.blueprint
        guard menus.count == 7, blueprint.dayPlans.count == 7,
              baseline.lockedPrefixCounts.count == 7, baseline.retainedKeysByDay.count == 7,
              baseline.selectionFocusIntents.count == 7,
              menus.indices.allSatisfy({ day in
                  baseline.lockedPrefixCounts[day] >= 0 && baseline.lockedPrefixCounts[day] <= menus[day].count
                      && blueprint.dayPlans[day].dayIndex == day + 1
                      && (blueprint.dayPlans[day].isRestDay ? menus[day].isEmpty : !menus[day].isEmpty)
              }), menus.indices.contains(sourceDay), menus.indices.contains(destinationDay),
              sourceDay != destinationDay, menus[sourceDay].indices.contains(sourceSlot) else {
            return .refused(.invalidContext)
        }
        guard (1...3).contains(baseline.weekNumber) else { return .refused(.unsupportedWeek) }
        guard baseline.roleFloorAdmission == .admitted else { return .refused(.baselineNotAdmitted) }
        let source = blueprint.dayPlans[sourceDay], receiver = blueprint.dayPlans[destinationDay]
        let moved = menus[sourceDay][sourceSlot]
        guard !source.isRestDay, !receiver.isRestDay,
              canonicalTrainingStyle(source.style) == "Lower",
              canonicalTrainingStyle(receiver.style) == "Pull",
              menus[sourceDay].count == 7, sourceSlot == menus[sourceDay].count - 1,
              moved.role == .core,
              proceduralExerciseRole(for: moved.exerciseName, muscleTarget: moved.muscleTarget) == .core,
              isDirectCoreHypertrophyMovement(exerciseName: moved.exerciseName,
                  muscleTarget: moved.muscleTarget, reps: proceduralRepRange(for: baseline.weekNumber,
                      exerciseName: moved.exerciseName, muscleTarget: moved.muscleTarget)) else { return .refused(.sourcePlacement) }
        guard menus[destinationDay].count < 6 else { return .refused(.receiverCeiling) }
        guard menus[destinationDay].count == 5 else { return .refused(.receiverSize) }
        let key = ExerciseWeightEntry.canonicalLookupKey(moved.exerciseName)
        guard !isProtectedAppearance(role: moved.role, slot: sourceSlot, style: source.style,
                  lockedPrefixCount: baseline.lockedPrefixCounts[sourceDay]),
              !baseline.retainedKeysByDay[sourceDay].contains(key) else { return .refused(.protectedSource) }
        guard !(baseline.exerciseHistory?.painExercises.contains(key) ?? false) else { return .refused(.painExcluded) }
        guard !menus[destinationDay].contains(where: {
            ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) == key
        }) else { return .refused(.duplicateIdentity) }
        var candidate = menus
        candidate[sourceDay].removeLast()
        candidate[destinationDay].append(moved)

        for group in majorMuscleGroups {
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            func exposureCount(_ plan: [[PreSelectedExercise]]) -> Int {
                plan.filter { day in day.contains {
                    exerciseDirectlyTargets(groupAliases: aliases, exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget)
                } }.count
            }
            guard exposureCount(candidate) >= exposureCount(menus) else { return .refused(.exposureLoss) }
        }
        func coreGaps(_ plan: [[PreSelectedExercise]]) -> [Int] {
            let days = plan.indices.filter { day in plan[day].contains {
                proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
            } }
            guard !days.isEmpty else { return [] }
            return days.indices.map { index in
                index + 1 < days.count ? days[index + 1] - days[index] : 7 + days[0] - days[index]
            }.sorted()
        }
        // Conservative experiment screen, not a scientific spacing law.
        guard coreGaps(candidate) == coreGaps(menus) else { return .refused(.spacingChange) }
        var days = blueprint.dayPlans
        days[destinationDay] = .init(dayIndex: receiver.dayIndex, style: receiver.style,
            focusArea: receiver.focusArea,
            supportAreas: receiver.supportAreas.contains("Core/Abs") ? receiver.supportAreas : receiver.supportAreas + ["Core/Abs"],
            targetFatigueCap: receiver.targetFatigueCap, targetSessionMinutes: receiver.targetSessionMinutes,
            targetPrioritySlots: receiver.targetPrioritySlots, emphasisPatterns: receiver.emphasisPatterns,
            isRestDay: receiver.isRestDay)
        let candidateBlueprint = ProgramBlueprint(evidenceVersion: blueprint.evidenceVersion,
            splitRecommendation: blueprint.splitRecommendation, weeklyTrainingDays: blueprint.weeklyTrainingDays,
            priorityAllocations: blueprint.priorityAllocations, dayPlans: days,
            topLeverageChange: blueprint.topLeverageChange, posturalFocus: blueprint.posturalFocus,
            injuryRiskFocus: blueprint.injuryRiskFocus, programmingNotes: blueprint.programmingNotes,
            calibration: blueprint.calibration)
        guard case .dosePreserved = compareAllocatedDoseOnly(candidate, baseline: menus,
            blueprint: candidateBlueprint, weekNumber: baseline.weekNumber) else { return .refused(.doseChange) }
        func signature(_ plan: [[PreSelectedExercise]]) -> [[String]] {
            plan.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
        }
        let ordered = reorderedMenusForSessionFlow(candidate, blueprint: candidateBlueprint,
            trainingIntent: trainingIntent, lockedPrefixCounts: baseline.lockedPrefixCounts)
        guard signature(ordered) == signature(candidate) else { return .refused(.orderChange) }
        return .candidate(.init(menus: candidate, blueprint: candidateBlueprint, weekNumber: baseline.weekNumber,
            lockedPrefixCounts: baseline.lockedPrefixCounts, retainedKeysByDay: baseline.retainedKeysByDay,
            exerciseHistory: baseline.exerciseHistory, selectionFocusIntents: baseline.selectionFocusIntents,
            // A changed placement has not passed a fresh allocation yet.
            roleFloorAdmission: .unassessed))
    }

    enum PressdownAdoptionDecision: Equatable {
        case consolidationRefused(String)
        case consolidated(day: Int, removed: String)
        case baselineNotAdmitted(RoleFloorAdmission)
        case search(PressdownSearchOutcome)
        case orderChange
        case finalNotAdmitted(RoleFloorAdmission)
        case finalVerification(PressdownTrialDecision)
        case adopted(day: Int, excessBefore: Int, excessAfter: Int)
    }

    struct PressdownFinalization {
        let plan: SubstitutionPlanningBaseline
        let messages: [String]
        let receipts: [SetFundingObservation]
        let decision: PressdownAdoptionDecision
    }

    /// The candidate must survive normal ordering and a fresh allocation without changing
    /// any original dose or another identity. Admission only proves role-floor reservation.
    func verifyFinalPressdownReplacement(_ candidate: [[PreSelectedExercise]],
        admission: RoleFloorAdmission, baseline: SubstitutionPlanningBaseline,
        trainingIntent: TrainingIntentPlan) -> PressdownAdoptionDecision {
        guard baseline.roleFloorAdmission == .admitted else {
            return .baselineNotAdmitted(baseline.roleFloorAdmission)
        }
        guard admission == .admitted else { return .finalNotAdmitted(admission) }
        let verification = evaluatePressdownSubstitutionTrial(candidate, plannedBaseline: baseline)
        guard case .qualified(let day, let before, let after) = verification else {
            return .finalVerification(verification)
        }
        let ordered = reorderedMenusForSessionFlow(candidate, blueprint: baseline.blueprint,
            trainingIntent: trainingIntent, lockedPrefixCounts: baseline.lockedPrefixCounts)
        guard zip(candidate, ordered).allSatisfy({ original, arranged in
            original.map { "\($0.exerciseName)#\($0.muscleTarget)" }
                == arranged.map { "\($0.exerciseName)#\($0.muscleTarget)" }
        }) else { return .orderChange }
        return .adopted(day: day, excessBefore: before, excessAfter: after)
    }

    /// Optional quality improvement only, never a pain-driven replacement fallback.
    /// At most one proposal is reallocated. A failed final check leaves alternatives
    /// unassessed; it must not be described as exhausting the candidate search.
    func finalizePressdownReduction(_ baseline: SubstitutionPlanningBaseline,
        trainingIntent: TrainingIntentPlan, baselineMessages: [String],
        baselineReceipts: [SetFundingObservation], collectFunding: Bool) -> PressdownFinalization {
        func retained(_ decision: PressdownAdoptionDecision) -> PressdownFinalization {
            .init(plan: baseline, messages: baselineMessages, receipts: baselineReceipts, decision: decision)
        }
        guard baseline.roleFloorAdmission == .admitted else {
            return retained(.baselineNotAdmitted(baseline.roleFloorAdmission))
        }
        let search = searchPressdownReduction(in: baseline)
        // After the existing fixed-slot search finds no acceptable replacement, try
        // one removal. No fallback search follows a failed fresh consolidation allocation.
        if search.outcome == .noQualifiedCandidate, baseline.weekNumber == 1 {
            for day in baseline.menus.indices where baseline.menus[day].count == 6
                && excessPressdownsByDay(in: baseline.menus)[day] > 0 {
                if let donor = baseline.menus[day].indices.reversed().first(where: { slot in
                    let item = baseline.menus[day][slot]
                    return pressdownRedundancyFamily.contains(item.exerciseName)
                        && !isProtectedAppearance(role: item.role, slot: slot,
                            style: baseline.blueprint.dayPlans[day].style, lockedPrefixCount: baseline.lockedPrefixCounts[day])
                        && !baseline.retainedKeysByDay[day].contains(ExerciseWeightEntry.canonicalLookupKey(item.exerciseName))
                }) {
                    return finalizeSameRegionPressdownConsolidation(baseline, day: day, donor: donor,
                        trainingIntent: trainingIntent, baselineMessages: baselineMessages,
                        baselineReceipts: baselineReceipts, collectFunding: collectFunding)
                }
            }
        }
        guard case .proposed = search.outcome else { return retained(.search(search.outcome)) }
        let preliminary = verifyFinalPressdownReplacement(search.proposedMenus, admission: .admitted,
            baseline: baseline, trainingIntent: trainingIntent)
        guard case .adopted = preliminary else { return retained(preliminary) }

        var messages: [String] = []
        var receipts: [SetFundingObservation] = []
        var admission: RoleFloorAdmission = .unassessed
        let observer: (([SetFundingObservation]) -> Void)? = collectFunding ? { receipts = $0 } : nil
        let allocated = allocateWeeklySetPrescription(search.proposedMenus, blueprint: baseline.blueprint,
            weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
            appearancePlanningReport: { messages.append($0) }, setFundingReport: observer,
            roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
        let decision = verifyFinalPressdownReplacement(allocated, admission: admission,
            baseline: baseline, trainingIntent: trainingIntent)
        guard case .adopted = decision else { return retained(decision) }
        let plan = SubstitutionPlanningBaseline(menus: allocated, blueprint: baseline.blueprint,
            weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
            retainedKeysByDay: baseline.retainedKeysByDay, exerciseHistory: baseline.exerciseHistory,
            selectionFocusIntents: baseline.selectionFocusIntents, roleFloorAdmission: admission)
        return .init(plan: plan, messages: messages, receipts: receipts, decision: decision)
    }

    private var pressdownRedundancyFamily: Set<String> {
        ["Rope Triceps Pressdown", "Cable Triceps Pressdown", "V-Bar Pressdown"]
    }

    enum PressdownSearchOutcome: Equatable {
        case invalidContext, unsupportedWeek, noRedundancy, noQualifiedCandidate, searchLimit
        case proposed(day: Int, slot: Int, replacement: String)
    }

    struct PressdownSearchAttempt: Equatable {
        let day: Int
        let slot: Int
        let replacement: String
        let decision: PressdownTrialDecision
    }

    struct PressdownSearchResult {
        let proposedMenus: [[PreSelectedExercise]]
        let outcome: PressdownSearchOutcome
        let attempts: [PressdownSearchAttempt]
    }

    /// Bounded, deterministic, single-replacement proposal. First qualified alternative
    /// wins in day order, reverse redundant-slot order, then the existing ordered/history
    /// filtered style catalog. Exhaustion is NOT proof that no possible plan can fit.
    func searchPressdownReduction(in baseline: SubstitutionPlanningBaseline,
                                 maximumTrials: Int = 64) -> PressdownSearchResult {
        var attempts: [PressdownSearchAttempt] = []
        func unchanged(_ outcome: PressdownSearchOutcome) -> PressdownSearchResult {
            .init(proposedMenus: baseline.menus, outcome: outcome, attempts: attempts)
        }
        guard baseline.menus.count == baseline.blueprint.dayPlans.count,
              baseline.lockedPrefixCounts.count == baseline.menus.count,
              baseline.retainedKeysByDay.count == baseline.menus.count,
              baseline.selectionFocusIntents.count == baseline.menus.count,
              baseline.menus.indices.allSatisfy({ baseline.lockedPrefixCounts[$0] >= 0
                  && baseline.lockedPrefixCounts[$0] <= baseline.menus[$0].count }) else {
            return unchanged(.invalidContext)
        }
        guard (1..<MesocyclePhase.deloadWeek).contains(baseline.weekNumber) else { return unchanged(.unsupportedWeek) }
        let excess = excessPressdownsByDay(in: baseline.menus)
        guard excess.contains(where: { $0 > 0 }) else { return unchanged(.noRedundancy) }
        let history = baseline.exerciseHistory
        let family = pressdownRedundancyFamily
        for day in baseline.menus.indices where excess[day] > 0 {
            let plan = baseline.blueprint.dayPlans[day]
            let selectionContext = ExerciseSelectionContext(calibration: baseline.blueprint.calibration,
                injuryRiskFocus: baseline.blueprint.injuryRiskFocus, style: plan.style)
            let catalog = applyHistoryFilters(orderedExerciseCatalog(for: plan.style,
                focusIntent: baseline.selectionFocusIntents[day], selectionContext: selectionContext),
                avoidedExercises: history?.painExercises ?? [],
                deprioritizedExercises: history?.equipmentSkipExercises ?? [],
                catalogOffset: history.map { variationCatalogOffset(for: $0) } ?? 0,
                weekNumber: baseline.weekNumber, priorMesocycleExercises: history?.priorMesocycleExercises ?? [])
            for slot in baseline.menus[day].indices.reversed() where family.contains(baseline.menus[day][slot].exerciseName) {
                let old = baseline.menus[day][slot]
                let oldRole = proceduralExerciseRole(for: old.exerciseName, muscleTarget: old.muscleTarget)
                // These exclusions cannot be changed by choosing a different replacement.
                // Do not consume a candidate trial on a protected or retained appearance.
                guard !isProtectedAppearance(role: old.role, slot: slot, style: plan.style,
                    lockedPrefixCount: baseline.lockedPrefixCounts[day]),
                    !isProtectedAppearance(role: oldRole, slot: slot, style: plan.style,
                    lockedPrefixCount: baseline.lockedPrefixCounts[day]),
                    !baseline.retainedKeysByDay[day].contains(ExerciseWeightEntry.canonicalLookupKey(old.exerciseName))
                else { continue }
                for replacement in catalog where replacement.target == old.muscleTarget && !family.contains(replacement.name) {
                    guard attempts.count < maximumTrials else { return unchanged(.searchLimit) }
                    var candidate = baseline.menus
                    candidate[day][slot] = .init(exerciseName: replacement.name, muscleTarget: replacement.target,
                        movementPattern: exerciseMetadata(forExerciseName: replacement.name,
                            muscleTarget: replacement.target).movementPattern,
                        role: proceduralExerciseRole(for: replacement.name, muscleTarget: replacement.target),
                        prescribedSets: old.prescribedSets)
                    let decision = evaluatePressdownSubstitutionTrial(candidate, plannedBaseline: baseline)
                    attempts.append(.init(day: day, slot: slot, replacement: replacement.name, decision: decision))
                    if case .qualified = decision {
                        return .init(proposedMenus: candidate,
                            outcome: .proposed(day: day, slot: slot, replacement: replacement.name), attempts: attempts)
                    }
                }
            }
        }
        return unchanged(.noQualifiedCandidate)
    }

    enum PressdownTrialDecision: Equatable {
        case rejected(PressdownTrialFailure)
        // A measured trial result, not authorization to replace the delivered menu.
        case qualified(day: Int, excessBefore: Int, excessAfter: Int)
    }

    enum PressdownTrialFailure: Equatable {
        case unsupportedWeek
        case eligibility(SubstitutionPreflightFailure)
        case dose(AllocatedPlanDoseFailure)
        case noRedundancyImprovement
    }

    /// Narrow catalog-identity objective, not a universal movement-equivalence rule.
    /// Keep naming/history normalization unchanged (INC-2); do not use this to reject
    /// early catalog candidates (INC-9). Tests pin exact members and unknown variants.
    func excessPressdownsByDay(in menus: [[PreSelectedExercise]]) -> [Int] {
        let family = pressdownRedundancyFamily
        return menus.map { day in max(0, day.filter { family.contains($0.exerciseName) }.count - 1) }
    }

    /// Optional quality trial only. No mutation, candidate search, live adoption or
    /// pain-driven replacement fallback is performed here. Returns the first refusal.
    func evaluatePressdownSubstitutionTrial(
        _ candidate: [[PreSelectedExercise]], plannedBaseline: SubstitutionPlanningBaseline
    ) -> PressdownTrialDecision {
        guard (1..<MesocyclePhase.deloadWeek).contains(plannedBaseline.weekNumber) else { return .rejected(.unsupportedWeek) }
        switch preflightFixedDoseSubstitution(candidate, plannedBaseline: plannedBaseline) {
        case .rejected(let failure): return .rejected(.eligibility(failure))
        case .structurallyEligible: break
        }
        switch compareAllocatedDoseOnly(candidate, baseline: plannedBaseline.menus,
            blueprint: plannedBaseline.blueprint, weekNumber: plannedBaseline.weekNumber) {
        case .rejected(let failure): return .rejected(.dose(failure))
        case .dosePreserved: break
        }
        let before = excessPressdownsByDay(in: plannedBaseline.menus)
        let after = excessPressdownsByDay(in: candidate)
        let improvedDays = before.indices.filter { after[$0] < before[$0] }
        guard before.indices.allSatisfy({ after[$0] <= before[$0] }),
              improvedDays.count == 1, let day = improvedDays.first else {
            return .rejected(.noRedundancyImprovement)
        }
        return .qualified(day: day, excessBefore: before[day], excessAfter: after[day])
    }

    struct SubstitutionPlanningBaseline {
        let menus: [[PreSelectedExercise]]
        let blueprint: ProgramBlueprint
        let weekNumber: Int
        let lockedPrefixCounts: [Int]
        // Identity protection is separate from ordering: focus days can retain work
        // while intentionally having no locked prefix. Removed identities are inert.
        let retainedKeysByDay: [Set<String>]
        let exerciseHistory: ExerciseHistoryContext?
        let selectionFocusIntents: [MusclePriorityIntent?]
        var roleFloorAdmission: RoleFloorAdmission = .unassessed
    }

    func preflightFixedDoseSubstitution(
        _ candidate: [[PreSelectedExercise]], plannedBaseline: SubstitutionPlanningBaseline
    ) -> SubstitutionPreflight {
        let baseline = plannedBaseline
        let pain = baseline.exerciseHistory.map { SubstitutionPainExclusions(history: $0) }
            ?? SubstitutionPainExclusions(exerciseNames: [])
        let result = preflightFixedDoseSubstitution(candidate, baseline: baseline.menus,
            blueprint: baseline.blueprint, lockedPrefixCounts: baseline.lockedPrefixCounts,
            painExclusions: pain)
        guard result == .structurallyEligible else { return result }
        guard baseline.retainedKeysByDay.count == baseline.menus.count,
              baseline.selectionFocusIntents.count == baseline.menus.count else { return .rejected(.lockContext) }
        for day in baseline.menus.indices {
            for slot in baseline.menus[day].indices {
                let old = baseline.menus[day][slot]
                if old.exerciseName != candidate[day][slot].exerciseName,
                   baseline.retainedKeysByDay[day].contains(ExerciseWeightEntry.canonicalLookupKey(old.exerciseName)) {
                    return .rejected(.retainedSlot)
                }
                if old.exerciseName != candidate[day][slot].exerciseName {
                    let new = candidate[day][slot]
                    let skipped = baseline.exerciseHistory?.equipmentSkipExercises ?? []
                    // Relative preference, not an equipment ban: keeping an already-skipped
                    // option or moving between two skipped options is not rejected here.
                    if skipped.contains(ExerciseWeightEntry.canonicalLookupKey(new.exerciseName)),
                       !skipped.contains(ExerciseWeightEntry.canonicalLookupKey(old.exerciseName)) {
                        return .rejected(.equipmentPreference)
                    }
                    // orderedExerciseCatalog scores only focus days, and compares focus rank
                    // BEFORE score. Preserve that order rather than invent a universal score gate.
                    if let focus = baseline.selectionFocusIntents[day] {
                        let oldRank = focusOrderingPriority(exerciseName: old.exerciseName,
                            muscleTarget: old.muscleTarget, focusArea: focus.area)
                        let newRank = focusOrderingPriority(exerciseName: new.exerciseName,
                            muscleTarget: new.muscleTarget, focusArea: focus.area)
                        let context = ExerciseSelectionContext(calibration: baseline.blueprint.calibration,
                            injuryRiskFocus: baseline.blueprint.injuryRiskFocus,
                            style: baseline.blueprint.dayPlans[day].style)
                        // The structural preflight already refuses a focus-rank downgrade.
                        // Score is only the tie-breaker; never veto a rank improvement by score.
                        if newRank == oldRank && exerciseSelectionScore(
                            exerciseName: new.exerciseName, muscleTarget: new.muscleTarget,
                            focusIntent: focus, selectionContext: context) < exerciseSelectionScore(
                            exerciseName: old.exerciseName, muscleTarget: old.muscleTarget,
                            focusIntent: focus, selectionContext: context) {
                            return .rejected(.selectionPreference)
                        }
                    }
                }
            }
        }
        // Full-candidate checks deliberately reject inherited violations too. A local
        // insertion check or unchanged warning count cannot establish complete-plan fit.
        // This eligibility gate supports optional quality adoption. It must not be used to keep
        // painful/unavailable work when a future safety-replacement request cannot pass it.
        for day in candidate.indices {
            let plan = baseline.blueprint.dayPlans[day]
            guard let focus = plan.focusArea else { continue }
            let primeCount = candidate[day].filter {
                focusStimulusKind(exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget,
                    focusArea: focus) == .prime
            }.count
            if primeCount > focusPrimeSlotCap(targetPrioritySlots: plan.targetPrioritySlots) {
                return .rejected(.focusPrimeCap)
            }
        }
        guard weeklyVariationViolations(in: candidate, blueprint: baseline.blueprint).isEmpty else {
            return .rejected(.weeklyVariation)
        }
        return result
    }

    struct SubstitutionPainExclusions {
        fileprivate let canonicalKeys: Set<String>

        init(exerciseNames: [String]) {
            canonicalKeys = Set(exerciseNames.map(ExerciseWeightEntry.canonicalLookupKey))
        }

        // The existing history producer already supplies canonical keys. Do not stem
        // them a second time or change the persisted naming contract here.
        init(history: ExerciseHistoryContext) {
            canonicalKeys = history.painExercises
        }
    }

    enum SubstitutionPreflight: Equatable {
        case rejected(SubstitutionPreflightFailure)
        case structurallyEligible
    }

    enum SubstitutionPreflightFailure: Equatable {
        case shape, lockContext, restDay, changeScope, protectedSlot, retainedSlot
        case catalog, metadata, painHistory, reportedShoulderConcern
        case duplicate, patternCap, coverage, focusQuality
        case equipmentPreference, selectionPreference, focusPrimeCap, weeklyVariation
    }

    /// Fixed-dose, single-slot preflight, NOT permission to adopt a replacement.
    /// SubstitutionPreflightTests pin the guards. Callers still need whole-plan dose
    /// comparison, an improvement objective and broader injury/selection review.
    /// Locks are explicit: missing context is not silently interpreted as no locks.
    func preflightFixedDoseSubstitution(
        _ candidate: [[PreSelectedExercise]], baseline: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint, lockedPrefixCounts: [Int],
        painExclusions: SubstitutionPainExclusions
    ) -> SubstitutionPreflight {
        guard candidate.count == baseline.count, baseline.count == blueprint.dayPlans.count,
              zip(candidate, baseline).allSatisfy({ pair in pair.0.count == pair.1.count }) else {
            return .rejected(.shape)
        }
        guard lockedPrefixCounts.count == baseline.count,
              baseline.indices.allSatisfy({ lockedPrefixCounts[$0] >= 0 && lockedPrefixCounts[$0] <= baseline[$0].count }) else {
            return .rejected(.lockContext)
        }
        var changed: [(Int, Int)] = []
        for day in baseline.indices {
            if blueprint.dayPlans[day].isRestDay && !baseline[day].isEmpty { return .rejected(.restDay) }
            for slot in baseline[day].indices {
                let old = baseline[day][slot], new = candidate[day][slot]
                guard old.prescribedSets == new.prescribedSets else { return .rejected(.changeScope) }
                if old.exerciseName != new.exerciseName || old.muscleTarget != new.muscleTarget
                    || old.role != new.role || old.movementPattern != new.movementPattern {
                    changed.append((day, slot))
                }
            }
        }
        guard changed.count == 1 else { return .rejected(.changeScope) }
        let (day, slot) = changed[0]
        let old = baseline[day][slot], new = candidate[day][slot]
        let plan = blueprint.dayPlans[day]
        let oldRole = proceduralExerciseRole(for: old.exerciseName, muscleTarget: old.muscleTarget)
        guard !isProtectedAppearance(role: old.role, slot: slot, style: plan.style, lockedPrefixCount: lockedPrefixCounts[day]),
              !isProtectedAppearance(role: oldRole, slot: slot, style: plan.style, lockedPrefixCount: lockedPrefixCounts[day]) else {
            return .rejected(.protectedSlot)
        }
        // Deliberately narrow pool: exact entries in this day's existing style catalog.
        // Rescue and focus-catalog alternatives require their own selection context later.
        guard exerciseCatalog(for: plan.style).contains(where: { $0.name == new.exerciseName && $0.target == new.muscleTarget }) else {
            return .rejected(.catalog)
        }
        let metadata = exerciseMetadata(forExerciseName: new.exerciseName, muscleTarget: new.muscleTarget)
        let newRole = proceduralExerciseRole(for: new.exerciseName, muscleTarget: new.muscleTarget)
        guard new.movementPattern == metadata.movementPattern, new.role == newRole, newRole == oldRole,
              new.muscleTarget == old.muscleTarget else { return .rejected(.metadata) }
        let key = ExerciseWeightEntry.canonicalLookupKey(new.exerciseName)
        guard !painExclusions.canonicalKeys.contains(key) else { return .rejected(.painHistory) }
        guard !reportedShoulderPainImplicates(exerciseName: new.exerciseName, muscleTarget: new.muscleTarget,
            injuryRiskFocus: blueprint.injuryRiskFocus) else { return .rejected(.reportedShoulderConcern) }
        let remaining = baseline[day].enumerated().filter { $0.offset != slot }.map(\.element)
        guard !remaining.contains(where: { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) == key }) else {
            return .rejected(.duplicate)
        }
        guard dayPatternCapAllows(candidateName: new.exerciseName, candidateTarget: new.muscleTarget,
            in: remaining.map { ($0.exerciseName, $0.muscleTarget) }) else { return .rejected(.patternCap) }
        // Conservative preflight: retain each pattern on the changed day, not merely
        // elsewhere in the week. This is not a claim that every such pattern is essential.
        let oldPatterns = Set(baseline[day].map(\.movementPattern))
        let newPatterns = Set(candidate[day].map(\.movementPattern))
        guard oldPatterns.isSubset(of: newPatterns) else { return .rejected(.coverage) }
        let oldAccounting = weeklyExerciseAccounting(for: baseline, blueprint: blueprint)
        let newAccounting = weeklyExerciseAccounting(for: candidate, blueprint: blueprint)
        let oldCost = oldAccounting.exercises[day][slot], newCost = newAccounting.exercises[day][slot]
        guard oldCost.directlyTargetsGroup.indices.allSatisfy({ !oldCost.directlyTargetsGroup[$0] || newCost.directlyTargetsGroup[$0] }) else {
            return .rejected(.coverage)
        }
        guard oldCost.qualityScore.indices.allSatisfy({ newCost.qualityScore[$0] >= oldCost.qualityScore[$0] }) else {
            return .rejected(.focusQuality)
        }
        if let focus = plan.focusArea {
            guard focusOrderingPriority(exerciseName: new.exerciseName, muscleTarget: new.muscleTarget, focusArea: focus)
                <= focusOrderingPriority(exerciseName: old.exerciseName, muscleTarget: old.muscleTarget, focusArea: focus) else {
                return .rejected(.focusQuality)
            }
        }
        return .structurallyEligible
    }
}
