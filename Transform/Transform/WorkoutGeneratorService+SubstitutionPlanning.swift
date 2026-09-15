import Foundation

extension ClaudeService {
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
        // This experimental gate has no live adoption caller. It must not be used to keep
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
