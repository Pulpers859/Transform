import Foundation

extension ClaudeService {
    struct SubstitutionPlanningBaseline {
        let menus: [[PreSelectedExercise]]
        let blueprint: ProgramBlueprint
        let weekNumber: Int
        let lockedPrefixCounts: [Int]
        // Identity protection is separate from ordering: focus days can retain work
        // while intentionally having no locked prefix. Removed identities are inert.
        let retainedKeysByDay: [Set<String>]
        let exerciseHistory: ExerciseHistoryContext?
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
        guard baseline.retainedKeysByDay.count == baseline.menus.count else { return .rejected(.lockContext) }
        for day in baseline.menus.indices {
            for slot in baseline.menus[day].indices {
                let old = baseline.menus[day][slot]
                if old.exerciseName != candidate[day][slot].exerciseName,
                   baseline.retainedKeysByDay[day].contains(ExerciseWeightEntry.canonicalLookupKey(old.exerciseName)) {
                    return .rejected(.retainedSlot)
                }
            }
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
