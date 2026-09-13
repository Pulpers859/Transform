import Foundation

// Executable against the shipping, Foundation-only solver on Windows as well as macOS.
@main
struct AppearancePlannerChecks {
    static func main() {
        typealias C = WorkoutAppearancePlanner.Constraint
        typealias P = WorkoutAppearancePlanner.Problem
        let weekly = C(name: "shared weekly", coefficients: [2, 2, 2], limit: 4)
        let late = C(name: "late focus", coefficients: [0, 0, 1], limit: 1)
        let early = C(name: "early exposure", coefficients: [1, 1, 0], limit: 1)
        let problem = P(protected: [false, false, false], upperBounds: [weekly],
            lowerBounds: [early, late], removalOrder: [2, 1, 0])
        precondition(WorkoutAppearancePlanner.solve(problem) == .admitted([0, 2]))
        precondition(WorkoutAppearancePlanner.solve(problem, maximumStates: 1) == .searchLimit(["shared weekly"]))
        // A queued valid solution must still be checked when the search budget fills.
        precondition(WorkoutAppearancePlanner.solve(problem, maximumStates: 2) == .admitted([0, 2]))
        let protected = P(protected: [true, true, true], upperBounds: [weekly],
            lowerBounds: [early, late], removalOrder: [0, 1, 2])
        precondition(WorkoutAppearancePlanner.solve(protected) == .infeasible(["shared weekly"]))
        let shared = P(protected: [false, false, false], upperBounds: [weekly,
            C(name: "other muscle", coefficients: [3, 0, 3], limit: 3)],
            lowerBounds: [late], removalOrder: [1, 0, 2])
        precondition(WorkoutAppearancePlanner.solve(shared) == .admitted([1, 2]))
        let invalid = P(protected: [false], upperBounds: [C(name: "bad", coefficients: [.nan], limit: 3)],
            lowerBounds: [], removalOrder: [0])
        precondition(WorkoutAppearancePlanner.solve(invalid) == .infeasible(["Invalid appearance-planning problem"]))
        let coverage = P(protected: [false, false, true], upperBounds: [weekly], lowerBounds: [],
            removalOrder: [0, 1, 2], coverage: [.init(name: "frequency", groups: [[0], [1], [2]], minimumGroups: 2)])
        precondition(WorkoutAppearancePlanner.solve(coverage) == .admitted([1, 2]))
        let stress = P(protected: Array(repeating: false, count: 36),
            upperBounds: [.init(name: "unfundable weekly floor", coefficients: Array(repeating: 2, count: 36), limit: 58)],
            lowerBounds: (0..<6).map { day in
                .init(name: "day \(day)", coefficients: (0..<36).map { $0 / 6 == day ? 1 : 0 }, limit: 5)
            }, removalOrder: Array(0..<36))
        let start = Date()
        precondition(WorkoutAppearancePlanner.solve(stress) == .searchLimit(["unfundable weekly floor"]))
        print("Bounded 36-appearance exhaustion case: \(Date().timeIntervalSince(start)) seconds")
        print("PASS: 8 appearance-planner adversarial checks")
    }
}
