import XCTest
@testable import Transform

/// Pins the bodyweight logging/progression contract and the structured-RIR,
/// execution-only-notes policy:
///  * weight 0 is a real bodyweight set, analyzed and progressed on reps — the
///    "1 lb felt complete. Try 2.5 lb next session" class of nonsense is dead;
///  * legacy fake "1 lb" records are reinterpreted, never rewritten;
///  * effort intent ships as targetRIR; progression prose in exercise notes is
///    a validator issue, not a validator requirement (it used to be REQUIRED).
@MainActor
final class BodyweightAndEffortFieldTests: XCTestCase {

    private let service = ClaudeService.shared

    private func set(_ n: Int, weight: Double, reps: Int, rir: Double? = nil) -> SetLogEntry {
        SetLogEntry(setNumber: n, weightLbs: weight, repsCompleted: reps, rir: rir)
    }

    // MARK: - Bodyweight analysis & progression

    func testBodyweightSetsAreWorkingSetsWithRepBasedTopSet() {
        let analysis = WorkingSetAnalysis.analyze([
            set(1, weight: 0, reps: 15),
            set(2, weight: 0, reps: 13),
            set(3, weight: 0, reps: 14)
        ])
        XCTAssertEqual(analysis.workingSets.count, 3, "Bodyweight sets must not be filtered out as invalid")
        XCTAssertEqual(analysis.workingWeight, 0)
        XCTAssertEqual(analysis.topWorkingSet?.reps, 15,
                       "With every e1RM at 0, the top set is the highest-rep set")
    }

    func testBodyweightSessionMaxingTheRangeAsksForExternalLoad() throws {
        let decision = try XCTUnwrap(WorkoutProgressionEngine.evaluate(
            latestSetLogs: [
                set(1, weight: 0, reps: 15),
                set(2, weight: 0, reps: 15),
                set(3, weight: 0, reps: 15)
            ],
            summaryWeight: 0,
            summaryReps: 15,
            repRange: RepRange(low: 12, high: 15)
        ))
        XCTAssertEqual(decision.kind, .addLoad)
        XCTAssertEqual(
            WorkoutProgressionEngine.nextLoad(from: decision.workingWeight, exerciseName: "Hanging Knee Raise"),
            2.5, accuracy: 0.001,
            "From bodyweight the first step is one small external increment, not percentage math"
        )
    }

    func testLegacyOneLbWorkaroundRecordsAreBodyweightEquivalent() {
        // Before the logger allowed BW, bodyweight exercises were logged as "1 lb".
        // Those records are reinterpreted at read time — no destructive migration.
        XCTAssertTrue(WorkoutProgressionEngine.isBodyweightEquivalent(0))
        XCTAssertTrue(WorkoutProgressionEngine.isBodyweightEquivalent(1.0))
        XCTAssertFalse(WorkoutProgressionEngine.isBodyweightEquivalent(2.5))
        XCTAssertEqual(WorkoutProgressionEngine.nextLoad(from: 1.0, exerciseName: "Hanging Knee Raise"),
                       2.5, accuracy: 0.001)
    }

    func testMixedSessionKeepsWeightedSetsAsWorking() {
        let analysis = WorkingSetAnalysis.analyze([
            set(1, weight: 0, reps: 20),
            set(2, weight: 10, reps: 12),
            set(3, weight: 10, reps: 11)
        ])
        XCTAssertEqual(analysis.workingWeight, 10,
                       "Added external load defines the working weight; the BW set is a warm-up")
        XCTAssertEqual(analysis.workingSets.count, 2)
    }

    func testFormatLoadRendersBodyweightHonestly() {
        XCTAssertEqual(formatLoad(0), "BW")
        XCTAssertEqual(formatLoad(2.5), "2.5 lb")
        XCTAssertEqual(formatLoad(100), "100 lb")
    }

    func testBestRecordAtEqualLoadPrefersMoreReps() {
        let entry = ExerciseWeightEntry(
            loggedAt: Date(timeIntervalSinceNow: -3 * 86_400),
            exerciseName: "Hanging Knee Raise",
            weightLbs: 0,
            repsCompleted: 12
        )
        XCTAssertTrue(entry.hasBestRecord, "A rep-only (bodyweight) record is still a record")

        entry.applyLog(
            loggedAt: Date(timeIntervalSinceNow: -2 * 86_400),
            exerciseName: "Hanging Knee Raise",
            weightLbs: 0, repsCompleted: 15, notes: ""
        )
        XCTAssertEqual(entry.bestRepsCompleted, 15)

        entry.applyLog(
            loggedAt: Date(timeIntervalSinceNow: -86_400),
            exerciseName: "Hanging Knee Raise",
            weightLbs: 0, repsCompleted: 13, notes: ""
        )
        XCTAssertEqual(entry.bestRepsCompleted, 15, "A worse rep count must not overwrite the best")
    }

    // MARK: - Structured targetRIR decode

    func testExerciseResponseDecodesAndClampsTargetRIR() throws {
        func decode(_ json: String) throws -> WorkoutExerciseResponse {
            try JSONDecoder().decode(WorkoutExerciseResponse.self, from: Data(json.utf8))
        }
        let base = #""exerciseName": "Row", "sets": 3, "reps": "8-10", "tempo": "", "restSeconds": 90, "notes": "Set the scapula first and pull with the elbows.", "muscleTarget": "Back""#

        XCTAssertEqual(try decode("{\(base), \"targetRIR\": 2}").targetRIR, 2)
        XCTAssertNil(try decode("{\(base), \"targetRIR\": 9}").targetRIR, "Out-of-range junk is dropped, not stored")
        XCTAssertNil(try decode("{\(base)}").targetRIR, "Pre-field programs decode with nil")
    }

    // MARK: - Execution-only notes policy

    func testProgressionInstructionDetectorMatchesRealOffenders() {
        for offender in [
            "Try 2.5 lb next session.",
            "Progression target: add 2.5-5 lb or 1 rep versus last week.",
            "Keep this at 2 RIR maintenance — add a rep before adding a barbell step.",
            "When you clear 15 clean reps, add ankle weight.",
            "Baseline target: finish sets with 2-3 reps in reserve."
        ] {
            XCTAssertTrue(service.notesContainProgressionInstruction(offender), "Should flag: \(offender)")
        }
        for clean in [
            "Brace hard and keep ribs over pelvis out of the hole.",
            "Curl the pelvis up rather than just lifting the knees, no swinging.",
            // Was "Prioritize full range and repeatable rep mechanics before chasing heavier
            // load." — clean against THIS detector, which is why it passed here for months,
            // but it matched `coachingCueConflict`'s add-load pattern and burned a paid
            // correction pass whenever the logged verdict was hold-below-range. Passing one
            // execution-only rule is not the same as being execution-only; see
            // CoachingVoiceTests.testNoCueContradictsTheProgressionVerdict, which checks the
            // whole cue library against both.
            "Prioritise a full range and repeatable mechanics over anything else in the set."
        ] {
            XCTAssertFalse(service.notesContainProgressionInstruction(clean), "Should NOT flag: \(clean)")
        }
    }

    func testProceduralNotesAreExecutionOnlyAndRIRIsStructured() {
        for week in 1...4 {
            let notes = service.proceduralExerciseNotes(
                weekNumber: week,
                exerciseName: "Incline Barbell Press",
                muscleTarget: "Upper Chest",
                index: 0,
                focus: "Upper Chest"
            )
            XCTAssertFalse(
                service.notesContainProgressionInstruction(notes),
                "Week \(week) procedural notes must not carry progression prose: \(notes)"
            )
        }
        XCTAssertEqual(service.proceduralTargetRIR(for: 1), 2)
        XCTAssertEqual(service.proceduralTargetRIR(for: 2), 2)
        XCTAssertEqual(service.proceduralTargetRIR(for: 3), 1, "Peak week pushes closer to failure")
        XCTAssertEqual(service.proceduralTargetRIR(for: 4), 3, "Deload week backs off")
    }
}
