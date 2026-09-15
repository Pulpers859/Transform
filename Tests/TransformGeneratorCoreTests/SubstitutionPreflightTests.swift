import XCTest
@testable import Transform

@MainActor
final class SubstitutionPreflightTests: XCTestCase {
    private let service = ClaudeService.shared
    private func slot(_ name: String, _ target: String) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
            movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
            role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: 2)
    }
    private func plan(style: String = "Arms", rest: Bool = false, injury: String = "(none)",
                      focus: String? = nil, priority: Bool = false, dayCount: Int = 1,
                      priorityArea: String = "Rear Deltoids", constrained: Bool = false) -> ClaudeService.ProgramBlueprint {
        let allocations: [ClaudeService.BlueprintPriorityAllocation] = priority ? [
            .init(area: priorityArea, priorityLevel: "High", rationale: "", targetFrequency: 1,
                targetExerciseSlots: 1, directSetTarget: 6, weightedStimulusTarget: 6,
                maxPerSessionDirectSets: 6, maxFocusSessionDirectSets: 6, preferredStyles: ["Pull"],
                preferredMovementPatterns: [], volumeBias: "Moderate", directWorkBias: "High")
        ] : []
        return .init(evidenceVersion: "test", splitRecommendation: style, weeklyTrainingDays: rest ? 0 : dayCount,
            priorityAllocations: allocations, dayPlans: (1...dayCount).map { day in
                .init(dayIndex: day, style: style, focusArea: focus, supportAreas: [], targetFatigueCap: 48,
                    targetSessionMinutes: 75, targetPrioritySlots: 1, emphasisPatterns: [], isRestDay: rest)
            }, topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: injury,
            programmingNotes: [], calibration: constrained ? .init(lowPerformanceDataQuality: false,
                poorNutritionAdherence: false, recoveryConstrained: true, recoveryTier: .constrained,
                recoveryAudit: "test", recompositionGoal: false, weeklyVolumeScale: 1,
                reduceExerciseSlotComplexity: false, defaultSessionTimeCapMinutes: 75,
                sessionTimeCapsByStyle: [:], programmingNotes: []) : service.neutralCalibrationProfile())
    }
    private func focusIntent(_ area: String) -> ClaudeService.MusclePriorityIntent {
        .init(area: area, priorityLevel: "High", rank: 0, rationale: "test", weeklyDayTarget: 2,
            weeklyExerciseTarget: 2, weeklyDirectSetTarget: 6, weeklyStimulusTarget: 6,
            preferredStyles: ["Arms"], preferredMovementPatterns: [], coverageKeywords: [],
            accessoryCatalog: [], volumeBias: "Moderate", directWorkBias: "High")
    }
    private func planned(_ base: [[ClaudeService.PreSelectedExercise]], blueprint: ClaudeService.ProgramBlueprint,
                         history: ClaudeService.ExerciseHistoryContext? = nil,
                         focus: ClaudeService.MusclePriorityIntent? = nil) -> ClaudeService.SubstitutionPlanningBaseline {
        .init(menus: base, blueprint: blueprint, weekNumber: 1,
            lockedPrefixCounts: Array(repeating: 0, count: base.count),
            retainedKeysByDay: Array(repeating: [], count: base.count), exerciseHistory: history,
            selectionFocusIntents: Array(repeating: focus, count: base.count))
    }
    // Small synthetic preflight inputs, not claims of complete useful workouts.
    private var baseline: [[ClaudeService.PreSelectedExercise]] {
        [[slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
          slot("V-Bar Pressdown", "Triceps"), slot("Machine Chest Press", "Chest"), slot("Standing Calf Raise", "Calves")]]
    }
    private func candidate(_ base: [[ClaudeService.PreSelectedExercise]], name: String = "Cable Kickback") -> [[ClaudeService.PreSelectedExercise]] {
        var result = base
        result[0][2] = slot(name, "Triceps")
        return result
    }
    private func check(_ proposal: [[ClaudeService.PreSelectedExercise]], _ base: [[ClaudeService.PreSelectedExercise]],
                       blueprint: ClaudeService.ProgramBlueprint? = nil, locks: [Int] = [0], pain: [String] = []) -> ClaudeService.SubstitutionPreflight {
        service.preflightFixedDoseSubstitution(proposal, baseline: base, blueprint: blueprint ?? plan(),
            lockedPrefixCounts: locks, painExclusions: .init(exerciseNames: pain))
    }

    func testExactCatalogAlternativeAndExplicitPainHistory() {
        let base = baseline, proposal = candidate(baseline)
        XCTAssertEqual(check(proposal, base), .structurallyEligible)
        let key = ExerciseWeightEntry.canonicalLookupKey("Cable Kickbacks")
        XCTAssertEqual(key, ExerciseWeightEntry.canonicalLookupKey("Cable Kickback"))
        XCTAssertEqual(check(proposal, base, pain: ["Cable Kickbacks"]), .rejected(.painHistory))
        let history = ClaudeService.ExerciseHistoryContext(painExercises: [key], equipmentSkipExercises: [],
            priorMesocycleExercises: [], mesocycleIndex: 0)
        XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal, baseline: base, blueprint: plan(),
            lockedPrefixCounts: [0], painExclusions: .init(history: history)), .rejected(.painHistory))
        let catalog = service.applyHistoryFilters(service.exerciseCatalog(for: "Arms"), avoidedExercises: [],
            deprioritizedExercises: [key], catalogOffset: 0, weekNumber: 1, priorMesocycleExercises: [])
        XCTAssertTrue(catalog.contains { $0.name == "Cable Kickback" }, "Equipment skip is a preference, not pain")
        XCTAssertEqual(check(proposal, base, blueprint: plan(injury: "Right shoulder pain with Cable Kickback")),
            .rejected(.reportedShoulderConcern))
    }

    func testRetainedIdentityIsProtectedWithoutAnOrderingLock() {
        let base = baseline
        let planned = ClaudeService.SubstitutionPlanningBaseline(menus: base, blueprint: plan(),
            weekNumber: 2, lockedPrefixCounts: [0],
            retainedKeysByDay: [[ExerciseWeightEntry.canonicalLookupKey("V-Bar Pressdown")]],
            exerciseHistory: nil, selectionFocusIntents: [nil])
        XCTAssertEqual(check(candidate(base), base), .structurallyEligible)
        XCTAssertEqual(service.preflightFixedDoseSubstitution(candidate(base), plannedBaseline: planned),
            .rejected(.retainedSlot))
        var reordered = base
        reordered[0].swapAt(2, 4)
        var proposal = reordered
        proposal[0][4] = slot("Cable Kickback", "Triceps")
        let moved = ClaudeService.SubstitutionPlanningBaseline(menus: reordered, blueprint: plan(),
            weekNumber: 2, lockedPrefixCounts: [0], retainedKeysByDay: planned.retainedKeysByDay,
            exerciseHistory: nil, selectionFocusIntents: [nil])
        XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal, plannedBaseline: moved), .rejected(.retainedSlot))
    }

    func testShapeScopeAndExplicitLockContextFailClosed() {
        let base = baseline, proposal = candidate(baseline)
        for focusIntents: [ClaudeService.MusclePriorityIntent?] in [[], [nil, nil]] {
            let malformed = ClaudeService.SubstitutionPlanningBaseline(menus: base, blueprint: plan(),
                weekNumber: 1, lockedPrefixCounts: [0], retainedKeysByDay: [[]],
                exerciseHistory: nil, selectionFocusIntents: focusIntents)
            XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal, plannedBaseline: malformed),
                .rejected(.lockContext))
        }
        XCTAssertEqual(check([], base), .rejected(.shape))
        XCTAssertEqual(check([Array(proposal[0].dropLast())], base), .rejected(.shape))
        for locks in [[], [-1], [6], [0, 0]] {
            XCTAssertEqual(check(proposal, base, locks: locks), .rejected(.lockContext))
        }
        XCTAssertEqual(check(proposal, base, blueprint: plan(rest: true)), .rejected(.restDay))
        XCTAssertEqual(check(base, base), .rejected(.changeScope))
        var extra = proposal
        extra[0][4].prescribedSets += 1
        XCTAssertEqual(check(extra, base), .rejected(.changeScope))
        extra = proposal
        extra[0][4] = slot("Seated Calf Raise", "Calves")
        XCTAssertEqual(check(extra, base), .rejected(.changeScope))
    }

    func testProtectedSlotsUseCanonicalRolesAndExplicitPrefix() {
        let base = baseline
        XCTAssertEqual(check(candidate(base), base, locks: [3]), .rejected(.protectedSlot))
        var first = base
        first[0][0] = slot("Cable Curl", "Biceps")
        XCTAssertEqual(check(first, base), .rejected(.protectedSlot))
        for (name, target, style) in [("Flat Barbell Bench Press", "Chest", "Arms"), ("Leg Press", "Quads", "Lower")] {
            var protected = base
            protected[0][2] = slot(name, target)
            XCTAssertEqual(check(candidate(protected), protected, blueprint: plan(style: style)), .rejected(.protectedSlot))
        }
        var forged = base
        forged[0][2] = .init(exerciseName: "Flat Barbell Bench Press", muscleTarget: "Chest",
            movementPattern: "Horizontal Press", role: .accessory, prescribedSets: 2)
        XCTAssertEqual(check(candidate(forged), forged), .rejected(.protectedSlot))
    }

    func testCatalogMetadataAndDuplicateChecks() {
        let base = baseline
        XCTAssertEqual(check(candidate(base, name: "Invented Triceps Machine"), base), .rejected(.catalog))
        XCTAssertEqual(check(candidate(base), base, blueprint: plan(style: "Pull")), .rejected(.catalog))
        for replacement in [
            ClaudeService.PreSelectedExercise(exerciseName: "Cable Kickback", muscleTarget: "Triceps", movementPattern: "Row", role: .accessory, prescribedSets: 2),
            .init(exerciseName: "Cable Kickback", muscleTarget: "Triceps", movementPattern: "Extension", role: .anchor, prescribedSets: 2)
        ] {
            var proposal = base
            proposal[0][2] = replacement
            XCTAssertEqual(check(proposal, base), .rejected(.metadata))
        }
        var duplicated = base
        duplicated[0][1] = slot("Cable Kickback", "Triceps")
        XCTAssertEqual(check(candidate(duplicated), duplicated), .rejected(.duplicate))
    }

    func testPreservesLastPatternAndRejectsThirdExtension() {
        var lastPattern = baseline
        lastPattern[0][1] = slot("Seated Calf Raise", "Calves")
        XCTAssertEqual(check(candidate(lastPattern), lastPattern), .rejected(.coverage))
        var crowded = baseline
        crowded[0][1] = slot("Overhead Cable Triceps Extension", "Triceps")
        crowded[0][3] = slot("EZ-Bar Skull Crusher", "Triceps")
        crowded[0][4] = slot("Rope Triceps Pressdown", "Triceps")
        XCTAssertEqual(check(candidate(crowded), crowded), .rejected(.patternCap))
    }

    func testPriorityAndDayFocusCannotDowngradeQuality() {
        let base = [[slot("EZ-Bar Curl", "Biceps"), slot("Reverse Pec Deck", "Rear Deltoids"),
            slot("Prone Incline Dumbbell Rear Delt Raise", "Rear Deltoids"), slot("Cable High Row", "Upper Back"),
            slot("Lat Pulldown", "Lats")]]
        var proposal = base
        proposal[0][1] = slot("Cable Face Pull", "Rear Deltoids")
        for (focus, priority) in [(Optional("Rear Deltoids"), false), (nil, true)] {
            let blueprint = plan(style: "Pull", focus: focus, priority: priority)
            XCTAssertEqual(check(proposal, base, blueprint: plan(style: "Pull", focus: focus, priority: priority)),
                .rejected(.focusQuality))
            XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal,
                plannedBaseline: planned(base, blueprint: blueprint, focus: focus.map(focusIntent))),
                .rejected(.focusQuality))
        }
    }

    func testPatternCapExcludesTheSlotBeingReplaced() {
        let base = [[slot("Rope Triceps Pressdown", "Triceps"), slot("Incline Dumbbell Curl", "Biceps"),
            slot("EZ-Bar Curl", "Biceps"), slot("Machine Chest Press", "Chest"), slot("Standing Calf Raise", "Calves")]]
        var proposal = base
        proposal[0][2] = slot("Dumbbell Spider Curl", "Biceps")
        XCTAssertEqual(check(proposal, base), .structurallyEligible)
    }

    func testAnotherDayCannotHideTheChangedDaysLostPattern() {
        var base = baseline
        base[0][1] = slot("Seated Calf Raise", "Calves")
        base.append(baseline[0])
        let proposal = candidate(base)
        XCTAssertEqual(check(proposal, base, blueprint: plan(dayCount: 2), locks: [0, 0]), .rejected(.coverage))
    }

    func testEquipmentPreferenceIsRelativeNotAnAbsoluteBan() {
        let base = baseline, proposal = candidate(baseline)
        let newKey = ExerciseWeightEntry.canonicalLookupKey("Cable Kickbacks")
        let oldKey = ExerciseWeightEntry.canonicalLookupKey("V-Bar Pressdown")
        for (skipped, expected) in [
            (Set([newKey]), ClaudeService.SubstitutionPreflight.rejected(.equipmentPreference)),
            (Set([newKey, oldKey]), .structurallyEligible),
            (Set([oldKey]), .structurallyEligible)
        ] {
            let history = ClaudeService.ExerciseHistoryContext(painExercises: [], equipmentSkipExercises: skipped,
                priorMesocycleExercises: [], mesocycleIndex: 0)
            XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal,
                plannedBaseline: planned(base, blueprint: plan(), history: history)), expected)
        }
    }

    func testSelectionScoreUsesCapturedFocusAndRecoveryContext() {
        let base = baseline, proposal = candidate(baseline, name: "Overhead Cable Triceps Extension")
        let blueprint = plan(focus: "Triceps", constrained: true)
        let focus = focusIntent("Triceps")
        let context = ClaudeService.ExerciseSelectionContext(calibration: blueprint.calibration,
            injuryRiskFocus: blueprint.injuryRiskFocus, style: "Arms")
        XCTAssertLessThan(service.exerciseSelectionScore(exerciseName: "Overhead Cable Triceps Extension",
            muscleTarget: "Triceps", focusIntent: focus, selectionContext: context),
            service.exerciseSelectionScore(exerciseName: "V-Bar Pressdown", muscleTarget: "Triceps",
                focusIntent: focus, selectionContext: context))
        XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal,
            plannedBaseline: planned(base, blueprint: blueprint, focus: focus)), .rejected(.selectionPreference))
        XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal,
            plannedBaseline: planned(base, blueprint: blueprint)), .structurallyEligible,
            "No synthetic score gate on a day the builder did not score")
        XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal,
            plannedBaseline: planned(base, blueprint: plan(focus: "Triceps"), focus: focus)), .structurallyEligible,
            "The constrained-recovery preference must not become an unconditional exercise ban")
    }

    func testWholeWeekVariationCountsRepeatedOldIdentityElsewhere() {
        var base = baseline
        base.append([slot("V-Bar Pressdown", "Triceps"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("EZ-Bar Skull Crusher", "Triceps"), slot("Overhead Cable Triceps Extension", "Triceps")])
        let blueprint = plan(priority: true, dayCount: 2, priorityArea: "Triceps")
        XCTAssertTrue(service.weeklyVariationViolations(in: base, blueprint: blueprint).isEmpty)
        let proposal = candidate(base)
        XCTAssertEqual(check(proposal, base, blueprint: blueprint, locks: [0, 0]), .structurallyEligible)
        XCTAssertEqual(service.weeklyVariationViolations(in: proposal, blueprint: blueprint).first?.count, 5)
        XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal,
            plannedBaseline: planned(base, blueprint: blueprint)), .rejected(.weeklyVariation))
        base[1].removeFirst()
        XCTAssertEqual(service.preflightFixedDoseSubstitution(candidate(base),
            plannedBaseline: planned(base, blueprint: blueprint)), .structurallyEligible)
    }

    func testPrimeReplacementAtCapAndUnrelatedSwapWithInheritedPrimeExcess() {
        var base = baseline
        base[0].append(slot("Overhead Cable Triceps Extension", "Triceps"))
        let blueprint = plan(focus: "Triceps")
        XCTAssertEqual(service.preflightFixedDoseSubstitution(candidate(base),
            plannedBaseline: planned(base, blueprint: blueprint)), .structurallyEligible)
        base[0].append(slot("EZ-Bar Skull Crusher", "Triceps"))
        base[0].append(slot("Incline Dumbbell Curl", "Biceps"))
        var proposal = base
        proposal[0][base[0].count - 1] = slot("Dumbbell Spider Curl", "Biceps")
        XCTAssertEqual(check(proposal, base, blueprint: blueprint), .structurallyEligible)
        XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal,
            plannedBaseline: planned(base, blueprint: blueprint)), .rejected(.focusPrimeCap))
    }

    func testInheritedWeeklyVariationExcessRejectsAnUnrelatedSwap() {
        var base = baseline
        base[0].append(slot("Incline Dumbbell Curl", "Biceps"))
        base.append([slot("EZ-Bar Skull Crusher", "Triceps"), slot("Overhead Cable Triceps Extension", "Triceps"),
            slot("Cable Kickback", "Triceps")])
        let blueprint = plan(priority: true, dayCount: 2, priorityArea: "Triceps")
        var proposal = base
        proposal[0][5] = slot("Dumbbell Spider Curl", "Biceps")
        XCTAssertEqual(service.weeklyVariationViolations(in: base, blueprint: blueprint).first?.count, 5)
        XCTAssertEqual(service.weeklyVariationViolations(in: proposal, blueprint: blueprint).first?.count, 5)
        XCTAssertEqual(check(proposal, base, blueprint: blueprint, locks: [0, 0]), .structurallyEligible)
        XCTAssertEqual(service.preflightFixedDoseSubstitution(proposal,
            plannedBaseline: planned(base, blueprint: blueprint)), .rejected(.weeklyVariation))
    }

    func testPressdownObjectiveCountsOnlyExcessExactCatalogAppearances() {
        func day(_ names: [String]) -> [ClaudeService.PreSelectedExercise] {
            names.map { slot($0, "Triceps") }
        }
        XCTAssertEqual(service.excessPressdownsByDay(in: [[], day(["Rope Triceps Pressdown"]),
            day(["Rope Triceps Pressdown", "V-Bar Pressdown"]),
            day(["Rope Triceps Pressdown", "Cable Triceps Pressdown", "V-Bar Pressdown"])]), [0, 0, 1, 2])
        XCTAssertEqual(service.excessPressdownsByDay(in: [day(["Rope Triceps Pressdown", "Cable Triceps Pressdown"])]),
            service.excessPressdownsByDay(in: [day(["Rope Triceps Pressdown", "V-Bar Pressdown"])]))
        XCTAssertEqual(service.excessPressdownsByDay(in: [day(["Single-Arm Cable Pressdown", "V Bar Pushdown",
            "Rope Pushdown", "Overhead Cable Triceps Extension", "Cable Kickback"])]), [0],
            "Do not invent equivalence for aliases or unilateral movements, or change persisted keys")
    }

    func testCombinedTrialRequiresImprovementAndPreservesFailureReasons() {
        // Synthetic guard-isolation fixture, not a complete useful workout.
        let base = [[slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("V-Bar Pressdown", "Triceps")]]
        let blueprint = plan()
        let context = planned(base, blueprint: blueprint)
        let proposal = candidate(base)
        for malformed in [[], [[]], base + base] as [[[ClaudeService.PreSelectedExercise]]] {
            XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(malformed, plannedBaseline: context),
                .rejected(.eligibility(.shape)), "Shape rejection must precede objective-array indexing")
        }
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(proposal, plannedBaseline: context),
            .qualified(day: 0, excessBefore: 1, excessAfter: 0))
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(base, plannedBaseline: context),
            .rejected(.eligibility(.changeScope)))
        var handleOnly = base
        handleOnly[0][1] = slot("Cable Triceps Pressdown", "Triceps")
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(handleOnly,
            plannedBaseline: planned(base, blueprint: plan(style: "Upper"))), .rejected(.noRedundancyImprovement))
        let triple = [[slot("Rope Triceps Pressdown", "Triceps"), slot("Cable Triceps Pressdown", "Triceps"),
            slot("V-Bar Pressdown", "Triceps")]]
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(candidate(triple),
            plannedBaseline: planned(triple, blueprint: blueprint)), .qualified(day: 0, excessBefore: 2, excessAfter: 1),
            "An incremental reduction is not complete elimination of redundancy")
        let single = [[slot("EZ-Bar Curl", "Biceps"), slot("V-Bar Pressdown", "Triceps")]]
        var singleProposal = single
        singleProposal[0][1] = slot("Cable Kickback", "Triceps")
        XCTAssertEqual(service.excessPressdownsByDay(in: single), [0])
        XCTAssertEqual(service.excessPressdownsByDay(in: singleProposal), [0])
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(singleProposal,
            plannedBaseline: planned(single, blueprint: blueprint)), .rejected(.eligibility(.coverage)),
            "Existing coverage protection refuses loss of the last pressdown pattern before objective scoring")
        var unrelatedBase = base
        unrelatedBase[0].append(slot("Incline Dumbbell Curl", "Biceps"))
        var unrelatedProposal = unrelatedBase
        unrelatedProposal[0][3] = slot("Dumbbell Spider Curl", "Biceps")
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(unrelatedProposal,
            plannedBaseline: planned(unrelatedBase, blueprint: blueprint)), .rejected(.noRedundancyImprovement))
        var underfundedBase = base
        underfundedBase[0][2].prescribedSets = 1
        var underfundedProposal = proposal
        underfundedProposal[0][2].prescribedSets = 1
        XCTAssertEqual(service.preflightFixedDoseSubstitution(underfundedProposal,
            plannedBaseline: planned(underfundedBase, blueprint: blueprint)), .structurallyEligible)
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(underfundedProposal,
            plannedBaseline: planned(underfundedBase, blueprint: blueprint)),
            .rejected(.dose(.roleDose(day: 0, exercise: 2))))
        let history = ClaudeService.ExerciseHistoryContext(
            painExercises: [ExerciseWeightEntry.canonicalLookupKey("Cable Kickback")], equipmentSkipExercises: [],
            priorMesocycleExercises: [], mesocycleIndex: 0)
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(proposal,
            plannedBaseline: planned(base, blueprint: blueprint, history: history)),
            .rejected(.eligibility(.painHistory)))
        for week in [0, 4, 5] {
            let outOfScope = ClaudeService.SubstitutionPlanningBaseline(menus: base, blueprint: blueprint,
                weekNumber: week, lockedPrefixCounts: [0], retainedKeysByDay: [[]],
                exerciseHistory: nil, selectionFocusIntents: [nil])
            XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(proposal, plannedBaseline: outOfScope),
                .rejected(.unsupportedWeek))
        }
    }

    func testBoundedSearchIsDeterministicAndUsesHistoryFilteredCatalog() {
        let base = [[slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("V-Bar Pressdown", "Triceps")]]
        let context = planned(base, blueprint: plan())
        let first = service.searchPressdownReduction(in: context)
        let second = service.searchPressdownReduction(in: context)
        XCTAssertEqual(first.outcome, .proposed(day: 0, slot: 2, replacement: "Overhead Cable Triceps Extension"))
        XCTAssertEqual(first.outcome, second.outcome)
        XCTAssertEqual(first.attempts, second.attempts)
        XCTAssertEqual(service.searchPressdownReduction(in: context,
            maximumTrials: first.attempts.count).outcome, first.outcome)
        XCTAssertEqual(service.searchPressdownReduction(in: context,
            maximumTrials: first.attempts.count - 1).outcome, .searchLimit)
        XCTAssertEqual(first.proposedMenus.map { $0.map(\.exerciseName) }, second.proposedMenus.map { $0.map(\.exerciseName) })
        XCTAssertEqual(service.evaluatePressdownSubstitutionTrial(first.proposedMenus, plannedBaseline: context),
            .qualified(day: 0, excessBefore: 1, excessAfter: 0))
        let history = ClaudeService.ExerciseHistoryContext(
            painExercises: [ExerciseWeightEntry.canonicalLookupKey("Overhead Cable Triceps Extension")],
            equipmentSkipExercises: [], priorMesocycleExercises: [], mesocycleIndex: 0)
        let filtered = service.searchPressdownReduction(in: planned(base, blueprint: plan(), history: history))
        XCTAssertEqual(filtered.outcome, .proposed(day: 0, slot: 2, replacement: "EZ-Bar Skull Crusher"))
        XCTAssertFalse(filtered.attempts.contains { $0.replacement == "Overhead Cable Triceps Extension" })
        XCTAssertEqual(context.menus[0][2].exerciseName, "V-Bar Pressdown")
    }

    func testBoundedSearchReturnsUnchangedPlanAndDistinguishesLimits() {
        let base = [[slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("V-Bar Pressdown", "Triceps")]]
        let locked = ClaudeService.SubstitutionPlanningBaseline(menus: base, blueprint: plan(), weekNumber: 1,
            lockedPrefixCounts: [3], retainedKeysByDay: [[]], exerciseHistory: nil, selectionFocusIntents: [nil])
        XCTAssertEqual(service.searchPressdownReduction(in: locked).outcome, .noQualifiedCandidate)
        XCTAssertTrue(service.searchPressdownReduction(in: locked).attempts.isEmpty)
        var underfunded = base
        underfunded[0][2].prescribedSets = 1
        let failing = planned(underfunded, blueprint: plan())
        for budget in [-1, 0, 1] {
            let result = service.searchPressdownReduction(in: failing, maximumTrials: budget)
            XCTAssertEqual(result.outcome, .searchLimit)
            XCTAssertLessThanOrEqual(result.attempts.count, max(0, budget))
            XCTAssertEqual(result.proposedMenus.map { $0.map(\.exerciseName) }, base.map { $0.map(\.exerciseName) })
            XCTAssertEqual(result.proposedMenus.map { $0.map(\.prescribedSets) }, underfunded.map { $0.map(\.prescribedSets) })
        }
        let exhausted = service.searchPressdownReduction(in: failing)
        XCTAssertEqual(exhausted.outcome, .noQualifiedCandidate)
        XCTAssertEqual(service.searchPressdownReduction(in: failing,
            maximumTrials: exhausted.attempts.count).outcome, .noQualifiedCandidate)
        XCTAssertEqual(service.searchPressdownReduction(in: failing,
            maximumTrials: exhausted.attempts.count - 1).outcome, .searchLimit)
        XCTAssertFalse(exhausted.attempts.isEmpty)
        let noDuplicate = [[slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps")]]
        XCTAssertEqual(service.searchPressdownReduction(in: planned(noDuplicate, blueprint: plan())).outcome, .noRedundancy)
        let malformed = ClaudeService.SubstitutionPlanningBaseline(menus: base, blueprint: plan(), weekNumber: 1,
            lockedPrefixCounts: [], retainedKeysByDay: [[]], exerciseHistory: nil, selectionFocusIntents: [nil])
        XCTAssertEqual(service.searchPressdownReduction(in: malformed).outcome, .invalidContext)
        for week in [0, MesocyclePhase.deloadWeek, MesocyclePhase.deloadWeek + 1] {
            let unsupported = ClaudeService.SubstitutionPlanningBaseline(menus: base, blueprint: plan(),
                weekNumber: week, lockedPrefixCounts: [0], retainedKeysByDay: [[]],
                exerciseHistory: nil, selectionFocusIntents: [nil])
            XCTAssertEqual(service.searchPressdownReduction(in: unsupported).outcome, .unsupportedWeek)
        }
        for locks in [[-1], [4]] {
            let invalid = ClaudeService.SubstitutionPlanningBaseline(menus: base, blueprint: plan(),
                weekNumber: 1, lockedPrefixCounts: locks, retainedKeysByDay: [[]],
                exerciseHistory: nil, selectionFocusIntents: [nil])
            XCTAssertEqual(service.searchPressdownReduction(in: invalid).outcome, .invalidContext)
        }
    }

    func testProtectedEarlyDayDoesNotConsumeLaterDayTrialBudget() {
        let day = [slot("EZ-Bar Curl", "Biceps"), slot("Rope Triceps Pressdown", "Triceps"),
            slot("V-Bar Pressdown", "Triceps")]
        for retainInsteadOfLock in [false, true] {
            let context = ClaudeService.SubstitutionPlanningBaseline(menus: [day, day],
                blueprint: plan(dayCount: 2), weekNumber: 1,
                lockedPrefixCounts: retainInsteadOfLock ? [0, 0] : [3, 0],
                retainedKeysByDay: [retainInsteadOfLock ? Set(day.map {
                    ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) }) : [], []],
                exerciseHistory: nil, selectionFocusIntents: [nil, nil])
            let result = service.searchPressdownReduction(in: context, maximumTrials: 1)
            XCTAssertEqual(result.attempts.count, 1)
            XCTAssertEqual(result.attempts.first?.day, 1,
                "Invariant slot refusals on the early day must not waste later-day search budget")
        }
    }
}
