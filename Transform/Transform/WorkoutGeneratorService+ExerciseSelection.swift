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
            muscleTarget: exercise.muscleTarget,
            targetRIR: exercise.targetRIR,
            // Set-count adjustment does not change who wrote the note. This helper is the
            // shared rebuild path for repair and trimming, so dropping provenance here would
            // erase it from every repaired day at once.
            coachingSource: exercise.coachingSource
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

    /// Where an exercise sits in the session's coarse running order, per EvidenceProfile.md
    /// ORD-001: anchor compounds first, the secondary/accessory body of the session next, direct
    /// core last.
    ///
    /// This band is the OUTER sort key in `arrangeProceduralSelection`, and focus ordering only
    /// applies WITHIN it. That relationship is the whole point. Focus ordering used to be the
    /// outer key, so a day's focus area could hoist a small isolation ahead of the session's
    /// heaviest lift: a Legs day carrying the week's Core/Abs focus shipped `Hanging Knee Raise`
    /// in slot 1 and `Trap Bar Deadlift` in slot 2 — direct trunk flexion immediately before a
    /// loaded hinge, for a lifter the same analysis had flagged for bracing and pelvic position.
    /// The AI path inherits menu order verbatim (the menu is locked and the prompt says to keep
    /// the order given), so nothing downstream could undo it.
    ///
    /// ORD-001's "unless the day is explicitly core-biased" clause survives as `dayHasAnchor`. A
    /// session with no anchor compound genuinely IS built around its small work, so core may lead
    /// there. A session containing a heavy compound is not that day, whatever its focus tag says.
    func sessionOrderingBand(role: ProceduralExerciseRole, dayHasAnchor: Bool) -> Int {
        switch role {
        case .anchor:
            return 0
        case .secondary, .accessory:
            return 1
        case .core:
            return dayHasAnchor ? 2 : 1
        }
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

        // Read from the WHOLE day, not just the sortable tail: a retained anchor sitting in the
        // locked prefix still makes this a session with a heavy lift in it, and core must not be
        // promoted to the front on the strength of the tail happening to look small.
        let dayHasAnchor = exercises.contains { exercise in
            proceduralExerciseRole(for: exercise.name, muscleTarget: exercise.target) == .anchor
        }

        let orderedRemaining = remaining
            .enumerated()
            .sorted { lhs, rhs in
                let lhsRole = proceduralExerciseRole(for: lhs.element.name, muscleTarget: lhs.element.target)
                let rhsRole = proceduralExerciseRole(for: rhs.element.name, muscleTarget: rhs.element.target)

                let lhsBand = sessionOrderingBand(role: lhsRole, dayHasAnchor: dayHasAnchor)
                let rhsBand = sessionOrderingBand(role: rhsRole, dayHasAnchor: dayHasAnchor)
                if lhsBand != rhsBand { return lhsBand < rhsBand }

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

    /// Free-standing barbell squats — the axial-loaded, high-skill squat variants capped at
    /// ONE per session (SEQ-001). Machine/guided/implement squats (hack, pendulum, sissy,
    /// belt, Smith, goblet, landmine, dumbbell, kettlebell) are NOT free-barbell squats even
    /// though they share the "Squat" movement pattern, and leg presses live in the separate
    /// "Press" pattern entirely — none of those trip this cap.
    func isFreeBarbellSquat(exerciseName: String, muscleTarget: String) -> Bool {
        guard menuMovementPattern(forExerciseName: exerciseName, muscleTarget: muscleTarget) == "Squat" else {
            return false
        }
        let name = normalizeExerciseName(exerciseName)
        guard name.contains("squat") else { return false }
        let guidedOrImplementSignals = [
            "hack", "pendulum", "sissy", "belt", "smith", "machine",
            "goblet", "landmine", "dumbbell", "kettlebell"
        ]
        return !guidedOrImplementSignals.contains { name.contains($0) }
    }

    /// Wording that changes only how you HOLD a movement, not what the movement is.
    ///
    /// Deliberately NOT a general "these names look similar" list, and the exclusions are the
    /// load-bearing part. Stance words stay out because Standing and Seated Calf Raise train
    /// different muscles (gastrocnemius vs soleus). Unilateral words stay out because a
    /// single-leg or single-arm version is a genuinely different demand, not a relabelling.
    /// Implement words ("machine", "dumbbell", "cable") stay out because swapping the implement
    /// is normal, useful variation. Only grips and handles belong here.
    var gripVariantQualifiers: [String] {
        [
            "neutral grip", "wide grip", "close grip", "narrow grip", "reverse grip",
            "underhand", "overhand", "supinated", "pronated",
            "rope", "v bar", "ez bar", "straight bar"
        ]
    }

    /// An exercise name with its grip/handle wording removed, used ONLY to recognise two
    /// spellings of one movement inside a single session.
    func gripVariantStem(forExerciseName name: String) -> String {
        var words = normalizeExerciseName(name)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }

        for qualifier in gripVariantQualifiers {
            let phrase = qualifier.components(separatedBy: " ").filter { !$0.isEmpty }
            guard !phrase.isEmpty else { continue }
            // Never strip a name down to nothing or to a single generic word: what survives has
            // to still name a movement. "EZ-Bar Curl" reducing to "curl" would collide with
            // every other curl in the catalogue, which is the opposite of the intent.
            guard words.count > phrase.count + 1 else { continue }
            let lastStart = words.count - phrase.count
            guard let start = (0...lastStart).first(where: { index in
                Array(words[index..<(index + phrase.count)]) == phrase
            }) else { continue }
            words.removeSubrange(start..<(start + phrase.count))
        }

        return words.joined(separator: " ")
    }

    /// Whether two exercises are the same movement wearing two labels: same movement pattern,
    /// same primary muscles, and identical names once grip/handle wording is removed.
    ///
    /// Live example this exists for: a single Upper day shipped `Lat Pulldown` (3 sets) and
    /// `Neutral-Grip Lat Pulldown` (3 sets) back to back with identical reps, rest, tempo and
    /// effort target — six sets spent on one exercise while the same week contained no rowing
    /// at all. The two-per-pattern cap allowed it because they are exactly two.
    ///
    /// All three conditions are required. Pattern alone would block Standing + Seated Calf
    /// Raise; primary muscles alone would block a barbell and a machine version of the same
    /// press. The stem comparison is what separates "another way to train this" from "the same
    /// thing twice".
    func isGripVariantDuplicate(
        candidateName: String,
        candidateTarget: String,
        of otherName: String,
        otherTarget: String
    ) -> Bool {
        guard let candidatePattern = menuMovementPattern(
            forExerciseName: candidateName,
            muscleTarget: candidateTarget
        ), candidatePattern != "Unknown" else { return false }
        guard let otherPattern = menuMovementPattern(
            forExerciseName: otherName,
            muscleTarget: otherTarget
        ), candidatePattern == otherPattern else { return false }

        let candidateMetadata = exerciseMetadata(
            forExerciseName: candidateName,
            muscleTarget: candidateTarget
        )
        let otherMetadata = exerciseMetadata(
            forExerciseName: otherName,
            muscleTarget: otherTarget
        )
        let candidateAreas = Set(candidateMetadata.primaryAreas.map(normalizedPriorityText))
        guard !candidateAreas.isEmpty,
              candidateAreas == Set(otherMetadata.primaryAreas.map(normalizedPriorityText))
        else { return false }

        let candidateStem = gripVariantStem(forExerciseName: candidateName)
        guard !candidateStem.isEmpty else { return false }
        return candidateStem == gripVariantStem(forExerciseName: otherName)
    }

    /// A single session gets at most 2 exercises of the same movement pattern. This is the
    /// selection-time guard against menus like four vertical pulls or three flat presses in
    /// one day — previously only penalized during fatigue trimming, never prevented.
    ///
    /// Free-barbell squats carry a stricter cap of ONE (SEQ-001): two axial-loaded free
    /// squats back-to-back (e.g. Back Squat + Front Squat) are redundant quad stimulus at
    /// high skill and systemic-fatigue cost. Stable machine/guided squats and leg presses
    /// are exempt, so a barbell squat can still be paired with a hack squat or leg press.
    ///
    /// Grip variants of one movement are capped at ONE regardless of pattern budget — see
    /// `isGripVariantDuplicate`. Two of them are not two exercises.
    func dayPatternCapAllows(
        candidateName: String,
        candidateTarget: String,
        in selected: [(name: String, target: String)]
    ) -> Bool {
        let duplicatesAnExistingGrip = selected.contains { existing in
            isGripVariantDuplicate(
                candidateName: candidateName,
                candidateTarget: candidateTarget,
                of: existing.name,
                otherTarget: existing.target
            )
        }
        if duplicatesAnExistingGrip { return false }

        if isFreeBarbellSquat(exerciseName: candidateName, muscleTarget: candidateTarget) {
            let barbellSquatsAlready = selected.contains {
                isFreeBarbellSquat(exerciseName: $0.name, muscleTarget: $0.target)
            }
            if barbellSquatsAlready { return false }
        }

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
        // Catalog position is the tiebreak, because Swift's sort is NOT stable: entries
        // sharing a fatigueCost had unspecified relative order, so an edit that touched
        // neither the cost nor the catalog order could still reorder the day. Renaming
        // exercises surfaced this — the deterministic menu snapshot moved with a pure rename,
        // which means "deterministic generation" was resting on an implementation detail of
        // the sort. Ordering is now a property of the catalog, which is reviewable.
        return exerciseMetadataEntries
            .filter { !aliases.isDisjoint(with: Set($0.primaryAreas)) }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.fatigueCost != rhs.element.fatigueCost {
                    return lhs.element.fatigueCost < rhs.element.fatigueCost
                }
                return lhs.offset < rhs.offset
            }
            .map { ($0.element.canonicalName, $0.element.primaryAreas.first ?? focusArea) }
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
            let orderedCandidates = catalog.enumerated().sorted { lhs, rhs in
                let lhsUsed = usedAcrossDays.contains(normalizeExerciseName(lhs.element.name))
                let rhsUsed = usedAcrossDays.contains(normalizeExerciseName(rhs.element.name))
                if lhsUsed != rhsUsed { return !lhsUsed }
                return lhs.offset < rhs.offset
            }.map(\.element)

            for candidate in orderedCandidates {
                guard focusMatchCount(in: result) < targetCount else { return }
                guard exerciseMatchesTrainingIntent(name: candidate.name, target: candidate.target, intent: focusIntent) else { continue }
                let candidateKey = normalizeExerciseName(candidate.name)
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
                let orderedCandidates = catalog.enumerated().sorted { lhs, rhs in
                    let lhsUsed = usedAcrossDays.contains(normalizeExerciseName(lhs.element.name))
                    let rhsUsed = usedAcrossDays.contains(normalizeExerciseName(rhs.element.name))
                    if lhsUsed != rhsUsed { return !lhsUsed }
                    return lhs.offset < rhs.offset
                }.map(\.element)

                for candidate in orderedCandidates {
                    guard exerciseMatchesTrainingIntent(name: candidate.name, target: candidate.target, intent: supportIntent) else { continue }
                    let candidateKey = normalizeExerciseName(candidate.name)
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
        let exercise = WorkoutExerciseResponse(
            exerciseName: exerciseName,
            sets: sets,
            reps: "",
            tempo: "",
            restSeconds: 0,
            notes: "",
            muscleTarget: muscleTarget
        )
        return directSetCredit(for: exercise, area: intent.area)
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
        minimumSetFloor(
            forExerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget
        )
    }

    /// The floor depends only on the exercise's ROLE, so the set count is irrelevant. The dose
    /// gates need it per candidate and must not pay to build a full `WorkoutExerciseResponse`
    /// (rep/tempo/rest strings) just to read a name and a target.
    func minimumSetFloor(forExerciseName exerciseName: String, muscleTarget: String) -> Int {
        switch proceduralExerciseRole(for: exerciseName, muscleTarget: muscleTarget) {
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

        // This list is rendered as the week-over-week change log. Dictionary/Set iteration order
        // is unspecified, and the closing `sorted(by: dayNumber)` is not a stable sort, so rows
        // within a day previously shuffled between reads of the same two weeks. Walk every
        // collection in a defined order instead.
        for style in currentByStyle.keys.sorted() {
            guard let currentStyleDays = currentByStyle[style],
                  let previousStyleDays = previousByStyle[style] else { continue }

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

                for key in previousKeys.keys.sorted() where currentKeys[key] == nil {
                    guard let exercise = previousKeys[key] else { continue }
                    entries.append(WeekDiffEntry(
                        dayNumber: current.dayNumber,
                        dayName: current.dayName,
                        kind: .removed,
                        exerciseName: exercise.exerciseName,
                        detail: "\(exercise.sets) sets × \(exercise.reps)"
                    ))
                }

                for key in currentKeys.keys.sorted() where previousKeys[key] == nil {
                    guard let exercise = currentKeys[key] else { continue }
                    entries.append(WeekDiffEntry(
                        dayNumber: current.dayNumber,
                        dayName: current.dayName,
                        kind: .added,
                        exerciseName: exercise.exerciseName,
                        detail: "\(exercise.sets) sets × \(exercise.reps)"
                    ))
                }

                for key in currentKeys.keys.sorted() {
                    guard let currentExercise = currentKeys[key],
                          let previousExercise = previousKeys[key] else { continue }
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

        // Insertion order is the tiebreak, because Swift's sort is not stable: rows sharing a
        // dayNumber otherwise had unspecified relative order even from identical input.
        return entries
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.dayNumber != rhs.element.dayNumber {
                    return lhs.element.dayNumber < rhs.element.dayNumber
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    // MARK: - Pre-Selected Exercise Menu (deterministic selection layer)

    /// A maintenance budget must constrain exercise identity as well as set dosage. With a
    /// meaningful two-set floor, an 8-set recovery-tight budget can support at most four
    /// movements for a non-priority group; selecting more creates fragmented token work before
    /// the set allocator even runs.
    /// `meaningfulDoseSets` is the per-movement dose the weekly ceiling must be able to pay for.
    /// It drops to 2 only on the last-resort sweeps that rescue a menu shorter than five
    /// exercises: a short menu is a validator hard failure and a deterministic dead-end, which
    /// outranks dose hygiene exactly as it already outranks the pattern cap and the priority-dose
    /// gate. Normal selection never passes anything but the default.
    func maintenanceSlotBudgetsAreFeasible(
        existingMenus: [[PreSelectedExercise]],
        selectedToday: [(name: String, target: String)],
        blueprint: ProgramBlueprint,
        meaningfulDoseSets: Int = 3
    ) -> Bool {
        let recoveryTight = blueprint.calibration.recoveryConstrained
            || blueprint.calibration.poorNutritionAdherence
        let maintenanceCeiling = recoveryTight ? 8 : 10
        // How many DISTINCT movements a non-priority group may hold is decided by what its
        // weekly ceiling can pay for at a dose worth programming. That dose is three sets, not
        // two.
        //
        // This divisor used to be 2, and it is the direct cause of the fragmentation the owner
        // reported: a recovery-tight ceiling of 8 admitted 4 movements, the maintenance loop
        // fills round-robin from a seed of 1, and 4 movements hit 2 sets apiece exactly as the
        // ceiling closes. Every quad, hamstring, glute, back and triceps movement in that week
        // read 2×8-12. The tell was calves — the only group that drew fewer movements — landing
        // on 3 sets each.
        //
        // Two hard sets is below what drives hypertrophy on a movement, and it is also too thin
        // for the app's own progression tracker to read a trend from, so the fragmentation cost
        // the owner twice. At a 3-set divisor the same ceiling admits 3 movements and the loop
        // lands 3/3/2 — same total, two movements at a real dose instead of none.
        //
        // Rounds UP so the ceiling still gets spent: floor(8/3) would admit only 2 movements and
        // strand 2 of the 8 available sets.
        //
        // At the default dose of 3 this yields 3 movements for a ceiling of 8 and 4 for a ceiling
        // of 10 — one fewer than before in both cases. The rescue sweeps pass 2, which reproduces
        // the previous numbers exactly (4 and 5), so tightening dose quality can never be the
        // reason a day menu ends up too short to ship.
        let maxMeaningfulSlots = (maintenanceCeiling + meaningfulDoseSets - 1) / meaningfulDoseSets

        // Prioritized groups are no longer skipped outright. They are counted on their RESIDUE —
        // the movements no priority allocation pays for — because that residue is funded from the
        // maintenance ceiling in `allocateWeeklySetPrescription` and is subject to exactly the
        // same arithmetic. Without this the residue could seat more movements than the ceiling can
        // dose, and the allocator would strand the surplus below the two-set floor.
        for group in majorMuscleGroups {
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            let countsForGroup: (String, String) -> Bool = { name, target in
                self.exerciseCountsTowardMaintenance(
                    groupSeed: group.seed,
                    groupAliases: aliases,
                    exerciseName: name,
                    muscleTarget: target,
                    blueprint: blueprint
                )
            }

            var distinctNames = Set<String>()
            for exercise in existingMenus.joined()
            where countsForGroup(exercise.exerciseName, exercise.muscleTarget) {
                distinctNames.insert(normalizeExerciseName(exercise.exerciseName))
            }
            for exercise in selectedToday where countsForGroup(exercise.name, exercise.target) {
                distinctNames.insert(normalizeExerciseName(exercise.name))
            }

            guard distinctNames.count <= maxMeaningfulSlots else { return false }
        }
        return true
    }

    /// Priority companion to `maintenanceSlotBudgetsAreFeasible`. Variety hygiene
    /// (`weeklyVariationViolations`) caps how many *kinds* of a movement a priority may use, but
    /// nothing tied breadth to the priority's set budget — so a small-muscle priority (rear
    /// delts, biceps, calves) could accumulate more distinct movements than its weekly direct-set
    /// budget can fund to the two-set minimum-dose floor, and the allocator then stranded the
    /// surplus at one seed set each (the fragmented single-set day the owner flagged). Mirror the
    /// maintenance floor here: the number of distinct movements that give a priority direct credit
    /// may not exceed what its recoverable weekly budget — the menu-locked over-volume hard-fail
    /// line, matching how the maintenance gate uses the maintenance ceiling — can pay for at two
    /// sets apiece.
    func priorityDoseBudgetsAreFeasible(
        existingMenus: [[PreSelectedExercise]],
        selectedToday: [(name: String, target: String)],
        blueprint: ProgramBlueprint
    ) -> Bool {
        let recoveryTight = blueprint.calibration.recoveryConstrained
            || blueprint.calibration.poorNutritionAdherence
        // Matches the validator's moderate over-volume multiplier (ParsingValidation): direct
        // sets above `target * moderateMultiplier + buffer` hard-fail a locked menu, so that
        // product is the most volume the plan can actually spend on this priority.
        let moderateMultiplier = recoveryTight ? 1.15 : 1.3
        let identities = existingMenus.joined().map {
            (name: $0.exerciseName, target: $0.muscleTarget)
        } + selectedToday
        for allocation in blueprint.priorityAllocations {
            let spendableDirectSets = allocation.directSetTarget * moderateMultiplier
            // Whole two-set doses the recoverable budget can pay for. Never below one so a
            // priority can always seat at least one movement even on a tiny budget.
            let maxDosedMovements = max(1, Int((spendableDirectSets / 2.0).rounded(.down)))
            // Counts DISTINCT NAMES, not exposures.
            //
            // Counting exposures was tried and REVERTED. It is the more correct affordability
            // question — the allocator must find a floor for every slot, and the same movement on
            // two days is two slots each needing its own — and it did clear the one-set lateral
            // raise. But this gate runs per candidate while days are built in order, so a WEEKLY
            // budget enforced greedily is spent by the early days: day 6 was refused the Lateral
            // Deltoids work its own day plan called for and delivered ZERO quality direct sets to
            // its stated focus, then the short-menu rescue sweep filled it with triceps, two of
            // which shipped at one set. Trading one under-dosed movement for a focus day with no
            // focus work, plus two more under-dosed movements, is a clear loss.
            //
            // Fixing it properly means either reserving each focus day's share of the budget
            // before selection starts, or distributing exposures across days rather than checking
            // a running total. Both are real changes to how menus are built. Until then the
            // narrower defect stands, documented, with its cause recorded in
            // `ResidueMuscleDoseTests`.
            let distinctDirect = identities.reduce(into: Set<String>()) { result, exercise in
                let probe = WorkoutExerciseResponse(
                    exerciseName: exercise.name,
                    sets: 1,
                    reps: "",
                    tempo: "",
                    restSeconds: 0,
                    notes: "",
                    muscleTarget: exercise.target
                )
                guard directSetCredit(for: probe, area: allocation.area) > 0 else { return }
                result.insert(normalizeExerciseName(exercise.name))
            }
            guard distinctDirect.count <= maxDosedMovements else { return false }
        }
        return true
    }

    func menuPlanningBudgetAllows(
        candidateName: String,
        candidateTarget: String,
        existingMenus: [[PreSelectedExercise]],
        selectedToday: [(name: String, target: String)],
        blueprint: ProgramBlueprint,
        enforcePriorityDose: Bool = true,
        enforceMaintenanceDose: Bool = true
    ) -> Bool {
        menuPlanningBudgetsAreFeasible(
            existingMenus: existingMenus,
            selectedToday: selectedToday + [(name: candidateName, target: candidateTarget)],
            blueprint: blueprint,
            enforcePriorityDose: enforcePriorityDose,
            enforceMaintenanceDose: enforceMaintenanceDose
        )
    }

    /// `enforcePriorityDose` and `enforceMaintenanceDose` are QUALITY guards, not safety ones:
    /// fragmenting a muscle across too many thin movements is a warning, never a menu-locked hard
    /// failure. The last-resort "avoid a <5-exercise menu" sweeps pass `false` for both, exactly as
    /// they already drop the within-day pattern cap — a short menu is a deterministic dead-end that
    /// outranks dose hygiene, and the allocation floor pass still doses whatever survives.
    ///
    /// The maintenance CEILING itself is the safety guard and is unaffected by either flag: it is
    /// enforced in `allocateWeeklySetPrescription`'s `canAddSet`, which never lets a non-priority
    /// group exceed its weekly total no matter how many movements reached the menu. What relaxes
    /// here is only how many movements that fixed budget may be spread across.
    func menuPlanningBudgetsAreFeasible(
        existingMenus: [[PreSelectedExercise]],
        selectedToday: [(name: String, target: String)],
        blueprint: ProgramBlueprint,
        enforcePriorityDose: Bool = true,
        enforceMaintenanceDose: Bool = true
    ) -> Bool {
        guard maintenanceSlotBudgetsAreFeasible(
            existingMenus: existingMenus,
            selectedToday: selectedToday,
            blueprint: blueprint,
            meaningfulDoseSets: enforceMaintenanceDose ? 3 : 2
        ) else {
            return false
        }

        if enforcePriorityDose {
            guard priorityDoseBudgetsAreFeasible(
                existingMenus: existingMenus,
                selectedToday: selectedToday,
                blueprint: blueprint
            ) else {
                return false
            }
        }

        let identities = existingMenus.joined().map {
            (name: $0.exerciseName, target: $0.muscleTarget)
        } + selectedToday
        return weeklyVariationViolations(for: identities, blueprint: blueprint).isEmpty
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

            let targetCount = MesocyclePhase.isDeloadWeek(weekNumber) ? 5 : 6
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
                guard menuPlanningBudgetAllows(
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
                guard menuPlanningBudgetAllows(
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
                    guard menuPlanningBudgetAllows(
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
                // A split can label compatible lower-body sessions differently (for example,
                // "Lower" and "Legs"). Reuse established, style-compatible identities across
                // that catalog boundary before introducing another weekly variation.
                let compatibleEstablished = allMenus.flatMap { $0 }.compactMap { exercise -> (name: String, target: String)? in
                    let probe = WorkoutExerciseResponse(
                        exerciseName: exercise.exerciseName,
                        sets: 3,
                        reps: "10-12",
                        tempo: "",
                        restSeconds: 60,
                        notes: "",
                        muscleTarget: exercise.muscleTarget
                    )
                    guard exerciseMatchesDayStyle(probe, style: styleKey) else { return nil }
                    return (exercise.exerciseName, exercise.muscleTarget)
                }
                let repeatPool = compatibleEstablished + catalog
                // First sweep honors the within-day pattern cap; the uncapped second sweep
                // only runs if the menu is still short, because a <5 menu is a validator
                // hard failure and a deterministic dead-end that outranks pattern hygiene.
                for candidate in repeatPool where selected.count < 5 {
                    let key = normalizeExerciseName(candidate.name)
                    guard !selected.contains(where: { normalizeExerciseName($0.name) == key }) else { continue }
                    guard dayPatternCapAllows(candidateName: candidate.name, candidateTarget: candidate.target, in: selected) else { continue }
                    guard menuPlanningBudgetAllows(
                        candidateName: candidate.name,
                        candidateTarget: candidate.target,
                        existingMenus: allMenus,
                        selectedToday: selected,
                        blueprint: blueprint,
                        enforcePriorityDose: false,
                        enforceMaintenanceDose: false
                    ) else { continue }
                    selected.append((candidate.name, candidate.target))
                }
                for candidate in repeatPool where selected.count < 5 {
                    let key = normalizeExerciseName(candidate.name)
                    guard !selected.contains(where: { normalizeExerciseName($0.name) == key }) else { continue }
                    guard menuPlanningBudgetAllows(
                        candidateName: candidate.name,
                        candidateTarget: candidate.target,
                        existingMenus: allMenus,
                        selectedToday: selected,
                        blueprint: blueprint,
                        enforcePriorityDose: false,
                        enforceMaintenanceDose: false
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
                        self.menuPlanningBudgetsAreFeasible(
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
                        self.menuPlanningBudgetsAreFeasible(
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
        let feasibilityCompleteMenus = enforcePriorityDirectSetFeasibility(
            coverageCompleteMenus,
            blueprint: blueprint,
            trainingIntent: trainingIntent,
            avoidedExercises: avoidedExercises
        )
        var finalCoverageMenus = feasibilityCompleteMenus
        for _ in 0..<majorMuscleGroups.count {
            let gapsBefore = Set(
                baselineCoverageGaps(in: finalCoverageMenus, blueprint: blueprint).map { $0.seed }
            )
            guard !gapsBefore.isEmpty else { break }

            let repairedMenus = enforceBaselineMuscleCoverage(
                finalCoverageMenus,
                blueprint: blueprint,
                trainingIntent: trainingIntent,
                avoidedExercises: avoidedExercises,
                allowReplacements: false
            )
            let gapsAfter = Set(
                baselineCoverageGaps(in: repairedMenus, blueprint: blueprint).map { $0.seed }
            )
            finalCoverageMenus = repairedMenus
            guard gapsAfter != gapsBefore else { break }
        }
        // Both balance passes run BEFORE the knee anchor on purpose. They are purely additive, so
        // they cannot create the shape the knee anchor repairs, but the knee anchor DOES evict
        // slots on lower-body days — letting it have the last word means a repair it considers
        // necessary is never blocked by a movement added for breadth.
        //
        // The row survives this ordering for a structural reason rather than by luck: "row" is a
        // FORBIDDEN keyword on Lower and Legs styles, so `exerciseMatchesDayStyle` can never place
        // a rowing movement on a lower-body day, and the knee anchor only ever touches those days.
        // A maintenance slot for quads, hamstrings, glutes or calves genuinely can be evicted
        // here, and that is the intended precedence: session balance outranks breadth.
        let rowCompleteMenus = enforceHorizontalPullCoverage(
            finalCoverageMenus,
            blueprint: blueprint,
            weekNumber: weekNumber,
            avoidedExercises: avoidedExercises
        )
        let breadthCompleteMenus = enforceMaintenanceExposureBreadth(
            rowCompleteMenus,
            blueprint: blueprint,
            weekNumber: weekNumber,
            avoidedExercises: avoidedExercises
        )
        let balancedMenus = enforceLowerSessionKneeAnchor(
            breadthCompleteMenus,
            blueprint: blueprint,
            trainingIntent: trainingIntent,
            avoidedExercises: avoidedExercises
        )
        // Last, so every movement any pass above appended is placed in the session by its role
        // rather than simply landing at the end of the day.
        let orderedMenus = reorderedMenusForSessionFlow(
            balancedMenus,
            blueprint: blueprint,
            trainingIntent: trainingIntent
        )
        return allocateWeeklySetPrescription(
            orderedMenus,
            blueprint: blueprint,
            weekNumber: weekNumber
        )
    }

    // MARK: - Lower-Session Knee-Dominant Anchor (menu-level)

    /// Repairs a broad lower-body day that the builder filled with glute/posterior-chain work
    /// and no knee-dominant quad anchor, BEFORE the menu is locked and handed to the AI.
    ///
    /// `validateLowerSessionBalance` rejects exactly that shape, and the rejection is a pure
    /// EXERCISE-SELECTION verdict. In a locked-menu flow nothing downstream can act on it: the
    /// AI is explicitly forbidden from adding, removing or substituting movements, and the
    /// procedural fallback consumes the same menu. So the finding survived every retry AND the
    /// correction pass, then failed the whole candidate set. Seen live on a 5-day block whose
    /// Legs day was Trap Bar Deadlift / Bulgarian Split Squat / Nordic Curl / Barbell Hip
    /// Thrust / Single-Leg Hip Thrust: two paid candidates plus a paid correction pass, all
    /// scored 5 on the identical unfixable issue, all discarded, and the week shipped from the
    /// procedural fallback with generic cues.
    ///
    /// The validator was also RIGHT about the programming — that day carried two hip-thrust
    /// variants and no bilateral quad stimulus at all. So the repair belongs here, in the one
    /// layer that is allowed to choose exercises, not in a looser validator.
    ///
    /// Driven by `validateLowerSessionBalance` itself rather than a re-statement of its rule,
    /// so the repair and the check cannot drift apart. Every swap must strictly reduce that
    /// day's findings while preserving BASE-001 coverage and each priority's exposure-day
    /// count, so this can never trade one validator failure for another.
    func enforceLowerSessionKneeAnchor(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        trainingIntent: TrainingIntentPlan,
        avoidedExercises: Set<String>
    ) -> [[PreSelectedExercise]] {
        var updated = menus

        for (dayOffset, plan) in blueprint.dayPlans.enumerated()
        where !plan.isRestDay && dayOffset < updated.count && !updated[dayOffset].isEmpty {
            let style = canonicalTrainingStyle(plan.style)
            guard style == "Lower" || style == "Legs" else { continue }

            let focusIntent = focusIntentForArea(plan.focusArea, within: trainingIntent)
            let supportIntents = plan.supportAreas.compactMap { focusIntentForArea($0, within: trainingIntent) }

            // One swap clears the anchor finding; the bound lets a day carrying more than one
            // balance finding keep repairing, and guarantees termination if a swap is a no-op.
            for _ in 0..<2 {
                let currentIssues = Set(
                    lowerSessionBalanceIssues(in: updated[dayOffset], dayOffset: dayOffset, plan: plan)
                )
                guard !currentIssues.isEmpty else { break }
                guard let repaired = kneeAnchorRepairedMenus(
                    updated,
                    dayOffset: dayOffset,
                    plan: plan,
                    currentIssues: currentIssues,
                    blueprint: blueprint,
                    trainingIntent: trainingIntent,
                    focusIntent: focusIntent,
                    supportIntents: supportIntents,
                    avoidedExercises: avoidedExercises
                ) else { break }
                updated = repaired
            }
        }

        return updated
    }

    /// One accepted swap, or nil when no candidate/slot pairing improves the day safely.
    private func kneeAnchorRepairedMenus(
        _ menus: [[PreSelectedExercise]],
        dayOffset: Int,
        plan: BlueprintDayPlan,
        currentIssues: Set<String>,
        blueprint: ProgramBlueprint,
        trainingIntent: TrainingIntentPlan,
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent],
        avoidedExercises: Set<String>
    ) -> [[PreSelectedExercise]]? {
        let style = canonicalTrainingStyle(plan.style)
        // Tuple members have no key paths in Swift, so these stay closures throughout.
        let usedElsewhere = Set(
            menus.indices
                .filter { $0 != dayOffset }
                .flatMap { menus[$0] }
                .map { normalizeExerciseName($0.exerciseName) }
        )
        let gapsBefore = Set(baselineCoverageGaps(in: menus, blueprint: blueprint).map { $0.seed })
        let exposureBefore = priorityExposureDayCounts(in: menus, trainingIntent: trainingIntent)

        // Lowest fatigue cost first: on a session that is already posterior-heavy, the cheapest
        // honest quad stimulus (a leg extension or a machine squat pattern) buys the missing
        // anchor without pushing the day past its fatigue cap.
        for candidate in metadataFocusExerciseCatalog(for: "quads") {
            let key = normalizeExerciseName(candidate.name)
            guard !avoidedExercises.contains(ExerciseWeightEntry.canonicalLookupKey(candidate.name)) else { continue }
            guard !usedElsewhere.contains(key) else { continue }
            guard !menus[dayOffset].contains(where: { normalizeExerciseName($0.exerciseName) == key }) else { continue }

            let metadata = exerciseMetadata(forExerciseName: candidate.name, muscleTarget: candidate.target)
            guard kneeDominantAnchorPatterns.contains(metadata.movementPattern) else { continue }

            let probe = WorkoutExerciseResponse(
                exerciseName: candidate.name,
                sets: 3,
                reps: "10-12",
                tempo: "",
                restSeconds: 60,
                notes: "",
                muscleTarget: candidate.target
            )
            guard exerciseMatchesDayStyle(probe, style: style) else { continue }

            let candidateMenu = PreSelectedExercise(
                exerciseName: candidate.name,
                muscleTarget: candidate.target,
                movementPattern: metadata.movementPattern,
                role: proceduralExerciseRole(for: candidate.name, muscleTarget: candidate.target),
                prescribedSets: 1
            )

            // Same expendability order BASE-001 uses: duplicated-pattern non-anchor slots that
            // serve neither the day's focus nor its support areas go first, so the priority
            // work and the day's anchors are never the thing that gets traded away.
            for replaceIndex in baselineCoverageReplacementIndices(
                in: menus[dayOffset],
                focusIntent: focusIntent,
                supportIntents: supportIntents
            ) {
                var proposed = menus
                proposed[dayOffset].remove(at: replaceIndex)
                proposed[dayOffset].insert(candidateMenu, at: replaceIndex)

                let proposedIssues = Set(
                    lowerSessionBalanceIssues(in: proposed[dayOffset], dayOffset: dayOffset, plan: plan)
                )
                guard proposedIssues.isStrictSubset(of: currentIssues) else { continue }

                let gapsAfter = Set(baselineCoverageGaps(in: proposed, blueprint: blueprint).map { $0.seed })
                guard gapsAfter.isSubset(of: gapsBefore) else { continue }

                let exposureAfter = priorityExposureDayCounts(in: proposed, trainingIntent: trainingIntent)
                guard exposureBefore.allSatisfy({ exposureAfter[$0.key, default: 0] >= $0.value }) else { continue }

                return proposed
            }
        }

        return nil
    }

    /// Runs the real validator over a menu by projecting it into the day shape the validator
    /// reads. Reps/tempo/rest are placeholders: `validateLowerSessionBalance` inspects only
    /// exercise identity and movement pattern.
    func lowerSessionBalanceIssues(
        in menu: [PreSelectedExercise],
        dayOffset: Int,
        plan: BlueprintDayPlan
    ) -> [String] {
        let probeDay = WorkoutDayResponse(
            dayNumber: dayOffset + 1,
            dayName: plan.style,
            muscleGroups: "",
            isRestDay: false,
            notes: "",
            exercises: menu.map { item in
                WorkoutExerciseResponse(
                    exerciseName: item.exerciseName,
                    sets: max(1, item.prescribedSets),
                    reps: "10-12",
                    tempo: "",
                    restSeconds: 60,
                    notes: "",
                    muscleTarget: item.muscleTarget
                )
            }
        )
        return validateLowerSessionBalance(
            on: probeDay,
            expectedStyle: canonicalTrainingStyle(plan.style),
            focusArea: plan.focusArea
        )
    }

    /// Distinct training days on which each priority has a directly-crediting exercise. The
    /// knee-anchor swap must never lower one of these — that is the ceiling
    /// `enforcePriorityDirectSetFeasibility` just finished raising, and dropping it here would
    /// hand the user the "missed its direct-set target" finding instead.
    func priorityExposureDayCounts(
        in menus: [[PreSelectedExercise]],
        trainingIntent: TrainingIntentPlan
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for priority in trainingIntent.priorities {
            counts[priority.area] = menus.filter { menu in
                menu.contains { exercise in
                    focusStimulusKind(
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget,
                        focusArea: priority.area
                    ) == .prime
                }
            }.count
        }
        return counts
    }

    // MARK: - BASE-001 Baseline Muscle Coverage (menu-level floor)

    /// EvidenceProfile.md BASE-001 [confidence: high]. The per-day selection above only
    /// enforces focus/support coverage, so a whole week could ship with zero direct work
    /// for an unlisted muscle (seen live: no hamstring exposure all week while calves got
    /// 6 sets). For every non-priority major muscle group with zero direct coverage, swap
    /// one expendable slot for the lowest-fatigue direct movement on a style-compatible day.
    /// This pass owns a hard identity floor; the later set allocator cannot repair a missing
    /// exercise, and the AI is explicitly forbidden from changing this menu.
    func enforceBaselineMuscleCoverage(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        trainingIntent: TrainingIntentPlan,
        avoidedExercises: Set<String>,
        allowReplacements: Bool = true
    ) -> [[PreSelectedExercise]] {
        var updated = menus
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
                    let candidateMenu = PreSelectedExercise(
                        exerciseName: candidate.name,
                        muscleTarget: candidate.target,
                        movementPattern: exerciseMetadata(
                            forExerciseName: candidate.name,
                            muscleTarget: candidate.target
                        ).movementPattern,
                        role: proceduralExerciseRole(for: candidate.name, muscleTarget: candidate.target),
                        prescribedSets: 1
                    )

                    var replaced = false
                    if allowReplacements {
                        let replacementIndices = baselineCoverageReplacementIndices(
                            in: updated[dayOffset],
                            focusIntent: focusIntent,
                            supportIntents: supportIntents
                        )
                        for replaceIndex in replacementIndices {
                            var menusWithoutReplacedSlot = updated
                            menusWithoutReplacedSlot[dayOffset].remove(at: replaceIndex)
                            menusWithoutReplacedSlot[dayOffset].insert(candidateMenu, at: replaceIndex)

                            // The general menu-budget gate also checks unrelated variation ledgers.
                            // Do not let one of those soft identity heuristics defeat BASE-001: this
                            // proposed swap is allowed when it preserves every baseline floor. It still
                            // goes through the normal gate whenever that gate can evaluate it cleanly.
                            let gapsBefore = Set(
                                baselineCoverageGaps(in: updated, blueprint: blueprint).map { $0.seed }
                            )
                            let gapsAfter = Set(
                                baselineCoverageGaps(in: menusWithoutReplacedSlot, blueprint: blueprint).map { $0.seed }
                            )
                            let baselineFloorPreserved = !gapsAfter.contains(group.seed)
                                && gapsAfter.isSubset(of: gapsBefore)
                            guard menuPlanningBudgetAllows(
                                candidateName: candidate.name,
                                candidateTarget: candidate.target,
                                existingMenus: {
                                    var menus = menusWithoutReplacedSlot
                                    menus[dayOffset].remove(at: replaceIndex)
                                    return menus
                                }(),
                                selectedToday: [],
                                blueprint: blueprint
                            ) || baselineFloorPreserved else { continue }

                            updated = menusWithoutReplacedSlot
                            replaced = true
                            break
                        }
                    }
                    if replaced {
                        break candidateSearch
                    }

                    // The validator permits 5-8 movements per training day. A six-movement
                    // menu can already contain the only direct exposure for several other
                    // maintenance groups, so swapping one of them would simply move BASE-001's
                    // zero to a different muscle. Use the available capacity only after every
                    // safe replacement has been rejected.
                    if updated[dayOffset].count < 8 {
                        var expandedMenus = updated
                        expandedMenus[dayOffset].append(candidateMenu)
                        let gapsBefore = Set(
                            baselineCoverageGaps(in: updated, blueprint: blueprint).map { $0.seed }
                        )
                        let gapsAfter = Set(
                            baselineCoverageGaps(in: expandedMenus, blueprint: blueprint).map { $0.seed }
                        )
                        let baselineFloorPreserved = !gapsAfter.contains(group.seed)
                            && gapsAfter.isSubset(of: gapsBefore)
                        guard menuPlanningBudgetAllows(
                            candidateName: candidate.name,
                            candidateTarget: candidate.target,
                            existingMenus: updated,
                            selectedToday: [],
                            blueprint: blueprint
                        ) || baselineFloorPreserved else { continue }
                        updated = expandedMenus
                        break candidateSearch
                    }
                }
            }
        }

        return updated
    }

    func baselineCoverageGaps(
        in menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint
    ) -> [(label: String, seed: String)] {
        majorMuscleGroups.compactMap { group in
            guard !isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint) else { return nil }
            let aliases = normalizedGroupAliases(forSeed: group.seed)
            let covered = menus.joined().contains { exercise in
                exerciseDirectlyTargets(
                    groupAliases: aliases,
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget
                )
            }
            return covered ? nil : group
        }
    }

    // MARK: - Menu-Level Balance Passes (shared additive placement)

    /// How many movements a day may hold before adding another one makes the session worse.
    ///
    /// The validator permits 5-8 movements per training day, but `validateSessionFocusDiscipline`
    /// applies a stricter rule to lower-body sessions: a Lower day with 7 or more movements is
    /// "too crowded for a fatigue-managed Lower session". The first version of the balance passes
    /// used the flat ceiling of 8 and promptly earned that finding — it added a second calf
    /// movement to a six-movement Legs day, trading a thin muscle group for an overcrowded
    /// session. Buying breadth by making a day worse is not a fix.
    func comfortableDayExerciseCeiling(forStyle style: String) -> Int {
        canonicalTrainingStyle(style) == "Lower" ? 6 : 8
    }

    /// Whether a day can absorb one more movement without breaking the budgets its plan set.
    ///
    /// This is NOT the same question as "can the allocator afford another set", and the difference
    /// is the whole point. `fatigueContribution` charges a movement its full `fatigueCost` at ONE
    /// set — the multiplier only rises at four sets and again at five — so an appended movement
    /// spends day fatigue and session minutes that no later pass can walk back.
    /// `allocateWeeklySetPrescription` guarantees the finished day stays inside its cap only while
    /// the SEEDED day, every movement at one set, already fits: past that line it can decline to
    /// fund further sets, but it cannot remove the movement that broke the budget.
    ///
    /// So the seeded projection is exactly the right test — not the finished day, which is unknown
    /// while the menu is still being built, and not the role-default projection, which the
    /// allocator is free to stop short of.
    ///
    /// Without this, a balance pass could hand the lifter a session that earns "carries too much
    /// total fatigue load" or a session-budget finding. Both are correction-worthy under menu-lock:
    /// a paid correction call, and the whole paid candidate set discarded if the finding survives
    /// it. A bad trade for one accessory.
    func seededDayFitsItsBudgets(
        adding candidate: (name: String, target: String),
        to menu: [PreSelectedExercise],
        plan: BlueprintDayPlan,
        weekNumber: Int
    ) -> Bool {
        let seeded = (menu.map { (name: $0.exerciseName, target: $0.muscleTarget) } + [candidate])
            .map { item -> WorkoutExerciseResponse in
                let reps = proceduralRepRange(
                    for: weekNumber,
                    exerciseName: item.name,
                    muscleTarget: item.target
                )
                return WorkoutExerciseResponse(
                    exerciseName: item.name,
                    sets: 1,
                    reps: reps,
                    tempo: proceduralTempo(
                        for: weekNumber,
                        exerciseName: item.name,
                        muscleTarget: item.target,
                        reps: reps
                    ),
                    restSeconds: proceduralRestSeconds(
                        for: item.name,
                        muscleTarget: item.target
                    ),
                    notes: "",
                    muscleTarget: item.target
                )
            }

        guard estimatedDayFatigue(for: seeded) <= plan.targetFatigueCap else { return false }
        return estimatedSessionMinutes(for: proceduralTrainingDay(from: seeded))
            <= plan.targetSessionMinutes + 3
    }

    /// Appends one catalogue exercise to a training day that has room for it, or returns nil when
    /// nothing fits anywhere.
    ///
    /// Deliberately ADDITIVE ONLY — it never evicts an existing movement.
    /// `enforceBaselineMuscleCoverage` owns the eviction path because a muscle with ZERO weekly
    /// exposure is worth trading a slot for. The callers here are correcting a LOPSIDED week, not
    /// an absent muscle, and buying breadth by deleting someone else's only exposure would just
    /// move the problem to a different muscle. When there is no room the week ships as it is and
    /// the validator says so out loud.
    ///
    /// - Parameter deprioritizedDays: days to consider only after every other day has been tried.
    ///   Callers spreading a muscle across the week pass the days that already train it, so a
    ///   second slot lands on a second day rather than stacking onto the first.
    func menusByAppendingBalanceExercise(
        to menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        weekNumber: Int,
        avoidedExercises: Set<String>,
        candidates: [(name: String, target: String)],
        deprioritizedDays: Set<Int> = []
    ) -> [[PreSelectedExercise]]? {
        // Lightest day first. Every caller here is evening out a lopsided week, and the day
        // carrying the fewest movements is both the likeliest to have slot, fatigue and time
        // budget left and the one that most needs the work.
        let dayOrder = blueprint.dayPlans.indices
            .filter { dayIndex in
                guard dayIndex < menus.count else { return false }
                return !blueprint.dayPlans[dayIndex].isRestDay && !menus[dayIndex].isEmpty
            }
            .sorted { lhs, rhs in
                let lhsDeferred = deprioritizedDays.contains(lhs)
                let rhsDeferred = deprioritizedDays.contains(rhs)
                if lhsDeferred != rhsDeferred { return !lhsDeferred }
                if menus[lhs].count != menus[rhs].count { return menus[lhs].count < menus[rhs].count }
                return lhs < rhs
            }

        for candidate in candidates {
            guard !avoidedExercises.contains(ExerciseWeightEntry.canonicalLookupKey(candidate.name)) else { continue }
            let key = normalizeExerciseName(candidate.name)
            guard !key.isEmpty else { continue }

            let probe = WorkoutExerciseResponse(
                exerciseName: candidate.name,
                sets: 3,
                reps: "10-12",
                tempo: "",
                restSeconds: 60,
                notes: "",
                muscleTarget: candidate.target
            )

            for dayIndex in dayOrder {
                guard menus[dayIndex].count < comfortableDayExerciseCeiling(
                    forStyle: blueprint.dayPlans[dayIndex].style
                ) else { continue }
                guard exerciseMatchesDayStyle(
                    probe,
                    style: canonicalTrainingStyle(blueprint.dayPlans[dayIndex].style)
                ) else { continue }
                guard !menus[dayIndex].contains(where: {
                    normalizeExerciseName($0.exerciseName) == key
                }) else { continue }
                guard dayPatternCapAllows(
                    candidateName: candidate.name,
                    candidateTarget: candidate.target,
                    in: menus[dayIndex].map { ($0.exerciseName, $0.muscleTarget) }
                ) else { continue }
                guard menuPlanningBudgetAllows(
                    candidateName: candidate.name,
                    candidateTarget: candidate.target,
                    existingMenus: menus,
                    selectedToday: [],
                    blueprint: blueprint
                ) else { continue }
                guard seededDayFitsItsBudgets(
                    adding: candidate,
                    to: menus[dayIndex],
                    plan: blueprint.dayPlans[dayIndex],
                    weekNumber: weekNumber
                ) else { continue }

                let metadata = exerciseMetadata(
                    forExerciseName: candidate.name,
                    muscleTarget: candidate.target
                )
                var updated = menus
                updated[dayIndex].append(
                    PreSelectedExercise(
                        exerciseName: candidate.name,
                        muscleTarget: candidate.target,
                        movementPattern: metadata.movementPattern,
                        role: proceduralExerciseRole(
                            for: candidate.name,
                            muscleTarget: candidate.target
                        ),
                        prescribedSets: 1
                    )
                )
                return updated
            }
        }

        return nil
    }

    // MARK: - Horizontal Pull Coverage (menu-level)

    /// Movement patterns that pull a load toward the torso under real load — the job vertical
    /// pulling does not do.
    ///
    /// "Face Pull" is deliberately NOT here, and the first draft of this fix got it wrong. A face
    /// pull is light rear-delt and external-rotation work at head height; it does not load the
    /// rhomboids and mid-traps through a rowing range. The very week that prompted this rule
    /// contained a Cable Face Pull and still had no rowing anywhere, so counting it would have
    /// left the gap unrepaired while reporting the week clean — worse than not having the rule.
    /// "Upright Row" is out for the same reason: the name says row, the movement is a delt raise.
    var horizontalPullPatterns: Set<String> { ["Row"] }

    /// Whether the week contains a movement that both uses one of `patterns` AND directly trains
    /// `groupSeed`.
    ///
    /// The muscle condition is not decoration. For an exercise missing from the catalogue,
    /// `inferredExerciseMetadata` assigns the "Row" pattern from the NAME — any name containing
    /// "row" — so a movement carried forward from an earlier program could satisfy a rowing
    /// requirement while training the shoulders. Requiring the movement to actually train the back
    /// makes the rule mean what it says, and costs one condition.
    func menusContainMovementPattern(
        _ patterns: Set<String>,
        trainingGroupSeed groupSeed: String,
        in menus: [[PreSelectedExercise]]
    ) -> Bool {
        let aliases = normalizedGroupAliases(forSeed: groupSeed)
        return menus.joined().contains { exercise in
            guard let pattern = menuMovementPattern(
                forExerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            ), patterns.contains(pattern) else { return false }
            return exerciseDirectlyTargets(
                groupAliases: aliases,
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            )
        }
    }

    /// Guarantees the week contains at least one ROWING movement whenever it trains the back.
    ///
    /// BASE-001 accounting treats "back" as ONE bucket whose aliases cover Lats, Upper Back and
    /// Mid Back together, so a single pulldown marks the entire bucket covered and no rule ever
    /// asked for a horizontal pull. Seen live: a five-day week whose only back work was
    /// `Lat Pulldown`, `Neutral-Grip Lat Pulldown` and `Pull-Up` — eight sets, all of them
    /// overhead, zero rows — for a lifter whose own analysis said to keep chest-supported rows and
    /// flagged thoracic rounding, which rowing addresses and pulldowns do not.
    ///
    /// The rule is deliberately DIRECTIONAL. A week of rows and no pulldown is not repaired here:
    /// rows still load the lats through a full range, whereas nothing in a vertical pull trains
    /// the rhomboids and mid-traps at their shortened position. Symmetry would look tidier and
    /// would be a claim the evidence does not support.
    ///
    /// Purely additive: a week with no room simply ships without the row, and
    /// `validateBackPatternBalance` reports it rather than the gap passing silently.
    func enforceHorizontalPullCoverage(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        weekNumber: Int,
        avoidedExercises: Set<String>
    ) -> [[PreSelectedExercise]] {
        let backAliases = normalizedGroupAliases(forSeed: "back")
        let trainsBack = menus.joined().contains { exercise in
            exerciseDirectlyTargets(
                groupAliases: backAliases,
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            )
        }
        guard trainsBack else { return menus }
        guard !menusContainMovementPattern(
            horizontalPullPatterns,
            trainingGroupSeed: "back",
            in: menus
        ) else { return menus }

        let rowCandidates = metadataFocusExerciseCatalog(for: "back").filter { candidate in
            guard let pattern = menuMovementPattern(
                forExerciseName: candidate.name,
                muscleTarget: candidate.target
            ) else { return false }
            return horizontalPullPatterns.contains(pattern)
        }

        return menusByAppendingBalanceExercise(
            to: menus,
            blueprint: blueprint,
            weekNumber: weekNumber,
            avoidedExercises: avoidedExercises,
            candidates: rowCandidates
        ) ?? menus
    }

    // MARK: - Maintenance Breadth (BASE-001 two-exposure floor)

    /// The number of weekly slots a major muscle group needs before its maintenance dose is
    /// reachable at all.
    ///
    /// EvidenceProfile.md BASE-001 asks for two weekly exposures per major group and MAINT-001
    /// puts the maintenance band at roughly 6-10 sets. The allocator can only fill an exercise up
    /// to its ROLE DEFAULT (about 3 sets), so a group holding one slot is structurally capped near
    /// 3 sets no matter how much weekly budget is left — no set-level rule can repair it, because
    /// the shortage is slots, not sets.
    ///
    /// That is exactly what shipped: Triceps held one slot (a single Dip) and received 2 sets for
    /// the week, while Calves held two slots and received 6. Calves are not mentioned anywhere in
    /// that lifter's analysis; triceps at 2 sets/week is below any maintenance definition.
    var maintenanceExposureFloor: Int { 2 }

    /// Every menu slot that directly trains `seed`, as (day index, exercise index) pairs.
    func maintenanceSlots(
        in menus: [[PreSelectedExercise]],
        forSeed seed: String
    ) -> [(day: Int, exercise: Int)] {
        let aliases = normalizedGroupAliases(forSeed: seed)
        return menus.indices.flatMap { dayIndex in
            menus[dayIndex].indices
                .filter { exerciseIndex in
                    exerciseDirectlyTargets(
                        groupAliases: aliases,
                        exerciseName: menus[dayIndex][exerciseIndex].exerciseName,
                        muscleTarget: menus[dayIndex][exerciseIndex].muscleTarget
                    )
                }
                .map { (day: dayIndex, exercise: $0) }
        }
    }

    /// Raises every already-covered non-priority major group to `maintenanceExposureFloor` weekly
    /// slots, spread across distinct days where the week has room.
    ///
    /// Only groups that are ALREADY covered are touched — a group at zero belongs to
    /// `enforceBaselineMuscleCoverage`, which is allowed to evict a slot for it and runs first.
    /// Prioritized groups are skipped because their own allocation owns their volume.
    ///
    /// Best-effort by construction. Every placement still passes the day's slot ceiling, the
    /// movement-pattern cap and the full menu budget, so a week with no room ships unchanged
    /// rather than being forced over its recovery budget to satisfy a breadth rule.
    func enforceMaintenanceExposureBreadth(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        weekNumber: Int,
        avoidedExercises: Set<String>
    ) -> [[PreSelectedExercise]] {
        var updated = menus

        for group in majorMuscleGroups {
            guard !isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint) else { continue }

            // The loop counts SLOTS, not days, and that is the termination argument: a
            // successful placement always adds exactly one slot, so the guard below is strictly
            // closer to failing on every pass. Counting distinct DAYS instead would not
            // terminate — a placement that landed on a day already training the group leaves the
            // day count unchanged, and the loop would keep appending movements until it ran out
            // of candidates. `deprioritizedDays` still steers the new slot onto a fresh day
            // whenever one will take it, which is what BASE-001's two-exposure wording asks for;
            // it is a preference here rather than a requirement precisely so that a week with
            // only one style-compatible day still gets the dose instead of nothing.
            while true {
                let slots = maintenanceSlots(in: updated, forSeed: group.seed)
                guard !slots.isEmpty, slots.count < maintenanceExposureFloor else { break }
                let coveredDays = Set(slots.map { $0.day })

                let alreadyInWeek = Set(updated.joined().map { normalizeExerciseName($0.exerciseName) })
                let aliases = normalizedGroupAliases(forSeed: group.seed)
                let candidates = metadataFocusExerciseCatalog(for: group.seed).filter { candidate in
                    // A second slot has to be a DIFFERENT movement. Repeating the same exercise on
                    // another day would add the exposure but not the variation, and the catalogue
                    // lists the group's own movements first anyway.
                    guard !alreadyInWeek.contains(normalizeExerciseName(candidate.name)) else { return false }
                    return exerciseDirectlyTargets(
                        groupAliases: aliases,
                        exerciseName: candidate.name,
                        muscleTarget: candidate.target
                    )
                }
                guard let expanded = menusByAppendingBalanceExercise(
                    to: updated,
                    blueprint: blueprint,
                    weekNumber: weekNumber,
                    avoidedExercises: avoidedExercises,
                    candidates: candidates,
                    deprioritizedDays: coveredDays
                ) else { break }

                updated = expanded
            }
        }

        return updated
    }

    // MARK: - Session Flow Re-Order

    /// Re-applies ORD-001 running order to every day after the coverage and repair passes.
    ///
    /// Each day is ordered once, during selection. Every pass after that — baseline coverage,
    /// priority feasibility, the knee anchor, and the two balance passes above — APPENDS to the
    /// end of a day, so whatever they added landed last regardless of what it was: a heavy
    /// compound injected to close a coverage gap sat after the isolation work. The menu is locked
    /// before the AI ever sees it and the prompt requires the given order, so last is where it
    /// stayed.
    ///
    /// Safe to run over an already-ordered day: the sort keys are the same ones selection used, so
    /// a day nothing was appended to comes back unchanged.
    func reorderedMenusForSessionFlow(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        trainingIntent: TrainingIntentPlan
    ) -> [[PreSelectedExercise]] {
        menus.indices.map { dayIndex -> [PreSelectedExercise] in
            let day = menus[dayIndex]
            guard dayIndex < blueprint.dayPlans.count,
                  !blueprint.dayPlans[dayIndex].isRestDay,
                  day.count > 1
            else { return day }

            // Re-keying below matches on name+target, so two slots sharing both would be
            // interchangeable and could swap each other's `prescribedSets`. Nothing should
            // produce that, and the day is left exactly as it is if anything ever does —
            // a silent set-count swap is a far worse outcome than an unsorted day.
            let identities = Set(day.map { "\($0.exerciseName)#\($0.muscleTarget)" })
            guard identities.count == day.count else { return day }

            let arranged = arrangeProceduralSelection(
                day.map { ($0.exerciseName, $0.muscleTarget) },
                lockedPrefixCount: 0,
                focusIntent: focusIntentForArea(
                    blueprint.dayPlans[dayIndex].focusArea,
                    within: trainingIntent
                )
            )

            // Re-key by identity rather than rebuilding the entries: `prescribedSets` and the
            // recorded role travel with the exercise, and re-deriving them here would silently
            // discard anything an earlier pass had already decided about this slot.
            var remaining = day
            let reordered = arranged.compactMap { item -> PreSelectedExercise? in
                guard let index = remaining.firstIndex(where: {
                    $0.exerciseName == item.name && $0.muscleTarget == item.target
                }) else { return nil }
                return remaining.remove(at: index)
            }

            // Ordering must never be able to LOSE a movement. If identity re-keying did not
            // account for every slot, keep the day exactly as it was.
            return reordered.count == day.count ? reordered : day
        }
    }

    // MARK: - Priority Direct-Set Feasibility (the "fight")

    /// Guarantees each priority actually has directly-crediting exercises spread across enough
    /// distinct training days that its weekly `directSetTarget` is reachable under the blueprint's
    /// per-session caps — BEFORE the allocator funds set counts.
    ///
    /// Without this, a small priority (e.g. Upper Chest, Lateral Deltoids) that the per-day
    /// selection only trained on its single focus day collapses the weekly ceiling to one
    /// session's cap (~8 sets). The allocator then physically cannot reach a ~10-set target, and
    /// the validator reports an unfixable "missed its direct-set target" — the exact failure this
    /// pass removes at the root. It mirrors `enforceBaselineMuscleCoverage`, but keyed on priority
    /// frequency/slot targets instead of zero-coverage, and it only ever swaps a redundant
    /// (duplicated-pattern, non-focus, non-anchor) slot, so no muscle loses its last exposure and
    /// no session grows in length. Menu-locked-safe: the deterministic builder owns the menu here,
    /// exactly where exercise selection is allowed to add work.
    func enforcePriorityDirectSetFeasibility(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint,
        trainingIntent: TrainingIntentPlan,
        avoidedExercises: Set<String>
    ) -> [[PreSelectedExercise]] {
        var updated = menus

        func credits(_ name: String, _ target: String, area: String) -> Bool {
            focusStimulusKind(
                exerciseName: name,
                muscleTarget: target,
                focusArea: area
            ) == .prime
        }

        for allocation in blueprint.priorityAllocations {
            func feasibilityCandidates() -> [(name: String, target: String)] {
                var seen = Set<String>()
                var candidates: [(name: String, target: String)] = []

                // Reuse established prime movements first. A repeated lift on a second day
                // creates another programmable slot without spending another variation.
                for exercise in updated.joined() {
                    let key = normalizeExerciseName(exercise.exerciseName)
                    guard !seen.contains(key) else { continue }
                    guard focusStimulusKind(
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget,
                        focusArea: allocation.area
                    ) == .prime else { continue }
                    seen.insert(key)
                    candidates.append((exercise.exerciseName, exercise.muscleTarget))
                }

                for candidate in metadataFocusExerciseCatalog(for: allocation.area) {
                    let key = normalizeExerciseName(candidate.name)
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    candidates.append(candidate)
                }
                return candidates
            }

            func creditingCount() -> Int {
                updated.joined().filter { credits($0.exerciseName, $0.muscleTarget, area: allocation.area) }.count
            }
            func creditingDays() -> Set<Int> {
                Set(updated.indices.filter { dayIndex in
                    updated[dayIndex].contains { credits($0.exerciseName, $0.muscleTarget, area: allocation.area) }
                })
            }

            let trainingDays = blueprint.dayPlans.indices.filter { dayIndex in
                guard dayIndex < updated.count else { return false }
                let plan = blueprint.dayPlans[dayIndex]
                return !plan.isRestDay && !updated[dayIndex].isEmpty
            }
            // The allocation names the session styles this priority belongs on, and this pass
            // used to ignore them entirely — any non-rest day would do. That is how a Lateral
            // Deltoids allocation declaring "Push, Upper, Arms" had its third exposure appended
            // to a PULL day the blueprint had assigned no lateral-delt pattern at all. The
            // `exerciseMatchesDayStyle` probe further down did not catch it, and could not: a
            // lateral raise is not illegal on a pull day. What was violated is the plan's own
            // statement about where this priority trains.
            //
            // Off-style days stay available as a last resort rather than being forbidden. A split
            // with no compatible day must still receive its priority work somewhere, and silently
            // dropping to zero coverage would be a worse answer than an imperfect placement.
            // `styleFeasibleAllocations` now trims the frequency target to the compatible days, so
            // in practice this fallback should only fire for a split with no compatible day at all.
            let styleCompatibleDays = trainingDays.filter { dayIndex in
                allocation.preferredStyles.contains(
                    canonicalTrainingStyle(blueprint.dayPlans[dayIndex].style)
                )
            }
            let candidateDays = styleCompatibleDays.isEmpty ? trainingDays : styleCompatibleDays
            guard !candidateDays.isEmpty else { continue }

            let neededDays = min(allocation.targetFrequency, candidateDays.count)
            // Enough weekly exercise slots that each occurrence can stay near the ~4-set ceiling.
            // A repeated movement on another day is a valid slot and is preferred over needless
            // within-week variation.
            let neededSlots = min(allocation.targetExerciseSlots, candidateDays.count * 2)

            var guardRail = neededSlots + candidateDays.count + 2
            while guardRail > 0 {
                guardRail -= 1
                let days = creditingDays()
                guard days.count < neededDays || creditingCount() < neededSlots else { break }

                // Prefer style-compatible days without priority coverage (raises both day count
                // and slot count); fall back to already-covered days (raises slot count only).
                let orderedDays = candidateDays.sorted { lhs, rhs in
                    let lhsUncovered = !days.contains(lhs)
                    let rhsUncovered = !days.contains(rhs)
                    if lhsUncovered != rhsUncovered { return lhsUncovered }
                    return lhs < rhs
                }

                var placed = false
                dayLoop: for dayIndex in orderedDays {
                    // Never over-stack one session with a single priority.
                    let dayCredits = updated[dayIndex].filter {
                        credits($0.exerciseName, $0.muscleTarget, area: allocation.area)
                    }.count
                    guard dayCredits < 2 else { continue }

                    let plan = blueprint.dayPlans[dayIndex]
                    let focusIntent = focusIntentForArea(plan.focusArea, within: trainingIntent)
                    let supportIntents = plan.supportAreas.compactMap { focusIntentForArea($0, within: trainingIntent) }

                    for candidate in feasibilityCandidates() {
                        let key = normalizeExerciseName(candidate.name)
                        guard !updated[dayIndex].contains(where: {
                            normalizeExerciseName($0.exerciseName) == key
                        }) else { continue }
                        guard !avoidedExercises.contains(ExerciseWeightEntry.canonicalLookupKey(candidate.name)) else { continue }
                        guard credits(candidate.name, candidate.target, area: allocation.area) else { continue }

                        let probe = WorkoutExerciseResponse(
                            exerciseName: candidate.name,
                            sets: 1,
                            reps: "",
                            tempo: "",
                            restSeconds: 0,
                            notes: "",
                            muscleTarget: candidate.target
                        )
                        guard exerciseMatchesDayStyle(probe, style: canonicalTrainingStyle(plan.style)) else { continue }
                        let replacementIndices = baselineCoverageReplacementIndices(
                            in: updated[dayIndex],
                            focusIntent: focusIntent,
                            supportIntents: supportIntents
                        )

                        // Priority coverage has the same capacity rule as BASE-001. Use an
                        // available validator-approved slot before asking a later fallback to
                        // trade away a baseline movement for another priority touch.
                        if updated[dayIndex].count < 8,
                           !blueprint.calibration.recoveryConstrained,
                           !blueprint.calibration.poorNutritionAdherence,
                           !updated[dayIndex].contains(where: {
                               normalizeExerciseName($0.exerciseName) == key
                           }),
                           dayPatternCapAllows(
                               candidateName: candidate.name,
                               candidateTarget: candidate.target,
                               in: updated[dayIndex].map { ($0.exerciseName, $0.muscleTarget) }
                           ),
                           menuPlanningBudgetAllows(
                               candidateName: candidate.name,
                               candidateTarget: candidate.target,
                               existingMenus: updated,
                               selectedToday: [],
                               blueprint: blueprint
                           ) {
                            let metadata = exerciseMetadata(forExerciseName: candidate.name, muscleTarget: candidate.target)
                            updated[dayIndex].append(PreSelectedExercise(
                                exerciseName: candidate.name,
                                muscleTarget: candidate.target,
                                movementPattern: metadata.movementPattern,
                                role: proceduralExerciseRole(for: candidate.name, muscleTarget: candidate.target),
                                prescribedSets: 1
                            ))
                            placed = true
                            break dayLoop
                        }

                        for replaceIndex in replacementIndices {
                            // Do not evict a slot that already credits this same priority (net-zero swap).
                            let evicted = updated[dayIndex][replaceIndex]
                            guard !credits(evicted.exerciseName, evicted.muscleTarget, area: allocation.area) else { continue }

                            // Priority feasibility is downstream of BASE-001. Never evict the
                            // only direct movement for another non-priority major group while
                            // trying to add a priority slot.
                            let baselineGapsBefore = Set(
                                baselineCoverageGaps(in: updated, blueprint: blueprint).map { $0.seed }
                            )
                            var menusWithoutReplacedSlot = updated
                            menusWithoutReplacedSlot[dayIndex].remove(at: replaceIndex)
                            let baselineGapsAfter = Set(
                                baselineCoverageGaps(in: menusWithoutReplacedSlot, blueprint: blueprint).map { $0.seed }
                            )
                            guard baselineGapsAfter.isSubset(of: baselineGapsBefore) else { continue }
                            guard menuPlanningBudgetAllows(
                                candidateName: candidate.name,
                                candidateTarget: candidate.target,
                                existingMenus: menusWithoutReplacedSlot,
                                selectedToday: [],
                                blueprint: blueprint
                            ) else { continue }

                            let metadata = exerciseMetadata(forExerciseName: candidate.name, muscleTarget: candidate.target)
                            updated[dayIndex][replaceIndex] = PreSelectedExercise(
                                exerciseName: candidate.name,
                                muscleTarget: candidate.target,
                                movementPattern: metadata.movementPattern,
                                role: proceduralExerciseRole(for: candidate.name, muscleTarget: candidate.target),
                                prescribedSets: 1
                            )
                            placed = true
                            break dayLoop
                        }
                    }
                }
                if !placed { break }
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
        // Every major group keeps a ledger. A prioritized group keeps a RESIDUE ledger — only the
        // work in it that no priority allocation pays for. Dropping prioritized groups entirely
        // (the previous behaviour) left that residue funded by nothing and capped by nothing: the
        // maintenance loop below skips any exercise whose `groupTargets` are all false, so a
        // rear-delt movement under a Lateral Deltoids priority never received a set from any loop
        // and shipped at the `minimumSetFloor` of 2 by default. See `exerciseCountsTowardMaintenance`.
        let maintenanceGroups = majorMuscleGroups.map { group in
            (
                label: group.label,
                aliases: normalizedGroupAliases(forSeed: group.seed),
                residueOnly: isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: blueprint)
            )
        }

        let allocations = blueprint.priorityAllocations

        // Precomputed per-exercise accounting. During allocation only `prescribedSets` changes —
        // exercise identity (name/target) is fixed — and stimulus credit is exactly linear in set
        // count, so each exercise's per-set ("unit") credit for a given priority is constant.
        // Precomputing it turns the coverage/maintenance ledgers from O(days x exercises x
        // response-build) rescans (rebuilding rep/tempo/rest strings only to read name/target/sets)
        // into cheap multiply-adds. This is the difference between ~200s and milliseconds per
        // generation for hard-to-fund small-muscle priorities. Numerically identical to the old path.
        struct ExerciseAccounting {
            var unitDirect: [Double]   // indexed by allocation index
            var unitWeighted: [Double] // indexed by allocation index
            var qualityScore: [Int]    // indexed by allocation index (prime 30 / sec 20 / support 10 / none 0)
            var groupTargets: [Bool]   // indexed by maintenance-group index
            var setFloor: Int          // `minimumSetFloor`, constant per exercise (role, not sets)
        }
        let accounting: [[ExerciseAccounting]] = allocated.map { day in
            day.map { exercise -> ExerciseAccounting in
                let unit = WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: 1,
                    reps: "",
                    tempo: "",
                    restSeconds: 0,
                    notes: "",
                    muscleTarget: exercise.muscleTarget
                )
                var unitDirect: [Double] = []
                var unitWeighted: [Double] = []
                var qualityScore: [Int] = []
                unitDirect.reserveCapacity(allocations.count)
                unitWeighted.reserveCapacity(allocations.count)
                qualityScore.reserveCapacity(allocations.count)
                for allocation in allocations {
                    let credit = stimulusCredit(for: unit, area: allocation.area)
                    unitDirect.append(credit.directSets)
                    unitWeighted.append(credit.weightedStimulus)
                    switch focusStimulusKind(
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget,
                        focusArea: allocation.area
                    ) {
                    case .prime: qualityScore.append(30)
                    case .secondary: qualityScore.append(20)
                    case .support: qualityScore.append(10)
                    case .none: qualityScore.append(0)
                    }
                }
                // Equivalent to `earnsDirectPriorityCredit(...)`, reusing the values just computed
                // rather than re-probing every allocation. The equivalence is not obvious and is
                // worth stating exactly: `unitDirect[i]` is `stimulusCredit(...).directSets`, and
                // `stimulusCredit` computes that field as literally `directSetCredit(for:area:)` —
                // the SAME call `earnsDirectPriorityCredit` makes. The secondary/quality credit
                // `stimulusCredit` also computes lands in `unitWeighted`, never here, so no
                // indirect work can leak into this classification.
                //
                // Do not "simplify" this to `unitWeighted` or to a `stimulusCredit(...)` truthiness
                // check: weighted credit includes secondary and support work, and using it would
                // pull genuinely un-funded residue OUT of the maintenance ledger and re-create the
                // starvation this fix exists to end. `ResidueMuscleDoseTests
                // .testAllocatorAndCanonicalPriorityCreditChecksAgree` pins the equivalence.
                let earnsPriorityCredit = unitDirect.contains { $0 > 0 }
                let groupTargets = maintenanceGroups.map { group -> Bool in
                    guard exerciseDirectlyTargets(
                        groupAliases: group.aliases,
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget
                    ) else { return false }
                    return group.residueOnly ? !earnsPriorityCredit : true
                }
                // Precomputed for the same reason as everything else here: `minimumSetFloor`
                // resolves the exercise's ROLE, which depends only on name and target, so it is
                // constant across allocation. Reading it per candidate per iteration would mean
                // rebuilding rep/tempo/rest strings inside the funding loops — the exact cost this
                // accounting struct exists to avoid.
                let setFloor = minimumSetFloor(
                    for: WorkoutExerciseResponse(
                        exerciseName: exercise.exerciseName,
                        sets: 1,
                        reps: "",
                        tempo: "",
                        restSeconds: 0,
                        notes: "",
                        muscleTarget: exercise.muscleTarget
                    )
                )
                return ExerciseAccounting(
                    unitDirect: unitDirect,
                    unitWeighted: unitWeighted,
                    qualityScore: qualityScore,
                    groupTargets: groupTargets,
                    setFloor: setFloor
                )
            }
        }
        // Whether each day's focus area matches each priority (stable; used for focus caps/bonuses).
        let focusMatch: [[Bool]] = blueprint.dayPlans.indices.map { dayIndex in
            allocations.map { allocation in
                blueprint.dayPlans[dayIndex].focusArea.map {
                    normalizedPriorityText($0) == normalizedPriorityText(allocation.area)
                } ?? false
            }
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

        func maintenanceSets(groupIndex: Int, addingAt location: (Int, Int)? = nil) -> Double {
            var total = 0.0
            for dayIndex in allocated.indices {
                for exerciseIndex in allocated[dayIndex].indices
                    where accounting[dayIndex][exerciseIndex].groupTargets[groupIndex] {
                    let extra = location?.0 == dayIndex && location?.1 == exerciseIndex ? 1 : 0
                    total += Double(allocated[dayIndex][exerciseIndex].prescribedSets + extra)
                }
            }
            return total
        }

        func priorityCoverage(
            allocIndex: Int,
            addingAt location: (Int, Int)? = nil
        ) -> (direct: Double, weighted: Double) {
            var direct = 0.0
            var weighted = 0.0
            for dayIndex in allocated.indices {
                for exerciseIndex in allocated[dayIndex].indices {
                    let extra = location?.0 == dayIndex && location?.1 == exerciseIndex ? 1 : 0
                    let sets = Double(allocated[dayIndex][exerciseIndex].prescribedSets + extra)
                    let acct = accounting[dayIndex][exerciseIndex]
                    direct += sets * acct.unitDirect[allocIndex]
                    weighted += sets * acct.unitWeighted[allocIndex]
                }
            }
            return (direct, weighted)
        }

        func canAddSet(dayIndex: Int, exerciseIndex: Int, allowFloorOvershoot: Bool = false) -> Bool {
            let exercise = allocated[dayIndex][exerciseIndex]
            let roleDefault = proceduralSets(
                for: weekNumber,
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget
            )
            let isPrimePriorityExercise = allocations.indices.contains { allocIndex in
                accounting[dayIndex][exerciseIndex].unitDirect[allocIndex] > 0
                    && accounting[dayIndex][exerciseIndex].qualityScore[allocIndex] == 30
            }
            // SLOT-001's feasibility floor assumes a prime priority slot can hold about four
            // sets. Honor that same ceiling here instead of creating a plan that promises
            // 12 sets across three slots and then caps every accessory at three.
            let setCeiling = isPrimePriorityExercise ? max(roleDefault, 4) : roleDefault
            guard exercise.prescribedSets < setCeiling else { return false }

            for groupIndex in maintenanceGroups.indices
                where accounting[dayIndex][exerciseIndex].groupTargets[groupIndex] {
                guard maintenanceSets(
                    groupIndex: groupIndex,
                    addingAt: (dayIndex, exerciseIndex)
                ) <= maintenanceCeiling + 0.01 else { return false }
            }

            // A set funded for one priority may also credit another. Check every weekly ledger
            // jointly so shared Chest/Triceps or Quads/Glutes work cannot overfill a later
            // priority before its own allocation pass begins.
            for allocIndex in allocations.indices {
                let current = priorityCoverage(allocIndex: allocIndex)
                let projected = priorityCoverage(
                    allocIndex: allocIndex,
                    addingAt: (dayIndex, exerciseIndex)
                )
                let addsDirectCredit = projected.direct > current.direct + 0.01
                // Normal funding stops at the soft weekly target. The floor pass may overshoot
                // it to buy a movement a real minimum dose, but must stay under the menu-locked
                // over-volume HARD-fail line (validator: directSets > target * moderateMultiplier
                // + moderateBuffer), or it would trade fragmentation for a deterministic,
                // unrepairable generation failure. The -0.02 margin absorbs the 0.01 allocator/
                // validator ledger tolerance on each side.
                let ceiling: Double
                if allowFloorOvershoot {
                    let moderateMultiplier = recoveryTight ? 1.15 : 1.3
                    let moderateBuffer = recoveryTight ? 0.0 : 0.5
                    ceiling = allocations[allocIndex].directSetTarget * moderateMultiplier
                        + moderateBuffer - 0.02
                } else {
                    ceiling = allocations[allocIndex].directSetTarget + 0.01
                }
                guard !addsDirectCredit || projected.direct <= ceiling else {
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

            for allocIndex in allocations.indices {
                guard accounting[dayIndex][exerciseIndex].unitDirect[allocIndex] > 0 else { continue }
                var dayDirectSets = 0.0
                for index in allocated[dayIndex].indices {
                    let extra = index == exerciseIndex ? 1 : 0
                    dayDirectSets += Double(allocated[dayIndex][index].prescribedSets + extra)
                        * accounting[dayIndex][index].unitDirect[allocIndex]
                }
                let cap = focusMatch[dayIndex][allocIndex]
                    ? allocations[allocIndex].maxFocusSessionDirectSets
                    : allocations[allocIndex].maxPerSessionDirectSets
                guard dayDirectSets <= cap + 0.01 else { return false }
            }

            return true
        }

        // Fund blueprint priorities before distributing maintenance volume.
        for allocIndex in allocations.indices {
            let allocation = allocations[allocIndex]
            let meaningfulThreshold = minimumMeaningfulPriorityExposureSets(for: allocation.area)
            let candidateDays = allocated.indices
                .filter { dayIndex in
                    allocated[dayIndex].indices.contains { exerciseIndex in
                        accounting[dayIndex][exerciseIndex].unitDirect[allocIndex] > 0
                    }
                }
                .sorted { lhs, rhs in
                    let lhsFocus = focusMatch[lhs][allocIndex]
                    let rhsFocus = focusMatch[rhs][allocIndex]
                    if lhsFocus != rhsFocus { return lhsFocus }
                    return lhs < rhs
                }

            // Establish distinct meaningful exposures first so the weekly total cannot be
            // concentrated into one impressive-looking day while frequency quietly misses.
            for dayIndex in candidateDays.prefix(allocation.targetFrequency) {
                var exposureGuardRail = 12
                while exposureGuardRail > 0 {
                    exposureGuardRail -= 1
                    var dayDirectSets = 0.0
                    for exerciseIndex in allocated[dayIndex].indices {
                        dayDirectSets += Double(allocated[dayIndex][exerciseIndex].prescribedSets)
                            * accounting[dayIndex][exerciseIndex].unitDirect[allocIndex]
                    }
                    guard dayDirectSets + 0.01 < meaningfulThreshold else { break }

                    let candidates = allocated[dayIndex].indices.compactMap { exerciseIndex -> (Int, Int)? in
                        guard canAddSet(dayIndex: dayIndex, exerciseIndex: exerciseIndex) else { return nil }
                        guard accounting[dayIndex][exerciseIndex].unitDirect[allocIndex] > 0 else { return nil }
                        let qualityScore = accounting[dayIndex][exerciseIndex].qualityScore[allocIndex]
                        return (exerciseIndex, qualityScore - allocated[dayIndex][exerciseIndex].prescribedSets)
                    }
                    guard let target = candidates.max(by: { $0.1 < $1.1 }) else { break }
                    allocated[dayIndex][target.0].prescribedSets += 1
                }
            }

            var guardRail = 80
            while guardRail > 0 {
                guardRail -= 1
                let current = priorityCoverage(allocIndex: allocIndex)
                guard current.direct + 0.01 < allocation.directSetTarget
                        || current.weighted + 0.01 < allocation.weightedStimulusTarget else { break }

                let candidates = allocated.indices.flatMap { dayIndex in
                    allocated[dayIndex].indices.compactMap { exerciseIndex -> (Int, Int, Int)? in
                        guard canAddSet(dayIndex: dayIndex, exerciseIndex: exerciseIndex) else { return nil }
                        let acct = accounting[dayIndex][exerciseIndex]
                        guard acct.unitDirect[allocIndex] > 0 || acct.unitWeighted[allocIndex] > 0 else { return nil }
                        let focusBonus = focusMatch[dayIndex][allocIndex] ? 5 : 0
                        // Floor first, quality second. This loop optimizes WEEKLY AGGREGATE volume
                        // and is otherwise indifferent to how that volume lands per movement, so
                        // quality score decides everything: a prime movement already at three sets
                        // scores 30-3=27 and beats an accessory still sitting at its seed of one,
                        // which scores 10-1=9. The prime keeps winning until the weekly target is
                        // met, the budget is gone, and the accessory is stranded at ONE SET — below
                        // `minimumSetFloor`, and unfixable by the floor pass afterwards because
                        // lifting it would cross the over-volume hard-fail line the earlier sets
                        // already spent. The recovery-tight regression fixture shipped exactly that:
                        // "Behind-the-Back Cable Lateral Raise#1" on day 1, four distinct lateral
                        // raises sharing an ~11.5-set budget.
                        //
                        // A bonus larger than any quality score guarantees every movement reaches a
                        // dose worth performing before any movement is pushed beyond it. Nothing is
                        // spent that would not have been spent anyway — only the order changes —
                        // and `canAddSet` still owns every ceiling.
                        let belowFloorBonus = allocated[dayIndex][exerciseIndex].prescribedSets < acct.setFloor ? 100 : 0
                        return (dayIndex, exerciseIndex, acct.qualityScore[allocIndex] + focusBonus + belowFloorBonus - allocated[dayIndex][exerciseIndex].prescribedSets)
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
                    let targetsMaintenance = accounting[dayIndex][exerciseIndex].groupTargets.contains(true)
                    guard targetsMaintenance else { continue }
                    guard canAddSet(dayIndex: dayIndex, exerciseIndex: exerciseIndex) else { continue }
                    allocated[dayIndex][exerciseIndex].prescribedSets += 1
                    madeProgress = true
                }
            }
        }

        // Per-exercise minimum-dose floor. The funding loops above optimize weekly aggregate
        // priority/maintenance volume and are indifferent to how it lands per movement, so an
        // exercise can still sit at the seed value of one set — below the two-set (accessory/
        // secondary) / three-set (anchor) floor `minimumSetFloor` treats as the minimum worth
        // programming and that the reduction path already refuses to cross. Lift every under-floor
        // exercise to its role floor wherever recoverability allows, reusing canAddSet's hard-fail
        // guards (day fatigue, session time, per-session and maintenance ceilings) with a bounded
        // overshoot of the soft weekly target so a real dose never tips into an over-volume hard
        // failure. The priority/maintenance breadth gates keep this from having much to do; this
        // is the belt-and-suspenders guarantee that nothing ships below its floor.
        for dayIndex in allocated.indices {
            for exerciseIndex in allocated[dayIndex].indices {
                let floor = minimumSetFloor(
                    for: response(dayIndex: dayIndex, exerciseIndex: exerciseIndex)
                )
                while allocated[dayIndex][exerciseIndex].prescribedSets < floor
                    && canAddSet(
                        dayIndex: dayIndex,
                        exerciseIndex: exerciseIndex,
                        allowFloorOvershoot: true
                    ) {
                    allocated[dayIndex][exerciseIndex].prescribedSets += 1
                }
            }
        }

        let consistencyIssues = allocationLedgerConsistencyIssues(
            allocated,
            blueprint: blueprint
        )
        assert(
            consistencyIssues.isEmpty,
            "Weekly allocation and validator stimulus ledgers diverged: \(consistencyIssues.joined(separator: " | "))"
        )
        return allocated
    }

    /// The allocator and validator must derive identical priority totals from the locked menu.
    /// Keeping this check at the planning boundary prevents a future accounting change from
    /// producing a menu that looks funded to allocation but deterministically fails validation.
    func allocationLedgerConsistencyIssues(
        _ menus: [[PreSelectedExercise]],
        blueprint: ProgramBlueprint
    ) -> [String] {
        let days = menus.indices.map { dayIndex in
            let exercises = menus[dayIndex].map { exercise in
                WorkoutExerciseResponse(
                    exerciseName: exercise.exerciseName,
                    sets: exercise.prescribedSets,
                    reps: "",
                    tempo: "",
                    restSeconds: 0,
                    notes: "",
                    muscleTarget: exercise.muscleTarget
                )
            }
            return WorkoutDayResponse(
                dayNumber: dayIndex + 1,
                dayName: "Planning Day \(dayIndex + 1)",
                muscleGroups: "Planning",
                isRestDay: exercises.isEmpty,
                notes: "",
                exercises: exercises
            )
        }
        let report = buildWeekStimulusReport(from: days)

        return blueprint.priorityAllocations.compactMap { allocation in
            let allocated = days.reduce(into: StimulusCredit.none) { total, day in
                for exercise in day.exercises {
                    let credit = stimulusCredit(for: exercise, area: allocation.area)
                    total = StimulusCredit(
                        directSets: total.directSets + credit.directSets,
                        weightedStimulus: total.weightedStimulus + credit.weightedStimulus
                    )
                }
            }
            let validated = priorityCoverage(for: allocation, stimulusReport: report)
            guard abs(allocated.directSets - validated.directSets) > 0.01
                    || abs(allocated.weightedStimulus - validated.weightedStimulus) > 0.01 else {
                return nil
            }
            return "\(allocation.area): allocator \(formatStimulusValue(allocated.directSets))/\(formatStimulusValue(allocated.weightedStimulus)), validator \(formatStimulusValue(validated.directSets))/\(formatStimulusValue(validated.weightedStimulus))"
        }
    }

    /// Slots the coverage pass may sacrifice, in preference order: first duplicated-pattern
    /// movements, then other non-focus/support non-anchor movements. Returning all legal slots
    /// matters because the first candidate can be the only exposure for another baseline group.
    func baselineCoverageReplacementIndices(
        in menu: [PreSelectedExercise],
        focusIntent: MusclePriorityIntent?,
        supportIntents: [MusclePriorityIntent]
    ) -> [Int] {
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

        let redundantIndices = menu.indices.reversed().filter { index in
            patternCounts[menu[index].movementPattern, default: 0] > 1
                && !matchesDayIntent(menu[index])
                && menu[index].role != .anchor
        }
        let otherEligibleIndices = menu.indices.reversed().filter { index in
            !matchesDayIntent(menu[index])
                && menu[index].role != .anchor
                && !redundantIndices.contains(index)
        }
        return redundantIndices + otherEligibleIndices
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
