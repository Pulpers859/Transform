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
        let exposures = max(1, intent.weeklyDayTarget)
        let perSessionTarget = Int(ceil(Double(intent.weeklyExerciseTarget) / Double(exposures)))
        return max(1, min(3, perSessionTarget))
    }

    func enforceFocusExerciseCoverage(
        _ selected: [(name: String, target: String)],
        targetCount: Int,
        focusIntent: MusclePriorityIntent,
        selectionLimit: Int
    ) -> [(name: String, target: String)] {
        var result = selected

        func focusMatchCount(in exercises: [(name: String, target: String)]) -> Int {
            exercises.filter { exerciseMatchesTrainingIntent(name: $0.name, target: $0.target, intent: focusIntent) }.count
        }

        for candidate in priorityAccessoryCatalog(for: focusIntent) {
            guard focusMatchCount(in: result) < targetCount else { break }
            let candidateKey = normalizeExerciseName(candidate.name)
            guard !result.contains(where: { normalizeExerciseName($0.name) == candidateKey }) else { continue }

            if result.count >= selectionLimit {
                guard let removalIndex = result.indices.reversed().first(where: { index in
                    !exerciseMatchesTrainingIntent(name: result[index].name, target: result[index].target, intent: focusIntent)
                }) else {
                    break
                }
                result.remove(at: removalIndex)
            }

            result.append(candidate)
        }

        return result
    }

    func enforceSupportExerciseCoverage(
        _ selected: [(name: String, target: String)],
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        selectionLimit: Int
    ) -> [(name: String, target: String)] {
        var result = selected

        for supportIntent in supportIntents {
            let alreadyCovered = result.contains {
                exerciseMatchesTrainingIntent(name: $0.name, target: $0.target, intent: supportIntent)
            }
            if alreadyCovered { continue }

            for candidate in priorityAccessoryCatalog(for: supportIntent) {
                let candidateKey = normalizeExerciseName(candidate.name)
                guard !result.contains(where: { normalizeExerciseName($0.name) == candidateKey }) else { continue }

                if result.count >= selectionLimit {
                    guard let removalIndex = result.indices.reversed().first(where: { index in
                        if let focusIntent,
                           exerciseMatchesTrainingIntent(
                               name: result[index].name,
                               target: result[index].target,
                               intent: focusIntent
                           ) {
                            return false
                        }
                        return !supportIntents.contains { intent in
                            exerciseMatchesTrainingIntent(
                                name: result[index].name,
                                target: result[index].target,
                                intent: intent
                            )
                        }
                    }) else {
                        break
                    }
                    result.remove(at: removalIndex)
                }

                result.append(candidate)
                break
            }
        }

        return result
    }

    func balancedProceduralExercises(
        _ exercises: [WorkoutExerciseResponse],
        weekNumber: Int,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        targetFatigueCap: Int
    ) -> [WorkoutExerciseResponse] {
        var balanced = exercises

        if let focusIntent {
            let focusCap = blueprintAllocation(for: focusIntent).maxFocusSessionDirectSets
            balanced = rebalanceDirectSets(
                in: balanced,
                for: focusIntent,
                allowedCap: focusCap
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

        return balanced
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
        focusIntent: MusclePriorityIntent?
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
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func orderedGenericExerciseCatalog(
        focusIntent: MusclePriorityIntent?
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
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

}
