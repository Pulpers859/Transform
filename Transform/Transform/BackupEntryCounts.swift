import Foundation

/// How many records of each kind the store holds, and the two rules that read a fall in those
/// counts as data loss: `hasSignificantDrop` (skip the automatic backup, and the startup
/// "Data loss detected" warning) and `shouldAttemptAutomaticRecovery` (merge the last
/// automatic backup back in at launch).
///
/// Moved out of `DataBackupManager.swift`, which the headless test package cannot compile,
/// so these rules have executed coverage. `DataBackupManager.EntryCounts` is a typealias for
/// this type; the stored JSON shape is unchanged.
nonisolated struct BackupEntryCounts: Codable, Equatable {
    let sleep: Int
    let weight: Int
    let nutrition: Int
    let measurement: Int
    let exerciseWeights: Int
    let exerciseLogs: Int
    let analyses: Int
    let workouts: Int
    let favorites: Int
    let savedNutritionProtocols: Int
    let progressPhotos: Int

    private enum CodingKeys: String, CodingKey {
        case sleep
        case weight
        case nutrition
        case measurement
        case exerciseWeights
        case exerciseLogs
        case analyses
        case workouts
        case favorites
        case savedNutritionProtocols
        case progressPhotos
        case total
    }

    init(
        sleep: Int,
        weight: Int,
        nutrition: Int,
        measurement: Int = 0,
        exerciseWeights: Int = 0,
        exerciseLogs: Int = 0,
        analyses: Int = 0,
        workouts: Int = 0,
        favorites: Int = 0,
        savedNutritionProtocols: Int = 0,
        progressPhotos: Int = 0
    ) {
        self.sleep = sleep
        self.weight = weight
        self.nutrition = nutrition
        self.measurement = measurement
        self.exerciseWeights = exerciseWeights
        self.exerciseLogs = exerciseLogs
        self.analyses = analyses
        self.workouts = workouts
        self.favorites = favorites
        self.savedNutritionProtocols = savedNutritionProtocols
        self.progressPhotos = progressPhotos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sleep = try container.decodeIfPresent(Int.self, forKey: .sleep) ?? 0
        weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 0
        nutrition = try container.decodeIfPresent(Int.self, forKey: .nutrition) ?? 0
        measurement = try container.decodeIfPresent(Int.self, forKey: .measurement) ?? 0
        exerciseWeights = try container.decodeIfPresent(Int.self, forKey: .exerciseWeights) ?? 0
        exerciseLogs = try container.decodeIfPresent(Int.self, forKey: .exerciseLogs) ?? 0
        analyses = try container.decodeIfPresent(Int.self, forKey: .analyses) ?? 0
        workouts = try container.decodeIfPresent(Int.self, forKey: .workouts) ?? 0
        favorites = try container.decodeIfPresent(Int.self, forKey: .favorites) ?? 0
        savedNutritionProtocols = try container.decodeIfPresent(Int.self, forKey: .savedNutritionProtocols) ?? 0
        progressPhotos = try container.decodeIfPresent(Int.self, forKey: .progressPhotos) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sleep, forKey: .sleep)
        try container.encode(weight, forKey: .weight)
        try container.encode(nutrition, forKey: .nutrition)
        try container.encode(measurement, forKey: .measurement)
        try container.encode(exerciseWeights, forKey: .exerciseWeights)
        try container.encode(exerciseLogs, forKey: .exerciseLogs)
        try container.encode(analyses, forKey: .analyses)
        try container.encode(workouts, forKey: .workouts)
        try container.encode(favorites, forKey: .favorites)
        try container.encode(savedNutritionProtocols, forKey: .savedNutritionProtocols)
        try container.encode(progressPhotos, forKey: .progressPhotos)
        try container.encode(total, forKey: .total)
    }

    var total: Int {
        sleep
            + weight
            + nutrition
            + measurement
            + exerciseWeights
            + exerciseLogs
            + analyses
            + workouts
            + favorites
            + savedNutritionProtocols
            + progressPhotos
    }

    var debugSummary: String {
        "sleep=\(sleep) weight=\(weight) nutrition=\(nutrition) measurement=\(measurement) exerciseWeights=\(exerciseWeights) exerciseLogs=\(exerciseLogs) analyses=\(analyses) workouts=\(workouts) favorites=\(favorites) savedProtocols=\(savedNutritionProtocols) progressPhotos=\(progressPhotos)"
    }

    func dropSummary(comparedTo previous: BackupEntryCounts) -> String {
        "sleep=\(previous.sleep - sleep) weight=\(previous.weight - weight) nutrition=\(previous.nutrition - nutrition) measurement=\(previous.measurement - measurement) exerciseWeights=\(previous.exerciseWeights - exerciseWeights) exerciseLogs=\(previous.exerciseLogs - exerciseLogs) analyses=\(previous.analyses - analyses) workouts=\(previous.workouts - workouts) favorites=\(previous.favorites - favorites) savedProtocols=\(previous.savedNutritionProtocols - savedNutritionProtocols) progressPhotos=\(previous.progressPhotos - progressPhotos) total=\(previous.total - total)"
    }

    func hasSignificantDrop(comparedTo previous: BackupEntryCounts) -> Bool {
        let measurementDrop = previous.measurement - measurement
        let exerciseWeightDrop = previous.exerciseWeights - exerciseWeights
        let exerciseLogDrop = previous.exerciseLogs - exerciseLogs
        let analysesDrop = previous.analyses - analyses
        let workoutsDrop = previous.workouts - workouts
        let favoritesDrop = previous.favorites - favorites
        let savedProtocolDrop = previous.savedNutritionProtocols - savedNutritionProtocols
        let progressPhotoDrop = previous.progressPhotos - progressPhotos
        let totalDrop = previous.total - total

        return (previous.sleep - sleep) > 2
            || (previous.weight - weight) > 2
            || (previous.nutrition - nutrition) > 5
            || measurementDrop > 2
            || exerciseWeightDrop > 2
            || exerciseLogDrop > 2
            || analysesDrop > 1
            || workoutsDrop > 1
            || favoritesDrop > 10
            || savedProtocolDrop > 1
            || progressPhotoDrop > 1
            || totalDrop > 10
    }

    func shouldAttemptAutomaticRecovery(comparedTo previous: BackupEntryCounts) -> Bool {
        let totalDrop = previous.total - total
        let zeroedHighValueCategories = [
            previous.exerciseLogs > 0 && exerciseLogs == 0,
            previous.exerciseWeights > 0 && exerciseWeights == 0,
            previous.analyses > 0 && analyses == 0,
            previous.workouts > 0 && workouts == 0,
            previous.savedNutritionProtocols > 0 && savedNutritionProtocols == 0
        ].filter { $0 }.count

        return totalDrop > 10
            || (previous.exerciseLogs > 2 && exerciseLogs == 0)
            || (previous.exerciseWeights > 2 && exerciseWeights == 0)
            || zeroedHighValueCategories >= 2
    }

    // MARK: - Deliberate removals

    private func zipped(_ other: BackupEntryCounts, _ combine: (Int, Int) -> Int) -> BackupEntryCounts {
        BackupEntryCounts(
            sleep: combine(sleep, other.sleep),
            weight: combine(weight, other.weight),
            nutrition: combine(nutrition, other.nutrition),
            measurement: combine(measurement, other.measurement),
            exerciseWeights: combine(exerciseWeights, other.exerciseWeights),
            exerciseLogs: combine(exerciseLogs, other.exerciseLogs),
            analyses: combine(analyses, other.analyses),
            workouts: combine(workouts, other.workouts),
            favorites: combine(favorites, other.favorites),
            savedNutritionProtocols: combine(savedNutritionProtocols, other.savedNutritionProtocols),
            progressPhotos: combine(progressPhotos, other.progressPhotos)
        )
    }

    /// What one deliberate owner action removed: counted before it, minus counted after it,
    /// per category, never below zero (a category that grew removed nothing).
    static func deliberateRemoval(before: BackupEntryCounts, after: BackupEntryCounts) -> BackupEntryCounts {
        before.zipped(after) { Swift.max(0, $0 - $1) }
    }

    /// The baseline the loss rules should compare against after a deliberate removal.
    ///
    /// WHY: both baselines (the last automatic backup's counts, and the counts saved at the
    /// last launch) only move when a backup is written or the app starts. Reset Day deletes
    /// a whole day's logs in one save, which reads as a "significant drop", so the backup
    /// after it was skipped and the baseline stayed above the store. At the next launch the
    /// gap could exceed the recovery threshold and the PRE-RESET backup was merged back in,
    /// undoing the reset; a smaller gap still raised "Data loss detected" (bug audit
    /// 2026-11-17, F2 and F5).
    ///
    /// The rule, per category: `max(after, baseline - removed)`.
    ///  * Baseline at or below the pre-action count (records were added since it was taken):
    ///    the result is `after`. The deliberate removal is fully explained and nothing is
    ///    loosened beyond it.
    ///  * Baseline ABOVE the pre-action count (something had already gone missing without
    ///    explanation): the result stays exactly that much above `after`, so the guard still
    ///    sees the unexplained loss. A deliberate action never launders an earlier loss.
    /// Subtracting `removed` from the baseline alone would loosen the guard in the first case
    /// by every record added since the baseline was taken. Pinned by BackupDropGuardTests.
    func acknowledgingDeliberateRemoval(_ removed: BackupEntryCounts, after: BackupEntryCounts) -> BackupEntryCounts {
        zipped(removed) { $0 - $1 }.zipped(after) { Swift.max($0, $1) }
    }
}
