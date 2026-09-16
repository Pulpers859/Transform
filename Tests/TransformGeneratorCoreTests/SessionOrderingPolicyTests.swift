import XCTest
@testable import Transform

/// Main-lift-first is a programming default, not a claim that all multi-joint movements
/// belong first or that every hypertrophy session must use this order. These fixtures test
/// ordering only; they do not claim complete-week budget admission or workout quality.
@MainActor
final class SessionOrderingPolicyTests: XCTestCase {
    private let service = ClaudeService.shared
    private typealias Exercise = (name: String, target: String)

    private func focus(_ area: String) -> ClaudeService.MusclePriorityIntent {
        .init(area: area, priorityLevel: "High", rank: 0, rationale: "test", weeklyDayTarget: 1,
            weeklyExerciseTarget: 2, weeklyDirectSetTarget: 6, weeklyStimulusTarget: 6,
            preferredStyles: [], preferredMovementPatterns: [], coverageKeywords: [],
            accessoryCatalog: [], volumeBias: "Moderate", directWorkBias: "Direct emphasis")
    }

    private func arranged(_ items: [Exercise], lock: Int = 0, focusArea: String? = nil) -> [String] {
        service.arrangeProceduralSelection(items, lockedPrefixCount: lock,
            focusIntent: focusArea.map { focus($0) }).map(\.name)
    }

    private func isMain(_ item: Exercise) -> Bool {
        service.isSessionMainLift(role: service.proceduralExerciseRole(for: item.name, muscleTarget: item.target),
            movementPattern: service.exerciseMetadata(forExerciseName: item.name, muscleTarget: item.target).movementPattern)
    }

    func testMachineInclinePressPrecedesFocusedLateralRaiseWithoutAnAnchor() {
        let press: Exercise = ("Machine Incline Press", "Upper Chest")
        XCTAssertEqual(service.proceduralExerciseRole(for: press.name, muscleTarget: press.target), .secondary)
        XCTAssertEqual(arranged([("Cable Lateral Raise", "Lateral Deltoids"), press], focusArea: "Lateral Deltoids"),
            [press.name, "Cable Lateral Raise"])
    }

    func testLegPressPrecedesFocusedKneeRaiseWithoutAnAnchor() {
        let press: Exercise = ("Leg Press", "Quads")
        XCTAssertEqual(service.proceduralExerciseRole(for: press.name, muscleTarget: press.target), .secondary)
        XCTAssertEqual(arranged([("Hanging Knee Raise", "Lower Abs"), press], focusArea: "Core/Abs"),
            [press.name, "Hanging Knee Raise"])
    }

    func testSecondaryCatalogFamiliesRequireAnExplicitOrderingDecision() {
        let mainFamilies: Set<String> = ["Horizontal Press", "Incline Press", "Vertical Press", "Landmine Press",
            "Close-Grip Press", "Dip", "Row", "Upright Row", "Vertical Pull", "Press", "Squat",
            "Split Squat", "Lunge", "Hinge", "Hip Thrust"]
        let accessoryFamilies: Set<String> = ["Curl", "Carry"]
        let secondary = service.exerciseMetadataEntries.filter {
            service.proceduralExerciseRole(for: $0.canonicalName, muscleTarget: $0.primaryAreas.joined(separator: "/")) == .secondary
        }
        XCTAssertEqual(Set(secondary.map(\.movementPattern)), mainFamilies.union(accessoryFamilies),
            "A new secondary family needs an explicit main-lift/accessory policy review")
        for entry in secondary {
            XCTAssertEqual(service.isSessionMainLift(role: .secondary, movementPattern: entry.movementPattern),
                mainFamilies.contains(entry.movementPattern), entry.canonicalName)
        }
        XCTAssertFalse(service.isSessionMainLift(role: .secondary, movementPattern: "Pull"), "Ambiguous inferred family")
        XCTAssertFalse(service.isSessionMainLift(role: .secondary, movementPattern: "Glute"), "Ambiguous inferred family")
        XCTAssertFalse(service.isSessionMainLift(role: .secondary, movementPattern: "Pressdown"), "No substring promotion")
        XCTAssertFalse(service.isSessionMainLift(role: .secondary, movementPattern: "Unknown"))
    }

    func testSecondaryNordicAndCarriesDoNotBecomeMainLifts() {
        for item: Exercise in [("Nordic Hamstring Curl", "Hamstrings"), ("Glute-Ham Raise", "Hamstrings"),
                               ("Dumbbell Suitcase Carry", "Obliques")] {
            XCTAssertEqual(service.proceduralExerciseRole(for: item.name, muscleTarget: item.target), .secondary)
            XCTAssertFalse(isMain(item), item.name)
        }
        XCTAssertEqual(arranged([("Nordic Hamstring Curl", "Hamstrings"), ("Leg Press", "Quads")], focusArea: "Hamstrings"),
            ["Leg Press", "Nordic Hamstring Curl"])
    }

    func testLowFatigueSupportRemainsAccessoryEvenWithCompoundLikePatterns() {
        for item: Exercise in [("Sissy Squat", "Quads"), ("Cable Pull-Through", "Glutes"),
                               ("Chest-Supported Rear Delt Row", "Rear Deltoids")] {
            XCTAssertEqual(service.proceduralExerciseRole(for: item.name, muscleTarget: item.target), .accessory)
            XCTAssertFalse(isMain(item), item.name)
        }
        XCTAssertFalse(service.isSessionMainLift(role: .accessory, movementPattern: "Row"))
    }

    func testSplitSquatDipLungeAndHipThrustAreMainLifts() {
        for item: Exercise in [("Dumbbell Bulgarian Split Squat", "Quads/Glutes"),
                               ("Dip (Assisted or Weighted)", "Chest"), ("Dumbbell Walking Lunge", "Quads/Glutes"),
                               ("Barbell Hip Thrust", "Glutes")] {
            XCTAssertTrue(isMain(item), item.name)
            XCTAssertEqual(arranged([("Cable Crunch", "Abs"), item], focusArea: "Core/Abs"),
                [item.name, "Cable Crunch"])
        }
    }

    func testCoreMayLeadOnlyAccessorySession() {
        XCTAssertEqual(arranged([("Machine Lateral Raise", "Lateral Deltoids"), ("Cable Crunch", "Abs")],
            focusArea: "Core/Abs"), ["Cable Crunch", "Machine Lateral Raise"])
        XCTAssertEqual(arranged([("Cable Crunch", "Abs"), ("Machine Lateral Raise", "Lateral Deltoids")],
            focusArea: "Lateral Deltoids"), ["Machine Lateral Raise", "Cable Crunch"],
            "No main lift permits core focus first; it does not force core ahead of a different focus")
    }

    func testFocusStillOrdersWithinMainLiftAndAccessoryBands() {
        XCTAssertEqual(arranged([("Machine Chest Press", "Chest"), ("Machine Incline Press", "Upper Chest"),
                                 ("Cable Lateral Raise", "Lateral Deltoids"), ("Low-Incline Cable Fly", "Upper Chest")],
            focusArea: "Upper Chest"),
            ["Machine Incline Press", "Machine Chest Press", "Low-Incline Cable Fly", "Cable Lateral Raise"])
    }

    func testAnchorsLeadOtherMainLiftsAndEqualKeysRetainInputOrder() {
        XCTAssertEqual(arranged([("Machine Incline Press", "Upper Chest"), ("Back Squat", "Quads")],
            focusArea: "Upper Chest"), ["Back Squat", "Machine Incline Press"])
        let equal: [Exercise] = [("Seated Cable Row", "Mid Back"), ("Machine Row", "Mid Back")]
        XCTAssertEqual(arranged(equal), equal.map(\.name))
        XCTAssertEqual(arranged(Array(equal.reversed())), Array(equal.reversed()).map(\.name))
    }

    func testLockedMainLiftControlsCorePositionInTail() {
        XCTAssertEqual(arranged([("Leg Press", "Quads"), ("Cable Crunch", "Abs"),
                                 ("Cable Lateral Raise", "Lateral Deltoids")], lock: 1, focusArea: "Core/Abs"),
            ["Leg Press", "Cable Lateral Raise", "Cable Crunch"])
    }

    func testUnusualLockedCorePrefixWinsAndLockIsClamped() {
        let items: [Exercise] = [("Cable Crunch", "Abs"), ("Cable Lateral Raise", "Lateral Deltoids"),
                                 ("Leg Press", "Quads")]
        XCTAssertEqual(arranged(items, lock: 1, focusArea: "Core/Abs"),
            ["Cable Crunch", "Leg Press", "Cable Lateral Raise"])
        XCTAssertEqual(arranged(items, lock: 99), items.map(\.name))
        XCTAssertEqual(arranged(items, lock: -1), arranged(items))
    }

    func testFinalReorderPreservesCompleteEntriesAndIsIdempotent() {
        let intent = ClaudeService.TrainingIntentPlan(splitRecommendation: "Upper", weeklyTrainingDays: 1,
            programmingNotes: [], priorities: [focus("Core/Abs")], topLeverageChange: "", posturalFocus: "",
            injuryRiskFocus: "", calibration: service.neutralCalibrationProfile())
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "test", splitRecommendation: "Upper",
            weeklyTrainingDays: 1, priorityAllocations: [], dayPlans: [
                .init(dayIndex: 1, style: "Upper", focusArea: "Core/Abs", supportAreas: [], targetFatigueCap: 48,
                    targetSessionMinutes: 75, targetPrioritySlots: 1, emphasisPatterns: [], isRestDay: false)
            ], topLeverageChange: "", posturalFocus: "", injuryRiskFocus: "", programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        let items: [Exercise] = [("Cable Crunch", "Abs"), ("Cable Lateral Raise", "Lateral Deltoids"),
                                 ("Machine Incline Press", "Upper Chest")]
        let entries = items.enumerated().map { index, item in
            ClaudeService.PreSelectedExercise(exerciseName: item.name, muscleTarget: item.target,
                movementPattern: service.exerciseMetadata(forExerciseName: item.name, muscleTarget: item.target).movementPattern,
                role: service.proceduralExerciseRole(for: item.name, muscleTarget: item.target), prescribedSets: index + 2)
        }
        for lock in [0, 1] {
            let ordered = service.reorderedMenusForSessionFlow([entries], blueprint: blueprint,
                trainingIntent: intent, lockedPrefixCounts: [lock])
            XCTAssertEqual(ordered[0].map(\.exerciseName), lock == 0
                ? ["Machine Incline Press", "Cable Lateral Raise", "Cable Crunch"]
                : ["Cable Crunch", "Machine Incline Press", "Cable Lateral Raise"])
            XCTAssertEqual(ordered[0].count, entries.count)
            for entry in ordered[0] {
                guard let original = entries.first(where: { $0.exerciseName == entry.exerciseName }) else {
                    return XCTFail("Unexpected identity")
                }
                XCTAssertEqual(entry.muscleTarget, original.muscleTarget)
                XCTAssertEqual(entry.movementPattern, original.movementPattern)
                XCTAssertEqual(entry.role, original.role)
                XCTAssertEqual(entry.prescribedSets, original.prescribedSets)
            }
            let twice = service.reorderedMenusForSessionFlow(ordered, blueprint: blueprint,
                trainingIntent: intent, lockedPrefixCounts: [lock])
            XCTAssertEqual(twice[0].map(\.exerciseName), ordered[0].map(\.exerciseName))
            XCTAssertEqual(twice[0].map(\.prescribedSets), ordered[0].map(\.prescribedSets))
        }
    }
}
