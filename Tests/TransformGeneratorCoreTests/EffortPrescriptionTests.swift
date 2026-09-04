import Foundation
import XCTest
@testable import Transform

/// The effort field had a presence check and nothing else: `validateDaySet` asked whether
/// `targetRIR` was written, never what it said. The generation prompt meanwhile carries rule 4,
/// "REPS AND targetRIR MUST AGREE … a range programmed with reserve needs a higher one" — an
/// instruction with no enforcement behind it, which is the prompt-vs-validator drift this repo
/// lists as a known failure mode.
///
/// Both new rules are anchored to `EvidenceProfile.md`, not to invented numbers. `SLEEP-002`
/// takes the Restricted-tier cut from accessory hard-set exposure and biases accessories about
/// one rep FURTHER from failure while protecting intensity on the first hard sets; a value
/// outside 0...5 is simply not a usable prescription.
@MainActor
final class EffortPrescriptionTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - Builders

    private func calibration(tier: RecoveryTier) -> ClaudeService.ProgramCalibrationProfile {
        ClaudeService.ProgramCalibrationProfile(
            lowPerformanceDataQuality: false,
            poorNutritionAdherence: false,
            recoveryConstrained: tier == .constrained || tier == .restricted,
            recoveryTier: tier,
            recoveryAudit: "test fixture",
            recompositionGoal: false,
            weeklyVolumeScale: 1.0,
            reduceExerciseSlotComplexity: false,
            defaultSessionTimeCapMinutes: 70,
            sessionTimeCapsByStyle: [:],
            programmingNotes: []
        )
    }

    private func blueprint(tier: RecoveryTier) -> ClaudeService.ProgramBlueprint {
        ClaudeService.ProgramBlueprint(
            evidenceVersion: "test",
            splitRecommendation: "Upper/Lower",
            weeklyTrainingDays: 4,
            priorityAllocations: [],
            dayPlans: [],
            topLeverageChange: "",
            posturalFocus: "",
            injuryRiskFocus: "",
            programmingNotes: [],
            calibration: calibration(tier: tier)
        )
    }

    private func exercise(_ name: String, _ target: String, rir: Int?) -> WorkoutExerciseResponse {
        WorkoutExerciseResponse(
            exerciseName: name,
            sets: 3,
            reps: "10-12",
            tempo: "2-0-1-1",
            restSeconds: 90,
            notes: "Control the eccentric and brace.",
            muscleTarget: target,
            targetRIR: rir
        )
    }

    private func week(_ exercises: [WorkoutExerciseResponse]) -> [WorkoutDayResponse] {
        [
            WorkoutDayResponse(
                dayNumber: 1,
                dayName: "Training",
                muscleGroups: "",
                isRestDay: false,
                notes: "Work the plan.",
                exercises: exercises
            )
        ]
    }

    // MARK: - Out-of-range values are bad data

    func testAnImpossibleEffortValueIsFlagged() {
        for bad in [-1, 6, 9, 47] {
            let issues = service.validateEffortPrescription(
                days: week([exercise("Cable Lateral Raise", "Lateral Deltoids", rir: bad)]),
                blueprint: blueprint(tier: .ready)
            )
            XCTAssertEqual(issues.count, 1, "targetRIR \(bad) should be rejected: \(issues)")
            XCTAssertTrue(issues[0].contains("has an out-of-range targetRIR"), issues[0])
        }
    }

    func testEveryUsableEffortValueIsAccepted() {
        for good in 0...5 {
            let issues = service.validateEffortPrescription(
                days: week([exercise("Cable Lateral Raise", "Lateral Deltoids", rir: good)]),
                blueprint: blueprint(tier: .ready)
            )
            XCTAssertTrue(issues.isEmpty, "targetRIR \(good) is a legitimate prescription: \(issues)")
        }
    }

    /// A missing value is the OTHER rule's job (`validateDaySet`). This one must not double-report.
    func testAMissingEffortValueIsLeftToThePresenceRule() {
        let issues = service.validateEffortPrescription(
            days: week([exercise("Cable Lateral Raise", "Lateral Deltoids", rir: nil)]),
            blueprint: blueprint(tier: .ready)
        )
        XCTAssertTrue(issues.isEmpty, "\(issues)")
    }

    // MARK: - SLEEP-002: Restricted weeks bias accessories AWAY from failure

    func testAnAccessoryTakenToFailureOnARestrictedWeekIsFlagged() {
        for rir in [0, 1] {
            let issues = service.validateEffortPrescription(
                days: week([exercise("Cable Lateral Raise", "Lateral Deltoids", rir: rir)]),
                blueprint: blueprint(tier: .restricted)
            )
            XCTAssertEqual(issues.count, 1, "RIR \(rir) accessory on a Restricted week: \(issues)")
            XCTAssertTrue(issues[0].contains("on a Restricted-recovery week"), issues[0])
        }
    }

    /// `SLEEP-002` protects intensity on the first hard sets and directs the cut at accessory
    /// exposure, so a hard compound is exactly what Restricted is meant to KEEP. Flagging it
    /// would invert the rule.
    func testAHardCompoundOnARestrictedWeekIsNotFlagged() {
        let issues = service.validateEffortPrescription(
            days: week([
                exercise("Back Squat", "Quads", rir: 1),
                exercise("Barbell Romanian Deadlift", "Hamstrings", rir: 0)
            ]),
            blueprint: blueprint(tier: .restricted)
        )
        XCTAssertTrue(issues.isEmpty, "Anchors keep their intensity under SLEEP-002: \(issues)")
    }

    /// The rule is scoped to Restricted specifically. `SLEEP-002` gives Constrained a different,
    /// volume-only treatment (band-midpoint caps), with no instruction about proximity to failure.
    func testAConstrainedOrReadyWeekDoesNotTriggerTheEffortBias() {
        for tier: RecoveryTier in [.ready, .constrained, .insufficientData] {
            let issues = service.validateEffortPrescription(
                days: week([exercise("Cable Lateral Raise", "Lateral Deltoids", rir: 0)]),
                blueprint: blueprint(tier: tier)
            )
            XCTAssertTrue(issues.isEmpty, "\(tier) must not inherit the Restricted bias: \(issues)")
        }
    }

    func testRestDaysAreIgnored() {
        let rest = WorkoutDayResponse(
            dayNumber: 3,
            dayName: "Rest",
            muscleGroups: "",
            isRestDay: true,
            notes: "",
            exercises: [exercise("Cable Lateral Raise", "Lateral Deltoids", rir: 99)]
        )
        XCTAssertTrue(
            service.validateEffortPrescription(days: [rest], blueprint: blueprint(tier: .restricted)).isEmpty
        )
    }

    // MARK: - Wiring

    /// Both findings are AI-owned — the model writes `targetRIR` itself and can rewrite it without
    /// touching the locked menu — so both must be correction-worthy on the locked path rather than
    /// falling through to the silent default.
    func testBothEffortFindingsAreCorrectionWorthyAndExplainedInPlainLanguage() {
        let findings =
            service.validateEffortPrescription(
                days: week([exercise("Cable Lateral Raise", "Lateral Deltoids", rir: 9)]),
                blueprint: blueprint(tier: .ready)
            )
            + service.validateEffortPrescription(
                days: week([exercise("Cable Lateral Raise", "Lateral Deltoids", rir: 0)]),
                blueprint: blueprint(tier: .restricted)
            )

        XCTAssertEqual(findings.count, 2, "\(findings)")

        for finding in findings {
            XCTAssertEqual(
                service.validationDisposition(for: finding, menuLocked: true),
                .correctionPass,
                "targetRIR is a field the model can rewrite under menu-lock: \(finding)"
            )
            let notices = WorkoutValidatorNotice.notices(from: [finding])
            XCTAssertEqual(notices.count, 1)
            XCTAssertNotEqual(
                notices[0].headline,
                "A plan check didn't pass",
                "Effort finding renders as the unrecognised fallback: \(finding)"
            )
        }
    }

    /// The pre-existing presence rule had no owner-facing copy either, so it rendered as the
    /// unrecognised fallback for a finding the app understood perfectly well.
    func testTheMissingEffortFindingAlsoHasPlainLanguageCopy() {
        let issues = service.validateDaySet(
            week([exercise("Cable Lateral Raise", "Lateral Deltoids", rir: nil)]),
            dayStart: 1,
            dayEnd: 1
        )
        guard let finding = issues.first(where: { $0.contains("is missing targetRIR") }) else {
            XCTFail("Expected the presence rule to fire: \(issues)")
            return
        }
        let notices = WorkoutValidatorNotice.notices(from: [finding])
        XCTAssertEqual(notices.first?.headline != "A plan check didn't pass", true, finding)
    }
}
