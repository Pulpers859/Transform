import XCTest
@testable import Transform

@MainActor
final class JointDoseProjectionTests: XCTestCase {
    private let service = ClaudeService.shared
    private func item(_ name: String, _ target: String, sets: Int = 1) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
            movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
            role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: sets)
    }
    private var menus: [[ClaudeService.PreSelectedExercise]] {
        let day = [item("Incline Barbell Press", "Upper Chest"), item("Rope Triceps Pressdown", "Triceps"),
            item("Cable Lateral Raise", "Lateral Deltoids"), item("Machine Leg Curl", "Hamstrings"),
            item("Cable Crunch", "Abs")]
        return [day, [], [], day, [], [], []]
    }
    private var required: [Set<String>] { Array(repeating: Set<String>(), count: 7) }
    private func blueprint(_ areas: [String] = [], slots: Int = 2) -> ClaudeService.ProgramBlueprint {
        .init(evidenceVersion: "projection-test", splitRecommendation: "Upper / Lower", weeklyTrainingDays: 2,
            priorityAllocations: areas.map { area in
                .init(area: area, priorityLevel: "High", rationale: "", targetFrequency: 2,
                    targetExerciseSlots: slots, directSetTarget: 8, weightedStimulusTarget: 10,
                    maxPerSessionDirectSets: 4, maxFocusSessionDirectSets: 6,
                    preferredStyles: [], preferredMovementPatterns: [], volumeBias: "High", directWorkBias: "High")
            }, dayPlans: (0..<7).map { day in
                .init(dayIndex: day + 1, style: day == 0 || day == 3 ? "Upper" : "Rest",
                    focusArea: day == 0 ? areas.first : nil, supportAreas: [],
                    targetFatigueCap: day == 0 || day == 3 ? 48 : 0,
                    targetSessionMinutes: 60, targetPrioritySlots: 0, emphasisPatterns: [],
                    isRestDay: day != 0 && day != 3)
            }, topLeverageChange: "", posturalFocus: "", injuryRiskFocus: "", programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
    }
    private func response(_ item: ClaudeService.PreSelectedExercise, sets: Int) -> WorkoutExerciseResponse {
        .init(exerciseName: item.exerciseName, sets: sets, reps: "", tempo: "", restSeconds: 0,
            notes: "", muscleTarget: item.muscleTarget)
    }
    private func snapshot(_ value: ClaudeService.JointDoseProjection) -> [String] {
        value.slotCapacityShortfalls + value.options.map { "\($0.day)|\($0.slot)|\($0.sets)" }
            + value.problem.domains.map { "domain:\($0)" }
            + value.problem.upperBounds.map { "upper:\($0.name)|\($0.coefficients)|\($0.limit)" }
            + value.problem.lowerBounds.map { "lower:\($0.name)|\($0.coefficients)|\($0.limit)" }
            + value.problem.coverage.map { "coverage:\($0.name)|\($0.groups)|\($0.minimumGroups)" }
            + value.problem.thresholdCoverage.flatMap { requirement in
                ["threshold:\(requirement.name)|\(requirement.minimumGroups)"]
                    + requirement.groups.map { "\($0.name)|\($0.coefficients)|\($0.limit)" }
            }
    }

    func testDomainsMapEachLocationAndRequiredIdentityExcludesOnlyItsOmission() throws {
        var keys = required
        keys[0].insert(ExerciseWeightEntry.canonicalLookupKey("Rope Triceps Pressdown"))
        let projected = try XCTUnwrap(service.jointDoseProjection(for: menus, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: keys))
        XCTAssertEqual(projected.problem.domains.count, 10)
        XCTAssertEqual(projected.problem.domains.flatMap { $0 }, Array(projected.options.indices))
        let locations = menus.indices.flatMap { day in menus[day].indices.map { (day, $0) } }
        for (domain, location) in zip(projected.problem.domains, locations) {
            XCTAssertTrue(domain.allSatisfy { projected.options[$0].day == location.0 && projected.options[$0].slot == location.1 })
            let doses = domain.map { projected.options[$0].sets }
            XCTAssertEqual(doses.contains(0), !(location.0 == 0 && location.1 == 1))
        }
        XCTAssertEqual(projected.problem.domains[0].map { projected.options[$0].sets }, [4, 3, 0])
        XCTAssertEqual(projected.problem.domains[1].map { projected.options[$0].sets }, [3, 2])
        XCTAssertEqual(projected.problem.domains[6].map { projected.options[$0].sets }, [3, 2, 0])
    }

    func testPlaceholderSetsIncludingIntMaxDoNotAffectProjection() throws {
        let original = try XCTUnwrap(service.jointDoseProjection(for: menus, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: required))
        for placeholder in [Int.max, Int.min, 0, 99] {
            var changed = menus
            for day in changed.indices { for slot in changed[day].indices { changed[day][slot].prescribedSets = placeholder } }
            let result = try XCTUnwrap(service.jointDoseProjection(for: changed, blueprint: blueprint(),
                weekNumber: 1, requiredKeysByDay: required))
            XCTAssertEqual(snapshot(result), snapshot(original))
            XCTAssertEqual(changed[0][0].prescribedSets, placeholder)
        }
    }

    func testPhaseAndPrimePriorityDetermineMeaningfulOptionBounds() throws {
        for week in [1, 2, 3] {
            for areas in [[], ["Triceps"]] {
                let projected = try XCTUnwrap(service.jointDoseProjection(for: menus, blueprint: blueprint(areas),
                    weekNumber: week, requiredKeysByDay: required))
                for domain in projected.problem.domains {
                    let first = projected.options[domain[0]], exercise = menus[first.day][first.slot]
                    let prime = areas.contains { service.focusStimulusKind(exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget, focusArea: $0) == .prime }
                    let ceiling = max(service.proceduralSets(for: week, exerciseName: exercise.exerciseName,
                        muscleTarget: exercise.muscleTarget), prime ? 4 : 0)
                    let floor = service.minimumSetFloor(for: response(exercise, sets: 1))
                    XCTAssertEqual(domain.map { projected.options[$0].sets }, Array(stride(from: ceiling, through: floor, by: -1)) + [0])
                }
            }
        }
    }

    func testProjectedCoefficientsMatchCanonicalCreditFatigueAndMembershipAPIs() throws {
        let plan = blueprint(["Triceps", "Lateral Deltoids"])
        let projected = try XCTUnwrap(service.jointDoseProjection(for: menus, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: required))
        func bound(_ name: String, upper: Bool) throws -> WorkoutAppearancePlanner.Constraint {
            try XCTUnwrap((upper ? projected.problem.upperBounds : projected.problem.lowerBounds).first { $0.name == name }, name)
        }
        for (index, option) in projected.options.enumerated() {
            let exercise = menus[option.day][option.slot]
            let output = response(exercise, sets: option.sets)
            for allocation in plan.priorityAllocations {
                let credit = service.stimulusCredit(for: output, area: allocation.area)
                XCTAssertEqual(try bound("\(allocation.area) direct target", upper: false).coefficients[index], credit.directSets, accuracy: 0.000001)
                XCTAssertEqual(try bound("\(allocation.area) weighted target", upper: false).coefficients[index], credit.weightedStimulus, accuracy: 0.000001)
                XCTAssertEqual(try bound("\(allocation.area) weekly ceiling", upper: true).coefficients[index], credit.directSets, accuracy: 0.000001)
                for day in [0, 3] {
                    let session = try bound("Day \(day + 1) \(allocation.area) ceiling", upper: true)
                    XCTAssertEqual(session.coefficients[index], option.day == day ? credit.directSets : 0, accuracy: 0.000001)
                    let expected = service.allowedPerSessionDirectSetCap(for: allocation, dayNumber: day + 1, blueprint: plan, dayStart: 1)
                    XCTAssertEqual(session.limit, expected + WorkoutSetBudgetPolicy.fundingTolerance, accuracy: 0.000001)
                }
            }
            for day in [0, 3] {
                let fatigue = try bound("Day \(day + 1) fatigue", upper: true)
                XCTAssertEqual(fatigue.coefficients[index], option.day == day && option.sets > 0 ? Double(service.estimatedDayFatigue(for: [output])) : 0)
                XCTAssertEqual(fatigue.limit, Double(plan.dayPlans[day].targetFatigueCap))
            }
            for group in service.majorMuscleGroups {
                let aliases = service.normalizedGroupAliases(forSeed: group.seed)
                let debit = service.exerciseCountsTowardMaintenance(groupSeed: group.seed, groupAliases: aliases,
                    exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget, blueprint: plan)
                XCTAssertEqual(try bound("\(group.label) maintenance/residue ceiling", upper: true).coefficients[index], debit ? Double(option.sets) : 0)
                if !service.isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: plan) {
                    let direct = service.exerciseDirectlyTargets(groupAliases: aliases, exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
                    XCTAssertEqual(try bound("\(group.label) maintenance floor", upper: false).coefficients[index], direct ? Double(option.sets) : 0)
                }
            }
        }
    }

    func testMalformedShapeDuplicateUnknownAndMissingRequiredIdentityRefuse() {
        var duplicate = menus
        duplicate[0].append(duplicate[0][0])
        var unknown = menus
        unknown[0][0] = item("Uncatalogued Press", "Upper Chest")
        var restWork = menus
        restWork[1] = [item("Cable Crunch", "Abs")]
        for value in [duplicate, unknown, restWork, Array(menus.dropLast())] {
            XCTAssertNil(service.jointDoseProjection(for: value, blueprint: blueprint(), weekNumber: 1, requiredKeysByDay: required))
        }
        var missing = required
        missing[0].insert(ExerciseWeightEntry.canonicalLookupKey("Cable Fly"))
        XCTAssertNil(service.jointDoseProjection(for: menus, blueprint: blueprint(), weekNumber: 1, requiredKeysByDay: missing))
        XCTAssertNil(service.jointDoseProjection(for: menus, blueprint: blueprint(), weekNumber: 1, requiredKeysByDay: []))
        XCTAssertNil(service.jointDoseProjection(for: menus, blueprint: blueprint(), weekNumber: 4, requiredKeysByDay: required))
    }

    func testMeaningfulDayThresholdsUseCanonicalDailyDirectCredit() throws {
        let plan = blueprint(["Triceps", "Lateral Deltoids"])
        let projection = try XCTUnwrap(service.jointDoseProjection(for: menus, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: required))
        for allocation in plan.priorityAllocations {
            let requirement = try XCTUnwrap(projection.problem.thresholdCoverage.first {
                $0.name == "\(allocation.area) meaningful days"
            })
            XCTAssertEqual(requirement.minimumGroups, allocation.targetFrequency)
            XCTAssertEqual(requirement.groups.count, 7)
            for day in 0..<7 {
                let group = requirement.groups[day]
                XCTAssertEqual(group.limit, service.minimumMeaningfulPriorityExposureSets(for: allocation.area) - 0.01,
                    "The projection must not add the search solver's ordinary 0.001 tolerance")
                for (index, option) in projection.options.enumerated() {
                    let exercise = menus[option.day][option.slot]
                    let expected = option.day == day ? service.stimulusCredit(
                        for: response(exercise, sets: option.sets), area: allocation.area).directSets : 0
                    XCTAssertEqual(group.coefficients[index], expected, accuracy: 0.000001)
                }
            }
        }
    }

    func testBaselineExposureDoesNotInventASecondSuppliedCoreDay() throws {
        var pool = menus
        pool[3][4] = item("Seated Calf Raise", "Calves")
        let projection = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: required))
        let core = try XCTUnwrap(projection.problem.coverage.first { $0.name == "Core baseline days" })
        XCTAssertEqual(core.minimumGroups, 1)
        XCTAssertEqual(core.groups.count, 1)
        XCTAssertTrue(core.groups[0].allSatisfy {
            projection.options[$0].day == 0 && projection.options[$0].slot == 4 && projection.options[$0].sets > 0
        })
        let hamstrings = try XCTUnwrap(projection.problem.coverage.first { $0.name == "Hamstrings baseline days" })
        XCTAssertEqual(hamstrings.minimumGroups, 2)
        XCTAssertEqual(hamstrings.groups.count, 2)
    }

    func testUnfundableRawSlotRequestStaysVisibleWithoutReducingDoseOrFrequency() throws {
        let plan = blueprint(["Triceps"], slots: 8)
        let allocation = plan.priorityAllocations[0]
        let projection = try XCTUnwrap(service.jointDoseProjection(for: menus, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: required))
        let capacity = [0, 3].reduce(0) { $0 + service.fundablePrioritySlotsPerSession(
            for: allocation, isFocusDay: $1 == 0) }
        XCTAssertLessThan(capacity, allocation.targetExerciseSlots)
        let slots = try XCTUnwrap(projection.problem.lowerBounds.first { $0.name == "Triceps prime slots" })
        XCTAssertEqual(slots.limit, Double(capacity))
        XCTAssertEqual(projection.slotCapacityShortfalls,
            ["Triceps: requested 8 prime slots; existing placement capacity \(capacity)"])
        let direct = try XCTUnwrap(projection.problem.lowerBounds.first { $0.name == "Triceps direct target" })
        let weighted = try XCTUnwrap(projection.problem.lowerBounds.first { $0.name == "Triceps weighted target" })
        let frequency = try XCTUnwrap(projection.problem.thresholdCoverage.first { $0.name == "Triceps meaningful days" })
        XCTAssertEqual(direct.limit, allocation.directSetTarget - WorkoutSetBudgetPolicy.fundingTolerance)
        XCTAssertEqual(weighted.limit, allocation.weightedStimulusTarget - WorkoutSetBudgetPolicy.fundingTolerance)
        XCTAssertEqual(frequency.minimumGroups, allocation.targetFrequency)
    }

    func testPreservedDailyPriorityBoundsMatchCanonicalBaselineCredits() throws {
        let plan = blueprint(["Triceps", "Lateral Deltoids"])
        var baseline = menus
        for day in [0, 3] { for slot in baseline[day].indices { baseline[day][slot].prescribedSets = 3 } }
        let plain = try XCTUnwrap(service.jointDoseProjection(for: menus, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: required))
        let projected = try XCTUnwrap(service.jointDoseProjection(for: menus, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: baseline))
        for allocation in plan.priorityAllocations {
            for day in 0..<7 {
                let credits = baseline[day].map { service.stimulusCredit(for: response($0, sets: $0.prescribedSets), area: allocation.area) }
                for weighted in [false, true] {
                    let suffix = weighted ? "weighted" : "direct"
                    let bound = try XCTUnwrap(projected.problem.lowerBounds.first {
                        $0.name == "Day \(day + 1) \(allocation.area) baseline \(suffix)"
                    })
                    let expected = credits.reduce(0.0) { $0 + (weighted ? $1.weightedStimulus : $1.directSets) }
                    XCTAssertEqual(bound.limit, expected - 0.01, accuracy: 0.000001)
                    for (index, option) in projected.options.enumerated() {
                        let credit = service.stimulusCredit(for: response(menus[option.day][option.slot], sets: option.sets), area: allocation.area)
                        XCTAssertEqual(bound.coefficients[index], option.day == day ? (weighted ? credit.weightedStimulus : credit.directSets) : 0, accuracy: 0.000001)
                    }
                }
            }
        }
        XCTAssertEqual(projected.problem.lowerBounds.filter { $0.name.contains(" baseline weekly ") }.count,
            plan.priorityAllocations.count * 2)
        XCTAssertEqual(projected.problem.thresholdCoverage.filter { $0.name.hasSuffix(" baseline meaningful days") }.count,
            plan.priorityAllocations.count)
        for allocation in plan.priorityAllocations {
            let dailyCredits = baseline.map { day in
                day.map { service.stimulusCredit(for: response($0, sets: $0.prescribedSets), area: allocation.area) }
            }
            for weighted in [false, true] {
                let suffix = weighted ? "weighted" : "direct"
                let bound = try XCTUnwrap(projected.problem.lowerBounds.first {
                    $0.name == "\(allocation.area) baseline weekly \(suffix)"
                })
                let total = dailyCredits.joined().reduce(0.0) { $0 + (weighted ? $1.weightedStimulus : $1.directSets) }
                XCTAssertEqual(bound.limit, total - 0.01, accuracy: 0.000001)
                for (index, option) in projected.options.enumerated() {
                    let credit = service.stimulusCredit(for: response(menus[option.day][option.slot], sets: option.sets), area: allocation.area)
                    XCTAssertEqual(bound.coefficients[index], weighted ? credit.weightedStimulus : credit.directSets, accuracy: 0.000001)
                }
            }
            let threshold = service.minimumMeaningfulPriorityExposureSets(for: allocation.area)
            let meaningful = dailyCredits.filter { $0.reduce(0.0) { $0 + $1.directSets } + 0.01 >= threshold }.count
            let coverage = try XCTUnwrap(projected.problem.thresholdCoverage.first {
                $0.name == "\(allocation.area) baseline meaningful days"
            })
            XCTAssertEqual(coverage.minimumGroups, meaningful)
            XCTAssertEqual(coverage.groups.count, 7)
            for day in 0..<7 {
                XCTAssertEqual(coverage.groups[day].limit, threshold - 0.01)
                for (index, option) in projected.options.enumerated() {
                    let credit = service.stimulusCredit(for: response(menus[option.day][option.slot], sets: option.sets), area: allocation.area)
                    XCTAssertEqual(coverage.groups[day].coefficients[index], option.day == day ? credit.directSets : 0, accuracy: 0.000001)
                }
            }
        }
        // Preservation adds requirements; it must not rewrite ordinary targets or ceilings.
        for original in plain.problem.lowerBounds + plain.problem.upperBounds {
            let same = try XCTUnwrap((projected.problem.lowerBounds + projected.problem.upperBounds).first { $0.name == original.name })
            XCTAssertEqual(same.limit, original.limit)
            XCTAssertEqual(same.coefficients, original.coefficients)
        }
    }

    func testPreservedRegionsDistinguishUpperChestFromBroadMaintenanceChest() throws {
        var pool = menus
        for day in [0, 3] { pool[day].append(item("Cable Fly", "Chest", sets: 2)) }
        var baseline = pool
        for day in [0, 3] { baseline[day][0].prescribedSets = 3 }
        let plan = blueprint()
        let projected = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: baseline))
        let upperChest = try XCTUnwrap(projected.problem.lowerBounds.first { $0.name == "upper chest baseline region" })
        let chest = try XCTUnwrap(projected.problem.lowerBounds.first { $0.name == "chest baseline region" })
        XCTAssertEqual(upperChest.limit, 6)
        XCTAssertEqual(chest.limit, 4)
        let regions = Set(baseline.joined().flatMap {
            service.exerciseMetadata(forExerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget).primaryAreas.map(service.normalizedPriorityText)
        })
        XCTAssertEqual(projected.problem.lowerBounds.filter { $0.name.hasSuffix(" baseline region") }.count, regions.count)
        for region in regions {
            let bound = try XCTUnwrap(projected.problem.lowerBounds.first { $0.name == "\(region) baseline region" })
            func targets(_ item: ClaudeService.PreSelectedExercise) -> Bool {
                service.exerciseMetadata(forExerciseName: item.exerciseName, muscleTarget: item.muscleTarget)
                    .primaryAreas.map(service.normalizedPriorityText).contains(region)
            }
            XCTAssertEqual(bound.limit, Double(baseline.joined().filter(targets).reduce(0) { $0 + $1.prescribedSets }))
            for (index, option) in projected.options.enumerated() {
                XCTAssertEqual(bound.coefficients[index], targets(pool[option.day][option.slot]) ? Double(option.sets) : 0)
            }
        }
        for group in service.majorMuscleGroups {
            let aliases = service.normalizedGroupAliases(forSeed: group.seed)
            func targets(_ item: ClaudeService.PreSelectedExercise) -> Bool {
                service.exerciseDirectlyTargets(groupAliases: aliases, exerciseName: item.exerciseName, muscleTarget: item.muscleTarget)
            }
            let bound = try XCTUnwrap(projected.problem.lowerBounds.first { $0.name == "\(group.label) baseline maintenance" })
            XCTAssertEqual(bound.limit, Double(baseline.joined().filter(targets).reduce(0) { $0 + $1.prescribedSets }) - 0.01, accuracy: 0.000001)
            for (index, option) in projected.options.enumerated() {
                XCTAssertEqual(bound.coefficients[index], targets(pool[option.day][option.slot]) ? Double(option.sets) : 0)
            }
        }
    }

    func testDefaultProjectionDoesNotInferBaselineDoseFromPlaceholders() throws {
        var pool = menus
        pool[0][0].prescribedSets = Int.max
        let implicit = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: required))
        let explicit = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: nil))
        XCTAssertEqual(snapshot(implicit), snapshot(explicit))
        XCTAssertFalse(implicit.problem.lowerBounds.contains {
            $0.name.contains("baseline direct") || $0.name.contains("baseline weighted")
                || $0.name.hasSuffix("baseline region") || $0.name.hasSuffix("baseline maintenance")
        })
    }

    func testMalformedPreservedBaselineRefusesBeforeArithmetic() {
        var invalid: [[[ClaudeService.PreSelectedExercise]]] = [Array(menus.dropLast())]
        for sets in [Int.max, Int.min, -1, 0] {
            var baseline = menus
            baseline[0][0].prescribedSets = sets
            invalid.append(baseline)
        }
        var unknown = menus
        unknown[0][0] = item("Uncatalogued Press", "Upper Chest", sets: 3)
        invalid.append(unknown)
        var restWork = menus
        restWork[1] = [item("Cable Crunch", "Abs", sets: 2)]
        invalid.append(restWork)
        for baseline in invalid {
            XCTAssertNil(service.jointDoseProjection(for: menus, blueprint: blueprint(),
                weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: baseline))
        }
    }
}
