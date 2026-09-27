import Foundation
import XCTest
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
}
