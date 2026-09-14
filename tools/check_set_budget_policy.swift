import Foundation

@main
struct SetBudgetPolicyChecks {
    static func main() {
        func close(_ lhs: Double, _ rhs: Double) { precondition(abs(lhs - rhs) < 0.000001) }
        close(WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight: false), 3)
        close(WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight: true), 2)
        close(WorkoutSetBudgetPolicy.maintenanceCeiling(recoveryTight: false), 10)
        close(WorkoutSetBudgetPolicy.maintenanceCeiling(recoveryTight: true), 8)
        close(WorkoutSetBudgetPolicy.normalWeeklyPriorityCeiling(target: 7.5), 7.51)
        close(WorkoutSetBudgetPolicy.floorWeeklyPriorityCeiling(target: 8, recoveryTight: false), 10.88)
        close(WorkoutSetBudgetPolicy.floorWeeklyPriorityCeiling(target: 8, recoveryTight: true), 9.18)
        close(WorkoutSetBudgetPolicy.sessionPriorityCeiling(ordinary: 2, focused: 4, isFocus: false), 2)
        close(WorkoutSetBudgetPolicy.sessionPriorityCeiling(ordinary: 2, focused: 4, isFocus: true), 4)
        let observation = SetFundingObservation(dayIndex: 1, exerciseIndex: 2, exerciseName: "probe",
            muscleTarget: "probe", prescribedSets: 2,
            rejection: .init(kind: .weeklyPriority, subject: "Quads", projected: 8, limit: 7.51))
        let data = try! JSONEncoder().encode(observation)
        precondition(try! JSONDecoder().decode(SetFundingObservation.self, from: data) == observation)
        print("Set budget policy: 9 numerical checks and diagnostic Codable round-trip passed.")
    }
}
