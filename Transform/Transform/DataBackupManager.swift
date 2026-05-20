import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

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

struct TransformBackupPayload: Codable {
    let version: Int
    let exportedAt: Date
    let weights: [WeightSnapshot]
    let measurements: [MeasurementSnapshot]
    let nutrition: [NutritionSnapshot]
    let favorites: [FavoriteFoodSnapshot]
    let savedNutritionProtocols: [SavedNutritionProtocolSnapshot]?
    let analyses: [AnalysisSnapshot]
    let workouts: [WorkoutProgramSnapshot]
    let exerciseWeights: [ExerciseWeightSnapshot]?
    let exercisePerformanceLogs: [ExercisePerformanceLogSnapshot]?

    init(
        version: Int,
        exportedAt: Date,
        weights: [WeightSnapshot],
        measurements: [MeasurementSnapshot],
        nutrition: [NutritionSnapshot],
        favorites: [FavoriteFoodSnapshot],
        savedNutritionProtocols: [SavedNutritionProtocolSnapshot]?,
        analyses: [AnalysisSnapshot],
        workouts: [WorkoutProgramSnapshot],
        exerciseWeights: [ExerciseWeightSnapshot]?,
        exercisePerformanceLogs: [ExercisePerformanceLogSnapshot]?
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.weights = weights
        self.measurements = measurements
        self.nutrition = nutrition
        self.favorites = favorites
        self.savedNutritionProtocols = savedNutritionProtocols
        self.analyses = analyses
        self.workouts = workouts
        self.exerciseWeights = exerciseWeights
        self.exercisePerformanceLogs = exercisePerformanceLogs
    }
}

// Legacy backup shape (before sugar/fiber/favorites fields were introduced).
struct LegacyTransformBackupPayload: Codable {
    let weights: [WeightSnapshot]
    let measurements: [MeasurementSnapshot]
    let nutrition: [LegacyNutritionSnapshot]
    let analyses: [AnalysisSnapshot]
    let workouts: [WorkoutProgramSnapshot]
}

struct LegacyNutritionSnapshot: Codable {
    let date: Date
    let mealName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let notes: String
}

struct WeightSnapshot: Codable {
    let date: Date
    let weightLbs: Double
    let notes: String
}

struct MeasurementSnapshot: Codable {
    let date: Date
    let chestIn: Double?
    let waistIn: Double?
    let hipsIn: Double?
    let neckIn: Double?
    let leftArmIn: Double?
    let rightArmIn: Double?
    let leftThighIn: Double?
    let rightThighIn: Double?
    let bodyFatPct: Double?
    let notes: String
}

struct NutritionSnapshot: Codable {
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

struct FavoriteFoodSnapshot: Codable {
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

struct SavedNutritionProtocolSnapshot: Codable {
    let createdAt: Date
    let updatedAt: Date
    let programJSON: String
    let followupWeeksJSON: String
}

struct AnalysisSnapshot: Codable {
    let date: Date
    let photoData: Data
    let pose: String
    let analysisJSON: String
    let photoCount: Int
    let analysisResult: String
    let priorityMuscles: String
    let dietRecommendation: String
}

struct WorkoutProgramSnapshot: Codable {
    let id: UUID
    let createdDate: Date
    let programName: String
    let programSummary: String
    let splitType: String
    let daysPerWeek: Int
    let totalDays: Int
    let focusAreas: String
    let sourceAnalysisDate: Date?
    let programJSON: String
    let currentWeek: Int
    let maxWeeks: Int
    let analysisJSON: String
    let days: [WorkoutDaySnapshot]
}

struct WorkoutDaySnapshot: Codable {
    let dayNumber: Int
    let dayName: String
    let muscleGroups: String
    let isRestDay: Bool
    let notes: String
    let isCompleted: Bool
    let exercises: [WorkoutExerciseSnapshot]
}

struct WorkoutExerciseSnapshot: Codable {
    let order: Int
    let exerciseName: String
    let sets: Int
    let reps: String
    let tempo: String?
    let restSeconds: Int
    let notes: String
    let muscleTarget: String
    let isCompleted: Bool
}

struct ExerciseWeightSnapshot: Codable {
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

struct ExercisePerformanceLogSnapshot: Codable {
    let loggedAt: Date
    let exerciseName: String
    let weightLbs: Double
    let repsCompleted: Int?
    let notes: String
    let muscleTarget: String
    let canonicalExerciseKey: String?
}

private extension WeightSnapshot {
    init(_ entry: WeightEntry) {
        self.init(date: entry.date, weightLbs: entry.weightLbs, notes: entry.notes)
    }

    var dedupeKey: String {
        "\(date.timeIntervalSince1970)-\(weightLbs)-\(notes)"
    }

    func makeModel() -> WeightEntry {
        WeightEntry(date: date, weightLbs: weightLbs, notes: notes)
    }
}

private extension MeasurementSnapshot {
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
            bodyFatPct: entry.bodyFatPct,
            notes: entry.notes
        )
    }

    var dedupeKey: String {
        "\(date.timeIntervalSince1970)-\(waistIn ?? -1)-\(chestIn ?? -1)-\(notes)"
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
        entry.bodyFatPct = bodyFatPct
        entry.notes = notes
        return entry
    }
}

private extension NutritionSnapshot {
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
        "\(date.timeIntervalSince1970)-\(mealName)-\(notes)-\(calories)-\(carbsG)-\(proteinG)-\(fatG)"
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

private extension FavoriteFoodSnapshot {
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
        "\(mealName)-\(name.lowercased())"
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

private extension SavedNutritionProtocolSnapshot {
    init(_ protocolModel: SavedNutritionProtocol) {
        self.init(
            createdAt: protocolModel.createdAt,
            updatedAt: protocolModel.updatedAt,
            programJSON: protocolModel.programJSON,
            followupWeeksJSON: protocolModel.followupWeeksJSON
        )
    }

    var dedupeKey: String {
        "\(createdAt.timeIntervalSince1970)-\(programJSON)-\(followupWeeksJSON)"
    }

    func makeModel() -> SavedNutritionProtocol {
        SavedNutritionProtocol(
            createdAt: createdAt,
            updatedAt: updatedAt,
            programJSON: programJSON,
            followupWeeksJSON: followupWeeksJSON
        )
    }
}

private extension AnalysisSnapshot {
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
        "\(date.timeIntervalSince1970)-\(pose)-\(photoCount)-\(analysisResult)"
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

private extension WorkoutExerciseSnapshot {
    init(_ exercise: WorkoutExercise) {
        self.init(
            order: exercise.order,
            exerciseName: exercise.exerciseName,
            sets: exercise.sets,
            reps: exercise.reps,
            tempo: exercise.tempo,
            restSeconds: exercise.restSeconds,
            notes: exercise.notes,
            muscleTarget: exercise.muscleTarget,
            isCompleted: exercise.isCompleted
        )
    }

    func makeModel() -> WorkoutExercise {
        let exercise = WorkoutExercise(
            order: order,
            exerciseName: exerciseName,
            sets: sets,
            reps: reps,
            tempo: tempo ?? "",
            restSeconds: restSeconds,
            notes: notes,
            muscleTarget: muscleTarget
        )
        exercise.isCompleted = isCompleted
        return exercise
    }
}

private extension WorkoutDaySnapshot {
    init(_ day: WorkoutDay) {
        self.init(
            dayNumber: day.dayNumber,
            dayName: day.dayName,
            muscleGroups: day.muscleGroups,
            isRestDay: day.isRestDay,
            notes: day.notes,
            isCompleted: day.isCompleted,
            exercises: day.sortedExercises.map(WorkoutExerciseSnapshot.init)
        )
    }

    func makeModel() -> WorkoutDay {
        let day = WorkoutDay(
            dayNumber: dayNumber,
            dayName: dayName,
            muscleGroups: muscleGroups,
            isRestDay: isRestDay,
            notes: notes
        )
        day.isCompleted = isCompleted

        for exerciseSnapshot in exercises {
            let exercise = exerciseSnapshot.makeModel()
            exercise.day = day
            day.exercises.append(exercise)
        }

        return day
    }
}

private extension WorkoutProgramSnapshot {
    init(_ program: WorkoutProgram) {
        self.init(
            id: program.id,
            createdDate: program.createdDate,
            programName: program.programName,
            programSummary: program.programSummary,
            splitType: program.splitType,
            daysPerWeek: program.daysPerWeek,
            totalDays: program.totalDays,
            focusAreas: program.focusAreas,
            sourceAnalysisDate: program.sourceAnalysisDate,
            programJSON: program.programJSON,
            currentWeek: program.currentWeek,
            maxWeeks: program.maxWeeks,
            analysisJSON: program.analysisJSON,
            days: program.sortedDays.map(WorkoutDaySnapshot.init)
        )
    }

    func makeModel() -> WorkoutProgram {
        let program = WorkoutProgram(
            programName: programName,
            programSummary: programSummary,
            splitType: splitType,
            daysPerWeek: daysPerWeek,
            totalDays: totalDays,
            focusAreas: focusAreas,
            sourceAnalysisDate: sourceAnalysisDate,
            programJSON: programJSON,
            currentWeek: currentWeek,
            maxWeeks: maxWeeks,
            analysisJSON: analysisJSON
        )
        program.id = id
        program.createdDate = createdDate

        for daySnapshot in days {
            let day = daySnapshot.makeModel()
            day.program = program
            program.days.append(day)
        }

        return program
    }
}

private extension ExerciseWeightSnapshot {
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

private extension ExercisePerformanceLogSnapshot {
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
            canonicalExerciseKey: entry.canonicalExerciseKey
        )
    }

    var dedupeKey: String {
        let repText = repsCompleted.map(String.init) ?? "nil"
        return "\(resolvedCanonicalKey)-\(loggedAt.timeIntervalSince1970)-\(weightLbs)-\(repText)-\(notes)"
    }

    func makeModel() -> ExercisePerformanceLog {
        let entry = ExercisePerformanceLog(
            loggedAt: loggedAt,
            exerciseName: exerciseName,
            weightLbs: weightLbs,
            repsCompleted: repsCompleted,
            notes: notes,
            muscleTarget: muscleTarget
        )
        entry.canonicalExerciseKey = resolvedCanonicalKey
        return entry
    }
}

private extension LegacyNutritionSnapshot {
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

final class DataBackupManager {
    static let shared = DataBackupManager()
    private init() {}
    let currentBackupVersion = 4
    private let supportedBackupVersions: Set<Int> = [1, 2, 3, 4]

    func exportDocument(using modelContext: ModelContext) throws -> BackupDocument {
        let payload = try buildPayload(using: modelContext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        return BackupDocument(data: data)
    }

    func importBackup(from data: Data, into modelContext: ModelContext) throws {
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
                try merge(payload: payload, into: modelContext)
            }
            writeAutomaticBackup(using: modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func writeAutomaticBackup(using modelContext: ModelContext) {
        do {
            let document = try exportDocument(using: modelContext)
            let url = automaticBackupURL()
            try document.data.write(to: url, options: [.atomic])
        } catch {
            // Keep backup writes best-effort and non-blocking.
            print("[Backup] Automatic backup failed: \(error.localizedDescription)")
        }
    }

    private func buildPayload(using modelContext: ModelContext) throws -> TransformBackupPayload {
        let weights = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        let measurements = try modelContext.fetch(FetchDescriptor<MeasurementEntry>())
        let nutrition = try modelContext.fetch(FetchDescriptor<NutritionEntry>())
        let favorites = try modelContext.fetch(FetchDescriptor<FavoriteFood>())
        let savedNutritionProtocols = try modelContext.fetch(FetchDescriptor<SavedNutritionProtocol>())
        let analyses = try modelContext.fetch(FetchDescriptor<BodyAnalysisSession>())
        let workouts = try modelContext.fetch(FetchDescriptor<WorkoutProgram>())
        let exerciseWeights = try modelContext.fetch(FetchDescriptor<ExerciseWeightEntry>())
        let exercisePerformanceLogs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())

        return TransformBackupPayload(
            version: currentBackupVersion,
            exportedAt: .now,
            weights: weights.map(WeightSnapshot.init),
            measurements: measurements.map(MeasurementSnapshot.init),
            nutrition: nutrition.map(NutritionSnapshot.init),
            favorites: favorites.map(FavoriteFoodSnapshot.init),
            savedNutritionProtocols: savedNutritionProtocols.map(SavedNutritionProtocolSnapshot.init),
            analyses: analyses.map(AnalysisSnapshot.init),
            workouts: workouts.map(WorkoutProgramSnapshot.init),
            exerciseWeights: exerciseWeights.map(ExerciseWeightSnapshot.init),
            exercisePerformanceLogs: exercisePerformanceLogs.map(ExercisePerformanceLogSnapshot.init)
        )
    }

    private func merge(payload: TransformBackupPayload, into modelContext: ModelContext) throws {
        let existingWeights = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        let existingMeasurements = try modelContext.fetch(FetchDescriptor<MeasurementEntry>())
        let existingNutrition = try modelContext.fetch(FetchDescriptor<NutritionEntry>())
        let existingFavorites = try modelContext.fetch(FetchDescriptor<FavoriteFood>())
        let existingSavedNutritionProtocols = try modelContext.fetch(FetchDescriptor<SavedNutritionProtocol>())
        let existingAnalyses = try modelContext.fetch(FetchDescriptor<BodyAnalysisSession>())
        let existingWorkouts = try modelContext.fetch(FetchDescriptor<WorkoutProgram>())
        var existingExerciseWeights = try modelContext.fetch(FetchDescriptor<ExerciseWeightEntry>())
        let existingExercisePerformanceLogs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())

        var weightKeys = Set(existingWeights.map { WeightSnapshot($0).dedupeKey })
        var measurementKeys = Set(existingMeasurements.map { MeasurementSnapshot($0).dedupeKey })
        var nutritionKeys = Set(existingNutrition.map { NutritionSnapshot($0).dedupeKey })
        var favoriteKeys = Set(existingFavorites.map { FavoriteFoodSnapshot($0).dedupeKey })
        var savedNutritionProtocolKeys = Set(existingSavedNutritionProtocols.map {
            SavedNutritionProtocolSnapshot($0).dedupeKey
        })
        var analysisKeys = Set(existingAnalyses.map { AnalysisSnapshot($0).dedupeKey })
        var workoutKeys = Set(existingWorkouts.map { $0.id.uuidString })
        var exerciseWeightKeys = Set(existingExerciseWeights.map { ExerciseWeightSnapshot($0).dedupeKey })
        var exercisePerformanceLogKeys = Set(existingExercisePerformanceLogs.map { ExercisePerformanceLogSnapshot($0).dedupeKey })

        for item in payload.weights {
            let key = item.dedupeKey
            guard !weightKeys.contains(key) else { continue }
            modelContext.insert(item.makeModel())
            weightKeys.insert(key)
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
            if let existing = existingFavorites.first(where: { FavoriteFoodSnapshot($0).dedupeKey == key }) {
                item.apply(to: existing)
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
            if let existing = existingExerciseWeights.first(where: { ExerciseWeightSnapshot($0).dedupeKey == key }) {
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
    }

    private func migrateLegacyPayload(_ legacy: LegacyTransformBackupPayload) -> TransformBackupPayload {
        TransformBackupPayload(
            version: 1,
            exportedAt: .now,
            weights: legacy.weights,
            measurements: legacy.measurements,
            nutrition: legacy.nutrition.map { $0.makeNutritionSnapshot() },
            favorites: [],
            savedNutritionProtocols: nil,
            analyses: legacy.analyses,
            workouts: legacy.workouts,
            exerciseWeights: [],
            exercisePerformanceLogs: []
        )
    }

    private func automaticBackupURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("Transform_AutoBackup.json")
    }
}

enum BackupError: LocalizedError {
    case parseError(String)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .parseError(let message):
            return message
        case .unsupportedVersion(let version):
            if version > DataBackupManager.shared.currentBackupVersion {
                return "This backup was created by a newer app version (backup format \(version)). Update Transform before importing to avoid data loss."
            }
            return "Unsupported backup version \(version)."
        }
    }
}
