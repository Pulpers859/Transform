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
    private func blueprint(_ areas: [String] = [], slots: Int = 2, frequency: Int = 2,
        directTarget: Double = 8, weightedTarget: Double = 10, focusCap: Double = 6,
        focusDay: Int = 0, injuryRiskFocus: String = "") -> ClaudeService.ProgramBlueprint {
        .init(evidenceVersion: "projection-test", splitRecommendation: "Upper / Lower", weeklyTrainingDays: 2,
            priorityAllocations: areas.map { area in
                .init(area: area, priorityLevel: "High", rationale: "", targetFrequency: frequency,
                    targetExerciseSlots: slots, directSetTarget: directTarget, weightedStimulusTarget: weightedTarget,
                    maxPerSessionDirectSets: 4, maxFocusSessionDirectSets: focusCap,
                    preferredStyles: [], preferredMovementPatterns: [], volumeBias: "High", directWorkBias: "High")
            }, dayPlans: (0..<7).map { day in
                .init(dayIndex: day + 1, style: day == 0 || day == 3 ? "Upper" : "Rest",
                    focusArea: day == focusDay ? areas.first : nil, supportAreas: [],
                    targetFatigueCap: day == 0 || day == 3 ? 48 : 0,
                    targetSessionMinutes: 60, targetPrioritySlots: 0, emphasisPatterns: [],
                    isRestDay: day != 0 && day != 3)
            }, topLeverageChange: "", posturalFocus: "", injuryRiskFocus: injuryRiskFocus, programmingNotes: [],
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
            + value.weightedGoals.map { "goal:\($0.name)|\($0.coefficients)|\($0.limit)" }
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
                let goal = try XCTUnwrap(projected.weightedGoals.first { $0.name == "\(allocation.area) weighted target" })
                XCTAssertEqual(goal.coefficients[index], credit.weightedStimulus, accuracy: 0.000001)
                XCTAssertEqual(goal.limit, allocation.weightedStimulusTarget)
                XCTAssertFalse(projected.problem.lowerBounds.contains { $0.name == goal.name })
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

    func testExpandedOptionalLocationDoesNotInventAnotherBaselineExposure() throws {
        var baseline = menus
        for day in [0, 3] { for slot in baseline[day].indices { baseline[day][slot].prescribedSets = 3 } }
        baseline[3][4] = item("Seated Calf Raise", "Calves", sets: 3)
        var pool = baseline
        pool[0].append(item("Seated Calf Raise", "Calves"))
        let aliases = service.normalizedGroupAliases(forSeed: "calf")
        XCTAssertTrue(service.exerciseDirectlyTargets(groupAliases: aliases,
            exerciseName: "Seated Calf Raise", muscleTarget: "Calves"))
        let preserved = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: baseline))
        let calves = try XCTUnwrap(preserved.problem.coverage.first { $0.name == "Calves baseline days" })
        XCTAssertEqual(calves.minimumGroups, 1)
        XCTAssertEqual(calves.groups.count, 2, "Both candidate locations remain available")
        XCTAssertEqual(Set(calves.groups.flatMap { $0 }.map { preserved.options[$0].day }), Set([0, 3]))
        let hamstrings = try XCTUnwrap(preserved.problem.coverage.first { $0.name == "Hamstrings baseline days" })
        XCTAssertEqual(hamstrings.minimumGroups, 2, "An original two-day obligation remains intact")
        let unpreserved = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: required))
        XCTAssertEqual(try XCTUnwrap(unpreserved.problem.coverage.first { $0.name == "Calves baseline days" }).minimumGroups, 2)

        // Isolate only calf choices and the exposure requirement, not full workout admission.
        let sourceDomains = preserved.problem.domains.filter { domain in
            let option = preserved.options[domain[0]]
            return pool[option.day][option.slot].exerciseName == "Seated Calf Raise"
        }
        XCTAssertEqual(sourceDomains.count, 2)
        let optionIDs = sourceDomains.flatMap { $0 }
        let remap = Dictionary(uniqueKeysWithValues: optionIDs.enumerated().map { ($0.element, $0.offset) })
        let domains = sourceDomains.map { $0.compactMap { remap[$0] } }
        let appearances = optionIDs.map { preserved.options[$0].sets > 0 ? 1.0 : 0.0 }
        let groups = calves.groups.map { $0.compactMap { remap[$0] } }
        for wantedDay in [0, 3] {
            let location = optionIDs.map { preserved.options[$0].day == wantedDay && preserved.options[$0].sets > 0 ? 1.0 : 0.0 }
            let sliced = WorkoutAppearancePlanner.ChoiceProblem(domains: domains,
                upperBounds: [.init(name: "one appearance", coefficients: appearances, limit: 1)],
                lowerBounds: [.init(name: "chosen location", coefficients: location, limit: 1)],
                coverage: [.init(name: calves.name, groups: groups, minimumGroups: calves.minimumGroups)])
            guard case .admitted(let selected) = WorkoutAppearancePlanner.solveChoices(sliced) else {
                return XCTFail("Either location alone should satisfy the original one-day exposure")
            }
            XCTAssertEqual(selected.reduce(0.0) { $0 + appearances[$1] }, 1)
            XCTAssertEqual(selected.reduce(0.0) { $0 + location[$1] }, 1)
        }
    }

    func testSingleBaselineAppearanceTreatsCopiesAsAlternateLocations() throws {
        var baseline = menus
        for day in [0, 3] { for slot in baseline[day].indices { baseline[day][slot].prescribedSets = 3 } }
        baseline[3][4] = item("Seated Calf Raise", "Calves", sets: 3)
        var pool = baseline
        pool[0].append(item("Seated Calf Raise", "Calves"))
        let separate = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: baseline))
        let grouped = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: baseline,
            groupSingleAppearanceAlternatives: true))
        XCTAssertEqual(grouped.problem.domains.count, separate.problem.domains.count - 1)
        let calfDomains = grouped.problem.domains.filter { domain in
            let first = grouped.options[domain[0]]
            return pool[first.day][first.slot].exerciseName == "Seated Calf Raise"
        }
        let domain = try XCTUnwrap(calfDomains.first)
        XCTAssertEqual(calfDomains.count, 1)
        XCTAssertEqual(Set(domain.filter { grouped.options[$0].sets > 0 }.map { grouped.options[$0].day }), Set([0, 3]))
        XCTAssertEqual(domain.filter { grouped.options[$0].sets == 0 }.count, 1)
        let calfCoverage = try XCTUnwrap(grouped.problem.coverage.first { $0.name == "Calves baseline days" })
        XCTAssertEqual(calfCoverage.minimumGroups, 1)

        let remap = Dictionary(uniqueKeysWithValues: domain.enumerated().map { ($0.element, $0.offset) })
        let locations = calfCoverage.groups.map { $0.compactMap { remap[$0] } }
        for wantedDay in [0, 3] {
            let coefficients = domain.map { grouped.options[$0].day == wantedDay && grouped.options[$0].sets > 0 ? 1.0 : 0.0 }
            let sliced = WorkoutAppearancePlanner.ChoiceProblem(domains: [Array(domain.indices)],
                upperBounds: [], lowerBounds: [.init(name: "chosen location", coefficients: coefficients, limit: 1)],
                coverage: [.init(name: calfCoverage.name, groups: locations, minimumGroups: 1)])
            guard case .admitted(let picks) = WorkoutAppearancePlanner.solveChoices(sliced) else {
                return XCTFail("Either single-appearance location must remain selectable")
            }
            XCTAssertEqual(picks.reduce(0.0) { $0 + coefficients[$1] }, 1)
        }

        var retained = required
        retained[3].insert(ExerciseWeightEntry.canonicalLookupKey("Seated Calf Raise"))
        let protected = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: blueprint(),
            weekNumber: 1, requiredKeysByDay: retained, preservingDoseOf: baseline,
            groupSingleAppearanceAlternatives: true))
        XCTAssertEqual(protected.problem.domains.count, separate.problem.domains.count,
            "Actual retained work cannot become a relocatable choice")
    }

    func testReportedSymptomGuardRejectsIncreasedAndNewImplicatedWork() throws {
        var baseline = menus
        for day in [0, 3] { for slot in baseline[day].indices { baseline[day][slot].prescribedSets = 3 } }
        var pool = baseline
        pool[0].append(item("Seated Calf Raise", "Calves"))
        let plan = blueprint(injuryRiskFocus: "Lower back pain with lumbar extension.")
        XCTAssertTrue(service.reportedJointPainImplicates(.lowerBack,
            exerciseName: "Incline Barbell Press", muscleTarget: "Upper Chest",
            injuryRiskFocus: plan.injuryRiskFocus))
        XCTAssertNil(service.jointDoseProjection(for: pool, blueprint: plan, weekNumber: 1,
            requiredKeysByDay: required, avoidReportedSymptomEscalation: true),
            "A symptom limit needs a real funded baseline")
        let guarded = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: baseline,
            avoidReportedSymptomEscalation: true))
        let bound = try XCTUnwrap(guarded.problem.upperBounds.first {
            $0.name == "No new or increased work implicated by reported symptoms"
        })
        func cost(_ day: Int, _ slot: Int, _ sets: Int) throws -> Double {
            let index = try XCTUnwrap(guarded.options.firstIndex {
                $0.day == day && $0.slot == slot && $0.sets == sets
            })
            return bound.coefficients[index]
        }
        XCTAssertEqual(try cost(0, 0, 4), 1, "An increase to an implicated lift is excluded")
        XCTAssertEqual(try cost(0, 0, 3), 0, "Existing baseline dose stays available")
        XCTAssertEqual(try cost(0, 5, 3), 1, "New implicated work is excluded")
        XCTAssertEqual(try cost(0, 5, 0), 0, "Omission remains available")
        XCTAssertEqual(bound.limit, 0)
        let inclineChoices = guarded.options.indices.filter {
            guarded.options[$0].day == 0 && guarded.options[$0].slot == 0
                && [3, 4].contains(guarded.options[$0].sets)
        }
        XCTAssertEqual(inclineChoices.count, 2)
        let isolated = WorkoutAppearancePlanner.ChoiceProblem(domains: [Array(inclineChoices.indices)],
            upperBounds: [.init(name: bound.name,
                coefficients: inclineChoices.map { bound.coefficients[$0] }, limit: bound.limit)],
            lowerBounds: [])
        guard case .admitted(let selected) = WorkoutAppearancePlanner.solveChoices(isolated) else {
            return XCTFail("The existing dose must remain selectable when an increase is guarded")
        }
        XCTAssertEqual(guarded.options[inclineChoices[try XCTUnwrap(selected.first)]].sets, 3)
        let unguarded = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: required, preservingDoseOf: baseline))
        XCTAssertFalse(unguarded.problem.upperBounds.contains { $0.name == bound.name })
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
        let weighted = try XCTUnwrap(projection.weightedGoals.first { $0.name == "Triceps weighted target" })
        let frequency = try XCTUnwrap(projection.problem.thresholdCoverage.first { $0.name == "Triceps meaningful days" })
        XCTAssertEqual(direct.limit, allocation.directSetTarget - WorkoutSetBudgetPolicy.fundingTolerance)
        XCTAssertEqual(weighted.limit, allocation.weightedStimulusTarget)
        XCTAssertFalse(projection.problem.lowerBounds.contains { $0.name == weighted.name })
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

    func testUnattainableCalfWeightedGoalDoesNotInvalidateHardDoseFeasibility() throws {
        let upper = [item("Incline Barbell Press", "Upper Chest"), item("Chest-Supported Row", "Upper Back"),
            item("Machine Shoulder Press", "Deltoids"), item("Rope Triceps Pressdown", "Triceps"),
            item("EZ-Bar Curl", "Biceps"), item("Cable Crunch", "Abs")]
        let lower = [item("Back Squat", "Quads"), item("Barbell Romanian Deadlift", "Hamstrings"),
            item("Barbell Hip Thrust", "Glutes"), item("Machine Leg Curl", "Hamstrings"),
            item("Seated Calf Raise", "Calves"), item("Cable Crunch", "Abs")]
        let pool = [upper, [], [], lower, [], [], []]
        let keys = pool.map { Set($0.map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) }) }
        let plan = blueprint(["Calves"], slots: 1, frequency: 1, directTarget: 3, weightedTarget: 4.5, focusCap: 4, focusDay: 3)
        for group in service.majorMuscleGroups {
            XCTAssertTrue(pool.joined().contains {
                service.exerciseDirectlyTargets(groupAliases: service.normalizedGroupAliases(forSeed: group.seed),
                    exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget)
            }, "Fixture must actually cover \(group.label) directly")
        }
        let projection = try XCTUnwrap(service.jointDoseProjection(for: pool, blueprint: plan,
            weekNumber: 1, requiredKeysByDay: keys))
        let goal = try XCTUnwrap(projection.weightedGoals.first { $0.name == "Calves weighted target" })
        XCTAssertEqual(goal.limit, 4.5)
        XCTAssertEqual(plan.priorityAllocations[0].directSetTarget, 3)
        XCTAssertFalse(projection.problem.lowerBounds.contains { $0.name == goal.name })
        guard case .admitted(let choices) = WorkoutAppearancePlanner.solveChoices(projection.problem, maximumStates: 4096) else {
            return XCTFail("This fixed-identity pool should fund hard constraints without the bonus goal")
        }
        let direct = try XCTUnwrap(projection.problem.lowerBounds.first { $0.name == "Calves direct target" })
        XCTAssertEqual(choices.reduce(0.0) { $0 + direct.coefficients[$1] }, 3)
        XCTAssertEqual(choices.reduce(0.0) { $0 + goal.coefficients[$1] }, 3)
        let overconstrained = WorkoutAppearancePlanner.ChoiceProblem(domains: projection.problem.domains,
            upperBounds: projection.problem.upperBounds, lowerBounds: projection.problem.lowerBounds + [goal],
            coverage: projection.problem.coverage, thresholdCoverage: projection.problem.thresholdCoverage)
        guard case .infeasible = WorkoutAppearancePlanner.solveChoices(overconstrained, maximumStates: 4096) else {
            return XCTFail("The calf-only credit source cannot reach 4.5 without exceeding its three-set weekly budget")
        }
    }
}
