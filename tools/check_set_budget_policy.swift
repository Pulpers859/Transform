import Foundation

@main
struct SetBudgetPolicyChecks {
    static func main() {
        func close(_ lhs: Double, _ rhs: Double) { precondition(abs(lhs - rhs) < 0.000001) }
        close(WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight: false), 3)
        close(WorkoutSetBudgetPolicy.maintenanceFloor(recoveryTight: true), 2)
        close(WorkoutSetBudgetPolicy.maintenanceCeiling(recoveryTight: false), 10)
        close(WorkoutSetBudgetPolicy.maintenanceCeiling(recoveryTight: true), 8)
        close(WorkoutSetBudgetPolicy.normalWeeklyPriorityCeiling(target: 7.5), 8.01)
        close(WorkoutSetBudgetPolicy.normalWeeklyPriorityCeiling(target: 7), 7.01)
        close(WorkoutSetBudgetPolicy.normalWeeklyPriorityCeiling(target: 7.000000001), 7.01)
        close(WorkoutSetBudgetPolicy.normalWeeklyPriorityCeiling(target: 6.999999999), 7.01)
        close(WorkoutSetBudgetPolicy.normalWeeklyPriorityCeiling(target: 7.05), 8.01)
        close(WorkoutSetBudgetPolicy.floorWeeklyPriorityCeiling(target: 8, recoveryTight: false), 10.88)
        close(WorkoutSetBudgetPolicy.floorWeeklyPriorityCeiling(target: 8, recoveryTight: true), 9.18)
        close(WorkoutSetBudgetPolicy.sessionPriorityCeiling(ordinary: 2, focused: 4, isFocus: false), 2)
        close(WorkoutSetBudgetPolicy.sessionPriorityCeiling(ordinary: 2, focused: 4, isFocus: true), 4)
        let observation = SetFundingObservation(dayIndex: 1, exerciseIndex: 2, exerciseName: "probe",
            muscleTarget: "probe", prescribedSets: 2,
            rejection: .init(kind: .weeklyPriority, subject: "Quads", projected: 9, limit: 8.01))
        let data = try! JSONEncoder().encode(observation)
        precondition(try! JSONDecoder().decode(SetFundingObservation.self, from: data) == observation)
        print("Set budget policy: 13 numerical checks and diagnostic Codable round-trip passed.")
    }
}
