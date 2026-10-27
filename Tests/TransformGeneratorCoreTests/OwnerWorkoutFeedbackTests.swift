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

    /// With the target recorded, effort is judged against it: the same RIR 1 is on target
    /// when 1 was asked, and harder than asked when 2 was.
    func testEffortIsJudgedAgainstEachSessionsRecordedTarget() {
        func targeted(_ timestamp: TimeInterval, rir: Double, target: Int) -> WorkoutPerformanceLogSnapshot {
            var snapshot = session(timestamp, rir: rir)
            snapshot.prescribedTargetRIR = target
            return snapshot
        }
        XCTAssertEqual(WorkoutProgressionEngine.effortSignal(
            for: "lying-leg-curl", from: [targeted(100, rir: 1, target: 1), targeted(200, rir: 1, target: 1)]), .neutral)
        XCTAssertEqual(WorkoutProgressionEngine.effortSignal(
            for: "lying-leg-curl", from: [targeted(100, rir: 1, target: 2), targeted(200, rir: 1, target: 2)]), .protectRecovery)
        XCTAssertEqual(WorkoutProgressionEngine.effortSignal(
            for: "lying-leg-curl", from: [targeted(100, rir: 3, target: 1), targeted(200, rir: 3, target: 1)]), .progressionHeadroom)
    }

    /// The log keeps the target it was given, and reports "not recorded" as nil, never as 0.
    func testPerformanceLogRecordsItsTargetRIR() {
        XCTAssertEqual(ExercisePerformanceLog(exerciseName: "Lying Leg Curl", weightLbs: 50,
                                              prescribedTargetRIR: 1).recordedTargetRIR, 1)
        XCTAssertNil(ExercisePerformanceLog(exerciseName: "Lying Leg Curl", weightLbs: 50).recordedTargetRIR)
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
