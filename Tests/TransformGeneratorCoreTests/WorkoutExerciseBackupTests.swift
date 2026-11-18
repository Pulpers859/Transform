import Foundation
import XCTest
import SwiftData
@testable import Transform

final class WorkoutExerciseBackupTests: XCTestCase {
    private let legacy = #"{"order":0,"exerciseName":"Dumbbell Lateral Raise","sets":3,"reps":"10-15","restSeconds":75,"notes":"Original cue","muscleTarget":"Lateral Deltoids","isCompleted":true,"completionStatusRaw":"Skipped — pain/discomfort"}"#

    func testOldBackupDoesNotInventPainResolutionOrReplacement() throws {
        let record = try JSONDecoder().decode(WorkoutExerciseSnapshot.self, from: Data(legacy.utf8))
        XCTAssertNil(record.painReviewRaw)
        XCTAssertNil(record.replacementName)
        XCTAssertNil(record.preferredReplacementName)
        XCTAssertEqual(record.sets, 3)
        XCTAssertEqual(record.completionStatusRaw, "Skipped — pain/discomfort")
    }

    func testNewBackupRoundTripsResolutionReplacementAndPreferenceWithoutChangingOriginal() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(legacy.utf8)) as? [String: Any])
        json["painReviewRaw"] = "resolved"
        json["replacementName"] = "Machine Lateral Raise"
        json["preferredReplacementName"] = "Machine Lateral Raise"
        let record = try JSONDecoder().decode(WorkoutExerciseSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        let restored = try JSONDecoder().decode(WorkoutExerciseSnapshot.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.painReviewRaw, "resolved")
        XCTAssertEqual(restored.replacementName, "Machine Lateral Raise")
        XCTAssertEqual(restored.preferredReplacementName, "Machine Lateral Raise")
        XCTAssertEqual(restored.exerciseName, "Dumbbell Lateral Raise")
        XCTAssertEqual(restored.sets, 3)
        XCTAssertEqual(restored.completionStatusRaw, "Skipped — pain/discomfort")
    }

    // MARK: - Whole program round trip (bug audit 2026-11-17, F7)

    @MainActor
    private func programRoundTrip(_ program: WorkoutProgram) throws -> WorkoutProgram {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(WorkoutProgramSnapshot(program))
        return try decoder.decode(WorkoutProgramSnapshot.self, from: data).makeModel()
    }

    /// A program restored from a backup lost its warnings banner and its week summaries.
    @MainActor
    func testProgramWarningsAndWeekSummariesSurviveABackupRoundTrip() throws {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let program = WorkoutProgram(programName: "Block 3", programSummary: "Summary", splitType: "Upper/Lower",
                                     daysPerWeek: 4, focusAreas: "Lateral Deltoids",
                                     validatorWarnings: "Chest maintenance is below target this week.")
        program.setWeekSummary("Week 1: build volume", for: 1)
        program.setWeekSummary("Week 2: add load", for: 2)
        let day = WorkoutDay(dayNumber: 1, dayName: "Upper A", muscleGroups: "Chest, Back")
        day.isSessionClosed = true
        let exercise = WorkoutExercise(order: 0, exerciseName: "Dumbbell Lateral Raise", sets: 3, reps: "12-15",
                                       muscleTarget: "Lateral Deltoids", targetRIR: 1)
        context.insert(program)
        program.days = [day]
        day.program = program
        day.exercises = [exercise]
        exercise.day = day

        let restored = try programRoundTrip(program)
        context.insert(restored)
        XCTAssertEqual(restored.validatorWarnings, "Chest maintenance is below target this week.")
        XCTAssertEqual(restored.weekSummary(for: 1), "Week 1: build volume")
        XCTAssertEqual(restored.weekSummary(for: 2), "Week 2: add load")
        XCTAssertEqual(restored.id, program.id)
        XCTAssertEqual(restored.sortedDays.map(\.isSessionClosed), [true])
        XCTAssertEqual(restored.sortedDays.first?.sortedExercises.map(\.exerciseName), ["Dumbbell Lateral Raise"])
        XCTAssertEqual(restored.sortedDays.first?.sortedExercises.first?.targetRIR, 1)
    }

    /// A backup written before these fields existed still restores, with them empty.
    @MainActor
    func testOlderProgramBackupWithoutWarningsStillRestores() throws {
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                           ExerciseWeightEntry.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","createdDate":"2026-09-01T12:00:00Z","programName":"Old","programSummary":"","splitType":"Push","daysPerWeek":3,"totalDays":7,"focusAreas":"","programJSON":"","currentWeek":2,"maxWeeks":4,"analysisJSON":"","days":[],"isArchived":true}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(WorkoutProgramSnapshot.self, from: Data(old.utf8)).makeModel()
        context.insert(restored)
        XCTAssertEqual(restored.validatorWarnings, "")
        XCTAssertEqual(restored.weekSummariesJSON, "")
        XCTAssertTrue(restored.isArchived)
        XCTAssertEqual(restored.currentWeek, 2)
    }
}
