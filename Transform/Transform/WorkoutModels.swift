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
    var weekSummariesJSON: String = ""
    var isArchived: Bool = false

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
        lastGenerationBundle: String = "",
        weekSummariesJSON: String = ""
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
        self.weekSummariesJSON = weekSummariesJSON
    }

    func weekSummary(for week: Int) -> String? {
        guard let data = weekSummariesJSON.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return map[String(week)]
    }

    func setWeekSummary(_ summary: String, for week: Int) {
        var map: [String: String] = [:]
        if let data = weekSummariesJSON.data(using: .utf8),
           let existing = try? JSONDecoder().decode([String: String].self, from: data) {
            map = existing
        }
        map[String(week)] = summary
        if let encoded = try? JSONEncoder().encode(map),
           let json = String(data: encoded, encoding: .utf8) {
            weekSummariesJSON = json
        }
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

    var hasCompletedExercises: Bool {
        days.contains { day in
            day.exercises.contains { $0.isCompleted }
        }
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
    var feedbackSubmittedAt: Date?
    var sessionEffort: Int = 0
    var stimulusQuality: Int = 0
    var jointPain: Int = 0
    var performanceRatingRaw: String = ""
    var sessionFeedbackNotes: String = ""
    var sessionStartedAt: Date?
    var sessionEndedAt: Date?

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

    var performanceRating: WorkoutPerformanceRating? {
        get { WorkoutPerformanceRating(rawValue: performanceRatingRaw) }
        set { performanceRatingRaw = newValue?.rawValue ?? "" }
    }

    var hasSessionFeedback: Bool {
        feedbackSubmittedAt != nil
    }
}

enum WorkoutPerformanceRating: String, CaseIterable, Identifiable {
    case better = "Better"
    case same = "Same"
    case worse = "Worse"

    var id: String { rawValue }
}

enum ExerciseCompletionStatus: String, CaseIterable, Identifiable {
    case completed = "Completed"
    case completedModified = "Completed (modified)"
    case skippedTime = "Skipped — ran out of time"
    case skippedEquipment = "Skipped — equipment unavailable"
    case skippedPain = "Skipped — pain/discomfort"
    case substituted = "Substituted"

    var id: String { rawValue }

    var isSkipped: Bool {
        switch self {
        case .skippedTime, .skippedEquipment, .skippedPain: return true
        default: return false
        }
    }

    var shortLabel: String {
        switch self {
        case .completed: return "Done"
        case .completedModified: return "Modified"
        case .skippedTime: return "Skipped — No Time"
        case .skippedEquipment: return "Skipped — No Equip"
        case .skippedPain: return "Skipped — Pain"
        case .substituted: return "Substituted"
        }
    }

    /// Plain reason phrase used in longitudinal skip-history summaries fed to the generator.
    var historyReason: String {
        switch self {
        case .completed: return "completed"
        case .completedModified: return "modified"
        case .skippedTime: return "ran out of time"
        case .skippedEquipment: return "equipment unavailable"
        case .skippedPain: return "pain/discomfort"
        case .substituted: return "substituted"
        }
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
    var completionStatusRaw: String = ""

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

    var completionStatus: ExerciseCompletionStatus? {
        get { ExerciseCompletionStatus(rawValue: completionStatusRaw) }
        set { completionStatusRaw = newValue?.rawValue ?? "" }
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
                return stemForCanonicalKey(token)
            }
            .filter { token in
                !token.isEmpty && !stopWords.contains(token)
            }

        if tokens.isEmpty {
            return normalize(exerciseName)
        }

        return tokens.sorted().joined(separator: " ")
    }

    private static func stemForCanonicalKey(_ token: String) -> String {
        let stemmed = pluralStemForCanonicalKey(token)
        // Words whose singular ends in 'e' (raise, lunge, bridge, squeeze) only converge
        // with their plural if the trailing 'e' is dropped too: the -es rule turns
        // "raises" into "rais" while the untouched singular stays "raise", silently
        // splitting the weight history for that movement. Applied identically on every
        // write and read; the startup normalizers re-derive stored keys from names.
        if stemmed.count > 3 && stemmed.hasSuffix("e") {
            return String(stemmed.dropLast())
        }
        return stemmed
    }

    private static func pluralStemForCanonicalKey(_ token: String) -> String {
        guard token.count > 3 else { return token }
        if token.hasSuffix("sses") { return String(token.dropLast(2)) }
        if token.hasSuffix("ches") || token.hasSuffix("shes") || token.hasSuffix("xes") || token.hasSuffix("zes") {
            return String(token.dropLast(2))
        }
        if token.hasSuffix("ies") && token.count > 4 {
            return String(token.dropLast(3)) + "y"
        }
        if token.hasSuffix("es") && token.count > 4 {
            let beforeEs = token[token.index(token.endIndex, offsetBy: -3)]
            if "aeiou".contains(beforeEs) { return String(token.dropLast(1)) }
            return String(token.dropLast(2))
        }
        if token.hasSuffix("ss") { return token }
        if token.hasSuffix("s") { return String(token.dropLast()) }
        return token
    }
}

nonisolated struct SetLogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var setNumber: Int
    var weightLbs: Double
    var repsCompleted: Int
    var notes: String = ""
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
    var setLogsJSON: String = ""
    /// The program day this session belongs to (`WorkoutDay.dayNumber`). Scopes the live
    /// "today's session" to the day actually being trained so a same-named exercise on a
    /// different day — or stray same-day data — can't show up as this card's progress.
    /// Defaults to 0 (lightweight migration); 0 means "unscoped / legacy", which never
    /// matches a real day (day numbers start at 1). Cross-session history keys off the
    /// exercise name, not this field, so progression continuity is unaffected.
    var workoutDayNumber: Int = 0

    init(
        loggedAt: Date = .now,
        exerciseName: String,
        weightLbs: Double,
        repsCompleted: Int? = nil,
        notes: String = "",
        muscleTarget: String = "",
        workoutDayNumber: Int = 0,
        setLogs: [SetLogEntry] = []
    ) {
        self.loggedAt = loggedAt
        self.exerciseName = exerciseName
        self.normalizedExerciseName = ExerciseWeightEntry.normalize(exerciseName)
        self.canonicalExerciseKey = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        self.weightLbs = weightLbs
        self.repsCompleted = repsCompleted
        self.notes = notes
        self.muscleTarget = muscleTarget
        self.workoutDayNumber = workoutDayNumber
        self.setLogsJSON = Self.encodeSetLogs(setLogs)
    }

    var decodedSetLogs: [SetLogEntry] {
        guard !setLogsJSON.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode([SetLogEntry].self, from: Data(setLogsJSON.utf8))
        } catch {
            print("[ExerciseLog] Failed to decode set logs for '\(exerciseName)': \(error.localizedDescription)")
            return []
        }
    }

    static func encodeSetLogs(_ logs: [SetLogEntry]) -> String {
        guard !logs.isEmpty,
              let data = try? JSONEncoder().encode(logs),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    static func topSetWeight(from logs: [SetLogEntry]) -> Double? {
        logs.max(by: { $0.weightLbs < $1.weightLbs })?.weightLbs
    }

    static func topSetReps(from logs: [SetLogEntry]) -> Int? {
        guard let maxWeight = topSetWeight(from: logs) else { return nil }
        return logs.filter { abs($0.weightLbs - maxWeight) < 0.01 }
            .max(by: { $0.repsCompleted < $1.repsCompleted })?.repsCompleted
    }
}

// MARK: - Working Set Analysis

/// Robust, read-time interpretation of a single session's logged sets.
///
/// The old logic assumed the heaviest set *was* the working weight, then matched it
/// exactly — so one outlier (a mis-log, or a lone heavy single) hijacked progression
/// and every other set became invisible. This type instead treats a session as a set
/// of (weight, reps) efforts and separates three roles:
///
/// - `warmup`   : a ramp set below the working load.
/// - `working`  : the genuine working sets at the top sustained load.
/// - `anomaly`  : a lone load far above the robust center (median), e.g. `180` among
///                `90`s. Surfaced for confirmation rather than silently trusted.
///
/// Strength is compared with estimated 1RM (the same blend the progression chart uses)
/// so back-off sets, rep changes, and ramps are handled coherently. This is a pure
/// value type with no SwiftData/SwiftUI dependency so it can be smoke-checked off-device.
struct WorkingSetAnalysis {
    enum Role {
        case warmup
        case working
        case anomaly
    }

    struct AnalyzedSet: Identifiable {
        let id: UUID
        let setNumber: Int
        let weightLbs: Double
        let reps: Int
        let estimatedOneRepMax: Double
        let role: Role
    }

    let sets: [AnalyzedSet]
    let workingSets: [AnalyzedSet]
    let anomalies: [AnalyzedSet]
    /// Representative top working load (heaviest non-anomalous weight). `nil` when no
    /// usable sets were logged.
    let workingWeight: Double?
    /// Highest estimated-1RM working set — the effort progression keys off.
    let topWorkingSet: AnalyzedSet?

    var hasAnomaly: Bool { !anomalies.isEmpty }

    /// Blend of Epley and Brzycki, matching `ExerciseProgressionView`. Brzycki is
    /// unstable as reps approach its 37-rep asymptote, so it is only blended in its
    /// reliable range and Epley alone is used for high-rep sets.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        let r = Double(reps)
        let epley = weight * (1.0 + r / 30.0)
        if reps <= 12 {
            let brzycki = weight * 36.0 / (37.0 - r)
            return (epley + brzycki) / 2.0
        }
        return epley
    }

    static func analyze(_ logs: [SetLogEntry]) -> WorkingSetAnalysis {
        let valid = logs.filter { $0.weightLbs > 0 && $0.repsCompleted > 0 }
        guard !valid.isEmpty else {
            return WorkingSetAnalysis(sets: [], workingSets: [], anomalies: [],
                                      workingWeight: nil, topWorkingSet: nil)
        }

        let weights = valid.map(\.weightLbs).sorted()
        let median = medianOfSorted(weights)
        let deviations = weights.map { abs($0 - median) }.sorted()
        let mad = medianOfSorted(deviations)

        // A load is "corroborated" if more than one set used (about) the same weight.
        func corroborated(_ w: Double) -> Bool {
            valid.filter { abs($0.weightLbs - w) <= max(0.5, w * 0.02) }.count > 1
        }

        // Anomaly: a lone load far above the robust center. Requires >= 3 sets to
        // establish a center. Use the MAD-based spread when it has signal, otherwise a
        // relative gap so an even split like 90/90/180/90 (MAD = 0) still flags 180.
        let anomalyGap = max(mad * 3.0, median * 0.4)
        func isAnomaly(_ w: Double) -> Bool {
            valid.count >= 3 && w > median && (w - median) > anomalyGap && !corroborated(w)
        }

        let workingWeight = valid.filter { !isAnomaly($0.weightLbs) }.map(\.weightLbs).max()
        let band = (workingWeight ?? 0) * 0.025

        let analyzed: [AnalyzedSet] = valid.map { s in
            let e1rm = estimatedOneRepMax(weight: s.weightLbs, reps: s.repsCompleted)
            let role: Role
            if isAnomaly(s.weightLbs) {
                role = .anomaly
            } else if let ww = workingWeight, s.weightLbs >= ww - band - 0.001 {
                role = .working
            } else {
                role = .warmup
            }
            return AnalyzedSet(id: s.id, setNumber: s.setNumber, weightLbs: s.weightLbs,
                               reps: s.repsCompleted, estimatedOneRepMax: e1rm, role: role)
        }

        let working = analyzed.filter { $0.role == .working }
        return WorkingSetAnalysis(
            sets: analyzed,
            workingSets: working,
            anomalies: analyzed.filter { $0.role == .anomaly },
            workingWeight: workingWeight,
            topWorkingSet: working.max(by: { $0.estimatedOneRepMax < $1.estimatedOneRepMax })
        )
    }

    private static func medianOfSorted(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let n = sorted.count
        if n % 2 == 1 { return sorted[n / 2] }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
    }
}

extension WorkingSetAnalysis {
    /// The session's progression-worthy top set: the highest estimated-1RM *working*
    /// set, after warm-ups and anomalies are excluded. Returns `nil` when there is no
    /// usable per-set data so callers can fall back to the raw top set for legacy logs.
    ///
    /// Use this — not `ExercisePerformanceLog.topSetWeight` — anywhere a personal best,
    /// summary load, or stored session weight is derived, so a lone mis-log (e.g. 180 lb
    /// among 90 lb sets) can never become a false PR. It must be applied in every
    /// derivation path (save, edit, and summary recompute); guarding only one lets the
    /// recompute re-promote the anomaly.
    static func qualifiedTop(from logs: [SetLogEntry]) -> (weightLbs: Double, reps: Int)? {
        guard let top = analyze(logs).topWorkingSet else { return nil }
        return (top.weightLbs, top.reps)
    }

    /// Role of each analyzed set keyed by its stable set-log ID, for views that
    /// badge individual sets (warm-up / anomaly) without re-deriving the
    /// analysis per row. Lives here — not as a private helper on some view —
    /// so every renderer of per-set roles reads the same derivation.
    var rolesBySetID: [UUID: Role] {
        // Non-trapping on the (corrupt-data) chance of duplicate set IDs.
        Dictionary(sets.map { ($0.id, $0.role) }, uniquingKeysWith: { first, _ in first })
    }

    /// Anomaly-aware summary stats for a session: the qualified working top when it
    /// exists, otherwise the raw heaviest set. `nil` only when `logs` is empty, so
    /// callers supply their own final fallback. This is the single place the
    /// qualified-vs-raw decision lives, so save, edit, and recompute stay in sync.
    static func summaryTop(from logs: [SetLogEntry]) -> (weightLbs: Double, reps: Int?)? {
        if let qualified = qualifiedTop(from: logs) {
            return (qualified.weightLbs, qualified.reps)
        }
        guard let weight = ExercisePerformanceLog.topSetWeight(from: logs) else { return nil }
        return (weight, ExercisePerformanceLog.topSetReps(from: logs))
    }
}

@MainActor
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

            var records: [BestRecord] = []
            records.reserveCapacity(entries.count)
            for entry in entries {
                records.append(bestRecord(from: entry))
            }
            let bestRecord = records.max { lhs, rhs in
                if lhs.weightLbs != rhs.weightLbs {
                    return lhs.weightLbs < rhs.weightLbs
                }
                return (lhs.loggedAt ?? .distantPast) < (rhs.loggedAt ?? .distantPast)
            } ?? bestRecord(from: latestEntry)

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

    @discardableResult
    static func normalizePerformanceLogs(in modelContext: ModelContext) throws -> Bool {
        let descriptor = FetchDescriptor<ExercisePerformanceLog>()
        let fetched = try modelContext.fetch(descriptor)
        guard !fetched.isEmpty else { return false }

        var changed = false
        for log in fetched {
            let correctKey = ExerciseWeightEntry.canonicalLookupKey(log.exerciseName)
            if log.canonicalExerciseKey != correctKey {
                log.canonicalExerciseKey = correctKey
                changed = true
            }
            let correctNorm = ExerciseWeightEntry.normalize(log.exerciseName)
            if log.normalizedExerciseName != correctNorm {
                log.normalizedExerciseName = correctNorm
                changed = true
            }
        }
        return changed
    }

    nonisolated private struct BestRecord {
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

nonisolated struct WorkoutProgramResponse: Codable {
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

nonisolated struct WorkoutDayResponse: Codable {
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

nonisolated struct WorkoutExerciseResponse: Codable {
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

nonisolated struct WorkoutWeekResponse: Codable {
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

nonisolated private extension KeyedDecodingContainer {
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

nonisolated private extension String {
    func cleanedOr(default fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

nonisolated private extension Int {
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
