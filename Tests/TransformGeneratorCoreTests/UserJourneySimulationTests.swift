import XCTest
@testable import Transform

/// A trial run of the app, driven the way an athlete actually uses it.
///
/// Every other test in this suite asks a narrow question about one rule. This one plays five
/// realistic people through the FULL mesocycle — week 1, then weeks 2, 3 and 4 each carrying
/// the previous week forward — and checks the things a person would notice: that a day is not
/// half empty, that the same lift is not prescribed twice in one session, that a week does not
/// silently lose a training day, and that running the same analysis twice gives the same
/// program.
///
/// It drives the PROCEDURAL path, which is network-free and therefore the only end-to-end path
/// a headless runner can execute. That path is not a lesser one: it consumes the same locked
/// menu, the same weekly set allocation and the same validator as the AI path, and it is what
/// the athlete actually receives whenever generation falls back.
///
/// Structural invariants below are hard assertions. Other findings are saved as evidence,
/// not an approval of workout quality. The text and JSON artifacts expose actual prescriptions;
/// explicit product requirements can then become regression gates without weakening validation.
@MainActor
final class UserJourneySimulationTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Personas

    private struct Persona {
        let name: String
        let days: Int
        let priorities: [(area: String, level: String, styles: [String])]
        let injuryNotes: String
        let posturalNotes: String
    }

    private var personas: [Persona] {
        [
            Persona(
                name: "Six-day push/pull/legs, back focus, no injuries",
                days: 6,
                priorities: [
                    ("Back", "High", ["Pull", "Upper"]),
                    ("Rear Deltoids", "Medium", ["Pull", "Upper"])
                ],
                injuryNotes: "",
                posturalNotes: "Mild forward head posture."
            ),
            Persona(
                name: "Four-day beginner with a shoulder that hurts overhead",
                days: 4,
                priorities: [
                    ("Chest", "High", ["Push", "Upper"]),
                    ("Quads", "Medium", ["Legs", "Lower"])
                ],
                injuryNotes: "Right shoulder pain with overhead pressing. No pain on rows.",
                posturalNotes: "Rounded shoulders."
            ),
            Persona(
                name: "Five-day lifter reporting lumbar-extension pain",
                days: 5,
                priorities: [
                    ("Hamstrings", "High", ["Legs", "Lower"]),
                    ("Lats", "Medium", ["Pull", "Upper"])
                ],
                injuryNotes: "Lower back pain with lumbar extension.",
                posturalNotes: "Anterior pelvic tilt."
            ),
            Persona(
                name: "Compound priority area, small muscles",
                days: 5,
                priorities: [
                    ("Lateral Deltoids", "High", ["Push", "Upper"]),
                    ("Calves", "Medium", ["Legs", "Lower"])
                ],
                injuryNotes: "",
                posturalNotes: ""
            ),
            Persona(
                name: "Arms specialisation on four days",
                days: 4,
                priorities: [
                    ("Biceps", "High", ["Pull", "Arms"]),
                    ("Triceps", "High", ["Push", "Arms"])
                ],
                injuryNotes: "Occasional elbow discomfort on skull crushers.",
                posturalNotes: ""
            )
        ]
    }

    private func analysis(for persona: Persona) -> BodyAnalysisResult {
        let structured = StructuredTrainingIntent(
            splitRecommendation: persona.days >= 6 ? "Push / Pull / Legs" : "Upper / Lower",
            weeklyTrainingDays: persona.days,
            priorities: persona.priorities.map { entry in
                StructuredTrainingPriority(
                    area: entry.area,
                    priorityLevel: entry.level,
                    rationale: "Simulation rationale for \(entry.area).",
                    weeklyDayTarget: entry.level == "High" ? 2 : 1,
                    weeklyExerciseTarget: entry.level == "High" ? 3 : 2,
                    preferredStyles: entry.styles,
                    preferredMovementPatterns: [],
                    volumeBias: entry.level == "High" ? "High" : "Moderate",
                    directWorkBias: "Direct emphasis"
                )
            },
            programmingNotes: ["Simulation persona: \(persona.name)."]
        )
        return BodyAnalysisResult(
            overallAssessment: "Simulated athlete.",
            trainingAssessment: "",
            nutritionAssessment: "",
            recoveryRiskAssessment: "",
            adherenceAssessment: "",
            analysisLimitations: "",
            inputContext: nil,
            regionBreakdown: [],
            topLeverageChange: "",
            priorityMuscles: persona.priorities.map(\.area),
            workoutRecommendations: [],
            dietRecommendations: [],
            posturalNotes: persona.posturalNotes,
            estimatedBodyFat: "",
            metabolicHealthNotes: "",
            psychologicalInsights: "",
            injuryRiskNotes: persona.injuryNotes,
            macroTargets: nil,
            structuredTrainingIntent: structured
        )
    }

    // MARK: - The journey

    /// Runs one persona through all four weeks and returns every week's days in order.
    /// One week as the athlete receives it, plus what the validator says about it.
    private struct SimulatedWeek {
        let days: [WorkoutDayResponse]
        let findings: [String]
        /// Per-training-day "style x movement count", so a session-shape finding can be read
        /// against the day that produced it instead of inferred from week totals.
        let shape: String
        let blueprint: ClaudeService.ProgramBlueprint
        let appearancePlanning: [String]
        let nextSetFunding: [SetFundingObservation]
        // Reuse the real generation's value snapshots within a test, never cache across runs.
        let planningBaseline: ClaudeService.SubstitutionPlanningBaseline
        let finalization: ClaudeService.PressdownFinalization
        let coreFinalization: ClaudeService.CoreRelocationFinalization
    }

    // Test-only export: no changes to production models or the generation contract.
    private struct JourneyEvidence: Encodable {
        let schemaVersion = 1
        let scope = "Synthetic procedural generation; no paid AI, logged training, or device/UI execution."
        let personas: [PersonaEvidence]
    }

    private struct PersonaEvidence: Encodable {
        let name: String
        let analysis: BodyAnalysisResult
        let weeks: [WeekEvidence]
    }

    private struct WeekEvidence: Encodable {
        let weekNumber: Int
        let evidenceVersion: String
        let plannedTrainingDays: Int
        let priorities: [PriorityEvidence]
        let days: [WorkoutDayResponse]
        let validatorFindings: [String]
        let appearancePlanning: [String]
        let nextSetFunding: [SetFundingObservation]
        let crossDayTrials: [CrossDayTrial]
    }

    // Diagnostic only: candidates never feed the next week or the shipping planner.
    private struct CrossDayTrial: Encodable {
        let hypothesis: String
        let contextBlockers: [String]
        let proposedDose: String
        let allocatedDose: String
        let admission: String
        let exactProposalRetained: Bool
        let allPrimaryRegionSetsPreserved: Bool
        let changedSurvivors: [String]
        let newValidatorFindings: [String]
        let baselinePrimaryRegionDays: [String: Int]
        let candidatePrimaryRegionDays: [String: Int]
        let proposedDays: [WorkoutDayResponse]
        let allocatedDays: [WorkoutDayResponse]
        let days: [WorkoutDayResponse]
        let receipts: [SetFundingObservation]
    }

    private func crossDayTrials(persona: Persona, weeks: [SimulatedWeek], index: Int) throws -> [CrossDayTrial] {
        let beginner = persona.name == "Four-day beginner with a shoulder that hurts overhead"
        let small = persona.name == "Compound priority area, small muscles"
        guard (beginner && index < 3) || (small && (1...2).contains(index)) else { return [] }
        let plan = weeks[index].coreFinalization.plan
        let menus = plan.menus, blueprint = plan.blueprint
        let intent = service.trainingIntentPlan(from: analysis(for: persona))
        let previous = index == 0 ? nil : weeks[index - 1].days
        let source = try XCTUnwrap(blueprint.dayPlans.indices.first {
            service.canonicalTrainingStyle(blueprint.dayPlans[$0].style) == "Upper"
        })
        let receiver = try XCTUnwrap(blueprint.dayPlans.indices.first {
            service.canonicalTrainingStyle(blueprint.dayPlans[$0].style) == (beginner ? "Pull" : "Arms")
        })
        if menus[source].count <= 6 {
            // Production has resolved this shape. Do not pretend its old 7/5
            // trial still describes the current sequential baseline.
            XCTAssertTrue(menus.allSatisfy { $0.count <= 6 })
            return []
        }
        XCTAssertEqual(menus[source].count, 7)
        XCTAssertEqual(menus[receiver].count, 5)
        XCTAssertEqual(plan.roleFloorAdmission, .admitted)
        XCTAssertNil(plan.exerciseHistory, "These are synthetic trials, not real-history proof")
        let hypotheses = beginner ? ["Dumbbell Rear Delt Fly", "Reverse Pec Deck"]
            : ["Rope Triceps Pressdown", "Overhead Cable Triceps Extension"]
        func signature(_ value: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
            value.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.role)|\($0.movementPattern)|\($0.prescribedSets)" } }
        }
        func regions(_ item: ClaudeService.PreSelectedExercise) -> Set<String> {
            Set(service.exerciseMetadata(forExerciseName: item.exerciseName, muscleTarget: item.muscleTarget)
                .primaryAreas.map(service.normalizedPriorityText))
        }
        func totals(_ value: [[ClaudeService.PreSelectedExercise]]) -> [String: Int] {
            var result: [String: Int] = [:]
            for item in value.joined() { for region in regions(item) { result[region, default: 0] += item.prescribedSets } }
            return result
        }
        func exposureDays(_ value: [[ClaudeService.PreSelectedExercise]]) -> [String: Int] {
            var result: [String: Int] = [:]
            for day in value {
                var sets: [String: Int] = [:]
                for item in day { for region in regions(item) { sets[region, default: 0] += item.prescribedSets } }
                for (region, count) in sets where count >= 2 { result[region, default: 0] += 1 }
            }
            return result
        }
        func protectionReasons(_ day: Int, _ slot: Int) -> [String] {
            let item = menus[day][slot]
            var reasons: [String] = []
            if service.isProtectedAppearance(role: item.role, slot: slot,
                style: blueprint.dayPlans[day].style, lockedPrefixCount: plan.lockedPrefixCounts[day])
                || service.isProtectedAppearance(role: service.proceduralExerciseRole(for: item.exerciseName,
                    muscleTarget: item.muscleTarget), slot: slot, style: blueprint.dayPlans[day].style,
                    lockedPrefixCount: plan.lockedPrefixCounts[day]) { reasons.append("role or prefix protected") }
            if plan.retainedKeysByDay[day].contains(ExerciseWeightEntry.canonicalLookupKey(item.exerciseName)) {
                reasons.append("retained identity")
            }
            if service.reportedShoulderPainImplicates(exerciseName: item.exerciseName,
                muscleTarget: item.muscleTarget, injuryRiskFocus: blueprint.injuryRiskFocus) {
                reasons.append("reported shoulder symptoms")
            }
            return reasons
        }
        func protected(_ day: Int, _ slot: Int) -> Bool {
            !protectionReasons(day, slot).isEmpty
        }
        func response(_ value: [[ClaudeService.PreSelectedExercise]]) -> WorkoutWeekResponse {
            service.buildProceduralWeek(weekNumber: index + 1, dayStart: index * 7 + 1, dayEnd: index * 7 + 7,
                splitType: intent.splitRecommendation, programName: "Cross-day diagnostic", trainingIntent: intent,
                blueprint: blueprint, previousWeekDays: previous, exerciseMenus: value)
        }
        func findings(_ output: WorkoutWeekResponse, _ value: [[ClaudeService.PreSelectedExercise]]) -> [String] {
            service.validateWeekResponse(output, dayStart: index * 7 + 1, dayEnd: index * 7 + 7,
                previousWeekDays: previous, blueprint: blueprint, expectedExerciseMenus: value)
        }
        let oldFindings = Dictionary(grouping: findings(response(menus), menus), by: { $0 }).mapValues(\.count)
        var trials: [CrossDayTrial] = []
        for hypothesis in hypotheses {
            let donorName = beginner ? hypothesis : "Cable Triceps Pressdown"
            let donor = try XCTUnwrap(menus[source].firstIndex { $0.exerciseName == donorName })
            let removed = menus[source][donor]
            var blockers: [String] = []
            blockers += protectionReasons(source, donor).map { "source: \($0)" }
            var proposed = menus
            proposed[source].remove(at: donor)
            if beginner {
                XCTAssertFalse(menus[receiver].contains { $0.exerciseName == donorName })
                proposed[receiver].append(removed)
                let movement = WorkoutExerciseResponse(exerciseName: donorName, sets: removed.prescribedSets,
                    reps: "10-15", tempo: "", restSeconds: 0, notes: "", muscleTarget: removed.muscleTarget)
                if !service.exerciseMatchesDayStyle(movement, style: blueprint.dayPlans[receiver].style) {
                    blockers.append("receiver style mismatch")
                }
                if !service.exerciseCatalog(for: blueprint.dayPlans[receiver].style).contains(where: {
                    $0.name == removed.exerciseName && $0.target == removed.muscleTarget
                }) { blockers.append("absent from receiver selection catalog") }
            } else {
                let slot = try XCTUnwrap(menus[receiver].firstIndex { $0.exerciseName == hypothesis })
                XCTAssertEqual(regions(menus[receiver][slot]), regions(removed))
                blockers += protectionReasons(receiver, slot).map { "receiver: \($0)" }
                if hypothesis == "Rope Triceps Pressdown" {
                    XCTAssertEqual(slot, 0)
                    XCTAssertTrue(protected(receiver, slot), "Negative control must expose the protected receiver")
                }
                proposed[receiver][slot].prescribedSets += removed.prescribedSets
            }
            XCTAssertEqual(totals(proposed), totals(menus), "The proposal cannot exchange muscle regions")
            XCTAssertEqual(proposed[source].count, 6)
            XCTAssertEqual(proposed[receiver].count, beginner ? 6 : 5)
            let proposedDose = service.compareAllocatedDoseOnly(proposed, baseline: menus,
                blueprint: blueprint, weekNumber: index + 1)
            var admission: ClaudeService.RoleFloorAdmission = .unassessed
            var receipts: [SetFundingObservation] = []
            let allocated = service.allocateWeeklySetPrescription(proposed, blueprint: blueprint, weekNumber: index + 1,
                lockedPrefixCounts: plan.lockedPrefixCounts, setFundingReport: { receipts = $0 },
                roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
            let ordered = service.reorderedMenusForSessionFlow(allocated, blueprint: blueprint,
                trainingIntent: intent, lockedPrefixCounts: plan.lockedPrefixCounts)
            func identities(_ value: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
                value.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.role)|\($0.movementPattern)" } }
            }
            XCTAssertEqual(identities(allocated), identities(proposed), "Allocation cannot change the proposed exercise menu")
            // Receipt coordinates belong to the allocated order, before the independent ordering check.
            XCTAssertEqual(receipts.map { "\($0.dayIndex):\($0.exerciseIndex):\($0.exerciseName):\($0.muscleTarget):\($0.prescribedSets)" },
                allocated.indices.flatMap { day in allocated[day].indices.map { slot in
                    let item = allocated[day][slot]
                    return "\(day):\(slot):\(item.exerciseName):\(item.muscleTarget):\(item.prescribedSets)"
                } })
            if signature(ordered) != signature(allocated) { blockers.append("fresh allocation needs reordering") }
            var changed: [String] = []
            if beginner {
                let relocated = try XCTUnwrap(ordered[receiver].first { $0.exerciseName == removed.exerciseName })
                if relocated.prescribedSets != removed.prescribedSets {
                    changed.append("relocated \(removed.exerciseName): \(removed.prescribedSets)->\(relocated.prescribedSets)")
                }
            }
            for day in menus.indices { for slot in menus[day].indices where !(day == source && slot == donor) {
                let old = menus[day][slot]
                guard let current = ordered[day].first(where: { $0.exerciseName == old.exerciseName && $0.muscleTarget == old.muscleTarget }) else {
                    XCTFail("Fresh allocation lost a survivor"); continue
                }
                if current.prescribedSets != old.prescribedSets {
                    changed.append("day \(day + 1) \(old.exerciseName): \(old.prescribedSets)->\(current.prescribedSets)")
                    if protected(day, slot) { blockers.append("fresh allocation changed protected \(old.exerciseName)") }
                }
            } }
            let output = response(ordered)
            XCTAssertEqual(output.days.map { $0.exercises.map(\.exerciseName) }, ordered.map { $0.map(\.exerciseName) })
            XCTAssertEqual(output.days.map { $0.exercises.map(\.sets) }, ordered.map { $0.map(\.prescribedSets) })
            let newCounts = Dictionary(grouping: findings(output, ordered), by: { $0 }).mapValues(\.count)
            let added = newCounts.keys.sorted().flatMap { message in
                Array(repeating: message, count: max(0, newCounts[message, default: 0] - oldFindings[message, default: 0]))
            }
            trials.append(.init(hypothesis: beginner ? "relocate \(hypothesis) Upper->Pull" : "consolidate Upper pressdown into Arms \(hypothesis)",
                contextBlockers: blockers, proposedDose: String(describing: proposedDose),
                allocatedDose: String(describing: service.compareAllocatedDoseOnly(ordered, baseline: menus,
                    blueprint: blueprint, weekNumber: index + 1)), admission: String(describing: admission),
                exactProposalRetained: signature(ordered) == signature(proposed),
                allPrimaryRegionSetsPreserved: totals(ordered) == totals(menus), changedSurvivors: changed,
                newValidatorFindings: added, baselinePrimaryRegionDays: exposureDays(menus),
                candidatePrimaryRegionDays: exposureDays(ordered), proposedDays: response(proposed).days,
                allocatedDays: response(allocated).days, days: output.days, receipts: receipts))
        }
        XCTAssertEqual(trials.count, 2)
        return trials
    }

    private struct PriorityEvidence: Encodable {
        let area: String
        let directSetTarget: Double
        let targetFrequency: Int
        let targetExerciseSlots: Int
        let deliveredDirectSets: Double
        let directSetShortfall: Double
        let meaningfulDays: Int
    }

    // directSetCredit currently awards 0 or one credit per whole working set.
    // Strict whole-set observer. Conditional fractional shortfalls require separate,
    // independently recomputed binding-budget evidence below, not just a warning label.
    private func meetsWholeSetTarget(delivered: Double, ceiling: Double) -> Bool {
        delivered + 0.01 >= floor(ceiling)
    }

    /// Fail-closed proof for the session/role blockers observed in this fixed matrix.
    /// Other blockers need their own arithmetic proof before this observer accepts them.
    /// This proves no immediate top-up in the retained menu, not global infeasibility.
    private func meetsTargetOrProvesFractionalBudgetLimit(allocation: ClaudeService.BlueprintPriorityAllocation,
        days: [WorkoutDayResponse], blueprint: ClaudeService.ProgramBlueprint,
        receipts: [SetFundingObservation], weekNumber: Int) -> Bool {
        func direct(_ exercises: [WorkoutExerciseResponse], _ area: String) -> Double {
            exercises.reduce(0) { $0 + service.directSetCredit(for: $1, area: area) }
        }
        let delivered = direct(days.flatMap(\.exercises), allocation.area)
        if meetsWholeSetTarget(delivered: delivered, ceiling: service.normalWeeklyPrioritySetCeiling(for: allocation)) {
            return true
        }
        let target = allocation.directSetTarget
        guard abs(target - target.rounded()) > 0.01, delivered + 0.01 >= floor(target),
              target - delivered < 1, days.count == blueprint.dayPlans.count else { return false }
        let limits = service.setBudgetLimits(for: blueprint)
        var eligible = 0
        for (dayIndex, day) in days.enumerated() {
            for (index, exercise) in day.exercises.enumerated()
                where service.directSetCredit(for: exercise, area: allocation.area) > 0 {
                eligible += 1
                let matches = receipts.filter { $0.dayIndex == dayIndex && $0.exerciseIndex == index }
                guard matches.count == 1, let receipt = matches.first,
                      receipt.exerciseName == exercise.exerciseName, receipt.muscleTarget == exercise.muscleTarget,
                      receipt.prescribedSets == exercise.sets, let rejection = receipt.rejection,
                      let reportedNext = rejection.projected, let reportedLimit = rejection.limit else { return false }
                let projected: Double
                let limit: Double
                switch rejection.kind {
                case .role:
                    guard rejection.subject == exercise.exerciseName else { return false }
                    let prime = blueprint.priorityAllocations.contains {
                        service.directSetCredit(for: exercise, area: $0.area) > 0 &&
                        service.focusStimulusKind(exerciseName: exercise.exerciseName,
                            muscleTarget: exercise.muscleTarget, focusArea: $0.area) == .prime
                    }
                    let role = service.proceduralSets(for: weekNumber,
                        exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
                    projected = Double(exercise.sets + 1)
                    limit = Double(prime ? max(role, 4) : role)
                case .sessionPriority:
                    guard let budgetIndex = blueprint.priorityAllocations.firstIndex(where: { $0.area == rejection.subject }),
                          exercise.sets > 0 else { return false }
                    let unitCredit = service.directSetCredit(for: exercise, area: rejection.subject) / Double(exercise.sets)
                    guard unitCredit == 1 else { return false }
                    projected = direct(day.exercises, rejection.subject) + unitCredit
                    limit = limits.sessionFundingCeiling(day: dayIndex, allocation: budgetIndex)
                default:
                    return false
                }
                guard projected > limit, abs(projected - reportedNext) < 0.000001,
                      abs(limit - reportedLimit) < 0.000001 else { return false }
            }
        }
        return eligible > 0
    }

    func testCurrentLowerTraceDoesNotRequireArtificialCrowding() throws {
        let persona = personas[1]
        let intent = service.trainingIntentPlan(from: analysis(for: persona))
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        let lower = try XCTUnwrap(blueprint.dayPlans.indices.first {
            service.canonicalTrainingStyle(blueprint.dayPlans[$0].style) == "Lower"
                && !blueprint.dayPlans[$0].isRestDay
        })
        var phases: [(String, [[ClaudeService.PreSelectedExercise]])] = []
        var preCore: ClaudeService.SubstitutionPlanningBaseline?
        var coreCallbacks = 0
        let observed = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: nil,
            menuPlanningTrace: { phases.append(($0, $1)) },
            corePlanningReport: { preCore = $0; coreCallbacks += 1; XCTAssertEqual($1.decision, .noEligiblePlacement) })
        let unobserved = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: nil)
        func signature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
            menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
        }
        // Emit the captured phases BEFORE throwing assertions. A selection regression
        // can eliminate the crowded baseline itself; that is when this trace is needed
        // most, not a reason to omit it from the failed run's diagnostic artifact.
        let crowdedTransition = phases.indices.first { phases[$0].1[lower].count > 6 }
        let transitionLabel: String
        if let index = crowdedTransition, index > 0 {
            transitionLabel = "\(phases[index - 1].0)->\(phases[index].0)"
        } else {
            transitionLabel = crowdedTransition == nil ? "none" : "initialSelection"
        }
        var report = ["CROWDING_TRACE persona=\(persona.name) week=1 day=\(lower + 1) firstTransition=\(transitionLabel)"]
        for phase in phases {
            report.append("CROWDING_TRACE phase=\(phase.0) lower=\(signature(phase.1)[lower])")
        }
        try writeArtifactIfRequested(report.joined(separator: "\n"), environmentKey: "TRANSFORM_CROWDING_TRACE_OUTPUT")
        XCTAssertEqual(signature(observed.menus), signature(unobserved.menus), "Tracing cannot alter a complete plan")
        XCTAssertEqual(observed.blueprint, unobserved.blueprint)
        XCTAssertEqual(coreCallbacks, 1)
        XCTAssertEqual(phases.map { $0.0 }, ["initialSelection", "baselineCoverage", "priorityFeasibility",
            "baselineCoverageRecheck", "horizontalPullCoverage", "maintenanceBreadth", "lowerKneeAnchor",
            "sessionOrder", "allocated", "sessionCapacity", "finalized"], "Phase labels identify operations, not success verdicts")
        let initial = try XCTUnwrap(phases.first { $0.0 == "initialSelection" })
        XCTAssertLessThanOrEqual(initial.1[lower].count, 6)
        XCTAssertEqual(observed.menus[lower].count, 6)
        let originalPlan = try XCTUnwrap(preCore)
        XCTAssertEqual(originalPlan.menus[lower].count, 6)
        XCTAssertEqual(phases.last?.0, "finalized")
        XCTAssertNil(crowdedTransition)
    }

    func testHistoricalCrowdedCompleteMenuStillExercisesCoreRelocation() throws {
        let persona = personas[1]
        let result = analysis(for: persona)
        let intent = service.trainingIntentPlan(from: result)
        // Reconstructed from d319e9a's synthetic week: reverse its core relocation.
        // Blueprint/context are explicit test inputs, not captured historical objects.
        // Integer seven preserves the original scarce quad budget after fractional rounding.
        let blueprint = withQuadBudget(service.programBlueprint(for: intent, weekNumber: 1), target: 7)
        let url = try XCTUnwrap(Bundle.module.url(forResource: "historical-crowded-core-week", withExtension: "json"))
        let days = try JSONDecoder().decode([WorkoutDayResponse].self, from: Data(contentsOf: url))
        let historicalMenus: [[ClaudeService.PreSelectedExercise]] = days.map { day in day.exercises.map {
            .init(exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget,
                movementPattern: service.exerciseMetadata(for: $0).movementPattern,
                role: service.proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget),
                prescribedSets: $0.sets)
        } }
        func signature(_ value: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
            value.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
        }
        // Preserve historical identities/doses, but use the explicit current order policy.
        // Otherwise an unrelated old fly-before-row order makes the relocation screen fail.
        let menus = service.reorderedMenusForSessionFlow(historicalMenus, blueprint: blueprint,
            trainingIntent: intent, lockedPrefixCounts: Array(repeating: 0, count: 7))
        XCTAssertEqual(signature(menus).map { $0.sorted() }, signature(historicalMenus).map { $0.sorted() })
        XCTAssertEqual(menus.map(\.count), [6, 7, 0, 7, 0, 5, 0])
        var admission: ClaudeService.RoleFloorAdmission = .unassessed
        let allocated = service.allocateWeeklySetPrescription(menus, blueprint: blueprint, weekNumber: 1,
            roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
        guard admission == .admitted, signature(allocated) == signature(menus) else {
            return XCTFail("Historical menu must fund exactly before testing relocation: \(admission), \(signature(allocated))")
        }
        let baseline = ClaudeService.SubstitutionPlanningBaseline(menus: menus, blueprint: blueprint, weekNumber: 1,
            lockedPrefixCounts: Array(repeating: 0, count: 7),
            retainedKeysByDay: Array(repeating: Set<String>(), count: 7), exerciseHistory: nil,
            selectionFocusIntents: blueprint.dayPlans.map { service.focusIntentForArea($0.focusArea, within: intent) },
            roleFloorAdmission: admission)
        try recordCoreRelocationTrial(planned: baseline, intent: intent, result: result, lower: 1)
    }

    private func withQuadBudget(_ blueprint: ClaudeService.ProgramBlueprint, target: Double) -> ClaudeService.ProgramBlueprint {
        return ClaudeService.ProgramBlueprint(
            evidenceVersion: blueprint.evidenceVersion,
            splitRecommendation: blueprint.splitRecommendation,
            weeklyTrainingDays: blueprint.weeklyTrainingDays,
            priorityAllocations: blueprint.priorityAllocations.map { allocation in
                guard allocation.area == "Quads" else { return allocation }
                return .init(area: allocation.area, priorityLevel: allocation.priorityLevel,
                    rationale: allocation.rationale, targetFrequency: allocation.targetFrequency,
                    targetExerciseSlots: allocation.targetExerciseSlots, directSetTarget: target,
                    weightedStimulusTarget: allocation.weightedStimulusTarget,
                    maxPerSessionDirectSets: allocation.maxPerSessionDirectSets,
                    maxFocusSessionDirectSets: allocation.maxFocusSessionDirectSets,
                    preferredStyles: allocation.preferredStyles,
                    preferredMovementPatterns: allocation.preferredMovementPatterns,
                    volumeBias: allocation.volumeBias, directWorkBias: allocation.directWorkBias)
            }, dayPlans: blueprint.dayPlans, topLeverageChange: blueprint.topLeverageChange,
            posturalFocus: blueprint.posturalFocus, injuryRiskFocus: blueprint.injuryRiskFocus,
            programmingNotes: blueprint.programmingNotes, calibration: blueprint.calibration)
    }

    /// Replay the reconstructed pre-core plan independently of live placement selection.
    /// The six-exercise receiver limit does not prove real-world session comfort.
    private func recordCoreRelocationTrial(planned: ClaudeService.SubstitutionPlanningBaseline,
        intent: ClaudeService.TrainingIntentPlan, result: BodyAnalysisResult, lower: Int) throws {
        let baseline = planned.menus
        let blueprint = planned.blueprint
        func signature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
            menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
        }
        let original = signature(baseline)
        let pull = try XCTUnwrap(blueprint.dayPlans.indices.first {
            !blueprint.dayPlans[$0].isRestDay && service.canonicalTrainingStyle(blueprint.dayPlans[$0].style) == "Pull"
        })
        let slot = try XCTUnwrap(baseline[lower].indices.first { baseline[lower][$0].role == .core })
        let moved = baseline[lower][slot]
        XCTAssertTrue(service.isDirectCoreHypertrophyMovement(exerciseName: moved.exerciseName,
            muscleTarget: moved.muscleTarget, reps: "10-15"))
        XCTAssertFalse(service.isProtectedAppearance(role: moved.role, slot: slot,
            style: blueprint.dayPlans[lower].style, lockedPrefixCount: planned.lockedPrefixCounts[lower]))
        XCTAssertFalse(planned.retainedKeysByDay[lower].contains(ExerciseWeightEntry.canonicalLookupKey(moved.exerciseName)))
        var candidate = baseline
        candidate[lower].remove(at: slot)
        candidate[pull].append(moved)
        XCTAssertEqual(signature(candidate).flatMap { $0 }.sorted(), original.flatMap { $0 }.sorted(),
            "Relocation must preserve every exercise field and dose, not add or delete work")
        XCTAssertEqual(signature(candidate)[lower], original[lower].enumerated().filter { $0.offset != slot }.map(\.element))
        XCTAssertEqual(Array(signature(candidate)[pull].dropLast()), original[pull])
        XCTAssertEqual(signature(candidate)[pull].last, original[lower][slot])
        for day in baseline.indices where day != lower && day != pull {
            XCTAssertEqual(signature(candidate)[day], original[day])
        }
        XCTAssertEqual(candidate[lower].count, 6)
        XCTAssertEqual(candidate[pull].count, 6)
        XCTAssertEqual(signature(service.reorderedMenusForSessionFlow(candidate, blueprint: blueprint,
            trainingIntent: intent, lockedPrefixCounts: planned.lockedPrefixCounts)), signature(candidate))
        let before = try service.validatedProceduralWeekOneProgram(from: result, trainingIntent: intent,
            blueprint: blueprint, exerciseMenus: baseline)
        let after = try service.validatedProceduralWeekOneProgram(from: result, trainingIntent: intent,
            blueprint: blueprint, exerciseMenus: candidate)
        XCTAssertEqual(after.days.map { $0.exercises.map(\.exerciseName) }, candidate.map { $0.map(\.exerciseName) })
        XCTAssertEqual(after.days.map { $0.exercises.map(\.muscleTarget) }, candidate.map { $0.map(\.muscleTarget) })
        XCTAssertEqual(after.days.map { $0.exercises.map(\.sets) }, candidate.map { $0.map(\.prescribedSets) })
        let limits = service.setBudgetLimits(for: blueprint)
        var report = ["RAW_UNDECLARED_CORE_CONTROL week=1 sourceDay=\(lower + 1) destinationDay=\(pull + 1) moved=\(moved.exerciseName) sets=\(moved.prescribedSets) NOT_ADOPTED",
            "BASELINE \(original)", "CANDIDATE \(signature(candidate))"]
        let dose = service.compareAllocatedDoseOnly(candidate, baseline: baseline, blueprint: blueprint, weekNumber: 1)
        XCTAssertEqual(dose, .dosePreserved(improvesMaintenanceMinimum: false), "Relocation must not buy comfort by losing useful dose")
        report.append("DOSE \(dose)")
        for day in candidate.indices {
            if blueprint.dayPlans[day].isRestDay { XCTAssertTrue(candidate[day].isEmpty) }
            let keys = candidate[day].map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) }
            XCTAssertEqual(Set(keys).count, keys.count)
            let fatigue = service.estimatedDayFatigue(for: after.days[day].exercises)
            let minutes = service.estimatedSessionMinutes(for: after.days[day])
            XCTAssertLessThanOrEqual(fatigue, limits.fatigue[day], "Trial exceeds modeled fatigue on day \(day + 1)")
            if day == lower || day == pull {
                // Conservative experiment screen only. Estimates are not measured gym times,
                // and this does not restore the removed production time-trimming rule.
                XCTAssertLessThanOrEqual(minutes, blueprint.dayPlans[day].targetSessionMinutes,
                    "Trial exceeds the affected day's reference time estimate")
            }
            report.append("DAY \(day + 1) counts=\(baseline[day].count)->\(candidate[day].count) fatigue=\(service.estimatedDayFatigue(for: before.days[day].exercises))->\(fatigue) fatigueCap=\(limits.fatigue[day]) estimatedMinutes=\(service.estimatedSessionMinutes(for: before.days[day]))->\(minutes) referenceMinutes=\(blueprint.dayPlans[day].targetSessionMinutes)")
        }
        // Preserve every major group's exposure-day count as well as weekly work.
        for group in service.majorMuscleGroups {
            let aliases = service.normalizedGroupAliases(forSeed: group.seed)
            func positions(_ days: [WorkoutDayResponse]) -> [Int] {
                days.indices.filter { day in days[day].exercises.contains {
                    service.exerciseDirectlyTargets(groupAliases: aliases, exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget)
                } }
            }
            let oldPositions = positions(before.days), newPositions = positions(after.days)
            XCTAssertGreaterThanOrEqual(newPositions.count, oldPositions.count)
            report.append("COVERAGE \(group.label) days=\(oldPositions.map { $0 + 1 })->\(newPositions.map { $0 + 1 })")
        }
        func corePositions(_ days: [WorkoutDayResponse]) -> [Int] {
            days.indices.filter { day in days[day].exercises.contains {
                service.proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
            } }
        }
        func cyclicGaps(_ positions: [Int]) -> [Int] {
            guard !positions.isEmpty else { return [] }
            return positions.indices.map { index in
                index + 1 < positions.count ? positions[index + 1] - positions[index] : 7 + positions[0] - positions[index]
            }.sorted()
        }
        let oldGaps = cyclicGaps(corePositions(before.days)), newGaps = cyclicGaps(corePositions(after.days))
        XCTAssertEqual(newGaps, oldGaps, "This fixture must preserve spacing, including repeated-week boundary")
        report.append("CORE_SPACING days=\(corePositions(before.days).map { $0 + 1 })->\(corePositions(after.days).map { $0 + 1 }) cyclicDayGaps=\(oldGaps)->\(newGaps); not a next-week history simulation")
        let deliveredCore = try XCTUnwrap(after.days[pull].exercises.last)
        report.append("STYLE currentPullMatcher=\(service.exerciseMatchesDayStyle(deliveredCore, style: blueprint.dayPlans[pull].style)); test permission does not alter production eligibility")
        let oldIssues = service.validateProgramResponse(before, blueprint: blueprint, expectedExerciseMenus: baseline)
        let newIssues = service.validateProgramResponse(after, blueprint: blueprint, expectedExerciseMenus: candidate)
        // The first executed experiment (35035225961) failed only because the original
        // blueprint did not declare the added support work. Keep that rejected control.
        let offTheme = "Day \(pull + 1) includes low-value filler that does not clearly support the Pull theme or the planned priorities (\(moved.exerciseName)). Trim the noise and keep the session more disciplined."
        XCTAssertEqual(Set(newIssues).subtracting(Set(oldIssues)), Set([offTheme]))
        report.append("FINDINGS_BEFORE \(oldIssues)")
        report.append("FINDINGS_AFTER \(newIssues)")
        var admission: ClaudeService.RoleFloorAdmission = .unassessed
        let reallocated = service.allocateWeeklySetPrescription(candidate, blueprint: blueprint, weekNumber: 1,
            lockedPrefixCounts: planned.lockedPrefixCounts, roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
        report.append("REALLOCATION admission=\(admission) exactCandidatePreserved=\(signature(reallocated) == signature(candidate)) menus=\(signature(reallocated))")
        XCTAssertEqual(admission, .admitted)
        XCTAssertEqual(signature(reallocated), signature(candidate), "Normal allocation must preserve the entire proposed plan")
        XCTAssertEqual(signature(planned.menus), original, "The live baseline is untouched by every trial")

        // Second experiment: declare Core as support on this complete candidate day.
        // No global style filter, catalog, priority target, budget or live plan changes.
        // This is a hand-built candidate, NOT proof that production selects or propagates it.
        var declaredDays = blueprint.dayPlans
        let receiver = declaredDays[pull]
        declaredDays[pull] = .init(dayIndex: receiver.dayIndex, style: receiver.style,
            focusArea: receiver.focusArea, supportAreas: receiver.supportAreas + ["Core/Abs"],
            targetFatigueCap: receiver.targetFatigueCap, targetSessionMinutes: receiver.targetSessionMinutes,
            targetPrioritySlots: receiver.targetPrioritySlots, emphasisPatterns: receiver.emphasisPatterns,
            isRestDay: receiver.isRestDay)
        let declaredBlueprint = ClaudeService.ProgramBlueprint(evidenceVersion: blueprint.evidenceVersion,
            splitRecommendation: blueprint.splitRecommendation, weeklyTrainingDays: blueprint.weeklyTrainingDays,
            priorityAllocations: blueprint.priorityAllocations, dayPlans: declaredDays,
            topLeverageChange: blueprint.topLeverageChange, posturalFocus: blueprint.posturalFocus,
            injuryRiskFocus: blueprint.injuryRiskFocus, programmingNotes: blueprint.programmingNotes,
            calibration: blueprint.calibration)
        // The reusable proposal must reproduce the hand-built control exactly. It does
        // not allocate, deliver, or adopt: those independent checks stay below.
        let firstProposal = service.proposeCoreRelocationTrial(planned,
            sourceDay: lower, sourceSlot: slot, destinationDay: pull, trainingIntent: intent)
        guard case .candidate(let proposed) = firstProposal else {
            return XCTFail("Measured candidate refused: \(firstProposal)")
        }
        XCTAssertEqual(signature(proposed.menus), signature(candidate))
        XCTAssertEqual(proposed.blueprint, declaredBlueprint)
        XCTAssertEqual(proposed.roleFloorAdmission, .unassessed, "Proposing a placement does not certify fresh allocation")
        func variant(menus: [[ClaudeService.PreSelectedExercise]]? = nil,
            blueprint replacementBlueprint: ClaudeService.ProgramBlueprint? = nil,
            locks: [Int]? = nil, retained: [Set<String>]? = nil,
            history: ClaudeService.ExerciseHistoryContext? = nil, week: Int = 1,
            admission: ClaudeService.RoleFloorAdmission = .admitted) -> ClaudeService.SubstitutionPlanningBaseline {
            .init(menus: menus ?? planned.menus, blueprint: replacementBlueprint ?? planned.blueprint, weekNumber: week,
                lockedPrefixCounts: locks ?? planned.lockedPrefixCounts,
                retainedKeysByDay: retained ?? planned.retainedKeysByDay,
                exerciseHistory: history, selectionFocusIntents: planned.selectionFocusIntents,
                roleFloorAdmission: admission)
        }
        func expectRefusal(_ plan: ClaudeService.SubstitutionPlanningBaseline,
            _ reason: ClaudeService.CoreRelocationRefusal, file: StaticString = #filePath, line: UInt = #line) {
            guard case .refused(let actual) = service.proposeCoreRelocationTrial(plan,
                sourceDay: lower, sourceSlot: slot, destinationDay: pull, trainingIntent: intent) else {
                return XCTFail("Forbidden relocation returned a candidate: \(reason)", file: file, line: line)
            }
            XCTAssertEqual(actual, reason, file: file, line: line)
        }
        // No dropping a destination exercise or reducing dosage to squeeze core in.
        for receiverCount in [6, 7] {
            var full = baseline
            full[pull].append(contentsOf: baseline[0].prefix(receiverCount - full[pull].count))
            XCTAssertEqual(Set(full[pull].map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) }).count, receiverCount)
            expectRefusal(variant(menus: full), .receiverCeiling)
            XCTAssertEqual(full[pull].count, receiverCount)
        }
        var locks = planned.lockedPrefixCounts
        locks[lower] = baseline[lower].count
        expectRefusal(variant(locks: locks), .protectedSource)
        let coreKey = ExerciseWeightEntry.canonicalLookupKey(moved.exerciseName)
        var retained = planned.retainedKeysByDay
        retained[lower].insert(coreKey)
        expectRefusal(variant(retained: retained), .protectedSource)
        let pain = ClaudeService.ExerciseHistoryContext(painExercises: [coreKey], equipmentSkipExercises: [],
            priorMesocycleExercises: [], mesocycleIndex: 0)
        expectRefusal(variant(history: pain), .painExcluded)
        expectRefusal(variant(week: 4), .unsupportedWeek)
        expectRefusal(variant(admission: .unassessed), .baselineNotAdmitted)
        expectRefusal(variant(locks: []), .invalidContext)
        var missingDay = baseline
        missingDay[0] = []
        var missingDayLocks = planned.lockedPrefixCounts
        missingDayLocks[0] = 0
        expectRefusal(variant(menus: missingDay, locks: missingDayLocks), .invalidContext)
        var duplicate = baseline
        duplicate[pull][duplicate[pull].count - 1] = moved
        expectRefusal(variant(menus: duplicate), .duplicateIdentity)
        let otherCoreDay = try XCTUnwrap(baseline.indices.first { day in
            day != lower && baseline[day].last?.role == .core
        })
        let otherCore = try XCTUnwrap(baseline[otherCoreDay].last)
        var reducedExposure = baseline
        reducedExposure[pull][reducedExposure[pull].count - 1] = otherCore
        expectRefusal(variant(menus: reducedExposure), .exposureLoss)
        var changedSpacing = baseline
        changedSpacing[otherCoreDay].removeLast()
        changedSpacing[0].append(otherCore)
        expectRefusal(variant(menus: changedSpacing), .spacingChange)
        var smallReceiver = baseline
        smallReceiver[pull].removeLast()
        expectRefusal(variant(menus: smallReceiver), .receiverSize)
        var nonCore = baseline
        nonCore[lower][slot] = .init(exerciseName: moved.exerciseName, muscleTarget: moved.muscleTarget,
            movementPattern: moved.movementPattern, role: .accessory, prescribedSets: moved.prescribedSets)
        expectRefusal(variant(menus: nonCore), .sourcePlacement)
        XCTAssertEqual(planned.lockedPrefixCounts[pull], 0, "This order-control fixture has no retained prefix")
        var misordered = baseline
        misordered[pull].swapAt(0, misordered[pull].count - 1)
        expectRefusal(variant(menus: misordered), .orderChange)
        var undosed = baseline
        undosed[lower][slot] = .init(exerciseName: moved.exerciseName, muscleTarget: moved.muscleTarget,
            movementPattern: moved.movementPattern, role: moved.role, prescribedSets: 0)
        expectRefusal(variant(menus: undosed), .doseChange)
        let corePriority = ClaudeService.BlueprintPriorityAllocation(area: "Core/Abs", priorityLevel: "High",
            rationale: "Adversarial test: preserve this day's priority dose", targetFrequency: 2,
            targetExerciseSlots: 2, directSetTarget: 6, weightedStimulusTarget: 6,
            maxPerSessionDirectSets: 6, maxFocusSessionDirectSets: 6,
            preferredStyles: ["Lower", "Pull"], preferredMovementPatterns: [moved.movementPattern],
            volumeBias: "", directWorkBias: "")
        let prioritizedCoreBlueprint = ClaudeService.ProgramBlueprint(evidenceVersion: blueprint.evidenceVersion,
            splitRecommendation: blueprint.splitRecommendation, weeklyTrainingDays: blueprint.weeklyTrainingDays,
            priorityAllocations: blueprint.priorityAllocations + [corePriority], dayPlans: blueprint.dayPlans,
            topLeverageChange: blueprint.topLeverageChange, posturalFocus: blueprint.posturalFocus,
            injuryRiskFocus: blueprint.injuryRiskFocus, programmingNotes: blueprint.programmingNotes,
            calibration: blueprint.calibration)
        XCTAssertEqual(service.compareAllocatedDoseOnly(candidate, baseline: baseline,
            blueprint: prioritizedCoreBlueprint, weekNumber: 1),
            .rejected(.sessionPriority(day: lower, area: "Core/Abs")))
        expectRefusal(variant(blueprint: prioritizedCoreBlueprint), .doseChange)
        let declaredAfter = try service.validatedProceduralWeekOneProgram(from: result, trainingIntent: intent,
            blueprint: declaredBlueprint, exerciseMenus: candidate)
        XCTAssertEqual(declaredAfter.days.map { $0.exercises.map(\.exerciseName) }, after.days.map { $0.exercises.map(\.exerciseName) })
        XCTAssertEqual(declaredAfter.days.map { $0.exercises.map(\.muscleTarget) }, after.days.map { $0.exercises.map(\.muscleTarget) })
        XCTAssertEqual(declaredAfter.days.map { $0.exercises.map(\.sets) }, after.days.map { $0.exercises.map(\.sets) })
        let declaredIssues = service.validateProgramResponse(declaredAfter, blueprint: declaredBlueprint, expectedExerciseMenus: candidate)
        XCTAssertTrue(Set(declaredIssues).subtracting(Set(oldIssues)).isEmpty,
            "Declared-support experiment introduces findings: \(declaredIssues)")
        XCTAssertEqual(service.compareAllocatedDoseOnly(candidate, baseline: baseline, blueprint: declaredBlueprint,
            weekNumber: 1), .dosePreserved(improvesMaintenanceMinimum: false))
        var declaredAdmission: ClaudeService.RoleFloorAdmission = .unassessed
        var declaredReceipts: [SetFundingObservation] = []
        let declaredAllocation = service.allocateWeeklySetPrescription(candidate, blueprint: declaredBlueprint,
            weekNumber: 1, lockedPrefixCounts: planned.lockedPrefixCounts,
            setFundingReport: { declaredReceipts = $0 },
            roleFloorAdmissionReport: { declaredAdmission = $0 }, publishConflictLogs: false)
        XCTAssertEqual(declaredAdmission, .admitted)
        XCTAssertEqual(signature(declaredAllocation), signature(candidate))
        let baselineMessages = ["Baseline diagnostic retained on refusal"]
        let baselineReceipts = [SetFundingObservation(dayIndex: lower, exerciseIndex: slot,
            exerciseName: moved.exerciseName, muscleTarget: moved.muscleTarget,
            prescribedSets: moved.prescribedSets, rejection: nil)]
        func finalize(_ input: ClaudeService.SubstitutionPlanningBaseline,
            previous: [WorkoutDayResponse]? = nil, collect: Bool = true) -> ClaudeService.CoreRelocationFinalization {
            service.finalizeCoreRelocation(input, sourceDay: lower, sourceSlot: slot,
                destinationDay: pull, trainingIntent: intent, previousWeekDays: previous,
                baselineMessages: baselineMessages, baselineReceipts: baselineReceipts, collectFunding: collect)
        }
        let finalized = finalize(planned)
        XCTAssertEqual(finalized.decision, .adopted)
        XCTAssertEqual(finalized.plan.blueprint, declaredBlueprint)
        XCTAssertEqual(signature(finalized.plan.menus), signature(candidate))
        XCTAssertEqual(finalized.plan.roleFloorAdmission, .admitted)
        XCTAssertEqual(finalized.receipts, declaredReceipts, "Accepted receipts must use new day/slot positions")
        XCTAssertFalse(finalized.messages.contains(baselineMessages[0]))
        let automatic = service.finalizeFirstCoreRelocation(planned, trainingIntent: intent,
            previousWeekDays: nil, baselineMessages: baselineMessages, baselineReceipts: baselineReceipts,
            collectFunding: true)
        XCTAssertEqual(automatic.decision, .adopted)
        XCTAssertEqual(automatic.plan.blueprint, declaredBlueprint)
        XCTAssertEqual(signature(automatic.plan.menus), signature(candidate))
        XCTAssertEqual(automatic.receipts, declaredReceipts)
        let withoutObserver = finalize(planned, collect: false)
        XCTAssertEqual(withoutObserver.decision, finalized.decision)
        XCTAssertEqual(withoutObserver.plan.blueprint, finalized.plan.blueprint)
        XCTAssertEqual(signature(withoutObserver.plan.menus), signature(finalized.plan.menus))
        XCTAssertEqual(withoutObserver.messages, finalized.messages)
        XCTAssertTrue(withoutObserver.receipts.isEmpty)
        report.append("CORE_ACCEPTANCE_BOUNDARY decision=\(finalized.decision) receiptParity=\(finalized.receipts == declaredReceipts) observerParity=\(signature(withoutObserver.plan.menus) == signature(finalized.plan.menus)); test invocation only, no live adoption")
        func expectRollback(_ input: ClaudeService.SubstitutionPlanningBaseline,
            previous: [WorkoutDayResponse]? = nil, reason: ClaudeService.CoreRelocationDecision,
            file: StaticString = #filePath, line: UInt = #line) {
            let refused = finalize(input, previous: previous)
            XCTAssertEqual(refused.decision, reason, file: file, line: line)
            XCTAssertEqual(refused.plan.blueprint, input.blueprint, file: file, line: line)
            XCTAssertEqual(signature(refused.plan.menus), signature(input.menus), file: file, line: line)
            XCTAssertEqual(refused.plan.roleFloorAdmission, input.roleFloorAdmission, file: file, line: line)
            XCTAssertEqual(refused.plan.lockedPrefixCounts, input.lockedPrefixCounts, file: file, line: line)
            XCTAssertEqual(refused.plan.retainedKeysByDay, input.retainedKeysByDay, file: file, line: line)
            XCTAssertEqual(refused.messages, baselineMessages, file: file, line: line)
            XCTAssertEqual(refused.receipts, baselineReceipts, file: file, line: line)
        }
        expectRollback(variant(history: pain), reason: .proposal(.painExcluded))
        expectRollback(variant(retained: retained), reason: .proposal(.protectedSource))
        expectRollback(planned, previous: before.days, reason: .invalidPreviousWeek)
        var lowerCoreFloor = baseline
        lowerCoreFloor[lower][slot].prescribedSets = service.minimumSetFloor(
            forExerciseName: moved.exerciseName, muscleTarget: moved.muscleTarget)
        XCTAssertLessThan(lowerCoreFloor[lower][slot].prescribedSets, moved.prescribedSets)
        let floorBaseline = variant(menus: lowerCoreFloor)
        guard case .candidate(let floorProposal) = service.proposeCoreRelocationTrial(floorBaseline,
            sourceDay: lower, sourceSlot: slot, destinationDay: pull, trainingIntent: intent) else {
            return XCTFail("Allocation-change control must first pass proposal checks")
        }
        var floorAdmission: ClaudeService.RoleFloorAdmission = .unassessed
        let refundedFloor = service.allocateWeeklySetPrescription(floorProposal.menus,
            blueprint: floorProposal.blueprint, weekNumber: 1, lockedPrefixCounts: floorProposal.lockedPrefixCounts,
            roleFloorAdmissionReport: { floorAdmission = $0 }, publishConflictLogs: false)
        XCTAssertEqual(floorAdmission, .admitted)
        XCTAssertNotEqual(signature(refundedFloor), signature(floorProposal.menus),
            "This control must make the real allocator change the proposed dose")
        expectRollback(floorBaseline, reason: .allocationChanged)
        let wrapperRefusal = service.finalizeFirstCoreRelocation(floorBaseline, trainingIntent: intent,
            previousWeekDays: nil, baselineMessages: baselineMessages, baselineReceipts: baselineReceipts,
            collectFunding: true)
        XCTAssertEqual(wrapperRefusal.decision, .allocationChanged)
        XCTAssertEqual(signature(wrapperRefusal.plan.menus), signature(floorBaseline.menus))
        XCTAssertEqual(wrapperRefusal.plan.blueprint, floorBaseline.blueprint)
        XCTAssertEqual(wrapperRefusal.messages, baselineMessages)
        XCTAssertEqual(wrapperRefusal.receipts, baselineReceipts)
        let protectedWrapper = service.finalizeFirstCoreRelocation(variant(retained: retained), trainingIntent: intent,
            previousWeekDays: nil, baselineMessages: baselineMessages, baselineReceipts: baselineReceipts,
            collectFunding: true)
        XCTAssertEqual(protectedWrapper.decision, .noEligiblePlacement)
        XCTAssertEqual(signature(protectedWrapper.plan.menus), signature(baseline))
        XCTAssertEqual(protectedWrapper.receipts, baselineReceipts)
        let malformedWrapper = service.finalizeFirstCoreRelocation(variant(locks: []), trainingIntent: intent,
            previousWeekDays: nil, baselineMessages: baselineMessages, baselineReceipts: baselineReceipts,
            collectFunding: true)
        XCTAssertEqual(malformedWrapper.decision, .proposal(.invalidContext))
        XCTAssertEqual(signature(malformedWrapper.plan.menus), signature(baseline))
        XCTAssertEqual(service.verifyCoreRelocationAllocation(candidate, admission: .unassessed,
            proposed: proposed), .finalNotAdmitted(.unassessed))
        var alteredAllocation = candidate
        alteredAllocation[pull][alteredAllocation[pull].count - 1].prescribedSets -= 1
        XCTAssertEqual(service.verifyCoreRelocationAllocation(alteredAllocation, admission: .admitted,
            proposed: proposed), .allocationChanged)
        let originalWeek = WorkoutWeekResponse(weekSummary: "Control", days: before.days)
        let proposedWeek = WorkoutWeekResponse(weekSummary: "Control", days: declaredAfter.days)
        XCTAssertNil(service.verifyCoreRelocationDelivery(original: originalWeek, candidate: proposedWeek,
            baseline: planned, proposed: proposed, previousWeekDays: nil))
        XCTAssertEqual(service.verifyCoreRelocationDelivery(original: originalWeek, candidate: originalWeek,
            baseline: planned, proposed: proposed, previousWeekDays: nil), .deliveryMismatch)
        XCTAssertEqual(service.verifyCoreRelocationDelivery(original: originalWeek, candidate: originalWeek,
            baseline: planned, proposed: planned, previousWeekDays: nil), .findingsNotImproved)
        for day in [lower, pull] {
            XCTAssertLessThanOrEqual(service.estimatedSessionMinutes(for: declaredAfter.days[day]), declaredDays[day].targetSessionMinutes)
            XCTAssertLessThanOrEqual(service.estimatedDayFatigue(for: declaredAfter.days[day].exercises), limits.fatigue[day])
        }
        report.append("DECLARED_SUPPORT_REPLAY day=\(pull + 1) support=\(receiver.supportAreas)->\(declaredDays[pull].supportAreas) findings=\(declaredIssues) admission=\(declaredAdmission) exactCandidatePreserved=\(signature(declaredAllocation) == signature(candidate))")
        try writeArtifactIfRequested(report.joined(separator: "\n"), environmentKey: "TRANSFORM_CORE_RELOCATION_OUTPUT")

        // Historical synthetic chain: explicitly fund the reconstructed crowded menu at
        // each phase. This is NOT a claim that current selection produces crowding.
        var previousExperimentalDays = declaredAfter.days
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func encodedDays(_ days: [WorkoutDayResponse]) throws -> String {
            String(decoding: try encoder.encode(days), as: UTF8.self)
        }
        let originalDeliveredExperiment = try encodedDays(declaredAfter.days)
        var chain = ["HISTORICAL_CORE_CHAIN; reconstructed crowded menus, synthetic zero locks/retention, integer quad budget; fresh phase allocation and actual delivered prior week; NOT naturally selected current menus",
            "ORIGINAL_WEEK1_BASELINE \(original)",
            "DELIVERED_EXPERIMENT_WEEK1 \(originalDeliveredExperiment)"]
        defer {
            do { try writeArtifactIfRequested(chain.joined(separator: "\n"), environmentKey: "TRANSFORM_CORE_CHAIN_OUTPUT") }
            catch { XCTFail("Could not preserve core chain diagnostic: \(error)") }
        }
        for week in 2...3 {
            XCTAssertEqual(previousExperimentalDays.count, 7, "Use the actual complete delivered previous week")
            XCTAssertEqual(previousExperimentalDays.map(\.dayNumber), Array(((week - 2) * 7 + 1)...((week - 1) * 7)))
            let previousSnapshot = try encodedDays(previousExperimentalDays)
            let nextBlueprint = withQuadBudget(service.programBlueprint(for: intent, weekNumber: week), target: 7)
            var historicalAdmission: ClaudeService.RoleFloorAdmission = .unassessed
            let historicalMenus = service.allocateWeeklySetPrescription(baseline, blueprint: nextBlueprint,
                weekNumber: week, roleFloorAdmissionReport: { historicalAdmission = $0 }, publishConflictLogs: false)
            guard historicalAdmission == .admitted else {
                return XCTFail("Historical week \(week) must fund before relocation: \(historicalAdmission)")
            }
            XCTAssertEqual(historicalMenus.map { $0.map(\.exerciseName) }, baseline.map { $0.map(\.exerciseName) },
                "Fresh phase allocation must not silently remove historical appearances")
            let next = ClaudeService.SubstitutionPlanningBaseline(menus: historicalMenus, blueprint: nextBlueprint,
                weekNumber: week, lockedPrefixCounts: Array(repeating: 0, count: 7),
                retainedKeysByDay: Array(repeating: Set<String>(), count: 7), exerciseHistory: nil,
                selectionFocusIntents: nextBlueprint.dayPlans.map { service.focusIntentForArea($0.focusArea, within: intent) },
                roleFloorAdmission: historicalAdmission)
            let nextSlot = try XCTUnwrap(next.menus[lower].indices.last)
            let nextProposal = service.proposeCoreRelocationTrial(next,
                sourceDay: lower, sourceSlot: nextSlot, destinationDay: pull, trainingIntent: intent)
            guard case .candidate(let relocated) = nextProposal else {
                return XCTFail("Week \(week) measured candidate refused: \(nextProposal)")
            }
            XCTAssertEqual(relocated.roleFloorAdmission, .unassessed)
            XCTAssertEqual(relocated.menus[lower].count, 6)
            XCTAssertEqual(relocated.menus[pull].count, 6)
            XCTAssertEqual(signature(relocated.menus).flatMap { $0 }.sorted(), signature(next.menus).flatMap { $0 }.sorted())
            XCTAssertEqual(service.compareAllocatedDoseOnly(relocated.menus, baseline: next.menus,
                blueprint: relocated.blueprint, weekNumber: week), .dosePreserved(improvesMaintenanceMinimum: false))
            let nextFinalized = service.finalizeCoreRelocation(next, sourceDay: lower,
                sourceSlot: nextSlot, destinationDay: pull, trainingIntent: intent,
                previousWeekDays: previousExperimentalDays, baselineMessages: [], baselineReceipts: [],
                collectFunding: true)
            XCTAssertEqual(nextFinalized.decision, .adopted)
            XCTAssertEqual(nextFinalized.plan.blueprint, relocated.blueprint)
            let automaticHistorical = service.finalizeFirstCoreRelocation(next, trainingIntent: intent,
                previousWeekDays: previousExperimentalDays, baselineMessages: [], baselineReceipts: [], collectFunding: true)
            XCTAssertEqual(automaticHistorical.decision, .adopted)
            XCTAssertEqual(automaticHistorical.plan.blueprint, nextFinalized.plan.blueprint)
            XCTAssertEqual(signature(automaticHistorical.plan.menus), signature(nextFinalized.plan.menus))
            XCTAssertEqual(automaticHistorical.receipts, nextFinalized.receipts)
            if week == 2 {
                XCTAssertEqual(nextSlot, slot, "Rollback helper must address the same last source slot")
                expectRollback(next, reason: .invalidPreviousWeek)
                expectRollback(next, previous: Array(previousExperimentalDays.dropLast()), reason: .invalidPreviousWeek)
                expectRollback(next, previous: Array(previousExperimentalDays.reversed()), reason: .invalidPreviousWeek)
                // Mirror the two sessions: cyclic spacing still passes, but the first
                // core day is now earlier relative to the actual previous delivery.
                func mirrored<T>(_ values: [T]) -> [T] {
                    var copy = values
                    copy.swapAt(lower, pull)
                    return copy
                }
                let mirroredDays = mirrored(next.blueprint.dayPlans).enumerated().map { index, day in
                    ClaudeService.BlueprintDayPlan(dayIndex: index + 1, style: day.style,
                        focusArea: day.focusArea, supportAreas: day.supportAreas,
                        targetFatigueCap: day.targetFatigueCap, targetSessionMinutes: day.targetSessionMinutes,
                        targetPrioritySlots: day.targetPrioritySlots, emphasisPatterns: day.emphasisPatterns,
                        isRestDay: day.isRestDay)
                }
                let nb = next.blueprint
                let mirroredBlueprint = ClaudeService.ProgramBlueprint(evidenceVersion: nb.evidenceVersion,
                    splitRecommendation: nb.splitRecommendation, weeklyTrainingDays: nb.weeklyTrainingDays,
                    priorityAllocations: nb.priorityAllocations, dayPlans: mirroredDays,
                    topLeverageChange: nb.topLeverageChange, posturalFocus: nb.posturalFocus,
                    injuryRiskFocus: nb.injuryRiskFocus, programmingNotes: nb.programmingNotes, calibration: nb.calibration)
                let mirroredPlan = ClaudeService.SubstitutionPlanningBaseline(menus: mirrored(next.menus),
                    blueprint: mirroredBlueprint, weekNumber: week,
                    lockedPrefixCounts: mirrored(next.lockedPrefixCounts), retainedKeysByDay: mirrored(next.retainedKeysByDay),
                    exerciseHistory: next.exerciseHistory, selectionFocusIntents: mirrored(next.selectionFocusIntents),
                    roleFloorAdmission: next.roleFloorAdmission)
                guard case .candidate = service.proposeCoreRelocationTrial(mirroredPlan,
                    sourceDay: pull, sourceSlot: nextSlot, destinationDay: lower, trainingIntent: intent) else {
                    return XCTFail("Boundary-refusal control must first pass within-week proposal checks")
                }
                let boundaryRefusal = service.finalizeCoreRelocation(mirroredPlan, sourceDay: pull,
                    sourceSlot: nextSlot, destinationDay: lower, trainingIntent: intent,
                    previousWeekDays: previousExperimentalDays, baselineMessages: baselineMessages,
                    baselineReceipts: baselineReceipts, collectFunding: true)
                XCTAssertEqual(boundaryRefusal.decision, .boundarySpacing)
                XCTAssertEqual(signature(boundaryRefusal.plan.menus), signature(mirroredPlan.menus))
                XCTAssertEqual(boundaryRefusal.plan.blueprint, mirroredBlueprint)
                XCTAssertEqual(boundaryRefusal.messages, baselineMessages)
                XCTAssertEqual(boundaryRefusal.receipts, baselineReceipts)
                // A relative no-shortening rule intentionally has the same verdict
                // regardless of which preceding day held the last core session.
                let previousLastIndex = try XCTUnwrap(previousExperimentalDays.indices.last { day in
                    previousExperimentalDays[day].exercises.contains {
                        service.proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
                    }
                })
                let previousRestIndex = try XCTUnwrap(previousExperimentalDays.indices.last {
                    previousExperimentalDays[$0].isRestDay
                })
                XCTAssertNotEqual(previousLastIndex, previousRestIndex)
                var shiftedPrevious = previousExperimentalDays
                shiftedPrevious.swapAt(previousLastIndex, previousRestIndex)
                shiftedPrevious = shiftedPrevious.enumerated().map { index, day in
                    WorkoutDayResponse(dayNumber: previousExperimentalDays[index].dayNumber,
                        dayName: day.dayName, muscleGroups: day.muscleGroups, isRestDay: day.isRestDay,
                        notes: day.notes, exercises: day.exercises)
                }
                let shiftedRefusal = service.finalizeCoreRelocation(mirroredPlan, sourceDay: pull,
                    sourceSlot: nextSlot, destinationDay: lower, trainingIntent: intent,
                    previousWeekDays: shiftedPrevious, baselineMessages: baselineMessages,
                    baselineReceipts: baselineReceipts, collectFunding: true)
                XCTAssertEqual(shiftedRefusal.decision, .boundarySpacing)
                XCTAssertEqual(signature(shiftedRefusal.plan.menus), signature(mirroredPlan.menus))
                XCTAssertEqual(shiftedRefusal.receipts, baselineReceipts)
                chain.append("WEEK \(week) MIRRORED_BOUNDARY_REFUSAL \(boundaryRefusal.decision) completeBaselineRetained=true")
            }
            let nextAdmission = nextFinalized.plan.roleFloorAdmission
            let reallocated = nextFinalized.plan.menus
            chain.append("WEEK \(week) CORE_ACCEPTANCE_BOUNDARY \(nextFinalized.decision); test invocation only")
            XCTAssertEqual(nextAdmission, .admitted)
            XCTAssertEqual(signature(reallocated), signature(relocated.menus))
            let dayStart = (week - 1) * 7 + 1, dayEnd = week * 7
            let delivered = try service.validatedProceduralWeek(weekNumber: week, dayStart: dayStart,
                dayEnd: dayEnd, splitType: intent.splitRecommendation, programName: "Core relocation chain experiment",
                trainingIntent: intent, blueprint: relocated.blueprint, previousWeekDays: previousExperimentalDays,
                exerciseMenus: relocated.menus)
            XCTAssertEqual(delivered.days.count, 7)
            XCTAssertEqual(delivered.days.map(\.dayNumber), Array(dayStart...dayEnd))
            XCTAssertEqual(delivered.days.map { $0.exercises.map(\.exerciseName) }, relocated.menus.map { $0.map(\.exerciseName) })
            XCTAssertEqual(delivered.days.map { $0.exercises.map(\.muscleTarget) }, relocated.menus.map { $0.map(\.muscleTarget) })
            XCTAssertEqual(delivered.days.map { $0.exercises.map(\.sets) }, relocated.menus.map { $0.map(\.prescribedSets) })
            for day in [lower, pull] {
                XCTAssertLessThanOrEqual(service.estimatedSessionMinutes(for: delivered.days[day]), relocated.blueprint.dayPlans[day].targetSessionMinutes)
                XCTAssertLessThanOrEqual(service.estimatedDayFatigue(for: delivered.days[day].exercises), service.setBudgetLimits(for: relocated.blueprint).fatigue[day])
            }
            // Compare the real delivered transition, not just a hypothetical repeated week.
            // Day numbers are ordinals, not logged calendar dates or medical recovery proof.
            let previousLastCore = try XCTUnwrap(previousExperimentalDays.last { day in day.exercises.contains {
                service.proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
            } }?.dayNumber)
            let baselineFirstCore = try XCTUnwrap(next.menus.indices.first { day in next.menus[day].contains {
                service.proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
            } }).advanced(by: dayStart)
            let deliveredFirstCore = try XCTUnwrap(delivered.days.first { day in day.exercises.contains {
                service.proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
            } }?.dayNumber)
            XCTAssertGreaterThanOrEqual(deliveredFirstCore - previousLastCore, baselineFirstCore - previousLastCore,
                "This trial must not shorten the actual prior-week core interval")
            chain.append("WEEK \(week) CORE_BOUNDARY previousLast=\(previousLastCore) baselineFirst=\(baselineFirstCore) deliveredFirst=\(deliveredFirstCore) baselineGap=\(baselineFirstCore - previousLastCore) deliveredGap=\(deliveredFirstCore - previousLastCore); ordinal days, not actual dates")
            XCTAssertEqual(try encodedDays(previousExperimentalDays), previousSnapshot, "Planning cannot mutate its previous-week input")
            chain.append("WEEK \(week) INPUT_PREVIOUS_DELIVERED \(previousSnapshot)")
            chain.append("WEEK \(week) PLAN admission=\(next.roleFloorAdmission) locks=\(next.lockedPrefixCounts) retainedKeys=\(next.retainedKeysByDay.map { $0.sorted() }) menus=\(signature(next.menus))")
            chain.append("WEEK \(week) REPEATED_PROPOSAL source=\(lower + dayStart) destination=\(pull + dayStart) receivingCeiling=6 admission=\(nextAdmission) exactReallocation=\(signature(reallocated) == signature(relocated.menus)) menus=\(signature(relocated.menus))")
            chain.append("WEEK \(week) HISTORICAL_FUNDING counts=\(historicalMenus.map(\.count)) menus=\(signature(historicalMenus)); synthetic context, not live selection")
            for previousDay in previousExperimentalDays where !previousDay.isRestDay {
                let style = service.canonicalTrainingStyle(service.inferredDayStyle(dayName: previousDay.dayName,
                    muscleGroups: previousDay.muscleGroups) ?? "Unknown")
                let styleEligible = service.retainedAnchorExercises(from: previousDay.exercises, style: style)
                for core in previousDay.exercises where service.proceduralExerciseRole(for: core.exerciseName, muscleTarget: core.muscleTarget) == .core {
                    chain.append("WEEK \(week) PRIOR_CORE day=\(previousDay.dayNumber) style=\(style) name=\(core.exerciseName) sets=\(core.sets) styleMatches=\(service.exerciseMatchesDayStyle(core, style: style)) inStyleFilteredRetentionPool=\(styleEligible.contains { $0.exerciseName == core.exerciseName && $0.muscleTarget == core.muscleTarget }); pool membership is not final retention")
                }
            }
            for day in delivered.days {
                let core = day.exercises.enumerated().filter {
                    service.proceduralExerciseRole(for: $0.element.exerciseName, muscleTarget: $0.element.muscleTarget) == .core
                }.map { "slot=\($0.offset + 1) name=\($0.element.exerciseName) target=\($0.element.muscleTarget) sets=\($0.element.sets)" }
                chain.append("WEEK \(week) DELIVERED_DAY \(day.dayNumber) name=\(day.dayName) count=\(day.exercises.count) core=\(core)")
            }
            let findings = service.validateWeekResponse(delivered, dayStart: dayStart, dayEnd: dayEnd,
                previousWeekDays: previousExperimentalDays, blueprint: relocated.blueprint, expectedExerciseMenus: relocated.menus)
            // This reconstructed historical week intentionally keeps a different seven-slot
            // Upper day. The live six-slot rule must flag it; relocation only fixes the Lower
            // receiver and must not introduce any other finding.
            XCTAssertEqual(findings, ["Day \(dayStart + 3) must have 5-6 exercises."],
                "The historical fixture should retain only its pre-existing Upper-day over-cap finding")
            chain.append("WEEK \(week) FINDINGS \(findings)")
            chain.append("WEEK \(week) DELIVERED \(try encodedDays(delivered.days))")
            previousExperimentalDays = delivered.days
        }
        XCTAssertEqual(signature(planned.menus), original)
        XCTAssertEqual(try encodedDays(declaredAfter.days), originalDeliveredExperiment)

        // Independent current-policy chain starts at the same actual Week 1 delivery.
        // Automatic refusal/no eligible placement is valid when no crowded source exists.
        var previousLiveDays = declaredAfter.days
        chain.append("CURRENT_POLICY_CHAIN; actual previous delivery, normal blueprint, exerciseHistory=nil; no required crowding or adoption")
        for week in 2...3 {
            let previousSnapshot = try encodedDays(previousLiveDays)
            let liveBlueprint = service.programBlueprint(for: intent, weekNumber: week)
            var captured: ClaudeService.SubstitutionPlanningBaseline?
            var capturedFinal: ClaudeService.CoreRelocationFinalization?
            var preCoreFinalization: ClaudeService.PressdownFinalization?
            var liveReceipts: [SetFundingObservation] = []
            var callbackCount = 0
            let liveNext = service.preSelectedExercisePlan(for: liveBlueprint, trainingIntent: intent,
                weekNumber: week, previousWeekDays: previousLiveDays, exerciseHistory: nil,
                setFundingReport: { liveReceipts = $0 },
                pressdownPlanningReport: { _, result in preCoreFinalization = result },
                corePlanningReport: { captured = $0; capturedFinal = $1; callbackCount += 1 })
            XCTAssertEqual(callbackCount, 1)
            let liveControl = try XCTUnwrap(captured)
            let liveFinal = try XCTUnwrap(capturedFinal)
            let coreInputs = try XCTUnwrap(preCoreFinalization)
            let independent = service.finalizeFirstCoreRelocation(liveControl, trainingIntent: intent,
                previousWeekDays: previousLiveDays, baselineMessages: coreInputs.messages,
                baselineReceipts: coreInputs.receipts, collectFunding: true)
            XCTAssertEqual(independent.decision, liveFinal.decision)
            XCTAssertEqual(independent.plan.blueprint, liveNext.blueprint)
            XCTAssertEqual(signature(independent.plan.menus), signature(liveNext.menus))
            XCTAssertEqual(independent.plan.roleFloorAdmission, liveNext.roleFloorAdmission)
            XCTAssertEqual(independent.plan.lockedPrefixCounts, liveNext.lockedPrefixCounts)
            XCTAssertEqual(independent.plan.retainedKeysByDay, liveNext.retainedKeysByDay)
            XCTAssertEqual(liveReceipts, liveFinal.receipts)
            XCTAssertEqual(independent.receipts, liveFinal.receipts)
            XCTAssertEqual(independent.messages, liveFinal.messages)
            if independent.decision == .adopted {
                XCTAssertEqual(service.compareAllocatedDoseOnly(liveNext.menus, baseline: liveControl.menus,
                    blueprint: liveNext.blueprint, weekNumber: week), .dosePreserved(improvesMaintenanceMinimum: false))
            } else {
                // A refusal retains the complete baseline, including its actual diagnostics.
                XCTAssertEqual(signature(liveNext.menus), signature(liveControl.menus))
                XCTAssertEqual(liveNext.blueprint, liveControl.blueprint)
                XCTAssertEqual(independent.receipts, coreInputs.receipts)
            }
            let dayStart = (week - 1) * 7 + 1
            let liveDelivered = try service.validatedProceduralWeek(weekNumber: week, dayStart: dayStart,
                dayEnd: week * 7, splitType: intent.splitRecommendation, programName: "Current-policy chain",
                trainingIntent: intent, blueprint: liveNext.blueprint, previousWeekDays: previousLiveDays,
                exerciseMenus: liveNext.menus)
            XCTAssertEqual(liveDelivered.days.map(\.dayNumber), Array(dayStart...(week * 7)))
            XCTAssertEqual(liveDelivered.days.map { $0.exercises.map(\.exerciseName) }, liveNext.menus.map { $0.map(\.exerciseName) })
            XCTAssertEqual(liveDelivered.days.map { $0.exercises.map(\.muscleTarget) }, liveNext.menus.map { $0.map(\.muscleTarget) })
            XCTAssertEqual(liveDelivered.days.map { $0.exercises.map(\.sets) }, liveNext.menus.map { $0.map(\.prescribedSets) })
            let lastPreviousCore = try XCTUnwrap(previousLiveDays.last { day in day.exercises.contains {
                service.proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
            } }?.dayNumber)
            let firstBaselineCore = try XCTUnwrap(liveControl.menus.indices.first { day in
                liveControl.menus[day].contains { $0.role == .core }
            }) + dayStart
            let firstDeliveredCore = try XCTUnwrap(liveDelivered.days.first { day in day.exercises.contains {
                service.proceduralExerciseRole(for: $0.exerciseName, muscleTarget: $0.muscleTarget) == .core
            } }?.dayNumber)
            XCTAssertGreaterThanOrEqual(firstDeliveredCore - lastPreviousCore, firstBaselineCore - lastPreviousCore)
            for day in [lower, pull] {
                XCTAssertLessThanOrEqual(service.estimatedDayFatigue(for: liveDelivered.days[day].exercises),
                    service.setBudgetLimits(for: liveNext.blueprint).fatigue[day])
                XCTAssertLessThanOrEqual(service.estimatedSessionMinutes(for: liveDelivered.days[day]),
                    liveNext.blueprint.dayPlans[day].targetSessionMinutes)
            }
            XCTAssertEqual(try encodedDays(previousLiveDays), previousSnapshot)
            let findings = service.validateWeekResponse(liveDelivered, dayStart: dayStart, dayEnd: week * 7,
                previousWeekDays: previousLiveDays, blueprint: liveNext.blueprint, expectedExerciseMenus: liveNext.menus)
            XCTAssertTrue(findings.isEmpty, "Current-policy chain findings: \(findings)")
            chain.append("LIVE_WEEK \(week) decision=\(liveFinal.decision) admission=\(liveNext.roleFloorAdmission) counts=\(liveNext.menus.map(\.count)) findings=\(findings)")
            chain.append("LIVE_WEEK \(week) INPUT_PREVIOUS \(previousSnapshot)")
            chain.append("LIVE_WEEK \(week) DELIVERED \(try encodedDays(liveDelivered.days))")
            previousLiveDays = liveDelivered.days
        }
        try writeArtifactIfRequested(chain.joined(separator: "\n"), environmentKey: "TRANSFORM_CORE_CHAIN_OUTPUT")
    }

    func testRecordRowAlternativeExplorationAndRejectInvalidDoses() throws {
        let persona = personas[2]
        let weeks = try fullMesocycle(for: persona)
        XCTAssertEqual(weeks.count, 4)
        guard weeks.count == 4 else { return }
        var report: [String] = []
        let blueprint = weeks[3].blueprint
        let planned = weeks[3].coreFinalization.plan
        let baseline = planned.menus
        func signature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
            menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
        }
        let original = signature(baseline)
        XCTAssertEqual(baseline.map { $0.map(\.exerciseName) }, weeks[3].days.map { $0.exercises.map(\.exerciseName) })
        XCTAssertEqual(baseline.map { $0.map(\.prescribedSets) }, weeks[3].days.map { $0.exercises.map(\.sets) })
        let back = service.normalizedGroupAliases(forSeed: "back")
        let locations = baseline.indices.flatMap { day in baseline[day].indices.map { (day, $0) } }
        func matches(_ location: (Int, Int), patterns: Set<String>) -> Bool {
            let exercise = baseline[location.0][location.1]
            guard let pattern = service.menuMovementPattern(forExerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget), patterns.contains(pattern) else { return false }
            return service.exerciseDirectlyTargets(groupAliases: back, exerciseName: exercise.exerciseName,
                muscleTarget: exercise.muscleTarget)
        }
        let vertical = locations.filter { matches($0, patterns: service.verticalPullPatterns) }
        let rows = locations.filter { matches($0, patterns: service.horizontalPullPatterns) }
        XCTAssertEqual(vertical.reduce(0) { $0 + baseline[$1.0][$1.1].prescribedSets }, 8,
            "Measured 3a62fd0 deload: fractional Lats funding raises vertical work from seven to eight; row balance remains unresolved")
        XCTAssertEqual(rows.reduce(0) { $0 + baseline[$1.0][$1.1].prescribedSets }, 3)
        let originalTotal = baseline.joined().reduce(0) { $0 + $1.prescribedSets }
        var trialCount = 0
        for donor in vertical where baseline[donor.0][donor.1].prescribedSets > 1 {
            for receiver in rows {
                var candidate = baseline
                candidate[donor.0][donor.1].prescribedSets -= 1
                candidate[receiver.0][receiver.1].prescribedSets += 1
                trialCount += 1
                XCTAssertEqual(candidate.map(\.count), baseline.map(\.count))
                XCTAssertEqual(candidate.map { $0.map(\.exerciseName) }, baseline.map { $0.map(\.exerciseName) })
                XCTAssertEqual(candidate.map { $0.map(\.muscleTarget) }, baseline.map { $0.map(\.muscleTarget) })
                XCTAssertEqual(candidate.map { $0.map(\.movementPattern) }, baseline.map { $0.map(\.movementPattern) })
                XCTAssertEqual(candidate.map { $0.map(\.role) }, baseline.map { $0.map(\.role) })
                XCTAssertEqual(candidate.joined().reduce(0) { $0 + $1.prescribedSets }, originalTotal)
                let decision = service.compareAllocatedDoseOnly(candidate, baseline: baseline,
                    blueprint: blueprint, weekNumber: 4)
                guard case .rejected(.roleDose) = decision else {
                    XCTFail("A transfer below donor floor or above the row's three-set ceiling must fail: \(decision)")
                    continue
                }
                // Diagnostic trial only: even dose preservation is not permission to change deload policy.
                report.append("ROW_DOSE_TRIAL persona=\(persona.name) week=4 donorDay=\(donor.0 + 1) donor=\(baseline[donor.0][donor.1].exerciseName) rowDay=\(receiver.0 + 1) row=\(baseline[receiver.0][receiver.1].exerciseName) decision=\(decision) candidate=\(signature(candidate))")
                XCTAssertEqual(signature(baseline), original, "Each trial starts from the untouched complete baseline")
            }
        }
        guard trialCount > 0 else { XCTFail("No row-dose transfer trials ran"); return }
        var substitutionTrials = 0
        for donor in vertical {
            let old = baseline[donor.0][donor.1]
            let catalog = service.exerciseCatalog(for: blueprint.dayPlans[donor.0].style)
            let alternatives = catalog.filter {
                $0.target == old.muscleTarget
                    && service.menuMovementPattern(forExerciseName: $0.name, muscleTarget: $0.target) == "Row"
            }
            if alternatives.isEmpty {
                report.append("ROW_SUBSTITUTION_TRIAL day=\(donor.0 + 1) old=\(old.exerciseName) no same-target Row in style catalog=\(blueprint.dayPlans[donor.0].style)")
            }
            for alternative in alternatives {
                var candidate = baseline
                candidate[donor.0][donor.1] = .init(exerciseName: alternative.name, muscleTarget: alternative.target,
                    movementPattern: service.exerciseMetadata(forExerciseName: alternative.name,
                        muscleTarget: alternative.target).movementPattern,
                    role: service.proceduralExerciseRole(for: alternative.name, muscleTarget: alternative.target),
                    prescribedSets: old.prescribedSets)
                substitutionTrials += 1
                XCTAssertEqual(candidate.map(\.count), baseline.map(\.count))
                XCTAssertEqual(candidate.map { $0.map(\.prescribedSets) }, baseline.map { $0.map(\.prescribedSets) })
                for location in locations where location.0 != donor.0 || location.1 != donor.1 {
                    XCTAssertEqual(signature(candidate)[location.0][location.1], original[location.0][location.1])
                }
                let preflight = service.preflightFixedDoseSubstitution(candidate, plannedBaseline: planned)
                let dose = service.compareAllocatedDoseOnly(candidate, baseline: baseline, blueprint: blueprint, weekNumber: 4)
                // Measured in run 35028562024. Pin the diagnostic boundary, not an
                // endorsement of the quality heuristic or proof that all alternatives fail.
                XCTAssertEqual(alternative.name, "Single-Arm Dumbbell Row")
                switch old.exerciseName {
                case "Pull-Up (Weighted or Assisted)":
                    XCTAssertEqual(preflight, .rejected(.protectedSlot))
                case "Lat Pulldown":
                    XCTAssertEqual(preflight, .rejected(.focusQuality))
                default:
                    XCTFail("New row alternative needs explicit review: \(old.exerciseName)")
                }
                XCTAssertEqual(dose, .dosePreserved(improvesMaintenanceMinimum: false))
                // Invalid-dose controls establish that preserving names alone is insufficient.
                var invalid = candidate
                invalid[donor.0][donor.1].prescribedSets = 0
                XCTAssertEqual(service.preflightFixedDoseSubstitution(invalid, plannedBaseline: planned),
                    .rejected(.changeScope))
                guard case .rejected = service.compareAllocatedDoseOnly(invalid, baseline: baseline,
                    blueprint: blueprint, weekNumber: 4) else { XCTFail("Zero-dose row must be rejected"); continue }
                report.append("ROW_SUBSTITUTION_TRIAL persona=\(persona.name) week=4 day=\(donor.0 + 1) old=\(old.exerciseName) replacement=\(alternative.name) sets=\(old.prescribedSets) preflight=\(preflight) dose=\(dose) candidate=\(signature(candidate))")
            }
        }
        guard substitutionTrials > 0 else { XCTFail("No catalog row alternatives were exercised"); return }
        XCTAssertEqual(substitutionTrials, 2, "Measured catalog trial count; review newly available alternatives")
        report.append("ROW_SUBSTITUTION_TRIAL same-style same-target alternatives tested=\(substitutionTrials)")
        let intent = service.trainingIntentPlan(from: analysis(for: persona))
        let limits = service.setBudgetLimits(for: blueprint)
        let maximumAppearanceTrials = 16
        var appearanceTrials = 0
        var appearanceLimitReached = false
        let originalOutput = service.buildProceduralWeek(weekNumber: 4, dayStart: 22, dayEnd: 28,
            splitType: intent.splitRecommendation, programName: "Row experiment baseline",
            trainingIntent: intent, blueprint: blueprint, previousWeekDays: weeks[2].days, exerciseMenus: baseline)
        let originalFindings = service.validateWeekResponse(originalOutput, dayStart: 22, dayEnd: 28,
            previousWeekDays: weeks[2].days, blueprint: blueprint, expectedExerciseMenus: baseline)
        report.append("ROW_EXPLORATION_BASELINE_FINDINGS \(originalFindings)")
        report.append("ROW_APPEARANCE_SCOPE existing Pull/Upper catalog; Row pattern and direct Back primary; includes direct-Lats candidates; maximumTrials=\(maximumAppearanceTrials); historySupplied=\(planned.exerciseHistory != nil); no pain/history eligibility filtering in this diagnostic; NOT_ADOPTED; deload ceiling remains binding")
        appearanceSearch: for day in baseline.indices where !blueprint.dayPlans[day].isRestDay {
            let style = service.canonicalTrainingStyle(blueprint.dayPlans[day].style)
            guard style == "Pull" || style == "Upper" else { continue }
            let existing = Set(baseline[day].map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) })
            for entry in service.exerciseCatalog(for: blueprint.dayPlans[day].style) {
                let metadata = service.exerciseMetadata(forExerciseName: entry.name, muscleTarget: entry.target)
                guard metadata.movementPattern == "Row",
                      service.exerciseDirectlyTargets(groupAliases: back, exerciseName: entry.name, muscleTarget: entry.target),
                      !existing.contains(ExerciseWeightEntry.canonicalLookupKey(entry.name)) else { continue }
                guard appearanceTrials < maximumAppearanceTrials else { appearanceLimitReached = true; break appearanceSearch }
                appearanceTrials += 1
                let floor = service.minimumSetFloor(forExerciseName: entry.name, muscleTarget: entry.target)
                var candidate = baseline
                candidate[day].append(.init(exerciseName: entry.name, muscleTarget: entry.target,
                    movementPattern: metadata.movementPattern,
                    role: service.proceduralExerciseRole(for: entry.name, muscleTarget: entry.target), prescribedSets: floor))
                let appended = candidate
                candidate = service.reorderedMenusForSessionFlow(candidate, blueprint: blueprint,
                    trainingIntent: intent, lockedPrefixCounts: planned.lockedPrefixCounts)
                for index in baseline.indices {
                    XCTAssertEqual(signature(candidate)[index].sorted(), signature(appended)[index].sorted())
                    let remaining = candidate[index].filter { index != day || $0.exerciseName != entry.name }
                    XCTAssertEqual(signature([remaining])[0].sorted(), original[index].sorted(), "Every original prescription must survive unchanged")
                }
                XCTAssertEqual(candidate.joined().reduce(0) { $0 + $1.prescribedSets }, originalTotal + floor)
                let dose = service.compareAllocatedDoseOnly(candidate, baseline: baseline, blueprint: blueprint, weekNumber: 4)
                let output = service.buildProceduralWeek(weekNumber: 4, dayStart: 22, dayEnd: 28,
                    splitType: intent.splitRecommendation, programName: "Row appearance experiment",
                    trainingIntent: intent, blueprint: blueprint, previousWeekDays: weeks[2].days, exerciseMenus: candidate)
                XCTAssertEqual(output.days.map { $0.exercises.map(\.exerciseName) }, candidate.map { $0.map(\.exerciseName) })
                XCTAssertEqual(output.days.map { $0.exercises.map(\.muscleTarget) }, candidate.map { $0.map(\.muscleTarget) })
                XCTAssertEqual(output.days.map { $0.exercises.map(\.sets) }, candidate.map { $0.map(\.prescribedSets) })
                let findings = service.validateWeekResponse(output, dayStart: 22, dayEnd: 28,
                    previousWeekDays: weeks[2].days, blueprint: blueprint, expectedExerciseMenus: candidate)
                let ceiling = service.comfortableDayExerciseCeiling(forStyle: style, weekNumber: 4)
                // Measured in run 35046866513: validator cleanliness does not
                // authorize exceeding the independent deload appearance ceiling.
                XCTAssertEqual(candidate[day].count, 6)
                XCTAssertEqual(ceiling, 5)
                if entry.name == "Single-Arm Dumbbell Row" {
                    XCTAssertEqual(dose, .rejected(.weeklyPriority(area: "Lats")))
                    XCTAssertFalse(findings.isEmpty)
                } else {
                    XCTAssertEqual(dose, .dosePreserved(improvesMaintenanceMinimum: false))
                    XCTAssertTrue(findings.isEmpty, "\(findings)")
                }
                let unit = WorkoutExerciseResponse(exerciseName: entry.name, sets: 1, reps: "", tempo: "",
                    restSeconds: 0, notes: "", muscleTarget: entry.target)
                report.append("ROW_APPEARANCE_TRIAL day=\(day + 1) name=\(entry.name) target=\(entry.target) primary=\(metadata.primaryAreas) secondary=\(metadata.secondaryAreas) pattern=\(metadata.movementPattern) roleFloor=\(floor) directLatsPerSet=\(service.directSetCredit(for: unit, area: "Lats")) dose=\(dose) count=\(candidate[day].count) deloadCeiling=\(ceiling) deloadCeilingRefused=\(candidate[day].count > ceiling) fatigue=\(service.estimatedDayFatigue(for: output.days[day].exercises)) fatigueCap=\(limits.fatigue[day]) variations=\(service.weeklyVariationViolations(in: candidate, blueprint: blueprint)) findings=\(findings) candidate=\(signature(candidate))")
                if case .dosePreserved = dose {
                    var admission: ClaudeService.RoleFloorAdmission = .unassessed
                    let allocated = service.allocateWeeklySetPrescription(candidate, blueprint: blueprint, weekNumber: 4,
                        lockedPrefixCounts: planned.lockedPrefixCounts, roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
                    let delivered = try service.validatedProceduralWeek(weekNumber: 4, dayStart: 22, dayEnd: 28,
                        splitType: intent.splitRecommendation, programName: "Row appearance reallocation experiment",
                        trainingIntent: intent, blueprint: blueprint, previousWeekDays: weeks[2].days, exerciseMenus: allocated)
                    XCTAssertEqual(delivered.days.map { $0.exercises.map(\.exerciseName) }, allocated.map { $0.map(\.exerciseName) })
                    XCTAssertEqual(delivered.days.map { $0.exercises.map(\.muscleTarget) }, allocated.map { $0.map(\.muscleTarget) })
                    XCTAssertEqual(delivered.days.map { $0.exercises.map(\.sets) }, allocated.map { $0.map(\.prescribedSets) })
                    let allocatedFindings = service.validateWeekResponse(delivered, dayStart: 22, dayEnd: 28,
                        previousWeekDays: weeks[2].days, blueprint: blueprint, expectedExerciseMenus: allocated)
                    XCTAssertEqual(admission, .deloadPolicy)
                    XCTAssertNotEqual(signature(allocated), signature(candidate), "Fresh allocation disagreed in the measured baseline")
                    XCTAssertTrue(allocatedFindings.isEmpty, "\(allocatedFindings)")
                    report.append("ROW_APPEARANCE_REALLOCATION day=\(day + 1) name=\(entry.name) admission=\(admission) exactCandidatePreserved=\(signature(allocated) == signature(candidate)) findings=\(allocatedFindings) menus=\(signature(allocated)); not permission to exceed deload ceiling")
                }
                XCTAssertEqual(signature(planned.menus), original)
            }
        }
        XCTAssertEqual(appearanceTrials, 4, "Measured catalog scope; changed candidates require review")
        XCTAssertFalse(appearanceLimitReached)
        report.append("ROW_APPEARANCE_SUMMARY tested=\(appearanceTrials) limitReached=\(appearanceLimitReached); finite catalog experiment, not proof no whole-plan solution exists")
        var crossCatalogTrials = 0
        let upperVertical = vertical.filter { service.canonicalTrainingStyle(blueprint.dayPlans[$0.0].style) == "Upper" }
        report.append("ROW_CROSS_CATALOG_SCOPE Upper vertical slot; same-target Row from Pull catalog; strict eligibility unchanged; NOT_ADOPTED")
        for location in upperVertical {
            let old = baseline[location.0][location.1]
            let dayPlan = blueprint.dayPlans[location.0]
            let alternatives = service.exerciseCatalog(for: "Pull").filter {
                $0.target == old.muscleTarget && service.menuMovementPattern(forExerciseName: $0.name, muscleTarget: $0.target) == "Row"
            }
            if alternatives.isEmpty { report.append("ROW_CROSS_CATALOG_NONE day=\(location.0 + 1) old=\(old.exerciseName) no same-target Pull Row") }
            for alternative in alternatives {
                crossCatalogTrials += 1
                var candidate = baseline
                let metadata = service.exerciseMetadata(forExerciseName: alternative.name, muscleTarget: alternative.target)
                candidate[location.0][location.1] = .init(exerciseName: alternative.name, muscleTarget: alternative.target,
                    movementPattern: metadata.movementPattern,
                    role: service.proceduralExerciseRole(for: alternative.name, muscleTarget: alternative.target),
                    prescribedSets: old.prescribedSets)
                XCTAssertEqual(candidate.map(\.count), baseline.map(\.count))
                XCTAssertEqual(candidate.map { $0.map(\.prescribedSets) }, baseline.map { $0.map(\.prescribedSets) })
                for untouched in locations where untouched.0 != location.0 || untouched.1 != location.1 {
                    XCTAssertEqual(signature(candidate)[untouched.0][untouched.1], original[untouched.0][untouched.1])
                }
                let strict = service.preflightFixedDoseSubstitution(candidate, plannedBaseline: planned)
                let dose = service.compareAllocatedDoseOnly(candidate, baseline: baseline, blueprint: blueprint, weekNumber: 4)
                let ordered = service.reorderedMenusForSessionFlow(candidate, blueprint: blueprint,
                    trainingIntent: intent, lockedPrefixCounts: planned.lockedPrefixCounts)
                let protected = service.isProtectedAppearance(role: old.role, slot: location.1,
                    style: dayPlan.style, lockedPrefixCount: planned.lockedPrefixCounts[location.0])
                let retained = planned.retainedKeysByDay[location.0].contains(ExerciseWeightEntry.canonicalLookupKey(old.exerciseName))
                let pain = planned.exerciseHistory?.painExercises.contains(ExerciseWeightEntry.canonicalLookupKey(alternative.name)) ?? false
                let output = service.buildProceduralWeek(weekNumber: 4, dayStart: 22, dayEnd: 28,
                    splitType: intent.splitRecommendation, programName: "Cross-catalog row experiment",
                    trainingIntent: intent, blueprint: blueprint, previousWeekDays: weeks[2].days, exerciseMenus: candidate)
                XCTAssertEqual(output.days.map { $0.exercises.map(\.exerciseName) }, candidate.map { $0.map(\.exerciseName) })
                XCTAssertEqual(output.days.map { $0.exercises.map(\.muscleTarget) }, candidate.map { $0.map(\.muscleTarget) })
                XCTAssertEqual(output.days.map { $0.exercises.map(\.sets) }, candidate.map { $0.map(\.prescribedSets) })
                let deliveredRow = output.days[location.0].exercises[location.1]
                let styleMatch = service.exerciseMatchesDayStyle(deliveredRow, style: dayPlan.style)
                let focusArea = dayPlan.focusArea ?? "(none)"
                let oldKind = service.focusStimulusKind(exerciseName: old.exerciseName, muscleTarget: old.muscleTarget, focusArea: focusArea)
                let newKind = service.focusStimulusKind(exerciseName: alternative.name, muscleTarget: alternative.target, focusArea: focusArea)
                let oldLats = service.focusStimulusKind(exerciseName: old.exerciseName, muscleTarget: old.muscleTarget, focusArea: "Lats")
                let newLats = service.focusStimulusKind(exerciseName: alternative.name, muscleTarget: alternative.target, focusArea: "Lats")
                let findings = service.validateWeekResponse(output, dayStart: 22, dayEnd: 28,
                    previousWeekDays: weeks[2].days, blueprint: blueprint, expectedExerciseMenus: candidate)
                // Pin the measured candidate's limits; this is not production eligibility.
                XCTAssertEqual(old.exerciseName, "Neutral-Grip Lat Pulldown")
                XCTAssertEqual(alternative.name, "Single-Arm Dumbbell Row")
                XCTAssertEqual(strict, .rejected(.catalog))
                XCTAssertFalse(protected)
                XCTAssertFalse(retained)
                XCTAssertFalse(pain)
                XCTAssertTrue(styleMatch)
                XCTAssertNil(dayPlan.focusArea)
                XCTAssertEqual(oldLats, .prime)
                XCTAssertEqual(newLats, .secondary)
                XCTAssertEqual(signature(ordered), signature(candidate))
                XCTAssertEqual(dose, .dosePreserved(improvesMaintenanceMinimum: false))
                XCTAssertTrue(findings.isEmpty, "\(findings)")
                report.append("ROW_CROSS_CATALOG_TRIAL day=\(location.0 + 1) slot=\(location.1 + 1) old=\(old.exerciseName) new=\(alternative.name) sets=\(old.prescribedSets) strictPreflight=\(strict) protected=\(protected) retained=\(retained) painExcluded=\(pain) historySupplied=\(planned.exerciseHistory != nil) styleMatch=\(styleMatch) focusArea=\(focusArea) dayFocusKind=\(oldKind)->\(newKind) latsKind=\(oldLats)->\(newLats) exactOrderPreserved=\(signature(ordered) == signature(candidate)) ordered=\(signature(ordered)) dose=\(dose) findings=\(findings) candidate=\(signature(candidate)); validator cleanliness is not eligibility approval")
                var admission: ClaudeService.RoleFloorAdmission = .unassessed
                let allocated = service.allocateWeeklySetPrescription(candidate, blueprint: blueprint, weekNumber: 4,
                    lockedPrefixCounts: planned.lockedPrefixCounts, roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
                let reallocatedOutput = service.buildProceduralWeek(weekNumber: 4, dayStart: 22, dayEnd: 28,
                    splitType: intent.splitRecommendation, programName: "Cross-catalog row reallocation",
                    trainingIntent: intent, blueprint: blueprint, previousWeekDays: weeks[2].days, exerciseMenus: allocated)
                XCTAssertEqual(reallocatedOutput.days.map { $0.exercises.map(\.exerciseName) }, allocated.map { $0.map(\.exerciseName) })
                XCTAssertEqual(reallocatedOutput.days.map { $0.exercises.map(\.muscleTarget) }, allocated.map { $0.map(\.muscleTarget) })
                XCTAssertEqual(reallocatedOutput.days.map { $0.exercises.map(\.sets) }, allocated.map { $0.map(\.prescribedSets) })
                let reallocatedDose = service.compareAllocatedDoseOnly(allocated, baseline: baseline, blueprint: blueprint, weekNumber: 4)
                let reallocatedFindings = service.validateWeekResponse(reallocatedOutput, dayStart: 22, dayEnd: 28,
                    previousWeekDays: weeks[2].days, blueprint: blueprint, expectedExerciseMenus: allocated)
                report.append("ROW_CROSS_CATALOG_REALLOCATION admission=\(admission) exactCandidatePreserved=\(signature(allocated) == signature(candidate)) dose=\(reallocatedDose) findings=\(reallocatedFindings) menus=\(signature(allocated)); NOT_ADOPTED")
                XCTAssertEqual(signature(planned.menus), original)
            }
        }
        XCTAssertEqual(upperVertical.count, 1)
        XCTAssertEqual(crossCatalogTrials, 1)
        report.append("ROW_CROSS_CATALOG_SUMMARY sourceSlots=\(upperVertical.count) tested=\(crossCatalogTrials)\(crossCatalogTrials == 0 ? "; no matching source/candidate found" : "")")
        XCTAssertEqual(signature(planned.menus), original)
        try writeArtifactIfRequested(report.joined(separator: "\n"), environmentKey: "TRANSFORM_ROW_TRIALS_OUTPUT")
    }

    func testGeneratedFractionalQuadBudgetRetainsSessionCapAndGluteMinimum() throws {
        let persona = personas[1]
        let intent = service.trainingIntentPlan(from: analysis(for: persona))
        let requested = service.programBlueprint(for: intent, weekNumber: 1)
        let allocation = try XCTUnwrap(requested.priorityAllocations.first { $0.area == "Quads" })
        XCTAssertEqual(allocation.directSetTarget, 7.5)
        var receipts: [SetFundingObservation] = []
        let plan = service.preSelectedExercisePlan(for: requested, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: nil, setFundingReport: { receipts = $0 })
        func direct(_ area: String) -> Double {
            plan.menus.joined().reduce(0) { total, exercise in
                total + service.directSetCredit(for: WorkoutExerciseResponse(exerciseName: exercise.exerciseName,
                    sets: exercise.prescribedSets, reps: "", tempo: "", restSeconds: 0, notes: "",
                    muscleTarget: exercise.muscleTarget), area: area)
            }
        }
        XCTAssertEqual(direct("Quads"), 7)
        XCTAssertEqual(allocation.maxFocusSessionDirectSets, 7.5)
        XCTAssertGreaterThanOrEqual(direct("Glutes"), 3)
        XCTAssertLessThanOrEqual(plan.menus[1].count, 6)
        let delivered = try service.validatedProceduralWeekOneProgram(from: analysis(for: persona),
            trainingIntent: intent, blueprint: plan.blueprint, exerciseMenus: plan.menus)
        func accepted(_ candidateReceipts: [SetFundingObservation], days: [WorkoutDayResponse]? = nil) -> Bool {
            meetsTargetOrProvesFractionalBudgetLimit(allocation: allocation, days: days ?? delivered.days,
                blueprint: plan.blueprint, receipts: candidateReceipts, weekNumber: 1)
        }
        XCTAssertTrue(accepted(receipts))
        XCTAssertFalse(accepted([]), "Missing diagnostic evidence cannot excuse a fractional shortfall")
        let quadReceiptIndex = try XCTUnwrap(receipts.firstIndex { $0.exerciseName == "Leg Press" })
        var missingOne = receipts
        missingOne.remove(at: quadReceiptIndex)
        XCTAssertFalse(accepted(missingOne), "Every eligible appearance needs proof, not just one blocked exercise")
        XCTAssertFalse(accepted(receipts + [receipts[quadReceiptIndex]]), "Duplicate indices cannot count as independent proof")
        for fake in [nil, SetFundingRejection(kind: .weeklyPriority, subject: "Quads", projected: 8, limit: 8.01),
                     SetFundingRejection(kind: .sessionPriority, subject: "Quads", projected: 99, limit: 1)] {
            let forged = receipts.map { SetFundingObservation(dayIndex: $0.dayIndex, exerciseIndex: $0.exerciseIndex,
                exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget,
                prescribedSets: $0.prescribedSets, rejection: fake) }
            XCTAssertFalse(accepted(forged), "A label without matching binding arithmetic is not proof")
        }
        var underfunded = delivered.days
        let lower = underfunded[1]
        let reduced = lower.exercises.enumerated().map { index, exercise in
            index == 0 ? service.exerciseResponse(exercise, withSets: exercise.sets - 1) : exercise
        }
        underfunded[1] = WorkoutDayResponse(dayNumber: lower.dayNumber, dayName: lower.dayName,
            muscleGroups: lower.muscleGroups, isRestDay: lower.isRestDay, notes: lower.notes, exercises: reduced)
        XCTAssertFalse(accepted(receipts, days: underfunded), "Six of 7.5 is not an acceptable fractional remainder")
    }

    // Historical f0e3f97 delivered Glutes2/Quads7 under a fractional ceiling.
    // Keep the scarce-budget regression with an explicit integer seven-set cap;
    // ordinary 7.5 targets may now reach eight under the owner's rounding policy.
    func testGluteMinimumIsReservedWithoutAnExtraAppearanceOrQuadOvershoot() throws {
        let persona = try XCTUnwrap(personas.first { $0.name == "Four-day beginner with a shoulder that hurts overhead" })
        let intent = service.trainingIntentPlan(from: analysis(for: persona))
        let generatedBlueprint = service.programBlueprint(for: intent, weekNumber: 1)
        let requestedBlueprint = withQuadBudget(generatedBlueprint, target: 7)
        var observations: [SetFundingObservation] = []
        let plan = service.preSelectedExercisePlan(for: requestedBlueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: nil, setFundingReport: { observations = $0 })
        let menus = plan.menus, blueprint = plan.blueprint
        let lunge = try XCTUnwrap(observations.first { $0.exerciseName == "Dumbbell Walking Lunge" })
        XCTAssertEqual(lunge.dayIndex, 1)
        XCTAssertEqual(lunge.prescribedSets, 3)
        XCTAssertEqual(menus[1].count, 6, "Core relocation must preserve the funded glute minimum")
        XCTAssertEqual(menus[1].first { $0.exerciseName == "Leg Press" }?.prescribedSets, 2)
        let refusal = try XCTUnwrap(lunge.rejection)
        XCTAssertEqual(refusal.kind, .weeklyPriority)
        XCTAssertEqual(refusal.subject, "Quads")
        XCTAssertEqual(try XCTUnwrap(refusal.projected), 8, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(refusal.limit), 7.01, accuracy: 0.000001)
        let gluteCredit = menus.joined().reduce(0.0) { total, exercise in
            total + service.directSetCredit(for: WorkoutExerciseResponse(exerciseName: exercise.exerciseName,
                sets: exercise.prescribedSets, reps: "", tempo: "", restSeconds: 0,
                notes: "", muscleTarget: exercise.muscleTarget), area: "Glutes")
        }
        XCTAssertEqual(gluteCredit, 3)
        let baseline = service.allocateSetPrescriptionCandidate(menus, blueprint: blueprint,
            weekNumber: 1, reserveMaintenanceMinimum: false)
        XCTAssertEqual(baseline.menus[1].first { $0.exerciseName == "Dumbbell Walking Lunge" }?.prescribedSets, 2)
        XCTAssertTrue(service.minimumDoseCandidatePreservesPlan(menus, baseline: baseline.menus,
            blueprint: blueprint, weekNumber: 1))
        XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(baseline.menus, baseline: baseline.menus,
            blueprint: blueprint, weekNumber: 1), "No improvement must not qualify")
        var changedIdentity = menus
        changedIdentity[1].removeLast()
        XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(changedIdentity, baseline: baseline.menus,
            blueprint: blueprint, weekNumber: 1))
        var illegalDose = menus
        illegalDose[1][lunge.exerciseIndex].prescribedSets = 100
        XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(illegalDose, baseline: baseline.menus,
            blueprint: blueprint, weekNumber: 1))
    }

    // Test-only, single-slot trials. These deliberately do NOT authorize substitutions:
    // A qualified objective/dose/eligibility trial still does not adopt a replacement.
    func testBoundedPressdownSubstitutionsAgainstCompleteBaselineWeeks() throws {
        let family: Set<String> = ["Rope Triceps Pressdown", "Cable Triceps Pressdown", "V-Bar Pressdown"]
        let replacementNames = ["Overhead Cable Triceps Extension", "Cable Kickback"]
        var attempted = 0
        var dosePreserved = 0
        var qualified = 0
        var searchProposals = 0
        var adopted = 0
        var lumbarTrials = 0
        var observedLockedDays = 0
        var observedRetainedDays = 0
        var observedUnlockedFocusRetention = 0
        var trialReport: [String] = []
        func signature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
            menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
        }
        for persona in personas {
            let weeks = try fullMesocycle(for: persona)
            XCTAssertEqual(weeks.count, 4)
            guard weeks.count == 4 else { continue }
            let intent = service.trainingIntentPlan(from: analysis(for: persona))
            // Deload policy is outside this experiment.
            for weekIndex in 0..<3 {
                let planned = weeks[weekIndex].planningBaseline
                let blueprint = planned.blueprint
                let finalized = weeks[weekIndex].finalization
                let pressdownPlan = finalized.plan
                let delivered = weeks[weekIndex].coreFinalization.plan
                let publishedReceipts = weeks[weekIndex].nextSetFunding
                let unobserved = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent,
                    weekNumber: weekIndex + 1, previousWeekDays: weekIndex == 0 ? nil : weeks[weekIndex - 1].days,
                    exerciseHistory: nil)
                XCTAssertEqual(signature(unobserved.menus), signature(delivered.menus),
                    "Diagnostic observers must not affect the selected plan")
                XCTAssertEqual(unobserved.blueprint, delivered.blueprint)
                XCTAssertEqual(publishedReceipts.map(\.exerciseName), delivered.menus.flatMap { $0.map(\.exerciseName) })
                XCTAssertEqual(publishedReceipts.map(\.prescribedSets), delivered.menus.flatMap { $0.map(\.prescribedSets) })
                for receipt in publishedReceipts {
                    XCTAssertEqual(receipt.exerciseName, delivered.menus[receipt.dayIndex][receipt.exerciseIndex].exerciseName)
                    XCTAssertEqual(receipt.muscleTarget, delivered.menus[receipt.dayIndex][receipt.exerciseIndex].muscleTarget)
                }
                trialReport.append("LIVE_FINALIZATION persona=\(persona.name) week=\(weekIndex + 1) decision=\(finalized.decision)")
                if case .adopted = finalized.decision {
                    adopted += 1
                    var checkedReceipts: [SetFundingObservation] = []
                    let checked = service.allocateWeeklySetPrescription(pressdownPlan.menus, blueprint: pressdownPlan.blueprint,
                        weekNumber: weekIndex + 1, lockedPrefixCounts: pressdownPlan.lockedPrefixCounts,
                        setFundingReport: { checkedReceipts = $0 })
                    XCTAssertEqual(signature(checked), signature(pressdownPlan.menus))
                    XCTAssertEqual(checkedReceipts, finalized.receipts,
                        "Final next-set blockers must agree, including kind, subject, projected value and limit")
                    guard case .qualified = service.evaluatePressdownSubstitutionTrial(pressdownPlan.menus,
                        plannedBaseline: planned) else { XCTFail("Live output must requalify against its original baseline"); continue }
                } else if case .consolidated(let day, let removed) = finalized.decision {
                    XCTAssertEqual(weekIndex, 0)
                    XCTAssertEqual(planned.menus[day].count, 6)
                    XCTAssertEqual(pressdownPlan.menus[day].count, 5)
                    var expected = planned.menus
                    let removedSlot = try XCTUnwrap(expected[day].firstIndex { $0.exerciseName == removed })
                    expected[day].remove(at: removedSlot)
                    XCTAssertEqual(pressdownPlan.menus.map { $0.map(\.exerciseName) }, expected.map { $0.map(\.exerciseName) })
                    XCTAssertEqual(pressdownPlan.menus.joined().reduce(0) { $0 + $1.prescribedSets },
                        planned.menus.joined().reduce(0) { $0 + $1.prescribedSets })
                    for index in expected.indices {
                        for slot in expected[index].indices {
                            XCTAssertGreaterThanOrEqual(pressdownPlan.menus[index][slot].prescribedSets,
                                expected[index][slot].prescribedSets)
                        }
                    }
                    guard case .dosePreserved = service.compareAllocatedDoseOnly(pressdownPlan.menus,
                        baseline: planned.menus, blueprint: planned.blueprint, weekNumber: planned.weekNumber) else {
                        XCTFail("Consolidation must preserve whole-plan dose"); continue
                    }
                    XCTAssertEqual(finalized.receipts.map(\.exerciseName), pressdownPlan.menus.flatMap { $0.map(\.exerciseName) })
                    XCTAssertEqual(finalized.receipts.map(\.prescribedSets), pressdownPlan.menus.flatMap { $0.map(\.prescribedSets) })
                } else {
                    XCTAssertEqual(signature(pressdownPlan.menus), signature(planned.menus))
                }
                let baseline = planned.menus
                XCTAssertEqual(planned.weekNumber, weekIndex + 1)
                XCTAssertEqual(planned.lockedPrefixCounts.count, baseline.count)
                XCTAssertEqual(planned.retainedKeysByDay.count, baseline.count)
                XCTAssertEqual(planned.selectionFocusIntents.count, baseline.count)
                observedLockedDays += planned.lockedPrefixCounts.filter { $0 > 0 }.count
                observedRetainedDays += planned.retainedKeysByDay.filter { !$0.isEmpty }.count
                for day in baseline.indices {
                    XCTAssertEqual(planned.selectionFocusIntents[day]?.area,
                        blueprint.dayPlans[day].isRestDay ? nil : service.focusIntentForArea(
                            blueprint.dayPlans[day].focusArea, within: intent)?.area)
                    XCTAssertLessThanOrEqual(planned.lockedPrefixCounts[day], baseline[day].count)
                    XCTAssertTrue(planned.retainedKeysByDay[day].isSubset(of:
                        Set(baseline[day].map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) })))
                    if blueprint.dayPlans[day].focusArea != nil, planned.lockedPrefixCounts[day] == 0,
                       !planned.retainedKeysByDay[day].isEmpty {
                        observedUnlockedFocusRetention += 1
                    }
                }
                let before = signature(baseline)
                XCTAssertNotEqual(planned.roleFloorAdmission, .unassessed)
                let search = service.searchPressdownReduction(in: planned)
                if persona.name == "Six-day push/pull/legs, back focus, no injuries", weekIndex == 0 {
                    guard case .proposed = search.outcome else {
                        XCTFail("Known complete Arms baseline must yield a qualified replacement, not vacuous search coverage")
                        continue
                    }
                }
                trialReport.append("BOUNDED_SEARCH persona=\(persona.name) week=\(weekIndex + 1) outcome=\(search.outcome) trials=\(search.attempts.count) admission=\(planned.roleFloorAdmission)")
                switch search.outcome {
                case .proposed:
                    searchProposals += 1
                    guard case .qualified = service.evaluatePressdownSubstitutionTrial(search.proposedMenus, plannedBaseline: planned) else {
                        XCTFail("Search must not return an unqualified proposal")
                        continue
                    }
                default:
                    XCTAssertEqual(signature(search.proposedMenus), before)
                }
                XCTAssertLessThanOrEqual(search.attempts.count, 64)
                XCTAssertEqual(signature(planned.menus), before)
                XCTAssertEqual(delivered.menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.prescribedSets)" } },
                    weeks[weekIndex].days.map { $0.exercises.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.sets)" } },
                    "Final chosen menu must match procedural generation without diagnostic observers")
                for day in baseline.indices {
                    let duplicates = baseline[day].indices.filter { family.contains(baseline[day][$0].exerciseName) }
                    guard duplicates.count > 1, let index = duplicates.last else { continue }
                    for replacementName in replacementNames where !baseline[day].contains(where: { $0.exerciseName == replacementName }) {
                        attempted += 1
                        if persona.name == "Five-day lifter reporting lumbar-extension pain" { lumbarTrials += 1 }
                        var candidate = baseline
                        let old = baseline[day][index]
                        XCTAssertEqual(old.muscleTarget, "Triceps", "This trial is scoped to the catalog's Triceps entries")
                        candidate[day][index] = .init(exerciseName: replacementName, muscleTarget: "Triceps",
                            movementPattern: service.exerciseMetadata(forExerciseName: replacementName,
                                muscleTarget: "Triceps").movementPattern,
                            role: service.proceduralExerciseRole(for: replacementName, muscleTarget: "Triceps"),
                            prescribedSets: old.prescribedSets)
                        XCTAssertEqual(candidate.map(\.count), baseline.map(\.count))
                        XCTAssertEqual(candidate[day].filter { family.contains($0.exerciseName) }.count, duplicates.count - 1)
                        let candidateSignature = signature(candidate)
                        for otherDay in baseline.indices {
                            for otherIndex in baseline[otherDay].indices where otherDay != day || otherIndex != index {
                                XCTAssertEqual(candidateSignature[otherDay][otherIndex], before[otherDay][otherIndex])
                            }
                        }
                        let comparison = service.compareAllocatedDoseOnly(candidate, baseline: baseline,
                            blueprint: blueprint, weekNumber: weekIndex + 1)
                        if case .dosePreserved = comparison { dosePreserved += 1 }
                        trialReport.append("SUBSTITUTION_TRIAL persona=\(persona.name) week=\(weekIndex + 1) day=\(day + 1) slot=\(index + 1) old=\(old.exerciseName) new=\(replacementName) sets=\(old.prescribedSets) dose=\(comparison)")
                        trialReport.append("BASELINE \(before)")
                        trialReport.append("BASELINE_DOSE \(service.compareAllocatedDoseOnly(baseline, baseline: baseline, blueprint: blueprint, weekNumber: weekIndex + 1))")
                        trialReport.append("CANDIDATE \(candidateSignature)")
                        let preflight = service.preflightFixedDoseSubstitution(candidate, plannedBaseline: planned)
                        trialReport.append("PREFLIGHT_PLANNER_CONTEXT \(preflight) locks=\(planned.lockedPrefixCounts)")
                        let decision = service.evaluatePressdownSubstitutionTrial(candidate, plannedBaseline: planned)
                        trialReport.append("COMBINED_TRIAL_DECISION \(decision)")
                        if case .qualified = decision { qualified += 1 }
                        if persona.name == "Six-day push/pull/legs, back focus, no injuries" {
                            XCTAssertEqual(preflight, .structurallyEligible)
                            XCTAssertEqual(decision, .qualified(day: day, excessBefore: duplicates.count - 1,
                                excessAfter: duplicates.count - 2))
                        } else if persona.name == "Five-day lifter reporting lumbar-extension pain" {
                            XCTAssertEqual(preflight, .rejected(.catalog), "Kickback is not in the Push style catalog; dose safety alone is insufficient")
                            XCTAssertEqual(decision, .rejected(.eligibility(.catalog)))
                        }
                        XCTAssertFalse(service.minimumDoseCandidatePreservesPlan(candidate, baseline: baseline,
                            blueprint: blueprint, weekNumber: weekIndex + 1), "The existing minimum-dose gate must not adopt these trial replacements")
                        var underfunded = candidate
                        underfunded[day][index].prescribedSets = 0
                        guard case .rejected = service.compareAllocatedDoseOnly(underfunded, baseline: baseline,
                            blueprint: blueprint, weekNumber: weekIndex + 1) else {
                            XCTFail("A replacement with no working sets must not pass dose comparison")
                            continue
                        }
                        XCTAssertEqual(signature(baseline), before, "Trials must not mutate the baseline")
                    }
                }
            }
        }
        XCTAssertGreaterThan(attempted, 0, "The experiment must exercise real duplicate sessions")
        XCTAssertGreaterThan(lumbarTrials, 0, "Do not silently skip the prior lumbar-persona regression")
        XCTAssertGreaterThan(dosePreserved, 0, "At least one full-week alternative must preserve dose")
        XCTAssertGreaterThan(qualified, 0, "Exercise the complete trial decision, not just separate checks")
        XCTAssertGreaterThan(searchProposals, 0, "Bounded search must propose a real full-week alternative")
        XCTAssertGreaterThan(adopted, 0, "Do not ship an adoption path that never adopts a complete-week improvement")
        XCTAssertGreaterThan(observedLockedDays, 0, "Exercise real previous-week ordering locks")
        XCTAssertGreaterThan(observedRetainedDays, 0, "Exercise real retained identities")
        XCTAssertGreaterThan(observedUnlockedFocusRetention, 0,
            "The real builder must capture retained identities even on focus days without an ordering lock")
        trialReport.append("SUBSTITUTION_TRIAL_SUMMARY attempted=\(attempted) dosePreserved=\(dosePreserved) qualified=\(qualified) adopted=\(adopted); physical iPhone NOT tested")
        try writeArtifactIfRequested(trialReport.joined(separator: "\n"),
            environmentKey: "TRANSFORM_SUBSTITUTION_REPORT_OUTPUT")
    }

    func testPlannerCapturedPainHistoryReachesSubstitutionPreflight() throws {
        let persona = personas[0]
        let intent = service.trainingIntentPlan(from: analysis(for: persona))
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        let key = ExerciseWeightEntry.canonicalLookupKey("Cable Kickbacks")
        let history = ClaudeService.ExerciseHistoryContext(painExercises: [key], equipmentSkipExercises: [],
            priorMesocycleExercises: [], mesocycleIndex: 0)
        var captured: ClaudeService.SubstitutionPlanningBaseline?
        let delivered = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: history,
            pressdownPlanningReport: { captured = $0; _ = $1 })
        let planned = try XCTUnwrap(captured)
        XCTAssertFalse(delivered.menus.joined().contains {
            ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) == key
        })
        XCTAssertEqual(planned.exerciseHistory?.painExercises, [key])
        let day = try XCTUnwrap(planned.menus.indices.first { day in
            blueprint.dayPlans[day].style == "Arms" && planned.menus[day].contains { $0.exerciseName == "V-Bar Pressdown" }
        })
        let slot = try XCTUnwrap(planned.menus[day].firstIndex { $0.exerciseName == "V-Bar Pressdown" })
        var candidate = planned.menus
        candidate[day][slot] = .init(exerciseName: "Cable Kickback", muscleTarget: "Triceps",
            movementPattern: service.exerciseMetadata(forExerciseName: "Cable Kickback", muscleTarget: "Triceps").movementPattern,
            role: service.proceduralExerciseRole(for: "Cable Kickback", muscleTarget: "Triceps"),
            prescribedSets: planned.menus[day][slot].prescribedSets)
        XCTAssertEqual(service.preflightFixedDoseSubstitution(candidate, plannedBaseline: planned), .rejected(.painHistory))
        XCTAssertEqual(service.preflightFixedDoseSubstitution(candidate, baseline: planned.menus,
            blueprint: blueprint, lockedPrefixCounts: planned.lockedPrefixCounts,
            painExclusions: .init(exerciseNames: [])), .structurallyEligible,
            "The captured pain history, not another guard, must explain the rejection")
    }

    func testLiveFinalizationRespectsPainHistoryForItsPreviouslyChosenReplacement() throws {
        let persona = personas[0]
        let intent = service.trainingIntentPlan(from: analysis(for: persona))
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        var original: ClaudeService.SubstitutionPlanningBaseline?
        var decision: ClaudeService.PressdownAdoptionDecision?
        let control = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: nil,
            pressdownPlanningReport: { original = $0; decision = $1.decision })
        guard case .adopted? = decision else { return XCTFail("Control must adopt before history can challenge it") }
        let before = try XCTUnwrap(original)
        let replacements = control.menus.indices.flatMap { day in
            control.menus[day].indices.compactMap { slot -> String? in
                control.menus[day][slot].exerciseName == before.menus[day][slot].exerciseName
                    ? nil : control.menus[day][slot].exerciseName
            }
        }
        XCTAssertEqual(replacements.count, 1)
        let key = ExerciseWeightEntry.canonicalLookupKey(try XCTUnwrap(replacements.first))
        let history = ClaudeService.ExerciseHistoryContext(painExercises: [key], equipmentSkipExercises: [],
            priorMesocycleExercises: [], mesocycleIndex: 0)
        let guarded = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: history)
        XCTAssertEqual(guarded.exerciseHistory?.painExercises, [key])
        XCTAssertFalse(guarded.menus.joined().contains {
            ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) == key
        }, "The complete live builder must not adopt the exercise newly excluded by real history context")
    }

    func testWholeSetTargetObserverRejectsMissingAttainableSets() {
        XCTAssertTrue(meetsWholeSetTarget(delivered: 7, ceiling: 7.51))
        XCTAssertFalse(meetsWholeSetTarget(delivered: 6, ceiling: 7.51))
        XCTAssertFalse(meetsWholeSetTarget(delivered: 7, ceiling: 8.01))
        XCTAssertFalse(meetsWholeSetTarget(delivered: 0, ceiling: 7.51))
    }

    private func fullMesocycle(for persona: Persona) throws -> [SimulatedWeek] {
        let result = analysis(for: persona)
        let intent = service.trainingIntentPlan(from: result)
        var weeks: [SimulatedWeek] = []
        var previous: [WorkoutDayResponse]?

        for weekNumber in 1...4 {
            let planningBlueprint = service.programBlueprint(for: intent, weekNumber: weekNumber)
            var appearancePlanning: [String] = []
            var nextSetFunding: [SetFundingObservation] = []
            var capturedBaseline: ClaudeService.SubstitutionPlanningBaseline?
            var capturedFinalization: ClaudeService.PressdownFinalization?
            var capturedPreCore: ClaudeService.SubstitutionPlanningBaseline?
            var capturedCoreFinalization: ClaudeService.CoreRelocationFinalization?
            var capturedCapacityBaseline: ClaudeService.SubstitutionPlanningBaseline?
            var capturedCapacity: ClaudeService.SessionCapacityFinalization?
            var receiptCalls = 0
            var finalizationCalls = 0
            var coreCalls = 0
            let delivered = service.preSelectedExercisePlan(
                for: planningBlueprint,
                trainingIntent: intent,
                weekNumber: weekNumber,
                previousWeekDays: previous,
                exerciseHistory: nil,
                appearancePlanningReport: { appearancePlanning.append($0) },
                setFundingReport: { nextSetFunding = $0; receiptCalls += 1 },
                pressdownPlanningReport: {
                    capturedBaseline = $0; capturedFinalization = $1; finalizationCalls += 1
                },
                corePlanningReport: {
                    capturedPreCore = $0; capturedCoreFinalization = $1; coreCalls += 1
                },
                capacityPlanningReport: {
                    capturedCapacityBaseline = $0; capturedCapacity = $1
                }
            )
            let capacityBaseline = try XCTUnwrap(capturedCapacityBaseline)
            let capacity = try XCTUnwrap(capturedCapacity)
            XCTAssertNil(service.capacityShoulderRegionLoss(capacity.plan.menus,
                baseline: capacityBaseline.menus), "Capacity cannot trade deltoid regions: \(persona.name), week \(weekNumber)")
            if persona.name == "Four-day beginner with a shoulder that hurts overhead", weekNumber < 4 {
                XCTAssertTrue(capacity.plan.menus.allSatisfy { $0.count <= 6 }, capacity.decision)
                if capacity.decision.contains("accessory relocation") {
                    func identitiesAndSets(_ value: [[ClaudeService.PreSelectedExercise]]) -> [String] {
                        value.flatMap { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.role)|\($0.movementPattern)|\($0.prescribedSets)" } }.sorted()
                    }
                    XCTAssertEqual(identitiesAndSets(capacity.plan.menus), identitiesAndSets(capacityBaseline.menus))
                }
            }
            if persona.name == "Compound priority area, small muscles", weekNumber < 4 {
                XCTAssertTrue(capacity.plan.menus.allSatisfy { $0.count <= 6 }, capacity.decision)
                if (2...3).contains(weekNumber) {
                    XCTAssertTrue(capacity.decision.contains("adopted six-slot cross-day triceps consolidation"),
                        "Week \(weekNumber) must adopt the complete-dose six-slot transfer: \(capacity.decision)")
                }
                if capacity.decision.contains("cross-day triceps consolidation") {
                    var removed: [ClaudeService.PreSelectedExercise] = []
                    var increments: [Int] = []
                    for day in capacityBaseline.menus.indices {
                        let old = capacityBaseline.menus[day], new = capacity.plan.menus[day]
                        for item in old {
                            if let current = new.first(where: { $0.exerciseName == item.exerciseName }) {
                                XCTAssertEqual(current.muscleTarget, item.muscleTarget)
                                XCTAssertEqual(current.role, item.role)
                                XCTAssertEqual(current.movementPattern, item.movementPattern)
                                if current.prescribedSets != item.prescribedSets {
                                    increments.append(current.prescribedSets - item.prescribedSets)
                                }
                            } else { removed.append(item) }
                        }
                        XCTAssertEqual(new.map(\.exerciseName), old.filter { item in
                            new.contains { $0.exerciseName == item.exerciseName }
                        }.map(\.exerciseName), "All survivor positions must stay fixed")
                    }
                    XCTAssertEqual(removed.count, 1)
                    XCTAssertEqual(removed.first?.prescribedSets, 2)
                    XCTAssertEqual(increments.sorted(), [1, 1])
                    XCTAssertEqual(capacity.plan.retainedKeysByDay, capacityBaseline.retainedKeysByDay)
                    XCTAssertEqual(capacity.plan.lockedPrefixCounts, capacityBaseline.lockedPrefixCounts)
                }
            }
            let blueprint = delivered.blueprint
            let menus = delivered.menus
            XCTAssertEqual(receiptCalls, 1)
            XCTAssertEqual(finalizationCalls, 1)
            XCTAssertEqual(coreCalls, 1)
            let planningBaseline = try XCTUnwrap(capturedBaseline)
            let finalization = try XCTUnwrap(capturedFinalization)
            let preCore = try XCTUnwrap(capturedPreCore)
            let coreFinalization = try XCTUnwrap(capturedCoreFinalization)
            if weekNumber == 4 { XCTAssertEqual(coreFinalization.decision, .unsupportedWeek) }
            func signature(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[String]] {
                menus.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.movementPattern)|\($0.role)|\($0.prescribedSets)" } }
            }
            XCTAssertEqual(signature(preCore.menus), signature(finalization.plan.menus))
            XCTAssertEqual(preCore.blueprint, finalization.plan.blueprint)
            XCTAssertEqual(signature(delivered.menus), signature(coreFinalization.plan.menus),
                "Core callback must describe the actual returned plan, including deload")
            XCTAssertEqual(delivered.blueprint, coreFinalization.plan.blueprint)
            XCTAssertEqual(nextSetFunding, coreFinalization.receipts)
            if coreFinalization.decision == .adopted {
                let receivers = menus.indices.filter { menus[$0].count > preCore.menus[$0].count }
                XCTAssertEqual(receivers.count, 1)
                let receiver = try XCTUnwrap(receivers.first)
                XCTAssertEqual(menus[receiver].count, 6)
                var expectedDays = planningBlueprint.dayPlans
                let day = expectedDays[receiver]
                expectedDays[receiver] = .init(dayIndex: day.dayIndex, style: day.style,
                    focusArea: day.focusArea,
                    supportAreas: day.supportAreas.contains("Core/Abs") ? day.supportAreas : day.supportAreas + ["Core/Abs"],
                    targetFatigueCap: day.targetFatigueCap, targetSessionMinutes: day.targetSessionMinutes,
                    targetPrioritySlots: day.targetPrioritySlots, emphasisPatterns: day.emphasisPatterns,
                    isRestDay: day.isRestDay)
                let expectedBlueprint = ClaudeService.ProgramBlueprint(evidenceVersion: planningBlueprint.evidenceVersion,
                    splitRecommendation: planningBlueprint.splitRecommendation,
                    weeklyTrainingDays: planningBlueprint.weeklyTrainingDays,
                    priorityAllocations: planningBlueprint.priorityAllocations, dayPlans: expectedDays,
                    topLeverageChange: planningBlueprint.topLeverageChange, posturalFocus: planningBlueprint.posturalFocus,
                    injuryRiskFocus: planningBlueprint.injuryRiskFocus, programmingNotes: planningBlueprint.programmingNotes,
                    calibration: planningBlueprint.calibration)
                XCTAssertEqual(delivered.blueprint, expectedBlueprint, "Only the receiving day's core support may change")
                XCTAssertEqual(signature(menus).flatMap { $0 }.sorted(), signature(preCore.menus).flatMap { $0 }.sorted())
            } else {
                XCTAssertEqual(delivered.blueprint, planningBlueprint)
                XCTAssertEqual(signature(menus), signature(preCore.menus))
                XCTAssertEqual(coreFinalization.receipts, finalization.receipts)
                XCTAssertEqual(coreFinalization.messages, finalization.messages)
            }
            XCTAssertEqual(nextSetFunding.count, menus.joined().count)
            XCTAssertEqual(nextSetFunding.map { "\($0.dayIndex):\($0.exerciseIndex)" },
                menus.indices.flatMap { day in menus[day].indices.map { "\(day):\($0)" } })
            var observedLocations = Set<String>()
            for observation in nextSetFunding {
                guard menus.indices.contains(observation.dayIndex),
                      menus[observation.dayIndex].indices.contains(observation.exerciseIndex) else {
                    XCTFail("Funding observation contains an out-of-range menu location")
                    continue
                }
                XCTAssertTrue(observedLocations.insert("\(observation.dayIndex):\(observation.exerciseIndex)").inserted,
                    "Each appearance must be reported exactly once")
                let exercise = menus[observation.dayIndex][observation.exerciseIndex]
                XCTAssertEqual(observation.exerciseName, exercise.exerciseName)
                XCTAssertEqual(observation.muscleTarget, exercise.muscleTarget)
                XCTAssertEqual(observation.prescribedSets, exercise.prescribedSets)
            }
            let days: [WorkoutDayResponse]
            if weekNumber == 1 {
                days = try service.validatedProceduralWeekOneProgram(
                    from: result,
                    trainingIntent: intent,
                    blueprint: blueprint,
                    exerciseMenus: menus
                ).days
            } else {
                days = try service.validatedProceduralWeek(
                    weekNumber: weekNumber,
                    dayStart: ((weekNumber - 1) * 7) + 1,
                    dayEnd: weekNumber * 7,
                    splitType: intent.splitRecommendation,
                    programName: "Simulation",
                    trainingIntent: intent,
                    blueprint: blueprint,
                    previousWeekDays: previous,
                    exerciseMenus: menus
                ).days
            }
            // Run the same validator the shipping path runs. The procedural week is what the
            // athlete actually receives whenever generation falls back, so a finding here is a
            // finding against a real delivered program — and several rules are heuristic counts
            // that no structural assertion in this file would ever notice.
            let findings: [String]
            if weekNumber == 1 {
                findings = service.validateProgramResponse(
                    WorkoutProgramResponse(
                        programName: "Simulation",
                        programSummary: "Simulation",
                        splitType: intent.splitRecommendation,
                        daysPerWeek: days.filter { !$0.isRestDay }.count,
                        days: days
                    ),
                    blueprint: blueprint,
                    expectedExerciseMenus: menus
                )
            } else {
                findings = service.validateWeekResponse(
                    WorkoutWeekResponse(weekSummary: "Simulation", days: days),
                    dayStart: ((weekNumber - 1) * 7) + 1,
                    dayEnd: weekNumber * 7,
                    previousWeekDays: previous,
                    blueprint: blueprint,
                    expectedExerciseMenus: menus
                )
            }

            let shape = zip(blueprint.dayPlans, days).compactMap { plan, day -> String? in
                guard !day.isRestDay else { return nil }
                return "d\(day.dayNumber):\(service.canonicalTrainingStyle(plan.style))x\(day.exercises.count)"
            }.joined(separator: " ")

            weeks.append(SimulatedWeek(days: days, findings: findings, shape: shape, blueprint: blueprint,
                appearancePlanning: appearancePlanning, nextSetFunding: nextSetFunding,
                planningBaseline: planningBaseline, finalization: finalization, coreFinalization: coreFinalization))
            previous = days
        }
        return weeks
    }

    /// The whole trial run. Structural failures are assertions; everything else is reported.
    func testEveryPersonaReceivesAUsableFourWeekProgram() throws {
        var report: [String] = ["", "=== USER JOURNEY SIMULATION ==="]
        var evidence: [PersonaEvidence] = []

        for persona in personas {
            let weeks = try fullMesocycle(for: persona)
            evidence.append(PersonaEvidence(
                name: persona.name,
                analysis: analysis(for: persona),
                weeks: try weeks.enumerated().map { index, week in
                    let stimulus = service.buildWeekStimulusReport(from: week.days)
                    return WeekEvidence(
                        weekNumber: index + 1,
                        evidenceVersion: week.blueprint.evidenceVersion,
                        plannedTrainingDays: week.blueprint.weeklyTrainingDays,
                        priorities: week.blueprint.priorityAllocations.map { allocation in
                            let coverage = service.priorityCoverage(for: allocation,
                                stimulusReport: stimulus)
                            return PriorityEvidence(
                                area: allocation.area,
                                directSetTarget: allocation.directSetTarget,
                                targetFrequency: allocation.targetFrequency,
                                targetExerciseSlots: allocation.targetExerciseSlots,
                                deliveredDirectSets: coverage.directSets,
                                directSetShortfall: max(0, allocation.directSetTarget - coverage.directSets),
                                meaningfulDays: coverage.meaningfulDayMatches
                            )
                        },
                        days: week.days,
                        validatorFindings: week.findings,
                        appearancePlanning: week.appearancePlanning,
                        nextSetFunding: week.nextSetFunding,
                        crossDayTrials: try crossDayTrials(persona: persona, weeks: weeks, index: index)
                    )
                }
            ))
            report.append("")
            report.append("PERSONA: \(persona.name)")

            for (index, week) in weeks.enumerated() {
                let weekNumber = index + 1
                let days = week.days
                if weekNumber == 1 && ["Six-day push/pull/legs, back focus, no injuries",
                    "Compound priority area, small muscles"].contains(persona.name) {
                    XCTAssertTrue(days.allSatisfy { $0.exercises.count <= 6 },
                        "The two verified Week 1 subsets must reach production delivery")
                }
                if persona.name == "Four-day beginner with a shoulder that hurts overhead" {
                    // Preserve the complete pre-classifier-change pulling prescription.
                    // Green unit tests hid an 8-vertical/2-row regression at 53f360e.
                    let pulls = days.flatMap(\.exercises).filter { exercise in
                        let pattern = service.exerciseMetadata(for: exercise).movementPattern
                        return service.verticalPullPatterns.contains(pattern) || service.horizontalPullPatterns.contains(pattern)
                    }.map { "\($0.exerciseName)|\($0.sets)|\($0.muscleTarget)" }.sorted()
                    XCTAssertEqual(pulls, ["Pull-Up (Weighted or Assisted)|3|Lats", "Lat Pulldown|2|Lats",
                        "Chest-Supported Row|3|Upper Back", "Seated Cable Row|2|Mid Back"].sorted(),
                        "Chest-accounting correction must not damage the established pulling plan in week \(weekNumber)")
                    XCTAssertFalse(week.findings.contains { $0.contains("The week's back work") })
                }
                let dayStart = ((weekNumber - 1) * 7) + 1
                if persona.name == "Compound priority area, small muscles", (2...3).contains(weekNumber) {
                    func directTriceps(_ day: WorkoutDayResponse) -> Int {
                        day.exercises.reduce(0) { total, item in
                            total + (service.exerciseMetadata(for: item).primaryAreas
                                .map(service.normalizedPriorityText).contains("triceps") ? item.sets : 0)
                        }
                    }
                    func loading(_ value: [WorkoutDayResponse]) -> [Int] {
                        value.filter { day in day.exercises.contains { item in
                            let info = service.exerciseMetadata(for: item)
                            return item.sets > 0 && (info.primaryAreas + info.secondaryAreas)
                                .map(service.normalizedPriorityText).contains("triceps")
                        } }.map(\.dayNumber)
                    }
                    XCTAssertTrue(days.allSatisfy { $0.exercises.count <= 6 })
                    XCTAssertEqual(days.map(directTriceps).reduce(0, +), 10)
                    XCTAssertEqual(days.filter { directTriceps($0) >= 2 }.count, 2)
                    let armsIndex = try XCTUnwrap(week.blueprint.dayPlans.firstIndex {
                        service.canonicalTrainingStyle($0.style) == "Arms"
                    })
                    XCTAssertEqual(directTriceps(days[armsIndex]), 8, "Include the two Dip sets, not just the six isolation sets")
                    let current = loading(days)
                    XCTAssertTrue(zip(current, current.dropFirst()).allSatisfy { $1 - $0 >= 2 })
                    if let before = loading(weeks[index - 1].days).last, let first = current.first {
                        XCTAssertGreaterThanOrEqual(first - before, 2)
                    }
                    // The complete sequential test can check the real following
                    // week (including deload), which the live planner cannot see yet.
                    if let last = current.last, let after = loading(weeks[index + 1].days).first {
                        XCTAssertGreaterThanOrEqual(after - last, 2)
                    }
                }
                let trainingDays = days.filter { !$0.isRestDay }
                XCTAssertTrue(trainingDays.allSatisfy { (5...6).contains($0.exercises.count) },
                    "\(persona.name) week \(weekNumber): live menu must contain five or six exercises per training day")
                let totalSets = trainingDays.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
                let exerciseCount = trainingDays.reduce(0) { $0 + $1.exercises.count }
                if !MesocyclePhase.isDeloadWeek(weekNumber) {
                    let stimulus = service.buildWeekStimulusReport(from: days)
                    let tight = week.blueprint.calibration.recoveryConstrained || week.blueprint.calibration.poorNutritionAdherence
                    for group in service.majorMuscleGroups {
                        guard !service.isMajorMuscleGroupPrioritized(seed: group.seed, blueprint: week.blueprint) else { continue }
                        let delivered = service.weeklyDirectSets(
                            forGroupAliases: service.normalizedGroupAliases(forSeed: group.seed), days: days)
                        XCTAssertGreaterThanOrEqual(delivered + 0.01,
                            WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight: tight),
                            "\(persona.name) week \(weekNumber): \(group.label) maintenance minimum missed")
                    }
                    for allocation in week.blueprint.priorityAllocations {
                        let coverage = service.priorityCoverage(for: allocation, stimulusReport: stimulus)
                        for exercise in days.flatMap(\.exercises) {
                            guard exercise.sets > 0 else {
                                XCTFail("Cannot audit direct-credit units for a nonpositive prescription")
                                continue
                            }
                            let unit = service.directSetCredit(for: exercise, area: allocation.area) / Double(exercise.sets)
                            XCTAssertTrue(unit == 0 || unit == 1, "Direct-credit semantics changed; revisit whole-set observer")
                        }
                        XCTAssertTrue(meetsTargetOrProvesFractionalBudgetLimit(allocation: allocation,
                            days: days, blueprint: week.blueprint, receipts: week.nextSetFunding, weekNumber: weekNumber),
                            "\(persona.name) week \(weekNumber): \(allocation.area) whole-set target missed without proven binding budget")
                        XCTAssertGreaterThanOrEqual(coverage.meaningfulDayMatches, allocation.targetFrequency,
                            "\(persona.name) week \(weekNumber): \(allocation.area) meaningful frequency missed")
                    }
                }

                // --- Structural invariants: a person would call any of these broken. ---

                XCTAssertEqual(days.count, 7, "\(persona.name) week \(weekNumber): not 7 days")

                XCTAssertEqual(
                    Set(days.map(\.dayNumber)),
                    Set(dayStart...(dayStart + 6)),
                    "\(persona.name) week \(weekNumber): day numbers are wrong"
                )

                for day in days where day.isRestDay {
                    XCTAssertTrue(
                        day.exercises.isEmpty,
                        "\(persona.name) week \(weekNumber) day \(day.dayNumber): rest day carries exercises"
                    )
                }

                for day in trainingDays {
                    XCTAssertFalse(
                        day.exercises.isEmpty,
                        "\(persona.name) week \(weekNumber) day \(day.dayNumber): training day with no exercises"
                    )

                    let names = day.exercises.map { service.normalizeExerciseName($0.exerciseName) }
                    XCTAssertEqual(
                        Set(names).count,
                        names.count,
                        "\(persona.name) week \(weekNumber) day \(day.dayNumber): the same lift appears twice — "
                            + day.exercises.map(\.exerciseName).joined(separator: ", ")
                    )

                    for exercise in day.exercises {
                        let label = "\(persona.name) week \(weekNumber) day \(day.dayNumber) "
                            + "\(exercise.exerciseName)"
                        XCTAssertFalse(
                            exercise.exerciseName.trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(label): empty exercise name"
                        )
                        XCTAssertTrue(
                            (1...8).contains(exercise.sets),
                            "\(label): \(exercise.sets) sets is outside 1-8"
                        )
                        if !MesocyclePhase.isDeloadWeek(weekNumber) {
                            XCTAssertGreaterThanOrEqual(exercise.sets, service.minimumSetFloor(for: exercise),
                                "\(label): loading-week appearance was not funded to its role floor")
                        }
                        XCTAssertFalse(
                            exercise.reps.trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(label): empty rep prescription"
                        )
                        XCTAssertTrue(
                            (30...240).contains(exercise.restSeconds),
                            "\(label): \(exercise.restSeconds)s rest is outside 30-240"
                        )
                        XCTAssertFalse(
                            exercise.notes.trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(label): no coaching note at all"
                        )
                    }
                    let plan = week.blueprint.dayPlans[day.dayNumber - dayStart]
                    XCTAssertLessThanOrEqual(service.estimatedDayFatigue(for: day.exercises), plan.targetFatigueCap,
                        "\(persona.name) week \(weekNumber) day \(day.dayNumber): delivered fatigue exceeds budget")
                }

                // --- Reported, not asserted. ---
                report.append(
                    "  week \(weekNumber): \(trainingDays.count) training days, "
                        + "\(exerciseCount) exercises, \(totalSets) total sets"
                )
                report.append("      shape: \(week.shape)")
                for day in days {
                    report.append("      day \(day.dayNumber): \(day.isRestDay ? "REST" : day.muscleGroups)")
                    for exercise in day.exercises {
                        report.append(
                            "        \(exercise.exerciseName) | \(exercise.sets) sets x \(exercise.reps)"
                                + " | \(exercise.muscleTarget) | rest \(exercise.restSeconds)s"
                                + " | tempo \(exercise.tempo)"
                        )
                    }
                }
                // Validator findings, tiered the way the shipping path tiers them. Reported
                // rather than asserted for now: a quality verdict belongs to a human reading
                // this, and several of these rules are heuristic counts. A HARD FAILURE here
                // would be different in kind — it means the procedural week the athlete
                // actually receives is one the app considers structurally broken — so those
                // are called out separately and loudly.
                for finding in week.findings {
                    let tier: String
                    switch service.validationDisposition(for: finding, menuLocked: true) {
                    case .hardFailure: tier = "HARD FAILURE"
                    case .correctionPass: tier = "repairable"
                    case .acceptableWarning: tier = "warning"
                    }
                    report.append("      [\(tier)] \(finding)")
                }
                if week.findings.isEmpty {
                    report.append("      (no validator findings)")
                }

                // Promoted to an assertion on the evidence of the first run, which reported
                // zero across all five personas and all four weeks. A hard failure here is not
                // a quality opinion: it means the procedural week the athlete actually receives
                // is one the app itself classifies as structurally broken, with no further
                // fallback behind it.
                let hardFailures = week.findings.filter {
                    service.validationDisposition(for: $0, menuLocked: true) == .hardFailure
                }
                XCTAssertTrue(
                    hardFailures.isEmpty,
                    "\(persona.name) week \(weekNumber) ships a structurally broken week: "
                        + hardFailures.joined(separator: " | ")
                )
            }

            // The deload must actually deload: week 4 carries less work than week 3.
            let week3Sets = weeks[2].days.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
            let week4Sets = weeks[3].days.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
            XCTAssertLessThan(
                week4Sets,
                week3Sets,
                "\(persona.name): week 4 is the deload and must carry fewer sets than week 3 "
                    + "(\(week4Sets) vs \(week3Sets))"
            )
            report.append("  deload check: week 3 \(week3Sets) sets -> week 4 \(week4Sets) sets")
        }

        // Written to a file rather than printed. `swift test --parallel` swallows test stdout,
        // so the first run of this simulation produced a report nobody could read; the workflow
        // uploads this path as an artifact instead.
        try writeArtifactIfRequested(
            report.joined(separator: "\n"),
            environmentKey: "TRANSFORM_JOURNEY_REPORT_OUTPUT"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(JourneyEvidence(personas: evidence))
        // Inspect the encoded raw JSON, not WorkoutDayResponse's forgiving decoder, which
        // could silently discard exercises on a rest day and conceal a broken export.
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let exportedPersonas = try XCTUnwrap(object["personas"] as? [[String: Any]])
        XCTAssertEqual(exportedPersonas.count, personas.count)
        for (exported, source) in zip(exportedPersonas, evidence) {
            let exportedWeeks = try XCTUnwrap(exported["weeks"] as? [[String: Any]])
            XCTAssertEqual(exportedWeeks.count, 4)
            for (exportedWeek, sourceWeek) in zip(exportedWeeks, source.weeks) {
                let exportedDays = try XCTUnwrap(exportedWeek["days"] as? [[String: Any]])
                XCTAssertEqual(exportedDays.count, sourceWeek.days.count)
                for (exportedDay, sourceDay) in zip(exportedDays, sourceWeek.days) {
                    let exercises = try XCTUnwrap(exportedDay["exercises"] as? [[String: Any]])
                    XCTAssertEqual(exercises.compactMap { $0["exerciseName"] as? String }, sourceDay.exercises.map(\.exerciseName))
                    XCTAssertEqual(exercises.compactMap { $0["sets"] as? Int }, sourceDay.exercises.map(\.sets))
                    XCTAssertEqual(exercises.compactMap { $0["reps"] as? String }, sourceDay.exercises.map(\.reps))
                    XCTAssertEqual(exercises.compactMap { $0["muscleTarget"] as? String }, sourceDay.exercises.map(\.muscleTarget))
                    XCTAssertEqual(exercises.compactMap { $0["restSeconds"] as? Int }, sourceDay.exercises.map(\.restSeconds))
                    XCTAssertEqual(exercises.compactMap { $0["tempo"] as? String }, sourceDay.exercises.map(\.tempo))
                    XCTAssertEqual(exercises.compactMap { $0["notes"] as? String }, sourceDay.exercises.map(\.notes))
                    XCTAssertEqual(exportedDay["dayNumber"] as? Int, sourceDay.dayNumber)
                    XCTAssertEqual(exportedDay["isRestDay"] as? Bool, sourceDay.isRestDay)
                }
            }
        }
        try writeArtifactIfRequested(
            String(decoding: encoded, as: UTF8.self),
            environmentKey: "TRANSFORM_JOURNEY_JSON_OUTPUT"
        )
    }

    private func writeArtifactIfRequested(_ contents: String, environmentKey: String) throws {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Same analysis in, same program out. A person who regenerates without changing anything
    /// should not get a different week, and the menu is supposed to be deterministic.
    ///
    /// KNOWN LIMIT, stated so this is not over-trusted: both runs happen in ONE process, and
    /// Swift seeds its hasher per process — so a Dictionary-ordering bug produces the same
    /// wrong answer twice here and passes. This catches ordering that varies WITHIN a run; it
    /// cannot catch the launch-to-launch class. That class is addressed by sorting at the
    /// sites that feed output (`peakDirectSession`, the pattern-stacking loop,
    /// `priorityProfileSpecificitySort`, candidate scoring), and those are what to re-check
    /// when this area changes. A cross-process version would need the suite to re-exec itself.
    // One independently schedulable case per persona avoids a single long tail
    // under swift test --parallel. Each pair still runs together, without caching
    // or dropping any of the forty generated weeks. Incidental cross-persona
    // singleton/process ordering is not guaranteed by these separate cases.
    private func assertRepeatedGeneration(personaNamed name: String) throws {
        XCTAssertEqual(personas.count, 5, "Add a repeatability case when expanding the persona matrix")
        let persona = try XCTUnwrap(personas.first { $0.name == name })
        let first = try fullMesocycle(for: persona)
        let second = try fullMesocycle(for: persona)

        for (index, weeks) in zip(first, second).enumerated() {
            let lhs = weeks.0.days.map { day in
                "\(day.dayNumber)|\(day.isRestDay)|"
                    + day.exercises.map { "\($0.exerciseName):\($0.sets):\($0.reps)" }
                        .joined(separator: ",")
            }
            let rhs = weeks.1.days.map { day in
                "\(day.dayNumber)|\(day.isRestDay)|"
                    + day.exercises.map { "\($0.exerciseName):\($0.sets):\($0.reps)" }
                        .joined(separator: ",")
            }
            XCTAssertEqual(lhs, rhs, "\(persona.name) week \(index + 1) differed between two identical runs")
        }
    }

    func testRepeatedGenerationBackFocus() throws {
        try assertRepeatedGeneration(personaNamed: "Six-day push/pull/legs, back focus, no injuries")
    }

    func testRepeatedGenerationBeginner() throws {
        try assertRepeatedGeneration(personaNamed: "Four-day beginner with a shoulder that hurts overhead")
    }

    func testRepeatedGenerationLumbarCaution() throws {
        try assertRepeatedGeneration(personaNamed: "Five-day lifter reporting lumbar-extension pain")
    }

    func testRepeatedGenerationSmallMuscles() throws {
        try assertRepeatedGeneration(personaNamed: "Compound priority area, small muscles")
    }

    func testRepeatedGenerationArmsFocus() throws {
        try assertRepeatedGeneration(personaNamed: "Arms specialisation on four days")
    }

    /// The blueprint and the week it produced must agree about how many sessions there are.
    /// This is the contradiction that made every six-day deload week a hard failure.
    func testNoWeekSilentlyLosesATrainingDayAgainstItsBlueprint() throws {
        for persona in personas {
            let result = analysis(for: persona)
            let intent = service.trainingIntentPlan(from: result)

            for weekNumber in 1...4 {
                let blueprint = service.programBlueprint(for: intent, weekNumber: weekNumber)
                XCTAssertEqual(
                    blueprint.weeklyTrainingDays,
                    blueprint.dayPlans.filter { !$0.isRestDay }.count,
                    "\(persona.name) week \(weekNumber): blueprint contradicts its own day plans"
                )
            }
        }
    }
}
