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
