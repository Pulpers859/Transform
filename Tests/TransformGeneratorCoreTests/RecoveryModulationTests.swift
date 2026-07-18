import XCTest
@testable import Transform

/// Headless coverage for the sleep-recovery modulation (EvidenceProfile SLEEP-001/SLEEP-002):
/// the tier decision runs on structured, dated numbers; tier cuts are whole-set caps anchored
/// to the VOL-001 evidence bands; and missing/stale data yields NO adjustment — never a
/// silent stale-string influence.
@MainActor
final class RecoveryModulationTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Builders

    private func state(
        builtDaysAgo: Double = 0,
        threeDay: Double = 7.5,
        sevenDay: Double = 7.4,
        acuteLogged: Int = 3,
        logged: Int = 7,
        underFive: Int = 0,
        underSix: Int = 0,
        variability: Double = 0.5,
        postCall: Bool = false
    ) -> SleepRecoveryState {
        SleepRecoveryState(
            builtAt: Date().addingTimeInterval(-builtDaysAgo * 86_400),
            threeDayAverageHours: threeDay,
            sevenDayAverageHours: sevenDay,
            acuteLoggedDays: acuteLogged,
            loggedDays: logged,
            daysUnderFive: underFive,
            daysUnderSix: underSix,
            variabilityHours: variability,
            recentPostCall: postCall
        )
    }

    private func calibration(tier: RecoveryTier) -> ClaudeService.ProgramCalibrationProfile {
        ClaudeService.ProgramCalibrationProfile(
            lowPerformanceDataQuality: false,
            poorNutritionAdherence: false,
            recoveryConstrained: tier == .constrained || tier == .restricted,
            recoveryTier: tier,
            recoveryAudit: "test",
            recompositionGoal: false,
            weeklyVolumeScale: 1.0,
            reduceExerciseSlotComplexity: false,
            defaultSessionTimeCapMinutes: 75,
            sessionTimeCapsByStyle: [:],
            programmingNotes: []
        )
    }

    private func highPriorityIntent(directSets: Double, stimulus: Double) -> ClaudeService.MusclePriorityIntent {
        ClaudeService.MusclePriorityIntent(
            area: "Back",
            priorityLevel: "High",
            rank: 0,
            rationale: "test",
            weeklyDayTarget: 2,
            weeklyExerciseTarget: 3,
            weeklyDirectSetTarget: directSets,
            weeklyStimulusTarget: stimulus,
            preferredStyles: ["Pull"],
            preferredMovementPatterns: ["row"],
            coverageKeywords: ["back"],
            accessoryCatalog: [],
            volumeBias: "High",
            directWorkBias: "Direct emphasis"
        )
    }

    private func blankAnalysis() -> BodyAnalysisResult {
        BodyAnalysisResult(
            overallAssessment: "", trainingAssessment: "", nutritionAssessment: "",
            recoveryRiskAssessment: "", adherenceAssessment: "", analysisLimitations: "",
            inputContext: nil, regionBreakdown: [], topLeverageChange: "",
            priorityMuscles: [], workoutRecommendations: [], dietRecommendations: [],
            posturalNotes: "", estimatedBodyFat: "", metabolicHealthNotes: "",
            psychologicalInsights: "", injuryRiskNotes: "", macroTargets: nil,
            structuredTrainingIntent: nil
        )
    }

    // MARK: - Tier decision policy (SLEEP-001)

    func testTierDecisionMatrix() {
        XCTAssertEqual(SleepRecoveryPolicy.decision(from: state()).tier, .ready)
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: state(sevenDay: 6.4)).tier, .constrained,
            "7-day average under 7h across a mostly-logged week is chronic mild shortfall"
        )
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: state(variability: 1.8)).tier, .constrained,
            "High night-to-night variability is a constrained signal"
        )
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: state(threeDay: 5.2)).tier, .restricted,
            "Acute 3-day average under 6h is restricted"
        )
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: state(underFive: 2)).tier, .restricted,
            "Two days under 5h in the week is restricted"
        )
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: state(postCall: true)).tier, .restricted,
            "A post-call recovery episode within 3 days is restricted"
        )
        XCTAssertEqual(SleepRecoveryPolicy.decision(from: nil).tier, .insufficientData)
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: state(acuteLogged: 0)).tier, .insufficientData,
            "Nothing logged in the acute window means no adjustment"
        )
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: state(logged: 2)).tier, .insufficientData,
            "Two logged days cannot justify a chronic volume adjustment"
        )
    }

    func testStaleStateProducesNoAdjustment() {
        let decision = SleepRecoveryPolicy.decision(from: state(builtDaysAgo: 5, threeDay: 4.5, underFive: 3))
        XCTAssertEqual(
            decision.tier, .insufficientData,
            "A stale state must not modulate, even when its (old) numbers look alarming"
        )
        XCTAssertTrue(decision.audit.contains("stale"), "The audit line must say WHY: \(decision.audit)")
    }

    func testAcuteSignalsFireEvenWithFewLoggedDays() {
        XCTAssertEqual(
            SleepRecoveryPolicy.decision(from: state(threeDay: 5.0, acuteLogged: 1, logged: 1)).tier,
            .restricted,
            "One measured terrible night is a valid acute signal; only chronic claims need 3+ days"
        )
    }

    func testJSONRoundTrip() {
        let original = state(threeDay: 5.9, sevenDay: 6.6, underFive: 1, postCall: true)
        let decoded = SleepRecoveryState.decodedJSON(original.encodedJSON())
        XCTAssertNotNil(decoded)
        if let decoded {
            XCTAssertEqual(decoded.threeDayAverageHours, original.threeDayAverageHours, accuracy: 0.001)
            XCTAssertEqual(decoded.recentPostCall, original.recentPostCall)
        }
        XCTAssertNil(SleepRecoveryState.decodedJSON(nil))
        XCTAssertNil(SleepRecoveryState.decodedJSON("not json"))
    }

    // MARK: - Band-anchored volume caps (SLEEP-002)

    func testRecoveryCapsAreWholeSetBandAnchors() throws {
        // VOL-001 High band is 8...12: restricted caps at the floor, constrained at midpoint.
        let intent = highPriorityIntent(directSets: 12.5, stimulus: 15.0)

        let restricted = service.adjustedPriorityIntent(intent, using: calibration(tier: .restricted))
        XCTAssertEqual(restricted.weeklyDirectSetTarget, 8.0, accuracy: 0.001,
                       "Restricted must cap a High priority at the band floor")
        XCTAssertGreaterThanOrEqual(restricted.weeklyStimulusTarget, restricted.weeklyDirectSetTarget + 1.0)

        let constrained = service.adjustedPriorityIntent(intent, using: calibration(tier: .constrained))
        XCTAssertEqual(constrained.weeklyDirectSetTarget, 10.0, accuracy: 0.001,
                       "Constrained must cap a High priority at the band midpoint")

        let ready = service.adjustedPriorityIntent(intent, using: calibration(tier: .ready))
        XCTAssertEqual(ready.weeklyDirectSetTarget, 12.5, accuracy: 0.001,
                       "Ready must not alter the evidence-derived target")

        let off = service.adjustedPriorityIntent(intent, using: calibration(tier: .insufficientData))
        XCTAssertEqual(off.weeklyDirectSetTarget, 12.5, accuracy: 0.001,
                       "Insufficient data must not alter the target — no silent modulation")
    }

    func testCapNeverLiftsATargetAlreadyBelowIt() throws {
        // A Low priority already at 4 sets stays at 4 under constrained (midpoint would be 4).
        let intent = ClaudeService.MusclePriorityIntent(
            area: "Calves", priorityLevel: "Low", rank: 2, rationale: "test",
            weeklyDayTarget: 1, weeklyExerciseTarget: 1,
            weeklyDirectSetTarget: 3.5, weeklyStimulusTarget: 5.0,
            preferredStyles: ["Legs"], preferredMovementPatterns: [],
            coverageKeywords: ["calves"], accessoryCatalog: [],
            volumeBias: "Low", directWorkBias: "Direct emphasis"
        )
        let adjusted = service.adjustedPriorityIntent(intent, using: calibration(tier: .constrained))
        XCTAssertEqual(adjusted.weeklyDirectSetTarget, 3.5, accuracy: 0.001,
                       "A cap is a ceiling, never a raise")
    }

    func testSlotFloorStaysConsistentWithCappedTarget() throws {
        let intent = highPriorityIntent(directSets: 12.0, stimulus: 14.0)
        let restricted = service.adjustedPriorityIntent(intent, using: calibration(tier: .restricted))
        XCTAssertGreaterThanOrEqual(
            Double(restricted.weeklyExerciseTarget) * 4.0,
            restricted.weeklyDirectSetTarget,
            "Slots must still be able to hold the capped target under the 4-set-per-exercise ceiling"
        )
    }

    // MARK: - Calibration end to end (structured decision -> tier -> profile)

    // Decisions are injected via calibrationProfile's parameter seam rather than written
    // through UserDefaults: `swift test --parallel` runs classes in separate processes
    // that share one defaults plist, so a stored-state write here could race the pinned
    // fixture test and flip its calibration mid-run.
    func testCalibrationAppliesInjectedRestrictedDecision() throws {
        let profile = service.calibrationProfile(
            from: blankAnalysis(),
            recoveryDecision: SleepRecoveryPolicy.decision(from: state(threeDay: 5.2))
        )
        XCTAssertEqual(profile.recoveryTier, .restricted)
        XCTAssertTrue(profile.recoveryConstrained)
        XCTAssertEqual(profile.weeklyVolumeScale, 1.0, accuracy: 0.001,
                       "Recovery must no longer contribute a flat scalar — the cut is the band cap")
        XCTAssertTrue(
            profile.programmingNotes.contains { $0.contains("RESTRICTED") },
            "The applied tier must be auditable in programming notes: \(profile.programmingNotes)"
        )
    }

    func testCalibrationStatesWhenModulationIsOff() throws {
        let profile = service.calibrationProfile(
            from: blankAnalysis(),
            recoveryDecision: SleepRecoveryPolicy.decision(from: nil)
        )
        XCTAssertEqual(profile.recoveryTier, .insufficientData)
        XCTAssertFalse(profile.recoveryConstrained)
        XCTAssertTrue(
            profile.programmingNotes.contains { $0.contains("Recovery modulation OFF") },
            "Turning modulation off must be stated, not silent: \(profile.programmingNotes)"
        )
    }

    func testProfileProseFallbackCanConstrainButNeverRestrict() throws {
        let analysis = BodyAnalysisResult(
            overallAssessment: "", trainingAssessment: "", nutritionAssessment: "",
            recoveryRiskAssessment: "Variable sleep from shift-work includes some nights under 5 hours.",
            adherenceAssessment: "", analysisLimitations: "",
            inputContext: nil, regionBreakdown: [], topLeverageChange: "",
            priorityMuscles: [], workoutRecommendations: [], dietRecommendations: [],
            posturalNotes: "", estimatedBodyFat: "", metabolicHealthNotes: "",
            psychologicalInsights: "", injuryRiskNotes: "", macroTargets: nil,
            structuredTrainingIntent: nil
        )
        let profile = service.calibrationProfile(
            from: analysis,
            recoveryDecision: SleepRecoveryPolicy.decision(from: nil)
        )
        XCTAssertEqual(
            profile.recoveryTier, .constrained,
            "Standing prose may justify constrained-level caution when no fresh logs exist"
        )
        XCTAssertTrue(profile.recoveryAudit.contains("no fresh sleep logs"),
                      "The audit must say the tier came from prose fallback: \(profile.recoveryAudit)")
    }
}
