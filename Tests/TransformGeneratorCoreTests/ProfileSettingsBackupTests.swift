import XCTest
@testable import Transform

/// The settings half of a backup (`ProfileSettingsSnapshot`).
final class ProfileSettingsBackupTests: XCTestCase {
    private func freshDefaults() throws -> UserDefaults {
        let name = "ProfileSettingsBackupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func roundTrip(_ source: UserDefaults, into target: UserDefaults) throws {
        let data = try JSONEncoder().encode(ProfileSettingsSnapshot.fromUserDefaults(source))
        try JSONDecoder().decode(ProfileSettingsSnapshot.self, from: data).applyToUserDefaults(target)
    }

    /// Bug audit 2026-11-17, F4. The app stores these six as TEXT (`@AppStorage` String
    /// fields); the backup read them as numbers, so every backup left them out and a restore
    /// on a new phone silently put the defaults back.
    func testTargetsGoalAndSleepHoursStoredAsTextSurviveABackupRoundTrip() throws {
        let source = try freshDefaults()
        let values: [(String, String)] = [
            (AppSettingsKeys.calorieTarget, "2650"),
            (AppSettingsKeys.proteinTarget, "195"),
            (AppSettingsKeys.carbTarget, "240"),
            (AppSettingsKeys.fatTarget, "75.5"),
            (AppSettingsKeys.bodyWeightGoal, "182"),
            (AppSettingsKeys.analysisSleepHours, "7.5"),
        ]
        for (key, value) in values { source.set(value, forKey: key) }
        let target = try freshDefaults()
        try roundTrip(source, into: target)
        for (key, value) in values {
            // Written back as text, the type `@AppStorage(String)` and AppSettingsStore read.
            XCTAssertEqual(target.object(forKey: key) as? String, value, key)
        }
    }

    /// Goal progress is measured from the date the goal was set, so it travels with the goal.
    func testBodyWeightGoalDateTravelsWithTheGoal() throws {
        let source = try freshDefaults()
        source.set("182", forKey: AppSettingsKeys.bodyWeightGoal)
        source.set(1_760_000_000.0, forKey: AppSettingsKeys.bodyWeightGoalSetAt)
        let target = try freshDefaults()
        try roundTrip(source, into: target)
        XCTAssertEqual(target.double(forKey: AppSettingsKeys.bodyWeightGoalSetAt), 1_760_000_000)
    }

    /// Settings already stored as numbers, and the injury note, still round-trip.
    func testNumericAndTextSettingsStillRoundTrip() throws {
        let source = try freshDefaults()
        source.set(34, forKey: AppSettingsKeys.analysisAgeValue)
        source.set(true, forKey: AppSettingsKeys.medicalCurrentInjury)
        source.set("Shoulder pain pressing overhead", forKey: AppSettingsKeys.analysisPainHistory)
        let target = try freshDefaults()
        try roundTrip(source, into: target)
        XCTAssertEqual(target.object(forKey: AppSettingsKeys.analysisAgeValue) as? Int, 34)
        XCTAssertEqual(target.object(forKey: AppSettingsKeys.medicalCurrentInjury) as? Bool, true)
        XCTAssertEqual(target.string(forKey: AppSettingsKeys.analysisPainHistory), "Shoulder pain pressing overhead")
    }

    /// A backup written before any of this, or one holding none of these settings, changes
    /// nothing already on the phone.
    func testABackupWithoutTheseSettingsLeavesThePhoneAlone() throws {
        let target = try freshDefaults()
        target.set("2500", forKey: AppSettingsKeys.calorieTarget)
        target.set("Shoulder pain pressing overhead", forKey: AppSettingsKeys.analysisPainHistory)
        try JSONDecoder().decode(ProfileSettingsSnapshot.self, from: Data("{}".utf8)).applyToUserDefaults(target)
        XCTAssertEqual(target.object(forKey: AppSettingsKeys.calorieTarget) as? String, "2500")
        XCTAssertEqual(target.string(forKey: AppSettingsKeys.analysisPainHistory), "Shoulder pain pressing overhead")
    }
}
