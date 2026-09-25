import Foundation

/// A bounded, whole-week admission search. Coefficients describe the cost/coverage of an
/// appearance at its reserved dose, not the number of distinct exercise names.
/// See WorkoutAppearancePlannerTests for shared budgets, protected slots and search exhaustion.
enum WorkoutAppearancePlanner {
    struct Constraint {
        let name: String
        let coefficients: [Double]
        let limit: Double
    }

    struct Problem {
        let protected: [Bool]
        let upperBounds: [Constraint]
        let lowerBounds: [Constraint]
        // Earlier entries are preferred for removal when equally small solutions exist.
        let removalOrder: [Int]
        var coverage: [Coverage] = []
    }

    struct Coverage {
        let name: String
        let groups: [[Int]]
        let minimumGroups: Int
    }

    enum Outcome: Equatable {
        case admitted([Int])
        case infeasible([String])
        case searchLimit([String])
    }

    /// Prospective finite choices: each domain is one decision, such as which
    /// eligible placement and set count to use for an appearance. Exactly one
    /// option per domain is chosen; omission requires an explicit zero-cost option.
    /// A fixed domain represents a commitment, not an automatically protected
    /// provisional choice. Callers own catalog, history and symptom eligibility.
    struct ChoiceProblem {
        let domains: [[Int]]
        let upperBounds: [Constraint]
        let lowerBounds: [Constraint]
        var coverage: [Coverage] = []
        var thresholdCoverage: [ThresholdCoverage] = []
    }

    /// Count groups whose aggregate selected dose reaches their own limit. Unlike
    /// binary coverage, several appearances can jointly fund one meaningful day.
    /// Limits already include the caller's policy tolerance; no extra slack here.
    struct ThresholdCoverage {
        let name: String
        let groups: [Constraint]
        let minimumGroups: Int
    }

    enum ChoiceOutcome: Equatable {
        case admitted([Int])
        case infeasible([String])
        case searchLimit([String])
        case invalidProblem(String)
    }

    struct ChoiceSearchStatistics: Equatable {
        // States include partial and pruned assignments; they are NOT complete
        // workouts tried or exercises ruled out. Full assignments may fail bounds.
        let visitedStates: Int
        let completeAssignments: Int
    }

    /// Joint feasibility, not a training-quality optimum or permission to publish
    /// a workout. Options must describe the SAME placement/dose in every budget.
    /// No production caller yet; JointDoseSearchTests independently enumerates
    /// small cases and checks returned choices. Does not change the subset solver.
    static func solveChoices(_ problem: ChoiceProblem, maximumStates: Int = 512,
        statistics: ((ChoiceSearchStatistics) -> Void)? = nil) -> ChoiceOutcome {
        var visited = 0, complete = 0
        defer { statistics?(.init(visitedStates: visited, completeAssignments: complete)) }
        let options = problem.domains.flatMap { $0 }
        let count = options.count
        let constraints = problem.upperBounds + problem.lowerBounds
        let validatedConstraints = constraints + problem.thresholdCoverage.flatMap(\.groups)
        guard problem.domains.allSatisfy({ !$0.isEmpty }),
              Set(options) == Set(0..<count),
              validatedConstraints.allSatisfy({ $0.coefficients.count == count && $0.limit.isFinite
                  && $0.coefficients.allSatisfy { $0.isFinite && $0 >= 0 }
                  && $0.coefficients.reduce(0, +).isFinite }),
              problem.coverage.allSatisfy({ $0.minimumGroups >= 0
                  && $0.groups.joined().allSatisfy { (0..<count).contains($0) } }),
              problem.thresholdCoverage.allSatisfy({ $0.minimumGroups >= 0 }) else {
            return .invalidProblem("Invalid finite-choice planning problem")
        }
        guard maximumStates > 0 else {
            return .searchLimit(["Joint planning state budget is exhausted"])
        }
        // Fewer choices first; ties preserve original decision order. The result
        // is mapped back to original domains, never search-order coordinates.
        let order = problem.domains.indices.sorted {
            let lhs = problem.domains[$0].count, rhs = problem.domains[$1].count
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
        var chosen = Array(repeating: -1, count: problem.domains.count)
        var exhausted = false
        var conflicts = Set<String>()

        func boundsAllowCompletion() -> Bool {
            var allowed = true
            for (index, constraint) in constraints.enumerated() {
                var minimum = 0.0, maximum = 0.0
                for domain in problem.domains.indices {
                    if chosen[domain] >= 0 {
                        let cost = constraint.coefficients[chosen[domain]]
                        minimum += cost
                        maximum += cost
                    } else {
                        let costs = problem.domains[domain].map { constraint.coefficients[$0] }
                        // Validation guarantees a nonempty domain.
                        minimum += costs.min()!
                        maximum += costs.max()!
                    }
                }
                if index < problem.upperBounds.count
                    ? minimum > constraint.limit + 0.001
                    : maximum + 0.001 < constraint.limit {
                    conflicts.insert(constraint.name)
                    allowed = false
                    // The root gathers a broad diagnostic. Below it, one failed
                    // necessary bound already proves this partial choice cannot
                    // complete; evaluating every other bound only burns runtime.
                    if visited > 1 { return false }
                }
            }
            for requirement in problem.coverage {
                // Count potentially covered groups, not exercise appearances.
                // At a complete assignment this is the exact covered-group count.
                let possible = requirement.groups.filter { group in
                    problem.domains.indices.contains { domain in
                        chosen[domain] >= 0 ? group.contains(chosen[domain])
                            : problem.domains[domain].contains(where: group.contains)
                    }
                }.count
                if possible < requirement.minimumGroups {
                    conflicts.insert(requirement.name)
                    allowed = false
                    if visited > 1 { return false }
                }
            }
            for requirement in problem.thresholdCoverage {
                // Independent maxima are optimistic while undecided; that can
                // cost search time but cannot wrongly prune a feasible assignment.
                // At a leaf every group total is exact in original domain order.
                let possible = requirement.groups.filter { group in
                    var maximum = 0.0
                    for domain in problem.domains.indices {
                        maximum += chosen[domain] >= 0 ? group.coefficients[chosen[domain]]
                            : problem.domains[domain].map { group.coefficients[$0] }.max()!
                    }
                    return maximum >= group.limit
                }.count
                if possible < requirement.minimumGroups {
                    conflicts.insert(requirement.name)
                    allowed = false
                    if visited > 1 { return false }
                }
            }
            return allowed
        }

        func search(_ depth: Int) -> [Int]? {
            guard visited < maximumStates else {
                exhausted = true
                return nil
            }
            visited += 1
            if depth == order.count { complete += 1 }
            guard boundsAllowCompletion() else { return nil }
            if depth == order.count { return chosen }
            let domain = order[depth]
            for option in problem.domains[domain] {
                chosen[domain] = option
                if let result = search(depth + 1) { return result }
                if exhausted { break }
            }
            chosen[domain] = -1
            return nil
        }
        if let result = search(0) { return .admitted(result) }
        // These are observed conflicts, not a minimal unsatisfiable constraint set.
        let reasons = conflicts.isEmpty ? ["No complete choice within the supplied constraints"] : conflicts.sorted()
        return exhausted ? .searchLimit(reasons) : .infeasible(reasons)
    }

    static func solve(_ problem: Problem, maximumStates: Int = 512) -> Outcome {
        let count = problem.protected.count
        let constraints = problem.upperBounds + problem.lowerBounds
        guard Set(problem.removalOrder) == Set(0..<count),
              problem.removalOrder.count == count,
              problem.coverage.allSatisfy({ $0.minimumGroups >= 0 && $0.groups.joined().allSatisfy { (0..<count).contains($0) } }),
              constraints.allSatisfy({ $0.coefficients.count == count && $0.limit.isFinite
                  && $0.coefficients.allSatisfy { $0.isFinite && $0 >= 0 } }) else {
            return .infeasible(["Invalid appearance-planning problem"])
        }
        // No search was permitted: this says nothing about whether the pool can fit.
        guard maximumStates > 0 else {
            return .searchLimit(["Appearance search state budget is exhausted"])
        }
        func total(_ constraint: Constraint, _ selected: Set<Int>) -> Double {
            // Fixed coefficient order keeps fractional sums reproducible without sorting
            // each selected set for every constraint at every search node.
            constraint.coefficients.indices.reduce(0) { selected.contains($1) ? $0 + constraint.coefficients[$1] : $0 }
        }
        func covers(_ selected: Set<Int>) -> Bool {
            problem.coverage.allSatisfy { requirement in
                requirement.groups.filter { $0.contains(where: { selected.contains($0) }) }.count >= requirement.minimumGroups
            }
        }
        func violations(_ selected: Set<Int>) -> [Constraint] {
            problem.upperBounds.filter { total($0, selected) > $0.limit + 0.001 }
        }
        let all = Set(0..<count)
        let initialIssues = violations(all).map(\.name)
        guard covers(all), problem.lowerBounds.allSatisfy({ total($0, all) + 0.001 >= $0.limit }) else {
            return .infeasible(["Candidate pool does not cover its requirements"])
        }
        // Breadth-first search minimizes removed appearances; it does not claim a global
        // training-quality optimum. Every state is checked against all shared constraints.
        var queue = [all]
        var visited: Set<Set<Int>> = [all]
        var cursor = 0
        var exhausted = false
        while cursor < queue.count {
            let selected = queue[cursor]
            cursor += 1
            let over = violations(selected)
            if over.isEmpty { return .admitted(selected.sorted()) }
            for index in problem.removalOrder where selected.contains(index) && !problem.protected[index] {
                guard over.contains(where: { $0.coefficients[index] > 0 }) else { continue }
                var next = selected
                next.remove(index)
                guard !visited.contains(next), covers(next),
                      problem.lowerBounds.allSatisfy({ total($0, next) + 0.001 >= $0.limit }) else { continue }
                guard visited.count < maximumStates else { exhausted = true; continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return exhausted ? .searchLimit(initialIssues) : .infeasible(initialIssues)
    }
}
