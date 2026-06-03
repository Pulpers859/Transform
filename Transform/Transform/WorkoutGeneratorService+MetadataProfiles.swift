import Foundation

extension ClaudeService {
    func canonicalPriorityAreaName(_ focusArea: String) -> String {
        let trimmed = focusArea.trimmedOr(default: "")
        guard !trimmed.isEmpty else { return focusArea }
        return priorityProfile(for: trimmed).label
    }

    func canonicalExerciseName(_ exerciseName: String, muscleTarget: String) -> String {
        let trimmed = exerciseName.trimmedOr(default: "Exercise")
        let normalized = normalizeExerciseName(trimmed)

        if let alias = Self.exerciseNameAliasCache[normalized] {
            return alias
        }

        if let metadata = exerciseMetadataCatalog[normalized] {
            return metadata.canonicalName
        }

        if normalized.contains("face pull") {
            return normalized.contains("external rotation")
                ? "Face Pull with External Rotation"
                : "Face Pull"
        }

        if normalized.contains("rope pushdown") {
            return "Rope Triceps Pressdown"
        }

        if normalized.contains("tricep pushdown") || normalized.contains("triceps pushdown") {
            return normalized.contains("rope")
                ? "Rope Triceps Pressdown"
                : "Cable Triceps Pressdown"
        }

        if normalized.contains("hammer curl") {
            return normalized.contains("cable")
                ? "Cable Hammer Curl"
                : "Hammer Curl"
        }

        if normalized == "barbell curls" || normalized == "barbell curl" {
            return "Barbell Curl"
        }

        if normalized == "barbell shrugs" || normalized == "barbell shrug" {
            return "Barbell Shrug"
        }

        if normalized == "band pull aparts" || normalized == "band pull apart" {
            return "Band Pull-Apart"
        }

        if normalized == "lying leg curls" || normalized == "lying leg curl" {
            return "Lying Leg Curl"
        }

        return trimmed
    }

    func stimulusAreaAliases(for focusArea: String) -> [String] {
        let normalized = normalizedPriorityText(focusArea)

        if normalized.contains("lateral delt") || normalized.contains("side delt") {
            return ["Lateral Deltoids"]
        }
        if normalized.contains("rear delt") || normalized.contains("posterior delt") {
            return ["Rear Deltoids", "Posterior Deltoids"]
        }
        if normalized.contains("front delt") || normalized.contains("anterior delt") {
            return ["Anterior Deltoids", "Front Deltoids"]
        }
        if normalized.contains("bicep") {
            return ["Biceps"]
        }
        if normalized.contains("tricep") {
            return ["Triceps"]
        }
        if normalized.contains("brachialis") {
            return ["Brachialis"]
        }
        if normalized.contains("forearm") {
            return ["Forearms"]
        }
        if normalized.contains("upper chest") || normalized.contains("clavicular") {
            return ["Upper Chest"]
        }
        if normalized == "chest" || normalized.contains("pec") {
            return ["Chest", "Upper Chest"]
        }
        if normalized == "lat" || normalized == "lats" || normalized.contains("lat width") {
            return ["Lats"]
        }
        if normalized.contains("upper back") {
            return ["Upper Back"]
        }
        if normalized.contains("mid back") {
            return ["Mid Back"]
        }
        if normalized.contains("shoulder") || normalized.contains("delt") {
            return ["Shoulders", "Deltoids", "Lateral Deltoids", "Rear Deltoids", "Anterior Deltoids"]
        }
        if containsPriorityPhrase(in: normalized, keywords: ["back", "lat", "lats", "latissimus dorsi", "latissimus"]) {
            return ["Back", "Lats", "Upper Back", "Mid Back"]
        }
        if normalized.contains("arm") {
            return ["Arms", "Biceps", "Triceps", "Brachialis", "Forearms"]
        }
        if normalized.contains("oblique") {
            return ["Obliques"]
        }
        if normalized.contains("serratus") {
            return ["Serratus"]
        }
        if normalized.contains("lower abs") {
            return ["Lower Abs"]
        }
        if normalized.contains("anterior core") {
            return ["Anterior Core"]
        }
        if normalized == "abs" || normalized.contains("rectus") {
            return ["Abs", "Lower Abs"]
        }
        if normalized.contains("core") || normalized.contains("abs") || normalized.contains("oblique") || normalized.contains("serratus") {
            return ["Core/Abs", "Abs", "Lower Abs", "Anterior Core", "Obliques", "Serratus"]
        }
        if normalized.contains("glute") {
            return ["Glutes", "Quads/Glutes", "Posterior Chain"]
        }
        if normalized.contains("quad") {
            return ["Quads", "Quads/Glutes"]
        }
        if normalized.contains("hamstring") {
            return ["Hamstrings", "Posterior Chain"]
        }
        if normalized.contains("calf") {
            return ["Calves"]
        }

        return [focusArea]
    }

    func validateDayPlans(
        days: [WorkoutDayResponse],
        blueprint: ProgramBlueprint,
        dayStart: Int
    ) -> [String] {
        var issues: [String] = []
        let stimulusReport = buildWeekStimulusReport(from: days)

        for plan in blueprint.dayPlans {
            let actualDayNumber = blueprintDayNumber(plan.dayIndex, dayStart: dayStart)
            guard let actualDay = days.first(where: { $0.dayNumber == actualDayNumber }) else {
                issues.append("Blueprint day \(plan.dayIndex) is missing from the generated output.")
                continue
            }

            if plan.isRestDay {
                if !actualDay.isRestDay {
                    issues.append(
                        "Blueprint day \(plan.dayIndex) was planned as a rest/recovery day, but the generated output turned it into a training session."
                    )
                }
                continue
            }

            if actualDay.isRestDay {
                issues.append(
                    "Blueprint day \(plan.dayIndex) expected a \(plan.style) training session, but the generated output made it a rest day."
                )
                continue
            }

            let actualStyle = inferredDayStyle(dayName: actualDay.dayName, muscleGroups: actualDay.muscleGroups)
            if let actualStyle,
               shouldFlagStyleMismatch(
                   expectedStyle: plan.style,
                   actualStyle: actualStyle,
                   day: actualDay
               ) {
                issues.append(
                    "Blueprint day \(plan.dayIndex) expected a \(plan.style) session, but the generated day reads as \(actualStyle)."
                )
            } else if actualStyle == nil,
                      !dayClearlySupportsExpectedStyle(plan.style, day: actualDay) {
                issues.append(
                    "Blueprint day \(plan.dayIndex) expected a \(plan.style) session, but the generated day does not clearly support that style."
                )
            }

            if let focusArea = plan.focusArea,
               !normalizedPriorityText("\(actualDay.dayName) \(actualDay.muscleGroups) \(actualDay.notes)").contains(normalizedPriorityText(focusArea)),
               !actualDay.exercises.contains(where: { exercise in
                   let text = normalizedPriorityText("\(exercise.exerciseName) \(exercise.muscleTarget)")
                   return containsAny(text, keywords: priorityCoverageKeywords(for: focusArea))
               }) {
                issues.append(
                    "Blueprint day \(plan.dayIndex) was supposed to emphasize \(focusArea), but the generated session does not clearly reflect that."
                )
            }

            if let focusArea = plan.focusArea {
                let focusSummary = focusStimulusSummary(for: actualDay, focusArea: focusArea)
                let focusDayDirectSets = focusSummary.qualityDirectSets
                let minimumUsefulDirectSets = Double(max(3, plan.targetPrioritySlots * 2))

                if focusSummary.matchedExercises < plan.targetPrioritySlots
                    && focusDayDirectSets + 0.01 < minimumUsefulDirectSets {
                    // EvidenceProfile.md SLOT-001 [confidence: moderate]
                    issues.append(
                        "Blueprint day \(plan.dayIndex) was planned for \(plan.targetPrioritySlots) \(focusArea) priority slots, but only \(focusSummary.matchedExercises) exercises clearly support that focus and the session only delivered \(formatStimulusValue(focusDayDirectSets)) quality direct sets to that area."
                    )
                }

                if focusSummary.primeExercises == 0 {
                    issues.append(
                        "Blueprint day \(plan.dayIndex) targets \(focusArea), but never includes a prime hypertrophy movement for that focus."
                    )
                }

                if focusSummary.firstMatchedKind == .support,
                   focusSummary.firstPrimeIndex != nil {
                    issues.append(
                        "Blueprint day \(plan.dayIndex) opens its \(focusArea) focus with support/corrective work before the main hypertrophy movement. Put the prime growth slot first."
                    )
                }

                if focusSummary.supportExercises >= 2 && focusSummary.primeExercises <= 1 {
                    issues.append(
                        "Blueprint day \(plan.dayIndex) spends too many \(focusArea) slots on support/corrective work instead of prime hypertrophy work."
                    )
                }
            }

            issues.append(contentsOf: validateSessionFocusDiscipline(
                on: actualDay,
                expectedStyle: plan.style,
                focusArea: plan.focusArea,
                supportAreas: plan.supportAreas
            ))
            issues.append(contentsOf: validateSessionTimeBudget(on: actualDay, budgetMinutes: plan.targetSessionMinutes))
            issues.append(contentsOf: validateSessionNoteAlignment(on: actualDay))
            issues.append(contentsOf: validateInjuryRiskAlignment(
                on: actualDay,
                injuryRiskFocus: blueprint.injuryRiskFocus
            ))
            issues.append(contentsOf: validateJointStressBudget(on: actualDay))
            issues.append(contentsOf: validateNoteContradictions(
                on: actualDay,
                blueprint: blueprint,
                dayStart: dayStart
            ))
            issues.append(contentsOf: validateRedundantPriorityVolume(
                on: actualDay,
                dayPlan: plan,
                blueprint: blueprint,
                stimulusReport: stimulusReport,
                dayStart: dayStart
            ))
        }

        return issues
    }

    func validateSessionTimeBudget(on day: WorkoutDayResponse, budgetMinutes: Int) -> [String] {
        guard budgetMinutes > 0, !day.isRestDay else { return [] }

        let estimatedMinutes = estimatedSessionMinutes(for: day)
        guard estimatedMinutes > budgetMinutes + 5 else { return [] }

        return [
            "Day \(day.dayNumber) is likely to run about \(estimatedMinutes) minutes, which exceeds its ~\(budgetMinutes)-minute session budget. Trim low-value accessories or simplify setup instead of letting the session bloat."
        ]
    }

    func estimatedSessionMinutes(for day: WorkoutDayResponse) -> Int {
        guard !day.isRestDay else { return 0 }

        let warmupMinutes = 8.0
        let exerciseMinutes = day.exercises.reduce(0.0) { partialResult, exercise in
            partialResult + estimatedExerciseMinutes(for: exercise)
        }

        return Int(ceil(warmupMinutes + exerciseMinutes))
    }

    func estimatedExerciseMinutes(for exercise: WorkoutExerciseResponse) -> Double {
        let metadata = exerciseMetadata(for: exercise)
        let role = proceduralExerciseRole(for: exercise.exerciseName, muscleTarget: exercise.muscleTarget)

        let activeSecondsPerSet: Double
        switch role {
        case .anchor:
            activeSecondsPerSet = 45
        case .secondary:
            activeSecondsPerSet = 40
        case .accessory:
            activeSecondsPerSet = 35
        case .core:
            activeSecondsPerSet = 30
        }

        let rampAndSetupMinutes: Double
        switch role {
        case .anchor:
            rampAndSetupMinutes = metadata.fatigueCost >= 3 ? 6.0 : 5.0
        case .secondary:
            rampAndSetupMinutes = 4.0
        case .accessory:
            rampAndSetupMinutes = 2.0
        case .core:
            rampAndSetupMinutes = 1.5
        }

        let activeMinutes = (Double(exercise.sets) * activeSecondsPerSet) / 60.0
        let restMinutes = (Double(max(0, exercise.sets - 1)) * Double(exercise.restSeconds)) / 60.0
        return activeMinutes + restMinutes + rampAndSetupMinutes
    }

    func shouldFlagStyleMismatch(
        expectedStyle: String,
        actualStyle: String,
        day: WorkoutDayResponse
    ) -> Bool {
        let expectedCanonical = canonicalTrainingStyle(expectedStyle)
        let actualCanonical = canonicalTrainingStyle(actualStyle)

        guard expectedCanonical.lowercased() != actualCanonical.lowercased() else {
            return false
        }

        return !dayClearlySupportsExpectedStyle(expectedCanonical, day: day)
    }

    func dayClearlySupportsExpectedStyle(_ expectedStyle: String, day: WorkoutDayResponse) -> Bool {
        let expectedCanonical = canonicalTrainingStyle(expectedStyle)
        let totalExercises = day.exercises.count
        guard totalExercises > 0 else { return false }

        let expectedMatches = day.exercises.filter { exerciseMatchesDayStyle($0, style: expectedCanonical) }.count
        let pushMatches = day.exercises.filter { exerciseMatchesDayStyle($0, style: "Push") }.count
        let pullMatches = day.exercises.filter { exerciseMatchesDayStyle($0, style: "Pull") }.count
        let lowerMatches = day.exercises.filter { exerciseMatchesDayStyle($0, style: "Lower") }.count

        switch expectedCanonical {
        case "Push":
            let requiredMatches = max(3, totalExercises - 2)
            return expectedMatches >= requiredMatches && pullMatches <= 1
        case "Pull":
            let requiredMatches = max(3, totalExercises - 2)
            return expectedMatches >= requiredMatches && pushMatches <= 1
        case "Upper":
            return pushMatches >= 2 && pullMatches >= 2 && lowerMatches == 0
        case "Arms":
            return expectedMatches >= max(3, totalExercises - 1) && lowerMatches == 0
        case "Lower":
            return expectedMatches >= max(3, totalExercises - 2)
        default:
            return false
        }
    }

    func directSets(on day: WorkoutDayResponse, forFocusArea focusArea: String) -> Double {
        return day.exercises.reduce(0) { partialResult, exercise in
            let kind = focusStimulusKind(
                exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget,
                focusArea: focusArea
            )
            return partialResult + (Double(exercise.sets) * focusStimulusCredit(for: kind))
        }
    }

    func validatePrescriptionUniformity(on day: WorkoutDayResponse) -> [String] {
        guard day.exercises.count >= 4 else { return [] }

        let roles = day.exercises.map {
            proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget)
        }
        let roleSet = Set(roles.map(\.rawValue))
        let hasCompoundRole = roles.contains(.anchor) || roles.contains(.secondary)
        let hasAccessoryRole = roles.contains(.accessory)

        guard roleSet.count >= 2, hasCompoundRole, hasAccessoryRole else {
            return []
        }

        var issues: [String] = []
        let uniqueRests = Set(day.exercises.map(\.restSeconds))
        if uniqueRests.count == 1 {
            issues.append(
                "Day \(day.dayNumber) uses one identical rest prescription across compounds and accessories. Rest should reflect exercise role instead of being templated."
            )
        }

        let tempoApplicableExercises = day.exercises.filter {
            requiresExplicitTempo(
                exerciseName: $0.exerciseName,
                muscleTarget: $0.muscleTarget,
                reps: $0.reps
            )
        }
        let normalizedTempos = Set(tempoApplicableExercises.map { normalizedTempo($0.tempo) ?? $0.tempo })
        if tempoApplicableExercises.count >= 2 && normalizedTempos.count == 1 {
            issues.append(
                "Day \(day.dayNumber) uses one identical tempo prescription across mixed exercise roles. Tempo should be role-aware, not copy-pasted."
            )
        }

        return issues
    }

    func validateSessionFocusDiscipline(
        on day: WorkoutDayResponse,
        expectedStyle: String,
        focusArea: String?,
        supportAreas: [String]
    ) -> [String] {
        let expectedCanonical = canonicalTrainingStyle(expectedStyle)
        let driftExercises = day.exercises.filter { exercise in
            let normalizedName = normalizeExerciseName(exercise.exerciseName)
            if isSupportOrCorrectivePattern(normalizedName) {
                return false
            }

            let supportsStyle = exerciseMatchesDayStyle(exercise, style: expectedCanonical)
            let supportsFocus = focusArea.map {
                focusStimulusKind(
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget,
                    focusArea: $0
                ) != .none
            } ?? false
            let supportsCompanion = supportAreas.contains { area in
                focusStimulusKind(
                    exerciseName: exercise.exerciseName,
                    muscleTarget: exercise.muscleTarget,
                    focusArea: area
                ) != .none
            }

            return !supportsStyle && !supportsFocus && !supportsCompanion
        }

        var issues: [String] = []
        if !driftExercises.isEmpty, day.exercises.count >= 6 {
            let driftNames = driftExercises.prefix(2).map(\.exerciseName).joined(separator: ", ")
            issues.append(
                "Day \(day.dayNumber) includes low-value filler that does not clearly support the \(expectedCanonical) theme or the planned priorities (\(driftNames)). Trim the noise and keep the session more disciplined."
            )
        }

        issues.append(contentsOf: validateArmsDayShoulderStress(
            on: day,
            expectedStyle: expectedCanonical,
            focusArea: focusArea
        ))

        if expectedCanonical == "Lower" && day.exercises.count >= 7 {
            issues.append(
                "Day \(day.dayNumber) is too crowded for a fatigue-managed Lower session. In a shift-work recomposition block, prefer fewer high-value lower-body movements over extra filler."
            )
        }

        issues.append(contentsOf: validateLowerSessionBalance(
            on: day,
            expectedStyle: expectedCanonical,
            focusArea: focusArea
        ))

        return issues
    }

    func validateRedundantPriorityVolume(
        on day: WorkoutDayResponse,
        dayPlan: BlueprintDayPlan,
        blueprint: ProgramBlueprint,
        stimulusReport: WeekStimulusReport,
        dayStart: Int
    ) -> [String] {
        guard !day.isRestDay else { return [] }
        var issues: [String] = []

        for allocation in blueprint.priorityAllocations {
            let coverage = priorityCoverage(for: allocation, stimulusReport: stimulusReport)
            guard coverage.directSets > allocation.directSetTarget else { continue }

            let allocatedDays = allocatedDayNumbers(for: allocation, blueprint: blueprint, dayStart: dayStart)
            guard !allocatedDays.contains(day.dayNumber) else { continue }

            let redundantExercises = day.exercises.filter {
                directSetCredit(for: $0, area: allocation.area) > 0
            }
            guard !redundantExercises.isEmpty else { continue }

            let names = redundantExercises.prefix(2).map(\.exerciseName).joined(separator: ", ")
            issues.append(
                "Day \(day.dayNumber): \(allocation.area) already reached its weekly target (\(formatStimulusValue(coverage.directSets))/\(formatStimulusValue(allocation.directSetTarget))), but this non-focus day still adds volume via \(names). Remove or replace with work that serves an unmet target."
            )
        }

        return issues
    }

    func validateArmsDayShoulderStress(
        on day: WorkoutDayResponse,
        expectedStyle: String,
        focusArea: String?
    ) -> [String] {
        guard expectedStyle == "Arms" else { return [] }

        let normalizedFocus = normalizedPriorityText(focusArea ?? "")
        let isDeltBiasedArmDay = normalizedFocus.contains("lateral delt")
            || normalizedFocus.contains("side delt")
            || normalizedFocus.contains("shoulder")
        guard isDeltBiasedArmDay else { return [] }

        let shoulderIntensivePresses = day.exercises.filter { exercise in
            let normalizedName = normalizeExerciseName(exercise.exerciseName)
            return containsAny(
                normalizedName,
                keywords: [
                    "close grip bench",
                    "close-grip bench",
                    "dip",
                    "shoulder press",
                    "overhead press",
                    "arnold press"
                ]
            )
        }

        guard !shoulderIntensivePresses.isEmpty else { return [] }

        let names = shoulderIntensivePresses.prefix(2).map(\.exerciseName).joined(separator: ", ")
        return [
            "Day \(day.dayNumber) uses shoulder-intensive pressing on an Arms/Lateral focus day (\(names)). Prefer cable or machine arm work so the lateral-delt exposure does not add avoidable anterior-shoulder stress."
        ]
    }

    func validateLowerSessionBalance(
        on day: WorkoutDayResponse,
        expectedStyle: String,
        focusArea: String?
    ) -> [String] {
        guard expectedStyle == "Lower" || expectedStyle == "Legs" else { return [] }

        let normalizedFocus = normalizedPriorityText(focusArea ?? "")
        let explicitPosteriorBias = containsAny(
            normalizedFocus,
            keywords: ["glute", "hamstring", "posterior chain"]
        )
        let explicitQuadBias = containsAny(normalizedFocus, keywords: ["quad"])
        let metadataByExercise = day.exercises.map { exerciseMetadata(for: $0) }

        let kneeDominantAnchorCount = metadataByExercise.filter { metadata in
            ["Squat", "Press", "Extension"].contains(metadata.movementPattern)
        }.count
        let unilateralLowerCount = metadataByExercise.filter { metadata in
            ["Split Squat", "Lunge"].contains(metadata.movementPattern)
        }.count
        let hipDominantCount = metadataByExercise.filter { metadata in
            ["Hinge", "Hip Thrust", "Glute"].contains(metadata.movementPattern)
        }.count
        let gluteSkewCount = metadataByExercise.filter { metadata in
            let primary = Set(metadata.primaryAreas.map(normalizedPriorityText))
            let secondary = Set(metadata.secondaryAreas.map(normalizedPriorityText))
            return primary.contains(normalizedPriorityText("Glutes"))
                || primary.contains(normalizedPriorityText("Posterior Chain"))
                || primary.contains(normalizedPriorityText("Quads/Glutes"))
                || secondary.contains(normalizedPriorityText("Glutes"))
                || ["Hinge", "Hip Thrust", "Glute", "Split Squat", "Lunge"].contains(metadata.movementPattern)
        }.count

        var issues: [String] = []

        if !explicitPosteriorBias && gluteSkewCount >= 4 && kneeDominantAnchorCount == 0 && day.exercises.count >= 6 {
            issues.append(
                "Day \(day.dayNumber) reads as a broad lower-body session, but it leans too heavily on glute/posterior-chain patterns without a clear knee-dominant quad anchor. Add or swap in a clearer squat/press/extension slot."
            )
        }

        if !explicitPosteriorBias && hipDominantCount >= 2 && unilateralLowerCount >= 2 {
            issues.append(
                "Day \(day.dayNumber) stacks too many glute- and hip-dominant lower-body patterns in one session. Trim one redundant posterior-chain accessory and reallocate that slot to a clearer quad or direct-core stimulus."
            )
        }

        if explicitQuadBias && kneeDominantAnchorCount == 0 {
            issues.append(
                "Day \(day.dayNumber) is supposed to emphasize quads, but it never includes a clear knee-dominant quad anchor."
            )
        }

        return issues
    }

    func validateSessionNoteAlignment(on day: WorkoutDayResponse) -> [String] {
        let note = normalizedPriorityText(day.notes)
        guard !note.isEmpty else { return [] }

        let hasPress = day.exercises.contains { exercise in
            let name = normalizedPriorityText(exercise.exerciseName)
            return containsAny(name, keywords: ["press", "bench", "dip"])
                && !containsAny(name, keywords: ["leg press", "pressdown", "pallof"])
        }
        let hasPull = day.exercises.contains { exercise in
            let name = normalizedPriorityText(exercise.exerciseName)
            return containsAny(name, keywords: ["row", "pulldown", "pull-up", "pull up", "chin-up", "chin up"])
        }
        let hasHinge = day.exercises.contains { exercise in
            let name = normalizedPriorityText(exercise.exerciseName)
            return containsAny(name, keywords: ["deadlift", "romanian deadlift", "rdl", "hinge", "good morning"])
        }

        var issues: [String] = []
        if containsAny(note, keywords: ["before pressing", "first pressing movement", "for pressing"]) && !hasPress {
            issues.append(
                "Day \(day.dayNumber) session notes talk about pressing, but the session does not contain a meaningful press. Align the coaching note with the actual day structure."
            )
        }
        if containsAny(note, keywords: ["before pulling", "first pulling movement", "for pulling"]) && !hasPull {
            issues.append(
                "Day \(day.dayNumber) session notes talk about pulling, but the session does not contain a meaningful pull. Align the coaching note with the actual day structure."
            )
        }
        if containsAny(note, keywords: ["before hinging", "before deadlifting", "for your hinge"]) && !hasHinge {
            issues.append(
                "Day \(day.dayNumber) session notes talk about hinge work, but the session does not contain a meaningful hinge pattern. Align the coaching note with the actual day structure."
            )
        }

        return issues
    }

    func validateInjuryRiskAlignment(
        on day: WorkoutDayResponse,
        injuryRiskFocus: String
    ) -> [String] {
        let normalizedRisk = normalizedPriorityText(injuryRiskFocus)
        guard containsAny(
            normalizedRisk,
            keywords: ["shoulder impingement", "internal shoulder rotation", "internally rotated shoulders", "upper crossed"]
        ) else {
            return []
        }

        let dayNote = normalizedPriorityText(day.notes)
        let riskyVerticalPresses = day.exercises.filter { exercise in
            let name = normalizedPriorityText(exercise.exerciseName)
            guard containsAny(name, keywords: ["shoulder press", "overhead press", "arnold press"]) else {
                return false
            }

            let note = normalizedPriorityText(exercise.notes)
            return !containsAny(name, keywords: ["landmine"])
                && !containsAny(note, keywords: ["neutral grip", "angled grip", "pain free", "shoulder friendly"])
                && !containsAny(dayNote, keywords: ["external rotation", "band pull apart", "band pull-apart", "wall slide", "serratus"])
        }

        guard !riskyVerticalPresses.isEmpty else { return [] }
        let names = riskyVerticalPresses.prefix(2).map(\.exerciseName).joined(separator: ", ")
        return [
            "Day \(day.dayNumber) includes shoulder pressing that is not clearly adapted to the impingement/internal-rotation risk in the analysis (\(names)). Use more shoulder-friendly setup cues or choose a better-aligned press variation."
        ]
    }

    // MARK: - Joint-Stress Budget

    struct JointStressBudget {
        var shoulder: Double = 0
        var elbow: Double = 0
        var lowerBack: Double = 0
        var knee: Double = 0
    }

    func exerciseJointStress(for exercise: WorkoutExerciseResponse) -> JointStressBudget {
        let metadata = exerciseMetadata(for: exercise)
        let name = normalizedPriorityText(exercise.exerciseName)
        let pattern = normalizedPriorityText(metadata.movementPattern)
        let sets = Double(exercise.sets)

        var stress = JointStressBudget()

        let shoulderBase = Double(metadata.shoulderRisk)
        if containsAny(pattern, keywords: ["horizontal press", "incline press", "vertical press", "close-grip press", "dip", "fly"]) {
            stress.shoulder += shoulderBase * sets * 0.5
        } else if containsAny(pattern, keywords: ["row", "vertical pull", "pullover", "face pull"]) {
            stress.shoulder += max(1, shoulderBase) * sets * 0.2
        } else if containsAny(pattern, keywords: ["lateral raise", "upright row", "rear delt fly"]) {
            stress.shoulder += shoulderBase * sets * 0.3
        }

        if containsAny(pattern, keywords: ["curl", "extension", "pressdown", "close-grip press"]) {
            stress.elbow += sets * 0.4
        }
        if containsAny(name, keywords: ["skull crusher", "preacher curl", "jm press"]) {
            stress.elbow += sets * 0.3
        }
        if containsAny(pattern, keywords: ["horizontal press", "incline press", "vertical press", "dip"]) {
            stress.elbow += sets * 0.2
        }

        if containsAny(pattern, keywords: ["hinge", "squat"]) && metadata.equipment != "Machine" {
            stress.lowerBack += Double(metadata.fatigueCost) * sets * 0.4
        }
        if containsAny(pattern, keywords: ["row"]) && !containsAny(name, keywords: ["chest supported", "machine", "cable", "seated cable"]) {
            stress.lowerBack += sets * 0.3
        }
        if containsAny(name, keywords: ["good morning"]) {
            stress.lowerBack += sets * 0.5
        }

        if containsAny(pattern, keywords: ["squat", "press", "lunge", "split squat", "extension"]) && containsAny(normalizedPriorityText(metadata.primaryAreas.joined(separator: " ")), keywords: ["quad", "glute"]) {
            stress.knee += Double(metadata.fatigueCost) * sets * 0.3
        }

        return stress
    }

    func sessionJointStress(for day: WorkoutDayResponse) -> JointStressBudget {
        guard !day.isRestDay else { return JointStressBudget() }
        return day.exercises.reduce(into: JointStressBudget()) { total, exercise in
            let stress = exerciseJointStress(for: exercise)
            total.shoulder += stress.shoulder
            total.elbow += stress.elbow
            total.lowerBack += stress.lowerBack
            total.knee += stress.knee
        }
    }

    func validateJointStressBudget(on day: WorkoutDayResponse) -> [String] {
        guard !day.isRestDay else { return [] }
        let stress = sessionJointStress(for: day)
        var issues: [String] = []

        if stress.shoulder > 18 {
            issues.append(
                "Day \(day.dayNumber) accumulates excessive shoulder joint stress (\(String(format: "%.0f", stress.shoulder)) vs 18 budget). Swap a compound press for a machine or cable alternative, or drop a redundant pressing slot."
            )
        }
        if stress.elbow > 14 {
            issues.append(
                "Day \(day.dayNumber) accumulates excessive elbow joint stress (\(String(format: "%.0f", stress.elbow)) vs 14 budget). Reduce overlapping curl/extension work or swap a barbell movement for a cable variant."
            )
        }
        if stress.lowerBack > 14 {
            issues.append(
                "Day \(day.dayNumber) accumulates excessive lower-back stress (\(String(format: "%.0f", stress.lowerBack)) vs 14 budget). Replace a free-weight hinge or row with a chest-supported or machine alternative."
            )
        }
        if stress.knee > 14 {
            issues.append(
                "Day \(day.dayNumber) accumulates excessive knee joint stress (\(String(format: "%.0f", stress.knee)) vs 14 budget). Consider swapping a compound squat for a machine press or reducing heavy quad work."
            )
        }

        return issues
    }

    // MARK: - Contradiction Detection

    func validateNoteContradictions(on day: WorkoutDayResponse, blueprint: ProgramBlueprint, dayStart: Int) -> [String] {
        guard !day.isRestDay else { return [] }
        let note = normalizedPriorityText(day.notes)
        let dayName = normalizedPriorityText(day.dayName)
        let combined = "\(note) \(dayName)"
        var issues: [String] = []

        if containsAny(combined, keywords: ["low fatigue", "low-fatigue", "recovery", "deload", "easy"]) {
            let heavyCompoundCount = day.exercises.filter { exercise in
                let metadata = exerciseMetadata(for: exercise)
                return metadata.fatigueCost >= 3
            }.count
            if heavyCompoundCount >= 2 {
                issues.append(
                    "Day \(day.dayNumber) notes describe a low-fatigue or recovery session, but it includes \(heavyCompoundCount) heavy compounds. Align the exercise selection with the session intent."
                )
            }
        }

        if containsAny(combined, keywords: ["shoulder friendly", "shoulder-friendly"]) {
            let riskyCount = day.exercises.filter { exercise in
                let metadata = exerciseMetadata(for: exercise)
                return metadata.shoulderRisk >= 3
            }.count
            if riskyCount >= 2 {
                issues.append(
                    "Day \(day.dayNumber) notes describe a shoulder-friendly session, but it includes \(riskyCount) high shoulder-risk exercises. Choose lower-risk pressing or isolation alternatives."
                )
            }
        }

        let matchedPlan = blueprint.dayPlans.first {
            blueprintDayNumber($0.dayIndex, dayStart: dayStart) == day.dayNumber && !$0.isRestDay
        }
        if let focusArea = matchedPlan?.focusArea {
            let focusText = normalizedPriorityText(focusArea)
            if containsAny(combined, keywords: [focusText, "\(focusText) focus", "\(focusText) emphasis"]) {
                let primeCount = day.exercises.filter { exercise in
                    focusStimulusKind(
                        exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget,
                        focusArea: focusArea
                    ) == .prime
                }.count
                if primeCount == 0 {
                    issues.append(
                        "Day \(day.dayNumber) notes claim \(focusArea) emphasis, but the session contains no prime hypertrophy exercises for that area. The notes contradict the actual programming."
                    )
                }
            }
        }

        return issues
    }

    func focusIntentForArea(_ area: String?, within trainingIntent: TrainingIntentPlan) -> MusclePriorityIntent? {
        guard let area else { return nil }
        return trainingIntent.priorities.first { normalizedPriorityText($0.area) == normalizedPriorityText(area) }
    }

    func exerciseMetadata(for exercise: WorkoutExerciseResponse) -> ExerciseMetadata {
        let normalizedName = normalizeExerciseName(exercise.exerciseName)
        if let metadata = exerciseMetadataCatalog[normalizedName] {
            return metadata
        }
        return inferredExerciseMetadata(for: exercise)
    }

    func exerciseMetadata(forExerciseName exerciseName: String, muscleTarget: String) -> ExerciseMetadata {
        exerciseMetadata(
            for: WorkoutExerciseResponse(
                exerciseName: exerciseName,
                sets: 1,
                reps: "1",
                tempo: "",
                restSeconds: 60,
                notes: "",
                muscleTarget: muscleTarget
            )
        )
    }

    func usesDistanceOrDurationPrescription(_ reps: String) -> Bool {
        let normalized = normalizedPriorityText(reps)
        return containsAny(
            normalized,
            keywords: [
                "yard", "yards", "meter", "meters", "metre", "metres",
                "mile", "miles", "foot", "feet", "ft", "seconds", "second",
                "secs", "sec", "minutes", "minute", "mins", "min"
            ]
        )
    }

    func requiresExplicitTempo(
        exerciseName: String,
        muscleTarget: String,
        reps: String
    ) -> Bool {
        let metadata = exerciseMetadata(
            forExerciseName: exerciseName,
            muscleTarget: muscleTarget
        )

        if metadata.movementPattern == "Carry" {
            return false
        }

        if usesDistanceOrDurationPrescription(reps) {
            return false
        }

        return true
    }

    func isDirectCoreHypertrophyMovement(
        exerciseName: String,
        muscleTarget: String,
        reps: String
    ) -> Bool {
        let metadata = exerciseMetadata(
            forExerciseName: exerciseName,
            muscleTarget: muscleTarget
        )
        guard metadata.movementPattern != "Carry" else { return false }

        let directCorePatterns: Set<String> = [
            "Core", "Spinal Flexion", "Leg Raise", "Anti-Extension", "Anti-Rotation"
        ]
        if directCorePatterns.contains(metadata.movementPattern) {
            return true
        }

        let coreAliases = Set(
            ["Core/Abs", "Abs", "Lower Abs", "Anterior Core", "Obliques", "Serratus"]
                .map(normalizedPriorityText)
        )
        let primaryAliases = Set(
            metadata.primaryAreas
                .flatMap { stimulusAreaAliases(for: $0) }
                .map(normalizedPriorityText)
        )

        return !coreAliases.isDisjoint(with: primaryAliases) && !usesDistanceOrDurationPrescription(reps)
    }

    func evidenceTunedCoachingLanguage(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return cleaned }

        let replacements: [(pattern: String, replacement: String)] = [
            (#"(?i)\bAPT correction\b"#, "pelvic-position and bracing work"),
            (#"(?i)\banterior pelvic tilt correction\b"#, "pelvic-position and bracing work"),
            (#"(?i)\bfix(?:ing)? your anterior pelvic tilt\b"#, "improve pelvic control and exercise position"),
            (#"(?i)\bcorrect(?:ing|ion)? your anterior pelvic tilt\b"#, "improve pelvic control and exercise position"),
            (#"(?i)\bcontributing to your anterior pelvic tilt\b"#, "that may be contributing to your hip-position and setup challenges"),
            (#"(?i)\bas important as the lifting\b"#, "supports the lifting quality")
        ]

        for replacement in replacements {
            cleaned = cleaned.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.replacement,
                options: .regularExpression
            )
        }

        return cleaned
    }

    var exerciseMetadataCatalog: [String: ExerciseMetadata] {
        Self.exerciseMetadataCatalogCache
    }

    var exerciseMetadataEntries: [ExerciseMetadata] {
        Self.exerciseMetadataEntriesCache
    }

    static let exerciseMetadataEntriesCache: [ExerciseMetadata] = [
            ExerciseMetadata(canonicalName: "Incline Dumbbell Press", primaryAreas: ["Upper Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Incline Press", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Incline Barbell Press", primaryAreas: ["Upper Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Incline Press", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Flat Barbell Bench Press", primaryAreas: ["Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Horizontal Press", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Machine Chest Press", primaryAreas: ["Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Horizontal Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Cable Fly", primaryAreas: ["Chest"], secondaryAreas: [], movementPattern: "Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Low-Incline Cable Fly", primaryAreas: ["Upper Chest"], secondaryAreas: [], movementPattern: "Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Dip (Assisted or Weighted)", primaryAreas: ["Chest", "Triceps"], secondaryAreas: ["Anterior Deltoids"], movementPattern: "Dip", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Seated Dumbbell Shoulder Press", primaryAreas: ["Anterior Deltoids"], secondaryAreas: ["Triceps"], movementPattern: "Vertical Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Machine Shoulder Press", primaryAreas: ["Anterior Deltoids"], secondaryAreas: ["Triceps"], movementPattern: "Vertical Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Dumbbell Shoulder Press", primaryAreas: ["Anterior Deltoids"], secondaryAreas: ["Triceps"], movementPattern: "Vertical Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Arnold Press", primaryAreas: ["Anterior Deltoids"], secondaryAreas: ["Lateral Deltoids", "Triceps"], movementPattern: "Vertical Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Cable Lateral Raise", primaryAreas: ["Lateral Deltoids"], secondaryAreas: [], movementPattern: "Lateral Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Machine Lateral Raise", primaryAreas: ["Lateral Deltoids"], secondaryAreas: [], movementPattern: "Lateral Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Dumbbell Lateral Raise", primaryAreas: ["Lateral Deltoids"], secondaryAreas: [], movementPattern: "Lateral Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Reverse Pec Deck", primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back"], movementPattern: "Rear Delt Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Cable Rear Delt Fly", primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back"], movementPattern: "Rear Delt Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Chest-Supported Rear Delt Row", primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back", "Biceps"], movementPattern: "Rear Delt Row", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Face Pull", primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back"], movementPattern: "Face Pull", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Face Pull with External Rotation", primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back"], movementPattern: "Face Pull", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Band Pull-Apart", primaryAreas: ["Shoulders"], secondaryAreas: ["Upper Back"], movementPattern: "Scapular Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Prone Incline Y-Raise", primaryAreas: ["Shoulders"], secondaryAreas: ["Upper Back"], movementPattern: "Scapular Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Pull-Up (Weighted or Assisted)", primaryAreas: ["Lats"], secondaryAreas: ["Biceps"], movementPattern: "Vertical Pull", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Lat Pulldown", primaryAreas: ["Lats"], secondaryAreas: ["Biceps"], movementPattern: "Vertical Pull", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Straight-Arm Pulldown", primaryAreas: ["Lats"], secondaryAreas: [], movementPattern: "Pullover", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Chest-Supported Row", primaryAreas: ["Upper Back"], secondaryAreas: ["Lats", "Biceps"], movementPattern: "Row", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Chest-Supported T-Bar Row", primaryAreas: ["Upper Back"], secondaryAreas: ["Lats", "Biceps"], movementPattern: "Row", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Wide-Grip Cable Row", primaryAreas: ["Upper Back"], secondaryAreas: ["Lats", "Biceps"], movementPattern: "Row", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Machine Row", primaryAreas: ["Mid Back"], secondaryAreas: ["Lats", "Biceps"], movementPattern: "Row", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Seated Cable Row", primaryAreas: ["Mid Back"], secondaryAreas: ["Lats", "Biceps"], movementPattern: "Row", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Single-Arm Dumbbell Row", primaryAreas: ["Lats"], secondaryAreas: ["Upper Back", "Biceps"], movementPattern: "Row", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "EZ-Bar Curl", primaryAreas: ["Biceps"], secondaryAreas: ["Forearms"], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Barbell Curl", primaryAreas: ["Biceps"], secondaryAreas: ["Forearms"], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Incline Dumbbell Curl", primaryAreas: ["Biceps"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Preacher Curl", primaryAreas: ["Biceps"], secondaryAreas: ["Forearms"], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Cable Curl", primaryAreas: ["Biceps"], secondaryAreas: ["Forearms"], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Hammer Curl", primaryAreas: ["Brachialis"], secondaryAreas: ["Biceps", "Forearms"], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Cable Hammer Curl", primaryAreas: ["Brachialis"], secondaryAreas: ["Biceps", "Forearms"], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Rope Triceps Pressdown", primaryAreas: ["Triceps"], secondaryAreas: [], movementPattern: "Pressdown", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Cable Triceps Pressdown", primaryAreas: ["Triceps"], secondaryAreas: [], movementPattern: "Pressdown", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Overhead Cable Triceps Extension", primaryAreas: ["Triceps"], secondaryAreas: [], movementPattern: "Extension", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Close-Grip Bench Press", primaryAreas: ["Triceps"], secondaryAreas: ["Chest", "Anterior Deltoids"], movementPattern: "Close-Grip Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "JM Press", primaryAreas: ["Triceps"], secondaryAreas: ["Chest", "Anterior Deltoids"], movementPattern: "Close-Grip Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Skull Crusher", primaryAreas: ["Triceps"], secondaryAreas: [], movementPattern: "Extension", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Back Squat", primaryAreas: ["Quads"], secondaryAreas: ["Glutes", "Hamstrings"], movementPattern: "Squat", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Front Squat", primaryAreas: ["Quads"], secondaryAreas: ["Glutes"], movementPattern: "Squat", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Romanian Deadlift", primaryAreas: ["Hamstrings"], secondaryAreas: ["Glutes", "Posterior Chain"], movementPattern: "Hinge", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Trap Bar Deadlift", primaryAreas: ["Quads", "Posterior Chain"], secondaryAreas: ["Glutes", "Hamstrings"], movementPattern: "Hinge", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Leg Press", primaryAreas: ["Quads"], secondaryAreas: ["Glutes"], movementPattern: "Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "45-Degree Leg Press", primaryAreas: ["Quads"], secondaryAreas: ["Glutes"], movementPattern: "Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Single-Leg Press", primaryAreas: ["Quads"], secondaryAreas: ["Glutes"], movementPattern: "Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Walking Lunge", primaryAreas: ["Quads/Glutes"], secondaryAreas: ["Quads", "Hamstrings"], movementPattern: "Lunge", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Bulgarian Split Squat", primaryAreas: ["Quads/Glutes"], secondaryAreas: ["Quads"], movementPattern: "Split Squat", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Hack Squat", primaryAreas: ["Quads"], secondaryAreas: ["Glutes"], movementPattern: "Squat", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Leg Curl", primaryAreas: ["Hamstrings"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Lying Leg Curl", primaryAreas: ["Hamstrings"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Seated Leg Curl", primaryAreas: ["Hamstrings"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Glute-Ham Raise", primaryAreas: ["Hamstrings"], secondaryAreas: ["Glutes"], movementPattern: "Curl", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Leg Extension", primaryAreas: ["Quads"], secondaryAreas: [], movementPattern: "Extension", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Hip Thrust", primaryAreas: ["Glutes"], secondaryAreas: ["Hamstrings"], movementPattern: "Hip Thrust", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Standing Calf Raise", primaryAreas: ["Calves"], secondaryAreas: [], movementPattern: "Calf Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Seated Calf Raise", primaryAreas: ["Calves"], secondaryAreas: [], movementPattern: "Calf Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Cable Crunch", primaryAreas: ["Abs"], secondaryAreas: [], movementPattern: "Spinal Flexion", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Cable Crossover", primaryAreas: ["Chest"], secondaryAreas: [], movementPattern: "Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Pec Deck", primaryAreas: ["Chest"], secondaryAreas: [], movementPattern: "Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Hanging Knee Raise", primaryAreas: ["Lower Abs"], secondaryAreas: [], movementPattern: "Leg Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Ab Wheel Rollout", primaryAreas: ["Anterior Core"], secondaryAreas: ["Shoulders"], movementPattern: "Anti-Extension", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Pallof Press", primaryAreas: ["Obliques"], secondaryAreas: ["Anterior Core"], movementPattern: "Anti-Rotation", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Farmer's Walk", primaryAreas: ["Anterior Core"], secondaryAreas: ["Forearms", "Upper Back"], movementPattern: "Carry", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Barbell Shrug", primaryAreas: ["Upper Back"], secondaryAreas: [], movementPattern: "Shrug", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Landmine Press", primaryAreas: ["Anterior Deltoids"], secondaryAreas: ["Upper Chest", "Triceps"], movementPattern: "Landmine Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Incline Smith Machine Press", primaryAreas: ["Upper Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Incline Press", fatigueCost: 2),

            ExerciseMetadata(canonicalName: "Dumbbell Bench Press", primaryAreas: ["Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Horizontal Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Flat Dumbbell Fly", primaryAreas: ["Chest"], secondaryAreas: [], movementPattern: "Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Decline Barbell Bench Press", primaryAreas: ["Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Horizontal Press", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Smith Machine Bench Press", primaryAreas: ["Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Horizontal Press", fatigueCost: 2),

            ExerciseMetadata(canonicalName: "Machine Incline Press", primaryAreas: ["Upper Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Incline Press", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Low-Incline Dumbbell Fly", primaryAreas: ["Upper Chest"], secondaryAreas: [], movementPattern: "Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Reverse-Grip Barbell Bench Press", primaryAreas: ["Upper Chest"], secondaryAreas: ["Triceps"], movementPattern: "Horizontal Press", fatigueCost: 2, shoulderRisk: 2),

            ExerciseMetadata(canonicalName: "Barbell Overhead Press", primaryAreas: ["Anterior Deltoids"], secondaryAreas: ["Triceps", "Lateral Deltoids"], movementPattern: "Vertical Press", fatigueCost: 3, shoulderRisk: 3),
            ExerciseMetadata(canonicalName: "Smith Machine Overhead Press", primaryAreas: ["Anterior Deltoids"], secondaryAreas: ["Triceps"], movementPattern: "Vertical Press", fatigueCost: 2, shoulderRisk: 2),

            ExerciseMetadata(canonicalName: "Behind-the-Back Cable Lateral Raise", primaryAreas: ["Lateral Deltoids"], secondaryAreas: [], movementPattern: "Lateral Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Leaning Dumbbell Lateral Raise", primaryAreas: ["Lateral Deltoids"], secondaryAreas: [], movementPattern: "Lateral Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Cable Upright Row", primaryAreas: ["Lateral Deltoids"], secondaryAreas: ["Upper Back", "Anterior Deltoids"], movementPattern: "Upright Row", fatigueCost: 2, shoulderRisk: 2),
            ExerciseMetadata(canonicalName: "Lying Incline Dumbbell Lateral Raise", primaryAreas: ["Lateral Deltoids"], secondaryAreas: [], movementPattern: "Lateral Raise", fatigueCost: 1),

            ExerciseMetadata(canonicalName: "Prone Incline Dumbbell Rear Delt Raise", primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back"], movementPattern: "Rear Delt Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Reverse Cable Crossover", primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back"], movementPattern: "Rear Delt Fly", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Dumbbell Rear Delt Fly", primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back"], movementPattern: "Rear Delt Fly", fatigueCost: 1),

            ExerciseMetadata(canonicalName: "Neutral-Grip Lat Pulldown", primaryAreas: ["Lats"], secondaryAreas: ["Biceps"], movementPattern: "Vertical Pull", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Cable Pullover", primaryAreas: ["Lats"], secondaryAreas: [], movementPattern: "Pullover", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Chin-Up", primaryAreas: ["Lats"], secondaryAreas: ["Biceps"], movementPattern: "Vertical Pull", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Machine Lat Pulldown", primaryAreas: ["Lats"], secondaryAreas: ["Biceps"], movementPattern: "Vertical Pull", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Single-Arm Cable Row", primaryAreas: ["Lats"], secondaryAreas: ["Upper Back", "Biceps"], movementPattern: "Row", fatigueCost: 2),

            ExerciseMetadata(canonicalName: "Barbell Bent-Over Row", primaryAreas: ["Upper Back"], secondaryAreas: ["Lats", "Biceps"], movementPattern: "Row", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Meadows Row", primaryAreas: ["Upper Back", "Lats"], secondaryAreas: ["Biceps"], movementPattern: "Row", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Cable High Row", primaryAreas: ["Upper Back"], secondaryAreas: ["Rear Deltoids"], movementPattern: "Row", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Dumbbell Shrug", primaryAreas: ["Upper Back"], secondaryAreas: [], movementPattern: "Shrug", fatigueCost: 1),

            ExerciseMetadata(canonicalName: "Spider Curl", primaryAreas: ["Biceps"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Bayesian Cable Curl", primaryAreas: ["Biceps"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Concentration Curl", primaryAreas: ["Biceps"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Machine Preacher Curl", primaryAreas: ["Biceps"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 1),

            ExerciseMetadata(canonicalName: "Dumbbell Overhead Triceps Extension", primaryAreas: ["Triceps"], secondaryAreas: [], movementPattern: "Extension", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Machine Dip", primaryAreas: ["Triceps"], secondaryAreas: ["Chest", "Anterior Deltoids"], movementPattern: "Dip", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Cable Kickback", primaryAreas: ["Triceps"], secondaryAreas: [], movementPattern: "Extension", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "V-Bar Pressdown", primaryAreas: ["Triceps"], secondaryAreas: [], movementPattern: "Pressdown", fatigueCost: 1),

            ExerciseMetadata(canonicalName: "Pendulum Squat", primaryAreas: ["Quads"], secondaryAreas: ["Glutes"], movementPattern: "Squat", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Sissy Squat", primaryAreas: ["Quads"], secondaryAreas: [], movementPattern: "Squat", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Belt Squat", primaryAreas: ["Quads"], secondaryAreas: ["Glutes"], movementPattern: "Squat", fatigueCost: 2),

            ExerciseMetadata(canonicalName: "Stiff-Leg Deadlift", primaryAreas: ["Hamstrings"], secondaryAreas: ["Glutes", "Posterior Chain"], movementPattern: "Hinge", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Single-Leg Romanian Deadlift", primaryAreas: ["Hamstrings"], secondaryAreas: ["Glutes"], movementPattern: "Hinge", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Nordic Hamstring Curl", primaryAreas: ["Hamstrings"], secondaryAreas: [], movementPattern: "Curl", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Cable Pull-Through", primaryAreas: ["Glutes", "Hamstrings"], secondaryAreas: ["Posterior Chain"], movementPattern: "Hinge", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Good Morning", primaryAreas: ["Hamstrings"], secondaryAreas: ["Glutes", "Posterior Chain"], movementPattern: "Hinge", fatigueCost: 3),

            ExerciseMetadata(canonicalName: "Cable Glute Kickback", primaryAreas: ["Glutes"], secondaryAreas: [], movementPattern: "Hip Extension", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Single-Leg Hip Thrust", primaryAreas: ["Glutes"], secondaryAreas: ["Hamstrings"], movementPattern: "Hip Thrust", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "Sumo Deadlift", primaryAreas: ["Glutes"], secondaryAreas: ["Quads", "Hamstrings", "Posterior Chain"], movementPattern: "Hinge", fatigueCost: 3),
            ExerciseMetadata(canonicalName: "Reverse Lunge", primaryAreas: ["Glutes"], secondaryAreas: ["Quads"], movementPattern: "Lunge", fatigueCost: 2),
            ExerciseMetadata(canonicalName: "45-Degree Back Extension", primaryAreas: ["Glutes"], secondaryAreas: ["Hamstrings", "Posterior Chain"], movementPattern: "Hip Extension", fatigueCost: 1),

            ExerciseMetadata(canonicalName: "Leg Press Calf Raise", primaryAreas: ["Calves"], secondaryAreas: [], movementPattern: "Calf Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Smith Machine Calf Raise", primaryAreas: ["Calves"], secondaryAreas: [], movementPattern: "Calf Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Single-Leg Standing Calf Raise", primaryAreas: ["Calves"], secondaryAreas: [], movementPattern: "Calf Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Donkey Calf Raise", primaryAreas: ["Calves"], secondaryAreas: [], movementPattern: "Calf Raise", fatigueCost: 1),

            ExerciseMetadata(canonicalName: "Hanging Leg Raise", primaryAreas: ["Lower Abs"], secondaryAreas: [], movementPattern: "Leg Raise", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Machine Crunch", primaryAreas: ["Abs"], secondaryAreas: [], movementPattern: "Spinal Flexion", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Decline Weighted Crunch", primaryAreas: ["Abs"], secondaryAreas: [], movementPattern: "Spinal Flexion", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Dead Bug", primaryAreas: ["Anterior Core"], secondaryAreas: [], movementPattern: "Anti-Extension", fatigueCost: 1),
            ExerciseMetadata(canonicalName: "Suitcase Carry", primaryAreas: ["Obliques"], secondaryAreas: ["Forearms"], movementPattern: "Carry", fatigueCost: 2)
    ]

    static let exerciseNameAliasCache: [String: String] = {
        let entries: [(String, String)] = [
            ("Face Pulls", "Face Pull"),
            ("Cable Face Pull", "Face Pull"),
            ("Cable Face Pulls", "Face Pull"),
            ("Cable Rope Pushdown", "Rope Triceps Pressdown"),
            ("Cable Rope Pushdowns", "Rope Triceps Pressdown"),
            ("Rope Pushdown", "Rope Triceps Pressdown"),
            ("Rope Pushdowns", "Rope Triceps Pressdown"),
            ("Cable Pushdown", "Cable Triceps Pressdown"),
            ("Cable Pushdowns", "Cable Triceps Pressdown"),
            ("Cable Tricep Pushdown", "Cable Triceps Pressdown"),
            ("Cable Tricep Pushdowns", "Cable Triceps Pressdown"),
            ("Cable Triceps Pushdown", "Cable Triceps Pressdown"),
            ("Cable Triceps Pushdowns", "Cable Triceps Pressdown"),
            ("Dumbbell Hammer Curl", "Hammer Curl"),
            ("Dumbbell Hammer Curls", "Hammer Curl"),
            ("Cable Hammer Curls", "Cable Hammer Curl"),
            ("Barbell Curls", "Barbell Curl"),
            ("Barbell Shrugs", "Barbell Shrug"),
            ("Band Pull Apart", "Band Pull-Apart"),
            ("Band Pull Aparts", "Band Pull-Apart"),
            ("Lying Leg Curls", "Lying Leg Curl"),
            ("Glute Ham Raise", "Glute-Ham Raise"),
            ("Cable Crossovers", "Cable Crossover"),
            ("Chin Up", "Chin-Up"),
            ("Chin Ups", "Chin-Up"),
            ("Chinup", "Chin-Up"),
            ("Chinups", "Chin-Up"),
            ("Weighted Chin-Up", "Chin-Up"),
            ("Neutral Grip Lat Pulldown", "Neutral-Grip Lat Pulldown"),
            ("Neutral Grip Pulldown", "Neutral-Grip Lat Pulldown"),
            ("Close Grip Lat Pulldown", "Close-Grip Lat Pulldown"),
            ("Cable Pullovers", "Cable Pullover"),
            ("Machine Pulldown", "Machine Lat Pulldown"),
            ("Single Arm Cable Row", "Single-Arm Cable Row"),
            ("One Arm Cable Row", "Single-Arm Cable Row"),
            ("Bent Over Row", "Barbell Bent-Over Row"),
            ("Bent-Over Row", "Barbell Bent-Over Row"),
            ("Barbell Row", "Barbell Bent-Over Row"),
            ("Barbell Rows", "Barbell Bent-Over Row"),
            ("Meadows Rows", "Meadows Row"),
            ("Landmine Meadows Row", "Meadows Row"),
            ("Dumbbell Shrugs", "Dumbbell Shrug"),
            ("DB Shrug", "Dumbbell Shrug"),
            ("DB Shrugs", "Dumbbell Shrug"),
            ("Cable High Rows", "Cable High Row"),
            ("Behind the Back Cable Lateral Raise", "Behind-the-Back Cable Lateral Raise"),
            ("Behind Back Cable Lateral Raise", "Behind-the-Back Cable Lateral Raise"),
            ("Leaning Lateral Raise", "Leaning Dumbbell Lateral Raise"),
            ("Leaning DB Lateral Raise", "Leaning Dumbbell Lateral Raise"),
            ("Cable Upright Rows", "Cable Upright Row"),
            ("Wide Grip Cable Upright Row", "Cable Upright Row"),
            ("Lying Lateral Raise", "Lying Incline Dumbbell Lateral Raise"),
            ("Incline Lateral Raise", "Lying Incline Dumbbell Lateral Raise"),
            ("Prone Rear Delt Raise", "Prone Incline Dumbbell Rear Delt Raise"),
            ("Incline Rear Delt Raise", "Prone Incline Dumbbell Rear Delt Raise"),
            ("Prone Dumbbell Rear Delt Raise", "Prone Incline Dumbbell Rear Delt Raise"),
            ("Reverse Cable Crossovers", "Reverse Cable Crossover"),
            ("Reverse Cable Fly", "Reverse Cable Crossover"),
            ("Dumbbell Rear Delt Flys", "Dumbbell Rear Delt Fly"),
            ("Bent-Over Dumbbell Rear Delt Fly", "Dumbbell Rear Delt Fly"),
            ("Bent Over Rear Delt Fly", "Dumbbell Rear Delt Fly"),
            ("Spider Curls", "Spider Curl"),
            ("Bayesian Curl", "Bayesian Cable Curl"),
            ("Bayesian Curls", "Bayesian Cable Curl"),
            ("Concentration Curls", "Concentration Curl"),
            ("Machine Preacher Curls", "Machine Preacher Curl"),
            ("Machine Bicep Curl", "Machine Preacher Curl"),
            ("V Bar Pressdown", "V-Bar Pressdown"),
            ("V-Bar Pushdown", "V-Bar Pressdown"),
            ("V Bar Pushdown", "V-Bar Pressdown"),
            ("Cable Kickbacks", "Cable Kickback"),
            ("Tricep Kickback", "Cable Kickback"),
            ("Triceps Kickback", "Cable Kickback"),
            ("Machine Dips", "Machine Dip"),
            ("Assisted Dip Machine", "Machine Dip"),
            ("Dumbbell Overhead Extension", "Dumbbell Overhead Triceps Extension"),
            ("DB Overhead Triceps Extension", "Dumbbell Overhead Triceps Extension"),
            ("Overhead Dumbbell Extension", "Dumbbell Overhead Triceps Extension"),
            ("Pendulum Squats", "Pendulum Squat"),
            ("Sissy Squats", "Sissy Squat"),
            ("Belt Squats", "Belt Squat"),
            ("Stiff Leg Deadlift", "Stiff-Leg Deadlift"),
            ("Stiff Legged Deadlift", "Stiff-Leg Deadlift"),
            ("Single Leg Romanian Deadlift", "Single-Leg Romanian Deadlift"),
            ("Single Leg RDL", "Single-Leg Romanian Deadlift"),
            ("Nordic Curl", "Nordic Hamstring Curl"),
            ("Nordic Curls", "Nordic Hamstring Curl"),
            ("Nordic Hamstring Curls", "Nordic Hamstring Curl"),
            ("Cable Pull Through", "Cable Pull-Through"),
            ("Cable Pull Throughs", "Cable Pull-Through"),
            ("Pull Through", "Cable Pull-Through"),
            ("Good Mornings", "Good Morning"),
            ("Barbell Good Morning", "Good Morning"),
            ("Cable Glute Kickbacks", "Cable Glute Kickback"),
            ("Glute Kickback", "Cable Glute Kickback"),
            ("Single Leg Hip Thrust", "Single-Leg Hip Thrust"),
            ("Single-Leg Glute Bridge", "Single-Leg Hip Thrust"),
            ("Sumo Deadlifts", "Sumo Deadlift"),
            ("Reverse Lunges", "Reverse Lunge"),
            ("Dumbbell Reverse Lunge", "Reverse Lunge"),
            ("Back Extension", "45-Degree Back Extension"),
            ("Hyperextension", "45-Degree Back Extension"),
            ("45 Degree Back Extension", "45-Degree Back Extension"),
            ("Leg Press Calf Raises", "Leg Press Calf Raise"),
            ("Smith Machine Calf Raises", "Smith Machine Calf Raise"),
            ("Single Leg Calf Raise", "Single-Leg Standing Calf Raise"),
            ("Single-Leg Calf Raise", "Single-Leg Standing Calf Raise"),
            ("Donkey Calf Raises", "Donkey Calf Raise"),
            ("Hanging Leg Raises", "Hanging Leg Raise"),
            ("Straight Leg Hanging Raise", "Hanging Leg Raise"),
            ("Machine Crunches", "Machine Crunch"),
            ("Decline Crunch", "Decline Weighted Crunch"),
            ("Weighted Decline Crunch", "Decline Weighted Crunch"),
            ("Dead Bugs", "Dead Bug"),
            ("Suitcase Carries", "Suitcase Carry"),
            ("Dumbbell Bench Presses", "Dumbbell Bench Press"),
            ("DB Bench Press", "Dumbbell Bench Press"),
            ("Flat Dumbbell Flys", "Flat Dumbbell Fly"),
            ("DB Fly", "Flat Dumbbell Fly"),
            ("Flat DB Fly", "Flat Dumbbell Fly"),
            ("Decline Bench Press", "Decline Barbell Bench Press"),
            ("Smith Machine Bench Presses", "Smith Machine Bench Press"),
            ("Machine Incline Presses", "Machine Incline Press"),
            ("Incline Machine Press", "Machine Incline Press"),
            ("Low Incline Dumbbell Fly", "Low-Incline Dumbbell Fly"),
            ("Reverse Grip Bench Press", "Reverse-Grip Barbell Bench Press"),
            ("Reverse-Grip Bench Press", "Reverse-Grip Barbell Bench Press"),
            ("Overhead Press", "Barbell Overhead Press"),
            ("Standing Overhead Press", "Barbell Overhead Press"),
            ("Strict Press", "Barbell Overhead Press"),
            ("Military Press", "Barbell Overhead Press"),
            ("Smith Machine Shoulder Press", "Smith Machine Overhead Press")
        ]
        var dict = [String: String]()
        for (key, value) in entries {
            dict[normalizedExerciseNameKey(key)] = value
        }
        return dict
    }()

    static let exerciseMetadataCatalogCache: [String: ExerciseMetadata] = {
        var dict = [String: ExerciseMetadata]()
        for entry in exerciseMetadataEntriesCache {
            let enriched = ClaudeService.enrichedExerciseMetadata(entry)
            dict[normalizedExerciseNameKey(entry.canonicalName)] = enriched
        }
        return dict
    }()

    func inferredExerciseMetadata(for exercise: WorkoutExerciseResponse) -> ExerciseMetadata {
        let nameText = normalizedPriorityText(exercise.exerciseName)
        let targetText = normalizedPriorityText(exercise.muscleTarget)
        let combinedText = "\(nameText) \(targetText)"

        let targetsBiceps = containsAny(targetText, keywords: ["bicep"])
        let targetsTriceps = containsAny(targetText, keywords: ["tricep"])
        let targetsShoulders = containsAny(targetText, keywords: ["shoulder", "delt", "deltoid"])
        let targetsRearDelts = containsAny(targetText, keywords: ["rear delt", "posterior delt"])
        let targetsLateralDelts = containsAny(targetText, keywords: ["lateral delt", "side delt"])
        let targetsAnteriorDelts = containsAny(targetText, keywords: ["front delt", "anterior delt"])
        let targetsUpperChest = containsAny(targetText, keywords: ["upper chest", "clavicular"])
        let targetsChest = containsAny(targetText, keywords: ["chest", "pec"])
        let targetsLats = containsPriorityPhrase(in: targetText, keywords: ["lat", "lats", "latissimus dorsi", "latissimus"])
        let targetsBack = containsAny(targetText, keywords: ["back"])
        let targetsUpperBack = containsAny(targetText, keywords: ["upper back", "mid back"])
        let targetsQuads = containsAny(targetText, keywords: ["quad"])
        let targetsHamstrings = containsAny(targetText, keywords: ["hamstring", "posterior chain"])
        let targetsGlutes = containsAny(targetText, keywords: ["glute"])
        let isLowerBodyCurlPattern = containsAny(combinedText, keywords: ["leg curl", "hamstring curl"])

        if containsAny(combinedText, keywords: ["core", "abs", "oblique", "crunch", "plank", "rollout", "pallof", "leg raise", "knee raise", "serratus"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Core/Abs"], secondaryAreas: [], movementPattern: "Core", fatigueCost: 1))
        }
        if containsAny(combinedText, keywords: ["calf"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Calves"], secondaryAreas: [], movementPattern: "Calf Raise", fatigueCost: 1))
        }
        if containsAny(combinedText, keywords: ["wrist curl", "wrist extension", "reverse curl"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Forearms"], secondaryAreas: ["Biceps"], movementPattern: "Forearm", fatigueCost: 1))
        }
        if containsAny(combinedText, keywords: ["y raise", "trap 3", "scaption", "wall slide", "external rotation", "pull apart"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Shoulders"], secondaryAreas: ["Upper Back"], movementPattern: "Scapular Raise", fatigueCost: 1))
        }
        if containsAny(combinedText, keywords: ["brachialis", "hammer curl", "cross body curl"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Brachialis"], secondaryAreas: ["Biceps", "Forearms"], movementPattern: "Curl", fatigueCost: 1))
        }
        if targetsBiceps || (containsAny(combinedText, keywords: ["bicep", "curl", "preacher curl", "bayesian curl"]) && !isLowerBodyCurlPattern) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Biceps"], secondaryAreas: ["Forearms"], movementPattern: "Curl", fatigueCost: 1))
        }
        if targetsTriceps || containsAny(combinedText, keywords: ["tricep", "pressdown", "kickback", "skull crusher", "jm press", "triceps extension", "overhead extension"]) {
            let usesCompoundPressPattern = containsAny(nameText, keywords: ["press"]) && !containsAny(nameText, keywords: ["pressdown"])
            return Self.enrichedExerciseMetadata(ExerciseMetadata(
                canonicalName: exercise.exerciseName,
                primaryAreas: ["Triceps"],
                secondaryAreas: usesCompoundPressPattern ? ["Chest", "Anterior Deltoids"] : [],
                movementPattern: usesCompoundPressPattern ? "Close-Grip Press" : "Extension",
                fatigueCost: usesCompoundPressPattern ? 2 : 1
            ))
        }
        if targetsRearDelts || containsAny(combinedText, keywords: ["rear delt", "posterior delt", "reverse fly", "reverse pec deck", "face pull"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Rear Deltoids"], secondaryAreas: ["Upper Back"], movementPattern: "Rear Delt", fatigueCost: 1))
        }
        if targetsLateralDelts || containsAny(combinedText, keywords: ["lateral raise", "lateral delt", "side delt"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Lateral Deltoids"], secondaryAreas: [], movementPattern: "Lateral Raise", fatigueCost: 1))
        }
        if targetsAnteriorDelts || (targetsShoulders && containsAny(nameText, keywords: ["press", "arnold"])) || containsAny(nameText, keywords: ["shoulder press", "overhead press", "arnold press"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Anterior Deltoids"], secondaryAreas: ["Triceps"], movementPattern: "Vertical Press", fatigueCost: 2))
        }
        if containsAny(combinedText, keywords: ["shoulder", "delt", "deltoid"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Shoulders"], secondaryAreas: ["Triceps"], movementPattern: "Shoulder", fatigueCost: 1))
        }
        if targetsUpperBack || containsAny(combinedText, keywords: ["row", "chest supported", "upper back", "mid back", "machine row", "t bar row"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Upper Back"], secondaryAreas: ["Lats", "Biceps"], movementPattern: "Row", fatigueCost: 2))
        }
        if targetsLats || containsPriorityPhrase(in: combinedText, keywords: ["lats", "lat", "latissimus dorsi", "pullup", "pull up", "chinup", "chin up", "pulldown", "straight arm pulldown"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Lats"], secondaryAreas: ["Biceps"], movementPattern: "Vertical Pull", fatigueCost: 2))
        }
        if targetsBack {
            let rowLikePattern = containsAny(nameText, keywords: ["row", "chest supported", "machine row", "t bar row"])
            return Self.enrichedExerciseMetadata(ExerciseMetadata(
                canonicalName: exercise.exerciseName,
                primaryAreas: ["Back"],
                secondaryAreas: ["Lats", "Biceps"],
                movementPattern: rowLikePattern ? "Row" : "Pull",
                fatigueCost: 2
            ))
        }
        if targetsGlutes || containsAny(combinedText, keywords: ["glute", "hip thrust", "glute bridge"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Glutes"], secondaryAreas: ["Hamstrings"], movementPattern: "Glute", fatigueCost: 2))
        }
        if targetsHamstrings || containsAny(combinedText, keywords: ["hamstring", "leg curl", "rdl", "romanian deadlift", "stiff leg", "good morning", "hinge", "deadlift"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Hamstrings"], secondaryAreas: ["Glutes"], movementPattern: "Hinge", fatigueCost: 2))
        }
        if targetsQuads || containsAny(combinedText, keywords: ["quad", "squat", "leg press", "split squat", "lunge", "leg extension", "step up", "hack squat"]) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Quads"], secondaryAreas: ["Glutes"], movementPattern: "Squat", fatigueCost: 2))
        }

        let hasChestPattern = containsAny(combinedText, keywords: ["chest", "pec", "bench", "fly", "dip"])
        let hasPressPattern = containsAny(nameText, keywords: ["press"])
        let isShoulderPressPattern = containsAny(nameText, keywords: ["shoulder press", "overhead press", "arnold press"])
        let isLowerBodyPressPattern = containsAny(nameText, keywords: ["leg press"])
        let isArmPressPattern = containsAny(nameText, keywords: ["pressdown", "jm press"])
        let isUpperChestPattern = targetsUpperChest || (
            containsAny(nameText, keywords: ["incline"])
                && containsAny(nameText, keywords: ["press", "fly"])
                && !containsAny(nameText, keywords: ["curl", "row"])
        )

        if isUpperChestPattern {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Upper Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Incline Press", fatigueCost: 2))
        }
        if targetsChest || hasChestPattern || (hasPressPattern && !isShoulderPressPattern && !isLowerBodyPressPattern && !isArmPressPattern && !targetsShoulders) {
            return Self.enrichedExerciseMetadata(ExerciseMetadata(canonicalName: exercise.exerciseName, primaryAreas: ["Chest"], secondaryAreas: ["Triceps", "Anterior Deltoids"], movementPattern: "Press", fatigueCost: 2))
        }

        return Self.enrichedExerciseMetadata(ExerciseMetadata(
            canonicalName: exercise.exerciseName,
            primaryAreas: [exercise.muscleTarget.trimmedOr(default: "Primary Target")],
            secondaryAreas: [],
            movementPattern: "Unknown",
            fatigueCost: 1
        ))
    }

    static func enrichedExerciseMetadata(_ metadata: ExerciseMetadata) -> ExerciseMetadata {
        func normalized(_ text: String) -> String {
            text
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
                .replacingOccurrences(of: "-", with: " ")
        }

        func containsAnyKeyword(_ text: String, keywords: [String]) -> Bool {
            keywords.contains { text.contains($0) }
        }

        let name = normalizedExerciseNameKey(metadata.canonicalName)
        let pattern = normalized(metadata.movementPattern)
        let primary = Set(metadata.primaryAreas.map(normalized))

        var equipment = metadata.equipment
        var exerciseClass = metadata.exerciseClass
        var systemicFatigue = metadata.systemicFatigue
        var stabilityDemand = metadata.stabilityDemand
        var shoulderRisk = metadata.shoulderRisk
        var preferredContexts = Set(metadata.preferredContexts)
        var avoidContexts = Set(metadata.avoidContexts)

        if name.contains("cable") || pattern.contains("pressdown") || pattern.contains("pullover") {
            equipment = "Cable"
        } else if name.contains("machine") || name.contains("pec deck") || name.contains("hack squat") {
            equipment = "Machine"
        } else if name.contains("barbell") || name.contains("ez-bar") || name.contains("smith") || name.contains("trap bar") {
            equipment = "Barbell"
        } else if name.contains("dumbbell") || name.contains("arnold") {
            equipment = "Dumbbell"
        } else if name.contains("band") {
            equipment = "Band"
        } else if name.contains("pull-up") || name.contains("dip") || name.contains("ab wheel") {
            equipment = "Bodyweight"
        }

        switch metadata.fatigueCost {
        case 3:
            exerciseClass = "Heavy Compound"
            systemicFatigue = max(systemicFatigue, 3)
            stabilityDemand = max(stabilityDemand, equipment == "Machine" ? 2 : 3)
        case 2:
            exerciseClass = pattern.contains("press") || pattern.contains("row") || pattern.contains("pull") || pattern.contains("squat") || pattern.contains("hinge")
                ? "Hypertrophy Compound"
                : "Stable Accessory"
            systemicFatigue = max(systemicFatigue, 2)
            stabilityDemand = max(stabilityDemand, equipment == "Machine" || equipment == "Cable" ? 1 : 2)
        default:
            exerciseClass = containsAnyKeyword(pattern, keywords: ["scapular", "face pull", "anti rotation", "anti extension", "core"])
                ? "Prehab"
                : "Isolation"
            systemicFatigue = max(systemicFatigue, 1)
            stabilityDemand = max(stabilityDemand, equipment == "Cable" || equipment == "Machine" ? 1 : 2)
        }

        if primary.contains(normalized("Upper Chest")) || primary.contains(normalized("Chest")) {
            preferredContexts.formUnion(["hypertrophy", "commercial_gym"])
            if equipment == "Cable" || equipment == "Machine" {
                preferredContexts.insert("shift_work_friendly")
            }
        }

        if primary.contains(normalized("Lateral Deltoids")) {
            preferredContexts.formUnion(["lateral_delt_priority", "physique", "low_systemic_fatigue"])
            if equipment == "Cable" || equipment == "Machine" {
                preferredContexts.formUnion(["shift_work_friendly", "shoulder_friendly"])
            }
        }

        if primary.contains(normalized("Rear Deltoids")) || pattern.contains("face pull") {
            preferredContexts.formUnion(["shoulder_friendly", "posture_support", "low_systemic_fatigue"])
        }

        if containsAnyKeyword(pattern, keywords: ["row", "vertical pull", "pullover"]) && (equipment == "Machine" || equipment == "Cable") {
            preferredContexts.insert("shift_work_friendly")
        }

        if containsAnyKeyword(pattern, keywords: ["squat", "hinge"]) && equipment != "Machine" {
            avoidContexts.formUnion(["short_session", "low_data_quality"])
        }

        if containsAnyKeyword(name, keywords: ["close grip bench", "jm press", "dip", "arnold press", "shoulder press", "overhead press"]) {
            shoulderRisk = max(shoulderRisk, 3)
        }
        if containsAnyKeyword(name, keywords: ["upright row", "dip", "arnold press"]) {
            shoulderRisk = max(shoulderRisk, 4)
        }
        if pattern.contains("vertical press") {
            shoulderRisk = max(shoulderRisk, 3)
        }
        if containsAnyKeyword(name, keywords: ["cable lateral raise", "machine lateral raise", "reverse pec deck", "face pull", "chest supported row", "lat pulldown", "leg press", "hack squat", "seated leg curl", "cable triceps pressdown", "rope triceps pressdown", "machine incline press", "machine lat pulldown", "machine preacher curl", "machine crunch", "machine dip", "v bar pressdown", "behind the back cable", "bayesian cable curl", "cable pullover", "cable high row", "cable kickback", "pendulum squat", "leg press calf raise"]) {
            preferredContexts.formUnion(["shift_work_friendly", "low_data_quality"])
        }
        if containsAnyKeyword(name, keywords: ["close grip bench", "jm press", "dip"]) {
            avoidContexts.formUnion(["shoulder_risk", "arms_pump_day", "short_session"])
        }
        if containsAnyKeyword(name, keywords: ["back squat", "front squat", "trap bar deadlift", "romanian deadlift"]) {
            avoidContexts.insert("short_session")
            if equipment != "Machine" {
                avoidContexts.insert("shift_work_friendly")
            }
        }
        if containsAnyKeyword(name, keywords: ["incline dumbbell press", "machine chest press", "landmine press", "incline smith machine press"]) {
            preferredContexts.formUnion(["hypertrophy", "shoulder_friendly"])
        }
        if containsAnyKeyword(name, keywords: ["landmine press"]) {
            shoulderRisk = min(shoulderRisk, 2)
            preferredContexts.insert("shoulder_risk")
        }
        if primary.contains(normalized("Anterior Deltoids")) && pattern.contains("vertical press") {
            avoidContexts.insert("shoulder_risk")
        }

        if primary.contains(normalized("Quads")) && (equipment == "Machine" || name.contains("leg press") || name.contains("hack squat")) {
            preferredContexts.formUnion(["shift_work_friendly", "short_session"])
        }

        if equipment == "Cable" || equipment == "Machine" {
            stabilityDemand = min(stabilityDemand, 2)
        }

        return ExerciseMetadata(
            canonicalName: metadata.canonicalName,
            primaryAreas: metadata.primaryAreas,
            secondaryAreas: metadata.secondaryAreas,
            movementPattern: metadata.movementPattern,
            fatigueCost: metadata.fatigueCost,
            equipment: equipment,
            exerciseClass: exerciseClass,
            systemicFatigue: systemicFatigue,
            stabilityDemand: stabilityDemand,
            shoulderRisk: shoulderRisk,
            preferredContexts: Array(preferredContexts).sorted(),
            avoidContexts: Array(avoidContexts).sorted()
        )
    }

    func priorityAccessoryCatalog(for intent: MusclePriorityIntent) -> [(name: String, target: String)] {
        intent.accessoryCatalog
    }

    func priorityCoverageKeywords(for focusArea: String) -> [String] {
        let profile = priorityProfile(for: focusArea)
        let normalizedArea = normalizedPriorityText(focusArea)
        let profileKeywords = profile.coverageKeywords.map(normalizedPriorityText)
        let rawAreaTokens = normalizedArea
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
        let qualifierTokens: Set<String> = [
            "upper", "lower", "front", "rear", "anterior", "posterior", "lateral", "mid"
        ]
        let hasSpecificQualifier = rawAreaTokens.count > 1 && rawAreaTokens.contains(where: qualifierTokens.contains)
        let areaTokens = hasSpecificQualifier ? [String]() : rawAreaTokens

        return Array(Set(profileKeywords + areaTokens + [normalizedArea]))
    }

    func priorityProfile(for focusArea: String) -> PriorityFocusProfile {
        let normalizedArea = normalizedPriorityText(focusArea)
        if let matchedProfile = priorityProfiles
            .sorted(by: priorityProfileSpecificitySort)
            .first(where: { profile in
                profile.triggerKeywords.contains(where: { containsPriorityPhrase(in: normalizedArea, keywords: [$0]) })
            }) {
            return matchedProfile
        }

        return PriorityFocusProfile(
            label: focusArea,
            triggerKeywords: [focusArea],
            coverageKeywords: [focusArea],
            preferredStyles: ["Upper", "Push", "Pull", "Legs", "Arms", "Lower"],
            accessoryCatalog: genericExerciseCatalog()
        )
    }

    var priorityProfiles: [PriorityFocusProfile] {
        [
            PriorityFocusProfile(
                label: "Biceps",
                triggerKeywords: ["bicep", "biceps"],
                coverageKeywords: ["bicep", "biceps", "curl", "preacher curl", "incline curl", "cable curl"],
                preferredStyles: ["Arms", "Pull", "Upper"],
                accessoryCatalog: [
                    ("EZ-Bar Curl", "Biceps"),
                    ("Incline Dumbbell Curl", "Biceps"),
                    ("Spider Curl", "Biceps"),
                    ("Bayesian Cable Curl", "Biceps"),
                    ("Concentration Curl", "Biceps"),
                    ("Machine Preacher Curl", "Biceps")
                ]
            ),
            PriorityFocusProfile(
                label: "Triceps",
                triggerKeywords: ["tricep", "triceps"],
                coverageKeywords: ["tricep", "triceps", "pressdown", "triceps extension", "skull crusher", "close-grip", "jm press"],
                preferredStyles: ["Arms", "Push", "Upper"],
                accessoryCatalog: [
                    ("Rope Triceps Pressdown", "Triceps"),
                    ("Overhead Cable Triceps Extension", "Triceps"),
                    ("V-Bar Pressdown", "Triceps"),
                    ("Cable Kickback", "Triceps"),
                    ("Dumbbell Overhead Triceps Extension", "Triceps")
                ]
            ),
            PriorityFocusProfile(
                label: "Lats",
                triggerKeywords: ["lat", "lats", "latissimus dorsi", "latissimus"],
                coverageKeywords: ["lat", "lats", "latissimus dorsi", "lat pulldown", "pull-up", "pull up", "straight-arm pulldown", "single-arm row"],
                preferredStyles: ["Pull", "Upper"],
                accessoryCatalog: [
                    ("Lat Pulldown", "Lats"),
                    ("Straight-Arm Pulldown", "Lats"),
                    ("Neutral-Grip Lat Pulldown", "Lats"),
                    ("Cable Pullover", "Lats"),
                    ("Machine Lat Pulldown", "Lats")
                ]
            ),
            PriorityFocusProfile(
                label: "Upper Back",
                triggerKeywords: ["upper back", "mid back", "scap"],
                coverageKeywords: ["upper back", "mid back", "row", "chest-supported row", "machine row", "t-bar row", "face pull"],
                preferredStyles: ["Pull", "Upper"],
                accessoryCatalog: [
                    ("Chest-Supported Row", "Upper Back"),
                    ("Machine Row", "Mid Back"),
                    ("Cable High Row", "Upper Back"),
                    ("Barbell Bent-Over Row", "Upper Back"),
                    ("Meadows Row", "Upper Back")
                ]
            ),
            PriorityFocusProfile(
                label: "Lower Abs",
                triggerKeywords: ["lower abs"],
                coverageKeywords: ["lower abs", "leg raise", "knee raise", "reverse crunch"],
                preferredStyles: ["Legs", "Lower", "Upper"],
                accessoryCatalog: [
                    ("Hanging Knee Raise", "Lower Abs"),
                    ("Cable Crunch", "Abs")
                ]
            ),
            PriorityFocusProfile(
                label: "Obliques",
                triggerKeywords: ["oblique", "obliques"],
                coverageKeywords: ["oblique", "obliques", "pallof", "side plank", "woodchop"],
                preferredStyles: ["Legs", "Lower", "Upper"],
                accessoryCatalog: [
                    ("Pallof Press", "Obliques"),
                    ("Ab Wheel Rollout", "Anterior Core")
                ]
            ),
            PriorityFocusProfile(
                label: "Anterior Core",
                triggerKeywords: ["anterior core"],
                coverageKeywords: ["anterior core", "ab wheel", "rollout", "plank", "dead bug"],
                preferredStyles: ["Legs", "Lower", "Upper"],
                accessoryCatalog: [
                    ("Ab Wheel Rollout", "Anterior Core"),
                    ("Pallof Press", "Obliques")
                ]
            ),
            PriorityFocusProfile(
                label: "Lateral Deltoids",
                triggerKeywords: ["lateral deltoids", "lateral delt", "side delt"],
                coverageKeywords: ["lateral deltoids", "lateral delt", "side delt", "lateral raise", "cable lateral raise", "machine lateral raise", "dumbbell lateral raise"],
                preferredStyles: ["Push", "Upper", "Arms"],
                accessoryCatalog: [
                    ("Cable Lateral Raise", "Lateral Deltoids"),
                    ("Machine Lateral Raise", "Lateral Deltoids"),
                    ("Dumbbell Lateral Raise", "Lateral Deltoids"),
                    ("Behind-the-Back Cable Lateral Raise", "Lateral Deltoids"),
                    ("Leaning Dumbbell Lateral Raise", "Lateral Deltoids"),
                    ("Lying Incline Dumbbell Lateral Raise", "Lateral Deltoids")
                ]
            ),
            PriorityFocusProfile(
                label: "Posterior Deltoids",
                triggerKeywords: ["posterior deltoids", "posterior delt", "rear delts", "rear delt"],
                coverageKeywords: ["posterior deltoids", "posterior delt", "rear delts", "rear delt", "reverse pec deck", "reverse fly", "face pull"],
                preferredStyles: ["Pull", "Upper"],
                accessoryCatalog: [
                    ("Reverse Pec Deck", "Rear Deltoids"),
                    ("Cable Rear Delt Fly", "Rear Deltoids"),
                    ("Chest-Supported Rear Delt Row", "Rear Deltoids"),
                    ("Prone Incline Dumbbell Rear Delt Raise", "Rear Deltoids"),
                    ("Reverse Cable Crossover", "Rear Deltoids"),
                    ("Dumbbell Rear Delt Fly", "Rear Deltoids")
                ]
            ),
            PriorityFocusProfile(
                label: "Anterior Deltoids",
                triggerKeywords: ["anterior deltoids", "anterior delt", "front delts", "front delt"],
                coverageKeywords: ["anterior deltoids", "anterior delt", "front delts", "front delt", "shoulder press", "overhead press"],
                preferredStyles: ["Push", "Upper"],
                accessoryCatalog: [
                    ("Seated Dumbbell Shoulder Press", "Anterior Deltoids"),
                    ("Machine Shoulder Press", "Anterior Deltoids")
                ]
            ),
            PriorityFocusProfile(
                label: "Upper Chest",
                triggerKeywords: ["upper chest", "clavicular"],
                coverageKeywords: ["upper chest", "clavicular", "incline press", "incline dumbbell press", "incline barbell press", "low incline", "incline fly"],
                preferredStyles: ["Push", "Upper"],
                accessoryCatalog: [
                    ("Incline Dumbbell Press", "Upper Chest"),
                    ("Incline Barbell Press", "Upper Chest"),
                    ("Low-Incline Cable Fly", "Upper Chest"),
                    ("Machine Incline Press", "Upper Chest"),
                    ("Low-Incline Dumbbell Fly", "Upper Chest"),
                    ("Incline Smith Machine Press", "Upper Chest")
                ]
            ),
            PriorityFocusProfile(
                label: "Chest",
                triggerKeywords: ["chest", "pec"],
                coverageKeywords: ["chest", "pec", "bench press", "chest press", "incline press", "fly", "dip"],
                preferredStyles: ["Push", "Upper"],
                accessoryCatalog: [
                    ("Machine Chest Press", "Chest"),
                    ("Cable Fly", "Chest"),
                    ("Dumbbell Bench Press", "Chest"),
                    ("Flat Dumbbell Fly", "Chest"),
                    ("Pec Deck", "Chest")
                ]
            ),
            PriorityFocusProfile(
                label: "Shoulders",
                triggerKeywords: ["shoulder", "delt", "deltoid"],
                coverageKeywords: ["shoulder", "delt", "deltoid", "lateral raise", "rear delt", "shoulder press", "face pull"],
                preferredStyles: ["Push", "Upper", "Arms"],
                accessoryCatalog: [
                    ("Cable Lateral Raise", "Lateral Deltoids"),
                    ("Reverse Pec Deck", "Rear Deltoids")
                ]
            ),
            PriorityFocusProfile(
                label: "Back",
                triggerKeywords: ["back", "lat", "lats"],
                coverageKeywords: ["back", "lat", "lats", "row", "pulldown", "pull-up", "upper back", "mid back"],
                preferredStyles: ["Pull", "Upper"],
                accessoryCatalog: [
                    ("Chest-Supported Row", "Upper Back"),
                    ("Lat Pulldown", "Lats")
                ]
            ),
            PriorityFocusProfile(
                label: "Arms",
                triggerKeywords: ["arm", "bicep", "tricep", "triceps", "biceps", "forearm"],
                coverageKeywords: ["arm", "bicep", "tricep", "triceps", "biceps", "curl", "pressdown", "triceps extension", "skull crusher", "close-grip", "hammer curl", "forearm", "brachialis"],
                preferredStyles: ["Arms", "Upper", "Push", "Pull"],
                accessoryCatalog: [
                    ("Incline Dumbbell Curl", "Biceps"),
                    ("Overhead Cable Triceps Extension", "Triceps")
                ]
            ),
            PriorityFocusProfile(
                label: "Core/Abs",
                triggerKeywords: ["core", "abs", "abdominal", "oblique", "serratus", "midsection"],
                coverageKeywords: ["core", "abs", "abdominal", "oblique", "serratus", "crunch", "plank", "pallof", "rollout", "leg raise", "knee raise"],
                preferredStyles: ["Legs", "Lower", "Upper"],
                accessoryCatalog: coreExerciseCatalog()
            ),
            PriorityFocusProfile(
                label: "Glutes",
                triggerKeywords: ["glute", "glutes"],
                coverageKeywords: ["glute", "hip thrust", "split squat", "rdl", "romanian deadlift", "hinge"],
                preferredStyles: ["Lower", "Legs"],
                accessoryCatalog: [
                    ("Hip Thrust", "Glutes"),
                    ("Bulgarian Split Squat", "Quads/Glutes"),
                    ("Cable Glute Kickback", "Glutes"),
                    ("Single-Leg Hip Thrust", "Glutes"),
                    ("Reverse Lunge", "Glutes"),
                    ("45-Degree Back Extension", "Glutes")
                ]
            ),
            PriorityFocusProfile(
                label: "Quads",
                triggerKeywords: ["quad", "quads"],
                coverageKeywords: ["quad", "quads", "squat", "leg press", "leg extension", "hack squat"],
                preferredStyles: ["Lower", "Legs"],
                accessoryCatalog: [
                    ("Front Squat", "Quads"),
                    ("Leg Extension", "Quads"),
                    ("Pendulum Squat", "Quads"),
                    ("Belt Squat", "Quads"),
                    ("Hack Squat", "Quads")
                ]
            ),
            PriorityFocusProfile(
                label: "Hamstrings",
                triggerKeywords: ["hamstring", "hamstrings"],
                coverageKeywords: ["hamstring", "hamstrings", "rdl", "romanian deadlift", "leg curl", "hinge"],
                preferredStyles: ["Lower", "Legs"],
                accessoryCatalog: [
                    ("Romanian Deadlift", "Hamstrings"),
                    ("Seated Leg Curl", "Hamstrings"),
                    ("Nordic Hamstring Curl", "Hamstrings"),
                    ("Lying Leg Curl", "Hamstrings"),
                    ("Stiff-Leg Deadlift", "Hamstrings")
                ]
            ),
            PriorityFocusProfile(
                label: "Calves",
                triggerKeywords: ["calf", "calves"],
                coverageKeywords: ["calf", "calves", "calf raise"],
                preferredStyles: ["Lower", "Legs"],
                accessoryCatalog: [
                    ("Standing Calf Raise", "Calves"),
                    ("Seated Calf Raise", "Calves")
                ]
            )
        ]
    }

    func normalizedPriorityText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    func priorityTextTokens(_ text: String) -> [String] {
        normalizedPriorityText(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func containsPriorityPhrase(in text: String, keywords: [String]) -> Bool {
        let haystackTokens = priorityTextTokens(text)

        return keywords.contains { keyword in
            let needleTokens = priorityTextTokens(keyword)
            guard !needleTokens.isEmpty, needleTokens.count <= haystackTokens.count else {
                return false
            }

            for startIndex in 0...(haystackTokens.count - needleTokens.count) {
                let slice = Array(haystackTokens[startIndex..<(startIndex + needleTokens.count)])
                if slice == needleTokens {
                    return true
                }
            }

            return false
        }
    }

    func priorityProfileSpecificitySort(_ lhs: PriorityFocusProfile, _ rhs: PriorityFocusProfile) -> Bool {
        let lhsSpecificity = lhs.triggerKeywords.map { priorityTextTokens($0).count }.max() ?? 0
        let rhsSpecificity = rhs.triggerKeywords.map { priorityTextTokens($0).count }.max() ?? 0
        if lhsSpecificity != rhsSpecificity {
            return lhsSpecificity > rhsSpecificity
        }

        let lhsKeywordLength = lhs.triggerKeywords.map(\.count).max() ?? 0
        let rhsKeywordLength = rhs.triggerKeywords.map(\.count).max() ?? 0
        return lhsKeywordLength > rhsKeywordLength
    }

    func exerciseMatchesTrainingIntent(name: String, target: String, intent: MusclePriorityIntent) -> Bool {
        let combined = normalizedPriorityText("\(name) \(target)")
        return containsPriorityPhrase(in: combined, keywords: intent.coverageKeywords)
    }

    func exerciseMatchesDayStyle(_ exercise: WorkoutExerciseResponse, style: String) -> Bool {
        let exerciseText = "\(exercise.exerciseName) \(exercise.muscleTarget)".lowercased()
        let forbidden = forbiddenKeywords(for: style)
        if forbidden.contains(where: { (keyword: String) -> Bool in exerciseText.contains(keyword) }) {
            return false
        }

        let preferred = preferredKeywords(for: style)
        if preferred.isEmpty {
            return true
        }
        return preferred.contains(where: { (keyword: String) -> Bool in exerciseText.contains(keyword) })
    }

    func preferredKeywords(for style: String) -> [String] {
        switch style.lowercased() {
        case "arms":
            return ["bicep", "tricep", "arm", "curl", "extension", "pressdown", "brachialis", "close-grip", "skull crusher"]
        case "legs", "lower":
            return ["quad", "hamstring", "glute", "calf", "squat", "deadlift", "lunge", "leg press", "hip thrust", "core", "abs", "oblique"]
        case "push":
            return ["chest", "shoulder", "tricep", "press", "fly", "dip", "lateral raise"]
        case "pull":
            return ["back", "lat", "row", "pulldown", "rear delt", "bicep", "face pull"]
        case "upper":
            return ["chest", "back", "lat", "shoulder", "delt", "rear delt", "tricep", "bicep", "row", "press", "pulldown", "lateral raise", "face pull", "core", "abs", "oblique"]
        default:
            return []
        }
    }

    func forbiddenKeywords(for style: String) -> [String] {
        switch style.lowercased() {
        case "arms":
            return ["squat", "deadlift", "lunge", "leg press", "leg extension", "leg curl", "calf raise", "hip thrust", "lat pulldown", "pull-up", "pull up", "row", "rear delt row"]
        case "legs", "lower":
            return ["bench", "chest press", "row", "pulldown", "pull-up", "triceps", "biceps", "lateral raise", "shoulder press"]
        case "push":
            return ["squat", "deadlift", "lunge", "leg press", "leg extension", "leg curl", "calf raise"]
        case "pull":
            return ["squat", "deadlift", "lunge", "leg press", "leg extension", "leg curl", "calf raise", "bench press"]
        case "upper":
            return ["squat", "leg press", "leg extension", "leg curl", "walking lunge", "calf raise", "hip thrust"]
        default:
            return []
        }
    }

    func polishedTrainingDayNotes(
        rawNotes: String,
        dayStyle: String?,
        weekNumber: Int,
        exercises: [WorkoutExerciseResponse]
    ) -> String {
        let trimmed = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Trust the AI. Only synthesize a fallback when the model truly gave us nothing
        // usable (empty or a handful of words). Never overwrite real coaching content just
        // because it didn't contain certain keywords.
        if isEmptyOrTooShortSessionNote(trimmed) {
            let style = dayStyle ?? "Training"
            let primaryLift = exercises.first?.exerciseName ?? "first compound movement"
            let warmup = warmupCue(for: style, primaryLift: primaryLift)
            let mobility = mobilityCue(for: style)
            let phase = phaseSentence(for: weekNumber)
            return evidenceTunedCoachingLanguage(
                "\(style) session. \(phase) Warm-up: \(warmup) Mobility/activation: \(mobility)"
            )
        }

        return evidenceTunedCoachingLanguage(trimmed)
    }

    /// Only true when the note is genuinely missing content — empty, or so short it can't
    /// carry the intent + warm-up guidance we need. Does NOT keyword-sniff.
    func isEmptyOrTooShortSessionNote(_ notes: String) -> Bool {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let wordCount = trimmed.split { $0.isWhitespace || $0.isNewline }.count
        return wordCount < 6
    }

    func warmupCue(for style: String, primaryLift: String) -> String {
        switch style.lowercased() {
        case "legs", "lower":
            return "5-7 min bike, then 2-3 ramp sets into \(primaryLift) with progressive loading."
        case "arms":
            return "3-5 min light cardio, then elbow and shoulder prep plus 2 ramp sets for \(primaryLift)."
        case "push":
            return "Band shoulder prep, thoracic extension work, then 2-3 ramp sets into \(primaryLift)."
        case "pull":
            return "Scapular pull activation, lat engagement drills, then 2-3 ramp sets for \(primaryLift)."
        case "upper":
            return "5 min incline walk, shoulder/scap prep, then 2-3 progressive ramp sets into \(primaryLift)."
        default:
            return "5 min light cardio and 2-3 progressive ramp sets into \(primaryLift)."
        }
    }

    func mobilityCue(for style: String) -> String {
        switch style.lowercased() {
        case "legs", "lower":
            return "ankle dorsiflexion drills, hip flexor stretch, and adductor rock-backs between early sets."
        case "arms":
            return "wrist flexor/extensor mobility and light band triceps/biceps activation."
        case "push":
            return "pec minor stretch, band external rotations, and serratus activation before pressing."
        case "pull":
            return "thoracic extension work, lat stretch, and band pull-aparts for scapular control."
        case "upper":
            return "thoracic mobility plus shoulder internal/external rotation prep between warm-up sets."
        default:
            return "dynamic mobility for the primary joints, then activation for the target muscle groups."
        }
    }

    func phaseSentence(for weekNumber: Int) -> String {
        switch weekNumber {
        case 2:
            return "Volume build: add quality work while keeping reps clean."
        case 3:
            return "Peak stress week: push top sets hard without sacrificing position."
        case 4:
            return "Deload emphasis: reduce fatigue and sharpen execution."
        default:
            return "Baseline week: establish repeatable technique and progression anchors."
        }
    }

}
