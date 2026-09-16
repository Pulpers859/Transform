import Foundation

// Shared policy values, not a promise that a candidate week can fund all targets.
// Reservation keeps the solver's 0.001 tolerance; incremental funding keeps 0.01.
// SetBudgetPolicyTests pins these distinct boundaries.
enum WorkoutSetBudgetPolicy {
    static let fundingTolerance = 0.01

    static func maintenanceFloor(recoveryTight: Bool) -> Double {
        recoveryTight ? 2 : 3
    }

    static func maintenanceCeiling(recoveryTight: Bool) -> Double {
        recoveryTight ? 8 : 10
    }

    static func normalWeeklyPriorityCeiling(target: Double) -> Double {
        // Whole-set allocation may meet a fractional target from above. This only
        // lifts the weekly target gate; role, maintenance, fatigue and session
        // limits must still fund the additional set (SetBudgetPolicyTests).
        // Snap values already within the existing funding tolerance of an integer
        // before rounding, so floating-point noise cannot buy a phantom set.
        ceil(target - fundingTolerance) + fundingTolerance
    }

    static func floorWeeklyPriorityCeiling(target: Double, recoveryTight: Bool) -> Double {
        // Extracted unchanged from the allocator's floor-repair guard, including
        // its buffer and margin. Changing these is a separate volume-policy decision.
        target * (recoveryTight ? 1.15 : 1.3) + (recoveryTight ? 0 : 0.5) - 0.02
    }

    static func sessionPriorityCeiling(ordinary: Double, focused: Double, isFocus: Bool) -> Double {
        isFocus ? focused : ordinary
    }
}

// A rejected NEXT set, not a diagnosis of every problem with the completed week.
// The allocator reports the first blocker in its existing evaluation order.
struct SetFundingRejection: Codable, Equatable {
    enum Kind: String, Codable {
        case role, maintenance, weeklyPriority, missingDayPlan, fatigue, sessionPriority
    }
    let kind: Kind
    let subject: String
    let projected: Double?
    let limit: Double?
}

struct SetFundingObservation: Codable, Equatable {
    // Zero-based indices into the final RETURNED menu, after any admission removals.
    let dayIndex: Int
    let exerciseIndex: Int
    let exerciseName: String
    let muscleTarget: String
    let prescribedSets: Int
    // nil means another set passes the budget gate, not that it should be prescribed.
    // Funding objectives/loop bounds can stop earlier. This is normal funding only.
    let rejection: SetFundingRejection?
}
