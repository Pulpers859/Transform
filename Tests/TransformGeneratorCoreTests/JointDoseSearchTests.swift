import XCTest
@testable import Transform

final class JointDoseSearchTests: XCTestCase {
    private typealias Problem = WorkoutAppearancePlanner.ChoiceProblem
    private typealias Constraint = WorkoutAppearancePlanner.Constraint

    // Deliberately exhaustive, without the production search's pruning or domain ordering.
    private func combinations(_ domains: [[Int]]) -> [[Int]] {
        domains.reduce([[]]) { prefixes, domain in
            prefixes.flatMap { prefix in domain.map { prefix + [$0] } }
        }
    }

    private func valid(_ picks: [Int], for problem: Problem) -> Bool {
        guard picks.count == problem.domains.count,
              zip(picks, problem.domains).allSatisfy({ $1.contains($0) }),
              Set(picks).count == picks.count else { return false }
        func total(_ constraint: Constraint) -> Double {
            picks.sorted().reduce(0) { $0 + constraint.coefficients[$1] }
        }
        return problem.upperBounds.allSatisfy { total($0) <= $0.limit + 0.001 }
            && problem.lowerBounds.allSatisfy { total($0) + 0.001 >= $0.limit }
            && problem.coverage.allSatisfy { coverage in
                coverage.groups.filter { group in group.contains { picks.contains($0) } }.count >= coverage.minimumGroups
            }
            && problem.thresholdCoverage.allSatisfy { coverage in
                coverage.groups.filter { total($0) >= $0.limit }.count >= coverage.minimumGroups
            }
    }

    func testJointDoseChoiceCanFitWhereKeepingEveryFloorAppearanceCannot() {
        // A: omit/2/4 sets, B: omit/2 sets. Only one appearance fits, but four sets
        // are required. Keeping both two-set floors cannot satisfy both constraints.
        let problem = Problem(domains: [[0, 1, 2], [3, 4]], upperBounds: [
            .init(name: "appearances", coefficients: [0, 1, 1, 0, 1], limit: 1),
            .init(name: "sets", coefficients: [0, 2, 4, 0, 2], limit: 4)
        ], lowerBounds: [.init(name: "dose", coefficients: [0, 2, 4, 0, 2], limit: 4)])
        XCTAssertFalse(valid([1, 4], for: problem))
        XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(problem), .admitted([2, 3]))
    }

    func testExactlyOneOptionPerDomainAndOriginalDomainOrder() {
        let problem = Problem(domains: [[0, 1, 2], [3], [5, 4]], upperBounds: [], lowerBounds: [])
        let result = WorkoutAppearancePlanner.solveChoices(problem)
        XCTAssertEqual(result, .admitted([0, 3, 5]), "Search reordering must not reorder the returned domains")
        if case .admitted(let picks) = result { XCTAssertTrue(valid(picks, for: problem)) }
    }

    func testSingletonProtectedChoiceCannotBeOmittedToFitBudget() {
        let problem = Problem(domains: [[0], [1, 2]],
            upperBounds: [.init(name: "budget", coefficients: [3, 0, 1], limit: 2)], lowerBounds: [])
        guard case .infeasible = WorkoutAppearancePlanner.solveChoices(problem) else {
            return XCTFail("A required singleton cannot be silently discarded")
        }
    }

    func testMultiMuscleCostsAreChargedSimultaneously() {
        let problem = Problem(domains: [[0, 1], [2, 3]], upperBounds: [
            .init(name: "quads", coefficients: [2, 1, 2, 0], limit: 2),
            .init(name: "glutes", coefficients: [2, 0, 2, 1], limit: 2)
        ], lowerBounds: [.init(name: "dose", coefficients: [1, 1, 1, 1], limit: 2)])
        XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(problem), .admitted([1, 3]))
    }

    func testCoverageCountsDistinctGroupsNotMultipleSlotsOnOneDay() {
        let problem = Problem(domains: [[0], [1], [2, 3]], upperBounds: [], lowerBounds: [],
            coverage: [.init(name: "two days", groups: [[0, 1], [3]], minimumGroups: 2)])
        XCTAssertFalse(valid([0, 1, 2], for: problem))
        XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(problem), .admitted([0, 1, 3]))
    }

    func testInfeasibilityAndSearchExhaustionAreDistinct() {
        let feasible = Problem(domains: [[0, 1], [2, 3]], upperBounds: [], lowerBounds: [])
        guard case .searchLimit = WorkoutAppearancePlanner.solveChoices(feasible, maximumStates: 0) else {
            return XCTFail("No search budget cannot prove infeasibility")
        }
        let impossible = Problem(domains: [[0, 1], [2, 3]], upperBounds: [],
            lowerBounds: [.init(name: "unreachable", coefficients: [1, 1, 1, 1], limit: 3)])
        guard case .infeasible = WorkoutAppearancePlanner.solveChoices(impossible, maximumStates: 10_000) else {
            return XCTFail("Exhaustive impossibility must not be reported as exhaustion")
        }
    }

    func testMalformedProblemsAreNotInfeasibilityProofs() {
        let malformed: [Problem] = [
            .init(domains: [[]], upperBounds: [], lowerBounds: []),
            .init(domains: [[0], [0]], upperBounds: [], lowerBounds: []),
            .init(domains: [[0, 2]], upperBounds: [], lowerBounds: []),
            .init(domains: [[-1, 0]], upperBounds: [], lowerBounds: []),
            .init(domains: [[0]], upperBounds: [.init(name: "length", coefficients: [], limit: 1)], lowerBounds: []),
            .init(domains: [[0]], upperBounds: [.init(name: "negative", coefficients: [-1], limit: 1)], lowerBounds: []),
            .init(domains: [[0]], upperBounds: [.init(name: "nan", coefficients: [.nan], limit: 1)], lowerBounds: []),
            .init(domains: [[0]], upperBounds: [], lowerBounds: [.init(name: "infinite", coefficients: [.infinity], limit: 1)]),
            .init(domains: [[0]], upperBounds: [.init(name: "limit", coefficients: [1], limit: .nan)], lowerBounds: []),
            .init(domains: [[0]], upperBounds: [], lowerBounds: [.init(name: "limit", coefficients: [1], limit: .infinity)]),
            .init(domains: [[0], [1]], upperBounds: [.init(name: "sum overflow",
                coefficients: [.greatestFiniteMagnitude, .greatestFiniteMagnitude], limit: 1)], lowerBounds: []),
            .init(domains: [[0]], upperBounds: [], lowerBounds: [], coverage: [.init(name: "bad index", groups: [[1]], minimumGroups: 1)]),
            .init(domains: [[0]], upperBounds: [], lowerBounds: [], coverage: [.init(name: "negative count", groups: [[0]], minimumGroups: -1)])
        ]
        for (index, problem) in malformed.enumerated() {
            guard case .invalidProblem = WorkoutAppearancePlanner.solveChoices(problem) else {
                XCTFail("Malformed fixture \(index) must have a distinct shape error")
                continue
            }
        }
    }

    func testPositiveBudgetExhaustionAtExactSearchBoundary() {
        let problem = Problem(domains: [[0, 1], [2, 3]], upperBounds: [], lowerBounds: [])
        guard case .searchLimit = WorkoutAppearancePlanner.solveChoices(problem, maximumStates: 2) else {
            return XCTFail("Root plus one partial assignment does not fund a complete two-domain search")
        }
        XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(problem, maximumStates: 3), .admitted([0, 2]))
    }

    func testEmptyValidProblemIsDistinctFromImpossibleEmptyRequirement() {
        let empty = Problem(domains: [], upperBounds: [], lowerBounds: [])
        XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(empty), .admitted([]))
        let impossible = Problem(domains: [], upperBounds: [],
            lowerBounds: [.init(name: "positive dose without options", coefficients: [], limit: 1)])
        guard case .infeasible = WorkoutAppearancePlanner.solveChoices(impossible) else {
            return XCTFail("A well-shaped empty problem cannot satisfy a positive lower bound")
        }
    }

    func testStatisticsReportOnceWithoutChangingAdmissionOrExhaustion() {
        let problem = Problem(domains: [[0, 1], [2, 3]], upperBounds: [], lowerBounds: [])
        for budget in [2, 3] {
            var observations: [WorkoutAppearancePlanner.ChoiceSearchStatistics] = []
            let observed = WorkoutAppearancePlanner.solveChoices(problem, maximumStates: budget,
                statistics: { observations.append($0) })
            XCTAssertEqual(observed, WorkoutAppearancePlanner.solveChoices(problem, maximumStates: budget))
            XCTAssertEqual(observations, [.init(visitedStates: budget, completeAssignments: budget == 3 ? 1 : 0)])
        }
    }

    func testStatisticsReportZeroOnceForMalformedAndZeroBudgetExits() {
        let cases: [(Problem, Int)] = [
            (.init(domains: [[]], upperBounds: [], lowerBounds: []), 512),
            (.init(domains: [[0]], upperBounds: [], lowerBounds: []), 0)
        ]
        for (problem, budget) in cases {
            var observations: [WorkoutAppearancePlanner.ChoiceSearchStatistics] = []
            let observed = WorkoutAppearancePlanner.solveChoices(problem, maximumStates: budget,
                statistics: { observations.append($0) })
            XCTAssertEqual(observed, WorkoutAppearancePlanner.solveChoices(problem, maximumStates: budget))
            XCTAssertEqual(observations, [.init(visitedStates: 0, completeAssignments: 0)])
        }
    }

    func testArithmeticToleranceMatchesExistingAdmissionContract() {
        let near = Problem(domains: [[0]],
            upperBounds: [.init(name: "upper", coefficients: [1], limit: 0.9995)],
            lowerBounds: [.init(name: "lower", coefficients: [1], limit: 1.0005)])
        XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(near), .admitted([0]))
        let outside = Problem(domains: [[0]],
            upperBounds: [.init(name: "upper", coefficients: [1], limit: 0.998)], lowerBounds: [])
        guard case .infeasible = WorkoutAppearancePlanner.solveChoices(outside) else {
            return XCTFail("Tolerance must not silently expand")
        }
    }

    func testThresholdCoverageAggregatesMultipleAppearancesOnTheSameDay() {
        let problem = Problem(domains: [[0], [1]], upperBounds: [], lowerBounds: [],
            thresholdCoverage: [.init(name: "meaningful day", groups: [
                .init(name: "day one", coefficients: [2, 1], limit: 3)
            ], minimumGroups: 1)])
        XCTAssertTrue(valid([0, 1], for: problem))
        XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(problem), .admitted([0, 1]))
    }

    func testWeeklyTwoPlusFourSetsDoesNotProveTwoThreeSetDays() {
        let problem = Problem(domains: [[0], [1]], upperBounds: [],
            lowerBounds: [.init(name: "weekly six", coefficients: [2, 4], limit: 6)],
            thresholdCoverage: [.init(name: "two meaningful days", groups: [
                .init(name: "day one", coefficients: [2, 0], limit: 3),
                .init(name: "day two", coefficients: [0, 4], limit: 3)
            ], minimumGroups: 2)])
        XCTAssertFalse(valid([0, 1], for: problem))
        guard case .infeasible = WorkoutAppearancePlanner.solveChoices(problem) else {
            return XCTFail("Weekly dose and two appearances cannot substitute for daily threshold coverage")
        }
    }

    func testThresholdCoverageDoesNotBorrowLinearBoundTolerance() {
        for (sets, admitted) in [(3.0, true), (2.9995, false), (2.99, false)] {
            let problem = Problem(domains: [[0]], upperBounds: [], lowerBounds: [],
                thresholdCoverage: [.init(name: "exact threshold", groups: [
                    .init(name: "day", coefficients: [sets], limit: 3)
                ], minimumGroups: 1)])
            XCTAssertEqual(valid([0], for: problem), admitted)
            let result = WorkoutAppearancePlanner.solveChoices(problem)
            if admitted { XCTAssertEqual(result, .admitted([0])) }
            else if case .infeasible = result {} else { XCTFail("No implicit 0.001 allowance: \(result)") }
        }
        let callerAdjusted = Problem(domains: [[0]], upperBounds: [], lowerBounds: [],
            thresholdCoverage: [.init(name: "caller policy tolerance", groups: [
                .init(name: "day", coefficients: [2.99], limit: 3 - 0.01)
            ], minimumGroups: 1)])
        XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(callerAdjusted), .admitted([0]))
    }

    func testMalformedThresholdCoverageIsNotAnInfeasibilityProof() {
        let malformedGroups: [Constraint] = [
            .init(name: "short", coefficients: [1], limit: 1),
            .init(name: "negative", coefficients: [-1, 0], limit: 1),
            .init(name: "nan coefficient", coefficients: [.nan, 0], limit: 1),
            .init(name: "infinite coefficient", coefficients: [.infinity, 0], limit: 1),
            .init(name: "nan limit", coefficients: [1, 0], limit: .nan),
            .init(name: "infinite limit", coefficients: [1, 0], limit: .infinity),
            .init(name: "overflowing sum", coefficients: [.greatestFiniteMagnitude, .greatestFiniteMagnitude], limit: 1)
        ]
        var cases = malformedGroups.map { group in
            Problem(domains: [[0], [1]], upperBounds: [], lowerBounds: [],
                thresholdCoverage: [.init(name: "bad group", groups: [group], minimumGroups: 1)])
        }
        cases.append(Problem(domains: [[0], [1]], upperBounds: [], lowerBounds: [],
            thresholdCoverage: [.init(name: "negative count", groups: [], minimumGroups: -1)]))
        for problem in cases {
            guard case .invalidProblem = WorkoutAppearancePlanner.solveChoices(problem) else {
                XCTFail("Malformed threshold coverage must be rejected before search")
                continue
            }
        }
    }

    func testThresholdCoverageMatchesSmallExhaustiveOracle() {
        // Each group shares options across decisions; optimistic maxima can conflict.
        // The oracle enumerates leaves without reproducing the DFS pruning logic.
        for threshold in 1...4 {
            for required in 0...3 {
                let problem = Problem(domains: [[1, 0], [2, 3], [4, 5]],
                    upperBounds: [.init(name: "budget", coefficients: [0, 2, 1, 2, 0, 2], limit: 4)],
                    lowerBounds: [], thresholdCoverage: [.init(name: "dose days", groups: [
                        .init(name: "day one", coefficients: [0, 2, 1, 0, 0, 0], limit: Double(threshold)),
                        .init(name: "day two", coefficients: [0, 0, 0, 2, 0, 2], limit: Double(threshold))
                    ], minimumGroups: required)])
                let exists = combinations(problem.domains).contains { valid($0, for: problem) }
                let result = WorkoutAppearancePlanner.solveChoices(problem, maximumStates: 1_000)
                switch result {
                case .admitted(let picks):
                    XCTAssertTrue(exists)
                    XCTAssertTrue(valid(picks, for: problem))
                case .infeasible: XCTAssertFalse(exists)
                default: XCTFail("Tiny well-formed problem should finish: \(result)")
                }
                XCTAssertEqual(result, WorkoutAppearancePlanner.solveChoices(problem, maximumStates: 1_000))
            }
        }
    }

    func testDeterministicFiniteProblemsMatchExhaustiveOracleWithoutMutation() {
        // 36 problems, eight combinations apiece; no workout generation or random seeds.
        for upper in 0...5 {
            for lower in 0...5 {
                let problem = Problem(domains: [[1, 0], [2, 3], [5, 4]], upperBounds: [
                    .init(name: "shared budget", coefficients: [0, 2, 1, 3, 0, 2], limit: Double(upper))
                ], lowerBounds: [.init(name: "regional dose", coefficients: [0, 2, 2, 1, 0, 3], limit: Double(lower))],
                    coverage: [.init(name: "two exposure groups", groups: [[1, 2], [3, 5]], minimumGroups: 2)])
                let domains = problem.domains
                let coefficients = problem.upperBounds.map(\.coefficients) + problem.lowerBounds.map(\.coefficients)
                let groups = problem.coverage.map(\.groups)
                let exists = combinations(problem.domains).contains { valid($0, for: problem) }
                let result = WorkoutAppearancePlanner.solveChoices(problem, maximumStates: 10_000)
                switch result {
                case .admitted(let picks):
                    XCTAssertTrue(exists)
                    XCTAssertTrue(valid(picks, for: problem), "Invalid result for limits \(upper)/\(lower)")
                case .infeasible:
                    XCTAssertFalse(exists, "Oracle found a solution for limits \(upper)/\(lower)")
                default:
                    XCTFail("Valid tiny problem should finish within budget: \(result)")
                }
                XCTAssertEqual(WorkoutAppearancePlanner.solveChoices(problem, maximumStates: 10_000), result)
                XCTAssertEqual(problem.domains, domains)
                XCTAssertEqual(problem.upperBounds.map(\.coefficients) + problem.lowerBounds.map(\.coefficients), coefficients)
                XCTAssertEqual(problem.coverage.map(\.groups), groups)
            }
        }
    }
}
