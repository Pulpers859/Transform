import XCTest
@testable import Transform

/// Pins the free-barbell-squat within-day cap (EvidenceProfile SEQ-001): at most one
/// axial-loaded barbell squat per session, while stable machine/guided squats and leg
/// presses stay exempt so they can still accompany a barbell squat.
@MainActor
final class SquatPatternCapTests: XCTestCase {

    private let service = ClaudeService.shared

    private func entry(_ name: String, _ target: String = "Quads") -> (name: String, target: String) {
        (name, target)
    }

    // MARK: - Classification

    func testFreeBarbellSquatsAreRecognized() {
        XCTAssertTrue(service.isFreeBarbellSquat(exerciseName: "Back Squat", muscleTarget: "Quads"))
        XCTAssertTrue(service.isFreeBarbellSquat(exerciseName: "Front Squat", muscleTarget: "Quads"))
        // Plural naming must not defeat the match.
        XCTAssertTrue(service.isFreeBarbellSquat(exerciseName: "Back Squats", muscleTarget: "Quads"))
    }

    func testMachineAndImplementSquatsAreNotFreeBarbellSquats() {
        for name in ["Hack Squat", "Pendulum Squat", "Sissy Squat", "Belt Squat",
                     "Smith Machine Squat", "Goblet Squat", "Dumbbell Squat"] {
            XCTAssertFalse(
                service.isFreeBarbellSquat(exerciseName: name, muscleTarget: "Quads"),
                "\(name) is a guided/implement squat and must be exempt from the barbell cap"
            )
        }
    }

    func testLegPressAndSplitSquatAreNotInTheBarbellSquatClass() {
        // Different movement patterns entirely ("Press" / "Split Squat"), so they never
        // count toward the barbell-squat cap.
        XCTAssertFalse(service.isFreeBarbellSquat(exerciseName: "Leg Press", muscleTarget: "Quads"))
        XCTAssertFalse(service.isFreeBarbellSquat(exerciseName: "Bulgarian Split Squat", muscleTarget: "Quads/Glutes"))
    }

    // MARK: - The cap

    func testSecondFreeBarbellSquatIsBlocked() {
        XCTAssertFalse(
            service.dayPatternCapAllows(
                candidateName: "Front Squat", candidateTarget: "Quads",
                in: [entry("Back Squat")]
            ),
            "Back Squat + Front Squat in one session must be blocked at the first barbell squat"
        )
    }

    func testMachineSquatCanAccompanyABarbellSquat() {
        for machine in ["Hack Squat", "Pendulum Squat", "Leg Press"] {
            XCTAssertTrue(
                service.dayPatternCapAllows(
                    candidateName: machine, candidateTarget: "Quads",
                    in: [entry("Back Squat")]
                ),
                "\(machine) must still be allowed alongside a barbell squat"
            )
        }
    }

    func testBarbellSquatBlockedWhenAMachineSquatCameFirst() {
        // Order independence: a barbell squat is still capped even if the machine squat
        // was selected first.
        XCTAssertTrue(
            service.dayPatternCapAllows(candidateName: "Back Squat", candidateTarget: "Quads",
                                        in: [entry("Hack Squat")]),
            "One barbell squat is fine next to a machine squat"
        )
        XCTAssertFalse(
            service.dayPatternCapAllows(candidateName: "Front Squat", candidateTarget: "Quads",
                                        in: [entry("Hack Squat"), entry("Back Squat")]),
            "The barbell squat slot is already taken by Back Squat"
        )
    }

    func testGenericTwoPerPatternCapStillAppliesToMachineSquats() {
        // Machine squats share the "Squat" movement pattern, so the general <=2 cap still
        // holds for them even though the stricter barbell cap does not.
        XCTAssertTrue(
            service.dayPatternCapAllows(candidateName: "Pendulum Squat", candidateTarget: "Quads",
                                        in: [entry("Hack Squat")]),
            "Two machine squats are allowed under the general two-per-pattern cap"
        )
        XCTAssertFalse(
            service.dayPatternCapAllows(candidateName: "Belt Squat", candidateTarget: "Quads",
                                        in: [entry("Hack Squat"), entry("Pendulum Squat")]),
            "A third same-pattern squat exceeds the general two-per-pattern cap"
        )
    }
}
