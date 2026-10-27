import XCTest
@testable import Transform

/// Owner feedback, 2026-10-27, from Day 16 screenshots.
@MainActor
final class OwnerWorkoutFeedbackTests: XCTestCase {

    private func session(_ timestamp: TimeInterval, rir: Double) -> WorkoutPerformanceLogSnapshot {
        WorkoutPerformanceLogSnapshot(
            canonicalExerciseKey: "lying-leg-curl",
            loggedAt: Date(timeIntervalSince1970: timestamp),
            setLogs: [
                SetLogEntry(setNumber: 1, weightLbs: 50, repsCompleted: 12, rir: rir),
                SetLogEntry(setNumber: 2, weightLbs: 50, repsCompleted: 11, rir: rir)
            ]
        )
    }

    /// The card prescribed RIR 1, the owner logged RIR 1, and the card answered "repeated low
    /// RIR suggests protecting recovery". Doing exactly what was asked must not read as a
    /// warning. The app never prescribes below RIR 1 on its own, so history without a
    /// recorded target is judged against 1.
    func testLoggingThePrescribedRIROneIsNotReadAsOverreaching() {
        XCTAssertNotEqual(
            WorkoutProgressionEngine.effortSignal(for: "lying-leg-curl",
                                                  from: [session(100, rir: 1), session(200, rir: 1)]),
            .protectRecovery
        )
    }

    /// Leg Press offered only 45-Degree Leg Press and Single-Leg Press. Machine squats train
    /// the same muscles with the same fatigue class and belong in the list; barbell squats are
    /// a heavier, more fatiguing lift and stay out of a like-for-like swap.
    func testLegPressCanBeSwappedForMachineSquatsButNotBarbellSquats() {
        for machine in ["Hack Squat", "Pendulum Squat", "Belt Squat"] {
            XCTAssertTrue(ExerciseReplacement.compatible(originalName: "Leg Press", candidateName: machine), machine)
            XCTAssertTrue(ExerciseReplacement.compatible(originalName: machine, candidateName: "Leg Press"), machine)
        }
        for barbell in ["Back Squat", "Front Squat"] {
            XCTAssertFalse(ExerciseReplacement.compatible(originalName: "Leg Press", candidateName: barbell), barbell)
        }
    }
}
