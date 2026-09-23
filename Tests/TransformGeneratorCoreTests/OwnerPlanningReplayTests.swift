import Foundation
import XCTest
@testable import Transform

/// Synthetic shape replay only: no owner analysis, photos, logs, dates or history.
/// Findings are diagnostic evidence, not assertions that historical defects should persist.
@MainActor
final class OwnerPlanningReplayTests: XCTestCase {
    private let service = ClaudeService.shared

    private func priority(_ area: String, level: String = "High", days: Int,
                          slots: Int = 3, styles: [String], patterns: [String]) -> StructuredTrainingPriority {
        .init(area: area, priorityLevel: level, rationale: "Synthetic priority.",
            weeklyDayTarget: days, weeklyExerciseTarget: slots, preferredStyles: styles,
            preferredMovementPatterns: patterns, volumeBias: level == "High" ? "High" : "Moderate",
            directWorkBias: level == "High" ? "Direct emphasis" : "Maintenance")
    }

    func testSyntheticFiveDayConstrainedPlanningReplay() throws {
        let structured = StructuredTrainingIntent(
            splitRecommendation: "Upper/Lower or Push/Pull/Legs over 5 days", weeklyTrainingDays: 5,
            priorities: [
                priority("Upper Chest", days: 2, styles: ["Push", "Upper"],
                    patterns: ["incline barbell press", "incline dumbbell press", "low-to-high cable fly", "clavicular", "incline press"]),
                priority("Lateral Deltoids", days: 3, styles: ["Push", "Upper", "Arms"],
                    patterns: ["cable lateral raise", "dumbbell lateral raise", "lateral delt", "lateral raise"]),
                priority("Core/Abs", level: "Medium", days: 2, slots: 2, styles: ["Upper", "Legs"],
                    patterns: ["cable crunch", "hanging or lying leg raise", "abdominal", "oblique", "serratus", "crunch"])
            ], programmingNotes: ["Keep specialization volume recoverable."])
        let analysis = BodyAnalysisResult(
            overallAssessment: "Synthetic body recomposition profile.", trainingAssessment: "",
            nutritionAssessment: "No nutrition logs were recorded.",
            recoveryRiskAssessment: "Variable sleep from shift-work includes some nights under 5 hours.",
            adherenceAssessment: "", analysisLimitations: "", inputContext: nil, regionBreakdown: [],
            topLeverageChange: "", priorityMuscles: ["Upper Chest", "Lateral Deltoids", "Rectus Abdominis"],
            workoutRecommendations: [], dietRecommendations: [], posturalNotes: "", estimatedBodyFat: "",
            metabolicHealthNotes: "", psychologicalInsights: "",
            injuryRiskNotes: "Shoulder pain during neutral-grip overhead pressing.", macroTargets: nil,
            structuredTrainingIntent: structured)
        // Do not read or mutate shared UserDefaults; inject missing measured sleep explicitly.
        let calibration = service.calibrationProfile(from: analysis,
            recoveryDecision: SleepRecoveryPolicy.decision(from: nil))
        XCTAssertEqual(calibration.recoveryTier, .constrained)
        XCTAssertTrue(calibration.recoveryAudit.contains("no fresh sleep logs"))
        let base = ClaudeService.TrainingIntentPlan(
            splitRecommendation: structured.splitRecommendation, weeklyTrainingDays: structured.weeklyTrainingDays,
            programmingNotes: structured.programmingNotes,
            priorities: service.mergedPriorityIntents(structured.priorities.enumerated().map {
                service.musclePriorityIntent(from: $0.element, rank: $0.offset, analysis: analysis)
            }), topLeverageChange: "(not provided)", posturalFocus: "(none)",
            injuryRiskFocus: service.resolvedInjuryRiskFocus(from: analysis),
            calibration: service.neutralCalibrationProfile())
        let intent = service.calibratedTrainingIntentPlan(base, using: calibration)
        let initialBlueprint = service.programBlueprint(for: intent, weekNumber: 1)
        var baseline: ClaudeService.SubstitutionPlanningBaseline?
        var pressdown: ClaudeService.PressdownFinalization?
        var preCore: ClaudeService.SubstitutionPlanningBaseline?
        var core: ClaudeService.CoreRelocationFinalization?
        var preRow: ClaudeService.SubstitutionPlanningBaseline?
        var rowResult: ClaudeService.RowBalanceFinalization?
        var diagnostics: [String] = []
        var callbackCounts = [0, 0]
        let delivered = service.preSelectedExercisePlan(for: initialBlueprint, trainingIntent: intent,
            weekNumber: 1, previousWeekDays: nil, exerciseHistory: nil,
            appearancePlanningReport: { diagnostics.append($0) },
            pressdownPlanningReport: { baseline = $0; pressdown = $1; callbackCounts[0] += 1 },
            corePlanningReport: { preCore = $0; core = $1; callbackCounts[1] += 1 },
            rowPlanningReport: { preRow = $0; rowResult = $1 })
        XCTAssertEqual(callbackCounts, [1, 1])
        let original = try XCTUnwrap(preRow)
        let pressdownInput = try XCTUnwrap(baseline)
        let rowFinalization = try XCTUnwrap(rowResult)
        let pressdownResult = try XCTUnwrap(pressdown)
        let coreInput = try XCTUnwrap(preCore)
        let coreResult = try XCTUnwrap(core)
        XCTAssertEqual(snapshot(coreInput.menus), snapshot(pressdownResult.plan.menus))
        XCTAssertEqual(snapshot(delivered.menus), snapshot(coreResult.plan.menus))
        XCTAssertEqual(delivered.blueprint, coreResult.plan.blueprint)
        XCTAssertEqual(snapshot(pressdownInput.menus), snapshot(rowFinalization.plan.menus))
        // This complete, admitted week reproduced the missed repair: selection used one-set
        // seeds, while allocation produced 6 vertical / 2 rowing sets. Exercise the production
        // finalizer, not an invented sparse menu that cannot satisfy appearance reservation.
        XCTAssertEqual(original.roleFloorAdmission, .admitted)
        let originalBack = rowSummary(original.menus, blueprint: original.blueprint)
        XCTAssertEqual(originalBack.verticalSets, 6)
        XCTAssertEqual(originalBack.rowingSets, 2)
        XCTAssertEqual(delivered.roleFloorAdmission, .admitted)
        let fundedBack = rowSummary(delivered.menus, blueprint: delivered.blueprint)
        XCTAssertEqual(fundedBack.verticalSets, 3)
        XCTAssertEqual(fundedBack.rowingSets, 5)
        XCTAssertEqual(delivered.menus.map(\.count), original.menus.map(\.count))
        XCTAssertEqual(delivered.menus.map { $0.map(\.prescribedSets) }, original.menus.map { $0.map(\.prescribedSets) })
        XCTAssertTrue(service.plannedBackBalanceFindings(delivered.menus, blueprint: delivered.blueprint).isEmpty)
        let changes = original.menus.indices.flatMap { day in
            original.menus[day].indices.compactMap { slot -> String? in
                let old = original.menus[day][slot], new = delivered.menus[day][slot]
                return old.exerciseName == new.exerciseName ? nil : "\(old.exerciseName) -> \(new.exerciseName)"
            }
        }
        XCTAssertEqual(changes, ["Lat Pulldown -> Single-Arm Dumbbell Row"])
        guard case .dosePreserved = service.compareAllocatedDoseOnly(delivered.menus, baseline: original.menus,
            blueprint: original.blueprint, weekNumber: 1) else {
            return XCTFail("A row improvement must preserve complete-plan dose")
        }
        XCTAssertEqual(service.preflightFixedDoseSubstitution(delivered.menus, plannedBaseline: original), .structurallyEligible)
        // Retained identities and non-admitted plans must fail closed with the exact baseline.
        var retained = original.retainedKeysByDay
        for day in original.menus.indices {
            retained[day].formUnion(original.menus[day].map { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) })
        }
        let protected = ClaudeService.SubstitutionPlanningBaseline(menus: original.menus, blueprint: original.blueprint,
            weekNumber: original.weekNumber, lockedPrefixCounts: original.lockedPrefixCounts,
            retainedKeysByDay: retained, exerciseHistory: original.exerciseHistory,
            selectionFocusIntents: original.selectionFocusIntents, roleFloorAdmission: original.roleFloorAdmission)
        let protectedResult = service.finalizeRowBalance(protected, trainingIntent: intent,
            baselineMessages: ["retained marker"], baselineReceipts: [], collectFunding: false)
        XCTAssertEqual(snapshot(protectedResult.plan.menus), snapshot(original.menus))
        XCTAssertEqual(protectedResult.messages, ["retained marker"])
        let malformed = ClaudeService.SubstitutionPlanningBaseline(menus: original.menus + [[]], blueprint: original.blueprint,
            weekNumber: original.weekNumber, lockedPrefixCounts: original.lockedPrefixCounts,
            retainedKeysByDay: original.retainedKeysByDay, exerciseHistory: original.exerciseHistory,
            selectionFocusIntents: original.selectionFocusIntents, roleFloorAdmission: .admitted)
        let malformedResult = service.finalizeRowBalance(malformed, trainingIntent: intent,
            baselineMessages: [], baselineReceipts: [], collectFunding: false)
        XCTAssertEqual(malformedResult.decision, "invalid planning context")
        XCTAssertEqual(snapshot(malformedResult.plan.menus), snapshot(malformed.menus))
        for status: ClaudeService.RoleFloorAdmission in [.unassessed, .deloadPolicy, .infeasible(["fixture"]), .searchLimit(["fixture"])] {
            var refused = original
            refused.roleFloorAdmission = status
            let result = service.finalizeRowBalance(refused, trainingIntent: intent,
                baselineMessages: [], baselineReceipts: [], collectFunding: false)
            XCTAssertEqual(snapshot(result.plan.menus), snapshot(original.menus))
            XCTAssertEqual(result.plan.roleFloorAdmission, status)
        }
        let program = try service.validatedProceduralWeekOneProgram(from: analysis, trainingIntent: intent,
            blueprint: delivered.blueprint, exerciseMenus: delivered.menus)
        let findings = service.validateProgramResponse(program, blueprint: delivered.blueprint,
            expectedExerciseMenus: delivered.menus)
        XCTAssertEqual(program.days.count, 7)
        XCTAssertEqual(program.days.filter { !$0.isRestDay }.count, 5)
        XCTAssertEqual(program.days.count, delivered.menus.count)
        for (day, menu) in zip(program.days, delivered.menus) {
            XCTAssertEqual(day.exercises.map(\.exerciseName), menu.map(\.exerciseName))
            XCTAssertEqual(day.exercises.map(\.sets), menu.map(\.prescribedSets))
            XCTAssertTrue(day.exercises.allSatisfy { $0.sets > 0 })
            XCTAssertTrue(day.isRestDay ? day.exercises.isEmpty : !day.exercises.isEmpty)
        }
        let deliveredBaseline = coreResult.plan
        let unchangedMenus = snapshot(deliveredBaseline.menus)
        let rowTrials = rowingTrials(baseline: deliveredBaseline, intent: intent, analysis: analysis)
        XCTAssertLessThanOrEqual(rowTrials.count, 3)
        let rowBaseline = rowSummary(deliveredBaseline.menus, blueprint: deliveredBaseline.blueprint)
        if rowBaseline.verticalSets > rowBaseline.rowingSets {
            XCTAssertFalse(rowTrials.isEmpty, "A vertical-heavy back plan must exercise at least one diagnostic proposal, including zero-row plans")
        }
        XCTAssertEqual(snapshot(deliveredBaseline.menus), unchangedMenus, "Diagnostic proposals never adopt into the baseline")
        XCTAssertEqual(snapshot(delivered.menus), unchangedMenus)
        let evidence = ReplayEvidence(analysis: analysis,
            initialBlueprint: BlueprintEvidence(initialBlueprint), blueprint: BlueprintEvidence(delivered.blueprint),
            baselineMenus: snapshot(original.menus), postPressdownMenus: snapshot(pressdownResult.plan.menus),
            menus: snapshot(delivered.menus), days: program.days, validatorFindings: findings,
            baselineAdmission: String(describing: original.roleFloorAdmission),
            pressdownDecision: String(describing: pressdownResult.decision),
            coreDecision: String(describing: coreResult.decision), diagnostics: diagnostics,
            rowBaselineContext: .init(weekNumber: deliveredBaseline.weekNumber,
                lockedPrefixCounts: deliveredBaseline.lockedPrefixCounts,
                retainedKeysByDay: deliveredBaseline.retainedKeysByDay.map { $0.sorted() },
                selectionFocusContexts: deliveredBaseline.selectionFocusIntents.map { $0.map { String(describing: $0) } },
                admission: String(describing: deliveredBaseline.roleFloorAdmission),
                historySupplied: deliveredBaseline.exerciseHistory != nil), rowTrials: rowTrials)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(evidence)
        // Check the export schema even when no artifact destination was requested.
        _ = try JSONDecoder().decode(ReplayEvidence.self, from: data)
        if let path = ProcessInfo.processInfo.environment["TRANSFORM_OWNER_REPLAY_OUTPUT"], !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    }

    private func snapshot(_ menus: [[ClaudeService.PreSelectedExercise]]) -> [[MenuEvidence]] {
        menus.map { $0.map { MenuEvidence(exerciseName: $0.exerciseName, muscleTarget: $0.muscleTarget,
            movementPattern: $0.movementPattern, role: $0.role.rawValue, prescribedSets: $0.prescribedSets) } }
    }

    /// Diagnostic only. Reuse the one actual delivered baseline; never rerun complete selection,
    /// append an appearance, relax preflight, or adopt a trial. At most three fresh allocations.
    private func rowingTrials(baseline: ClaudeService.SubstitutionPlanningBaseline,
                              intent: ClaudeService.TrainingIntentPlan, analysis: BodyAnalysisResult) -> [RowTrialEvidence] {
        let menus = baseline.menus
        let locations = menus.indices.filter { !baseline.blueprint.dayPlans[$0].isRestDay }
            .flatMap { day in menus[day].indices.map { (day, $0) } }
        let donors = locations.filter { day, slot in
            let entry = menus[day][slot]
            return entry.role != .anchor && matchesBackPattern(entry, patterns: service.verticalPullPatterns)
        }
        let rows = locations.filter { day, slot in
            matchesBackPattern(menus[day][slot], patterns: service.horizontalPullPatterns)
        }
        var proposals: [(kind: String, edit: String, menus: [[ClaudeService.PreSelectedExercise]])] = []
        if let donor = donors.first(where: { menus[$0.0][$0.1].prescribedSets > 1 }), let row = rows.first {
            var candidate = menus
            candidate[donor.0][donor.1].prescribedSets -= 1
            candidate[row.0][row.1].prescribedSets += 1
            proposals.append(("oneSetTransfer", "day \(donor.0 + 1) \(menus[donor.0][donor.1].exerciseName) -1; day \(row.0 + 1) \(menus[row.0][row.1].exerciseName) +1", candidate))
        }
        var substitutions = 0
        var proposedRowKeys = Set<String>()
        for donor in donors {
            guard substitutions < 2 else { break }
            let old = menus[donor.0][donor.1]
            for alternative in service.exerciseCatalog(for: baseline.blueprint.dayPlans[donor.0].style) {
                guard substitutions < 2 else { break }
                guard alternative.target == old.muscleTarget,
                      let pattern = service.menuMovementPattern(forExerciseName: alternative.name, muscleTarget: alternative.target),
                      service.horizontalPullPatterns.contains(pattern) else { continue }
                let key = ExerciseWeightEntry.canonicalLookupKey(alternative.name)
                // Spend the two trial slots on distinct row identities, not aliases or the same
                // row swapped into two donors. Existing same-day rows cannot be added twice.
                guard !proposedRowKeys.contains(key),
                      !menus[donor.0].contains(where: { ExerciseWeightEntry.canonicalLookupKey($0.exerciseName) == key }) else { continue }
                var candidate = menus
                candidate[donor.0][donor.1] = .init(exerciseName: alternative.name, muscleTarget: alternative.target,
                    movementPattern: service.exerciseMetadata(forExerciseName: alternative.name, muscleTarget: alternative.target).movementPattern,
                    role: service.proceduralExerciseRole(for: alternative.name, muscleTarget: alternative.target),
                    prescribedSets: old.prescribedSets)
                guard matchesBackPattern(candidate[donor.0][donor.1], patterns: service.horizontalPullPatterns) else { continue }
                proposals.append(("sameTargetCatalogSubstitution", "day \(donor.0 + 1) slot \(donor.1 + 1): \(old.exerciseName) -> \(alternative.name)", candidate))
                substitutions += 1
                proposedRowKeys.insert(key)
            }
        }
        XCTAssertLessThanOrEqual(proposals.count, 3)
        return proposals.map { proposal in
            XCTAssertEqual(proposal.menus.map(\.count), menus.map(\.count), "No appearance growth")
            let preflight = proposal.kind == "sameTargetCatalogSubstitution"
                ? String(describing: service.preflightFixedDoseSubstitution(proposal.menus, plannedBaseline: baseline))
                : "not applicable: fixed-dose substitution preflight does not authorize set transfers"
            let dose = service.compareAllocatedDoseOnly(proposal.menus, baseline: menus,
                blueprint: baseline.blueprint, weekNumber: baseline.weekNumber)
            var admission: ClaudeService.RoleFloorAdmission = .unassessed
            var receipts: [SetFundingObservation] = []
            var messages: [String] = []
            let allocated = service.allocateWeeklySetPrescription(proposal.menus, blueprint: baseline.blueprint,
                weekNumber: baseline.weekNumber, lockedPrefixCounts: baseline.lockedPrefixCounts,
                appearancePlanningReport: { messages.append($0) }, setFundingReport: { receipts = $0 },
                roleFloorAdmissionReport: { admission = $0 }, publishConflictLogs: false)
            let ordered = service.reorderedMenusForSessionFlow(allocated, blueprint: baseline.blueprint,
                trainingIntent: intent, lockedPrefixCounts: baseline.lockedPrefixCounts)
            let finalDose = service.compareAllocatedDoseOnly(ordered, baseline: menus,
                blueprint: baseline.blueprint, weekNumber: baseline.weekNumber)
            var deliveryDays: [WorkoutDayResponse] = []
            var findings: [String] = []
            var deliveryError: String?
            var deliveryMatchesMenus: Bool?
            do {
                let delivery = try service.validatedProceduralWeekOneProgram(from: analysis, trainingIntent: intent,
                    blueprint: baseline.blueprint, exerciseMenus: ordered)
                deliveryDays = delivery.days
                findings = service.validateProgramResponse(delivery, blueprint: baseline.blueprint, expectedExerciseMenus: ordered)
                deliveryMatchesMenus = delivery.days.count == ordered.count && zip(delivery.days, ordered).allSatisfy { day, menu in
                    day.exercises.map(\.exerciseName) == menu.map(\.exerciseName)
                        && day.exercises.map(\.muscleTarget) == menu.map(\.muscleTarget)
                        && day.exercises.map(\.sets) == menu.map(\.prescribedSets)
                }
            } catch {
                deliveryError = String(describing: error)
            }
            // This is deliberately diagnostic, not an acceptance gate for a proposed
            // replacement: preflight, dose, and validator findings remain evidence that
            // may reject the candidate. The invariant below only ensures the procedural
            // replay cannot silently diverge from its own ordered locked menu.
            if deliveryError == nil {
                XCTAssertEqual(deliveryMatchesMenus, true, "A successful diagnostic delivery must remain menu-locked")
            } else {
                XCTAssertNil(deliveryMatchesMenus, "A failed diagnostic delivery cannot claim menu equivalence")
            }
            return RowTrialEvidence(kind: proposal.kind, edit: proposal.edit,
                preflight: preflight, doseComparison: String(describing: dose),
                before: rowSummary(menus, blueprint: baseline.blueprint),
                proposed: rowSummary(proposal.menus, blueprint: baseline.blueprint),
                afterAllocationAndOrdering: rowSummary(ordered, blueprint: baseline.blueprint),
                proposedMenus: snapshot(proposal.menus), allocatedMenus: snapshot(allocated), orderedMenus: snapshot(ordered),
                allocationAdmission: String(describing: admission), allocationMessages: messages, allocationReceipts: receipts,
                allocationPreservedProposal: snapshot(allocated) == snapshot(proposal.menus),
                orderingPreservedAllocation: snapshot(ordered) == snapshot(allocated), finalDoseComparison: String(describing: finalDose),
                deliveryDays: deliveryDays, deliveryMatchesMenus: deliveryMatchesMenus,
                validatorFindings: findings, deliveryError: deliveryError)
        }
    }

    private func matchesBackPattern(_ exercise: ClaudeService.PreSelectedExercise, patterns: Set<String>) -> Bool {
        guard let pattern = service.menuMovementPattern(forExerciseName: exercise.exerciseName,
            muscleTarget: exercise.muscleTarget), patterns.contains(pattern) else { return false }
        return service.exerciseDirectlyTargets(groupAliases: service.normalizedGroupAliases(forSeed: "back"),
            exerciseName: exercise.exerciseName, muscleTarget: exercise.muscleTarget)
    }

    private func rowSummary(_ menus: [[ClaudeService.PreSelectedExercise]], blueprint: ClaudeService.ProgramBlueprint) -> RowSummary {
        // Same pattern AND direct Back eligibility as validateBackPatternBalance; ignore rest days.
        let active = menus.indices.filter { !blueprint.dayPlans[$0].isRestDay }.flatMap { menus[$0] }
        func sets(_ patterns: Set<String>) -> Int {
            active.filter { matchesBackPattern($0, patterns: patterns) }.reduce(0) { $0 + $1.prescribedSets }
        }
        return .init(verticalSets: sets(service.verticalPullPatterns), rowingSets: sets(service.horizontalPullPatterns), slotsByDay: menus.map(\.count))
    }

    private struct RowBaselineContext: Codable {
        let weekNumber: Int
        let lockedPrefixCounts: [Int]
        let retainedKeysByDay: [[String]]
        let selectionFocusContexts: [String?]
        let admission: String
        let historySupplied: Bool
    }

    private struct RowSummary: Codable {
        let verticalSets: Int, rowingSets: Int
        let slotsByDay: [Int]
    }

    private struct RowTrialEvidence: Codable {
        var scope = "Synthetic diagnostic only; NOT ADOPTED. Substitution eligibility and dose comparison are separate. No whole-block or private-history proof. Delivery uses the freshly allocated, ordered candidate."
        var allocationReceiptCoordinates = "Zero-based dayIndex/exerciseIndex in allocatedMenus BEFORE ordering, not orderedMenus or deliveryDays."
        let kind: String, edit: String, preflight: String, doseComparison: String
        let before: RowSummary, proposed: RowSummary, afterAllocationAndOrdering: RowSummary
        let proposedMenus: [[MenuEvidence]], allocatedMenus: [[MenuEvidence]], orderedMenus: [[MenuEvidence]]
        let allocationAdmission: String
        let allocationMessages: [String]
        let allocationReceipts: [SetFundingObservation]
        let allocationPreservedProposal: Bool, orderingPreservedAllocation: Bool
        let finalDoseComparison: String
        let deliveryDays: [WorkoutDayResponse]
        let deliveryMatchesMenus: Bool?
        let validatorFindings: [String]
        let deliveryError: String?
    }

    private struct MenuEvidence: Codable, Equatable {
        let exerciseName: String
        let muscleTarget: String
        let movementPattern: String
        let role: String
        let prescribedSets: Int
    }

    private struct ReplayEvidence: Codable {
        var schemaVersion = 2
        var scope = "Synthetic network-free procedural replay; no private history, live AI, or iPhone/UI validation."
        let analysis: BodyAnalysisResult
        let initialBlueprint: BlueprintEvidence
        let blueprint: BlueprintEvidence
        let baselineMenus: [[MenuEvidence]]
        let postPressdownMenus: [[MenuEvidence]]
        let menus: [[MenuEvidence]]
        let days: [WorkoutDayResponse]
        let validatorFindings: [String]
        let baselineAdmission: String
        let pressdownDecision: String
        let coreDecision: String
        let diagnostics: [String]
        let rowBaselineContext: RowBaselineContext
        let rowTrials: [RowTrialEvidence]
    }

    private struct BlueprintEvidence: Codable {
        let evidenceVersion: String
        let splitRecommendation: String
        let weeklyTrainingDays: Int
        let priorityAllocations: [PriorityEvidence]
        let dayPlans: [DayEvidence]
        let topLeverageChange: String
        let posturalFocus: String
        let injuryRiskFocus: String
        let programmingNotes: [String]
        let calibration: CalibrationEvidence
        init(_ value: ClaudeService.ProgramBlueprint) {
            evidenceVersion = value.evidenceVersion; splitRecommendation = value.splitRecommendation
            weeklyTrainingDays = value.weeklyTrainingDays
            priorityAllocations = value.priorityAllocations.map(PriorityEvidence.init)
            dayPlans = value.dayPlans.map(DayEvidence.init)
            topLeverageChange = value.topLeverageChange; posturalFocus = value.posturalFocus
            injuryRiskFocus = value.injuryRiskFocus; programmingNotes = value.programmingNotes
            calibration = CalibrationEvidence(value.calibration)
        }
    }

    private struct PriorityEvidence: Codable {
        let area: String, priorityLevel: String, rationale: String
        let targetFrequency: Int, targetExerciseSlots: Int
        let directSetTarget: Double, weightedStimulusTarget: Double
        let maxPerSessionDirectSets: Double, maxFocusSessionDirectSets: Double
        let preferredStyles: [String], preferredMovementPatterns: [String]
        let volumeBias: String, directWorkBias: String
        init(_ value: ClaudeService.BlueprintPriorityAllocation) {
            area = value.area; priorityLevel = value.priorityLevel; rationale = value.rationale
            targetFrequency = value.targetFrequency; targetExerciseSlots = value.targetExerciseSlots
            directSetTarget = value.directSetTarget; weightedStimulusTarget = value.weightedStimulusTarget
            maxPerSessionDirectSets = value.maxPerSessionDirectSets; maxFocusSessionDirectSets = value.maxFocusSessionDirectSets
            preferredStyles = value.preferredStyles; preferredMovementPatterns = value.preferredMovementPatterns
            volumeBias = value.volumeBias; directWorkBias = value.directWorkBias
        }
    }

    private struct DayEvidence: Codable {
        let dayIndex: Int
        let style: String, focusArea: String?
        let supportAreas: [String]
        let targetFatigueCap: Int, targetSessionMinutes: Int, targetPrioritySlots: Int
        let emphasisPatterns: [String]
        let isRestDay: Bool
        init(_ value: ClaudeService.BlueprintDayPlan) {
            dayIndex = value.dayIndex; style = value.style; focusArea = value.focusArea
            supportAreas = value.supportAreas; targetFatigueCap = value.targetFatigueCap
            targetSessionMinutes = value.targetSessionMinutes; targetPrioritySlots = value.targetPrioritySlots
            emphasisPatterns = value.emphasisPatterns; isRestDay = value.isRestDay
        }
    }

    private struct CalibrationEvidence: Codable {
        let lowPerformanceDataQuality: Bool, poorNutritionAdherence: Bool, recoveryConstrained: Bool
        let recoveryTier: String, recoveryAudit: String
        let recompositionGoal: Bool
        let weeklyVolumeScale: Double
        let reduceExerciseSlotComplexity: Bool
        let defaultSessionTimeCapMinutes: Int
        let sessionTimeCapsByStyle: [String: Int]
        let programmingNotes: [String]
        init(_ value: ClaudeService.ProgramCalibrationProfile) {
            lowPerformanceDataQuality = value.lowPerformanceDataQuality; poorNutritionAdherence = value.poorNutritionAdherence
            recoveryConstrained = value.recoveryConstrained; recoveryTier = String(describing: value.recoveryTier)
            recoveryAudit = value.recoveryAudit; recompositionGoal = value.recompositionGoal
            weeklyVolumeScale = value.weeklyVolumeScale; reduceExerciseSlotComplexity = value.reduceExerciseSlotComplexity
            defaultSessionTimeCapMinutes = value.defaultSessionTimeCapMinutes
            sessionTimeCapsByStyle = value.sessionTimeCapsByStyle; programmingNotes = value.programmingNotes
        }
    }
}
