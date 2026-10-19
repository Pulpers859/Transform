import Foundation
import XCTest
import SwiftData
@testable import Transform

/// Pins the "About N min" line on the day screen. Expected per-set seconds were computed by
/// hand: mid-range reps times the tempo's seconds per rep.
@MainActor
final class SessionLengthDisplayTests: XCTestCase {

    private let service = ClaudeService.shared

    func testRepTempoSecondsAreMidRangeRepsTimesTempo() {
        XCTAssertEqual(ClaudeService.repTempoSecondsPerSet(reps: "12-20", tempo: "2-0-1-1"), 64)
        XCTAssertEqual(ClaudeService.repTempoSecondsPerSet(reps: "10-12", tempo: "3-1-1-0"), 55)
        XCTAssertEqual(ClaudeService.repTempoSecondsPerSet(reps: "10", tempo: "3-1-1"), 50)
        XCTAssertEqual(ClaudeService.repTempoSecondsPerSet(reps: "8-12", tempo: "X-0-1-0"), 20,
                       "An explosive phase counts as one second")
    }

    func testUnreadableFieldsFallBackToTheRoleDefault() {
        XCTAssertNil(ClaudeService.repTempoSecondsPerSet(reps: "30s", tempo: "2-0-1-1"))
        XCTAssertNil(ClaudeService.repTempoSecondsPerSet(reps: "AMRAP", tempo: "2-0-1-1"))
        XCTAssertNil(ClaudeService.repTempoSecondsPerSet(reps: "10-12", tempo: ""))
        XCTAssertNil(ClaudeService.repTempoSecondsPerSet(reps: "10-12", tempo: "slow"))
    }

    /// A slow high-rep set takes far longer than the flat per-role figure, so the shown
    /// estimate must grow — while the default (used by every older test) must not move.
    func testCountingTempoLengthensASlowDayAndLeavesTheDefaultAlone() {
        let raise = WorkoutExerciseResponse(
            exerciseName: "Cable Lateral Raise", sets: 4, reps: "12-20", tempo: "2-0-1-1",
            restSeconds: 60, notes: "", muscleTarget: "Lateral Deltoids")
        let day = WorkoutDayResponse(
            dayNumber: 1, dayName: "Upper", muscleGroups: "Shoulders", isRestDay: false,
            notes: "", exercises: [raise])
        let flat = service.estimatedExerciseMinutes(for: raise)
        let counted = service.estimatedExerciseMinutes(for: raise, countingRepTempo: true)
        XCTAssertGreaterThan(counted, flat)
        XCTAssertEqual(service.estimatedSessionMinutes(for: day, countingRepTempo: false),
                       service.estimatedSessionMinutes(for: day))
    }

    func testTheDayScreenFigureIsRoundedUpToFiveAndHiddenOnRestDays() throws {
        // Same in-memory setup as WorkoutDayResetTests: relationships are only trustworthy on
        // inserted models.
        let container = try ModelContainer(for: WorkoutProgram.self, ExercisePerformanceLog.self,
                                          ExerciseWeightEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let program = WorkoutProgram(programName: "Test", programSummary: "", splitType: "Upper", daysPerWeek: 3, focusAreas: "Quads")
        let day = WorkoutDay(dayNumber: 9, dayName: "Lower", muscleGroups: "Quads")
        let press = WorkoutExercise(order: 0, exerciseName: "Leg Press", sets: 4, reps: "10-12",
                                    tempo: "3-1-1-0", restSeconds: 150, muscleTarget: "Quads")
        context.insert(program)
        program.days = [day]
        day.program = program
        day.exercises = [press]
        press.day = day
        try context.save()

        let shown = try XCTUnwrap(service.displayedSessionMinutes(for: day))
        XCTAssertEqual(shown % 5, 0)
        XCTAssertGreaterThanOrEqual(shown, 8, "Never less than the warm-up alone")

        let rest = WorkoutDay(dayNumber: 10, dayName: "Rest", muscleGroups: "", isRestDay: true)
        XCTAssertNil(service.displayedSessionMinutes(for: rest))
    }
}
