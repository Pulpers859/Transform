import Foundation

extension ClaudeService {
    /// At most one fresh allocation in this stage. Any refusal returns the
    /// untouched input plan/reports rather than trying further reallocations.
    func finalizeFirstCrossDayTricepsConsolidation(_ baseline: SubstitutionPlanningBaseline,
        trainingIntent: TrainingIntentPlan, previousWeekDays: [WorkoutDayResponse]?,
        baselineMessages: [String], baselineReceipts: [SetFundingObservation], collectFunding: Bool
    ) -> SessionCapacityFinalization {
        func retained(_ reason: String) -> SessionCapacityFinalization {
            .init(plan: baseline, messages: baselineMessages, receipts: baselineReceipts, decision: reason)
        }
        guard baseline.menus.count == 7, baseline.blueprint.dayPlans.count == 7 else {
            return retained("no eligible cross-day triceps consolidation")
        }
        let source = baseline.menus.indices.first(where: { day in
                baseline.menus[day].count == 7
                    && canonicalTrainingStyle(baseline.blueprint.dayPlans[day].style) == "Upper"
            }) ?? baseline.menus.indices.first(where: { day in
                baseline.menus[day].count == 6
                    && canonicalTrainingStyle(baseline.blueprint.dayPlans[day].style) == "Upper"
            })
        guard let source else { return retained("no eligible cross-day triceps consolidation") }
        for donor in baseline.menus[source].indices.reversed() {
            for receiver in baseline.menus.indices where baseline.menus[receiver].count == 5 {
                guard case .candidate(let proposed) = proposeCrossDayTricepsConsolidation(baseline,
                    source: source, donor: donor, receiver: receiver, trainingIntent: trainingIntent,
                    previousWeekDays: previousWeekDays) else { continue }
                var admission: RoleFloorAdmission = .unassessed
                var messages: [String] = []
                var receipts: [SetFundingObservation] = []
                let observer: (([SetFundingObservation]) -> Void)? = collectFunding ? { receipts = $0 } : nil
                let allocated = allocateWeeklySetPrescription(proposed.menus, blueprint: proposed.blueprint,
                    weekNumber: proposed.weekNumber, lockedPrefixCounts: proposed.lockedPrefixCounts,
                    appearancePlanningReport: { messages.append($0) }, setFundingReport: observer,
                    roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
                // The existing helper verifies exact identities, order and sets;
                // it does not authorize either operation's eligibility policy.
                if let reason = verifyAccessoryRelocationAllocation(allocated, admission: admission, proposed: proposed) {
                    return retained(reason)
                }
                let start = (baseline.weekNumber - 1) * 7 + 1
                func delivered(_ menus: [[PreSelectedExercise]]) -> WorkoutWeekResponse {
                    buildProceduralWeek(weekNumber: baseline.weekNumber, dayStart: start, dayEnd: start + 6,
                        splitType: trainingIntent.splitRecommendation, programName: "Triceps consolidation verification",
                        trainingIntent: trainingIntent, blueprint: baseline.blueprint,
                        previousWeekDays: previousWeekDays, exerciseMenus: menus)
                }
                if let reason = verifyCrossDayTricepsDelivery(original: delivered(baseline.menus),
                    candidate: delivered(allocated), baseline: baseline, proposed: proposed,
                    previousWeekDays: previousWeekDays) { return retained(reason) }
                return .init(plan: .init(menus: allocated, blueprint: proposed.blueprint,
                    weekNumber: proposed.weekNumber, lockedPrefixCounts: proposed.lockedPrefixCounts,
                    retainedKeysByDay: proposed.retainedKeysByDay, exerciseHistory: proposed.exerciseHistory,
                    selectionFocusIntents: proposed.selectionFocusIntents, roleFloorAdmission: admission),
                    messages: messages, receipts: receipts,
                    decision: "adopted six-slot cross-day triceps consolidation with two explicit receiver increments")
            }
        }
        return retained("no eligible cross-day triceps consolidation")
    }

    enum CrossDayTricepsTrial {
        case refused(String)
        case candidate(SubstitutionPlanningBaseline)
    }

    /// A distinct capacity operation, not a relaxation of substitution protection.
    /// One unprotected two-set pressdown is removed; two existing pure-triceps
    /// accessories each gain one set. Receiver identity/order may be retained or
    /// prefix-locked; their exact +1 is the only protected-prescription exception.
    func proposeCrossDayTricepsConsolidation(_ baseline: SubstitutionPlanningBaseline,
        source: Int, donor: Int, receiver: Int, trainingIntent: TrainingIntentPlan,
        previousWeekDays: [WorkoutDayResponse]?) -> CrossDayTricepsTrial {
        let menus = baseline.menus, blueprint = baseline.blueprint
        guard (2...3).contains(baseline.weekNumber), baseline.roleFloorAdmission == .admitted,
              !blueprint.calibration.recoveryConstrained, !blueprint.calibration.poorNutritionAdherence,
              menus.count == 7, blueprint.dayPlans.count == 7,
              baseline.lockedPrefixCounts.count == 7, baseline.retainedKeysByDay.count == 7,
              baseline.selectionFocusIntents.count == 7,
              blueprint.dayPlans.filter({ !$0.isRestDay }).count == blueprint.weeklyTrainingDays,
              menus.indices.contains(source), menus.indices.contains(receiver), source != receiver,
              menus[source].indices.contains(donor),
              menus.indices.allSatisfy({ day in
                  blueprint.dayPlans[day].dayIndex == day + 1
                      && baseline.lockedPrefixCounts[day] >= 0
                      && baseline.lockedPrefixCounts[day] <= menus[day].count
                      && (blueprint.dayPlans[day].isRestDay ? menus[day].isEmpty : (5...7).contains(menus[day].count))
                      && menus[day].allSatisfy { $0.prescribedSets > 0 }
                      && Set(menus[day].map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) }).count == menus[day].count
              }), menus.filter({ $0.count > 6 }).count == (menus[source].count == 7 ? 1 : 0),
              (6...7).contains(menus[source].count), menus[receiver].count == 5,
              canonicalTrainingStyle(blueprint.dayPlans[source].style) == "Upper",
              canonicalTrainingStyle(blueprint.dayPlans[receiver].style) == "Arms" else {
            return .refused("outside bounded cross-day triceps context")
        }
        let start = (baseline.weekNumber - 1) * 7 + 1
        guard let previous = previousWeekDays, previous.count == 7,
              previous.map(\.dayNumber) == Array((start - 7)..<start),
              previous.allSatisfy({ $0.isRestDay == $0.exercises.isEmpty
                  && $0.exercises.allSatisfy { $0.sets > 0 } }) else {
            return .refused("invalid previous week")
        }
        func metadata(_ item: PreSelectedExercise) -> ExerciseMetadata {
            exerciseMetadata(forExerciseName: item.exerciseName, muscleTarget: item.muscleTarget)
        }
        func pureAccessory(_ item: PreSelectedExercise) -> Bool {
            let info = metadata(item)
            return item.role == .accessory
                && proceduralExerciseRole(for: item.exerciseName, muscleTarget: item.muscleTarget) == .accessory
                && Set(info.primaryAreas.map(normalizedPriorityText)) == ["triceps"]
                && info.secondaryAreas.isEmpty
        }
        let removed = menus[source][donor]
        guard pureAccessory(removed), removed.prescribedSets == 2,
              metadata(removed).movementPattern == "Pressdown",
              !isProtectedAppearance(role: removed.role, slot: donor, style: blueprint.dayPlans[source].style,
                  lockedPrefixCount: baseline.lockedPrefixCounts[source]),
              !baseline.retainedKeysByDay[source].contains(ExerciseWeightEntry.canonicalLookupKey(removed.exerciseName)) else {
            return .refused("protected or unsupported triceps donor")
        }
        let receivers = menus[receiver].indices.filter { pureAccessory(menus[receiver][$0]) }
        guard receivers.count == 2, receivers.allSatisfy({ menus[receiver][$0].prescribedSets == 2 }),
              receivers.filter({ metadata(menus[receiver][$0]).movementPattern == "Pressdown" }).count == 1,
              receivers.filter({ metadata(menus[receiver][$0]).movementPattern == "Extension" }).count == 1 else {
            return .refused("requires two existing complementary two-set receivers")
        }
        let accounting = weeklyExerciseAccounting(for: menus, blueprint: blueprint)
        for (day, slot) in [(source, donor)] + receivers.map({ (receiver, $0) }) {
            let item = menus[day][slot], key = ExerciseWeightEntry.canonicalLookupKey(item.exerciseName)
            let cost = accounting.exercises[day][slot]
            guard cost.unitDirect.allSatisfy({ $0 == 0 }), cost.unitWeighted.allSatisfy({ $0 == 0 }) else {
                return .refused("priority-involved triceps work is protected")
            }
            guard !(baseline.exerciseHistory?.painExercises.contains(key) ?? false),
                  !(baseline.exerciseHistory?.equipmentSkipExercises.contains(key) ?? false),
                  !reportedShoulderPainImplicates(exerciseName: item.exerciseName, muscleTarget: item.muscleTarget,
                      injuryRiskFocus: blueprint.injuryRiskFocus),
                  [ReportedJointStressArea.elbow, .lowerBack, .knee].allSatisfy({ joint in
                      !reportedJointPainImplicates(joint, exerciseName: item.exerciseName,
                          muscleTarget: item.muscleTarget, injuryRiskFocus: blueprint.injuryRiskFocus)
                  }) else { return .refused("history or symptoms exclude triceps consolidation") }
        }
        var proposed = menus
        proposed[source].remove(at: donor)
        for slot in receivers { proposed[receiver][slot].prescribedSets += 1 }
        func direct(_ day: [PreSelectedExercise]) -> Int {
            day.reduce(0) { $0 + (metadata($1).primaryAreas.map(normalizedPriorityText).contains("triceps") ? $1.prescribedSets : 0) }
        }
        let oldDirectDays = menus.indices.filter { direct(menus[$0]) >= 2 }
        let newDirectDays = proposed.indices.filter { direct(proposed[$0]) >= 2 }
        guard oldDirectDays.count == 3, newDirectDays.count == 2,
              newDirectDays == oldDirectDays.filter({ $0 != source }),
              direct(proposed[source]) == 0, direct(proposed[receiver]) <= 8,
              menus.map(direct).reduce(0, +) == proposed.map(direct).reduce(0, +) else {
            return .refused("outside two-day eight-set triceps concentration boundary")
        }
        // Include every positive primary OR secondary exposure, not just isolation
        // sets. The upper-day shoulder press still counts after pressdown removal.
        func overlaps(_ primary: [String], _ secondary: [String]) -> Bool {
            (primary + secondary).map(normalizedPriorityText).contains("triceps")
        }
        func loadingDays(_ value: [[PreSelectedExercise]]) -> [Int] {
            value.indices.filter { day in value[day].contains { item in
                let info = metadata(item)
                return overlaps(info.primaryAreas, info.secondaryAreas) && item.prescribedSets > 0
            } }
        }
        let oldLoading = loadingDays(menus), newLoading = loadingDays(proposed)
        guard newLoading == oldLoading, newLoading.count >= 2,
              zip(newLoading, newLoading.dropFirst()).allSatisfy({ $1 - $0 >= 2 }),
              7 + newLoading[0] - newLoading[newLoading.count - 1] >= 2 else {
            return .refused("pressing overlap or cyclic spacing refused")
        }
        if let last = previous.last(where: { day in day.exercises.contains { item in
            let info = exerciseMetadata(for: item)
            return item.sets > 0 && overlaps(info.primaryAreas, info.secondaryAreas)
        } })?.dayNumber {
            guard start + newLoading[0] - last >= 2 else { return .refused("prior-week pressing interval refused") }
        }
        // The first and last loading days remain unchanged, so this operation
        // cannot shorten either boundary relative to the original plan. A future
        // week is not yet known; cyclic spacing is not proof of its actual spacing.
        // Both spacing and the eight-set cap are engineering screens, not clinical
        // thresholds, biological equivalence, or a guarantee of 48 elapsed hours.
        guard case .dosePreserved = compareAllocatedDoseOnly(proposed, baseline: menus,
            blueprint: blueprint, weekNumber: baseline.weekNumber) else { return .refused("complete triceps dose refused") }
        let ordered = reorderedMenusForSessionFlow(proposed, blueprint: blueprint,
            trainingIntent: trainingIntent, lockedPrefixCounts: baseline.lockedPrefixCounts)
        guard crossDayTricepsSignature(ordered) == crossDayTricepsSignature(proposed) else {
            return .refused("triceps proposal requires reordering")
        }
        return .candidate(.init(menus: proposed, blueprint: blueprint, weekNumber: baseline.weekNumber,
            lockedPrefixCounts: baseline.lockedPrefixCounts, retainedKeysByDay: baseline.retainedKeysByDay,
            exerciseHistory: baseline.exerciseHistory, selectionFocusIntents: baseline.selectionFocusIntents,
            roleFloorAdmission: .unassessed))
    }

    private func crossDayTricepsSignature(_ menus: [[PreSelectedExercise]]) -> [[String]] {
        menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.role)|\($0.movementPattern)|\($0.prescribedSets)" } }
    }

    func verifyCrossDayTricepsDelivery(original: WorkoutWeekResponse, candidate: WorkoutWeekResponse,
        baseline: SubstitutionPlanningBaseline, proposed: SubstitutionPlanningBaseline,
        previousWeekDays: [WorkoutDayResponse]?) -> String? {
        let start = (baseline.weekNumber - 1) * 7 + 1
        func matches(_ output: WorkoutWeekResponse, _ plan: SubstitutionPlanningBaseline) -> Bool {
            output.days.count == 7 && plan.menus.count == 7 && plan.blueprint.dayPlans.count == 7
                && output.days.map(\.dayNumber) == Array(start...(start + 6))
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
        guard matches(original, baseline), matches(candidate, proposed) else { return "triceps delivery mismatch" }
        for day in candidate.days.indices {
            for item in candidate.days[day].exercises {
                guard let old = original.days[day].exercises.first(where: {
                    $0.exerciseName == item.exerciseName && $0.muscleTarget == item.muscleTarget
                }), item.reps == old.reps, item.tempo == old.tempo,
                    item.restSeconds == old.restSeconds, item.targetRIR == old.targetRIR else {
                    return "triceps delivery changed execution prescription"
                }
            }
        }
        func findings(_ output: WorkoutWeekResponse, _ plan: SubstitutionPlanningBaseline) -> [String: Int] {
            Dictionary(grouping: validateWeekResponse(output, dayStart: start, dayEnd: start + 6,
                previousWeekDays: previousWeekDays, blueprint: plan.blueprint, expectedExerciseMenus: plan.menus),
                by: { $0 }).mapValues(\.count)
        }
        let old = findings(original, baseline), new = findings(candidate, proposed)
        guard new.allSatisfy({ message, count in count <= old[message, default: 0] }) else {
            return "new triceps validator findings"
        }
        return nil
    }
}
