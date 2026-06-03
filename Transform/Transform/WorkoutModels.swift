import SwiftUI
import SwiftData
import Foundation

// MARK: - Workout Program (weekly progressive container)

@Model
class WorkoutProgram {
    var id: UUID
    var createdDate: Date
    var programName: String = ""
    var programSummary: String = ""
    var splitType: String = ""
    var daysPerWeek: Int = 5
    var totalDays: Int = 7
    var focusAreas: String = ""
    var sourceAnalysisDate: Date?
    var programJSON: String = ""
    var currentWeek: Int = 1
    var maxWeeks: Int = 4
    var analysisJSON: String = ""
    var validatorWarnings: String = ""
    var lastGenerationBundle: String = ""

    @Relationship(deleteRule: .cascade, inverse: \WorkoutDay.program)
    var days: [WorkoutDay] = []

    init(
        programName: String,
        programSummary: String,
        splitType: String,
        daysPerWeek: Int,
        totalDays: Int = 7,
        focusAreas: String,
        sourceAnalysisDate: Date? = nil,
        programJSON: String = "",
        currentWeek: Int = 1,
        maxWeeks: Int = 4,
        analysisJSON: String = "",
        validatorWarnings: String = "",
        lastGenerationBundle: String = ""
    ) {
        self.id = UUID()
        self.createdDate = .now
        self.programName = programName
        self.programSummary = programSummary
        self.splitType = splitType
        self.daysPerWeek = daysPerWeek
        self.totalDays = totalDays
        self.focusAreas = focusAreas
        self.sourceAnalysisDate = sourceAnalysisDate
        self.programJSON = programJSON
        self.currentWeek = currentWeek
        self.maxWeeks = maxWeeks
        self.analysisJSON = analysisJSON
        self.validatorWarnings = validatorWarnings
        self.lastGenerationBundle = lastGenerationBundle
    }

    var sortedDays: [WorkoutDay] {
        days.sorted { $0.dayNumber < $1.dayNumber }
    }

    var canGenerateNextWeek: Bool {
        currentWeek < maxWeeks
    }

    var latestWeekDays: [WorkoutDay] {
        sortedDays.filter { $0.weekNumber == currentWeek }
    }
}

// MARK: - Workout Day

@Model
class WorkoutDay {
    var dayNumber: Int = 1
    var dayName: String = ""
    var muscleGroups: String = ""
    var isRestDay: Bool = false
    var notes: String = ""
    var isCompleted: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.day)
    var exercises: [WorkoutExercise] = []

    var program: WorkoutProgram?

    init(
        dayNumber: Int,
        dayName: String,
        muscleGroups: String,
        isRestDay: Bool = false,
        notes: String = ""
    ) {
        self.dayNumber = dayNumber
        self.dayName = dayName
        self.muscleGroups = muscleGroups
        self.isRestDay = isRestDay
        self.notes = notes
        self.isCompleted = false
    }

    var sortedExercises: [WorkoutExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var weekNumber: Int {
        ((dayNumber - 1) / 7) + 1
    }
}

// MARK: - Workout Exercise

@Model
class WorkoutExercise {
    var order: Int = 0
    var exerciseName: String = ""
    var sets: Int = 0
    var reps: String = ""
    var tempo: String = ""
    var restSeconds: Int = 90
    var notes: String = ""
    var muscleTarget: String = ""
    var isCompleted: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \ExerciseWeightEntry.exercise)
    var weightLogs: [ExerciseWeightEntry] = []

    var day: WorkoutDay?

    init(
        order: Int,
        exerciseName: String,
        sets: Int,
        reps: String,
        tempo: String = "",
        restSeconds: Int = 90,
        notes: String = "",
        muscleTarget: String = ""
    ) {
        self.order = order
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.tempo = tempo
        self.restSeconds = restSeconds
        self.notes = notes
        self.muscleTarget = muscleTarget
        self.isCompleted = false
    }
}

// MARK: - Logged Exercise Weight (for progression tracking)

@Model
class ExerciseWeightEntry {
    var loggedAt: Date
    var exerciseName: String = ""
    var normalizedExerciseName: String = ""
    var canonicalExerciseKey: String = ""
    var weightLbs: Double = 0
    var repsCompleted: Int?
    var notes: String = ""
    var bestWeightLbs: Double = 0
    var bestLoggedAt: Date?
    var bestRepsCompleted: Int?
    var bestNotes: String = ""

    // Legacy relationship retained for schema compatibility. Weight summaries are
    // now resolved globally by canonical exercise key instead of belonging to a
    // single workout instance.
    var exercise: WorkoutExercise?

    init(
        loggedAt: Date = .now,
        exerciseName: String,
        weightLbs: Double,
        repsCompleted: Int? = nil,
        notes: String = ""
    ) {
        self.loggedAt = loggedAt
        self.exerciseName = exerciseName
        self.normalizedExerciseName = ExerciseWeightEntry.normalize(exerciseName)
        self.canonicalExerciseKey = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        self.weightLbs = weightLbs
        self.repsCompleted = repsCompleted
        self.notes = notes
        self.bestWeightLbs = weightLbs
        self.bestLoggedAt = loggedAt
        self.bestRepsCompleted = repsCompleted
        self.bestNotes = notes
    }

    var hasBestRecord: Bool {
        bestWeightLbs > 0
    }

    func applyLog(
        loggedAt: Date,
        exerciseName: String,
        weightLbs: Double,
        repsCompleted: Int?,
        notes: String
    ) {
        self.loggedAt = loggedAt
        self.exerciseName = exerciseName
        self.normalizedExerciseName = ExerciseWeightEntry.normalize(exerciseName)
        self.canonicalExerciseKey = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        self.weightLbs = weightLbs
        self.repsCompleted = repsCompleted
        self.notes = notes

        let shouldReplaceBest: Bool
        if !hasBestRecord {
            shouldReplaceBest = true
        } else if weightLbs > bestWeightLbs + 0.001 {
            shouldReplaceBest = true
        } else if abs(weightLbs - bestWeightLbs) <= 0.001 {
            shouldReplaceBest = (bestLoggedAt ?? .distantPast) <= loggedAt
        } else {
            shouldReplaceBest = false
        }

        if shouldReplaceBest {
            bestWeightLbs = weightLbs
            bestLoggedAt = loggedAt
            bestRepsCompleted = repsCompleted
            bestNotes = notes
        }
    }

    static func normalize(_ exerciseName: String) -> String {
        exerciseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    static func canonicalLookupKey(_ exerciseName: String) -> String {
        let lowered = exerciseName
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let normalizedCharacters = lowered.map { character -> Character in
            if character.isLetter || character.isNumber || character.isWhitespace {
                return character
            }
            return " "
        }

        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "with", "for", "to",
            "week", "day", "set", "sets", "rep", "reps", "rir", "rpe"
        ]

        let normalizedText = String(normalizedCharacters)
        let tokens = normalizedText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .map { token in
                if token.hasSuffix("s"), token.count > 3 {
                    return String(token.dropLast())
                }
                return token
            }
            .filter { token in
                !token.isEmpty && !stopWords.contains(token)
            }

        if tokens.isEmpty {
            return normalize(exerciseName)
        }

        return tokens.sorted().joined(separator: " ")
    }
}

@Model
class ExercisePerformanceLog {
    var loggedAt: Date
    var exerciseName: String = ""
    var normalizedExerciseName: String = ""
    var canonicalExerciseKey: String = ""
    var weightLbs: Double = 0
    var repsCompleted: Int?
    var notes: String = ""
    var muscleTarget: String = ""

    init(
        loggedAt: Date = .now,
        exerciseName: String,
        weightLbs: Double,
        repsCompleted: Int? = nil,
        notes: String = "",
        muscleTarget: String = ""
    ) {
        self.loggedAt = loggedAt
        self.exerciseName = exerciseName
        self.normalizedExerciseName = ExerciseWeightEntry.normalize(exerciseName)
        self.canonicalExerciseKey = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        self.weightLbs = weightLbs
        self.repsCompleted = repsCompleted
        self.notes = notes
        self.muscleTarget = muscleTarget
    }
}

enum ExerciseWeightStore {
    @discardableResult
    static func normalizeAndConsolidate(in modelContext: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<ExerciseWeightEntry>()
        let fetched = try modelContext.fetch(descriptor)
        guard !fetched.isEmpty else {
            return false
        }

        var changed = false
        let grouped = Dictionary(grouping: fetched) { entry in
            ExerciseWeightEntry.canonicalLookupKey(entry.exerciseName)
        }

        for (canonicalKey, entries) in grouped {
            let latestEntry = entries.max {
                lhs, rhs in
                lhs.loggedAt < rhs.loggedAt
            } ?? entries[0]

            let bestRecord = entries
                .map(bestRecord(from:))
                .max(by: compareBestRecords)
                ?? bestRecord(from: latestEntry)

            let survivor = latestEntry
            let desiredBestNotes = bestRecord.notes ?? ""

            if survivor.canonicalExerciseKey != canonicalKey {
                survivor.canonicalExerciseKey = canonicalKey
                changed = true
            }
            let normalizedLatestName = ExerciseWeightEntry.normalize(latestEntry.exerciseName)
            if survivor.normalizedExerciseName != normalizedLatestName {
                survivor.normalizedExerciseName = normalizedLatestName
                changed = true
            }
            if survivor.bestWeightLbs != bestRecord.weightLbs {
                survivor.bestWeightLbs = bestRecord.weightLbs
                changed = true
            }
            if survivor.bestLoggedAt != bestRecord.loggedAt {
                survivor.bestLoggedAt = bestRecord.loggedAt
                changed = true
            }
            if survivor.bestRepsCompleted != bestRecord.repsCompleted {
                survivor.bestRepsCompleted = bestRecord.repsCompleted
                changed = true
            }
            if survivor.bestNotes != desiredBestNotes {
                survivor.bestNotes = desiredBestNotes
                changed = true
            }
            if survivor.exercise != nil {
                survivor.exercise = nil
                changed = true
            }

            for duplicate in entries where duplicate !== survivor {
                modelContext.delete(duplicate)
                changed = true
            }
        }

        return changed
    }

    static func summary(for exercise: WorkoutExercise, within entries: [ExerciseWeightEntry]) -> ExerciseWeightEntry? {
        let canonicalKey = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)

        let exactMatches = entries.filter { $0.canonicalExerciseKey == canonicalKey }
        if let match = exactMatches.max(by: { $0.loggedAt < $1.loggedAt }) {
            return match
        }

        let normalizedName = ExerciseWeightEntry.normalize(exercise.exerciseName)
        let legacyMatches = entries.filter { $0.normalizedExerciseName == normalizedName }
        if let match = legacyMatches.max(by: { $0.loggedAt < $1.loggedAt }) {
            return match
        }
        return nil
    }

    private struct BestRecord {
        let weightLbs: Double
        let loggedAt: Date?
        let repsCompleted: Int?
        let notes: String?
    }

    private static func bestRecord(from entry: ExerciseWeightEntry) -> BestRecord {
        if entry.hasBestRecord {
            return BestRecord(
                weightLbs: entry.bestWeightLbs,
                loggedAt: entry.bestLoggedAt,
                repsCompleted: entry.bestRepsCompleted,
                notes: entry.bestNotes
            )
        }

        return BestRecord(
            weightLbs: entry.weightLbs,
            loggedAt: entry.loggedAt,
            repsCompleted: entry.repsCompleted,
            notes: entry.notes
        )
    }

    private static func compareBestRecords(_ lhs: BestRecord, _ rhs: BestRecord) -> Bool {
        if lhs.weightLbs != rhs.weightLbs {
            return lhs.weightLbs < rhs.weightLbs
        }
        return (lhs.loggedAt ?? .distantPast) < (rhs.loggedAt ?? .distantPast)
    }
}

// MARK: - Generation Result Wrappers

struct WorkoutProgramGenerationResult {
    let response: WorkoutProgramResponse
    let validatorWarnings: [String]
    let bundleText: String
}

struct WorkoutWeekGenerationResult {
    let response: WorkoutWeekResponse
    let validatorWarnings: [String]
    let bundleText: String
}

// MARK: - JSON Codable Structs for API Response Parsing

struct WorkoutProgramResponse: Codable {
    let programName: String
    let programSummary: String
    let splitType: String
    let daysPerWeek: Int
    let days: [WorkoutDayResponse]

    init(
        programName: String,
        programSummary: String,
        splitType: String,
        daysPerWeek: Int,
        days: [WorkoutDayResponse]
    ) {
        self.programName = programName
        self.programSummary = programSummary
        self.splitType = splitType
        self.daysPerWeek = daysPerWeek
        self.days = days
    }

    private enum CodingKeys: String, CodingKey {
        case programName
        case programSummary
        case splitType
        case daysPerWeek
        case days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDays = container.decodeFlexibleArray(WorkoutDayResponse.self, forKey: .days)

        let trainingDayCount = decodedDays.filter { !$0.isRestDay }.count
        let fallbackDaysPerWeek = trainingDayCount > 0 ? trainingDayCount : 5

        self.programName = container.decodeFlexibleString(
            forKey: .programName,
            default: "Custom 4-Week Program"
        )
        self.programSummary = container.decodeFlexibleString(
            forKey: .programSummary,
            default: "Progressive 4-week hypertrophy mesocycle."
        )
        self.splitType = container.decodeFlexibleString(
            forKey: .splitType,
            default: "Custom Split"
        )
        self.daysPerWeek = container.decodeFlexibleInt(
            forKey: .daysPerWeek,
            default: fallbackDaysPerWeek,
            minimum: 1
        )
        self.days = decodedDays
    }
}

struct WorkoutDayResponse: Codable {
    let dayNumber: Int
    let dayName: String
    let muscleGroups: String
    let isRestDay: Bool
    let notes: String
    let exercises: [WorkoutExerciseResponse]

    init(
        dayNumber: Int,
        dayName: String,
        muscleGroups: String,
        isRestDay: Bool,
        notes: String,
        exercises: [WorkoutExerciseResponse]
    ) {
        self.dayNumber = dayNumber
        self.dayName = dayName
        self.muscleGroups = muscleGroups
        self.isRestDay = isRestDay
        self.notes = notes
        self.exercises = exercises
    }

    private enum CodingKeys: String, CodingKey {
        case dayNumber
        case dayName
        case muscleGroups
        case isRestDay
        case notes
        case exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let parsedExercises = container.decodeFlexibleArray(WorkoutExerciseResponse.self, forKey: .exercises)

        let parsedDayNumber = container.decodeFlexibleInt(forKey: .dayNumber, default: 1, minimum: 1)
        let explicitRest = container.decodeFlexibleBool(forKey: .isRestDay)
        let resolvedRestDay = explicitRest ?? parsedExercises.isEmpty

        self.dayNumber = parsedDayNumber
        self.dayName = container.decodeFlexibleString(forKey: .dayName, default: "Day \(parsedDayNumber)")
        self.muscleGroups = container.decodeFlexibleString(
            forKey: .muscleGroups,
            default: resolvedRestDay ? "Recovery" : "Primary Training"
        )
        self.isRestDay = resolvedRestDay
        self.notes = container.decodeFlexibleString(
            forKey: .notes,
            default: resolvedRestDay
                ? "Active recovery, mobility work, and light cardio."
                : "Prime your setup, execute with controlled tempo, and progress load only if rep quality stays high."
        )
        self.exercises = resolvedRestDay ? [] : parsedExercises
    }
}

struct WorkoutExerciseResponse: Codable {
    let exerciseName: String
    let sets: Int
    let reps: String
    let tempo: String
    let restSeconds: Int
    let notes: String
    let muscleTarget: String

    init(
        exerciseName: String,
        sets: Int,
        reps: String,
        tempo: String,
        restSeconds: Int,
        notes: String,
        muscleTarget: String
    ) {
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.tempo = tempo
        self.restSeconds = restSeconds
        self.notes = notes
        self.muscleTarget = muscleTarget
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseName
        case sets
        case reps
        case tempo
        case restSeconds
        case notes
        case muscleTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.exerciseName = container.decodeFlexibleString(forKey: .exerciseName, default: "Exercise")
        self.sets = container.decodeFlexibleInt(forKey: .sets) ?? 0
        self.reps = container.decodeFlexibleString(forKey: .reps, default: "")
        self.tempo = container.decodeFlexibleString(forKey: .tempo, default: "")
        self.restSeconds = container.decodeFlexibleInt(forKey: .restSeconds) ?? 0
        self.notes = container.decodeFlexibleString(
            forKey: .notes,
            default: "Control the eccentric for 2-3 seconds, keep full ROM, and add load only after you own every rep."
        )
        self.muscleTarget = container.decodeFlexibleString(forKey: .muscleTarget, default: "Primary Target")
    }
}

// MARK: - Week-Only Response (for generating subsequent weeks)

struct WorkoutWeekResponse: Codable {
    let weekSummary: String
    let days: [WorkoutDayResponse]

    init(weekSummary: String, days: [WorkoutDayResponse]) {
        self.weekSummary = weekSummary
        self.days = days
    }

    private enum CodingKeys: String, CodingKey {
        case weekSummary
        case days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.weekSummary = container.decodeFlexibleString(
            forKey: .weekSummary,
            default: "Progressive overload adjustments applied for this week."
        )
        self.days = container.decodeFlexibleArray(WorkoutDayResponse.self, forKey: .days)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func decodeFlexibleString(forKey key: Key, default fallback: String) -> String {
        (decodeFlexibleString(forKey: key) ?? "").cleanedOr(default: fallback)
    }

    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int.fromFlexibleString(value)
        }
        return nil
    }

    func decodeFlexibleInt(forKey key: Key, default fallback: Int, minimum: Int? = nil) -> Int {
        let decoded = decodeFlexibleInt(forKey: key) ?? fallback
        guard let minimum else { return decoded }
        return max(minimum, decoded)
    }

    func decodeFlexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "y", "1"].contains(lowered) || lowered.contains("rest") {
                return true
            }
            if ["false", "no", "n", "0"].contains(lowered) {
                return false
            }
        }
        return nil
    }

    func decodeFlexibleArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        if let values = try? decodeIfPresent([T].self, forKey: key) {
            return values
        }
        return []
    }
}

private extension String {
    func cleanedOr(default fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private extension Int {
    static func fromFlexibleString(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Int(trimmed) {
            return direct
        }
        if let directDouble = Double(trimmed) {
            return Int(directDouble.rounded())
        }

        let pattern = "-?\\d+(?:\\.\\d+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              let numberRange = Range(match.range, in: trimmed) else {
            return nil
        }
        let numericSubstring = String(trimmed[numberRange])
        if let number = Double(numericSubstring) {
            return Int(number.rounded())
        }
        return nil
    }
}
