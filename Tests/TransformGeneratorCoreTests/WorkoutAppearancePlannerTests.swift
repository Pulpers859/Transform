import XCTest
@testable import Transform

final class WorkoutAppearancePlannerTests: XCTestCase {
    func testRepeatedAppearancesReserveSeparateDosesAndProtectLateExposure() {
        let problem = WorkoutAppearancePlanner.Problem(protected: [false, false, false],
            upperBounds: [.init(name: "weekly", coefficients: [2, 2, 2], limit: 4)],
            lowerBounds: [.init(name: "early", coefficients: [1, 1, 0], limit: 1),
                          .init(name: "late", coefficients: [0, 0, 1], limit: 1)],
            removalOrder: [2, 1, 0])
        XCTAssertEqual(WorkoutAppearancePlanner.solve(problem), .admitted([0, 2]))
        XCTAssertEqual(WorkoutAppearancePlanner.solve(problem, maximumStates: 1), .searchLimit(["weekly"]))
        XCTAssertEqual(WorkoutAppearancePlanner.solve(problem, maximumStates: 2), .admitted([0, 2]))
    }

    func testProtectedInfeasiblePlanIsNotReportedAsFunded() {
        let problem = WorkoutAppearancePlanner.Problem(protected: [true, true],
            upperBounds: [.init(name: "fatigue", coefficients: [9, 9], limit: 10)],
            lowerBounds: [], removalOrder: [0, 1])
        XCTAssertEqual(WorkoutAppearancePlanner.solve(problem), .infeasible(["fatigue"]))
    }

    func testOptionalThirdExposureCanBeRemovedWhileTwoRequiredDaysSurvive() {
        let problem = WorkoutAppearancePlanner.Problem(protected: [false, false, true],
            upperBounds: [.init(name: "weekly", coefficients: [2, 2, 2], limit: 5)],
            lowerBounds: [], removalOrder: [0, 1, 2],
            coverage: [.init(name: "frequency", groups: [[0], [1], [2]], minimumGroups: 2)])
        XCTAssertEqual(WorkoutAppearancePlanner.solve(problem), .admitted([1, 2]))
    }
}
