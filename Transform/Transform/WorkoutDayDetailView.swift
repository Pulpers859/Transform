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
    /// Which exercise cards are open. Manual open/close is authoritative; the one-time
    /// seed (see `seedExpansionIfNeeded`) opens only the current lift so a finished or
    /// returning day lands collapsed and calm.
    @State private var expandedExerciseIDs: Set<PersistentIdentifier> = []
    /// Guards the one-time default so re-appearing (returning from a pushed Progression
    /// view) never re-collapses cards the lifter opened by hand.
    @State private var didSeedExpansion = false

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
                sessionTimingBadge
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
        // The default soft scroll edge leaves card text readable straight through the
        // inline nav title on this dark theme; the hard edge keeps the bar legible.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .workoutTabBarClearance()
        .onAppear { seedExpansionIfNeeded() }
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
            partialCompletionPromptTitle,
            isPresented: Binding(
                get: { completionPromptExercise != nil },
                set: { isPresented in
                    if !isPresented {
                        completionPromptExercise = nil
                    }
                }
            )
        ) {
            Button("Log Missing Set", role: .cancel) {
                if let exercise = completionPromptExercise {
                    exerciseForWeightLogging = exercise
                }
                completionPromptExercise = nil
            }
            Button(partialCompletionActionLabel) {
                if let exercise = completionPromptExercise {
                    completeExerciseAsModified(exercise)
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

    // MARK: - Session Timing

    /// Auto-tracking clock. Once the first set is logged the session start is stamped
    /// automatically (see SetLoggingService.stampSessionTiming) and this shows a live
    /// running duration. Before any set exists it offers an optional manual start for
    /// athletes who want a long warm-up counted — but starting is never required.
    @ViewBuilder
    var sessionTimingBadge: some View {
        if !day.isCompleted {
            if let start = day.sessionStartedAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let minutes = max(0, Int(context.date.timeIntervalSince(start) / 60))
                    HStack(spacing: 8) {
                        Image(systemName: "stopwatch")
                            .font(.caption.bold())
                            .foregroundStyle(TFColor.accent)
                        Text("Session in progress")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(start.formatted(date: .omitted, time: .shortened)) · \(minutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(TFColor.accent.opacity(0.10))
                    .clipShape(Capsule())
                }
            } else {
                Button(action: startSessionManually) {
                    HStack(spacing: 8) {
                        Image(systemName: "stopwatch")
                            .font(.caption.bold())
                        Text("Start session timer")
                            .font(.caption.bold())
                        Spacer()
                        Text("or just log your first set")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(TFColor.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(TFColor.accent.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start session timer")
            }
        }
    }

    private func startSessionManually() {
        guard day.sessionStartedAt == nil else { return }
        // End is left nil so a started-but-unlogged session still defaults its finish to
        // "now" in the feedback sheet; the first logged set stamps the real end.
        day.sessionStartedAt = .now
        TFHaptics.impact(.light)
        guard PersistenceReporter.save(modelContext, operation: "manual session start") else {
            modelContext.rollback()
            return
        }
        TFHaptics.success()
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
                    Text(sessionFeedbackSubtitle)
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

    /// Duration first (it's the auto-tracked highlight), then ratings or the prompt.
    private var sessionFeedbackSubtitle: String {
        let durationPrefix = day.sessionDurationMinutes.map { "\($0) min · " } ?? ""
        let body = day.hasSessionFeedback
            ? "Effort \(day.sessionEffort)/5 · Stimulus \(day.stimulusQuality)/5 · Pain \(day.jointPain)/5 · \(day.performanceRating?.rawValue ?? "Not rated")"
            : "Four quick ratings help calibrate next week."
        return durationPrefix + body
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
                    performanceHistory: performanceLogSnapshots,
                    isExpanded: expandedExerciseIDs.contains(exercise.persistentModelID),
                    onToggle: { toggleExercise(exercise) },
                    onToggleExpanded: { toggleExpanded(exercise) },
                    onLogWeight: { exerciseForWeightLogging = exercise }
                )
            }
        }
    }

    /// Opens only the current lift (the first not-yet-completed exercise) on first load,
    /// so a finished or returning day stays collapsed. Runs once per view lifetime; every
    /// manual open/close afterward wins.
    private func seedExpansionIfNeeded() {
        guard !didSeedExpansion else { return }
        didSeedExpansion = true
        if let current = day.sortedExercises.first(where: { !$0.isCompleted }) {
            expandedExerciseIDs = [current.persistentModelID]
        } else {
            expandedExerciseIDs = []
        }
    }

    private func toggleExpanded(_ exercise: WorkoutExercise) {
        let id = exercise.persistentModelID
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedExerciseIDs.contains(id) {
                expandedExerciseIDs.remove(id)
            } else {
                expandedExerciseIDs.insert(id)
            }
        }
    }

    var partialCompletionPromptTitle: String {
        guard let exercise = completionPromptExercise else {
            return "Finish as modified?"
        }
        let logged = todaysSetLogs(for: exercise).count
        return logged > 0 ? "Finish \(logged)/\(exercise.sets) sets?" : "Complete without logged sets?"
    }

    var partialCompletionActionLabel: String {
        guard let exercise = completionPromptExercise else {
            return "Finish Modified"
        }
        let logged = todaysSetLogs(for: exercise).count
        return logged > 0 ? "Finish \(logged)/\(exercise.sets)" : "Finish Modified"
    }

    var completionPromptMessage: String {
        guard let exercise = completionPromptExercise else {
            return "Logging sets improves future progression cues."
        }
        let logged = todaysSetLogs(for: exercise).count
        if logged > 0 {
            return "\(logged) of \(exercise.sets) planned sets are logged. This marks the exercise as Modified; progression will use only the sets you actually logged."
        }
        return "No sets are logged yet. This marks the exercise as Modified and does not create any fake reps or volume."
    }

    func toggleExercise(_ exercise: WorkoutExercise) {
        if !exercise.isCompleted, exercise.sets > 0 {
            let logged = todaysSetLogs(for: exercise).count
            if logged < exercise.sets {
                completionPromptExercise = exercise
                TFHaptics.impact(.soft)
                return
            }
        }

        let previousExerciseState = exercise.isCompleted
        let previousDayState = day.isCompleted
        let previousStatus = exercise.completionStatus
        exercise.isCompleted.toggle()
        if !exercise.isCompleted && previousStatus == .completedModified {
            exercise.completionStatus = nil
        }

        let allDone = day.exercises.allSatisfy { $0.isCompleted }
        if allDone != day.isCompleted {
            day.isCompleted = allDone
        }

        guard PersistenceReporter.save(modelContext, operation: "exercise completion toggle") else {
            modelContext.rollback()
            exercise.isCompleted = previousExerciseState
            exercise.completionStatus = previousStatus
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

    func completeExerciseAsModified(_ exercise: WorkoutExercise) {
        let previousExerciseState = exercise.isCompleted
        let previousDayState = day.isCompleted
        let previousStatus = exercise.completionStatus

        exercise.isCompleted = true
        exercise.completionStatus = .completedModified

        let allDone = day.exercises.allSatisfy { $0.isCompleted }
        if allDone != day.isCompleted {
            day.isCompleted = allDone
        }

        guard PersistenceReporter.save(modelContext, operation: "exercise modified completion") else {
            modelContext.rollback()
            exercise.isCompleted = previousExerciseState
            exercise.completionStatus = previousStatus
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

    var performanceLogSnapshots: [WorkoutPerformanceLogSnapshot] {
        allPerformanceLogs.map {
            WorkoutPerformanceLogSnapshot(
                canonicalExerciseKey: $0.canonicalExerciseKey,
                loggedAt: $0.loggedAt,
                setLogs: $0.decodedSetLogs
            )
        }
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
    /// All decoded performance sessions, used for the exercise-specific effort signal.
    let performanceHistory: [WorkoutPerformanceLogSnapshot]
    /// Whether this card is open. Ownership lives in the parent so the default (only the
    /// current lift open) can reason across exercises; the card just renders the state.
    let isExpanded: Bool
    let onToggle: () -> Void
    let onToggleExpanded: () -> Void
    let onLogWeight: () -> Void
    @State private var showDetails = false

    var latestWeightLog: ExerciseWeightEntry? {
        weightSummary
    }

    var bestWeightText: String? {
        guard let latestWeightLog else { return nil }
        let bestWeight = latestWeightLog.hasBestRecord ? latestWeightLog.bestWeightLbs : latestWeightLog.weightLbs
        return formatLoad(bestWeight)
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

    /// Previous-session analysis. Drives set-log PREFILL (chain the next set off last
    /// session's working load) and the "Last" panel. Deliberately NOT today's — prefilling
    /// from a set you just logged would fight the live draft chaining in InlineSetLogger.
    var workingSetAnalysis: WorkingSetAnalysis {
        WorkingSetAnalysis.analyze(latestSetLogs)
    }

    /// The session the progression cue and anomaly check must reason about: today's logged
    /// sets the instant they exist, otherwise the previous completed session. Progression
    /// answers "what next time," so once today is logged it MUST reflect today — not keep
    /// coaching off a session you've already beaten (the live bug: a 135 lb × 15 set that
    /// was told to "try 105 lb next session" because the cue was frozen on last week's 100).
    var progressionReferenceSets: [SetLogEntry] {
        todaysSetLogs.isEmpty ? latestSetLogs : todaysSetLogs
    }

    var progressionAnalysis: WorkingSetAnalysis {
        WorkingSetAnalysis.analyze(progressionReferenceSets)
    }

    /// Cross-session sanity check on the just-logged session. The intra-session anomaly
    /// detector needs 3+ sets to establish a center, so single-set isolation work (a rear-
    /// delt machine, a raise) has NOTHING guarding a fat-fingered entry — and that entry
    /// silently becomes the Best and the next progression baseline. Compare today's working
    /// load with last session's: an implausible one-week jump earns a soft "confirm or fix"
    /// (it never blocks). The ~10 lb floor keeps tiny-weight ratios (5→10) from over-firing;
    /// a ≥25% single-session jump is far beyond any step the engine would ever recommend.
    var historicalLoadAnomaly: (setNumber: Int, weight: Double, reference: Double)? {
        let today = WorkingSetAnalysis.analyze(todaysSetLogs)
        guard let todayWeight = today.workingWeight, todayWeight > 0,
              let top = today.topWorkingSet else { return nil }
        let prior = WorkingSetAnalysis.analyze(latestSetLogs)
        guard let priorWeight = prior.workingWeight, priorWeight > 0 else { return nil }
        guard todayWeight >= priorWeight * 1.25, todayWeight - priorWeight >= 10 else { return nil }
        return (top.setNumber, todayWeight, priorWeight)
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
        let kept = coachingSentences(
            from: note,
            hideProgressionCue: hideProgressionCue,
            hideDeloadCue: hideDeloadCue
        ).prefix(3)

        let compact = kept.joined(separator: " ")
        if compact.count > 420 {
            // Cut on a word boundary, never mid-word.
            let hard = compact.prefix(417)
            let wordSafe = (hard.lastIndex(of: " ").map { String(hard[..<$0]) } ?? String(hard))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(wordSafe)…"
        }
        return tidyTrailingFragment(compact)
    }

    /// Defends the cue against a coaching note stored truncated mid-thought (seen live:
    /// "…chase reps first at"). A well-formed note ends in . ! or ? and is returned
    /// untouched; only text that trails off with no terminal punctuation AND ends on a
    /// connector/preposition gets its dangling tail trimmed so the card never renders a
    /// broken half-sentence. The real fix for the truncated DATA is regenerating the
    /// program (generator/parsing layer) — this just stops it from LOOKING broken.
    private func tidyTrailingFragment(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, !".!?".contains(last) else { return trimmed }
        let danglers: Set<String> = [
            "at", "the", "a", "an", "and", "or", "to", "of", "for", "with", "in", "on",
            "before", "after", "then", "than", "as", "by", "up", "your", "you", "is",
            "are", "this", "that", "into", "from", "toward", "so", "but"
        ]
        func tailWord(_ words: [String]) -> String? {
            words.last?.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        }
        var words = trimmed.split(separator: " ").map(String.init)
        guard let tail = tailWord(words), danglers.contains(tail) else { return trimmed }
        while let tail = tailWord(words), danglers.contains(tail) { words.removeLast() }
        let rebuilt = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return rebuilt.isEmpty ? trimmed : "\(rebuilt)…"
    }

    /// Full-length variant for the expanded Details view: same sentence filtering as the
    /// collapsed cue, no sentence cap. The deterministic progression banner owns load/rep
    /// advice, so an AI progression sentence surviving here can sit directly under a
    /// banner saying the opposite (seen live: "hold 70 lb" under an "Add load" banner
    /// after 3x14 beat a 10-12 prescription).
    private func detailedWorkoutInsight(
        from note: String,
        hideProgressionCue: Bool,
        hideDeloadCue: Bool
    ) -> String {
        tidyTrailingFragment(
            coachingSentences(
                from: note,
                hideProgressionCue: hideProgressionCue,
                hideDeloadCue: hideDeloadCue
            ).joined(separator: " ")
        )
    }

    private func coachingSentences(
        from note: String,
        hideProgressionCue: Bool,
        hideDeloadCue: Bool
    ) -> [String] {
        let sentences = splitSentences(note)
        guard !sentences.isEmpty else { return [] }

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
                "before loading", "progression", "progress load", "hold load", "increase to",
                // Phrasings seen shipping past this filter while a live banner said
                // the opposite: "add ankle weight or a dumbbell", "then a 5 lb stack
                // step", "add a rep before adding a barbell step", "log a load you
                // can reliably progress", "when you clear 15 clean reps".
                "ankle weight", "add a dumbbell", "add a rep", "stack step",
                "barbell step", "reliably progress", "when you clear", "add a plate",
                "external load", "next week add",
                // Load/rep-advance phrasings the structured ProgressionSuggestionBadge
                // already owns, seen duplicated in the Cue ("move up to 105", "chase reps
                // first", "go heavier"). Kept deliberately load-specific: bare "move to",
                // "bump", and "keep the load" are excluded because they also match
                // technique cues ("move to a staggered stance", "bump your chest up",
                // "keep the load on your lats").
                "move up to", "go up to", "go heavier", "bump the load", "bump to", "chase reps"
               ]) {
                continue
            }

            // Last-session performance recaps: the Last panel and the progression badge
            // already show what you did, so narrating it again never belongs in the
            // execution Cue ("You beat 100 lb x15 — move to 105 lb" was shipping in both).
            if containsAny(normalized, [
                "you logged", "you used", "your last session", "last time you",
                "you beat"
            ]) {
                continue
            }

            let key = normalized
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(key).inserted else { continue }

            kept.append(sentence)
        }

        return kept
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
            analysis: progressionAnalysis,
            summaryRepsCompleted: log.repsCompleted,
            repRange: repRange,
            lastWeight: log.weightLbs,
            exerciseName: exercise.exerciseName,
            performanceHistory: performanceHistory
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

    var detailedCoachingNote: String {
        detailedWorkoutInsight(
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

    /// Structured target RIR when generation provided it; prose-parsed fallback for
    /// programs generated before the structured field existed.
    var displayTargetRIR: String? {
        if let structured = exercise.targetRIR { return String(structured) }
        return parsedPrescription?.rir
    }

    var prescriptionItems: [ExercisePrescriptionPillData] {
        var items = [
            ExercisePrescriptionPillData(icon: "square.stack.3d.up", label: setsLabel(exercise.sets)),
            ExercisePrescriptionPillData(icon: "arrow.up.arrow.down", label: "\(exercise.reps) reps")
        ]
        if let tempo = displayTempo {
            items.append(ExercisePrescriptionPillData(icon: "metronome", label: "Tempo \(tempo)"))
        }
        if let rir = displayTargetRIR {
            items.append(ExercisePrescriptionPillData(icon: "gauge", label: "RIR \(rir)"))
        }
        return items
    }

    var compactLastSessionText: String? {
        guard !latestSetLogs.isEmpty else {
            guard let latestWeightLog else { return nil }
            var text = formatLoad(latestWeightLog.weightLbs)
            if let reps = latestWeightLog.repsCompleted {
                text += " x \(reps)"
            }
            return text
        }

        let compactSets = workingSetAnalysis.workingSets
        if let first = compactSets.first,
           compactSets.allSatisfy({ abs($0.weightLbs - first.weightLbs) < 0.05 }) {
            let reps = compactSets.map { "\($0.reps)" }.joined(separator: ", ")
            return "\(formatLoad(first.weightLbs)) x \(reps)"
        }

        if !compactSets.isEmpty {
            return compactSets
                .map { "\(compactLoad($0.weightLbs))x\($0.reps)" }
                .joined(separator: ", ")
        }

        return latestSetLogs
            .map { "\(compactLoad($0.weightLbs))x\($0.repsCompleted)" }
            .joined(separator: ", ")
    }

    /// Shorthand load for dense set lists: "BW" or the bare number ("90x12").
    private func compactLoad(_ weightLbs: Double) -> String {
        WorkoutProgressionEngine.isBodyweightEquivalent(weightLbs) ? "BW" : formatWeight(weightLbs)
    }

    var compactBestText: String? {
        guard let bestWeightText else { return nil }
        if let bestRepsTileText {
            return "\(bestWeightText) · \(bestRepsTileText)"
        }
        return bestWeightText
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                collapsedRow
            }
        }
        .background(exercise.isCompleted ? TFColor.success.opacity(0.05) : TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(exercise.isCompleted ? TFColor.success.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    /// Closed state, per the owner's spec: exercise name + prescription (`3×8-12`) only.
    /// The green fill (from `body`) is the "completed" signal, so nothing else competes
    /// here. The whole row is the tap target — a forgiving hit area for a sweaty gym thumb.
    private var collapsedRow: some View {
        HStack(spacing: 12) {
            Text(exercise.exerciseName)
                .font(.subheadline.bold())
                .foregroundStyle(exercise.isCompleted ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Text(compactPrescription)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { onToggleExpanded() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.exerciseName), \(compactPrescription)")
        .accessibilityHint("Double tap to expand")
    }

    /// Sets by rep range and nothing more — "3×8-12". Falls back to a bare set count if a
    /// program somehow has no rep string.
    private var compactPrescription: String {
        exercise.reps.isEmpty ? "\(exercise.sets) sets" : "\(exercise.sets)×\(exercise.reps)"
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            exerciseHeader

            VStack(alignment: .leading, spacing: 10) {
                ExercisePrescriptionPillRow(items: prescriptionItems)

                // A finished exercise has no rest left to run — hide the timer band. It
                // still shows through the last set (completion is a separate, explicit
                // toggle, so logging the final set does not flip isCompleted on its own).
                if exercise.restSeconds > 0 && !exercise.isCompleted {
                    ExerciseRestTimerView(exercise: exercise)
                }

                InlineSetLogger(
                    exercise: exercise,
                    loggedSets: todaysSetLogs,
                    suggestedWeight: workingSetAnalysis.workingWeight,
                    suggestedReps: workingSetAnalysis.topWorkingSet?.reps,
                    targetRepsPlaceholder: RepRange.parse(exercise.reps)?.high,
                    onLog: { setNumber, weight, reps, rir in
                        if SetLoggingService.logSet(setNumber: setNumber, weightLbs: weight, reps: reps, rir: rir, for: exercise, modelContext: modelContext) {
                            // A finished set is when rest begins — start the timer
                            // without a second tap (the rest card can still pause/reset).
                            NotificationCenter.default.post(
                                name: .tfWorkoutSetLogged,
                                object: exercise.persistentModelID
                            )
                        }
                    },
                    onClear: { setNumber in
                        SetLoggingService.clearSet(setNumber: setNumber, for: exercise, modelContext: modelContext)
                    }
                )

                if let compactLastSessionText {
                    LastSessionCompactRow(
                        summary: compactLastSessionText,
                        best: compactBestText
                    )
                }

                if let suggestion = progressionSuggestion {
                    ProgressionSuggestionBadge(suggestion: suggestion)
                }

                if let anomaly = progressionAnalysis.anomalies.first {
                    let reference = progressionAnalysis.workingWeight ?? anomaly.weightLbs
                    SetAnomalyNotice(
                        text: "Check Set \(anomaly.setNumber): \(formatLoad(anomaly.weightLbs)) is well above your \(formatLoad(reference)) working sets. Confirm or fix the entry — it isn't used for progression."
                    )
                } else if let hist = historicalLoadAnomaly {
                    SetAnomalyNotice(
                        text: "Check Set \(hist.setNumber): \(formatLoad(hist.weight)) is a big jump from last session's \(formatLoad(hist.reference)). Confirm it — a mis-log here would set a false best and skew your next target."
                    )
                }

                if !conciseCoachingNote.isEmpty {
                    // Expanded view gets the filtered full note, not the raw one: the raw
                    // note can carry a generation-time progression cue that contradicts
                    // the live ProgressionSuggestion banner rendered just above.
                    CoachingInsightCard(
                        text: showDetails ? detailedCoachingNote : conciseCoachingNote,
                        isExpanded: showDetails
                    )
                }
            }
            .padding(14)

            if let status = exercise.completionStatus, status != .completed {
                completionStatusRow(status)
            }

            if showDetails {
                Divider().padding(.horizontal, 14)
                detailContent
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Divider().padding(.horizontal, 14)
            exerciseActionRow
        }
    }

    private var exerciseHeader: some View {
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
                // Completed exercises are dimmed, not struck through: a line through the
                // title reads as "deleted/cancelled," the opposite of "done." The green
                // check plus the muted color already communicate completion.
                Text(exercise.exerciseName)
                    .font(.subheadline.bold())
                    .foregroundStyle(exercise.isCompleted ? .secondary : .primary)

                if !exercise.muscleTarget.isEmpty {
                    Text(exercise.muscleTarget)
                        .font(.caption2)
                        .foregroundStyle(TFColor.accent)
                }
            }
            // Tapping the title area collapses the card (the completion circle to its left
            // is a separate Button, so it is unaffected). The caret is the visible
            // affordance; this just widens the hit area.
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpanded() }

            Spacer()

            Text("#\(exercise.order + 1)")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)

            Button {
                onToggleExpanded()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse \(exercise.exerciseName)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if parsedPrescription != nil || displayTargetRIR != nil {
                HStack(alignment: .center) {
                    if let intensity = parsedPrescription?.intensity,
                       let label = parsedPrescription?.intensityLabel {
                        Text(label)
                            .font(intensity == .light ? .caption : .caption.bold())
                            .foregroundStyle(intensity.color)
                    }

                    Spacer()

                    if let rirValue = displayTargetRIR {
                        Text("RIR \(rirValue)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !latestSetLogs.isEmpty {
                setLogBreakdown
            } else if latestWeightLog != nil {
                ExerciseWeightSnapshotTile(
                    lastWeightText: latestWeightLog.map { formatLoad($0.weightLbs) } ?? "-",
                    lastRepsText: lastRepsTileText,
                    bestWeightText: bestWeightText ?? "-",
                    bestRepsText: bestRepsTileText
                )
            }

            if let latestWeightLog,
               !latestWeightLog.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTES")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                    Text(latestWeightLog.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func completionStatusRow(_ status: ExerciseCompletionStatus) -> some View {
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

    private var exerciseActionRow: some View {
        HStack(spacing: 16) {
            Button {
                onLogWeight()
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
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

            NavigationLink {
                ExerciseProgressionView(exerciseName: exercise.exerciseName)
            } label: {
                Label("Progression", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showDetails.toggle()
                }
            } label: {
                Label(showDetails ? "Hide" : "Details", systemImage: showDetails ? "chevron.up" : "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(TFColor.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    var setLogBreakdown: some View {
        let roles = workingSetAnalysis.rolesBySetID

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
                    Text(formatLoad(set.weightLbs))
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

// MARK: - Exercise Compact Components

struct ExercisePrescriptionPillData: Identifiable {
    let icon: String
    let label: String

    var id: String { "\(icon)-\(label)" }
}

struct ExercisePrescriptionPillRow: View {
    let items: [ExercisePrescriptionPillData]

    var body: some View {
        ExercisePillFlowLayout(spacing: 7, rowSpacing: 7) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    Image(systemName: item.icon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TFColor.accent)
                    Text(item.label)
                        .font(.caption2.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ExercisePillFlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for item in arrangement.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (items: [(index: Int, origin: CGPoint, size: CGSize)], size: CGSize) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var items: [(index: Int, origin: CGPoint, size: CGSize)] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += rowHeight + rowSpacing
                rowHeight = 0
            }
            items.append((index, cursor, size))
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }

        return (items, CGSize(width: min(usedWidth, maxWidth), height: cursor.y + rowHeight))
    }
}

struct LastSessionCompactRow: View {
    let summary: String
    let best: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Last")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .tracking(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if let best {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(TFColor.warning)
                    Text("Best \(best)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }
}

struct CoachingInsightCard: View {
    let text: String
    let isExpanded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lightbulb.fill")
                .font(.caption2)
                .foregroundStyle(TFColor.warning)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(isExpanded ? "Coaching" : "Cue")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(TFColor.warning.opacity(0.8))
                    .tracking(1)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TFColor.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRestTimerActive ? "Rest running" : restStatusLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(timerAccent.opacity(0.85))
                        .tracking(1)
                    Text(restDisplayText)
                        .font(.subheadline.bold())
                        .foregroundStyle(timerAccent)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Button {
                    toggleRestTimer()
                } label: {
                    Label(isRestTimerActive ? "Pause" : (remainingRestSeconds != exercise.restSeconds ? "Resume" : "Start rest"), systemImage: isRestTimerActive ? "pause.fill" : "play.fill")
                        .font(.caption.bold())
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(timerAccent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if remainingRestSeconds != exercise.restSeconds || isRestTimerActive || didCompleteRestTimer {
                    Button {
                        resetRestTimer()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(7)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset rest timer")
                }

                Button {
                    showExpandedRestTimer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open full-screen rest timer")
            }

            if isRestTimerActive || remainingRestSeconds != exercise.restSeconds || didCompleteRestTimer {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(timerAccent.opacity(0.14))
                        Capsule()
                            .fill(timerAccent)
                            .frame(width: geo.size.width * max(0, min(restProgress, 1)))
                    }
                }
                .frame(height: 5)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(timerAccent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
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
        .onDisappear {
            if !showExpandedRestTimer {
                stopRestTimer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tfWorkoutSetLogged)) { note in
            // A confirmed set means a fresh rest period starts now — no second tap.
            // Restarts from full even if a previous countdown was mid-flight.
            guard let id = note.object as? PersistentIdentifier,
                  id == exercise.persistentModelID else { return }
            didCompleteRestTimer = false
            remainingRestSeconds = exercise.restSeconds
            restEndDate = Date().addingTimeInterval(Double(remainingRestSeconds))
            isRestTimerActive = true
            startRestTimer()
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
    /// Optional: many generated notes carry RIR/tempo without an intensity word.
    /// The parse used to bail entirely without one, which silently discarded a
    /// perfectly parseable "2 RIR" (seen live: Back Squat had no RIR chip while
    /// Hanging Knee Raise did).
    let intensity: WorkoutIntensity?
    let rir: String?
    let tempo: String?
    let cleanedNotes: String

    var intensityLabel: String? {
        guard let intensity else { return nil }
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

        let intensity = firstCapture(in: trimmed, pattern: #"(?i)\b(light|moderate|heavy)\b"#)
            .flatMap { WorkoutIntensity(rawValue: $0.lowercased()) }

        // Range-aware ("2-3 RIR", "2-3 reps in reserve"): capturing only the single
        // trailing digit used to read "2-3 reps in reserve" as RIR 3 AND leave a
        // dangling "2-" behind after cleaning (seen shipping: "finish sets with 2-
        // and log a load…").
        let rirNumber = #"\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?"#
        let rir = firstCapture(in: trimmed, pattern: "(?i)\\bRIR\\b\\s*[:\\-]?\\s*(\(rirNumber))\\b")
            ?? firstCapture(in: trimmed, pattern: "(?i)\\b(\(rirNumber))\\s*RIR\\b")
            ?? firstCapture(in: trimmed, pattern: "(?i)\\b(\(rirNumber))\\s*reps?\\s+in\\s+reserve\\b")
        let tempo = firstCapture(in: trimmed, pattern: #"(?i)\btempo\b\s*[:\-]?\s*([0-9Xx](?:\s*-\s*[0-9Xx]){3})\b"#)?
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        var cleaned = trimmed
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bweek\s*\d+\s*(light|moderate|heavy)\s+weight\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b(light|moderate|heavy)\s+weight\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bweek\s*\d+\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b(light|moderate|heavy)\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?i)\\bRIR\\b\\s*[:\\-]?\\s*\(rirNumber)\\b", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?i)\\b\(rirNumber)\\s*RIR\\b", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "(?i)\\b\(rirNumber)\\s*reps?\\s+in\\s+reserve\\b", with: "", options: .regularExpression)
        // Connector left behind when an embedded RIR phrase is removed
        // ("finish sets with [2-3 reps in reserve] and log…").
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bwith\s+and\b"#, with: "and", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\btempo\b\s*[:\-]?\s*[0-9Xx](?:\s*-\s*[0-9Xx]){3}\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\.\s*[:\-]\s*"#, with: ". ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[:\-]\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-"))

        // A prescription with no parsed values adds nothing over the raw note.
        guard week != nil || intensity != nil || rir != nil || tempo != nil else { return nil }

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
        exerciseName: String,
        performanceHistory: [WorkoutPerformanceLogSnapshot] = []
    ) -> ProgressionSuggestion? {
        let key = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
        let effortSignal = WorkoutProgressionEngine.effortSignal(
            for: key,
            from: performanceHistory
        )
        guard let decision = WorkoutProgressionEngine.evaluate(
            analysis: analysis,
            summaryWeight: lastWeight,
            summaryReps: summaryRepsCompleted,
            repRange: repRange,
            effortSignal: effortSignal
        ) else { return nil }

        let weightText = formatWeight(decision.workingWeight)
        let nextText = formatWeight(
            WorkoutProgressionEngine.nextLoad(from: decision.workingWeight, exerciseName: exerciseName)
        )

        // Bodyweight-equivalent history (true 0-load logs, or the legacy "1 lb"
        // stand-ins from before the logger allowed BW) gets bodyweight coaching:
        // percentage math off a fake base produced advice like "1 lb felt
        // complete. Try 2.5 lb" while the movement's real progression is reps,
        // then a first external increment.
        let isBodyweight = WorkoutProgressionEngine.isBodyweightEquivalent(decision.workingWeight)
        let atLoad = isBodyweight ? "at bodyweight" : "at \(weightText) lb"
        let holdLabel = isBodyweight ? "Hold bodyweight" : "Hold \(weightText) lb"

        switch decision.kind {
        case .addLoad:
            if decision.workingSetCount > 0 && decision.ceilingSetCount < decision.workingSetCount {
                return ProgressionSuggestion(
                    icon: "arrow.up.circle.fill",
                    text: isBodyweight
                        ? "Add load — \(decision.ceilingSetCount) of \(setsLabel(decision.workingSetCount)) hit \(repRange.high) \(atLoad). Add ~\(nextText) lb external (ankle weight or dumbbell) next session"
                        : "Add load — \(decision.ceilingSetCount) of \(setsLabel(decision.workingSetCount)) hit \(repRange.high) \(atLoad). Try \(nextText) lb next session",
                    color: TFColor.success
                )
            }
            return ProgressionSuggestion(
                icon: "arrow.up.circle.fill",
                text: {
                    if isBodyweight {
                        return "Bodyweight is maxing the rep range — add ~\(nextText) lb external (ankle weight or dumbbell) next session"
                    }
                    return decision.usedPerSetEvidence
                        ? "Add load — \(weightText) lb felt complete. Try \(nextText) lb next session"
                        : "Increase to \(nextText) lb next session"
                }(),
                color: TFColor.success
            )
        case .holdBelowRange:
            let reps = decision.minimumWorkingReps ?? repRange.low
            return ProgressionSuggestion(
                icon: "arrow.down.circle.fill",
                text: decision.usedPerSetEvidence
                    ? "\(holdLabel) — a working set dropped to \(reps) (target \(repRange.low)-\(repRange.high)); even your sets out before adding"
                    : "Stay \(atLoad), focus on form and full ROM",
                color: TFColor.warning
            )
        case .holdForRecovery:
            return ProgressionSuggestion(
                icon: "arrow.down.right.circle.fill",
                text: "\(holdLabel) — repeated low RIR suggests protecting recovery before adding load",
                color: TFColor.warning
            )
        case .addRepsInRange:
            if decision.ceilingSetCount > 0 && decision.workingSetCount > 0 {
                let majority = max(1, Int(ceil(Double(decision.workingSetCount) * 0.67)))
                if decision.ceilingSetCount < majority {
                    let needed = majority - decision.ceilingSetCount
                    return ProgressionSuggestion(
                        icon: "flame.fill",
                        text: "Strong top set \(atLoad) — hit \(repRange.high) on \(needed) more set\(needed == 1 ? "" : "s") before adding",
                        color: TFColor.accent
                    )
                }
            }
            let reps = decision.minimumWorkingReps ?? repRange.low
            let text = decision.workingSetCount > 0
                ? "On track \(atLoad) — build all sets to \(repRange.high) reps (lowest was \(reps))"
                : "On track — aim for \(reps + 1)-\(repRange.high) reps next session"
            return ProgressionSuggestion(
                icon: "arrow.right.circle.fill",
                text: text,
                color: .blue
            )
        }
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

extension Notification.Name {
    /// Posted after a set is persisted; object is the exercise's PersistentIdentifier.
    /// The exercise's rest timer listens and auto-starts its countdown.
    static let tfWorkoutSetLogged = Notification.Name("tfWorkoutSetLogged")
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
        rir: Double? = nil,
        for exercise: WorkoutExercise,
        modelContext: ModelContext,
        on date: Date = .now
    ) -> Bool {
        // Weight 0 is an explicit bodyweight set; only negative weight or
        // non-positive reps are rejected.
        guard weightLbs >= 0, reps > 0 else { return false }
        let log = todaysLogOrCreate(for: exercise, modelContext: modelContext, date: date)
        var sets = log.decodedSetLogs.filter { $0.setNumber != setNumber }
        sets.append(SetLogEntry(setNumber: setNumber, weightLbs: weightLbs, repsCompleted: reps, rir: rir))
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

        stampSessionTiming(for: exercise, date: date)

        return persist(modelContext)
    }

    /// Warm-up lead: the athlete is already training (warming up) before the first rep is
    /// logged, so an inferred start is back-dated by this much to approximate real session
    /// length. Applies ONLY to the automatic first-set start — a manual "Start" tap records
    /// an exact time and is left untouched. The athlete can still nudge it in the sheet.
    static let inferredWarmupLeadMinutes = 10

    /// Auto-tracks session duration so the athlete never hand-dials a clock. The first
    /// set logged marks the session start (minus the warm-up lead); each later set advances
    /// the end, so by the time feedback is entered the real elapsed time is already
    /// recorded. Only touches a live (not-yet-finalized) session and only for logs stamped
    /// today, so correcting an old session's set tomorrow can't rewrite its clock.
    private static func stampSessionTiming(for exercise: WorkoutExercise, date: Date) {
        guard let day = exercise.day,
              day.feedbackSubmittedAt == nil,
              Calendar.current.isDateInToday(date) else { return }
        if day.sessionStartedAt == nil {
            day.sessionStartedAt = date.addingTimeInterval(-Double(inferredWarmupLeadMinutes) * 60)
        }
        if let end = day.sessionEndedAt {
            if date > end { day.sessionEndedAt = date }
        } else {
            day.sessionEndedAt = date
        }
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
    /// Prefill values must come from ACTUAL history (this session's last set, or
    /// last session's working sets) — never from the programmed target, which is
    /// a guess and renders as a placeholder instead (`targetRepsPlaceholder`).
    let suggestedWeight: Double?
    let suggestedReps: Int?
    let targetRepsPlaceholder: Int?
    let onLog: (Int, Double, Int, Double?) -> Void
    let onClear: (Int) -> Void

    @State private var expanded = false
    @State private var editing: Set<Int> = []
    @State private var draftWeight: [Int: String] = [:]
    @State private var draftReps: [Int: String] = [:]
    @State private var draftRIR: [Int: String] = [:]
    @FocusState private var focusedField: FieldKey?

    enum FieldKey: Hashable {
        case weight(Int)
        case reps(Int)
        case rir(Int)
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
                Text("Confirm each set as you finish.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    ForEach(1...programmedCount, id: \.self) { n in
                        setRow(n)
                    }
                }
            }
        }
        .padding(expanded ? 10 : 0)
        .background(expanded ? Color.primary.opacity(0.04) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text("Log sets")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text("\(loggedCount)/\(programmedCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.18))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(allLogged ? TFColor.success : TFColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
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
            Text(formatLoad(set.weightLbs))
                .font(.caption.bold())
            Text("\u{00D7}").font(.caption2).foregroundStyle(.tertiary)
            Text("\(set.repsCompleted) reps").font(.caption).foregroundStyle(.secondary)
            if let rir = set.rir {
                Text("RIR \(formatRIR(rir))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                draftWeight[n] = WorkoutProgressionEngine.isBodyweightEquivalent(set.weightLbs) ? "BW" : formatWeight(set.weightLbs)
                draftReps[n] = "\(set.repsCompleted)"
                draftRIR[n] = set.rir.map { formatRIR($0) } ?? ""
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
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(.systemBackground).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func entryRow(_ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                setLabel(n)
                field(text: weightBinding(n), placeholder: "lb", key: .weight(n), isReps: false, width: 50)
                Text("\u{00D7}").font(.caption2).foregroundStyle(.tertiary)
                field(text: repsBinding(n), placeholder: repsPlaceholder, key: .reps(n), isReps: true, width: 42)
                Spacer(minLength: 4)
                Text("RIR")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                field(text: rirBinding(n), placeholder: "—", key: .rir(n), isReps: false, width: 38)
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
            // The decimal keyboard can't type "BW", so an empty weight field offers
            // it explicitly. The row disappears once a load (or BW) is entered.
            if weightBinding(n).wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    draftWeight[n] = "BW"
                    // A bodyweight movement progresses on reps and usually has no
                    // load history to prefill them, so tapping "Bodyweight" used to
                    // resolve the weight but leave reps an empty placeholder — the
                    // checkmark stayed silently disabled and the set dead-ended.
                    // Seed the programmed target as an editable starting point so the
                    // set is one confirm away; the user still edits/confirms the
                    // actual count (a tap reports what happened, not what was hoped).
                    if repsBinding(n).wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty,
                       let target = targetRepsPlaceholder ?? suggestedReps {
                        draftReps[n] = "\(target)"
                    }
                } label: {
                    Label("Bodyweight — no external load", systemImage: "figure.core.training")
                        .font(.caption2.bold())
                        .foregroundStyle(TFColor.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log set \(n) as bodyweight")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemBackground).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    /// Placeholder for the reps field: the programmed target, visibly a suggestion.
    /// Actual history prefills as a value; a pure guess never does — a tap must
    /// report what happened, not confirm what was hoped.
    private var repsPlaceholder: String {
        targetRepsPlaceholder.map(String.init) ?? "reps"
    }

    private func defaultWeightText() -> String {
        // nil = no history (leave empty); bodyweight-equivalent history (true 0 or a legacy
        // ≤1 lb stand-in) prefills "BW" so the logger field matches how the load displays.
        guard let w = loggedSets.last?.weightLbs ?? suggestedWeight else { return "" }
        return WorkoutProgressionEngine.isBodyweightEquivalent(w) ? "BW" : formatWeight(w)
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

    private func rirBinding(_ n: Int) -> Binding<String> {
        Binding(get: { draftRIR[n] ?? "" }, set: { draftRIR[n] = $0 })
    }

    private func parsedWeight(_ n: Int) -> Double? {
        let t = (draftWeight[n] ?? defaultWeightText())
            .trimmingCharacters(in: .whitespaces)
        // "BW" (from the bodyweight button or a BW-history prefill) is an explicit
        // 0-load set; it is the only way to log 0 — a typed number must be positive.
        if t.caseInsensitiveCompare("BW") == .orderedSame { return 0 }
        let cleaned = t.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(cleaned), v > 0 else { return nil }
        return v
    }

    private func parsedReps(_ n: Int) -> Int? {
        let t = (draftReps[n] ?? defaultRepsText()).trimmingCharacters(in: .whitespaces)
        guard let v = Int(t), v > 0 else { return nil }
        return v
    }

    private func parsedRIR(_ n: Int) -> Double? {
        let t = (draftRIR[n] ?? "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), (0...6).contains(v) else { return nil }
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
        onLog(n, w, r, parsedRIR(n))
    }

    private func resetDraft(_ n: Int) {
        draftWeight[n] = nil
        draftReps[n] = nil
        draftRIR[n] = nil
        editing.remove(n)
    }

    private func formatRIR(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

}
