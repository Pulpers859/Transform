import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

nonisolated private enum BackupFormat {
    static let currentVersion = 9
    static let supportedVersions: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9]
}

@MainActor
private func mainActorMap<Input, Output>(
    _ values: [Input],
    _ transform: @MainActor (Input) -> Output
) -> [Output] {
    var results: [Output] = []
    results.reserveCapacity(values.count)
    for value in values {
        results.append(transform(value))
    }
    return results
}

@MainActor
private func mainActorFirst<Input>(
    in values: [Input],
    where predicate: @MainActor (Input) -> Bool
) -> Input? {
    for value in values where predicate(value) {
        return value
    }
    return nil
}

nonisolated private func backupDateDedupeKey(_ date: Date) -> Int64 {
    Int64(floor(date.timeIntervalSince1970))
}

nonisolated private enum BackupDedupeKey {
    private static let separator = "\u{1F}"

    static func date(_ date: Date) -> String {
        String(backupDateDedupeKey(date))
    }

    static func make(_ parts: CustomStringConvertible?...) -> String {
        parts
            .map { $0?.description ?? "nil" }
            .joined(separator: separator)
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let incoming = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = incoming
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated struct TransformBackupPayload: Codable {
    let version: Int
    let exportedAt: Date
    let weights: [WeightSnapshot]
    let sleep: [SleepSnapshot]?
    let measurements: [MeasurementSnapshot]
    let nutrition: [NutritionSnapshot]
    let favorites: [FavoriteFoodSnapshot]
    let savedNutritionProtocols: [SavedNutritionProtocolSnapshot]?
    let progressPhotos: [ProgressPhotoSnapshot]?
    let analyses: [AnalysisSnapshot]
    let workouts: [WorkoutProgramSnapshot]
    let exerciseWeights: [ExerciseWeightSnapshot]?
    let exercisePerformanceLogs: [ExercisePerformanceLogSnapshot]?
    let profileSettings: ProfileSettingsSnapshot?

    init(
        version: Int,
        exportedAt: Date,
        weights: [WeightSnapshot],
        sleep: [SleepSnapshot]?,
        measurements: [MeasurementSnapshot],
        nutrition: [NutritionSnapshot],
        favorites: [FavoriteFoodSnapshot],
        savedNutritionProtocols: [SavedNutritionProtocolSnapshot]?,
        progressPhotos: [ProgressPhotoSnapshot]?,
        analyses: [AnalysisSnapshot],
        workouts: [WorkoutProgramSnapshot],
        exerciseWeights: [ExerciseWeightSnapshot]?,
        exercisePerformanceLogs: [ExercisePerformanceLogSnapshot]?,
        profileSettings: ProfileSettingsSnapshot? = nil
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.weights = weights
        self.sleep = sleep
        self.measurements = measurements
        self.nutrition = nutrition
        self.favorites = favorites
        self.savedNutritionProtocols = savedNutritionProtocols
        self.progressPhotos = progressPhotos
        self.analyses = analyses
        self.workouts = workouts
        self.exerciseWeights = exerciseWeights
        self.exercisePerformanceLogs = exercisePerformanceLogs
        self.profileSettings = profileSettings
    }
}

// Legacy backup shape (before sugar/fiber/favorites fields were introduced).
nonisolated struct LegacyTransformBackupPayload: Codable {
    let weights: [WeightSnapshot]
    let measurements: [MeasurementSnapshot]
    let nutrition: [LegacyNutritionSnapshot]
    let analyses: [AnalysisSnapshot]
    let workouts: [WorkoutProgramSnapshot]
}

nonisolated struct LegacyNutritionSnapshot: Codable {
    let date: Date
    let mealName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let notes: String
}

nonisolated struct WeightSnapshot: Codable {
    let date: Date
    let weightLbs: Double
    let notes: String
}

nonisolated struct SleepSnapshot: Codable {
    let date: Date
    let durationHours: Double
    let qualityRating: Int
    let shiftTypeRaw: String
    let notes: String
    let startDate: Date?
    let endDate: Date?
    let episodeTypeRaw: String?
    // Optional so older backups (no source key) still decode — missing means manual.
    let sourceRaw: String?
}

nonisolated struct MeasurementSnapshot: Codable {
    let date: Date
    let chestIn: Double?
    let waistIn: Double?
    let hipsIn: Double?
    let neckIn: Double?
    let leftArmIn: Double?
    let rightArmIn: Double?
    let leftThighIn: Double?
    let rightThighIn: Double?
    let leftCalfIn: Double?
    let rightCalfIn: Double?
    let bodyFatPct: Double?
    let notes: String
    let measurementTiming: String?
    let isStandardMeasurement: Bool?

    init(
        date: Date,
        chestIn: Double?,
        waistIn: Double?,
        hipsIn: Double?,
        neckIn: Double?,
        leftArmIn: Double?,
        rightArmIn: Double?,
        leftThighIn: Double?,
        rightThighIn: Double?,
        leftCalfIn: Double? = nil,
        rightCalfIn: Double? = nil,
        bodyFatPct: Double?,
        notes: String,
        measurementTiming: String? = nil,
        isStandardMeasurement: Bool? = nil
    ) {
        self.date = date
        self.chestIn = chestIn
        self.waistIn = waistIn
        self.hipsIn = hipsIn
        self.neckIn = neckIn
        self.leftArmIn = leftArmIn
        self.rightArmIn = rightArmIn
        self.leftThighIn = leftThighIn
        self.rightThighIn = rightThighIn
        self.leftCalfIn = leftCalfIn
        self.rightCalfIn = rightCalfIn
        self.bodyFatPct = bodyFatPct
        self.notes = notes
        self.measurementTiming = measurementTiming
        self.isStandardMeasurement = isStandardMeasurement
    }
}

nonisolated struct NutritionSnapshot: Codable {
    let date: Date
    let mealName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let sugarG: Double
    let fiberG: Double
    let fatG: Double
    let notes: String
}

nonisolated struct FavoriteFoodSnapshot: Codable {
    let createdAt: Date
    let name: String
    let mealName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let sugarG: Double
    let fiberG: Double
    let fatG: Double
}

nonisolated struct SavedNutritionProtocolSnapshot: Codable {
    let createdAt: Date
    let updatedAt: Date
    let programJSON: String
    let followupWeeksJSON: String
    let macroReviewJSON: String?
    let macroReviewUpdatedAt: Date?
    let appliedCalories: Int?
    let appliedProteinG: Double?
    let appliedCarbsG: Double?
    let appliedFatG: Double?
}

nonisolated struct ProgressPhotoSnapshot: Codable {
    let date: Date
    let pose: String
    let imageData: Data
    let aiAnalysis: String?
    let notes: String
}

nonisolated struct AnalysisSnapshot: Codable {
    let date: Date
    let photoData: Data
    let pose: String
    let analysisJSON: String
    let photoCount: Int
    let analysisResult: String
    let priorityMuscles: String
    let dietRecommendation: String
}

// `WorkoutProgramSnapshot` and `WorkoutDaySnapshot` live in WorkoutExerciseSnapshot.swift.

nonisolated struct ExerciseWeightSnapshot: Codable {
    let loggedAt: Date
    let exerciseName: String
    let weightLbs: Double
    let repsCompleted: Int?
    let notes: String
    let canonicalExerciseKey: String?
    let bestWeightLbs: Double?
    let bestLoggedAt: Date?
    let bestRepsCompleted: Int?
    let bestNotes: String?
}

nonisolated struct ExercisePerformanceLogSnapshot: Codable {
    let loggedAt: Date
    let exerciseName: String
    let weightLbs: Double
    let repsCompleted: Int?
    let notes: String
    let muscleTarget: String
    let canonicalExerciseKey: String?
    let setLogsJSON: String?
    let workoutDayNumber: Int?
    /// Optional, like every field added after v1: a backup written before these existed
    /// decodes with them absent rather than failing. A restore that dropped them would
    /// turn a session whose prescription IS known back into an ungradeable one.
    let prescribedSets: Int?
    let prescribedReps: String?
    /// Optional for the same reason; absent in every backup written before it existed.
    var prescribedTargetRIR: Int? = nil
}

// `ProfileSettingsSnapshot` lives in ProfileSettingsBackup.swift so the headless tests
// can round-trip it.

@MainActor private extension WeightSnapshot {
    init(_ entry: WeightEntry) {
        self.init(date: entry.date, weightLbs: entry.weightLbs, notes: entry.notes)
    }

    var dedupeKey: String {
        BackupDedupeKey.make(BackupDedupeKey.date(date), weightLbs, notes)
    }

    func makeModel() -> WeightEntry {
        WeightEntry(date: date, weightLbs: weightLbs, notes: notes)
    }
}

@MainActor private extension SleepSnapshot {
    init(_ entry: SleepEntry) {
        self.init(
            date: entry.date,
            durationHours: entry.durationHours,
            qualityRating: entry.qualityRating,
            shiftTypeRaw: entry.shiftTypeRaw,
            notes: entry.notes,
            startDate: entry.startDate,
            endDate: entry.endDate,
            episodeTypeRaw: entry.episodeTypeRaw,
            sourceRaw: entry.sourceRaw
        )
    }

    var dedupeKey: String {
        let resolvedEnd = endDate ?? (
            Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        )
        let resolvedStart = startDate ?? resolvedEnd.addingTimeInterval(-durationHours * 3600)
        return BackupDedupeKey.make(
            BackupDedupeKey.date(resolvedStart),
            BackupDedupeKey.date(resolvedEnd),
            episodeTypeRaw ?? SleepEpisodeType.mainSleep.rawValue
        )
    }

    func makeModel() -> SleepEntry {
        let resolvedEnd = endDate ?? (
            Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
        )
        let resolvedStart = startDate ?? resolvedEnd.addingTimeInterval(-durationHours * 3600)
        return SleepEntry(
            startDate: resolvedStart,
            endDate: resolvedEnd,
            qualityRating: qualityRating,
            shiftType: SleepShiftType(rawValue: shiftTypeRaw) ?? .off,
            episodeType: SleepEpisodeType(rawValue: episodeTypeRaw ?? "") ?? .mainSleep,
            notes: notes,
            source: SleepEntrySource(rawValue: sourceRaw ?? "") ?? .manual
        )
    }
}

@MainActor private extension MeasurementSnapshot {
    init(_ entry: MeasurementEntry) {
        self.init(
            date: entry.date,
            chestIn: entry.chestIn,
            waistIn: entry.waistIn,
            hipsIn: entry.hipsIn,
            neckIn: entry.neckIn,
            leftArmIn: entry.leftArmIn,
            rightArmIn: entry.rightArmIn,
            leftThighIn: entry.leftThighIn,
            rightThighIn: entry.rightThighIn,
            leftCalfIn: entry.leftCalfIn,
            rightCalfIn: entry.rightCalfIn,
            bodyFatPct: entry.bodyFatPct,
            notes: entry.notes,
            measurementTiming: entry.measurementTiming,
            isStandardMeasurement: entry.isStandardMeasurement
        )
    }

    var dedupeKey: String {
        BackupDedupeKey.make(BackupDedupeKey.date(date), waistIn ?? -1, chestIn ?? -1, notes)
    }

    func makeModel() -> MeasurementEntry {
        let entry = MeasurementEntry(date: date)
        entry.chestIn = chestIn
        entry.waistIn = waistIn
        entry.hipsIn = hipsIn
        entry.neckIn = neckIn
        entry.leftArmIn = leftArmIn
        entry.rightArmIn = rightArmIn
        entry.leftThighIn = leftThighIn
        entry.rightThighIn = rightThighIn
        entry.leftCalfIn = leftCalfIn
        entry.rightCalfIn = rightCalfIn
        entry.bodyFatPct = bodyFatPct
        entry.notes = notes
        entry.measurementTiming = measurementTiming
        entry.isStandardMeasurement = isStandardMeasurement ?? true
        return entry
    }
}

@MainActor private extension NutritionSnapshot {
    init(_ entry: NutritionEntry) {
        self.init(
            date: entry.date,
            mealName: entry.mealName,
            calories: entry.calories,
            proteinG: entry.proteinG,
            carbsG: entry.carbsG,
            sugarG: entry.sugarG,
            fiberG: entry.fiberG,
            fatG: entry.fatG,
            notes: entry.notes
        )
    }

    var dedupeKey: String {
        BackupDedupeKey.make(BackupDedupeKey.date(date), mealName, notes, calories, carbsG, proteinG, fatG)
    }

    func makeModel() -> NutritionEntry {
        NutritionEntry(
            date: date,
            mealName: mealName,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            notes: notes,
            sugarG: sugarG,
            fiberG: fiberG
        )
    }
}

@MainActor private extension FavoriteFoodSnapshot {
    init(_ favorite: FavoriteFood) {
        self.init(
            createdAt: favorite.createdAt,
            name: favorite.name,
            mealName: favorite.mealName,
            calories: favorite.calories,
            proteinG: favorite.proteinG,
            carbsG: favorite.carbsG,
            sugarG: favorite.sugarG,
            fiberG: favorite.fiberG,
            fatG: favorite.fatG
        )
    }

    var dedupeKey: String {
        BackupDedupeKey.make(mealName, name.lowercased())
    }

    func apply(to favorite: FavoriteFood) {
        favorite.createdAt = createdAt
        favorite.calories = calories
        favorite.proteinG = proteinG
        favorite.carbsG = carbsG
        favorite.sugarG = sugarG
        favorite.fiberG = fiberG
        favorite.fatG = fatG
    }

    func makeModel() -> FavoriteFood {
        FavoriteFood(
            createdAt: createdAt,
            name: name,
            mealName: mealName,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            sugarG: sugarG,
            fiberG: fiberG,
            fatG: fatG
        )
    }
}

@MainActor private extension SavedNutritionProtocolSnapshot {
    init(_ protocolModel: SavedNutritionProtocol) {
        self.init(
            createdAt: protocolModel.createdAt,
            updatedAt: protocolModel.updatedAt,
            programJSON: protocolModel.programJSON,
            followupWeeksJSON: protocolModel.followupWeeksJSON,
            macroReviewJSON: protocolModel.macroReviewJSON,
            macroReviewUpdatedAt: protocolModel.macroReviewUpdatedAt,
            appliedCalories: protocolModel.appliedCalories,
            appliedProteinG: protocolModel.appliedProteinG,
            appliedCarbsG: protocolModel.appliedCarbsG,
            appliedFatG: protocolModel.appliedFatG
        )
    }

    var dedupeKey: String {
        BackupDedupeKey.make(BackupDedupeKey.date(createdAt), programJSON, followupWeeksJSON, macroReviewJSON ?? "")
    }

    func makeModel() -> SavedNutritionProtocol {
        let model = SavedNutritionProtocol(
            createdAt: createdAt,
            updatedAt: updatedAt,
            programJSON: programJSON,
            followupWeeksJSON: followupWeeksJSON
        )
        model.macroReviewJSON = macroReviewJSON ?? ""
        model.macroReviewUpdatedAt = macroReviewUpdatedAt
        model.appliedCalories = appliedCalories
        model.appliedProteinG = appliedProteinG
        model.appliedCarbsG = appliedCarbsG
        model.appliedFatG = appliedFatG
        return model
    }
}

@MainActor private extension ProgressPhotoSnapshot {
    init(_ photo: ProgressPhoto) {
        self.init(
            date: photo.date,
            pose: photo.pose,
            imageData: photo.imageData,
            aiAnalysis: photo.aiAnalysis,
            notes: photo.notes
        )
    }

    var dedupeKey: String {
        BackupDedupeKey.make(BackupDedupeKey.date(date), pose, imageData.count, notes, aiAnalysis ?? "")
    }

    func makeModel() -> ProgressPhoto {
        let photo = ProgressPhoto(
            date: date,
            pose: pose,
            imageData: imageData,
            notes: notes
        )
        photo.aiAnalysis = aiAnalysis
        return photo
    }
}

@MainActor private extension AnalysisSnapshot {
    init(_ session: BodyAnalysisSession) {
        self.init(
            date: session.date,
            photoData: session.photoData,
            pose: session.pose,
            analysisJSON: session.analysisJSON,
            photoCount: session.photoCount,
            analysisResult: session.analysisResult,
            priorityMuscles: session.programmingPrioritySummary,
            dietRecommendation: session.dietRecommendation
        )
    }

    var dedupeKey: String {
        BackupDedupeKey.make(BackupDedupeKey.date(date), pose, photoCount, analysisResult)
    }

    func makeModel() -> BodyAnalysisSession {
        BodyAnalysisSession(
            date: date,
            photoData: photoData,
            pose: pose,
            analysisResult: analysisResult,
            priorityMuscles: priorityMuscles,
            dietRecommendation: dietRecommendation,
            analysisJSON: analysisJSON,
            photoCount: photoCount
        )
    }
}

@MainActor private extension ExerciseWeightSnapshot {
    var resolvedCanonicalKey: String {
        let recomputed = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        if !recomputed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recomputed
        }
        return canonicalExerciseKey ?? recomputed
    }

    init(_ entry: ExerciseWeightEntry) {
        self.init(
            loggedAt: entry.loggedAt,
            exerciseName: entry.exerciseName,
            weightLbs: entry.weightLbs,
            repsCompleted: entry.repsCompleted,
            notes: entry.notes,
            canonicalExerciseKey: entry.canonicalExerciseKey,
            bestWeightLbs: entry.hasBestRecord ? entry.bestWeightLbs : entry.weightLbs,
            bestLoggedAt: entry.bestLoggedAt ?? entry.loggedAt,
            bestRepsCompleted: entry.bestRepsCompleted ?? entry.repsCompleted,
            bestNotes: entry.hasBestRecord ? entry.bestNotes : entry.notes
        )
    }

    var dedupeKey: String {
        resolvedCanonicalKey
    }

    func makeModel() -> ExerciseWeightEntry {
        let entry = ExerciseWeightEntry(
            loggedAt: loggedAt,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            repsCompleted: repsCompleted,
            notes: notes
        )
        entry.canonicalExerciseKey = resolvedCanonicalKey
        entry.bestWeightLbs = bestWeightLbs ?? weightLbs
        entry.bestLoggedAt = bestLoggedAt ?? loggedAt
        entry.bestRepsCompleted = bestRepsCompleted ?? repsCompleted
        entry.bestNotes = bestNotes ?? notes
        return entry
    }

    func merge(into entry: ExerciseWeightEntry) {
        let incomingLast = ExerciseWeightEntry(
            loggedAt: loggedAt,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            repsCompleted: repsCompleted,
            notes: notes
        )

        if entry.loggedAt <= incomingLast.loggedAt {
            entry.loggedAt = incomingLast.loggedAt
            entry.exerciseName = incomingLast.exerciseName
            entry.normalizedExerciseName = incomingLast.normalizedExerciseName
            entry.weightLbs = incomingLast.weightLbs
            entry.repsCompleted = incomingLast.repsCompleted
            entry.notes = incomingLast.notes
        }

        let incomingBestWeight = bestWeightLbs ?? weightLbs
        let incomingBestDate = bestLoggedAt ?? loggedAt
        let incomingBestNotes = bestNotes ?? notes
        let shouldReplaceBest = !entry.hasBestRecord
            || incomingBestWeight > entry.bestWeightLbs + 0.001
            || (abs(incomingBestWeight - entry.bestWeightLbs) <= 0.001
                && (entry.bestLoggedAt ?? .distantPast) < incomingBestDate)

        if shouldReplaceBest {
            entry.bestWeightLbs = incomingBestWeight
            entry.bestLoggedAt = incomingBestDate
            entry.bestRepsCompleted = bestRepsCompleted ?? repsCompleted
            entry.bestNotes = incomingBestNotes
        }

        entry.canonicalExerciseKey = resolvedCanonicalKey
    }
}

@MainActor private extension ExercisePerformanceLogSnapshot {
    var resolvedCanonicalKey: String {
        let recomputed = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        if !recomputed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recomputed
        }
        return canonicalExerciseKey ?? recomputed
    }

    init(_ entry: ExercisePerformanceLog) {
        self.init(
            loggedAt: entry.loggedAt,
            exerciseName: entry.exerciseName,
            weightLbs: entry.weightLbs,
            repsCompleted: entry.repsCompleted,
            notes: entry.notes,
            muscleTarget: entry.muscleTarget,
            canonicalExerciseKey: entry.canonicalExerciseKey,
            setLogsJSON: entry.setLogsJSON.isEmpty ? nil : entry.setLogsJSON,
            workoutDayNumber: entry.workoutDayNumber,
            prescribedSets: entry.recordedPrescribedSets,
            prescribedReps: entry.prescribedReps.isEmpty ? nil : entry.prescribedReps,
            prescribedTargetRIR: entry.recordedTargetRIR
        )
    }

    var dedupeKey: String {
        let repText = repsCompleted.map(String.init) ?? "nil"
        return BackupDedupeKey.make(resolvedCanonicalKey, BackupDedupeKey.date(loggedAt), weightLbs, repText, notes)
    }

    func makeModel() -> ExercisePerformanceLog {
        let entry = ExercisePerformanceLog(
            loggedAt: loggedAt,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            repsCompleted: repsCompleted,
            notes: notes,
            muscleTarget: muscleTarget,
            workoutDayNumber: workoutDayNumber ?? 0,
            prescribedSets: prescribedSets ?? 0,
            prescribedReps: prescribedReps ?? "",
            prescribedTargetRIR: prescribedTargetRIR
        )
        entry.canonicalExerciseKey = resolvedCanonicalKey
        entry.setLogsJSON = setLogsJSON ?? ""
        return entry
    }
}

@MainActor private extension LegacyNutritionSnapshot {
    func makeNutritionSnapshot() -> NutritionSnapshot {
        NutritionSnapshot(
            date: date,
            mealName: mealName,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            sugarG: 0,
            fiberG: 0,
            fatG: fatG,
            notes: notes
        )
    }
}

@MainActor
final class DataBackupManager {
    static let shared = DataBackupManager()
    private init() {}
    let currentBackupVersion = BackupFormat.currentVersion
    private let supportedBackupVersions = BackupFormat.supportedVersions

    /// Set when the app falls back to an ephemeral in-memory store, so an empty
    /// store can't overwrite the last good on-disk backup.
    var suppressAutomaticBackups = false

    func exportDocument(using modelContext: ModelContext) throws -> BackupDocument {
        let payload = try buildPayload(using: modelContext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return BackupDocument(data: data)
    }

    /// Merges a backup into the store. Records are added and de-duplicated; nothing logged is
    /// deleted.
    ///
    /// - Parameter replaceSettings: whether the backup's profile, injury note, medical answers,
    ///   targets and theme REPLACE the ones on this phone, and whether a saved food the phone
    ///   already has takes the backup's numbers. Off, nothing already on the phone changes.
    ///   The owner chooses this explicitly in Settings. The automatic restores always pass
    ///   false: settings live outside the database and survive the store failures those
    ///   restores exist for, so applying a backup's older settings there could only replace
    ///   newer ones, such as an injury note updated after that backup was written (bug audit
    ///   2026-11-17, F3).
    func importBackup(from data: Data, into modelContext: ModelContext, replaceSettings: Bool) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: TransformBackupPayload
        if let decoded = try? decoder.decode(TransformBackupPayload.self, from: data) {
            payload = decoded
        } else if let legacy = try? decoder.decode(LegacyTransformBackupPayload.self, from: data) {
            payload = migrateLegacyPayload(legacy)
        } else {
            throw BackupError.parseError("Unsupported or corrupt backup format.")
        }

        guard supportedBackupVersions.contains(payload.version) else {
            throw BackupError.unsupportedVersion(payload.version)
        }

        let originalAutosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = originalAutosave }

        do {
            try modelContext.transaction {
                try merge(payload: payload, into: modelContext, replaceSettings: replaceSettings)
            }
            SleepTrendStore.refresh(using: modelContext)
            writeAutomaticBackup(using: modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Coalesced variant for high-frequency in-workout writes (set logging, completion
    /// toggles). The SwiftData save is already durable; the automatic backup is a full
    /// export (photos + all data) and must not run once per tap. The scene-phase hook in
    /// ContentView still writes a fresh backup whenever the app backgrounds, so the
    /// recovery snapshot never lags a finished session.
    private var lastCoalescedBackupAt: Date?
    private static let coalescedBackupMinInterval: TimeInterval = 45
    private var pendingAutomaticBackupTask: Task<Void, Never>?
    private static let scheduledBackupDebounceNanoseconds: UInt64 = 1_500_000_000

    func writeAutomaticBackupCoalesced(using modelContext: ModelContext) {
        let now = Date()
        if let last = lastCoalescedBackupAt,
           now.timeIntervalSince(last) < Self.coalescedBackupMinInterval {
            return
        }
        lastCoalescedBackupAt = now
        writeAutomaticBackup(using: modelContext)
    }

    func writeAutomaticBackup(using modelContext: ModelContext) {
        pendingAutomaticBackupTask?.cancel()
        pendingAutomaticBackupTask = nil
        guard !suppressAutomaticBackups else { return }
        do {
            let document = try exportDocument(using: modelContext)
            let counts = try? entryCounts(using: modelContext)
            if let counts, let lastKnown = loadLastKnownCounts() {
                if counts.hasSignificantDrop(comparedTo: lastKnown) {
                    print("[Backup] Skipping auto-backup: significant data drop detected. Previous: \(lastKnown.debugSummary) Current: \(counts.debugSummary) Drop: \(counts.dropSummary(comparedTo: lastKnown)). Preserving existing backups.")
                    return
                }
            }

            rotateBackups()
            let url = automaticBackupURL(slot: 0)
            // The backup contains body photos and health/medical PII. Encrypt it at
            // rest with file protection so it is unreadable while the device is locked.
            try document.data.write(to: url, options: [.atomic, .completeFileProtection])

            if let counts {
                saveLastKnownCounts(counts)
            }
        } catch {
            print("[Backup] Automatic backup failed: \(error.localizedDescription)")
        }
    }

    /// Merges the last automatic backup (if any) into the given context. Used to
    /// recover user data when the persistent store fails to initialize and the app
    /// falls back to an in-memory store, so a storage failure isn't silent total
    /// data loss. The merge is additive and dedupe-guarded, so this is safe even if
    /// the target store already holds data. Returns true if a backup was applied.
    @discardableResult
    func restoreFromAutomaticBackupIfAvailable(into modelContext: ModelContext) -> Bool {
        let url = automaticBackupURL(slot: 0)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return false
        }
        do {
            try importBackup(from: data, into: modelContext, replaceSettings: false)
            return true
        } catch {
            print("[Backup] Automatic backup restore failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Modification date of the newest automatic backup, for the dashboard's
    /// backup-status indicator and the Settings backup section. Read-only;
    /// never touches the backup contents or the drop guard.
    var lastAutomaticBackupDate: Date? {
        let url = automaticBackupURL(slot: 0)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    private static let backupSlots = 3

    private func automaticBackupURL(slot: Int) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return slot == 0
            ? dir.appendingPathComponent("Transform_AutoBackup.json")
            : dir.appendingPathComponent("Transform_AutoBackup_\(slot).json")
    }

    private func rotateBackups() {
        let fm = FileManager.default
        for slot in stride(from: Self.backupSlots - 1, through: 1, by: -1) {
            let dest = automaticBackupURL(slot: slot)
            let source = automaticBackupURL(slot: slot - 1)
            try? fm.removeItem(at: dest)
            if fm.fileExists(atPath: source.path) {
                try? fm.copyItem(at: source, to: dest)
            }
        }
    }

    /// Lives in `BackupEntryCounts.swift` so the headless tests can drive the drop guard.
    typealias EntryCounts = BackupEntryCounts

    func entryCounts(using modelContext: ModelContext) throws -> EntryCounts {
        let sleep = try modelContext.fetchCount(FetchDescriptor<SleepEntry>())
        let weight = try modelContext.fetchCount(FetchDescriptor<WeightEntry>())
        let nutrition = try modelContext.fetchCount(FetchDescriptor<NutritionEntry>())
        let measurement = try modelContext.fetchCount(FetchDescriptor<MeasurementEntry>())
        let exerciseWeights = try modelContext.fetchCount(FetchDescriptor<ExerciseWeightEntry>())
        let exerciseLogs = try modelContext.fetchCount(FetchDescriptor<ExercisePerformanceLog>())
        let analyses = try modelContext.fetchCount(FetchDescriptor<BodyAnalysisSession>())
        let workouts = try modelContext.fetchCount(FetchDescriptor<WorkoutProgram>())
        let favorites = try modelContext.fetchCount(FetchDescriptor<FavoriteFood>())
        let savedNutritionProtocols = try modelContext.fetchCount(FetchDescriptor<SavedNutritionProtocol>())
        let progressPhotos = try modelContext.fetchCount(FetchDescriptor<ProgressPhoto>())

        return EntryCounts(
            sleep: sleep,
            weight: weight,
            nutrition: nutrition,
            measurement: measurement,
            exerciseWeights: exerciseWeights,
            exerciseLogs: exerciseLogs,
            analyses: analyses,
            workouts: workouts,
            favorites: favorites,
            savedNutritionProtocols: savedNutritionProtocols,
            progressPhotos: progressPhotos
        )
    }

    private static let countsKey = "transform.lastKnownEntryCounts"

    private func saveLastKnownCounts(_ counts: EntryCounts) {
        if let data = try? JSONEncoder().encode(counts) {
            UserDefaults.standard.set(data, forKey: Self.countsKey)
        }
    }

    private func loadLastKnownCounts() -> EntryCounts? {
        guard let data = UserDefaults.standard.data(forKey: Self.countsKey) else { return nil }
        return try? JSONDecoder().decode(EntryCounts.self, from: data)
    }

    /// Call after a deliberate, confirmed owner action that removed records in bulk and has
    /// already been saved (Reset Workout Day), passing the counts taken just before it.
    ///
    /// Moves both loss baselines down by exactly what the action removed
    /// (`BackupEntryCounts.acknowledgingDeliberateRemoval`), then writes the automatic backup
    /// at once. Without this the drop guard skipped that backup, and the next launch could
    /// either merge the pre-reset backup back in (undoing the reset) or warn "Data loss
    /// detected". Loss the action does not account for is still caught.
    ///
    /// The baseline is saved BEFORE the backup is attempted, so a failed write cannot leave
    /// the launch-time recovery comparing against the pre-reset count.
    ///
    /// Deliberate limit: if records had ALREADY gone missing without explanation before this
    /// action, that gap stays in the baseline, the drop guard still skips the backup, and the
    /// file on disk is still the pre-action one. If that unexplained gap exceeds the recovery
    /// threshold, the next launch merges that backup back in: the lost records return, and so
    /// do the ones this action removed. Recovering unexplained loss is judged worth that. The rotated older
    /// backups (slots 1 and 2) still hold the pre-reset data. Does nothing while the app runs
    /// on the in-memory fallback store, whose counts say nothing about the real one.
    func acknowledgeDeliberateRemoval(before: EntryCounts, using modelContext: ModelContext) {
        guard !suppressAutomaticBackups, let after = try? entryCounts(using: modelContext) else { return }
        let removed = EntryCounts.deliberateRemoval(before: before, after: after)
        if let lastKnown = loadLastKnownCounts() {
            saveLastKnownCounts(lastKnown.acknowledgingDeliberateRemoval(removed, after: after))
        }
        DataIntegrityMonitor.acknowledgeDeliberateRemoval(removed, after: after)
        writeAutomaticBackup(using: modelContext)
    }

    @MainActor
    func scheduleAutomaticBackup(using modelContext: ModelContext) {
        guard !suppressAutomaticBackups else { return }
        pendingAutomaticBackupTask?.cancel()
        pendingAutomaticBackupTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: Self.scheduledBackupDebounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            pendingAutomaticBackupTask = nil
            writeAutomaticBackup(using: modelContext)
        }
    }

    @MainActor
    func attemptAutomaticRecoveryIfNeeded(using modelContext: ModelContext) -> String? {
        guard
            let previous = loadLastKnownCounts(),
            let current = try? entryCounts(using: modelContext),
            current.shouldAttemptAutomaticRecovery(comparedTo: previous)
        else {
            return nil
        }

        guard restoreFromAutomaticBackupIfAvailable(into: modelContext) else {
            return nil
        }

        guard let recovered = try? entryCounts(using: modelContext) else {
            return "Some data was missing at launch, so Transform restored your latest automatic backup."
        }

        guard recovered.total > current.total else { return nil }

        return "Some data was missing at launch, so Transform restored \(recovered.total - current.total) entries from your latest automatic backup."
    }

    private func buildPayload(using modelContext: ModelContext) throws -> TransformBackupPayload {
        let weights = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        let sleep = try modelContext.fetch(FetchDescriptor<SleepEntry>())
        let measurements = try modelContext.fetch(FetchDescriptor<MeasurementEntry>())
        let nutrition = try modelContext.fetch(FetchDescriptor<NutritionEntry>())
        let favorites = try modelContext.fetch(FetchDescriptor<FavoriteFood>())
        let savedNutritionProtocols = try modelContext.fetch(FetchDescriptor<SavedNutritionProtocol>())
        let progressPhotos = try modelContext.fetch(FetchDescriptor<ProgressPhoto>())
        let analyses = try modelContext.fetch(FetchDescriptor<BodyAnalysisSession>())
        let workouts = try modelContext.fetch(FetchDescriptor<WorkoutProgram>())
        let exerciseWeights = try modelContext.fetch(FetchDescriptor<ExerciseWeightEntry>())
        let exercisePerformanceLogs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())

        return TransformBackupPayload(
            version: currentBackupVersion,
            exportedAt: .now,
            weights: mainActorMap(weights, WeightSnapshot.init),
            sleep: mainActorMap(sleep, SleepSnapshot.init),
            measurements: mainActorMap(measurements, MeasurementSnapshot.init),
            nutrition: mainActorMap(nutrition, NutritionSnapshot.init),
            favorites: mainActorMap(favorites, FavoriteFoodSnapshot.init),
            savedNutritionProtocols: mainActorMap(savedNutritionProtocols, SavedNutritionProtocolSnapshot.init),
            progressPhotos: mainActorMap(progressPhotos, ProgressPhotoSnapshot.init),
            analyses: mainActorMap(analyses, AnalysisSnapshot.init),
            workouts: mainActorMap(workouts) { WorkoutProgramSnapshot($0) },
            exerciseWeights: mainActorMap(exerciseWeights, ExerciseWeightSnapshot.init),
            exercisePerformanceLogs: mainActorMap(exercisePerformanceLogs, ExercisePerformanceLogSnapshot.init),
            profileSettings: ProfileSettingsSnapshot.fromUserDefaults()
        )
    }

    private func merge(payload: TransformBackupPayload, into modelContext: ModelContext, replaceSettings: Bool) throws {
        let existingWeights = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        let existingSleep = try modelContext.fetch(FetchDescriptor<SleepEntry>())
        let existingMeasurements = try modelContext.fetch(FetchDescriptor<MeasurementEntry>())
        let existingNutrition = try modelContext.fetch(FetchDescriptor<NutritionEntry>())
        let existingFavorites = try modelContext.fetch(FetchDescriptor<FavoriteFood>())
        let existingSavedNutritionProtocols = try modelContext.fetch(FetchDescriptor<SavedNutritionProtocol>())
        let existingProgressPhotos = try modelContext.fetch(FetchDescriptor<ProgressPhoto>())
        let existingAnalyses = try modelContext.fetch(FetchDescriptor<BodyAnalysisSession>())
        let existingWorkouts = try modelContext.fetch(FetchDescriptor<WorkoutProgram>())
        var existingExerciseWeights = try modelContext.fetch(FetchDescriptor<ExerciseWeightEntry>())
        let existingExercisePerformanceLogs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())

        var weightKeys = Set(mainActorMap(existingWeights) { WeightSnapshot($0).dedupeKey })
        var sleepKeys = Set(mainActorMap(existingSleep) { SleepSnapshot($0).dedupeKey })
        var measurementKeys = Set(mainActorMap(existingMeasurements) { MeasurementSnapshot($0).dedupeKey })
        var nutritionKeys = Set(mainActorMap(existingNutrition) { NutritionSnapshot($0).dedupeKey })
        var favoriteKeys = Set(mainActorMap(existingFavorites) { FavoriteFoodSnapshot($0).dedupeKey })
        var savedNutritionProtocolKeys = Set(mainActorMap(existingSavedNutritionProtocols) {
            SavedNutritionProtocolSnapshot($0).dedupeKey
        })
        var progressPhotoKeys = Set(mainActorMap(existingProgressPhotos) { ProgressPhotoSnapshot($0).dedupeKey })
        var analysisKeys = Set(mainActorMap(existingAnalyses) { AnalysisSnapshot($0).dedupeKey })
        var workoutKeys = Set(mainActorMap(existingWorkouts) { $0.id.uuidString })
        var exerciseWeightKeys = Set(mainActorMap(existingExerciseWeights) { ExerciseWeightSnapshot($0).dedupeKey })
        var exercisePerformanceLogKeys = Set(mainActorMap(existingExercisePerformanceLogs) {
            ExercisePerformanceLogSnapshot($0).dedupeKey
        })

        for item in payload.weights {
            let key = item.dedupeKey
            guard !weightKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            weightKeys.insert(key)
        }

        for item in payload.sleep ?? [] {
            let key = item.dedupeKey
            guard !sleepKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            sleepKeys.insert(key)
        }

        for item in payload.measurements {
            let key = item.dedupeKey
            guard !measurementKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            measurementKeys.insert(key)
        }

        for item in payload.nutrition {
            let key = item.dedupeKey
            guard !nutritionKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            nutritionKeys.insert(key)
        }

        for item in payload.favorites {
            let key = item.dedupeKey
            if let existing = mainActorFirst(
                in: existingFavorites,
                where: { FavoriteFoodSnapshot($0).dedupeKey == key }
            ) {
                if replaceSettings { item.apply(to: existing) }
            } else if !favoriteKeys.contains(key) {
                modelContext.insert(item.makeModel())
                favoriteKeys.insert(key)
            }
        }

        for item in payload.savedNutritionProtocols ?? [] {
            let key = item.dedupeKey
            guard !savedNutritionProtocolKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            savedNutritionProtocolKeys.insert(key)
        }

        for item in payload.progressPhotos ?? [] {
            let key = item.dedupeKey
            guard !progressPhotoKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            progressPhotoKeys.insert(key)
        }

        for item in payload.analyses {
            let key = item.dedupeKey
            guard !analysisKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            analysisKeys.insert(key)
        }

        for item in payload.workouts {
            guard !workoutKeys.contains(item.id.uuidString) else { continue }
            let program = item.makeModel()
            modelContext.insert(program)
            workoutKeys.insert(item.id.uuidString)
        }

        for item in payload.exerciseWeights ?? [] {
            let key = item.dedupeKey
            if let existing = mainActorFirst(
                in: existingExerciseWeights,
                where: { ExerciseWeightSnapshot($0).dedupeKey == key }
            ) {
                item.merge(into: existing)
                exerciseWeightKeys.insert(key)
                continue
            }

            let created = item.makeModel()
            modelContext.insert(created)
            existingExerciseWeights.append(created)
            exerciseWeightKeys.insert(key)
        }

        for item in payload.exercisePerformanceLogs ?? [] {
            let key = item.dedupeKey
            guard !exercisePerformanceLogKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            exercisePerformanceLogKeys.insert(key)
        }

        _ = try ExerciseWeightStore.normalizeAndConsolidate(in: modelContext)

        if replaceSettings {
            payload.profileSettings?.applyToUserDefaults()
        }
    }

    private func migrateLegacyPayload(_ legacy: LegacyTransformBackupPayload) -> TransformBackupPayload {
        TransformBackupPayload(
            version: 1,
            exportedAt: .now,
            weights: legacy.weights,
            sleep: nil,
            measurements: legacy.measurements,
            nutrition: mainActorMap(legacy.nutrition) { $0.makeNutritionSnapshot() },
            favorites: [],
            savedNutritionProtocols: nil,
            progressPhotos: nil,
            analyses: legacy.analyses,
            workouts: legacy.workouts,
            exerciseWeights: [],
            exercisePerformanceLogs: []
        )
    }
}

nonisolated enum BackupError: LocalizedError {
    case parseError(String)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .parseError(let message):
            return message
        case .unsupportedVersion(let version):
            if version > BackupFormat.currentVersion {
                return "This backup is from a newer version of Transform. Update the app before importing it so no data is lost."
            }
            return "Unsupported backup version \(version)."
        }
    }
}
