import Foundation

/// Actual backup wire shape, shared with the headless tests. Additive optional fields
/// decode old backups without inventing a recovery decision or replacement preference.
nonisolated struct WorkoutExerciseSnapshot: Codable {
    let order: Int
    let exerciseName: String
    let sets: Int
    let reps: String
    let tempo: String?
    let restSeconds: Int
    let notes: String
    let muscleTarget: String
    let isCompleted: Bool
    let completionStatusRaw: String?
    let targetRIR: Int?
    let coachingSourceRaw: String?
    let painReviewRaw: String?
    let replacementName: String?
    let preferredReplacementName: String?
}

nonisolated struct WorkoutProgramSnapshot: Codable {
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
    let isArchived: Bool?
    /// The generator's warnings for the latest week; `WorkoutView` renders them as the
    /// warnings banner. Missing from backups until 2026-11-18, so a restored program lost
    /// its banner (bug audit 2026-11-17, F7). Absent in older backups, which restore as "".
    var validatorWarnings: String? = nil
    /// Per-week summary text keyed by week number (`WorkoutProgram.setWeekSummary`). Same
    /// history and same absent-means-empty reading as `validatorWarnings`.
    var weekSummariesJSON: String? = nil
    // `lastGenerationBundle` is deliberately NOT backed up: it is the Generator Lab's
    // diagnostic dump of the last generation run on this phone (often the largest text in a
    // program), and nothing outside that developer tool reads it.
}

nonisolated struct WorkoutDaySnapshot: Codable {
    let dayNumber: Int
    let dayName: String
    let muscleGroups: String
    let isRestDay: Bool
    let notes: String
    let isCompleted: Bool
    let feedbackSubmittedAt: Date?
    let sessionEffort: Int?
    let stimulusQuality: Int?
    let jointPain: Int?
    let performanceRatingRaw: String?
    let sessionFeedbackNotes: String?
    let sessionStartedAt: Date?
    let sessionEndedAt: Date?
    /// Optional so backups written before the session-clock close flag decode cleanly;
    /// absent means "never closed", which is the correct reading of an older backup.
    let isSessionClosed: Bool?
    let exercises: [WorkoutExerciseSnapshot]
}

@MainActor extension WorkoutExerciseSnapshot {
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
            isCompleted: exercise.isCompleted,
            completionStatusRaw: exercise.completionStatusRaw.isEmpty ? nil : exercise.completionStatusRaw,
            targetRIR: exercise.targetRIR,
            coachingSourceRaw: exercise.coachingSourceRaw.isEmpty ? nil : exercise.coachingSourceRaw,
            painReviewRaw: exercise.painReviewRaw.isEmpty ? nil : exercise.painReviewRaw,
            replacementName: exercise.replacementName.isEmpty ? nil : exercise.replacementName,
            preferredReplacementName: exercise.preferredReplacementName.isEmpty ? nil : exercise.preferredReplacementName
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
            muscleTarget: muscleTarget,
            targetRIR: targetRIR
        )
        exercise.isCompleted = isCompleted
        exercise.completionStatusRaw = completionStatusRaw ?? ""
        exercise.coachingSourceRaw = coachingSourceRaw ?? ""
        exercise.painReviewRaw = painReviewRaw ?? ""
        exercise.replacementName = replacementName ?? ""
        exercise.preferredReplacementName = preferredReplacementName ?? ""
        return exercise
    }
}

@MainActor extension WorkoutDaySnapshot {
    init(_ day: WorkoutDay) {
        self.init(
            dayNumber: day.dayNumber,
            dayName: day.dayName,
            muscleGroups: day.muscleGroups,
            isRestDay: day.isRestDay,
            notes: day.notes,
            isCompleted: day.isCompleted,
            feedbackSubmittedAt: day.feedbackSubmittedAt,
            sessionEffort: day.sessionEffort,
            stimulusQuality: day.stimulusQuality,
            jointPain: day.jointPain,
            performanceRatingRaw: day.performanceRatingRaw,
            sessionFeedbackNotes: day.sessionFeedbackNotes,
            sessionStartedAt: day.sessionStartedAt,
            sessionEndedAt: day.sessionEndedAt,
            isSessionClosed: day.isSessionClosed,
            exercises: day.sortedExercises.map { WorkoutExerciseSnapshot($0) }
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
        day.feedbackSubmittedAt = feedbackSubmittedAt
        day.sessionEffort = sessionEffort ?? 0
        day.stimulusQuality = stimulusQuality ?? 0
        day.jointPain = jointPain ?? 0
        day.performanceRatingRaw = performanceRatingRaw ?? ""
        day.sessionFeedbackNotes = sessionFeedbackNotes ?? ""
        day.sessionStartedAt = sessionStartedAt
        day.sessionEndedAt = sessionEndedAt
        day.isSessionClosed = isSessionClosed ?? false

        for exerciseSnapshot in exercises {
            let exercise = exerciseSnapshot.makeModel()
            exercise.day = day
            day.exercises.append(exercise)
        }

        return day
    }
}

@MainActor extension WorkoutProgramSnapshot {
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
            days: program.sortedDays.map { WorkoutDaySnapshot($0) },
            isArchived: program.isArchived,
            validatorWarnings: program.validatorWarnings.isEmpty ? nil : program.validatorWarnings,
            weekSummariesJSON: program.weekSummariesJSON.isEmpty ? nil : program.weekSummariesJSON
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
        program.isArchived = isArchived ?? false
        // SEAM: pre-fix behaviour, warnings and week summaries are not restored.

        for daySnapshot in days {
            let day = daySnapshot.makeModel()
            day.program = program
            program.days.append(day)
        }

        return program
    }
}
