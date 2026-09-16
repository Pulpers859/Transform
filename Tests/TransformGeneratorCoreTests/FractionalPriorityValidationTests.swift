import XCTest
@testable import Transform

/// Isolates the redundant non-focus volume warning using real exercise stimulus accounting.
/// No claim that these two-day validator fixtures are otherwise complete or valid programs.
@MainActor
final class FractionalPriorityValidationTests: XCTestCase {
    private let service = ClaudeService.shared

    private func findings(target: Double, delivered: Int, secondDayFocus: String? = nil,
                          secondDaySupport: [String] = []) -> [String] {
        let allocation = ClaudeService.BlueprintPriorityAllocation(area: "Lats", priorityLevel: "Medium",
            rationale: "test", targetFrequency: 1, targetExerciseSlots: 2, directSetTarget: target,
            weightedStimulusTarget: target, maxPerSessionDirectSets: 6, maxFocusSessionDirectSets: 6,
            preferredStyles: ["Pull"], preferredMovementPatterns: ["Vertical Pull"],
            volumeBias: "Moderate", directWorkBias: "Direct emphasis")
        let plans: [ClaudeService.BlueprintDayPlan] = (1...2).map { number in
            .init(dayIndex: number, style: "Pull", focusArea: number == 1 ? "Lats" : secondDayFocus,
                supportAreas: number == 1 ? [] : secondDaySupport, targetFatigueCap: 48,
                targetSessionMinutes: 75, targetPrioritySlots: 1, emphasisPatterns: [], isRestDay: false)
        }
        let blueprint = ClaudeService.ProgramBlueprint(evidenceVersion: "test", splitRecommendation: "Pull",
            weeklyTrainingDays: 2, priorityAllocations: [allocation], dayPlans: plans, topLeverageChange: "",
            posturalFocus: "", injuryRiskFocus: "", programmingNotes: [], calibration: service.neutralCalibrationProfile())
        let days: [WorkoutDayResponse] = (1...2).map { number in
            .init(dayNumber: number, dayName: "Pull", muscleGroups: "Lats", isRestDay: false, notes: "",
                exercises: [.init(exerciseName: number == 1 ? "Lat Pulldown" : "Neutral-Grip Lat Pulldown",
                    sets: number == 1 ? 4 : delivered - 4, reps: "8-12", tempo: "2-0-1-1",
                    restSeconds: 90, notes: "", muscleTarget: "Lats")])
        }
        let report = service.buildWeekStimulusReport(from: days)
        let coverage = service.priorityCoverage(for: allocation, stimulusReport: report)
        XCTAssertEqual(coverage.directSets, Double(delivered), accuracy: 0.000001,
            "Fixture must actually credit the asserted weekly dose through production accounting")
        let allocatedDays = service.allocatedDayNumbers(for: allocation, blueprint: blueprint, dayStart: 1)
        XCTAssertTrue(allocatedDays.contains(1))
        XCTAssertEqual(allocatedDays.contains(2), secondDayFocus == "Lats" || secondDaySupport.contains("Lats"))
        XCTAssertTrue(service.validateRedundantPriorityVolume(on: days[0], dayPlan: plans[0],
            blueprint: blueprint, stimulusReport: report, dayStart: 1).isEmpty,
            "This warning remains excluded on an allocated focus day")
        return service.validateRedundantPriorityVolume(on: days[1], dayPlan: plans[1],
            blueprint: blueprint, stimulusReport: report, dayStart: 1)
    }

    func testEightSetsMeetingSevenAndAHalfTargetAreNotNonFocusSurplus() {
        XCTAssertTrue(findings(target: 7.5, delivered: 8).isEmpty)
    }

    func testNineSetsStillWarnOnNonFocusDayAboveFractionalTargetCeiling() {
        let issues = findings(target: 7.5, delivered: 9)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues.first?.contains("Day 2: Lats already reached its weekly target") == true)
        XCTAssertTrue(issues.first?.contains("Neutral-Grip Lat Pulldown") == true)
    }

    func testEightSetsStillWarnAboveIntegerSevenTarget() {
        let issues = findings(target: 7, delivered: 8)
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues.first?.contains("non-focus day still adds volume") == true)
    }

    func testAllocatedFocusAndSupportDaysKeepTheirExistingExemption() {
        XCTAssertTrue(findings(target: 7.5, delivered: 9, secondDayFocus: "Lats").isEmpty)
        XCTAssertTrue(findings(target: 7.5, delivered: 9, secondDaySupport: ["Lats"]).isEmpty)
        XCTAssertEqual(findings(target: 7.5, delivered: 9, secondDayFocus: "Biceps").count, 1,
            "A different focus is not an exemption for Lats")
    }
}
