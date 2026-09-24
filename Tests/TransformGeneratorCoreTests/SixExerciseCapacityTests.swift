import Foundation
import XCTest
@testable import Transform

/// Compare guarded production capacity planning with independent complete-plan trials.
@MainActor
final class SixExerciseCapacityTests: XCTestCase {
    private let service = ClaudeService.shared

    func testCapacityProtectsShoulderRegionsRatherThanTheirCombinedTotal() {
        func funded(_ name: String, _ target: String, _ sets: Int) -> ClaudeService.PreSelectedExercise {
            var exercise = slot(name, target)
            exercise.prescribedSets = sets
            return exercise
        }
        let baseline = [[funded("Reverse Pec Deck", "Rear Deltoids", 2),
                         funded("Dumbbell Rear Delt Fly", "Rear Deltoids", 2)],
                        [funded("Cable Lateral Raise", "Lateral Deltoids", 3),
                         funded("Leaning Dumbbell Lateral Raise", "Lateral Deltoids", 3)]]
        let traded = [[funded("Reverse Pec Deck", "Rear Deltoids", 3)],
                      [funded("Cable Lateral Raise", "Lateral Deltoids", 4),
                       funded("Leaning Dumbbell Lateral Raise", "Lateral Deltoids", 3)]]
        XCTAssertEqual(service.capacityShoulderRegionLoss(traded, baseline: baseline),
            .init(region: "Rear deltoids", baselineSets: 4, candidateSets: 3))
        XCTAssertEqual(service.capacityShoulderRegionLoss(baseline, baseline: traded),
            .init(region: "Lateral deltoids", baselineSets: 7, candidateSets: 6))
        var consolidated = traded
        consolidated[0][0].prescribedSets = 4
        consolidated[1][0].prescribedSets = 3
        // Only regional accounting is tested here; role/fatigue limits still gate adoption.
        XCTAssertNil(service.capacityShoulderRegionLoss(consolidated, baseline: baseline))
        XCTAssertNil(service.capacityShoulderRegionLoss(Array(consolidated.reversed()), baseline: baseline))
        XCTAssertNil(service.capacityShoulderRegionLoss(baseline, baseline: baseline))
        XCTAssertNil(service.capacityShoulderRegionLoss([], baseline: []))
        // Display labels cannot hide loss of the exercise's primary metadata region.
        let press = [[funded("Machine Shoulder Press", "Deltoids", 3)]]
        let lateral = [[funded("Cable Lateral Raise", "Deltoids", 3)]]
        XCTAssertEqual(service.capacityShoulderRegionLoss(lateral, baseline: press),
            .init(region: "Anterior deltoids", baselineSets: 3, candidateSets: 0))
        XCTAssertNil(service.capacityShoulderRegionLoss(
            [[funded("Incline Barbell Press", "Upper Chest", 3), funded("Cable Fly", "Chest", 3)]],
            baseline: [[funded("Incline Barbell Press", "Upper Chest", 4), funded("Cable Fly", "Chest", 2)]]))
    }

    private func slot(_ name: String, _ target: String) -> ClaudeService.PreSelectedExercise {
        .init(exerciseName: name, muscleTarget: target,
            movementPattern: service.exerciseMetadata(forExerciseName: name, muscleTarget: target).movementPattern,
            role: service.proceduralExerciseRole(for: name, muscleTarget: target), prescribedSets: 1)
    }

    func testOptionalCapacityUsesTheSharedReservationAndRespectsProtectedSlots() {
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "capacity-control", splitRecommendation: "Upper",
            weeklyTrainingDays: 1, priorityAllocations: [], dayPlans: [
                .init(dayIndex: 1, style: "Upper", focusArea: nil, supportAreas: [], targetFatigueCap: 48,
                    targetSessionMinutes: 75, targetPrioritySlots: 0, emphasisPatterns: [], isRestDay: false)
            ], topLeverageChange: "", posturalFocus: "", injuryRiskFocus: "", programmingNotes: [],
            calibration: service.neutralCalibrationProfile())
        let menus = [[slot("EZ-Bar Curl", "Biceps"), slot("Incline Dumbbell Curl", "Biceps"),
            slot("Rope Triceps Pressdown", "Triceps"), slot("Machine Chest Press", "Chest"),
            slot("Seated Cable Row", "Mid Back"), slot("Cable Lateral Raise", "Lateral Deltoids"),
            slot("Cable Crunch", "Abs")]]
        let normal = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1)
        guard case .admitted = normal.outcome else { return XCTFail("Control must fit other budgets: \(normal.outcome)") }
        XCTAssertEqual(normal.menus[0].count, 7)
        let limited = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1,
            maximumExercisesPerDay: 6)
        guard case .admitted = limited.outcome else { return XCTFail("Redundant unprotected curl can fit: \(limited.outcome)") }
        XCTAssertEqual(limited.menus[0].count, 6)
        XCTAssertEqual(limited.menus[0].first?.exerciseName, menus[0].first?.exerciseName)
        XCTAssertEqual(Set(limited.menus[0].map(\.muscleTarget)), Set(menus[0].map(\.muscleTarget)))
        let protected = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1,
            lockedPrefixCounts: [7], maximumExercisesPerDay: 6)
        guard case .infeasible(let conflicts) = protected.outcome else {
            return XCTFail("Seven protected slots cannot fit six: \(protected.outcome)")
        }
        XCTAssertTrue(conflicts.contains("Day 1 exercise ceiling"))
        XCTAssertEqual(protected.menus[0].map(\.exerciseName), menus[0].map(\.exerciseName))
        let exhausted = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1,
            maximumStates: 0, maximumExercisesPerDay: 6)
        guard case .searchLimit = exhausted.outcome else { return XCTFail("No search is not infeasibility") }
        let belowFloor = service.reserveWeeklyAppearanceFloors(menus, blueprint: blueprint, weekNumber: 1,
            maximumExercisesPerDay: 4)
        guard case .infeasible = belowFloor.outcome else { return XCTFail("Ceiling cannot override floor five") }
    }

    // Exact synthetic persona definitions from UserJourneySimulationTests. Kept local so this
    // bounded diagnostic does not change the existing journey harness or its evidence schema.
    private struct Persona {
        let name: String
        let days: Int
        let priorities: [(area: String, level: String, styles: [String])]
        let injuryNotes: String
        let posturalNotes: String
    }
    private var personas: [Persona] { [
        .init(name: "Six-day push/pull/legs, back focus, no injuries", days: 6,
            priorities: [("Back", "High", ["Pull", "Upper"]), ("Rear Deltoids", "Medium", ["Pull", "Upper"])],
            injuryNotes: "", posturalNotes: "Mild forward head posture."),
        .init(name: "Four-day beginner with a shoulder that hurts overhead", days: 4,
            priorities: [("Chest", "High", ["Push", "Upper"]), ("Quads", "Medium", ["Legs", "Lower"])],
            injuryNotes: "Right shoulder pain with overhead pressing. No pain on rows.", posturalNotes: "Rounded shoulders."),
        .init(name: "Five-day lifter reporting lumbar-extension pain", days: 5,
            priorities: [("Hamstrings", "High", ["Legs", "Lower"]), ("Lats", "Medium", ["Pull", "Upper"])],
            injuryNotes: "Lower back pain with lumbar extension.", posturalNotes: "Anterior pelvic tilt."),
        .init(name: "Compound priority area, small muscles", days: 5,
            priorities: [("Lateral Deltoids", "High", ["Push", "Upper"]), ("Calves", "Medium", ["Legs", "Lower"])],
            injuryNotes: "", posturalNotes: ""),
        .init(name: "Arms specialisation on four days", days: 4,
            priorities: [("Biceps", "High", ["Pull", "Arms"]), ("Triceps", "High", ["Push", "Arms"])],
            injuryNotes: "Occasional elbow discomfort on skull crushers.", posturalNotes: "")
    ] }
    private func analysis(for persona: Persona) -> BodyAnalysisResult {
        let structured = StructuredTrainingIntent(
            splitRecommendation: persona.days >= 6 ? "Push / Pull / Legs" : "Upper / Lower",
            weeklyTrainingDays: persona.days, priorities: persona.priorities.map { entry in
                StructuredTrainingPriority(area: entry.area, priorityLevel: entry.level,
                    rationale: "Simulation rationale for \(entry.area).", weeklyDayTarget: entry.level == "High" ? 2 : 1,
                    weeklyExerciseTarget: entry.level == "High" ? 3 : 2, preferredStyles: entry.styles,
                    preferredMovementPatterns: [], volumeBias: entry.level == "High" ? "High" : "Moderate",
                    directWorkBias: "Direct emphasis")
            }, programmingNotes: ["Simulation persona: \(persona.name)."])
        return BodyAnalysisResult(overallAssessment: "Simulated athlete.", trainingAssessment: "", nutritionAssessment: "",
            recoveryRiskAssessment: "", adherenceAssessment: "", analysisLimitations: "", inputContext: nil,
            regionBreakdown: [], topLeverageChange: "", priorityMuscles: persona.priorities.map(\.area),
            workoutRecommendations: [], dietRecommendations: [], posturalNotes: persona.posturalNotes,
            estimatedBodyFat: "", metabolicHealthNotes: "", psychologicalInsights: "", injuryRiskNotes: persona.injuryNotes,
            macroTargets: nil, structuredTrainingIntent: structured)
    }

    func testTraceFiveCompleteWeekOnePlansWithOptionalSixSlotReservation() throws {
        var report = ["SIX_SLOT_DIAGNOSTIC: five synthetic Week 1 plans; production capacity comparison, no device proof.",
            "Reservation proves role-floor subset feasibility only; fresh allocation/dose comparison is reported separately."]
        var processed = 0
        var expectedCrowded = 0
        var verifiedSubsets = 0
        var adoptedPersonas = Set<String>()
        var postAllocationRefusals = 0
        for persona in personas {
            let intent = service.trainingIntentPlan(from: analysis(for: persona))
            let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
            var phases: [(String, [[ClaudeService.PreSelectedExercise]])] = []
            var baseline: ClaudeService.SubstitutionPlanningBaseline?
            var capacity: ClaudeService.SessionCapacityFinalization?
            var rowInput: ClaudeService.SubstitutionPlanningBaseline?
            let delivered = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent, weekNumber: 1,
                previousWeekDays: nil, exerciseHistory: nil,
                menuPlanningTrace: { phases.append(($0, $1)) }, rowPlanningReport: { rowInput = $0; _ = $1 },
                capacityPlanningReport: { baseline = $0; capacity = $1 })
            let funded = try XCTUnwrap(baseline)
            XCTAssertEqual(funded.roleFloorAdmission, .admitted, "Preserved-dose diagnostics require an admitted baseline")
            let observedCapacity = try XCTUnwrap(capacity)
            let observedRowInput = try XCTUnwrap(rowInput)
            XCTAssertEqual(signature(observedRowInput.menus), signature(observedCapacity.plan.menus))
            XCTAssertEqual(observedRowInput.roleFloorAdmission, observedCapacity.plan.roleFloorAdmission)
            let effectiveBlueprint = funded.blueprint
            let candidate = try XCTUnwrap(phases.first { $0.0 == "sessionOrder" }).1
            let saved = signature(delivered.menus)
            XCTAssertEqual(candidate.count, 7)
            processed += 1
            let crowded = candidate.contains { $0.count > 6 }
            if crowded { expectedCrowded += 1 }
            XCTAssertTrue(crowded, "The historical Week 1 candidate must exercise the over-six diagnostic: \(persona.name)")
            report.append("PERSONA \(persona.name)")
            report.append("BASELINE admission=\(funded.roleFloorAdmission) counts=\(funded.menus.map(\.count))")
            for day in candidate.indices where !effectiveBlueprint.dayPlans[day].isRestDay {
                let first = phases.indices.first { phases[$0].1[day].count > 6 }
                let transition = first.map { $0 == 0 ? phases[$0].0 : "\(phases[$0 - 1].0)->\(phases[$0].0)" } ?? "none"
                report.append("DAY \(day + 1) style=\(effectiveBlueprint.dayPlans[day].style) firstOverSix=\(transition) phaseCounts=\(phases.map { "\($0.0):\($0.1[day].count)" }.joined(separator: ","))")
                if ["Five-day lifter reporting lumbar-extension pain", "Arms specialisation on four days"].contains(persona.name),
                   let first, first > 0 {
                    // Reuse captured menus: no extra generation. Multiset subtraction preserves
                    // repeated appearances; a dose/role change appears as removal plus insertion.
                    func records(_ menu: [ClaudeService.PreSelectedExercise]) -> [String] {
                        menu.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.role)|\($0.prescribedSets)" }
                    }
                    func subtract(_ values: [String], _ other: [String]) -> [String] {
                        var remaining = other
                        return values.filter { value in
                            if let index = remaining.firstIndex(of: value) {
                                remaining.remove(at: index)
                                return false
                            }
                            return true
                        }
                    }
                    let before = records(phases[first - 1].1[day])
                    let after = records(phases[first].1[day])
                    report.append("FIRST_OVER_SIX_DELTA week=1 day=\(day + 1) transition=\(transition) fields=name|target|role|sets before=\(before) after=\(after) inserted=\(subtract(after, before)) removed=\(subtract(before, after))")
                }
            }
            report.append("CANDIDATE \(signature(candidate))")
            // Diagnostic only: exact inclusion+dose choices within this supplied
            // fixed-location pool. No names, placements or history are invented;
            // numeric admission is NOT full quality or symptom authorization.
            func traceJointSearch(_ label: String, _ pool: [[ClaudeService.PreSelectedExercise]], preservingBaseline: Bool = false) throws {
                let projection = try XCTUnwrap(service.jointDoseProjection(for: pool,
                    blueprint: effectiveBlueprint, weekNumber: 1, requiredKeysByDay: funded.retainedKeysByDay,
                    preservingDoseOf: preservingBaseline ? funded.menus : nil))
                var statistics: WorkoutAppearancePlanner.ChoiceSearchStatistics?
                let outcome = WorkoutAppearancePlanner.solveChoices(projection.problem, maximumStates: 512,
                    statistics: { statistics = $0 })
                let observed = try XCTUnwrap(statistics)
                XCTAssertLessThanOrEqual(observed.visitedStates, 512)
                // Synthetic, network-free replay of these EXACT coefficients permits
                // search-only experiments on Windows without rebuilding the app/core.
                func constraintJSON(_ value: WorkoutAppearancePlanner.Constraint) -> [String: Any] {
                    ["name": value.name, "coefficients": value.coefficients, "limit": value.limit]
                }
                let replay: [String: Any] = ["persona": persona.name, "pool": label,
                    "domains": projection.problem.domains,
                    "upperBounds": projection.problem.upperBounds.map(constraintJSON),
                    "lowerBounds": projection.problem.lowerBounds.map(constraintJSON),
                    "coverage": projection.problem.coverage.map {
                        ["name": $0.name, "groups": $0.groups, "minimumGroups": $0.minimumGroups] as [String: Any]
                    },
                    "thresholdCoverage": projection.problem.thresholdCoverage.map {
                        ["name": $0.name, "groups": $0.groups.map(constraintJSON), "minimumGroups": $0.minimumGroups] as [String: Any]
                    },
                    "options": projection.options.map {
                        ["day": $0.day, "slot": $0.slot, "sets": $0.sets,
                         "name": pool[$0.day][$0.slot].exerciseName] as [String: Any]
                    }]
                let replayData = try JSONSerialization.data(withJSONObject: replay, options: [.sortedKeys])
                report.append("JOINT_REPLAY " + (try XCTUnwrap(String(data: replayData, encoding: .utf8))))
                report.append("JOINT_SEARCH \(label) domains=\(projection.problem.domains.count) options=\(projection.options.count) states=\(observed.visitedStates) complete=\(observed.completeAssignments) outcome=\(outcome); supplied pool only, not exhaustive catalog search or workout approval")
                report.append("JOINT_SEARCH \(label) slotCapacityShortfalls=\(projection.slotCapacityShortfalls)")
                if case .admitted(let picks) = outcome {
                    var proposed = Array(repeating: [ClaudeService.PreSelectedExercise](), count: 7)
                    for pick in picks {
                        let option = projection.options[pick]
                        guard option.sets > 0 else { continue }
                        var item = pool[option.day][option.slot]
                        item.prescribedSets = option.sets
                        proposed[option.day].append(item)
                    }
                    for day in proposed.indices {
                        XCTAssertTrue(effectiveBlueprint.dayPlans[day].isRestDay
                            ? proposed[day].isEmpty : (5...6).contains(proposed[day].count))
                    }
                    let verified = service.verifyExactFundedDose(proposed, baseline: funded)
                    if preservingBaseline { XCTAssertEqual(verified, .verified, "Modeled preservation must survive the independent dose verifier") }
                    report.append("JOINT_SEARCH \(label) menus=\(signature(proposed)) exactBaselineDose=\(verified); complete placement checks still required")
                }
            }
            try traceJointSearch("existingLocations", candidate)
            try traceJointSearch("existingLocationsPreservingDose", candidate, preservingBaseline: true)
            if ["Five-day lifter reporting lumbar-extension pain", "Arms specialisation on four days"].contains(persona.name) {
                // Named diagnostic hypotheses, NOT a production search or an adoption path.
                // They distinguish whole-plan feasibility from the current operation contract.
                var trial = funded.menus
                func index(_ name: String, day: Int) throws -> Int {
                    try XCTUnwrap(trial[day].firstIndex { $0.exerciseName == name }, name)
                }
                if persona.name == "Five-day lifter reporting lumbar-extension pain" {
                    trial[4].remove(at: try index("Machine Incline Press", day: 4))
                    trial[4][try index("Incline Barbell Press", day: 4)].prescribedSets += 1
                    trial[5][try index("Incline Dumbbell Press", day: 5)].prescribedSets += 1
                    let moved = trial[4].remove(at: try index("Machine Shoulder Press", day: 4))
                    trial[5].insert(moved, at: 1)
                } else {
                    trial[0].remove(at: try index("EZ-Bar Skull Crusher", day: 0))
                    trial[0][try index("Rope Triceps Pressdown", day: 0)].prescribedSets += 1
                    trial[0][try index("Overhead Cable Triceps Extension", day: 0)].prescribedSets += 1
                    let lateral = trial[3].remove(at: try index("Machine Lateral Raise", day: 3))
                    trial[0].append(lateral)
                    let core = trial[3].remove(at: try index("Cable Pallof Press", day: 3))
                    trial[0].append(core)
                }
                func summarize(_ label: String, _ menus: [[ClaudeService.PreSelectedExercise]]) {
                    let dose = service.compareAllocatedDoseOnly(menus, baseline: funded.menus,
                        blueprint: effectiveBlueprint, weekNumber: 1)
                    let shoulderLoss = service.capacityShoulderRegionLoss(menus, baseline: funded.menus)
                    let days = menus.indices.map { day in
                        WorkoutDayResponse(dayNumber: day + 1, dayName: effectiveBlueprint.dayPlans[day].style,
                            muscleGroups: "", isRestDay: effectiveBlueprint.dayPlans[day].isRestDay, notes: "",
                            exercises: menus[day].map { item in
                                WorkoutExerciseResponse(exerciseName: item.exerciseName, sets: item.prescribedSets,
                                    reps: "", tempo: "", restSeconds: 0, notes: "", muscleTarget: item.muscleTarget)
                            })
                    }
                    let style = days.indices.filter { !days[$0].isRestDay }.map { day in
                        service.dayClearlySupportsExpectedStyle(effectiveBlueprint.dayPlans[day].style, day: days[day])
                    }
                    let reordered = service.reorderedMenusForSessionFlow(menus, blueprint: effectiveBlueprint,
                        trainingIntent: intent, lockedPrefixCounts: funded.lockedPrefixCounts)
                    func regionalSets(_ value: [[ClaudeService.PreSelectedExercise]]) -> [String: Int] {
                        var totals: [String: Int] = [:]
                        for item in value.joined() {
                            let areas = service.exerciseMetadata(forExerciseName: item.exerciseName,
                                muscleTarget: item.muscleTarget).primaryAreas
                            for area in Set(areas.map(service.normalizedPriorityText)) {
                                totals[area, default: 0] += item.prescribedSets
                            }
                        }
                        return totals
                    }
                    let oldRegions = regionalSets(funded.menus), newRegions = regionalSets(menus)
                    let changes = Set(oldRegions.keys).union(newRegions.keys).sorted().compactMap { area -> String? in
                        let old = oldRegions[area, default: 0], new = newRegions[area, default: 0]
                        return old == new ? nil : "\(area):\(old)->\(new)"
                    }
                    report.append("JOINT_HYPOTHESIS \(label) counts=\(menus.map(\.count)) dose=\(dose) shoulderLoss=\(String(describing: shoulderLoss)) wholeDayStyle=\(style) fatigue=\(days.map { service.estimatedDayFatigue(for: $0.exercises) }) limits=\(effectiveBlueprint.dayPlans.map(\.targetFatigueCap)) orderingUnchanged=\(signature(reordered) == signature(menus))")
                    report.append("JOINT_HYPOTHESIS \(label) primaryRegionChanges=\(changes) originalLocks=\(funded.lockedPrefixCounts); ordering comparison is not retained-identity authorization")
                    report.append("JOINT_HYPOTHESIS \(label) menus=\(signature(menus)) back=\(service.plannedBackBalanceFindings(menus, blueprint: effectiveBlueprint))")
                }
                summarize("proposed", trial)
                try traceJointSearch("hypothesisLocations", trial)
                try traceJointSearch("hypothesisLocationsPreservingDose", trial, preservingBaseline: true)
                let exactProposedDose = service.verifyExactFundedDose(trial, baseline: funded)
                report.append("EXACT_FUNDED_DOSE proposed=\(exactProposedDose); quantitative only, no placement authorization")
                XCTAssertEqual(exactProposedDose, .verified, persona.name)
                // Quantities cannot authorize these optional changes: reproduce the
                // same reported-symptom screen used by existing placement operations.
                // This is a policy finding, not proof these exercises cause pain.
                let changedReceivers: [(Int, String)] = persona.name == "Arms specialisation on four days"
                    ? [(0, "Rope Triceps Pressdown"), (0, "Overhead Cable Triceps Extension")]
                    : [(4, "Incline Barbell Press"), (5, "Incline Dumbbell Press"), (5, "Machine Shoulder Press")]
                let joint: ClaudeService.ReportedJointStressArea = persona.name == "Arms specialisation on four days"
                    ? .elbow : .lowerBack
                for (day, name) in changedReceivers {
                    let item = try XCTUnwrap(trial[day].first { $0.exerciseName == name })
                    let implicated = service.reportedJointPainImplicates(joint, exerciseName: item.exerciseName,
                        muscleTarget: item.muscleTarget, injuryRiskFocus: effectiveBlueprint.injuryRiskFocus)
                    XCTAssertTrue(implicated, "The current optional-change symptom policy must not be bypassed: \(name)")
                    report.append("PLACEMENT_SYMPTOM_CONFLICT day=\(day + 1) exercise=\(name) joint=\(joint) implicated=\(implicated); exact dose verification is not adoption permission")
                }
                if persona.name == "Arms specialisation on four days" {
                    // Preserve the actual daily priority dose, not just weekly arm totals.
                    for area in ["Biceps", "Triceps"] {
                        func dailyDose(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [Double] {
                            menus.map { menu in
                                menu.reduce(0) { sum, item in
                                    sum + Double(item.prescribedSets) * service.focusDirectSetCredit(
                                        for: service.focusStimulusKind(exerciseName: item.exerciseName,
                                            muscleTarget: item.muscleTarget, focusArea: area))
                                }
                            }
                        }
                        XCTAssertEqual(dailyDose(trial), dailyDose(funded.menus), area)
                        report.append("JOINT_HYPOTHESIS simplerArms \(area) baseline=\(dailyDose(funded.menus)) proposed=\(dailyDose(trial))")
                    }
                }
                var trialAdmission: ClaudeService.RoleFloorAdmission = .unassessed
                let trialAllocated = service.allocateWeeklySetPrescription(trial, blueprint: effectiveBlueprint,
                    weekNumber: 1, lockedPrefixCounts: funded.lockedPrefixCounts,
                    roleFloorAdmissionReport: { trialAdmission = $0 }, publishConflictLogs: false)
                summarize("reallocated", trialAllocated)
                let exactReallocatedDose = service.verifyExactFundedDose(trialAllocated, baseline: funded)
                report.append("EXACT_FUNDED_DOSE reallocated=\(exactReallocatedDose)")
                if persona.name == "Arms specialisation on four days" {
                    XCTAssertEqual(exactReallocatedDose, .refused(.dose(.sessionPriority(day: 0, area: "Triceps"))))
                } else {
                    XCTAssertEqual(exactReallocatedDose,
                        .refused(.primaryRegionLoss(region: "upper chest", baselineSets: 8, candidateSets: 7)))
                }
                report.append("JOINT_HYPOTHESIS admission=\(trialAdmission); not authorized for adoption: reported-symptom conflict reproduced; complete catalog/history eligibility, full prescriptions and neighboring weeks remain unverified")
            }
            let result = service.reserveWeeklyAppearanceFloors(candidate, blueprint: effectiveBlueprint, weekNumber: 1,
                lockedPrefixCounts: funded.lockedPrefixCounts, maximumExercisesPerDay: 6)
            report.append("RESERVATION outcome=\(result.outcome) counts=\(result.menus.map(\.count))")
            if case .admitted = result.outcome {
                XCTAssertTrue(result.menus.indices.allSatisfy {
                    effectiveBlueprint.dayPlans[$0].isRestDay ? result.menus[$0].isEmpty : (5...6).contains(result.menus[$0].count)
                })
                var admission: ClaudeService.RoleFloorAdmission = .unassessed
                let allocated = service.allocateWeeklySetPrescription(result.menus, blueprint: effectiveBlueprint, weekNumber: 1,
                    lockedPrefixCounts: funded.lockedPrefixCounts, roleFloorAdmissionReport: { admission = $0 },
                    publishConflictLogs: false)
                let dose = service.compareAllocatedDoseOnly(allocated, baseline: funded.menus, blueprint: effectiveBlueprint, weekNumber: 1)
                report.append("FRESH_ALLOCATION admission=\(admission) counts=\(allocated.map(\.count)) dose=\(dose)")
                report.append("FUNDED_BASELINE \(signature(funded.menus))")
                report.append("FUNDED_CANDIDATE \(signature(allocated))")
            } else {
                XCTAssertEqual(signature(result.menus), signature(candidate), "Refused reservation must retain the candidate")
            }
            XCTAssertEqual(signature(delivered.menus), saved, "Diagnostics never mutate the actual delivered plan")
            let marker = SetFundingObservation(dayIndex: 0, exerciseIndex: 0, exerciseName: "baseline marker",
                muscleTarget: "marker", prescribedSets: 2, rejection: nil)
            let finalized = service.finalizeSessionCapacity(funded, trainingIntent: intent,
                baselineMessages: ["baseline marker"], baselineReceipts: [marker], collectFunding: true)
            report.append("VERIFIED_SUBSET decision=\(finalized.decision)")
            XCTAssertEqual(finalized.decision, observedCapacity.decision)
            XCTAssertEqual(signature(finalized.plan.menus), signature(observedCapacity.plan.menus))
            if finalized.decision.hasPrefix("adopted") {
                verifiedSubsets += 1
                adoptedPersonas.insert(persona.name)
                XCTAssertEqual(finalized.plan.roleFloorAdmission, .admitted)
                XCTAssertTrue(finalized.plan.menus.allSatisfy { $0.count <= 6 })
                guard case .dosePreserved = service.compareAllocatedDoseOnly(finalized.plan.menus,
                    baseline: funded.menus, blueprint: effectiveBlueprint, weekNumber: 1) else {
                    return XCTFail("A verified subset cannot lose baseline dose")
                }
                let originalProgram = try service.validatedProceduralWeekOneProgram(from: analysis(for: persona),
                    trainingIntent: intent, blueprint: effectiveBlueprint, exerciseMenus: funded.menus)
                let subsetProgram = try service.validatedProceduralWeekOneProgram(from: analysis(for: persona),
                    trainingIntent: intent, blueprint: effectiveBlueprint, exerciseMenus: finalized.plan.menus)
                XCTAssertEqual(subsetProgram.days.count, finalized.plan.menus.count)
                for (day, menu) in zip(subsetProgram.days, finalized.plan.menus) {
                    XCTAssertEqual(day.exercises.map(\.exerciseName), menu.map(\.exerciseName))
                    XCTAssertEqual(day.exercises.map(\.muscleTarget), menu.map(\.muscleTarget))
                    XCTAssertEqual(day.exercises.map(\.sets), menu.map(\.prescribedSets))
                }
                let oldFindings = service.validateProgramResponse(originalProgram, blueprint: effectiveBlueprint,
                    expectedExerciseMenus: funded.menus)
                let newFindings = service.validateProgramResponse(subsetProgram, blueprint: effectiveBlueprint,
                    expectedExerciseMenus: finalized.plan.menus)
                let oldCounts = Dictionary(grouping: oldFindings, by: { $0 }).mapValues(\.count)
                let newCounts = Dictionary(grouping: newFindings, by: { $0 }).mapValues(\.count)
                XCTAssertTrue(newCounts.allSatisfy { message, count in count <= oldCounts[message, default: 0] },
                    "New findings: \(newFindings)")
                report.append("VERIFIED_SUBSET menus=\(signature(finalized.plan.menus)) findings=\(newFindings)")
                XCTAssertFalse(finalized.receipts.isEmpty)
                XCTAssertFalse(finalized.receipts.contains(marker))
                let coordinates = finalized.plan.menus.indices.flatMap { day in
                    finalized.plan.menus[day].indices.map { "\(day):\($0)" }
                }
                XCTAssertEqual(finalized.receipts.map { "\($0.dayIndex):\($0.exerciseIndex)" }, coordinates)
                for receipt in finalized.receipts {
                    guard finalized.plan.menus.indices.contains(receipt.dayIndex),
                          finalized.plan.menus[receipt.dayIndex].indices.contains(receipt.exerciseIndex) else {
                        return XCTFail("Receipt points outside its returned plan")
                    }
                    let actual = finalized.plan.menus[receipt.dayIndex][receipt.exerciseIndex]
                    XCTAssertEqual(receipt.exerciseName, actual.exerciseName)
                    XCTAssertEqual(receipt.muscleTarget, actual.muscleTarget)
                    XCTAssertEqual(receipt.prescribedSets, actual.prescribedSets)
                }
                let repeated = service.finalizeSessionCapacity(finalized.plan, trainingIntent: intent,
                    baselineMessages: finalized.messages, baselineReceipts: finalized.receipts, collectFunding: true)
                XCTAssertEqual(repeated.decision, "already within six exercises")
                XCTAssertEqual(signature(repeated.plan.menus), signature(finalized.plan.menus))
                XCTAssertEqual(repeated.receipts, finalized.receipts)
                XCTAssertEqual(repeated.messages, finalized.messages)
            } else {
                if finalized.decision.hasPrefix("fresh allocation dose refused") { postAllocationRefusals += 1 }
                XCTAssertEqual(signature(finalized.plan.menus), signature(funded.menus))
                XCTAssertEqual(finalized.messages, ["baseline marker"])
                XCTAssertEqual(finalized.receipts, [marker])
            }
            let retainedPlan = ClaudeService.SubstitutionPlanningBaseline(menus: funded.menus,
                blueprint: effectiveBlueprint, weekNumber: 1, lockedPrefixCounts: funded.lockedPrefixCounts,
                retainedKeysByDay: funded.menus.map { Set($0.map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) }) },
                exerciseHistory: funded.exerciseHistory, selectionFocusIntents: funded.selectionFocusIntents,
                roleFloorAdmission: .admitted)
            let protectedResult = service.finalizeSessionCapacity(retainedPlan, trainingIntent: intent,
                baselineMessages: ["protected marker"], baselineReceipts: [marker], collectFunding: true)
            XCTAssertFalse(protectedResult.decision.hasPrefix("adopted"))
            if finalized.decision.hasPrefix("adopted") {
                XCTAssertEqual(protectedResult.decision, "reservation removed protected or retained appearance")
            }
            XCTAssertEqual(signature(protectedResult.plan.menus), signature(funded.menus))
            XCTAssertEqual(protectedResult.messages, ["protected marker"])
            XCTAssertEqual(protectedResult.receipts, [marker])
            for status in [ClaudeService.RoleFloorAdmission.unassessed, .deloadPolicy,
                           .infeasible(["fixture"]), .searchLimit(["fixture"])] {
                var nonAdmitted = funded
                nonAdmitted.roleFloorAdmission = status
                let refusal = service.finalizeSessionCapacity(nonAdmitted, trainingIntent: intent,
                    baselineMessages: ["admission marker"], baselineReceipts: [marker], collectFunding: true)
                XCTAssertEqual(refusal.decision, "baseline not admitted")
                XCTAssertEqual(refusal.plan.roleFloorAdmission, status)
                XCTAssertEqual(signature(refusal.plan.menus), signature(funded.menus))
                XCTAssertEqual(refusal.messages, ["admission marker"])
                XCTAssertEqual(refusal.receipts, [marker])
            }
            let malformed = ClaudeService.SubstitutionPlanningBaseline(menus: funded.menus,
                blueprint: effectiveBlueprint, weekNumber: 1, lockedPrefixCounts: [],
                retainedKeysByDay: funded.retainedKeysByDay, exerciseHistory: funded.exerciseHistory,
                selectionFocusIntents: funded.selectionFocusIntents, roleFloorAdmission: .admitted)
            let invalidResult = service.finalizeSessionCapacity(malformed, trainingIntent: intent,
                baselineMessages: ["context marker"], baselineReceipts: [marker], collectFunding: true)
            XCTAssertEqual(invalidResult.decision, "invalid planning context")
            XCTAssertEqual(signature(invalidResult.plan.menus), signature(funded.menus))
            XCTAssertEqual(invalidResult.messages, ["context marker"])
            XCTAssertEqual(invalidResult.receipts, [marker])
        }
        XCTAssertEqual(processed, 5)
        XCTAssertEqual(expectedCrowded, 5, "All five historical Week 1 profiles must exercise the capacity problem")
        XCTAssertGreaterThanOrEqual(verifiedSubsets, 2, "The two previously dose-preserving profiles must exercise verification")
        XCTAssertTrue(adoptedPersonas.contains("Six-day push/pull/legs, back focus, no injuries"))
        XCTAssertTrue(adoptedPersonas.contains("Compound priority area, small muscles"))
        XCTAssertGreaterThan(postAllocationRefusals, 0, "At least one actual dose refusal must preserve baseline reports")
        report.append("VERIFIED_SUBSETS count=\(verifiedSubsets); production callback and standalone result agree")
        report.append("SUMMARY processed=\(processed) expectedCrowded=\(expectedCrowded)")
        let output = report.joined(separator: "\n")
        print(output)
        if let path = ProcessInfo.processInfo.environment["TRANSFORM_SIX_SLOT_REPORT_OUTPUT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func signature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
        menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role.rawValue)|\($0.prescribedSets)" } }
    }
}
