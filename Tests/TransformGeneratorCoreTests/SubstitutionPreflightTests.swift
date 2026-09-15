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
                      focus: String? = nil, priority: Bool = false, dayCount: Int = 1) -> ClaudeService.ProgramBlueprint {
        let allocations: [ClaudeService.BlueprintPriorityAllocation] = priority ? [
            .init(area: "Rear Deltoids", priorityLevel: "High", rationale: "", targetFrequency: 1,
                targetExerciseSlots: 1, directSetTarget: 6, weightedStimulusTarget: 6,
                maxPerSessionDirectSets: 6, maxFocusSessionDirectSets: 6, preferredStyles: ["Pull"],
                preferredMovementPatterns: [], volumeBias: "Moderate", directWorkBias: "High")
        ] : []
        return .init(evidenceVersion: "test", splitRecommendation: style, weeklyTrainingDays: rest ? 0 : dayCount,
            priorityAllocations: allocations, dayPlans: (1...dayCount).map { day in
                .init(dayIndex: day, style: style, focusArea: focus, supportAreas: [], targetFatigueCap: 48,
                    targetSessionMinutes: 75, targetPrioritySlots: 1, emphasisPatterns: [], isRestDay: rest)
            }, topLeverageChange: "", posturalFocus: "(none)", injuryRiskFocus: injury,
            programmingNotes: [], calibration: service.neutralCalibrationProfile())
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

    func testShapeScopeAndExplicitLockContextFailClosed() {
        let base = baseline, proposal = candidate(baseline)
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
            XCTAssertEqual(check(proposal, base, blueprint: plan(style: "Pull", focus: focus, priority: priority)),
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
}
