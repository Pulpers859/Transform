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
        targetFatigueCap: Int,
        targetSessionMinutes: Int? = nil
    ) -> [WorkoutExerciseResponse] {
        var balanced = exercises

        if let focusIntent {
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

    func preSelectedExerciseMenu(
        for blueprint: ProgramBlueprint,
        trainingIntent: TrainingIntentPlan,
        weekNumber: Int,
        previousWeekDays: [WorkoutDayResponse]?
    ) -> [[PreSelectedExercise]] {
        let previousExercisesByStyle = proceduralPreviousExercisesByStyle(from: previousWeekDays)
        var previousUsageByStyle: [String: Int] = [:]

        return blueprint.dayPlans.map { plan in
            guard !plan.isRestDay else { return [] }

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
            var used = Set<String>()

            let retained = retainedAnchorExercises(from: previousExercises, style: style)
                .filter { exercise in
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
                used.insert(key)
                selected.append((exercise.exerciseName, exercise.muscleTarget))
            }
            let lockedPrefixCount = focusIntent == nil ? selected.count : 0

            let catalog = orderedExerciseCatalog(
                for: style,
                focusIntent: focusIntent,
                selectionContext: selectionContext
            )
            for candidate in catalog where selected.count < targetCount {
                let key = normalizeExerciseName(candidate.name)
                guard !used.contains(key) else { continue }
                used.insert(key)
                selected.append((candidate.name, candidate.target))
            }

            if selected.count < 5 {
                for candidate in orderedGenericExerciseCatalog(
                    focusIntent: focusIntent,
                    selectionContext: selectionContext
                ) where selected.count < 5 {
                    let key = normalizeExerciseName(candidate.name)
                    guard !used.contains(key) else { continue }
                    used.insert(key)
                    selected.append((candidate.name, candidate.target))
                }
            }

            if let focusIntent {
                selected = enforceFocusExerciseCoverage(
                    selected,
                    targetCount: focusExerciseTargetCount(for: focusIntent),
                    focusIntent: focusIntent,
                    selectionLimit: targetCount
                )
            }

            if !supportIntents.isEmpty {
                selected = enforceSupportExerciseCoverage(
                    selected,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents,
                    selectionLimit: targetCount
                )
            }

            let arranged = arrangeProceduralSelection(
                Array(selected.prefix(8)),
                lockedPrefixCount: lockedPrefixCount,
                focusIntent: focusIntent
            )

            return arranged.map { item in
                let metadata = exerciseMetadata(forExerciseName: item.name, muscleTarget: item.target)
                let role = proceduralExerciseRole(for: item.name, muscleTarget: item.target)
                return PreSelectedExercise(
                    exerciseName: item.name,
                    muscleTarget: item.target,
                    movementPattern: metadata.movementPattern,
                    role: role
                )
            }
        }
    }

}
