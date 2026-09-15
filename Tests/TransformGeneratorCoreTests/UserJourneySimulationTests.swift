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
    // The allocator's normal target is also a ceiling, so 7.5 permits seven, not eight.
    // This observer must fail if direct-credit semantics change; weighted credit is separate.
    private func meetsWholeSetTarget(delivered: Double, ceiling: Double) -> Bool {
        delivered + 0.01 >= floor(ceiling)
    }

    // Baseline f0e3f97 artifact delivered Glutes2/Quads7: a third lunge set was
    // refused at Quads8 > 7.51 after optional leg-press funding spent the budget.
    func testGluteMinimumIsReservedWithoutAnExtraAppearanceOrQuadOvershoot() throws {
        let persona = try XCTUnwrap(personas.first { $0.name == "Four-day beginner with a shoulder that hurts overhead" })
        let intent = service.trainingIntentPlan(from: analysis(for: persona))
        let blueprint = service.programBlueprint(for: intent, weekNumber: 1)
        var observations: [SetFundingObservation] = []
        let menus = service.preSelectedExerciseMenu(for: blueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, setFundingReport: { observations = $0 })
        let lunge = try XCTUnwrap(observations.first { $0.exerciseName == "Dumbbell Walking Lunge" })
        XCTAssertEqual(lunge.dayIndex, 1)
        XCTAssertEqual(lunge.prescribedSets, 3)
        XCTAssertEqual(menus[1].count, 7, "No new appearance buys the missing dose")
        XCTAssertEqual(menus[1].first { $0.exerciseName == "Leg Press" }?.prescribedSets, 2)
        let refusal = try XCTUnwrap(lunge.rejection)
        XCTAssertEqual(refusal.kind, .weeklyPriority)
        XCTAssertEqual(refusal.subject, "Quads")
        XCTAssertEqual(try XCTUnwrap(refusal.projected), 8, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(refusal.limit), 7.51, accuracy: 0.000001)
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
                let blueprint = weeks[weekIndex].blueprint
                let planned = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent,
                    weekNumber: weekIndex + 1, previousWeekDays: weekIndex == 0 ? nil : weeks[weekIndex - 1].days,
                    exerciseHistory: nil)
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
                XCTAssertEqual(baseline.map { $0.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.prescribedSets)" } },
                    weeks[weekIndex].days.map { $0.exercises.map { "\($0.exerciseName)|\($0.muscleTarget)|\($0.sets)" } },
                    "Trial baseline must match the exercises and doses actually delivered by procedural generation")
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
        XCTAssertGreaterThan(observedLockedDays, 0, "Exercise real previous-week ordering locks")
        XCTAssertGreaterThan(observedRetainedDays, 0, "Exercise real retained identities")
        XCTAssertGreaterThan(observedUnlockedFocusRetention, 0,
            "The real builder must capture retained identities even on focus days without an ordering lock")
        trialReport.append("SUBSTITUTION_TRIAL_SUMMARY attempted=\(attempted) dosePreserved=\(dosePreserved) qualified=\(qualified); live adoption NOT tested")
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
        let planned = service.preSelectedExercisePlan(for: blueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: history)
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
            let blueprint = service.programBlueprint(for: intent, weekNumber: weekNumber)
            var appearancePlanning: [String] = []
            var nextSetFunding: [SetFundingObservation] = []
            let menus = service.preSelectedExerciseMenu(
                for: blueprint,
                trainingIntent: intent,
                weekNumber: weekNumber,
                previousWeekDays: previous,
                appearancePlanningReport: { appearancePlanning.append($0) },
                setFundingReport: { nextSetFunding = $0 }
            )
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
                appearancePlanning: appearancePlanning, nextSetFunding: nextSetFunding))
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
                weeks: weeks.enumerated().map { index, week in
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
                        nextSetFunding: week.nextSetFunding
                    )
                }
            ))
            report.append("")
            report.append("PERSONA: \(persona.name)")

            for (index, week) in weeks.enumerated() {
                let days = week.days
                let weekNumber = index + 1
                let dayStart = ((weekNumber - 1) * 7) + 1
                let trainingDays = days.filter { !$0.isRestDay }
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
                        XCTAssertTrue(meetsWholeSetTarget(delivered: coverage.directSets,
                            ceiling: service.normalWeeklyPrioritySetCeiling(for: allocation)),
                            "\(persona.name) week \(weekNumber): \(allocation.area) whole-set target missed")
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
    func testTheSameAnalysisProducesTheSameProgramTwice() throws {
        for persona in personas {
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
                XCTAssertEqual(
                    lhs,
                    rhs,
                    "\(persona.name) week \(index + 1) differed between two identical runs"
                )
            }
        }
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
