import Foundation

extension ClaudeService {
    /// One fresh allocation at most. Failed experiments never replace baseline
    /// messages/receipts, and never trigger a second reallocation search.
    func finalizeFirstAccessoryRelocation(_ baseline: SubstitutionPlanningBaseline,
        trainingIntent: TrainingIntentPlan, previousWeekDays: [WorkoutDayResponse]?,
        baselineMessages: [String], baselineReceipts: [SetFundingObservation], collectFunding: Bool
    ) -> SessionCapacityFinalization {
        func retained(_ reason: String) -> SessionCapacityFinalization {
            .init(plan: baseline, messages: baselineMessages, receipts: baselineReceipts, decision: reason)
        }
        guard baseline.menus.count == 7, baseline.roleFloorAdmission == .admitted,
              (1...3).contains(baseline.weekNumber),
              baseline.menus.filter({ $0.count > 6 }).count == 1,
              let source = baseline.menus.firstIndex(where: { $0.count == 7 }) else {
            return retained("no eligible accessory placement")
        }
        for slot in baseline.menus[source].indices.reversed() {
            for receiver in baseline.menus.indices where baseline.menus[receiver].count == 5 {
                guard case .candidate(let proposed) = proposeAccessoryRelocation(baseline,
                    source: source, slot: slot, receiver: receiver, trainingIntent: trainingIntent,
                    previousWeekDays: previousWeekDays) else { continue }
                var admission: RoleFloorAdmission = .unassessed
                var messages: [String] = []
                var receipts: [SetFundingObservation] = []
                let observer: (([SetFundingObservation]) -> Void)? = collectFunding ? { receipts = $0 } : nil
                let allocated = allocateWeeklySetPrescription(proposed.menus, blueprint: proposed.blueprint,
                    weekNumber: proposed.weekNumber, lockedPrefixCounts: proposed.lockedPrefixCounts,
                    appearancePlanningReport: { messages.append($0) }, setFundingReport: observer,
                    roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
                if let reason = verifyAccessoryRelocationAllocation(allocated, admission: admission, proposed: proposed) {
                    return retained(reason)
                }
                let start = (baseline.weekNumber - 1) * 7 + 1
                func delivered(_ menus: [[PreSelectedExercise]]) -> WorkoutWeekResponse {
                    buildProceduralWeek(weekNumber: baseline.weekNumber, dayStart: start, dayEnd: start + 6,
                        splitType: trainingIntent.splitRecommendation, programName: "Accessory placement verification",
                        trainingIntent: trainingIntent, blueprint: baseline.blueprint,
                        previousWeekDays: previousWeekDays, exerciseMenus: menus)
                }
                if let reason = verifyAccessoryRelocationDelivery(original: delivered(baseline.menus),
                    candidate: delivered(allocated), baseline: baseline, proposed: proposed,
                    previousWeekDays: previousWeekDays) { return retained(reason) }
                let plan = SubstitutionPlanningBaseline(menus: allocated, blueprint: proposed.blueprint,
                    weekNumber: proposed.weekNumber, lockedPrefixCounts: proposed.lockedPrefixCounts,
                    retainedKeysByDay: proposed.retainedKeysByDay, exerciseHistory: proposed.exerciseHistory,
                    selectionFocusIntents: proposed.selectionFocusIntents, roleFloorAdmission: admission)
                return .init(plan: plan, messages: messages, receipts: receipts,
                    decision: "adopted six-slot accessory relocation with unchanged identities and sets")
            }
        }
        return retained("no eligible accessory placement")
    }

    enum AccessoryRelocationTrial {
        case refused(String)
        case candidate(SubstitutionPlanningBaseline)
    }

    /// Bounded experiment: split existing one-day nonpriority accessory work across
    /// two nonadjacent days, without changing any identity or prescription. Calendar
    /// spacing is an engineering screen, not a recovery or medical-safety guarantee.
    func proposeAccessoryRelocation(_ baseline: SubstitutionPlanningBaseline,
        source: Int, slot: Int, receiver: Int, trainingIntent: TrainingIntentPlan,
        previousWeekDays: [WorkoutDayResponse]?) -> AccessoryRelocationTrial {
        let menus = baseline.menus, blueprint = baseline.blueprint
        guard (1...3).contains(baseline.weekNumber), baseline.roleFloorAdmission == .admitted,
              menus.count == 7, blueprint.dayPlans.count == 7,
              baseline.lockedPrefixCounts.count == 7, baseline.retainedKeysByDay.count == 7,
              baseline.selectionFocusIntents.count == 7,
              blueprint.dayPlans.filter({ !$0.isRestDay }).count == blueprint.weeklyTrainingDays,
              menus.indices.contains(source), menus.indices.contains(receiver), source != receiver,
              menus[source].indices.contains(slot),
              menus.indices.allSatisfy({ day in
                  blueprint.dayPlans[day].dayIndex == day + 1
                      && baseline.lockedPrefixCounts[day] >= 0
                      && baseline.lockedPrefixCounts[day] <= menus[day].count
                      && (blueprint.dayPlans[day].isRestDay ? menus[day].isEmpty
                          : (5...7).contains(menus[day].count))
                      && menus[day].allSatisfy { $0.prescribedSets > 0 }
              }), menus.filter({ $0.count > 6 }).count == 1,
              menus[source].count == 7, menus[receiver].count == 5 else {
            return .refused("outside single seven-to-six placement boundary")
        }
        let start = (baseline.weekNumber - 1) * 7 + 1
        if baseline.weekNumber == 1 {
            guard previousWeekDays?.isEmpty ?? true else { return .refused("invalid previous week") }
        } else {
            guard let previous = previousWeekDays, previous.count == 7,
                  previous.map(\.dayNumber) == Array((start - 7)..<start),
                  previous.allSatisfy({ $0.isRestDay == $0.exercises.isEmpty
                      && $0.exercises.allSatisfy { $0.sets > 0 } }) else {
                return .refused("invalid previous week")
            }
        }
        let moved = menus[source][slot]
        let key = ExerciseWeightEntry.canonicalLookupKey(moved.exerciseName)
        let actualRole = proceduralExerciseRole(for: moved.exerciseName, muscleTarget: moved.muscleTarget)
        guard moved.role == .accessory, actualRole == .accessory,
              !isProtectedAppearance(role: moved.role, slot: slot, style: blueprint.dayPlans[source].style,
                  lockedPrefixCount: baseline.lockedPrefixCounts[source]),
              !baseline.retainedKeysByDay[source].contains(key) else {
            return .refused("protected source")
        }
        guard !(baseline.exerciseHistory?.painExercises.contains(key) ?? false),
              !(baseline.exerciseHistory?.equipmentSkipExercises.contains(key) ?? false),
              !reportedShoulderPainImplicates(exerciseName: moved.exerciseName, muscleTarget: moved.muscleTarget,
                  injuryRiskFocus: blueprint.injuryRiskFocus),
              [ReportedJointStressArea.elbow, .lowerBack, .knee].allSatisfy({ joint in
                  !reportedJointPainImplicates(joint, exerciseName: moved.exerciseName,
                      muscleTarget: moved.muscleTarget, injuryRiskFocus: blueprint.injuryRiskFocus)
              }) else { return .refused("history or reported symptoms exclude relocation") }
        let cost = weeklyExerciseAccounting(for: menus, blueprint: blueprint).exercises[source][slot]
        guard cost.unitDirect.allSatisfy({ $0 == 0 }), cost.unitWeighted.allSatisfy({ $0 == 0 }) else {
            return .refused("priority work is not movable")
        }
        guard exerciseCatalog(for: blueprint.dayPlans[receiver].style).contains(where: {
            $0.name == moved.exerciseName && $0.target == moved.muscleTarget
        }) else { return .refused("absent from receiver catalog") }
        let response = WorkoutExerciseResponse(exerciseName: moved.exerciseName, sets: moved.prescribedSets,
            reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: moved.muscleTarget)
        guard exerciseMatchesDayStyle(response, style: blueprint.dayPlans[receiver].style),
              !menus[receiver].contains(where: { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) == key }),
              dayPatternCapAllows(candidateName: moved.exerciseName, candidateTarget: moved.muscleTarget,
                  in: menus[receiver].map { (name: $0.exerciseName, target: $0.muscleTarget) }) else {
            return .refused("receiver style, duplicate or pattern conflict")
        }
        var proposed = menus
        proposed[source].remove(at: slot)
        proposed[receiver].append(moved)
        let regions = Set(exerciseMetadata(forExerciseName: moved.exerciseName, muscleTarget: moved.muscleTarget)
            .primaryAreas.map(normalizedPriorityText))
        guard !regions.isEmpty else { return .refused("unknown primary region") }
        for region in regions {
            func exposureDays(_ value: [[PreSelectedExercise]]) -> [Int] {
                value.indices.filter { day in
                    value[day].reduce(0) { total, item in
                        let primary = exerciseMetadata(forExerciseName: item.exerciseName, muscleTarget: item.muscleTarget)
                            .primaryAreas.map(normalizedPriorityText)
                        return total + (primary.contains(region) ? item.prescribedSets : 0)
                    } >= 2
                }
            }
            let oldDays = exposureDays(menus), newDays = exposureDays(proposed)
            // Do not reduce, slide or generally rearrange frequency. Only 1 -> 2;
            // the original exposure day remains, with at least two direct sets.
            guard oldDays == [source], newDays.count == 2, newDays.contains(source),
                  newDays[1] - newDays[0] >= 2,
                  7 + newDays[0] - newDays[1] >= 2 else {
                return .refused("outside bounded one-to-two regional frequency trial")
            }
            if let last = previousWeekDays?.last(where: { day in day.exercises.contains { item in
                exerciseMetadata(for: item).primaryAreas.map(normalizedPriorityText).contains(region)
                    && item.sets > 0
            } })?.dayNumber {
                // Preserve the baseline's boundary interval; this is not a claim
                // that the original interval supplied sufficient recovery.
                guard start + newDays[0] - last >= start + oldDays[0] - last else {
                    return .refused("earlier exposure across prior-week boundary")
                }
            }
        }
        guard case .dosePreserved = compareAllocatedDoseOnly(proposed, baseline: menus,
            blueprint: blueprint, weekNumber: baseline.weekNumber) else { return .refused("complete dose changed") }
        let ordered = reorderedMenusForSessionFlow(proposed, blueprint: blueprint,
            trainingIntent: trainingIntent, lockedPrefixCounts: baseline.lockedPrefixCounts)
        guard accessoryRelocationSignature(ordered) == accessoryRelocationSignature(proposed) else {
            return .refused("candidate needs reordering")
        }
        return .candidate(.init(menus: proposed, blueprint: blueprint, weekNumber: baseline.weekNumber,
            lockedPrefixCounts: baseline.lockedPrefixCounts, retainedKeysByDay: baseline.retainedKeysByDay,
            exerciseHistory: baseline.exerciseHistory, selectionFocusIntents: baseline.selectionFocusIntents,
            roleFloorAdmission: .unassessed))
    }

    private func accessoryRelocationSignature(_ menus: [[PreSelectedExercise]]) -> [[String]] {
        menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.role)|\($0.movementPattern)|\($0.prescribedSets)" } }
    }

    /// Allocation is not allowed to pay for a relocation by silently changing a
    /// survivor's prescription, even when a broad weekly total still looks right.
    func verifyAccessoryRelocationAllocation(_ allocated: [[PreSelectedExercise]],
        admission: RoleFloorAdmission, proposed: SubstitutionPlanningBaseline) -> String? {
        guard admission == .admitted else { return "fresh allocation not admitted" }
        guard accessoryRelocationSignature(allocated) == accessoryRelocationSignature(proposed.menus) else {
            return "fresh allocation changed the proposed identity or dose"
        }
        return nil
    }

    func verifyAccessoryRelocationDelivery(original: WorkoutWeekResponse, candidate: WorkoutWeekResponse,
        baseline: SubstitutionPlanningBaseline, proposed: SubstitutionPlanningBaseline,
        previousWeekDays: [WorkoutDayResponse]?) -> String? {
        let start = (baseline.weekNumber - 1) * 7 + 1
        func matches(_ output: WorkoutWeekResponse, _ plan: SubstitutionPlanningBaseline) -> Bool {
            output.days.count == 7 && plan.menus.count == 7 && plan.blueprint.dayPlans.count == 7
                && output.days.map(\.dayNumber) == Array(start...(start + 7 - 1))
                && output.days.indices.allSatisfy { day in
                    let response = output.days[day], expected = plan.menus[day]
                    return response.isRestDay == plan.blueprint.dayPlans[day].isRestDay
                        && response.exercises.count == expected.count
                        && zip(response.exercises, expected).allSatisfy {
                            $0.exerciseName == $1.exerciseName && $0.muscleTarget == $1.muscleTarget
                                && $0.sets == $1.prescribedSets
                        }
                }
        }
        guard matches(original, baseline), matches(candidate, proposed) else { return "delivery mismatch" }
        func prescriptions(_ output: WorkoutWeekResponse) -> [String] {
            output.days.flatMap { $0.exercises.map {
                "\($0.exerciseName)|\($0.muscleTarget)|\($0.sets)|\($0.reps)|\($0.tempo)|\($0.restSeconds)|\(String(describing: $0.targetRIR))"
            } }.sorted()
        }
        guard prescriptions(original) == prescriptions(candidate) else { return "delivery changed execution prescription" }
        func findings(_ output: WorkoutWeekResponse, _ plan: SubstitutionPlanningBaseline) -> [String: Int] {
            Dictionary(grouping: validateWeekResponse(output, dayStart: start, dayEnd: start + 6,
                previousWeekDays: previousWeekDays, blueprint: plan.blueprint, expectedExerciseMenus: plan.menus),
                by: { $0 }).mapValues(\.count)
        }
        let old = findings(original, baseline), new = findings(candidate, proposed)
        guard new.allSatisfy({ message, count in count <= old[message, default: 0] }) else {
            return "new validator findings"
        }
        return nil
    }
}
