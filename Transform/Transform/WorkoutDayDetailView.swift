import SwiftUI
import SwiftData
import Foundation

struct WorkoutDayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseWeightEntry.loggedAt, order: .reverse) private var allWeightLogs: [ExerciseWeightEntry]
    @Query(sort: \ExercisePerformanceLog.loggedAt, order: .reverse) private var allPerformanceLogs: [ExercisePerformanceLog]
    let day: WorkoutDay
    @State private var exerciseForWeightLogging: WorkoutExercise?
    @State private var feedbackDay: WorkoutDay?
    @State private var completionPromptExercise: WorkoutExercise?

    var completedExerciseCount: Int {
        day.sortedExercises.filter { $0.isCompleted }.count
    }

    var totalExerciseCount: Int {
        day.exercises.count
    }

    var exerciseProgress: Double {
        totalExerciseCount > 0 ? Double(completedExerciseCount) / Double(totalExerciseCount) : 0
    }

    var sessionNoteSections: SessionNoteSections {
        SessionNoteSections.parse(day.notes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dayHeader
                if !day.notes.isEmpty {
                    sessionNotes
                }
                if day.isCompleted {
                    sessionFeedbackCard
                }
                exerciseList
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .workoutTabBarClearance()
        .navigationTitle("Day \(day.dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exerciseForWeightLogging) { exercise in
            AddExerciseWeightSheet(
                exercise: exercise,
                weightSummary: weightSummary(for: exercise),
                latestSetLogs: latestSetLogs(for: exercise),
                todaysSetLogs: todaysSetLogs(for: exercise)
            )
        }
        .sheet(item: $feedbackDay) { selectedDay in
            WorkoutSessionFeedbackSheet(day: selectedDay)
        }
        .alert(
            "Complete without logged sets?",
            isPresented: Binding(
                get: { completionPromptExercise != nil },
                set: { isPresented in
                    if !isPresented {
                        completionPromptExercise = nil
                    }
                }
            )
        ) {
            Button("Log Sets", role: .cancel) {
                if let exercise = completionPromptExercise {
                    exerciseForWeightLogging = exercise
                }
                completionPromptExercise = nil
            }
            Button("Complete Anyway") {
                if let exercise = completionPromptExercise {
                    toggleExercise(exercise, allowIncompleteLogs: true)
                }
                completionPromptExercise = nil
            }
        } message: {
            Text(completionPromptMessage)
        }
    }

    // MARK: - Day Header

    var dayHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.dayName)
                        .font(.title2.bold())
                    Text(day.muscleGroups)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                weekBadge
            }

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(TFColor.accent.opacity(0.15))
                            .frame(height: 6)
                        Capsule()
                            .fill(TFColor.accent)
                            .frame(width: geo.size.width * exerciseProgress, height: 6)
                            .animation(.easeOut(duration: 0.4), value: exerciseProgress)
                    }
                }
                .frame(height: 6)

                Text("\(completedExerciseCount)/\(totalExerciseCount)")
                    .font(.caption.bold())
                    .foregroundStyle(TFColor.accent)
                    .frame(width: 36)
            }
        }
        .dashCard()
    }

    var weekBadge: some View {
        Text("Week \(day.weekNumber)")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(TFColor.accent.opacity(0.15))
            .foregroundStyle(TFColor.accent)
            .clipShape(Capsule())
    }

    // MARK: - Session Notes

    var sessionNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Session Notes", systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(TFColor.accent)

            if !sessionNoteSections.summary.isEmpty {
                Text(sessionNoteSections.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !sessionNoteSections.warmupSteps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warm-up Checklist")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)

                    ForEach(sessionNoteSections.warmupSteps, id: \.self) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(TFColor.accent)
                                .padding(.top, 6)

                            Text(step)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    var sessionFeedbackCard: some View {
        Button {
            feedbackDay = day
        } label: {
            HStack(spacing: 12) {
                Image(systemName: day.hasSessionFeedback ? "checkmark.bubble.fill" : "bubble.left.and.exclamationmark.bubble.right")
                    .foregroundStyle(day.hasSessionFeedback ? TFColor.success : TFColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.hasSessionFeedback ? "Session Feedback" : "Add Session Feedback")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(day.hasSessionFeedback
                         ? "Effort \(day.sessionEffort)/5 · Stimulus \(day.stimulusQuality)/5 · Pain \(day.jointPain)/5 · \(day.performanceRating?.rawValue ?? "Not rated")"
                         : "Four quick ratings help calibrate next week.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(TFColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exercise List

    var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            TFSectionLabel(text: "Exercises")

            ForEach(day.sortedExercises) { exercise in
                ExerciseCard(
                    exercise: exercise,
                    weightSummary: weightSummary(for: exercise),
                    latestSetLogs: latestSetLogs(for: exercise),
                    todaysSetLogs: todaysSetLogs(for: exercise),
                    onToggle: { toggleExercise(exercise) },
                    onLogWeight: { exerciseForWeightLogging = exercise }
                )
            }
        }
    }

    var completionPromptMessage: String {
        guard let exercise = completionPromptExercise else {
            return "Logging sets improves future progression cues."
        }
        let logged = todaysSetLogs(for: exercise).count
        return "\(logged)/\(exercise.sets) sets are logged. Logging sets improves future progression cues."
    }

    func toggleExercise(_ exercise: WorkoutExercise, allowIncompleteLogs: Bool = false) {
        if !allowIncompleteLogs, !exercise.isCompleted, exercise.sets > 0 {
            let logged = todaysSetLogs(for: exercise).count
            if logged < exercise.sets {
                completionPromptExercise = exercise
                TFHaptics.impact(.soft)
                return
            }
        }

        let previousExerciseState = exercise.isCompleted
        let previousDayState = day.isCompleted
        exercise.isCompleted.toggle()

        let allDone = day.exercises.allSatisfy { $0.isCompleted }
        if allDone != day.isCompleted {
            day.isCompleted = allDone
        }

        guard PersistenceReporter.save(modelContext, operation: "exercise completion toggle") else {
            modelContext.rollback()
            exercise.isCompleted = previousExerciseState
            day.isCompleted = previousDayState
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.writeAutomaticBackupCoalesced(using: modelContext)
        TFHaptics.impact(.light)
        if day.isCompleted && !previousDayState {
            feedbackDay = day
        }
    }

    func weightSummary(for exercise: WorkoutExercise) -> ExerciseWeightEntry? {
        ExerciseWeightStore.summary(for: exercise, within: allWeightLogs)
    }

    /// The most recent completed session before today — the "last session" reference.
    func latestSetLogs(for exercise: WorkoutExercise) -> [SetLogEntry] {
        SetLoggingService.previousSets(for: exercise, in: allPerformanceLogs)
    }

    /// Sets already logged for today's in-progress session.
    func todaysSetLogs(for exercise: WorkoutExercise) -> [SetLogEntry] {
        SetLoggingService.todaysSets(for: exercise, in: allPerformanceLogs)
    }
}

// MARK: - Exercise Card

struct ExerciseCard: View {
    @Environment(\.modelContext) private var modelContext
    let exercise: WorkoutExercise
    let weightSummary: ExerciseWeightEntry?
    /// The most recent *completed* session before today — drives the "last session"
    /// panel and the progression suggestion.
    let latestSetLogs: [SetLogEntry]
    /// Sets already logged for today's in-progress session — drives the inline logger.
    let todaysSetLogs: [SetLogEntry]
    let onToggle: () -> Void
    let onLogWeight: () -> Void

    var latestWeightLog: ExerciseWeightEntry? {
        weightSummary
    }

    var bestWeightText: String? {
        guard let latestWeightLog else { return nil }
        let bestWeight = latestWeightLog.hasBestRecord ? latestWeightLog.bestWeightLbs : latestWeightLog.weightLbs
        return "\(formatWeight(bestWeight)) lb"
    }

    var lastRepsTileText: String? {
        latestWeightLog?.repsCompleted.map { "\($0) reps" }
    }

    var bestRepsTileText: String? {
        guard let latestWeightLog else { return nil }
        let bestReps = latestWeightLog.hasBestRecord ? (latestWeightLog.bestRepsCompleted ?? latestWeightLog.repsCompleted) : latestWeightLog.repsCompleted
        return bestReps.map { "\($0) reps" }
    }

    var parsedPrescription: ExercisePrescription? {
        ExercisePrescription.parse(from: exercise.notes)
    }

    var workingSetAnalysis: WorkingSetAnalysis {
        WorkingSetAnalysis.analyze(latestSetLogs)
    }

    /// True when this exercise sits inside a deload block. Deload weeks intentionally pull
    /// load back (the program notes call for roughly 10% under the prior block and stopping
    /// shy of failure), so the "add load / go heavier" cue is wrong here and is replaced by
    /// hold-back coaching. Detected from the day or exercise notes, where the generator
    /// states the deload intent.
    var isDeloadContext: Bool {
        let sources = [exercise.day?.notes ?? "", exercise.day?.dayName ?? "", exercise.notes]
        return sources.contains { $0.range(of: "deload", options: .caseInsensitive) != nil }
    }

    /// The set count the coaching note explicitly prescribes for THIS exercise, if any
    /// (e.g. "complete 4 clean sets" → 4). Weekly-volume phrasing ("the 10 direct sets the
    /// blueprint prescribes") is deliberately excluded. Used to detect note-vs-structured
    /// drift left behind when the generator trimmed the set count without rewriting prose.
    var noteClaimedSetCount: Int? {
        let note = exercise.notes
        let patterns = [
            #"(?i)\ball\s+(\d+)\s+(?:clean\s+|quality\s+|working\s+|hard\s+)?sets\b"#,
            #"(?i)\bcomplete\s+(\d+)\s+(?:clean\s+|quality\s+|working\s+|hard\s+)?sets\b"#,
            #"(?i)\b(\d+)\s+(?:clean|quality|working|hard)\s+sets\b"#,
        ]
        var best: Int?
        for pattern in patterns {
            if let value = firstIntCapture(note, pattern) {
                best = max(best ?? value, value)
            }
        }
        return best
    }

    private func firstIntCapture(_ text: String, _ pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[captureRange])
    }

    private func conciseWorkoutInsight(
        from note: String,
        hideProgressionCue: Bool,
        hideDeloadCue: Bool
    ) -> String {
        let sentences = splitSentences(note)
        guard !sentences.isEmpty else { return "" }

        var seen = Set<String>()
        var kept: [String] = []

        for sentence in sentences {
            let normalized = sentence
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()

            if hideDeloadCue,
               containsAny(normalized, [
                "deload", "10%", "under your last", "leave 2", "leave 3", "reserve",
                "chase pr", "prs", "personal record"
               ]) {
                continue
            }

            if hideProgressionCue,
               containsAny(normalized, [
                "next session", "add load", "add weight", "add reps", "before adding",
                "progression", "progress load", "hold load", "increase to"
               ]) {
                continue
            }

            if containsAny(normalized, ["you logged", "you used", "your last session", "last time you"]) {
                continue
            }

            let key = normalized
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(key).inserted else { continue }

            kept.append(sentence)
            if kept.count == 2 { break }
        }

        let compact = kept.joined(separator: " ")
        guard compact.count > 220 else { return compact }

        let prefix = compact.prefix(217).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

    private func splitSentences(_ text: String) -> [String] {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return [] }

        let pattern = #"[^.!?]+[.!?]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [collapsed] }
        let range = NSRange(collapsed.startIndex..<collapsed.endIndex, in: collapsed)

        return regex.matches(in: collapsed, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: collapsed) else { return nil }
            let sentence = collapsed[matchRange].trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? nil : sentence
        }
    }

    private func containsAny(_ text: String, _ fragments: [String]) -> Bool {
        fragments.contains { text.contains($0) }
    }

    var progressionSuggestion: ProgressionSuggestion? {
        // On a deload day, never tell the lifter to add weight — that contradicts the
        // prescription. Coach to hold the lighter load regardless of last session's reps.
        if isDeloadContext { return .deloadGuidance }
        guard let log = latestWeightLog else { return nil }
        guard let repRange = RepRange.parse(exercise.reps) else { return nil }
        let suggestion = ProgressionSuggestion.evaluate(
            analysis: workingSetAnalysis,
            summaryRepsCompleted: log.repsCompleted,
            repRange: repRange,
            lastWeight: log.weightLbs,
            exerciseName: exercise.exerciseName
        )
        // Safety net for already-generated workouts where the note still prescribes more
        // sets than the (trimmed) structured count: don't let the generic heuristic
        // greenlight a load increase the written prescription says to hold. Self-correcting
        // — once prose and structured sets agree, this veto goes quiet.
        if let suggestion, suggestion.increasesLoad,
           let claimed = noteClaimedSetCount, claimed > exercise.sets {
            return .completePrescribedSets(claimed)
        }
        return suggestion
    }

    var cleanedCoachingNote: String {
        if let parsedPrescription {
            return parsedPrescription.cleanedNotes
        }
        return exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var conciseCoachingNote: String {
        conciseWorkoutInsight(
            from: cleanedCoachingNote,
            hideProgressionCue: progressionSuggestion != nil,
            hideDeloadCue: isDeloadContext
        )
    }

    var displayTempo: String? {
        let structuredTempo = exercise.tempo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !structuredTempo.isEmpty {
            return structuredTempo
        }
        return parsedPrescription?.tempo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    onToggle()
                } label: {
                    Image(systemName: exercise.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(exercise.isCompleted ? TFColor.success : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(exercise.isCompleted ? "Mark \(exercise.exerciseName) incomplete" : "Mark \(exercise.exerciseName) complete")

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.exerciseName)
                        .font(.subheadline.bold())
                        .strikethrough(exercise.isCompleted, color: .secondary)
                        .foregroundStyle(exercise.isCompleted ? .secondary : .primary)

                    if !exercise.muscleTarget.isEmpty {
                        Text(exercise.muscleTarget)
                            .font(.caption2)
                            .foregroundStyle(TFColor.accent)
                    }
                }

                Spacer()

                Text("#\(exercise.order + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 14)

            if exercise.restSeconds > 0 {
                ExerciseRestTimerView(exercise: exercise)
                Divider().padding(.horizontal, 14)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ExerciseStat(icon: "square.stack.3d.up", label: "Sets", value: "\(exercise.sets)")
                    ExerciseStat(icon: "arrow.up.arrow.down", label: "Reps", value: exercise.reps)
                    if let tempo = displayTempo {
                        ExerciseStat(icon: "metronome", label: "Tempo", value: tempo)
                    }
                }

                InlineSetLogger(
                    exercise: exercise,
                    loggedSets: todaysSetLogs,
                    suggestedWeight: workingSetAnalysis.workingWeight,
                    suggestedReps: workingSetAnalysis.topWorkingSet?.reps ?? RepRange.parse(exercise.reps)?.high,
                    onLog: { setNumber, weight, reps in
                        SetLoggingService.logSet(setNumber: setNumber, weightLbs: weight, reps: reps, for: exercise, modelContext: modelContext)
                    },
                    onClear: { setNumber in
                        SetLoggingService.clearSet(setNumber: setNumber, for: exercise, modelContext: modelContext)
                    }
                )

                if !latestSetLogs.isEmpty {
                    setLogBreakdown
                } else if latestWeightLog != nil {
                    ExerciseWeightSnapshotTile(
                        lastWeightText: latestWeightLog.map { "\(formatWeight($0.weightLbs)) lb" } ?? "-",
                        lastRepsText: lastRepsTileText,
                        bestWeightText: bestWeightText ?? "-",
                        bestRepsText: bestRepsTileText
                    )
                }

                if let suggestion = progressionSuggestion {
                    ProgressionSuggestionBadge(suggestion: suggestion)
                }

                if let anomaly = workingSetAnalysis.anomalies.first {
                    let reference = workingSetAnalysis.workingWeight ?? anomaly.weightLbs
                    SetAnomalyNotice(
                        text: "Check Set \(anomaly.setNumber): \(formatWeight(anomaly.weightLbs)) lb is well above your \(formatWeight(reference)) lb working sets. Confirm or fix the entry — it isn't used for progression."
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let parsedPrescription {
                Divider().padding(.horizontal, 14)
                HStack(alignment: .center) {
                    Text(parsedPrescription.intensityLabel)
                        .font(parsedPrescription.intensity == .light ? .caption : .caption.bold())
                        .foregroundStyle(parsedPrescription.intensity.color)

                    Spacer()

                    if let rirValue = parsedPrescription.rir {
                        Text("RIR \(rirValue)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider().padding(.horizontal, 14)
            if let status = exercise.completionStatus, status != .completed {
                HStack(spacing: 6) {
                    Image(systemName: status.isSkipped ? "forward.fill" : "arrow.triangle.swap")
                        .font(.caption2)
                        .foregroundStyle(status.isSkipped ? TFColor.danger : TFColor.warning)
                    Text(status.shortLabel)
                        .font(.caption2.bold())
                        .foregroundStyle(status.isSkipped ? TFColor.danger : TFColor.warning)
                    Spacer()
                    Button {
                        exercise.completionStatus = nil
                        if status.isSkipped { exercise.isCompleted = false }
                        PersistenceReporter.saveWithBackup(modelContext, operation: "clear exercise status", haptic: .success)
                    } label: {
                        Text("Clear")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(status.isSkipped ? TFColor.danger.opacity(0.06) : TFColor.warning.opacity(0.06))
            }

            Divider().padding(.horizontal, 14)
            HStack {
                Button {
                    onLogWeight()
                } label: {
                    Label("Edit / Notes", systemImage: "square.and.pencil")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(ExerciseCompletionStatus.allCases.filter { $0 != .completed }) { status in
                        Button {
                            exercise.completionStatus = status
                            if status.isSkipped {
                                exercise.isCompleted = true
                            }
                            PersistenceReporter.saveWithBackup(modelContext, operation: "set exercise status", haptic: .success)
                        } label: {
                            Text(status.rawValue)
                        }
                    }
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ExerciseProgressionView(exerciseName: exercise.exerciseName)
                } label: {
                    Label("Progression", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                if let latestWeightLog {
                    Text(latestWeightLog.loggedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let latestWeightLog,
               !latestWeightLog.notes.isEmpty {
                Divider().padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 4) {
                    if !latestWeightLog.notes.isEmpty {
                        Text(latestWeightLog.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !conciseCoachingNote.isEmpty {
                Divider().padding(.horizontal, 14)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(TFColor.warning)
                    Text(conciseCoachingNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(exercise.isCompleted ? TFColor.success.opacity(0.05) : TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(exercise.isCompleted ? TFColor.success.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    var setLogBreakdown: some View {
        let analysis = workingSetAnalysis
        let roles = setRoleLookup(from: analysis.sets)

        return VStack(alignment: .leading, spacing: 6) {
            Text("LAST SESSION")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .tracking(1)

            ForEach(latestSetLogs) { set in
                let role = roles[set.id] ?? .working
                HStack(spacing: 8) {
                    Text("Set \(set.setNumber)")
                        .font(.caption2.bold())
                        .foregroundStyle(role == .anomaly ? TFColor.warning : TFColor.accent)
                        .frame(width: 38, alignment: .leading)
                    Text("\(formatWeight(set.weightLbs)) lb")
                        .font(.caption.bold())
                        .foregroundStyle(role == .anomaly ? TFColor.warning : .primary)
                        .frame(width: 65, alignment: .trailing)
                    Text("\u{00D7}")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(set.repsCompleted) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if role == .warmup {
                        Text("warm-up")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(TFColor.accent.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(TFColor.accent.opacity(0.1))
                            .clipShape(Capsule())
                    } else if role == .anomaly {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(TFColor.warning)
                    }
                    Spacer()
                }
            }

            if let best = bestWeightText {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(TFColor.warning)
                    Text("Best: \(best)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }


}

// MARK: - Exercise Stat

struct ExerciseStat: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundStyle(TFColor.accent)
                .frame(height: 16)

            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }
}

struct ExerciseWeightSnapshotTile: View {
    let lastWeightText: String
    let lastRepsText: String?
    let bestWeightText: String
    let bestRepsText: String?

    var body: some View {
        HStack(spacing: 0) {
            weightColumn(title: "Last", value: lastWeightText, reps: lastRepsText)
            Divider()
                .padding(.vertical, 10)
            weightColumn(title: "Best", value: bestWeightText, reps: bestRepsText)
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    func weightColumn(title: String, value: String, reps: String?) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let reps, !reps.isEmpty {
                Text(reps)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}

struct ExerciseRestTimerView: View {
    let exercise: WorkoutExercise

    @State private var isRestTimerActive = false
    @State private var remainingRestSeconds = 0
    @State private var restTimerTask: Task<Void, Never>?
    @State private var showExpandedRestTimer = false
    @State private var didCompleteRestTimer = false
    @State private var restEndDate: Date?

    var restDisplayText: String {
        if didCompleteRestTimer { return "00:00" }
        if isRestTimerActive { return formatCountdown(remainingRestSeconds) }
        if remainingRestSeconds != exercise.restSeconds { return formatCountdown(remainingRestSeconds) }
        return formatRest(exercise.restSeconds)
    }

    var restStatusLabel: String {
        if didCompleteRestTimer { return "Complete" }
        if isRestTimerActive { return "Running" }
        if remainingRestSeconds != exercise.restSeconds { return "Paused" }
        return "Rest"
    }

    var restProgress: Double {
        guard exercise.restSeconds > 0 else { return 0 }
        if didCompleteRestTimer { return 1 }
        let clampedRemaining = min(max(remainingRestSeconds, 0), exercise.restSeconds)
        return 1 - (Double(clampedRemaining) / Double(exercise.restSeconds))
    }

    var timerAccent: Color {
        if didCompleteRestTimer { return TFColor.success }
        if isRestTimerActive { return remainingRestSeconds <= 15 ? TFColor.danger : TFColor.accent }
        if remainingRestSeconds != exercise.restSeconds { return TFColor.warning }
        return TFColor.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Rest Timer:")
                    .font(.title3)
                    .foregroundStyle(.primary)
                Text(restDisplayText)
                    .font(.title3.bold())
                    .foregroundStyle(timerAccent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 58, alignment: .leading)
                Spacer()

                Button {
                    showExpandedRestTimer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(timerAccent.opacity(0.14))
                    Capsule()
                        .fill(timerAccent)
                        .frame(width: geo.size.width * max(0, min(restProgress, 1)))
                }
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                Button {
                    toggleRestTimer()
                } label: {
                    Label(isRestTimerActive ? "Pause" : (remainingRestSeconds != exercise.restSeconds ? "Resume" : "Start Rest"), systemImage: isRestTimerActive ? "pause.fill" : "play.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(timerAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
                }
                .buttonStyle(.plain)

                Button {
                    resetRestTimer()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.06))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer: \(restStatusLabel), \(restDisplayText)")
        .onAppear {
            if remainingRestSeconds == 0 && !didCompleteRestTimer {
                remainingRestSeconds = exercise.restSeconds
            }
            if isRestTimerActive && restTimerTask == nil {
                startRestTimer()
            }
        }
        .fullScreenCover(isPresented: $showExpandedRestTimer) {
            RestTimerFullscreen(
                exerciseName: exercise.exerciseName,
                exerciseNumber: exercise.order + 1,
                prescriptionLabel: "\(exercise.sets) sets x \(exercise.reps) reps",
                statusLabel: restStatusLabel,
                timeText: restDisplayText,
                accent: timerAccent,
                isTimerActive: isRestTimerActive,
                progress: restProgress,
                onToggle: { toggleRestTimer() },
                onReset: { resetRestTimer() },
                onClose: { showExpandedRestTimer = false }
            )
        }
    }

    private func setRoleLookup(from sets: [WorkingSetAnalysis.AnalyzedSet]) -> [UUID: WorkingSetAnalysis.Role] {
        var lookup: [UUID: WorkingSetAnalysis.Role] = [:]
        for set in sets {
            lookup[set.id] = set.role
        }
        return lookup
    }

    func toggleRestTimer() {
        if isRestTimerActive {
            pauseRestTimer()
            return
        }
        if didCompleteRestTimer {
            didCompleteRestTimer = false
            remainingRestSeconds = exercise.restSeconds
        }
        if remainingRestSeconds <= 0 || remainingRestSeconds > exercise.restSeconds {
            remainingRestSeconds = exercise.restSeconds
        }
        restEndDate = Date().addingTimeInterval(Double(remainingRestSeconds))
        isRestTimerActive = true
        startRestTimer()
        TFHaptics.impact(.light)
    }

    func startRestTimer() {
        stopRestTimer()
        restTimerTask = Task { @MainActor in
            while isRestTimerActive && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                tickRestTimer()
            }
        }
    }

    func stopRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
    }

    func pauseRestTimer() {
        if let endDate = restEndDate {
            remainingRestSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        }
        restEndDate = nil
        isRestTimerActive = false
        stopRestTimer()
    }

    func resetRestTimer() {
        pauseRestTimer()
        didCompleteRestTimer = false
        remainingRestSeconds = exercise.restSeconds
    }

    func tickRestTimer() {
        guard isRestTimerActive, let endDate = restEndDate else {
            stopRestTimer()
            return
        }
        let remaining = Int(ceil(endDate.timeIntervalSinceNow))
        if remaining > 0 {
            if remaining != remainingRestSeconds {
                remainingRestSeconds = remaining
            }
            return
        }
        pauseRestTimer()
        remainingRestSeconds = 0
        didCompleteRestTimer = true
        TFHaptics.success()
    }

    func formatCountdown(_ seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let min = clamped / 60
        let sec = clamped % 60
        return String(format: "%02d:%02d", min, sec)
    }

    func formatRest(_ seconds: Int) -> String {
        if seconds >= 60 {
            let min = seconds / 60
            let sec = seconds % 60
            return sec > 0 ? "\(min)m \(sec)s" : "\(min)m"
        }
        return "\(seconds)s"
    }
}

struct RestTimerFullscreen: View {
    let exerciseName: String
    let exerciseNumber: Int
    let prescriptionLabel: String
    let statusLabel: String
    let timeText: String
    let accent: Color
    let isTimerActive: Bool
    let progress: Double
    let onToggle: () -> Void
    let onReset: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, accent.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button("Done") {
                        onClose()
                    }
                    .font(.headline.bold())
                    .foregroundStyle(.white.opacity(0.9))

                    Spacer()
                }

                Spacer()

                Text("Exercise \(exerciseNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Text(exerciseName)
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Text(prescriptionLabel)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)

                Text(statusLabel.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                    .tracking(2)

                Text(timeText)
                    .font(.system(size: 92, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * max(0, min(progress, 1)))
                    }
                }
                .frame(height: 12)

                HStack(spacing: 12) {
                    Button {
                        onToggle()
                    } label: {
                        Label(isTimerActive ? "Pause" : "Start / Resume", systemImage: isTimerActive ? "pause.fill" : "play.fill")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .foregroundStyle(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }

                    Button {
                        onReset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .statusBarHidden()
    }
}

struct SessionNoteSections {
    let summary: String
    let warmupSteps: [String]

    static func parse(_ raw: String) -> SessionNoteSections {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SessionNoteSections(summary: "", warmupSteps: [])
        }

        if let delimitedSections = parseDelimitedWarmupSections(from: trimmed) {
            return delimitedSections
        }

        if let embeddedSections = parseEmbeddedWarmupSections(from: trimmed) {
            return embeddedSections
        }

        return SessionNoteSections(summary: trimmed, warmupSteps: [])
    }

    private static func parseDelimitedWarmupSections(from text: String) -> SessionNoteSections? {
        let normalized = text
            .replacingOccurrences(of: "Warm-up checklist:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Warm up checklist:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Warm-up:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Warm up:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Mobility/activation:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Mobility:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Activation:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Prime with:", with: "|", options: .caseInsensitive)

        let chunks = normalized
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard chunks.count > 1 else {
            return nil
        }

        let summary = chunks.first ?? ""
        let instructionText = chunks.dropFirst().joined(separator: " ")
        let steps = splitWarmupSteps(from: instructionText)

        return SessionNoteSections(summary: summary, warmupSteps: steps)
    }

    private static func parseEmbeddedWarmupSections(from text: String) -> SessionNoteSections? {
        guard let triggerRange = text.range(
            of: #"(?i)(?:warm[\s-]*up with|begin with|start with|prime with)\s+"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let summaryPrefix = text[..<triggerRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let warmupAndRemainder = String(text[triggerRange.upperBound...])

        let delimiters = [" — ", " – ", ";", "."]
        let endIndex = delimiters
            .compactMap { delimiter in
                warmupAndRemainder.range(of: delimiter).map { $0.lowerBound }
            }
            .min()

        let warmupListText: String
        let trailingGuidance: String
        if let endIndex {
            warmupListText = String(warmupAndRemainder[..<endIndex])
            trailingGuidance = String(warmupAndRemainder[endIndex...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        } else {
            warmupListText = warmupAndRemainder
            trailingGuidance = ""
        }

        let steps = splitWarmupSteps(from: warmupListText)
        guard !steps.isEmpty else {
            return nil
        }

        let summary = [summaryPrefix, trailingGuidance]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SessionNoteSections(summary: summary, warmupSteps: steps)
    }

    private static func splitWarmupSteps(from text: String) -> [String] {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: " then ", with: ", ", options: .caseInsensitive)
            .replacingOccurrences(of: " plus ", with: ", ", options: .caseInsensitive)
            .replacingOccurrences(of: " and ", with: ", ", options: .caseInsensitive)
            .replacingOccurrences(of: "\n•", with: "\n")
            .replacingOccurrences(of: "\n-", with: "\n")

        return cleaned
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map {
                $0.replacingOccurrences(of: "Emphasis today:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            .filter { !$0.isEmpty }
    }
}

enum WorkoutIntensity: String {
    case light
    case moderate
    case heavy

    var color: Color {
        switch self {
        case .light: return TFColor.success
        case .moderate: return TFColor.warning
        case .heavy: return TFColor.danger
        }
    }
}

struct ExercisePrescription {
    let week: Int?
    let intensity: WorkoutIntensity
    let rir: String?
    let tempo: String?
    let cleanedNotes: String

    var intensityLabel: String {
        var left = ""
        if let week {
            left = "Week \(week)"
        }

        let intensityText: String
        switch intensity {
        case .light:
            intensityText = "Light Weight"
        case .moderate:
            intensityText = "Moderate Weight"
        case .heavy:
            intensityText = "Heavy Weight"
        }

        if left.isEmpty {
            return intensityText
        }
        return "\(left) \(intensityText)"
    }

    static func parse(from rawNotes: String) -> ExercisePrescription? {
        let trimmed = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let weekString = firstCapture(in: trimmed, pattern: #"(?i)\bweek\s*(\d+)\b"#)
        let week = weekString.flatMap(Int.init)

        guard let intensityMatch = firstCapture(in: trimmed, pattern: #"(?i)\b(light|moderate|heavy)\b"#)?.lowercased(),
              let intensity = WorkoutIntensity(rawValue: intensityMatch) else {
            return nil
        }

        let rir = firstCapture(in: trimmed, pattern: #"(?i)\bRIR\b\s*[:\-]?\s*(\d+(?:\.\d+)?)\b"#)
            ?? firstCapture(in: trimmed, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*RIR\b"#)
            ?? firstCapture(in: trimmed, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*reps?\s+in\s+reserve\b"#)
        let tempo = firstCapture(in: trimmed, pattern: #"(?i)\btempo\b\s*[:\-]?\s*([0-9Xx](?:\s*-\s*[0-9Xx]){3})\b"#)?
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        var cleaned = trimmed
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bweek\s*\d+\s*(light|moderate|heavy)\s+weight\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b(light|moderate|heavy)\s+weight\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bweek\s*\d+\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b(light|moderate|heavy)\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bRIR\b\s*[:\-]?\s*\d+(?:\.\d+)?\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b\d+(?:\.\d+)?\s*RIR\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b\d+(?:\.\d+)?\s*reps?\s+in\s+reserve\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\btempo\b\s*[:\-]?\s*[0-9Xx](?:\s*-\s*[0-9Xx]){3}\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\.\s*[:\-]\s*"#, with: ". ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[:\-]\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-"))

        return ExercisePrescription(
            week: week,
            intensity: intensity,
            rir: rir,
            tempo: tempo,
            cleanedNotes: cleaned
        )
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let value = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Progression Suggestion

struct RepRange {
    let low: Int
    let high: Int

    static func parse(_ reps: String) -> RepRange? {
        let cleaned = reps
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        if cleaned.contains("-") {
            let parts = cleaned.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, parts[0] > 0, parts[1] >= parts[0] else { return nil }
            return RepRange(low: parts[0], high: parts[1])
        }

        if let single = Int(cleaned), single > 0 {
            return RepRange(low: single, high: single)
        }

        return nil
    }
}

struct ProgressionSuggestion {
    let icon: String
    let text: String
    let color: Color

    /// True for cues that tell the lifter to add weight. Used so a written prescription can
    /// veto a generic "add load" cue that would contradict it.
    var increasesLoad: Bool { icon == "arrow.up.circle.fill" }

    /// Shown when the coaching note prescribes more working sets than have been completed
    /// (note-vs-structured drift): finish the prescription before adding weight.
    static func completePrescribedSets(_ count: Int) -> ProgressionSuggestion {
        ProgressionSuggestion(
            icon: "hand.raised.fill",
            text: "Your note prescribes \(count) sets — complete all of them at this load before adding weight",
            color: TFColor.warning
        )
    }

    /// Shown on deload days in place of a load-progression cue: the block is deliberately
    /// lighter, so the correct coaching is to hold back, not to add weight.
    static var deloadGuidance: ProgressionSuggestion {
        ProgressionSuggestion(
            icon: "arrow.down.right.circle.fill",
            text: "Deload week — keep load light (~10% under your last block) and leave 2–3 reps in reserve; don't chase PRs",
            color: TFColor.info
        )
    }

    static func evaluate(
        analysis: WorkingSetAnalysis,
        summaryRepsCompleted: Int?,
        repRange: RepRange,
        lastWeight: Double,
        exerciseName: String
    ) -> ProgressionSuggestion? {
        // Preferred path: reason over the genuine working sets, robust to warm-up ramps
        // and to a lone anomalous spike (which is excluded here and surfaced separately).
        if let workingWeight = analysis.workingWeight, !analysis.workingSets.isEmpty {
            return fromWorkingSets(
                workingSets: analysis.workingSets,
                workingWeight: workingWeight,
                repRange: repRange,
                exerciseName: exerciseName
            )
        }

        // Degraded path: older logs with no usable per-set data. Reason from the summary
        // alone — outliers cannot be detected without the individual sets.
        guard let repsCompleted = summaryRepsCompleted else { return nil }

        if repsCompleted >= repRange.high {
            let suggestedWeight = nextLoad(from: lastWeight, exerciseName: exerciseName)
            return ProgressionSuggestion(
                icon: "arrow.up.circle.fill",
                text: "Increase to \(formatWeight(suggestedWeight)) lb next session",
                color: TFColor.success
            )
        }

        if repsCompleted < repRange.low {
            return ProgressionSuggestion(
                icon: "arrow.down.circle.fill",
                text: "Stay at \(formatWeight(lastWeight)) lb, focus on form and full ROM",
                color: TFColor.warning
            )
        }

        return ProgressionSuggestion(
            icon: "arrow.right.circle.fill",
            text: "On track — aim for \(repsCompleted + 1)-\(repRange.high) reps next session",
            color: .blue
        )
    }

    /// Next-session target weight, derived from the working weight rather than the muscle
    /// group: heavier loads tolerate larger absolute jumps and lighter loads need smaller
    /// ones. Roughly 2.5% of the load, but the result is snapped to the smallest *real*
    /// load step for the equipment so the suggestion is always achievable. Dumbbells come
    /// in 5 lb pairs, so a 2.5 lb plate step would name an unloadable weight (e.g. 77.5 lb);
    /// dumbbell lifts therefore step — and land — on 5 lb. Everything else uses a 2.5 lb
    /// plate step. Equipment is inferred from the exercise name because the logged model
    /// carries no equipment metadata; muscle-group guessing (the old approach) was strictly
    /// worse. Returns the next weight to put on the bar/rack, not a bare increment.
    static func nextLoad(from weight: Double, exerciseName: String) -> Double {
        guard weight > 0 else { return 2.5 }
        let isDumbbell = isDumbbellLift(exerciseName)
        let step: Double = isDumbbell ? 5.0 : 2.5
        let rawJump = max(weight * 0.025, step)
        let cappedJump = min(rawJump, isDumbbell ? 15.0 : 10.0)
        let target = weight + cappedJump
        // Snap to the nearest real step so the named weight actually exists on the rack.
        return (target / step).rounded() * step
    }

    /// True when the exercise is performed with dumbbells, inferred from its name.
    /// Matches the canonical "dumbbell" token and the "DB" abbreviation as a whole word
    /// so substrings (e.g. "abductor") never trigger a false positive.
    static func isDumbbellLift(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.contains("dumbbell") { return true }
        let tokens = lowered.split { !$0.isLetter }
        return tokens.contains("db")
    }

    /// Decide the next step from the genuine working sets only. Recommendations name the
    /// working weight so the advice is self-explanatory, and a single failed set blocks a
    /// load increase even when the top set looked strong.
    private static func fromWorkingSets(
        workingSets: [WorkingSetAnalysis.AnalyzedSet],
        workingWeight: Double,
        repRange: RepRange,
        exerciseName: String
    ) -> ProgressionSuggestion {
        let reps = workingSets.map(\.reps)
        let minReps = reps.min() ?? repRange.low
        let atCeiling = reps.filter { $0 >= repRange.high }.count
        let total = workingSets.count
        let majority = max(1, Int(ceil(Double(total) * 0.67)))
        let weightText = formatWeight(workingWeight)
        let nextText = formatWeight(nextLoad(from: workingWeight, exerciseName: exerciseName))

        // Every working set reached the rep ceiling — unambiguous green light to add load.
        if minReps >= repRange.high {
            return ProgressionSuggestion(
                icon: "arrow.up.circle.fill",
                text: "Add load — \(weightText) lb felt complete. Try \(nextText) lb next session",
                color: TFColor.success
            )
        }

        // A working set fell below the target floor. Hold and even the sets out before
        // adding weight, even if another set hit the top (this is the Romanian Deadlift
        // case: 90 lb sets of 10 / 5 / 10 should not read as "stay at 180").
        if minReps < repRange.low {
            return ProgressionSuggestion(
                icon: "arrow.down.circle.fill",
                text: "Hold \(weightText) lb — a working set dropped to \(minReps) (target \(repRange.low)-\(repRange.high)); even your sets out before adding",
                color: TFColor.warning
            )
        }

        // All working sets in range, and the majority maxed the ceiling — ready to add.
        if atCeiling >= majority {
            return ProgressionSuggestion(
                icon: "arrow.up.circle.fill",
                text: "Add load — \(atCeiling) of \(total) sets hit \(repRange.high) at \(weightText) lb. Try \(nextText) lb next session",
                color: TFColor.success
            )
        }

        // In range with a strong top set, but not yet consistent — build the rest up first.
        if atCeiling > 0 {
            let needed = majority - atCeiling
            return ProgressionSuggestion(
                icon: "flame.fill",
                text: "Strong top set at \(weightText) lb — hit \(repRange.high) on \(needed) more set\(needed == 1 ? "" : "s") before adding",
                color: TFColor.accent
            )
        }

        // All sets in range, none at the ceiling — keep the load and chase the top rep.
        return ProgressionSuggestion(
            icon: "arrow.right.circle.fill",
            text: "On track at \(weightText) lb — build all sets to \(repRange.high) reps (lowest was \(minReps))",
            color: TFColor.info
        )
    }

}

struct ProgressionSuggestionBadge: View {
    let suggestion: ProgressionSuggestion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: suggestion.icon)
                .font(.caption2)
                .foregroundStyle(suggestion.color)
            Text(suggestion.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(suggestion.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SetAnomalyNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(TFColor.warning)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TFColor.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Set Logging Service

/// Incremental, session-aware set logging. A "session" is a single
/// `ExercisePerformanceLog` for one exercise, scoped to one calendar day *and* one
/// program day (`WorkoutDay.dayNumber`) so a same-named exercise on a different day —
/// or stray same-day data — never shows up as the current card's progress. Inline
/// set-by-set logging and the bulk sheet both funnel through here so they share one log
/// per session instead of fragmenting it — which would skew the summary, the personal
/// best, and the anomaly analysis. The "previous session" lookup deliberately stays
/// cross-day so progression continuity tracks the exercise across the whole program.
///
/// Reads take a `@Query`-backed array (reactive UI). Writes fetch fresh from the
/// context so two quick taps cannot create a duplicate session log before the query
/// republishes.
@MainActor
enum SetLoggingService {

    // MARK: Reads (from a query-backed array)

    static func todaysSets(
        for exercise: WorkoutExercise,
        in logs: [ExercisePerformanceLog],
        on date: Date = .now
    ) -> [SetLogEntry] {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let dayNumber = exercise.day?.dayNumber ?? 0
        let cal = Calendar.current
        let log = logs.first {
            $0.canonicalExerciseKey == key
                && $0.workoutDayNumber == dayNumber
                && cal.isDate($0.loggedAt, inSameDayAs: date)
        }
        return (log?.decodedSetLogs ?? []).sorted { $0.setNumber < $1.setNumber }
    }

    /// Most recent completed session strictly before `date` — used for the "last
    /// session" panel and the progression suggestion (which targets the next session).
    static func previousSets(
        for exercise: WorkoutExercise,
        in logs: [ExercisePerformanceLog],
        on date: Date = .now
    ) -> [SetLogEntry] {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let cal = Calendar.current
        let prior = logs
            .filter { $0.canonicalExerciseKey == key && !$0.setLogsJSON.isEmpty && !cal.isDate($0.loggedAt, inSameDayAs: date) }
            .max { $0.loggedAt < $1.loggedAt }
        return (prior?.decodedSetLogs ?? []).sorted { $0.setNumber < $1.setNumber }
    }

    // MARK: Writes (fetch fresh, then persist)

    @discardableResult
    static func logSet(
        setNumber: Int,
        weightLbs: Double,
        reps: Int,
        for exercise: WorkoutExercise,
        modelContext: ModelContext,
        on date: Date = .now
    ) -> Bool {
        guard weightLbs > 0, reps > 0 else { return false }
        let log = todaysLogOrCreate(for: exercise, modelContext: modelContext, date: date)
        var sets = log.decodedSetLogs.filter { $0.setNumber != setNumber }
        sets.append(SetLogEntry(setNumber: setNumber, weightLbs: weightLbs, repsCompleted: reps))
        return apply(sets.sorted { $0.setNumber < $1.setNumber }, to: log, exercise: exercise, modelContext: modelContext, date: date)
    }

    @discardableResult
    static func clearSet(
        setNumber: Int,
        for exercise: WorkoutExercise,
        modelContext: ModelContext,
        on date: Date = .now
    ) -> Bool {
        guard let log = todaysLog(for: exercise, modelContext: modelContext, date: date) else { return true }
        let sets = log.decodedSetLogs.filter { $0.setNumber != setNumber }.sorted { $0.setNumber < $1.setNumber }
        if sets.isEmpty {
            modelContext.delete(log)
            return persist(modelContext)
        }
        return apply(sets, to: log, exercise: exercise, modelContext: modelContext, date: date)
    }

    /// Replace today's session with a full set list (the bulk sheet's save path).
    @discardableResult
    static func replaceTodaysSets(
        _ sets: [SetLogEntry],
        for exercise: WorkoutExercise,
        modelContext: ModelContext,
        on date: Date = .now
    ) -> Bool {
        guard !sets.isEmpty else { return clearAllToday(for: exercise, modelContext: modelContext, date: date) }
        let log = todaysLogOrCreate(for: exercise, modelContext: modelContext, date: date)
        return apply(sets.sorted { $0.setNumber < $1.setNumber }, to: log, exercise: exercise, modelContext: modelContext, date: date)
    }

    // MARK: Internals

    private static func clearAllToday(for exercise: WorkoutExercise, modelContext: ModelContext, date: Date) -> Bool {
        if let log = todaysLog(for: exercise, modelContext: modelContext, date: date) {
            modelContext.delete(log)
        }
        return persist(modelContext)
    }

    private static func todaysLog(for exercise: WorkoutExercise, modelContext: ModelContext, date: Date) -> ExercisePerformanceLog? {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let dayNumber = exercise.day?.dayNumber ?? 0
        let descriptor = FetchDescriptor<ExercisePerformanceLog>(
            predicate: #Predicate { $0.canonicalExerciseKey == key && $0.workoutDayNumber == dayNumber }
        )
        let logs = (try? modelContext.fetch(descriptor)) ?? []
        let cal = Calendar.current
        return logs.first { cal.isDate($0.loggedAt, inSameDayAs: date) }
    }

    private static func todaysLogOrCreate(for exercise: WorkoutExercise, modelContext: ModelContext, date: Date) -> ExercisePerformanceLog {
        if let existing = todaysLog(for: exercise, modelContext: modelContext, date: date) { return existing }
        let log = ExercisePerformanceLog(
            loggedAt: date,
            exerciseName: exercise.exerciseName,
            weightLbs: 0,
            repsCompleted: nil,
            muscleTarget: exercise.muscleTarget,
            workoutDayNumber: exercise.day?.dayNumber ?? 0
        )
        modelContext.insert(log)
        return log
    }

    private static func summaryEntryOrCreate(for exercise: WorkoutExercise, weight: Double, reps: Int?, date: Date, modelContext: ModelContext) -> ExerciseWeightEntry {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let descriptor = FetchDescriptor<ExerciseWeightEntry>(predicate: #Predicate { $0.canonicalExerciseKey == key })
        if let existing = (try? modelContext.fetch(descriptor))?.max(by: { $0.loggedAt < $1.loggedAt }) {
            return existing
        }
        let entry = ExerciseWeightEntry(loggedAt: date, exerciseName: exercise.exerciseName, weightLbs: weight, repsCompleted: reps)
        modelContext.insert(entry)
        return entry
    }

    private static func apply(
        _ sets: [SetLogEntry],
        to log: ExercisePerformanceLog,
        exercise: WorkoutExercise,
        modelContext: ModelContext,
        date: Date
    ) -> Bool {
        // Summary / best come from the qualified working set so an anomalous entry never
        // becomes a false PR; raw per-set data is preserved on the log.
        let top = WorkingSetAnalysis.summaryTop(from: sets)
        let topWeight = top?.weightLbs ?? sets.first?.weightLbs ?? 0
        let topReps = top?.reps

        log.loggedAt = date
        log.weightLbs = topWeight
        log.repsCompleted = topReps
        log.setLogsJSON = ExercisePerformanceLog.encodeSetLogs(sets)

        let summary = summaryEntryOrCreate(for: exercise, weight: topWeight, reps: topReps, date: date, modelContext: modelContext)
        summary.applyLog(loggedAt: date, exerciseName: exercise.exerciseName, weightLbs: topWeight, repsCompleted: topReps, notes: summary.notes)

        return persist(modelContext)
    }

    private static func persist(_ modelContext: ModelContext) -> Bool {
        guard PersistenceReporter.save(modelContext, operation: "inline set logging") else {
            modelContext.rollback()
            TFHaptics.error()
            return false
        }
        // The SwiftData save above is durable. The automatic backup is a full export
        // (photos + all data), so coalesce it: logging set-by-set during a workout must
        // not trigger one heavy export per tap. The recovery snapshot tolerates a short lag.
        DataBackupManager.shared.writeAutomaticBackupCoalesced(using: modelContext)
        return true
    }
}

// MARK: - Inline Set Logger

/// Compact, collapsed-by-default set tracker shown on each exercise card. Expands to
/// exactly the programmed number of set rows. Unlogged rows are pre-filled (working
/// weight + target reps, chaining off the last set logged), so a set is usually one tap
/// to confirm. Each confirm/clear persists immediately into today's session.
struct InlineSetLogger: View {
    let exercise: WorkoutExercise
    let loggedSets: [SetLogEntry]
    let suggestedWeight: Double?
    let suggestedReps: Int?
    let onLog: (Int, Double, Int) -> Void
    let onClear: (Int) -> Void

    @State private var expanded = false
    @State private var editing: Set<Int> = []
    @State private var draftWeight: [Int: String] = [:]
    @State private var draftReps: [Int: String] = [:]
    @FocusState private var focusedField: FieldKey?

    enum FieldKey: Hashable {
        case weight(Int)
        case reps(Int)
    }

    private var programmedCount: Int {
        max(exercise.sets, loggedSets.map(\.setNumber).max() ?? 0, 1)
    }

    private var loggedCount: Int { loggedSets.count }
    private var allLogged: Bool { loggedCount >= programmedCount }

    private func loggedSet(_ n: Int) -> SetLogEntry? {
        loggedSets.first { $0.setNumber == n }
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            if expanded {
                VStack(spacing: 6) {
                    ForEach(1...programmedCount, id: \.self) { n in
                        setRow(n)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.caption.bold())
                    .foregroundStyle(TFColor.accent)
                Text("Log sets")
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text("\(loggedCount)/\(programmedCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background((allLogged ? TFColor.success : TFColor.accent).opacity(0.15))
                    .foregroundStyle(allLogged ? TFColor.success : TFColor.accent)
                    .clipShape(Capsule())
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log sets, \(loggedCount) of \(programmedCount) logged")
        .accessibilityHint(expanded ? "Collapses the set logger" : "Expands the set logger")
    }

    @ViewBuilder
    private func setRow(_ n: Int) -> some View {
        if let logged = loggedSet(n), !editing.contains(n) {
            loggedRow(n, logged)
        } else {
            entryRow(n)
        }
    }

    private func loggedRow(_ n: Int, _ set: SetLogEntry) -> some View {
        HStack(spacing: 8) {
            setLabel(n)
            Text("\(formatWeight(set.weightLbs)) lb")
                .font(.caption.bold())
            Text("\u{00D7}").font(.caption2).foregroundStyle(.tertiary)
            Text("\(set.repsCompleted) reps").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                draftWeight[n] = formatWeight(set.weightLbs)
                draftReps[n] = "\(set.repsCompleted)"
                editing.insert(n)
            } label: {
                Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit set \(n)")
            Button {
                onClear(n)
                resetDraft(n)
            } label: {
                Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear set \(n)")
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(TFColor.success)
        }
    }

    private func entryRow(_ n: Int) -> some View {
        HStack(spacing: 8) {
            setLabel(n)
            field(text: weightBinding(n), placeholder: "lb", key: .weight(n), isReps: false, width: 54)
            Text("\u{00D7}").font(.caption2).foregroundStyle(.tertiary)
            field(text: repsBinding(n), placeholder: "reps", key: .reps(n), isReps: true, width: 44)
            Spacer()
            Button {
                logRow(n)
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(canLog(n) ? AnyShapeStyle(TFColor.accent) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .disabled(!canLog(n))
            .accessibilityLabel("Log set \(n)")
        }
    }

    private func setLabel(_ n: Int) -> some View {
        Text("Set \(n)")
            .font(.caption2.bold())
            .foregroundStyle(TFColor.accent)
            .frame(width: 38, alignment: .leading)
    }

    private func field(text: Binding<String>, placeholder: String, key: FieldKey, isReps: Bool, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(isReps ? .numberPad : .decimalPad)
            .focused($focusedField, equals: key)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 6)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Drafts & parsing

    private func defaultWeightText() -> String {
        if let w = loggedSets.last?.weightLbs ?? suggestedWeight, w > 0 { return formatWeight(w) }
        return ""
    }

    private func defaultRepsText() -> String {
        if let r = loggedSets.last?.repsCompleted ?? suggestedReps, r > 0 { return "\(r)" }
        return ""
    }

    private func weightBinding(_ n: Int) -> Binding<String> {
        Binding(get: { draftWeight[n] ?? defaultWeightText() }, set: { draftWeight[n] = $0 })
    }

    private func repsBinding(_ n: Int) -> Binding<String> {
        Binding(get: { draftReps[n] ?? defaultRepsText() }, set: { draftReps[n] = $0 })
    }

    private func parsedWeight(_ n: Int) -> Double? {
        let t = (draftWeight[n] ?? defaultWeightText())
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), v > 0 else { return nil }
        return v
    }

    private func parsedReps(_ n: Int) -> Int? {
        let t = (draftReps[n] ?? defaultRepsText()).trimmingCharacters(in: .whitespaces)
        guard let v = Int(t), v > 0 else { return nil }
        return v
    }

    private func canLog(_ n: Int) -> Bool {
        parsedWeight(n) != nil && parsedReps(n) != nil
    }

    private func logRow(_ n: Int) {
        guard let w = parsedWeight(n), let r = parsedReps(n) else { return }
        focusedField = nil
        editing.remove(n)
        TFHaptics.impact(.light)
        onLog(n, w, r)
    }

    private func resetDraft(_ n: Int) {
        draftWeight[n] = nil
        draftReps[n] = nil
        editing.remove(n)
    }

}
