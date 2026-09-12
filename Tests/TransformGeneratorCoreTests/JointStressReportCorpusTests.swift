import XCTest
@testable import Transform

/// Report shapes crossed with movements, for the joint-stress rules that read the lifter's
/// injury note. The shoulder side of this question has `ShoulderReportCorpusTests`; the
/// elbow / lower-back / knee side had no executed coverage at all before this file.
///
/// The rule under test is `reportedJointPainImplicates`, and the direction that matters is
/// FAIL-SAFE: a complaint the code cannot narrow to a specific movement must implicate the
/// movements anyway, because the alternative is a lifter who reported pain receiving no
/// caution. `reportNamesAnyJointStressMovement` is the gate that decides "did this report
/// name a lift?", and getting it wrong silently disables the fallback it exists to trigger.
///
/// The regression pinned here: that gate's phrase union contained the bare token "extension",
/// which belongs to the Triceps Extension family. "extension" is a JOINT ACTION, not a lift,
/// and it is ordinary anatomical prose — "lumbar extension", "thoracic extension", "hip
/// extension". Counting it made a report that named no movement read as specific, the
/// fallback never fired, and a lumbar-extension complaint produced zero lower-back caution.
/// This is the same trap `reportNamesAnyMovement` documents at length for "overhead" and
/// "scapular" on the shoulder side.
@MainActor
final class JointStressReportCorpusTests: XCTestCase {

    private let service = ClaudeService.shared

    // MARK: - The regression: an anatomical word must not pass as a named movement

    func testLumbarExtensionPainStillImplicatesTheHinge() {
        let report = "Lower back pain with lumbar extension."

        XCTAssertTrue(
            service.hasReportedRisk(for: .lowerBack, injuryRiskFocus: report),
            "Premise: this is a reported lower-back problem"
        )
        XCTAssertFalse(
            service.reportNamesAnyJointStressMovement(service.normalizedPriorityText(report)),
            "\"extension\" is a joint action, not a lift — this report names no movement"
        )
        XCTAssertTrue(
            service.reportedJointPainImplicates(
                .lowerBack,
                exerciseName: "Barbell Romanian Deadlift",
                muscleTarget: "Hamstrings",
                injuryRiskFocus: report
            ),
            "A lifter reporting lumbar pain must get lower-back caution on a heavy hinge"
        )
    }

    /// The same hole, reached through the other two phrasings a body-analysis model writes.
    func testOtherAnatomicalExtensionPhrasingsAlsoStayVague() {
        let reports = [
            "Low back discomfort provoked by repeated lumbar extension.",
            "Lumbar pain, worse with end-range extension."
        ]
        for report in reports {
            XCTAssertTrue(
                service.reportedJointPainImplicates(
                    .lowerBack,
                    exerciseName: "Barbell Romanian Deadlift",
                    muscleTarget: "Hamstrings",
                    injuryRiskFocus: report
                ),
                "Vague lumbar report must fail safe: \(report)"
            )
        }
    }

    // MARK: - The other direction: a report that DOES name a movement still narrows

    /// The word stays in its family, so a genuine triceps-extension complaint still reaches
    /// triceps-extension movements. Removing it from the family would have been the wrong fix.
    func testATricepsExtensionComplaintStillNarrowsToThatMovement() {
        let report = "Elbow pain with triceps extension."

        XCTAssertTrue(
            service.reportedJointPainImplicates(
                .elbow,
                exerciseName: "Overhead Cable Triceps Extension",
                muscleTarget: "Triceps",
                injuryRiskFocus: report
            ),
            "The movement the lifter actually named must still be implicated"
        )
    }

    /// And a specific complaint must still NOT spread to an unrelated movement — otherwise
    /// "fail safe" would just mean "penalise everything", which is the blanket behaviour the
    /// per-movement rules exist to end.
    func testASpecificComplaintDoesNotSpreadToAnUnrelatedLift() {
        let report = "Elbow pain with triceps extension."

        XCTAssertFalse(
            service.reportedJointPainImplicates(
                .elbow,
                exerciseName: "Barbell Curl",
                muscleTarget: "Biceps",
                injuryRiskFocus: report
            ),
            "A named triceps complaint should not charge the curl as well"
        )
    }

    /// A report naming a hinge by name narrows to it, unchanged by this fix.
    func testANamedDeadliftComplaintImplicatesTheHinge() {
        XCTAssertTrue(
            service.reportedJointPainImplicates(
                .lowerBack,
                exerciseName: "Barbell Romanian Deadlift",
                muscleTarget: "Hamstrings",
                injuryRiskFocus: "Lower back pain on deadlifts."
            )
        )
    }

    /// No reported problem means no implication at all — the gate before everything else.
    func testNoReportedProblemImplicatesNothing() {
        XCTAssertFalse(
            service.reportedJointPainImplicates(
                .lowerBack,
                exerciseName: "Barbell Romanian Deadlift",
                muscleTarget: "Hamstrings",
                injuryRiskFocus: "(none)"
            )
        )
    }
}
