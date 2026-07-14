import Foundation

extension ClaudeService {

    func exerciseResponse(
        _ exercise: WorkoutExerciseResponse,
        withSets sets: Int
    ) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: exercise.exerciseName,
            sets: sets,
            reps: exercise.reps,
            tempo: exercise.tempo,
            restSeconds: exercise.restSeconds,
            notes: exercise.notes,
            muscleTarget: exercise.muscleTarget
        )
    }

    func retainedAnchorExercises(
        from previousExercises: [WorkoutExerciseResponse],
        style: String
    ) -> [WorkoutExerciseResponse] {
        // EvidenceProfile.md ORD-001 / CONT-001 [confidence: moderate]
        previousExercises
            .enumerated()
            .filter { _, exercise in
                let key = normalizeExerciseName(exercise.exerciseName)
                return !key.isEmpty && exerciseMatchesDayStyle(exercise, style: style)
            }
            .sorted { lhs, rhs in
                let lhsRole = proceduralExerciseRole(for: lhs.element.exerciseName, muscleTarget: lhs.element.muscleTarget)
                let rhsRole = proceduralExerciseRole(for: rhs.element.exerciseName, muscleTarget: rhs.element.muscleTarget)
                if lhsRole != rhsRole {
                    return proceduralExerciseRolePriority(lhsRole) < proceduralExerciseRolePriority(rhsRole)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func arrangeProceduralSelection(
        _ exercises: [(name: String, target: String)],
        lockedPrefixCount: Int,
        focusIntent: MusclePriorityIntent?
    ) -> [(name: String, target: String)] {
        // EvidenceProfile.md ORD-001 [confidence: moderate]
        let safeLockedCount = max(0, min(lockedPrefixCount, exercises.count))
        let locked = Array(exercises.prefix(safeLockedCount))
        let remaining = Array(exercises.dropFirst(safeLockedCount))

        let orderedRemaining = remaining
            .enumerated()
            .sorted { lhs, rhs in
                if let focusIntent {
                    let lhsFocusPriority = focusOrderingPriority(
                        exerciseName: lhs.element.name,
                        muscleTarget: lhs.element.target,
                        focusArea: focusIntent.area
                    )
                    let rhsFocusPriority = focusOrderingPriority(
                        exerciseName: rhs.element.name,
                        muscleTarget: rhs.element.target,
                        focusArea: focusIntent.area
                    )
                    if lhsFocusPriority != rhsFocusPriority { return lhsFocusPriority < rhsFocusPriority }
                }

                let lhsRole = proceduralExerciseRole(for: lhs.element.name, muscleTarget: lhs.element.target)
                let rhsRole = proceduralExerciseRole(for: rhs.element.name, muscleTarget: rhs.element.target)
                let lhsPriority = proceduralExerciseRolePriority(lhsRole)
                let rhsPriority = proceduralExerciseRolePriority(rhsRole)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }

                return lhs.offset < rhs.offset
            }
            .map(\.element)

        return locked + orderedRemaining
    }

    func focusExerciseTargetCount(for intent: MusclePriorityIntent) -> Int {
        // EvidenceProfile.md SLOT-001 / VOL-001 [confidence: moderate]
        let exposures = max(1, intent.weeklyDayTarget)
        let slotDrivenTarget = Int(ceil(Double(intent.weeklyExerciseTarget) / Double(exposures)))
        // Set-arithmetic floor: enough exercises per exposure that the session's share of
        // the weekly direct-set target never forces a single exercise above ~4 sets.
        let setDrivenTarget = Int(ceil(intent.weeklyDirectSetTarget / Double(exposures) / 4.0))
        return max(1, min(3, max(slotDrivenTarget, setDrivenTarget)))
    }

    // MARK: - Within-Day Movement-Pattern Cap

    /// Movement pattern used for the within-day redundancy cap; nil when metadata has no
    /// usable pattern so unrecognized exercises never share one blocking bucket.
    func menuMovementPattern(forExerciseName name: String, muscleTarget: String) -> String? {
        let pattern = exerciseMetadata(forExerciseName: name, muscleTarget: muscleTarget)
            .movementPattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return pattern.isEmpty ? nil : pattern
    }

    /// A single session gets at most 2 exercises of the same movement pattern. This is the
    /// selection-time guard against menus like four vertical pulls or three flat presses in
    /// one day — previously only penalized during fatigue trimming, never prevented.
    func dayPatternCapAllows(
        candidateName: String,
        candidateTarget: String,
        in selected: [(name: String, target: String)]
    ) -> Bool {
        guard let pattern = menuMovementPattern(forExerciseName: candidateName, muscleTarget: candidateTarget) else {
            return true
        }
        let matches = selected.filter {
            menuMovementPattern(forExerciseName: $0.name, muscleTarget: $0.target) == pattern
        }.count
        return matches < 2
    }

    func metadataFocusExerciseCatalog(for focusArea: String) -> [(name: String, target: String)] {
        let aliases = Set(stimulusAreaAliases(for: focusArea))
        guard !aliases.isEmpty else { return [] }
        return exerciseMetadataEntries
            .filter { !aliases.isDisjoint(with: Set($0.primaryAreas)) }
            .sorted { $0.fatigueCost < $1.fatigueCost }
            .map { ($0.canonicalName, $0.primaryAreas.first ?? focusArea) }
    }

    func enforceFocusExerciseCoverage(
        _ selected: [(name: String, target: String)],
        targetCount: Int,
        focusIntent: MusclePriorityIntent,
        selectionLimit: Int,
        protectedPrefixCount: Int = 0,
        usedAcrossDays: Set<String> = [],
        avoidedExercises: Set<String> = [],
        selectionAllowed: (([(name: String, target: String)]) -> Bool)? = nil
    ) -> [(name: String, target: String)] {
        var result = selected

        func focusMatchCount(in exercises: [(name: String, target: String)]) -> Int {
            exercises.filter { exerciseMatchesTrainingIntent(name: $0.name, target: $0.target, intent: focusIntent) }.count
        }

        func injectFocusCandidates(from catalog: [(name: String, target: String)]) {
            for candidate in catalog {
                guard focusMatchCount(in: result) < targetCount else { return }
                guard exerciseMatchesTrainingIntent(name: candidate.name, target: candidate.target, intent: focusIntent) else { continue }
                let candidateKey = normalizeExerciseName(candidate.name)
                guard !usedAcrossDays.contains(candidateKey) else { continue }
                guard !avoidedExercises.contains(ExerciseWeightEntry.canonicalLookupKey(candidate.name)) else { continue }
                guard !result.contains(where: { normalizeExerciseName($0.name) == candidateKey }) else { continue }
                guard dayPatternCapAllows(candidateName: candidate.name, candidateTarget: candidate.target, in: result) else { continue }

                var proposed = result
                if proposed.count >= selectionLimit {
                    guard let removalIndex = proposed.indices.reversed().first(where: { index in
                        index >= protectedPrefixCount &&
                        !exerciseMatchesTrainingIntent(name: proposed[index].name, target: proposed[index].target, intent: focusIntent)
                    }) else {
                        return
                    }
                    proposed.remove(at: removalIndex)
                }
                proposed.append(candidate)
                guard selectionAllowed?(proposed) ?? true else { continue }
                result = proposed
            }
        }

        injectFocusCandidates(from: priorityAccessoryCatalog(for: focusIntent))

        if focusMatchCount(in: result) < targetCount {
            injectFocusCandidates(from: metadataFocusExerciseCatalog(for: focusIntent.area))
        }

        return result
    }

    func enforceSupportExerciseCoverage(
        _ selected: [(name: String, target: String)],
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        selectionLimit: Int,
        protectedPrefixCount: Int = 0,
        usedAcrossDays: Set<String> = [],
        avoidedExercises: Set<String> = [],
        selectionAllowed: (([(name: String, target: String)]) -> Bool)? = nil
    ) -> [(name: String, target: String)] {
        var result = selected

        for supportIntent in supportIntents {
            let alreadyCovered = result.contains {
                exerciseMatchesTrainingIntent(name: $0.name, target: $0.target, intent: supportIntent)
            }
            if alreadyCovered { continue }

            let catalogs: [[(name: String, target: String)]] = [
                priorityAccessoryCatalog(for: supportIntent),
                metadataFocusExerciseCatalog(for: supportIntent.area)
            ]

            var added = false
            for catalog in catalogs where !added {
                for candidate in catalog {
                    guard exerciseMatchesTrainingIntent(name: candidate.name, target: candidate.target, intent: supportIntent) else { continue }
                    let candidateKey = normalizeExerciseName(candidate.name)
                    guard !usedAcrossDays.contains(candidateKey) else { continue }
                    guard !avoidedExercises.contains(ExerciseWeightEntry.canonicalLookupKey(candidate.name)) else { continue }
                    guard !result.contains(where: { normalizeExerciseName($0.name) == candidateKey }) else { continue }
                    guard dayPatternCapAllows(candidateName: candidate.name, candidateTarget: candidate.target, in: result) else { continue }

                    var proposed = result
                    if proposed.count >= selectionLimit {
                        guard let removalIndex = proposed.indices.reversed().first(where: { index in
                            guard index >= protectedPrefixCount else { return false }
                            if let focusIntent,
                               exerciseMatchesTrainingIntent(
                                   name: proposed[index].name,
                                   target: proposed[index].target,
                                   intent: focusIntent
                               ) {
                                return false
                            }
                            return !supportIntents.contains { intent in
                                exerciseMatchesTrainingIntent(
                                    name: proposed[index].name,
                                    target: proposed[index].target,
                                    intent: intent
                                )
                            }
                        }) else {
                            break
                        }
                        proposed.remove(at: removalIndex)
                    }
                    proposed.append(candidate)
                    guard selectionAllowed?(proposed) ?? true else { continue }
                    result = proposed
                    added = true
                    break
                }
            }
        }

        return result
    }

    func balancedProceduralExercises(
        _ exercises: [WorkoutExerciseResponse],
        weekNumber: Int,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        targetFatigueCap: Int,
        targetSessionMinutes: Int? = nil,
        menuLocked: Bool = false
    ) -> [WorkoutExerciseResponse] {
        var balanced = exercises

        if let focusIntent {
            if !menuLocked {
                let focusCap = blueprintAllocation(for: focusIntent).maxFocusSessionDirectSets
                balanced = rebalanceDirectSets(
                    in: balanced,
                    for: focusIntent,
                    allowedCap: focusCap
                )
                balanced = trimExcessPriorityExerciseMatches(
                    in: balanced,
                    for: focusIntent,
                    maxMatches: focusExerciseTargetCount(for: focusIntent)
                )
            }
        }

        if !menuLocked {
            for supportIntent in supportIntents {
                balanced = trimExcessPriorityExerciseMatches(
                    in: balanced,
                    for: supportIntent,
                    maxMatches: 1
                )
            }

            balanced = rebalanceDayFatigue(
                in: balanced,
                weekNumber: weekNumber,
                focusIntent: focusIntent,
                supportIntents: supportIntents,
                targetFatigueCap: targetFatigueCap
            )

            while balanced.count > 5 && estimatedDayFatigue(for: balanced) > targetFatigueCap {
                guard let removalIndex = fatigueTrimCandidateIndex(
                    in: balanced,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents
                ) else {
                    break
                }
                balanced.remove(at: removalIndex)
            }

            if let targetSessionMinutes {
                balanced = rebalanceSessionTime(
                    in: balanced,
                    weekNumber: weekNumber,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents,
                    targetSessionMinutes: targetSessionMinutes
                )
            }
        } else {
            balanced = setOnlyFatigueRebalance(
                balanced,
                weekNumber: weekNumber,
                focusIntent: focusIntent,
                supportIntents: supportIntents,
                targetFatigueCap: targetFatigueCap,
                targetSessionMinutes: targetSessionMinutes
            )
        }

        return balanced
    }

    func setOnlyFatigueRebalance(
        _ exercises: [WorkoutExerciseResponse],
        weekNumber: Int,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        targetFatigueCap: Int,
        targetSessionMinutes: Int?
    ) -> [WorkoutExerciseResponse] {
        var balanced = exercises

        while estimatedDayFatigue(for: balanced) > targetFatigueCap {
            guard let idx = volumeReductionCandidateIndex(
                in: balanced, weekNumber: weekNumber,
                focusIntent: focusIntent, supportIntents: supportIntents
            ) else { break }
            guard balanced[idx].sets > minimumSetFloor(for: balanced[idx]) else { break }
            balanced[idx] = exerciseResponse(balanced[idx], withSets: balanced[idx].sets - 1)
        }

        if let targetSessionMinutes {
            while estimatedSessionMinutes(for: proceduralTrainingDay(from: balanced)) > targetSessionMinutes + 3 {
                guard let idx = volumeReductionCandidateIndex(
                    in: balanced, weekNumber: weekNumber,
                    focusIntent: focusIntent, supportIntents: supportIntents
                ) else { break }
                guard balanced[idx].sets > minimumSetFloor(for: balanced[idx]) else { break }
                balanced[idx] = exerciseResponse(balanced[idx], withSets: balanced[idx].sets - 1)
            }
        }

        return balanced
    }

    func trimExcessPriorityExerciseMatches(
        in exercises: [WorkoutExerciseResponse],
        for intent: MusclePriorityIntent,
        maxMatches: Int
    ) -> [WorkoutExerciseResponse] {
        guard maxMatches >= 0 else { return exercises }

        var trimmed = exercises
        let minimumExerciseCount = 5

        func matchingIndices(in source: [WorkoutExerciseResponse]) -> [Int] {
            source.indices.filter { index in
                directPrioritySetContribution(
                    exerciseName: source[index].exerciseName,
                    muscleTarget: source[index].muscleTarget,
                    intent: intent,
                    sets: source[index].sets
                ) > 0
            }
        }

        while matchingIndices(in: trimmed).count > maxMatches, trimmed.count > minimumExerciseCount {
            let candidates = matchingIndices(in: trimmed)
            guard let removalIndex = candidates.max(by: { lhs, rhs in
                priorityExerciseRemovalScore(
                    for: trimmed[lhs],
                    at: lhs,
                    intent: intent
                ) < priorityExerciseRemovalScore(
                    for: trimmed[rhs],
                    at: rhs,
                    intent: intent
                )
            }) else {
                break
            }
            trimmed.remove(at: removalIndex)
        }

        return trimmed
    }

    func priorityExerciseRemovalScore(
        for exercise: WorkoutExerciseResponse,
        at index: Int,
        intent: MusclePriorityIntent
    ) -> Int {
        let role = proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
        let kind = focusStimulusKind(
            exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget,
            focusArea: intent.area
        )

        var score = index * 10
        score += exercise.sets * 2

        switch kind {
        case .support:
            score += 20
        case .secondary:
            score += 10
        case .prime:
            score -= 20
        case .none:
            score += 30
        }

        switch role {
        case .accessory:
            score += 8
        case .secondary:
            score += 4
        case .anchor:
            score -= 8
        case .core:
            score += 2
        }

        return score
    }

    func estimatedDayFatigue(for exercises: [WorkoutExerciseResponse]) -> Int {
        exercises.reduce(0) { partialResult, exercise in
            partialResult + fatigueContribution(for: exercise, metadata: exerciseMetadata(for: exercise))
        }
    }

    func fatigueTrimCandidateIndex(
        in exercises: [WorkoutExerciseResponse],
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent]
    ) -> Int? {
        let patternCounts = Dictionary(grouping: exercises.indices, by: { index in
            exerciseMetadata(for: exercises[index]).movementPattern
        }).mapValues(\.count)

        return exercises.indices.max { lhs, rhs in
            removalPriority(
                for: exercises[lhs],
                at: lhs,
                within: exercises,
                patternCounts: patternCounts,
                focusIntent: focusIntent,
                supportIntents: supportIntents
            ) < removalPriority(
                for: exercises[rhs],
                at: rhs,
                within: exercises,
                patternCounts: patternCounts,
                focusIntent: focusIntent,
                supportIntents: supportIntents
            )
        }
    }

    func removalPriority(
        for exercise: WorkoutExerciseResponse,
        at index: Int,
        within exercises: [WorkoutExerciseResponse],
        patternCounts: [String: Int],
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent]
    ) -> Int {
        let metadata = exerciseMetadata(for: exercise)
        let role = proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
        let focusKind = focusIntent.map {
            focusStimulusKind(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                focusArea: $0.area
            )
        } ?? .none
        let supportsCompanionPriority = supportIntents.contains { intent in
            directPrioritySetContribution(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                intent: intent,
                sets: exercise.sets
            ) > 0
        }

        var score = index

        switch focusKind {
        case .none:
            score += 10
        case .support:
            score += 7
        case .secondary:
            score += 3
        case .prime:
            score -= 12
        }

        if supportsCompanionPriority {
            score -= 6
        }

        if patternCounts[metadata.movementPattern, default: 0] > 1 {
            score += 8
        }

        switch role {
        case .anchor:
            score += metadata.fatigueCost >= 3 ? 9 : 4
        case .secondary:
            score += 5
        case .accessory:
            score += 2
        case .core:
            score += 1
        }

        if metadata.primaryAreas.contains("Upper Chest"),
           exercises.contains(where: { other in
               other.exerciseName != exercise.exerciseName
                   && exerciseMetadata(for: other).primaryAreas.contains("Upper Chest")
           }) {
            score += 4
        }

        if metadata.primaryAreas.contains("Quads"),
           metadata.movementPattern == "Squat",
           exercises.contains(where: { other in
               other.exerciseName != exercise.exerciseName
                   && exerciseMetadata(for: other).movementPattern == "Squat"
           }) {
            score += 5
        }

        return score
    }

    func rebalanceDirectSets(
        in exercises: [WorkoutExerciseResponse],
        for intent: MusclePriorityIntent,
        allowedCap: Double
    ) -> [WorkoutExerciseResponse] {
        var rebalanced = exercises

        while totalDirectSets(in: rebalanced, for: intent) > allowedCap + 0.01 {
            let candidateIndices = rebalanced.indices.filter { index in
                directPrioritySetContribution(
                    exerciseName: rebalanced[index].exerciseName,
                    muscleTarget: rebalanced[index].muscleTarget,
                    intent: intent,
                    sets: rebalanced[index].sets
                ) > 0 && rebalanced[index].sets > minimumSetFloor(for: rebalanced[index])
            }

            guard let reductionIndex = candidateIndices.max(by: { lhs, rhs in
                directSetReductionPriority(
                    for: rebalanced[lhs],
                    index: lhs,
                    focusArea: intent.area
                ) < directSetReductionPriority(
                    for: rebalanced[rhs],
                    index: rhs,
                    focusArea: intent.area
                )
            }) else {
                break
            }

            let updatedSets = rebalanced[reductionIndex].sets - 1
            rebalanced[reductionIndex] = exerciseResponse(
                rebalanced[reductionIndex],
                withSets: updatedSets
            )
        }

        return rebalanced
    }

    func rebalanceDayFatigue(
        in exercises: [WorkoutExerciseResponse],
        weekNumber: Int,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        targetFatigueCap: Int
    ) -> [WorkoutExerciseResponse] {
        var rebalanced = exercises

        while estimatedDayFatigue(for: rebalanced) > targetFatigueCap {
            guard let reductionIndex = volumeReductionCandidateIndex(
                in: rebalanced,
                weekNumber: weekNumber,
                focusIntent: focusIntent,
                supportIntents: supportIntents
            ) else {
                break
            }

            let minimumSets = minimumSetFloor(for: rebalanced[reductionIndex])
            if rebalanced[reductionIndex].sets > minimumSets {
                let updatedSets = rebalanced[reductionIndex].sets - 1
                rebalanced[reductionIndex] = exerciseResponse(
                    rebalanced[reductionIndex],
                    withSets: updatedSets
                )
                continue
            }

            if weekNumber > 1 && rebalanced.count > 5 {
                rebalanced.remove(at: reductionIndex)
                continue
            }

            break
        }

        return rebalanced
    }

    func rebalanceSessionTime(
        in exercises: [WorkoutExerciseResponse],
        weekNumber: Int,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        targetSessionMinutes: Int
    ) -> [WorkoutExerciseResponse] {
        var rebalanced = exercises

        while estimatedSessionMinutes(for: proceduralTrainingDay(from: rebalanced)) > targetSessionMinutes + 3 {
            guard let reductionIndex = volumeReductionCandidateIndex(
                in: rebalanced,
                weekNumber: weekNumber,
                focusIntent: focusIntent,
                supportIntents: supportIntents
            ) else {
                break
            }

            let minimumSets = minimumSetFloor(for: rebalanced[reductionIndex])
            if rebalanced[reductionIndex].sets > minimumSets {
                rebalanced[reductionIndex] = exerciseResponse(
                    rebalanced[reductionIndex],
                    withSets: rebalanced[reductionIndex].sets - 1
                )
                continue
            }

            if rebalanced.count > 5 {
                rebalanced.remove(at: reductionIndex)
                continue
            }

            break
        }

        return rebalanced
    }

    func proceduralTrainingDay(from exercises: [WorkoutExerciseResponse]) -> WorkoutDayResponse {
        WorkoutDayResponse(
            dayNumber: 1,
            dayName: "Procedural Session",
            muscleGroups: "Training",
            isRestDay: false,
            notes: "",
            exercises: exercises
        )
    }

    func volumeReductionCandidateIndex(
        in exercises: [WorkoutExerciseResponse],
        weekNumber: Int,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent]
    ) -> Int? {
        let canRemoveExercise = weekNumber > 1 && exercises.count > 5
        let candidateIndices = exercises.indices.filter { index in
            exercises[index].sets > minimumSetFloor(for: exercises[index]) || canRemoveExercise
        }

        return candidateIndices.max { lhs, rhs in
            volumeReductionPriority(
                for: exercises[lhs],
                index: lhs,
                focusIntent: focusIntent,
                supportIntents: supportIntents
            ) < volumeReductionPriority(
                for: exercises[rhs],
                index: rhs,
                focusIntent: focusIntent,
                supportIntents: supportIntents
            )
        }
    }

    func volumeReductionPriority(
        for exercise: WorkoutExerciseResponse,
        index: Int,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent]
    ) -> Int {
        let metadata = exerciseMetadata(for: exercise)
        let role = proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
        let isFocusDirect = focusIntent.map {
            directPrioritySetContribution(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                intent: $0,
                sets: exercise.sets
            ) > 0
        } ?? false
        let isSupportDirect = supportIntents.contains { intent in
            directPrioritySetContribution(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                intent: intent,
                sets: exercise.sets
            ) > 0
        }

        var score = index
        if !isFocusDirect { score += 12 } else { score -= 10 }
        if !isSupportDirect { score += 4 } else { score -= 4 }
        score += exercise.sets
        score += metadata.fatigueCost * 4

        switch role {
        case .anchor:
            score += 8
        case .secondary:
            score += 5
        case .accessory:
            score += 2
        case .core:
            score += 1
        }

        return score
    }

    func totalDirectSets(in exercises: [WorkoutExerciseResponse], for intent: MusclePriorityIntent) -> Double {
        exercises.reduce(0) { partialResult, exercise in
            partialResult + directPrioritySetContribution(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                intent: intent,
                sets: exercise.sets
            )
        }
    }

    func directPrioritySetContribution(
        exerciseName: String,
        muscleTarget: String,
        intent: MusclePriorityIntent,
        sets: Int
    ) -> Double {
        let qualityKind = focusStimulusKind(
            exerciseName: exerciseName,
            muscleTarget: muscleTarget,
            focusArea: intent.area
        )
        let qualityCredit = focusStimulusCredit(for: qualityKind) * Double(sets)
        if qualityCredit > 0 {
            return qualityCredit
        }

        let metadata = exerciseMetadata(forExerciseName: exerciseName, muscleTarget: muscleTarget)
        let focusAliases = Set(stimulusAreaAliases(for: intent.area).map(normalizedPriorityText))
        let primaryAliases = Set(metadata.primaryAreas.flatMap { stimulusAreaAliases(for: $0) }.map(normalizedPriorityText))
        if !focusAliases.isDisjoint(with: primaryAliases) {
            return Double(sets)
        }

        let secondaryAliases = Set(metadata.secondaryAreas.flatMap { stimulusAreaAliases(for: $0) }.map(normalizedPriorityText))
        if !focusAliases.isDisjoint(with: secondaryAliases) {
            return Double(sets) * 0.5
        }

        return 0
    }

    func directSetReductionPriority(
        for exercise: WorkoutExerciseResponse,
        index: Int,
        focusArea: String
    ) -> Int {
        let role = proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
        let kind = focusStimulusKind(
            exerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget,
            focusArea: focusArea
        )

        var score = index + exercise.sets
        switch kind {
        case .prime:
            score -= 8
        case .secondary:
            score += 4
        case .support:
            score += 10
        case .none:
            score += 12
        }

        switch role {
        case .anchor:
            score += 6
        case .secondary:
            score += 3
        case .accessory:
            score += 1
        case .core:
            score += 0
        }

        return score
    }

    func minimumSetFloor(for exercise: WorkoutExerciseResponse) -> Int {
        switch proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget) {
        case .anchor:
            return 3
        case .secondary:
            return 2
        case .accessory, .core:
            return 2
        }
    }

    func proceduralExerciseRole(for exerciseName: String, muscleTarget: String) -> ProceduralExerciseRole {
        let metadata = exerciseMetadata(
            forExerciseName: exerciseName,
            muscleTarget: muscleTarget
        )

        if isDirectCoreHypertrophyMovement(
            exerciseName: exerciseName,
            muscleTarget: muscleTarget,
            reps: ""
        ) {
            return .core
        }
        if metadata.fatigueCost >= 3 {
            return .anchor
        }
        if metadata.fatigueCost == 2 {
            return .secondary
        }
        return .accessory
    }

    func proceduralExerciseRolePriority(_ role: ProceduralExerciseRole) -> Int {
        switch role {
        case .anchor: return 0
        case .secondary: return 1
        case .accessory: return 2
        case .core: return 3
        }
    }

    func orderedExerciseCatalog(
        for style: String,
        focusIntent: MusclePriorityIntent?,
        selectionContext: ExerciseSelectionContext? = nil
    ) -> [(name: String, target: String)] {
        let catalog = exerciseCatalog(for: style)
        guard let focusIntent else { return catalog }

        return catalog
            .enumerated()
            .sorted { lhs, rhs in
                let lhsFocusPriority = focusOrderingPriority(
                    exerciseName: lhs.element.name,
                    muscleTarget: lhs.element.target,
                    focusArea: focusIntent.area
                )
                let rhsFocusPriority = focusOrderingPriority(
                    exerciseName: rhs.element.name,
                    muscleTarget: rhs.element.target,
                    focusArea: focusIntent.area
                )
                if lhsFocusPriority != rhsFocusPriority { return lhsFocusPriority < rhsFocusPriority }
                if let selectionContext {
                    let lhsScore = exerciseSelectionScore(
                        exerciseName: lhs.element.name,
                        muscleTarget: lhs.element.target,
                        focusIntent: focusIntent,
                        selectionContext: selectionContext
                    )
                    let rhsScore = exerciseSelectionScore(
                        exerciseName: rhs.element.name,
                        muscleTarget: rhs.element.target,
                        focusIntent: focusIntent,
                        selectionContext: selectionContext
                    )
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func orderedGenericExerciseCatalog(
        focusIntent: MusclePriorityIntent?,
        selectionContext: ExerciseSelectionContext? = nil
    ) -> [(name: String, target: String)] {
        let catalog = genericExerciseCatalog()
        guard let focusIntent else { return catalog }

        return catalog
            .enumerated()
            .sorted { lhs, rhs in
                let lhsFocusPriority = focusOrderingPriority(
                    exerciseName: lhs.element.name,
                    muscleTarget: lhs.element.target,
                    focusArea: focusIntent.area
                )
                let rhsFocusPriority = focusOrderingPriority(
                    exerciseName: rhs.element.name,
                    muscleTarget: rhs.element.target,
                    focusArea: focusIntent.area
                )
                if lhsFocusPriority != rhsFocusPriority { return lhsFocusPriority < rhsFocusPriority }
                if let selectionContext {
                    let lhsScore = exerciseSelectionScore(
                        exerciseName: lhs.element.name,
                        muscleTarget: lhs.element.target,
                        focusIntent: focusIntent,
                        selectionContext: selectionContext
                    )
                    let rhsScore = exerciseSelectionScore(
                        exerciseName: rhs.element.name,
                        muscleTarget: rhs.element.target,
                        focusIntent: focusIntent,
                        selectionContext: selectionContext
                    )
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func exerciseSelectionScore(
        exerciseName: String,
        muscleTarget: String,
        focusIntent: MusclePriorityIntent?,
        selectionContext: ExerciseSelectionContext
    ) -> Int {
        let metadata = exerciseMetadata(
            forExerciseName: exerciseName,
            muscleTarget: muscleTarget
        )
        var score = 0

        if let focusIntent {
            switch focusStimulusKind(
                exerciseName: exerciseName,
                muscleTarget: muscleTarget,
                focusArea: focusIntent.area
            ) {
            case .prime:
                score += 30
            case .secondary:
                score += 20
            case .support:
                score += 8
            case .none:
                break
            }
        }

        if metadata.preferredContexts.contains("hypertrophy") {
            score += 8
        }

        if selectionContext.calibration.recoveryConstrained {
            score -= metadata.systemicFatigue * 4
            if metadata.preferredContexts.contains("shift_work_friendly") {
                score += 10
            }
            if metadata.avoidContexts.contains("shift_work_friendly") {
                score -= 12
            }
        } else {
            score -= metadata.systemicFatigue * 2
        }

        if selectionContext.calibration.lowPerformanceDataQuality {
            score -= metadata.stabilityDemand * 4
            if metadata.preferredContexts.contains("low_data_quality") {
                score += 8
            }
            if metadata.avoidContexts.contains("low_data_quality") {
                score -= 8
            }
        }

        if selectionContext.targetSessionMinutes <= 60 {
            if metadata.preferredContexts.contains("short_session") {
                score += 8
            }
            if metadata.avoidContexts.contains("short_session") {
                score -= 10
            }
            if metadata.exerciseClass == "Isolation" || metadata.exerciseClass == "Prehab" {
                score += 4
            }
            score -= max(0, metadata.systemicFatigue - 1) * 2
        }

        if hasShoulderRisk(injuryRiskFocus: selectionContext.injuryRiskFocus) {
            score -= metadata.shoulderRisk * 5
            if metadata.preferredContexts.contains("shoulder_risk") || metadata.preferredContexts.contains("shoulder_friendly") {
                score += 10
            }
            if metadata.avoidContexts.contains("shoulder_risk") {
                score -= 14
            }
        }

        if let focusIntent,
           normalizedPriorityText(focusIntent.area).contains("lateral delt"),
           metadata.preferredContexts.contains("lateral_delt_priority") {
            score += 12
        }

        if canonicalTrainingStyle(selectionContext.style) == "Arms" {
            if metadata.avoidContexts.contains("arms_pump_day") {
                score -= 12
            }
            if metadata.exerciseClass == "Isolation" {
                score += 6
            }
        }

        if metadata.exerciseClass == "Heavy Compound" && selectionContext.calibration.lowPerformanceDataQuality {
            score -= 6
        }

        return score
    }

    func hasShoulderRisk(injuryRiskFocus: String) -> Bool {
        let normalized = normalizedPriorityText(injuryRiskFocus)
        return containsAny(
            normalized,
            keywords: ["shoulder impingement", "internal rotation", "internally rotated", "upper crossed", "shoulder health"]
        )
    }

    // MARK: - Week-over-Week Plan Diff

    func weekDiff(
        currentDays: [WorkoutDayResponse],
        previousDays: [WorkoutDayResponse]
    ) -> [WeekDiffEntry] {
        let currentByStyle = groupedTrainingDaysByStyle(currentDays)
        let previousByStyle = groupedTrainingDaysByStyle(previousDays)
        var entries: [WeekDiffEntry] = []

        for (style, currentStyleDays) in currentByStyle {
            guard let previousStyleDays = previousByStyle[style] else { continue }

            for index in 0..<min(currentStyleDays.count, previousStyleDays.count) {
                let current = currentStyleDays[index]
                let previous = previousStyleDays[index]

                let currentKeys = Dictionary(
                    current.exercises.map { (normalizeExerciseName($0.exerciseName), $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                let previousKeys = Dictionary(
                    previous.exercises.map { (normalizeExerciseName($0.exerciseName), $0) },
                    uniquingKeysWith: { first, _ in first }
                )

                for (key, exercise) in previousKeys where currentKeys[key] == nil {
                    entries.append(WeekDiffEntry(
                        dayNumber: current.dayNumber,
                        dayName: current.dayName,
                        kind: .removed,
                        exerciseName: exercise.exerciseName,
                        detail: "\(exercise.sets) sets × \(exercise.reps)"
                    ))
                }

                for (key, exercise) in currentKeys where previousKeys[key] == nil {
                    entries.append(WeekDiffEntry(
                        dayNumber: current.dayNumber,
                        dayName: current.dayName,
                        kind: .added,
                        exerciseName: exercise.exerciseName,
                        detail: "\(exercise.sets) sets × \(exercise.reps)"
                    ))
                }

                for (key, currentExercise) in currentKeys {
                    guard let previousExercise = previousKeys[key] else { continue }
                    if currentExercise.sets != previousExercise.sets {
                        entries.append(WeekDiffEntry(
                            dayNumber: current.dayNumber,
                            dayName: current.dayName,
                            kind: .setsChanged,
                            exerciseName: currentExercise.exerciseName,
                            detail: "\(previousExercise.sets) → \(currentExercise.sets) sets"
                        ))
                    }
                    if currentExercise.reps != previousExercise.reps {
                        entries.append(WeekDiffEntry(
                            dayNumber: current.dayNumber,
                            dayName: current.dayName,
                            kind: .repsChanged,
                            exerciseName: currentExercise.exerciseName,
                            detail: "\(previousExercise.reps) → \(currentExercise.reps)"
                        ))
                    }
                }
            }
        }

        return entries.sorted { $0.dayNumber < $1.dayNumber }
    }

    // MARK: - Pre-Selected Exercise Menu (deterministic selection layer)

    /// A maintenance budget must constrain exercise identity as well as set dosage. With a
    /// meaningful two-set floor, an 8-set recovery-tight budget can support at most four
    /// movements for a non-priority group; selecting more creates fragmented token work before
    /// the set allocator even runs.
    func maintenanceSlotBudgetAllows(
        candidateName: String,
        candidateTarget: String,
        existingMenus: [[PreSelectedExercise]],
        selectedToday: [(name: String, target: String)],
        blueprint: ProgramBlueprint
    ) -> Bool {
        maintenanceSlotBudgetsAreFeasible(
            existingMenus: existingMenus,
            selectedToday: selectedToday + [(name: candidateName, target: candidateTarget)],
            blueprint: blueprint
        )
    }

    func maintenanceSlotBudgetsAreFeasible(
        existingMenus: [[PreSelectedExercise]],
        selectedToday: [(name: String, target: String)],
        blueprint: ProgramBlueprint
    ) -> Bool {
        let recoveryTight = blueprint.calibration.recoveryConstrained
            || blueprint.calibration.poorNutritionAdherence
        let maintenanceCeiling = recoveryTight ? 8 : 10
        let maxMeaningfulSlots = maintenanceCeiling / 2
        for group in majorMuscleGroups {
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            guard !isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint) else { continue }
            let priorCount = existingMenus.joined().filter {
                exerciseDirectlyTargets(
                    groupAliases: aliases,
                    exerciseName: $0.exerciseName,
                    muscleTarget: $0.muscleTarget
                )
            }.count
            let todayCount = selectedToday.filter {
                exerciseDirectlyTargets(
                    groupAliases: aliases,
                    exerciseName: $0.name,
                    muscleTarget: $0.target
                )
            }.count
            guard priorCount + todayCount <= maxMeaningfulSlots else { return false }
        }
        return true
    }

    func preSelectedExerciseMenu(
        for blueprint: ProgramBlueprint,
        trainingIntent: TrainingIntentPlan,
        weekNumber: Int,
        previousWeekDays: [WorkoutDayResponse]?,
        exerciseHistory: ExerciseHistoryContext? = nil
    ) -> [[PreSelectedExercise]] {
        let previousExercisesByStyle = proceduralPreviousExercisesByStyle(from: previousWeekDays)
        var previousUsageByStyle: [String: Int] = [:]
        var usedAcrossDays = Set<String>()
        var allMenus: [[PreSelectedExercise]] = []

        let avoidedExercises = exerciseHistory?.painExercises ?? []
        let deprioritizedExercises = exerciseHistory?.equipmentSkipExercises ?? []
        let catalogOffset = exerciseHistory.map { variationCatalogOffset(for: $0) } ?? 0

        for plan in blueprint.dayPlans {
            guard !plan.isRestDay else {
                allMenus.append([])
                continue
            }

            let style = plan.style
            let focusIntent = focusIntentForArea(plan.focusArea, within: trainingIntent)
            let supportIntents = plan.supportAreas.compactMap { focusIntentForArea($0, within: trainingIntent) }
            let styleKey = canonicalTrainingStyle(style)
            let styleUsage = previousUsageByStyle[styleKey, default: 0]

            let previousExercises: [WorkoutExerciseResponse] = previousExercisesByStyle[styleKey].flatMap { grouped in
                guard styleUsage < grouped.count else { return nil }
                return grouped[styleUsage]
            } ?? []
            previousUsageByStyle[styleKey] = styleUsage + 1

            let selectionContext = ExerciseSelectionContext(
                calibration: blueprint.calibration,
                injuryRiskFocus: blueprint.injuryRiskFocus,
                targetSessionMinutes: plan.targetSessionMinutes,
                style: style
            )

            let targetCount = weekNumber == 4 ? 5 : 6
            var selected: [(name: String, target: String)] = []
            var used = usedAcrossDays

            let retained = retainedAnchorExercises(from: previousExercises, style: style)
                .filter { exercise in
                    let canonKey = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                    if avoidedExercises.contains(canonKey) { return false }
                    guard let focusIntent else { return true }
                    return focusStimulusKind(
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget,
                        focusArea: focusIntent.area
                    ) != .support
                }
                .prefix(2)
            for exercise in retained {
                let key = normalizeExerciseName(exercise.exerciseName)
                guard !used.contains(key) else { continue }
                guard maintenanceSlotBudgetAllows(
                    candidateName: exercise.exerciseName,
                    candidateTarget: exercise.muscleTarget,
                    existingMenus: allMenus,
                    selectedToday: selected,
                    blueprint: blueprint
                ) else { continue }
                used.insert(key)
                selected.append((exercise.exerciseName, exercise.muscleTarget))
            }
            let retainedCount = selected.count
            let lockedPrefixCount = focusIntent == nil ? retainedCount : 0

            let rawCatalog = orderedExerciseCatalog(
                for: style,
                focusIntent: focusIntent,
                selectionContext: selectionContext
            )
            let catalog = applyHistoryFilters(
                rawCatalog,
                avoidedExercises: avoidedExercises,
                deprioritizedExercises: deprioritizedExercises,
                catalogOffset: catalogOffset,
                weekNumber: weekNumber,
                priorMesocycleExercises: exerciseHistory?.priorMesocycleExercises ?? []
            )
            for candidate in catalog where selected.count < targetCount {
                let key = normalizeExerciseName(candidate.name)
                guard !used.contains(key) else { continue }
                guard dayPatternCapAllows(candidateName: candidate.name, candidateTarget: candidate.target, in: selected) else { continue }
                guard maintenanceSlotBudgetAllows(
                    candidateName: candidate.name,
                    candidateTarget: candidate.target,
                    existingMenus: allMenus,
                    selectedToday: selected,
                    blueprint: blueprint
                ) else { continue }
                used.insert(key)
                selected.append((candidate.name, candidate.target))
            }

            if selected.count < 5 {
                let rawGeneric = orderedGenericExerciseCatalog(
                    focusIntent: focusIntent,
                    selectionContext: selectionContext
                )
                let generic = applyHistoryFilters(
                    rawGeneric,
                    avoidedExercises: avoidedExercises,
                    deprioritizedExercises: deprioritizedExercises,
                    catalogOffset: catalogOffset,
                    weekNumber: weekNumber,
                    priorMesocycleExercises: exerciseHistory?.priorMesocycleExercises ?? []
                )
                for candidate in generic where selected.count < 5 {
                    let key = normalizeExerciseName(candidate.name)
                    guard !used.contains(key) else { continue }
                    // The generic catalog spans all styles; without this check a depleted
                    // Push day can be topped up with a hinge or squat, which the locked
                    // menu then forces into the session.
                    let probe = WorkoutExerciseResponse(
                        exerciseName: candidate.name,
                        sets: 3,
                        reps: "10-12",
                        tempo: "",
                        restSeconds: 60,
                        notes: "",
                        muscleTarget: candidate.target
                    )
                    guard exerciseMatchesDayStyle(probe, style: styleKey) else { continue }
                    guard dayPatternCapAllows(candidateName: candidate.name, candidateTarget: candidate.target, in: selected) else { continue }
                    guard maintenanceSlotBudgetAllows(
                        candidateName: candidate.name,
                        candidateTarget: candidate.target,
                        existingMenus: allMenus,
                        selectedToday: selected,
                        blueprint: blueprint
                    ) else { continue }
                    used.insert(key)
                    selected.append((candidate.name, candidate.target))
                }
            }

            // Last resort: relax cross-day uniqueness (a movement may repeat on a second
            // same-style day) rather than emit a menu with fewer than 5 exercises. A short
            // menu is a validator HARD failure, and because the procedural fallback consumes
            // this same menu, it becomes a deterministic, retry-proof generation dead-end.
            // Pain-avoided movements stay excluded (`catalog` is already history-filtered).
            if selected.count < 5 {
                // First sweep honors the within-day pattern cap; the uncapped second sweep
                // only runs if the menu is still short, because a <5 menu is a validator
                // hard failure and a deterministic dead-end that outranks pattern hygiene.
                for candidate in catalog where selected.count < 5 {
                    let key = normalizeExerciseName(candidate.name)
                    guard !selected.contains(where: { normalizeExerciseName($0.name) == key }) else { continue }
                    guard dayPatternCapAllows(candidateName: candidate.name, candidateTarget: candidate.target, in: selected) else { continue }
                    guard maintenanceSlotBudgetAllows(
                        candidateName: candidate.name,
                        candidateTarget: candidate.target,
                        existingMenus: allMenus,
                        selectedToday: selected,
                        blueprint: blueprint
                    ) else { continue }
                    selected.append((candidate.name, candidate.target))
                }
                for candidate in catalog where selected.count < 5 {
                    let key = normalizeExerciseName(candidate.name)
                    guard !selected.contains(where: { normalizeExerciseName($0.name) == key }) else { continue }
                    guard maintenanceSlotBudgetAllows(
                        candidateName: candidate.name,
                        candidateTarget: candidate.target,
                        existingMenus: allMenus,
                        selectedToday: selected,
                        blueprint: blueprint
                    ) else { continue }
                    selected.append((candidate.name, candidate.target))
                }
            }

            if let focusIntent {
                selected = enforceFocusExerciseCoverage(
                    selected,
                    targetCount: focusExerciseTargetCount(for: focusIntent),
                    focusIntent: focusIntent,
                    selectionLimit: targetCount,
                    protectedPrefixCount: retainedCount,
                    usedAcrossDays: usedAcrossDays,
                    avoidedExercises: avoidedExercises,
                    selectionAllowed: {
                        self.maintenanceSlotBudgetsAreFeasible(
                            existingMenus: allMenus,
                            selectedToday: $0,
                            blueprint: blueprint
                        )
                    }
                )
            }

            if !supportIntents.isEmpty {
                selected = enforceSupportExerciseCoverage(
                    selected,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents,
                    selectionLimit: targetCount,
                    protectedPrefixCount: retainedCount,
                    usedAcrossDays: usedAcrossDays,
                    avoidedExercises: avoidedExercises,
                    selectionAllowed: {
                        self.maintenanceSlotBudgetsAreFeasible(
                            existingMenus: allMenus,
                            selectedToday: $0,
                            blueprint: blueprint
                        )
                    }
                )
            }

            let arranged = arrangeProceduralSelection(
                Array(selected.prefix(targetCount)),
                lockedPrefixCount: lockedPrefixCount,
                focusIntent: focusIntent
            )

            for item in arranged {
                usedAcrossDays.insert(normalizeExerciseName(item.name))
            }

            allMenus.append(arranged.map { item in
                let metadata = exerciseMetadata(forExerciseName: item.name, muscleTarget: item.target)
                let role = proceduralExerciseRole(for: item.name, muscleTarget: item.target)
                return PreSelectedExercise(
                    exerciseName: item.name,
                    muscleTarget: item.target,
                    movementPattern: metadata.movementPattern,
                    role: role,
                    prescribedSets: 1
                )
            })
        }

        let coverageCompleteMenus = enforceBaselineMuscleCoverage(
            allMenus,
            blueprint: blueprint,
            trainingIntent: trainingIntent,
            avoidedExercises: avoidedExercises
        )
        return allocateWeeklySetPrescription(
            coverageCompleteMenus,
            blueprint: blueprint,
            weekNumber: weekNumber
        )
    }

    // MARK: - BASE-001 Baseline Muscle Coverage (menu-level floor)

    /// EvidenceProfile.md BASE-001 [confidence: high]. The per-day selection above only
    /// enforces focus/support coverage, so a whole week could ship with zero direct work
    /// for an unlisted muscle (seen live: no hamstring exposure all week while calves got
    /// 6 sets). For every non-priority major muscle group with zero direct coverage, swap
    /// one redundant slot for the lowest-fatigue direct movement on a style-compatible day.
    func enforceBaselineMuscleCoverage(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        trainingIntent: TrainingIntentPlan,
        avoidedExercises: Set<String>
    ) -> [[PreSelectedExercise]] {
        var updated = menus
        var usedKeys = Set(menus.joined().map { normalizeExerciseName($0.exerciseName) })
        for group in majorMuscleGroups {
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            guard !isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint) else { continue }

            let covered = updated.joined().contains { exercise in
                exerciseDirectlyTargets(
                    groupAliases: aliases,
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget
                )
            }
            guard !covered else { continue }

            candidateSearch: for candidate in metadataFocusExerciseCatalog(for: group.seed) {
                let key = normalizeExerciseName(candidate.name)
                guard !usedKeys.contains(key) else { continue }
                guard !avoidedExercises.contains(ExerciseWeightEntry.canonicalLookupKey(candidate.name)) else { continue }
                guard exerciseDirectlyTargets(
                    groupAliases: aliases,
                    exerciseName: candidate.name,
                    muscleTarget: candidate.target
                ) else { continue }

                let probe = WorkoutExerciseResponse(
                    exerciseName: candidate.name,
                    sets: 3,
                    reps: "10-12",
                    tempo: "",
                    restSeconds: 60,
                    notes: "",
                    muscleTarget: candidate.target
                )

                for (dayOffset, plan) in blueprint.dayPlans.enumerated()
                where !plan.isRestDay && dayOffset < updated.count && !updated[dayOffset].isEmpty {
                    guard exerciseMatchesDayStyle(probe, style: canonicalTrainingStyle(plan.style)) else { continue }

                    let focusIntent = focusIntentForArea(plan.focusArea, within: trainingIntent)
                    let supportIntents = plan.supportAreas.compactMap { focusIntentForArea($0, within: trainingIntent) }
                    guard let replaceIndex = baselineCoverageReplacementIndex(
                        in: updated[dayOffset],
                        focusIntent: focusIntent,
                        supportIntents: supportIntents
                    ) else { continue }
                    var menusWithoutReplacedSlot = updated
                    menusWithoutReplacedSlot[dayOffset].remove(at: replaceIndex)
                    guard maintenanceSlotBudgetAllows(
                        candidateName: candidate.name,
                        candidateTarget: candidate.target,
                        existingMenus: menusWithoutReplacedSlot,
                        selectedToday: [],
                        blueprint: blueprint
                    ) else { continue }

                    let metadata = exerciseMetadata(forExerciseName: candidate.name, muscleTarget: candidate.target)
                    updated[dayOffset][replaceIndex] = PreSelectedExercise(
                        exerciseName: candidate.name,
                        muscleTarget: candidate.target,
                        movementPattern: metadata.movementPattern,
                        role: proceduralExerciseRole(for: candidate.name, muscleTarget: candidate.target),
                        prescribedSets: 1
                    )
                    usedKeys.insert(key)
                    break candidateSearch
                }
            }
        }

        return updated
    }

    // MARK: - Weekly Set Allocation

    /// Owns weekly dosage before the locked menu reaches either Claude or procedural fallback.
    /// Priority targets are funded first; remaining movements can grow only while every
    /// non-priority major muscle they directly train remains inside its maintenance budget.
    func allocateWeeklySetPrescription(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        weekNumber: Int
    ) -> [[PreSelectedExercise]] {
        var allocated = menus.map { menu in
            menu.map { exercise in
                var seeded = exercise
                seeded.prescribedSets = 1
                return seeded
            }
        }
        let recoveryTight = blueprint.calibration.recoveryConstrained
            || blueprint.calibration.poorNutritionAdherence
        let maintenanceCeiling = recoveryTight ? 8.0 : 10.0
        let maintenanceGroups = majorMuscleGroups.compactMap { group -> (label: String, aliases: Set<String>)? in
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            guard !isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint) else { return nil }
            return (group.label, aliases)
        }

        func response(dayIndex: Int, exerciseIndex: Int, addingSet: Bool = false) -> WorkoutExerciseResponse {
            let exercise = allocated[dayIndex][exerciseIndex]
            let sets = exercise.prescribedSets + (addingSet ? 1 : 0)
            let reps = proceduralRepRange(
                for: weekNumber,
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            )
            return WorkoutExerciseResponse(
                exerciseName: exercise.exerciseName,
                sets: sets,
                reps: reps,
                tempo: proceduralTempo(
                    for: weekNumber,
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget,
                    reps: reps
                ),
                restSeconds: proceduralRestSeconds(
                    for: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget
                ),
                notes: "",
                muscleTarget: exercise.muscleTarget
            )
        }

        func maintenanceSets(for aliases: Set<String>, addingAt location: (Int, Int)? = nil) -> Double {
            allocated.indices.reduce(0.0) { weekTotal, dayIndex in
                weekTotal + allocated[dayIndex].indices.reduce(0.0) { dayTotal, exerciseIndex in
                    let exercise = allocated[dayIndex][exerciseIndex]
                    guard exerciseDirectlyTargets(
                        groupAliases: aliases,
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget
                    ) else { return dayTotal }
                    let extra = location?.0 == dayIndex && location?.1 == exerciseIndex ? 1 : 0
                    return dayTotal + Double(exercise.prescribedSets + extra)
                }
            }
        }

        func priorityCoverage(
            for allocation: BlueprintPriorityAllocation,
            addingAt location: (Int, Int)? = nil
        ) -> (direct: Double, weighted: Double) {
            var direct = 0.0
            var weighted = 0.0
            for dayIndex in allocated.indices {
                for exerciseIndex in allocated[dayIndex].indices {
                    let exercise = response(
                        dayIndex: dayIndex,
                        exerciseIndex: exerciseIndex,
                        addingSet: location?.0 == dayIndex && location?.1 == exerciseIndex
                    )
                    direct += directSetCredit(for: exercise, area: allocation.area)
                    weighted += weightedStimulusCredit(for: exercise, area: allocation.area)
                }
            }
            return (direct, weighted)
        }

        func canAddSet(dayIndex: Int, exerciseIndex: Int) -> Bool {
            let exercise = allocated[dayIndex][exerciseIndex]
            let roleDefault = proceduralSets(
                for: weekNumber,
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            )
            guard exercise.prescribedSets < roleDefault else { return false }

            for group in maintenanceGroups where exerciseDirectlyTargets(
                groupAliases: group.aliases,
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            ) {
                guard maintenanceSets(
                    for: group.aliases,
                    addingAt: (dayIndex, exerciseIndex)
                ) <= maintenanceCeiling + 0.01 else { return false }
            }

            // A set funded for one priority may also credit another. Check every weekly ledger
            // jointly so shared Chest/Triceps or Quads/Glutes work cannot overfill a later
            // priority before its own allocation pass begins.
            for allocation in blueprint.priorityAllocations {
                let current = priorityCoverage(for: allocation)
                let projected = priorityCoverage(
                    for: allocation,
                    addingAt: (dayIndex, exerciseIndex)
                )
                let addsDirectCredit = projected.direct > current.direct + 0.01
                guard !addsDirectCredit
                        || projected.direct <= allocation.directSetTarget + 0.01 else {
                    return false
                }
            }

            guard dayIndex < blueprint.dayPlans.count else { return false }
            let plan = blueprint.dayPlans[dayIndex]
            let dayExercises = allocated[dayIndex].indices.map { index in
                response(
                    dayIndex: dayIndex,
                    exerciseIndex: index,
                    addingSet: index == exerciseIndex
                )
            }
            guard estimatedDayFatigue(for: dayExercises) <= plan.targetFatigueCap else { return false }
            guard estimatedSessionMinutes(for: proceduralTrainingDay(from: dayExercises))
                    <= plan.targetSessionMinutes + 3 else { return false }

            for allocation in blueprint.priorityAllocations {
                let candidate = response(
                    dayIndex: dayIndex,
                    exerciseIndex: exerciseIndex,
                    addingSet: true
                )
                guard directSetCredit(for: candidate, area: allocation.area) > 0 else { continue }
                let dayDirectSets = dayExercises.reduce(0.0) {
                    $0 + directSetCredit(for: $1, area: allocation.area)
                }
                let isFocusDay = plan.focusArea.map {
                    normalizedPriorityText($0) == normalizedPriorityText(allocation.area)
                } ?? false
                let cap = isFocusDay
                    ? allocation.maxFocusSessionDirectSets
                    : allocation.maxPerSessionDirectSets
                guard dayDirectSets <= cap + 0.01 else { return false }
            }

            return true
        }

        // Fund blueprint priorities before distributing maintenance volume.
        for allocation in blueprint.priorityAllocations {
            let meaningfulThreshold = minimumMeaningfulPriorityExposureSets(for: allocation.area)
            let candidateDays = allocated.indices
                .filter { dayIndex in
                    allocated[dayIndex].indices.contains { exerciseIndex in
                        directSetCredit(
                            for: response(dayIndex: dayIndex, exerciseIndex: exerciseIndex),
                            area: allocation.area
                        ) > 0
                    }
                }
                .sorted { lhs, rhs in
                    let lhsFocus = blueprint.dayPlans[lhs].focusArea.map {
                        normalizedPriorityText($0) == normalizedPriorityText(allocation.area)
                    } ?? false
                    let rhsFocus = blueprint.dayPlans[rhs].focusArea.map {
                        normalizedPriorityText($0) == normalizedPriorityText(allocation.area)
                    } ?? false
                    if lhsFocus != rhsFocus { return lhsFocus }
                    return lhs < rhs
                }

            // Establish distinct meaningful exposures first so the weekly total cannot be
            // concentrated into one impressive-looking day while frequency quietly misses.
            for dayIndex in candidateDays.prefix(allocation.targetFrequency) {
                var exposureGuardRail = 12
                while exposureGuardRail > 0 {
                    exposureGuardRail -= 1
                    let dayDirectSets = allocated[dayIndex].indices.reduce(0.0) {
                        $0 + directSetCredit(
                            for: response(dayIndex: dayIndex, exerciseIndex: $1),
                            area: allocation.area
                        )
                    }
                    guard dayDirectSets + 0.01 < meaningfulThreshold else { break }

                    let candidates = allocated[dayIndex].indices.compactMap { exerciseIndex -> (Int, Int)? in
                        guard canAddSet(dayIndex: dayIndex, exerciseIndex: exerciseIndex) else { return nil }
                        let probe = response(dayIndex: dayIndex, exerciseIndex: exerciseIndex, addingSet: true)
                        guard directSetCredit(for: probe, area: allocation.area) > 0 else { return nil }
                        let kind = focusStimulusKind(
                            exerciseName: probe.exerciseName,
                            muscleTarget: probe.muscleTarget,
                            focusArea: allocation.area
                        )
                        let qualityScore: Int
                        switch kind {
                        case .prime: qualityScore = 30
                        case .secondary: qualityScore = 20
                        case .support: qualityScore = 10
                        case .none: qualityScore = 0
                        }
                        return (exerciseIndex, qualityScore - allocated[dayIndex][exerciseIndex].prescribedSets)
                    }
                    guard let target = candidates.max(by: { $0.1 < $1.1 }) else { break }
                    allocated[dayIndex][target.0].prescribedSets += 1
                }
            }

            var guardRail = 80
            while guardRail > 0 {
                guardRail -= 1
                let current = priorityCoverage(for: allocation)
                guard current.direct + 0.01 < allocation.directSetTarget
                        || current.weighted + 0.01 < allocation.weightedStimulusTarget else { break }

                let candidates = allocated.indices.flatMap { dayIndex in
                    allocated[dayIndex].indices.compactMap { exerciseIndex -> (Int, Int, Int)? in
                        guard canAddSet(dayIndex: dayIndex, exerciseIndex: exerciseIndex) else { return nil }
                        let probe = response(dayIndex: dayIndex, exerciseIndex: exerciseIndex, addingSet: true)
                        let credit = stimulusCredit(for: probe, area: allocation.area)
                        guard credit.directSets > 0 || credit.weightedStimulus > 0 else { return nil }
                        let kind = focusStimulusKind(
                            exerciseName: probe.exerciseName,
                            muscleTarget: probe.muscleTarget,
                            focusArea: allocation.area
                        )
                        let qualityScore: Int
                        switch kind {
                        case .prime: qualityScore = 30
                        case .secondary: qualityScore = 20
                        case .support: qualityScore = 10
                        case .none: qualityScore = 0
                        }
                        let focusBonus = blueprint.dayPlans[dayIndex].focusArea.map {
                            normalizedPriorityText($0) == normalizedPriorityText(allocation.area) ? 5 : 0
                        } ?? 0
                        return (dayIndex, exerciseIndex, qualityScore + focusBonus - allocated[dayIndex][exerciseIndex].prescribedSets)
                    }
                }
                guard let target = candidates.max(by: { $0.2 < $1.2 }) else { break }
                allocated[target.0][target.1].prescribedSets += 1
            }
        }

        // Fill useful maintenance work toward role defaults without ever exceeding a
        // shared weekly budget. Multi-primary exercises debit every affected group.
        var madeProgress = true
        var guardRail = 160
        while madeProgress && guardRail > 0 {
            guardRail -= 1
            madeProgress = false
            for dayIndex in allocated.indices {
                for exerciseIndex in allocated[dayIndex].indices {
                    let exercise = allocated[dayIndex][exerciseIndex]
                    let targetsMaintenance = maintenanceGroups.contains { group in
                        exerciseDirectlyTargets(
                            groupAliases: group.aliases,
                            exerciseName: exercise.exerciseName,
                            muscleTarget: exercise.muscleTarget
                        )
                    }
                    guard targetsMaintenance else { continue }
                    guard canAddSet(dayIndex: dayIndex, exerciseIndex: exerciseIndex) else { continue }
                    allocated[dayIndex][exerciseIndex].prescribedSets += 1
                    madeProgress = true
                }
            }
        }

        return allocated
    }

    /// Slot the coverage pass may sacrifice: prefer the last exercise whose movement
    /// pattern is already duplicated in the session, never a focus/support match, never
    /// an anchor. Returns nil when the day has nothing expendable.
    func baselineCoverageReplacementIndex(
        in menu: [PreSelectedExercise],
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent]
    ) -> Int? {
        let patternCounts = Dictionary(grouping: menu.indices, by: { menu[$0].movementPattern })
            .mapValues(\.count)

        func matchesDayIntent(_ exercise: PreSelectedExercise) -> Bool {
            if let focusIntent,
               exerciseMatchesTrainingIntent(
                   name: exercise.exerciseName,
                   target: exercise.muscleTarget,
                   intent: focusIntent
               ) {
                return true
            }
            return supportIntents.contains { intent in
                exerciseMatchesTrainingIntent(
                    name: exercise.exerciseName,
                    target: exercise.muscleTarget,
                    intent: intent
                )
            }
        }

        if let redundantIndex = menu.indices.reversed().first(where: { index in
            patternCounts[menu[index].movementPattern, default: 0] > 1
                && !matchesDayIntent(menu[index])
                && menu[index].role != .anchor
        }) {
            return redundantIndex
        }

        return menu.indices.reversed().first { index in
            !matchesDayIntent(menu[index])
                && (menu[index].role == .accessory || menu[index].role == .core)
        }
    }

    // MARK: - Phase 2: Exercise History Filtering

    func applyHistoryFilters(
        _ catalog: [(name: String, target: String)],
        avoidedExercises: Set<String>,
        deprioritizedExercises: Set<String>,
        catalogOffset: Int,
        weekNumber: Int,
        priorMesocycleExercises: Set<String>
    ) -> [(name: String, target: String)] {
        let filtered = catalog.filter { item in
            !avoidedExercises.contains(ExerciseWeightEntry.canonicalLookupKey(item.name))
        }

        guard filtered.count > 1 else { return filtered }

        let accessoryStartIndex = filtered.firstIndex { item in
            let role = proceduralExerciseRole(for: item.name, muscleTarget: item.target)
            return role == .accessory || role == .core
        } ?? filtered.count

        let anchors = Array(filtered.prefix(accessoryStartIndex))
        var accessories = Array(filtered.dropFirst(accessoryStartIndex))

        if catalogOffset > 0 && accessories.count > 1 {
            let shift = catalogOffset % accessories.count
            if shift > 0 {
                accessories = Array(accessories[shift...]) + Array(accessories[..<shift])
            }
        }

        var result = anchors + accessories

        let anchorCount = anchors.count
        for i in result.indices.reversed() where i >= anchorCount {
            let canonKey = ExerciseWeightEntry.canonicalLookupKey(result[i].name)
            if deprioritizedExercises.contains(canonKey) {
                let item = result.remove(at: i)
                result.append(item)
            }
        }

        return result
    }

    func variationCatalogOffset(for history: ExerciseHistoryContext) -> Int {
        guard history.mesocycleIndex > 0 else { return 0 }
        return history.mesocycleIndex
    }

}
