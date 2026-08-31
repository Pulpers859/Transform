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

    /// The day briefing, with load/rep progression sentences removed.
    ///
    /// This note sits at the TOP of the screen, above cards whose deterministic banners can say
    /// the opposite — and it was the one piece of coaching text in the app that no filter and no
    /// validator rule ever touched. A briefing reading "put 5 lb on the top set today" rendered
    /// directly above a card reading "Hold 100 lb", with nothing anywhere to prevent it.
    ///
    /// Only the prose summary is filtered; `warmupSteps` is a checklist of movements, never load
    /// advice, and must survive intact. Deload phrasing is also left alone here on purpose: at
    /// the day level "keep it light this week" is useful framing, not a competing instruction
    /// about a specific lift's load, which is the only thing the banner actually owns.
    var filteredSessionSummary: String {
        CoachingProse.filteredSentences(
            in: sessionNoteSections.summary,
            hideProgressionCue: true,
            hideDeloadCue: false
        ).joined(separator: " ")
    }

    /// Accent while there is work left, success once the day was genuinely trained. A full bar
    /// still painted in the in-progress accent reads as "not finished" against every other
    /// done-signal in the app, which are all green.
    ///
    /// "Resolved" is NOT the same as "performed", and the bar must not conflate them. Every
    /// skip — including a skip for pain — sets `isCompleted = true` so the day can close, and
    /// finishing an exercise as Modified with zero sets logged does too. Tinting on
    /// `completedExerciseCount` alone would paint a session where three lifts were abandoned
    /// for shoulder pain in the app's universal "you did it" colour. Green is reserved for a
    /// day where every exercise was actually worked.
    var progressTint: Color {
        guard totalExerciseCount > 0, completedExerciseCount == totalExerciseCount else {
            return TFColor.accent
        }
        return day.sortedExercises.allSatisfy(\.wasPerformed) ? TFColor.success : TFColor.accent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dayHeader
                sessionTimingBadge
                // Gated on what will actually RENDER, not on the raw note: a briefing made
                // entirely of progression sentences now filters down to nothing, and the old
                // `!day.notes.isEmpty` guard would have drawn an empty card around it.
                if !filteredSessionSummary.isEmpty || !sessionNoteSections.warmupSteps.isEmpty {
                    sessionNotes
                }
                if day.hasReviewableSession {
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
                sessionSetLogs: sessionSetLogs(for: exercise)
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
                            .fill(progressTint.opacity(0.15))
                            .frame(height: 6)
                        Capsule()
                            .fill(progressTint)
                            .frame(width: geo.size.width * exerciseProgress, height: 6)
                            .animation(.easeOut(duration: 0.4), value: exerciseProgress)
                    }
                }
                .frame(height: 6)

                Text("\(completedExerciseCount)/\(totalExerciseCount)")
                    .font(.caption.bold())
                    .foregroundStyle(progressTint)
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
    /// automatically (see `SessionLifecycle.noteSetLogged`) and this shows a live running
    /// duration. Before any set exists it offers an optional manual start for athletes who
    /// want a long warm-up counted — but starting is never required.
    ///
    /// The running badge also carries "Finish" — the escape hatch for a session that ends
    /// without every exercise being resolved. Without it, walking away mid-day left the
    /// clock running and the feedback sheet unreachable, since the feedback card only
    /// appears once the day is finished.
    @ViewBuilder
    var sessionTimingBadge: some View {
        if !day.isCompleted && !day.isSessionClosed {
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
                        Button(action: finishSessionEarly) {
                            Text("Finish")
                                .font(.caption.bold())
                                .foregroundStyle(TFColor.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Finish session now")
                        .accessibilityHint("Stops the clock and opens session feedback")
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

            if !filteredSessionSummary.isEmpty {
                Text(filteredSessionSummary)
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

                    // What the rating actually did. The numbers were already echoed back
                    // verbatim and nothing on the screen reacted to them — a session rated
                    // 2/5 for stimulus with non-zero pain looked identical to a great one.
                    // Feedback IS consumed (WorkoutEffortGovernance feeds generation), so the
                    // gap was visibility, not plumbing: rating something and observing no
                    // response is how a rating habit dies.
                    if let response = feedbackResponseText {
                        Text(response)
                            .font(.caption2)
                            .foregroundStyle(TFColor.accent)
                            .multilineTextAlignment(.leading)
                    }
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

    /// The governance signal your ratings are currently producing, in plain language.
    ///
    /// `nil` when there is nothing to say — no feedback on this day yet, or a neutral signal,
    /// where inventing a reassurance would be noise. The signal needs at least two rated
    /// sessions to exist at all, so early in a block this is silent by design rather than
    /// broken.
    private var feedbackResponseText: String? {
        guard day.hasSessionFeedback else { return nil }
        // Scoped to THIS day's week, matching how generation actually builds the signal
        // (WorkoutView's next-week request filters to a single week before snapshotting).
        //
        // Reading every week instead produced a line that asserted a consequence which would
        // not happen: on the first rated day of a week, generation sees one session and stays
        // neutral, while an all-weeks read pulls in the tail of the previous week, crosses the
        // recovery threshold, and promises load changes nobody requested. It also let an old
        // day's card describe ratings recorded weeks AFTER the session being viewed.
        let rated = (day.program?.days ?? [])
            .filter { $0.weekNumber == day.weekNumber && $0.hasSessionFeedback }
            .sorted { $0.dayNumber < $1.dayNumber }
            .map {
                WorkoutSessionFeedbackSnapshot(
                    effort: $0.sessionEffort,
                    stimulus: $0.stimulusQuality,
                    jointPain: $0.jointPain,
                    performanceRawValue: $0.performanceRatingRaw
                )
            }

        switch WorkoutEffortGovernance.signal(from: rated) {
        case .protectRecovery:
            return "Your recent ratings are asking for recovery — next week holds load steady."
        case .progressionHeadroom:
            return "Your recent ratings show headroom — next week keeps adding reps before load."
        case .neutral:
            return nil
        }
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
        // Resolved once per render, OUTSIDE the loop. Every card used to read the
        // `performanceLogSnapshots` computed property from inside `ForEach`, which decoded
        // every performance log in the database once per exercise — see the property's own
        // note for why that was the expensive way to answer a per-exercise question.
        let historyByKey = performanceSnapshotsByKey

        return VStack(alignment: .leading, spacing: 10) {
            TFSectionLabel(text: "Exercises")

            ForEach(day.sortedExercises) { exercise in
                // Each of these scans the full log set, so they are resolved ONCE here and
                // handed down rather than recomputed inside the card.
                let entry = weightSummary(for: exercise)
                let previous = latestSetLogs(for: exercise)
                let today = sessionSetLogs(for: exercise)

                ExerciseCard(
                    exercise: exercise,
                    summary: sessionSummary(
                        for: exercise,
                        entry: entry,
                        previous: previous,
                        today: today
                    ),
                    weightSummary: entry,
                    latestSetLogs: previous,
                    sessionSetLogs: today,
                    // Only this exercise's history. The card's single consumer
                    // (`WorkoutProgressionEngine.effortSignal`) filters to one canonical key
                    // and keeps three sessions, so handing it the whole database was work
                    // done purely to be discarded.
                    performanceHistory: historyByKey[
                        ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                    ] ?? [],
                    previousPrescription: previousPrescription(for: exercise),
                    isExpanded: expandedExerciseIDs.contains(exercise.persistentModelID),
                    onToggle: { toggleExercise(exercise) },
                    onToggleExpanded: { toggleExpanded(exercise) },
                    onFinalSetLogged: { autoCompleteAfterFinalSet(exercise) },
                    onLogWeight: { exerciseForWeightLogging = exercise },
                    onSetStatus: { setStatus($0, on: exercise) },
                    onClearStatus: { clearStatus(on: exercise) }
                )
            }
        }
    }

    /// Resolves the one answer to "what happened on this exercise?" that every element of the
    /// card reads from.
    ///
    /// The best-date argument is the subtle part. `bestLoggedAt` is nil whenever the summary
    /// row has not yet promoted a separate best record — which is exactly the case where the
    /// row itself IS the current best, including a personal best set minutes ago. Passing it
    /// bare would report `wasSetToday == false` for the very case the flag was added for, and
    /// `resolve` would accept that silently because a missing date is documented as
    /// historical. Fall back to the row's own timestamp, matching what AddExerciseWeightSheet
    /// and DataBackupManager already do.
    func sessionSummary(
        for exercise: WorkoutExercise,
        entry: ExerciseWeightEntry?,
        previous: [SetLogEntry],
        today: [SetLogEntry]
    ) -> ExerciseSessionSummary {
        ExerciseSessionSummary.resolve(
            isCompleted: exercise.isCompleted,
            completionStatus: exercise.completionStatus,
            plannedSets: exercise.sets,
            reps: exercise.reps,
            targetRIR: exercise.targetRIR,
            loggedSets: today,
            previousSets: previous,
            bestWeightLbs: entry.map { $0.hasBestRecord ? $0.bestWeightLbs : $0.weightLbs },
            bestReps: entry.flatMap { $0.hasBestRecord ? ($0.bestRepsCompleted ?? $0.repsCompleted) : $0.repsCompleted },
            bestLoggedAt: entry.flatMap { $0.hasBestRecord ? $0.bestLoggedAt : $0.loggedAt }
        )
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
        let logged = sessionSetLogs(for: exercise).count
        return logged > 0 ? "Finish \(logged)/\(exercise.sets) sets?" : "Complete without logged sets?"
    }

    var partialCompletionActionLabel: String {
        guard let exercise = completionPromptExercise else {
            return "Finish Modified"
        }
        let logged = sessionSetLogs(for: exercise).count
        return logged > 0 ? "Finish \(logged)/\(exercise.sets)" : "Finish Modified"
    }

    var completionPromptMessage: String {
        guard let exercise = completionPromptExercise else {
            return "Logging sets improves future progression cues."
        }
        let logged = sessionSetLogs(for: exercise).count
        if logged > 0 {
            return "\(logged) of \(exercise.sets) planned sets are logged. This marks the exercise as Modified; progression will use only the sets you actually logged."
        }
        return "No sets are logged yet. This marks the exercise as Modified and does not create any fake reps or volume."
    }

    func toggleExercise(_ exercise: WorkoutExercise) {
        if !exercise.isCompleted, exercise.sets > 0 {
            let logged = sessionSetLogs(for: exercise).count
            if logged < exercise.sets {
                completionPromptExercise = exercise
                TFHaptics.impact(.soft)
                return
            }
        }

        // Snapshot before mutating — it captures the exercise's own flags, so taking it
        // afterwards would "restore" the very values the rollback is meant to undo.
        let snapshot = DispositionSnapshot(exercise: exercise, day: day, status: exercise.completionStatus)
        exercise.isCompleted.toggle()
        if !exercise.isCompleted && snapshot.status == .completedModified {
            exercise.completionStatus = nil
        }
        commitDisposition(of: exercise, operation: "exercise completion toggle", restoring: snapshot)
    }

    /// Ticks the completion check the instant the last prescribed set is logged.
    ///
    /// Deliberately NOT routed through `toggleExercise`: that is a toggle, so a stray call on
    /// an already-finished lift would UN-finish it. This only ever moves an exercise forward.
    /// It also skips the partial-completion alert on purpose — the alert exists to ask about
    /// missing sets, and by definition none are missing here.
    func autoCompleteAfterFinalSet(_ exercise: WorkoutExercise) {
        guard !exercise.isCompleted else { return }
        let snapshot = DispositionSnapshot(exercise: exercise, day: day, status: exercise.completionStatus)
        exercise.isCompleted = true
        commitDisposition(
            of: exercise,
            operation: "final set auto-completion",
            restoring: snapshot,
            // Stated rather than looked up. The set that triggered this is already persisted,
            // but `allPerformanceLogs` is a `@Query` and republishes on its own schedule, so
            // re-reading it here can still come back empty — which on a single-set exercise
            // would leave the card sitting open on work it has just finished.
            knownToHaveLoggedWork: true
        )
    }

    func completeExerciseAsModified(_ exercise: WorkoutExercise) {
        let snapshot = DispositionSnapshot(exercise: exercise, day: day, status: exercise.completionStatus)
        exercise.isCompleted = true
        exercise.completionStatus = .completedModified
        commitDisposition(of: exercise, operation: "exercise modified completion", restoring: snapshot)
    }

    /// Records an exercise's disposition (completed / modified / skipped / cleared) that
    /// the caller has already applied, then re-derives the day through the one funnel that
    /// owns that decision. Every path that can finish a day lands here, so skipping the
    /// last lift closes the session exactly like ticking it off does.
    /// - Parameter knownToHaveLoggedWork: set by callers that know a set was just written and
    ///   cannot rely on the `@Query` having caught up yet. Only affects whether the card
    ///   closes itself; it never changes what is stored.
    func commitDisposition(
        of exercise: WorkoutExercise,
        operation: String,
        restoring snapshot: DispositionSnapshot,
        knownToHaveLoggedWork: Bool = false
    ) {
        let transition = SessionLifecycle.syncDayCompletion(for: day)

        guard PersistenceReporter.save(modelContext, operation: operation) else {
            modelContext.rollback()
            snapshot.restore(exercise: exercise, day: day)
            TFHaptics.error()
            return
        }

        DataBackupManager.shared.writeAutomaticBackupCoalesced(using: modelContext)
        TFHaptics.impact(.light)

        // A settled exercise with work behind it has nothing left to operate, so it closes
        // itself. Ticking the check used to leave a full-height card open — set logger, rest
        // band and all — and the lifter had to tap the same card a second time to get past it.
        //
        // The logged-sets condition is the exception that keeps this honest. A lift finished
        // with NOTHING logged renders a "Log what you did" remedy inside the open card and
        // nowhere else; collapsing it would hide the only way out of a state the app itself
        // just flagged as incomplete. Same for a skip cleared later — "Clear" lives in that
        // row too. So: resolved AND something to show for it collapses; resolved and empty
        // stays open holding its own fix.
        if exercise.isCompleted && (knownToHaveLoggedWork || !sessionSetLogs(for: exercise).isEmpty) {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedExerciseIDs.remove(exercise.persistentModelID)
            }
        }

        if transition == .justFinished {
            // Training is over, so the day becomes something to review rather than operate.
            //
            // The one-time seed already lands a RETURNING finished day collapsed, but it runs
            // once per view lifetime and cannot help here: over a session the lifter opens
            // each card as they reach it, and by the last set all of them are open. Nothing
            // ever closed them again, so the moment of finishing left six full-height cards —
            // each still leading with a Log-sets button — between the lifter and the summary
            // they actually want.
            //
            // Collapsing here is the missing state transition, not a second default.
            withAnimation(.easeInOut(duration: 0.25)) {
                expandedExerciseIDs.removeAll()
            }
            feedbackDay = day
        } else if transition == .reopened {
            // Symmetry. Finishing collapses everything, so un-finishing has to give the lifter
            // somewhere to land — otherwise a mis-tap and an undo leaves six closed cards and
            // no indication of which one just re-opened.
            withAnimation(.easeInOut(duration: 0.25)) {
                // Discarded explicitly: `Set.insert` returns (inserted:memberAfterInsert:), and
                // as the closure's only statement that tuple becomes `withAnimation`'s return
                // value — which nothing reads, hence "result of call is unused". Whether the ID
                // was already present is genuinely irrelevant here; the card ends up open either
                // way.
                _ = expandedExerciseIDs.insert(exercise.persistentModelID)
            }
        }
    }

    /// Pre-change state for the rollback path. SwiftData's `rollback()` reverts the store,
    /// but the in-memory objects this view already mutated need restoring by hand.
    struct DispositionSnapshot {
        let exerciseCompleted: Bool
        let dayCompleted: Bool
        let sessionEndedAt: Date?
        let sessionClosed: Bool
        let status: ExerciseCompletionStatus?

        init(exercise: WorkoutExercise, day: WorkoutDay, status: ExerciseCompletionStatus?) {
            self.exerciseCompleted = exercise.isCompleted
            self.dayCompleted = day.isCompleted
            self.sessionEndedAt = day.sessionEndedAt
            self.sessionClosed = day.isSessionClosed
            self.status = status
        }

        func restore(exercise: WorkoutExercise, day: WorkoutDay) {
            exercise.isCompleted = exerciseCompleted
            exercise.completionStatus = status
            day.isCompleted = dayCompleted
            day.sessionEndedAt = sessionEndedAt
            day.isSessionClosed = sessionClosed
        }
    }

    /// "I'm done for today" with work still unresolved — ran out of time and walked away.
    /// Closes the clock and opens feedback so the session is recorded honestly, but
    /// deliberately does NOT mark the day complete: the untouched exercises are real
    /// missing work and skip/pain history feeds next week's programming.
    func finishSessionEarly() {
        let previousEnd = day.sessionEndedAt
        let previousClosed = day.isSessionClosed
        SessionLifecycle.markSessionEnded(for: day)
        guard PersistenceReporter.save(modelContext, operation: "finish session early") else {
            modelContext.rollback()
            day.sessionEndedAt = previousEnd
            day.isSessionClosed = previousClosed
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.writeAutomaticBackupCoalesced(using: modelContext)
        TFHaptics.impact(.light)
        feedbackDay = day
    }

    /// Skip / substitute / modified from the exercise's action menu. A skip resolves the
    /// exercise for today, so it can finish the day and trigger feedback just like the
    /// completion checkmark — the case that used to leave a timed-out session open.
    func setStatus(_ status: ExerciseCompletionStatus, on exercise: WorkoutExercise) {
        let snapshot = DispositionSnapshot(exercise: exercise, day: day, status: exercise.completionStatus)
        exercise.completionStatus = status
        // Any settling status finishes the exercise, not just skips. Picking "Completed" from
        // the menu used to set the status and leave isCompleted false, so the card claimed to
        // be done while the resolver read it as not started and the day never closed.
        if status.marksExerciseFinished {
            exercise.isCompleted = true
        }
        commitDisposition(of: exercise, operation: "set exercise status", restoring: snapshot)
    }

    /// Undo a skip / substitution. Re-opens the day if that exercise was holding it shut,
    /// which the old inline handler never did — a cleared skip could leave the day ticked
    /// off with unresolved work in it.
    func clearStatus(on exercise: WorkoutExercise) {
        let snapshot = DispositionSnapshot(exercise: exercise, day: day, status: exercise.completionStatus)
        if exercise.completionStatus?.isSkipped == true {
            exercise.isCompleted = false
        }
        exercise.completionStatus = nil
        commitDisposition(of: exercise, operation: "clear exercise status", restoring: snapshot)
    }

    func weightSummary(for exercise: WorkoutExercise) -> ExerciseWeightEntry? {
        ExerciseWeightStore.summary(for: exercise, within: allWeightLogs)
    }

    /// The most recent completed session before the one on screen — the "last session"
    /// reference.
    func latestSetLogs(for exercise: WorkoutExercise) -> [SetLogEntry] {
        SetLoggingService.previousSets(for: exercise, in: allPerformanceLogs)
    }

    /// Sets logged for the session on screen: today's while training, that day's when looking
    /// back at a day already trained.
    func sessionSetLogs(for exercise: WorkoutExercise) -> [SetLogEntry] {
        SetLoggingService.loggedSets(for: exercise, in: allPerformanceLogs)
    }

    /// What the previous session recorded as its own prescription.
    ///
    /// Resolved through `SetLoggingService.previousLog`, the same call `latestSetLogs` goes
    /// through, so the prescription and the sets it describes always come from one session.
    func previousPrescription(for exercise: WorkoutExercise) -> RecordedPrescription {
        guard let log = SetLoggingService.previousLog(for: exercise, in: allPerformanceLogs) else {
            return .unrecorded
        }
        return RecordedPrescription(sets: log.recordedPrescribedSets, repRange: log.recordedRepRange)
    }

    /// Performance history sliced by canonical exercise key, built ONCE per render.
    ///
    /// `ExercisePerformanceLog.decodedSetLogs` runs a full `JSONDecoder` pass on every access.
    /// This used to be a flat array read from inside `exerciseList`'s `ForEach`, so a single
    /// render decoded every log in the database once per exercise card — and a card only ever
    /// looks at its OWN exercise, so the rest was decoded and thrown away.
    ///
    /// The cost landed at the worst possible moment. This view's body re-runs on every
    /// keystroke in the inline set logger and every minute from the session-timer
    /// `TimelineView`, so the waste compounded while the lifter was mid-set typing a weight,
    /// and it grew with every workout ever logged.
    ///
    /// Grouping by the log's stored `canonicalExerciseKey` while callers look up by
    /// `canonicalLookupKey(exerciseName)` is the same pairing `effortSignal` already relies
    /// on, and the startup normalizers re-derive stored keys from names each launch — so this
    /// introduces no assumption that was not already load-bearing.
    var performanceSnapshotsByKey: [String: [WorkoutPerformanceLogSnapshot]] {
        Dictionary(
            grouping: allPerformanceLogs.map {
                WorkoutPerformanceLogSnapshot(
                    canonicalExerciseKey: $0.canonicalExerciseKey,
                    loggedAt: $0.loggedAt,
                    setLogs: $0.decodedSetLogs,
                    prescribedReps: $0.prescribedReps
                )
            },
            by: \.canonicalExerciseKey
        )
    }
}

/// What a past session was PRESCRIBED, as that session recorded it.
///
/// Both fields are optional because sessions logged before the prescription was stored have
/// no answer, and an absent prescription must never be read as "0 sets" or "no rep range" —
/// a reader that treated 0 as real would call every legacy session unfinished.
struct RecordedPrescription: Equatable {
    let sets: Int?
    let repRange: RepRange?

    static let unrecorded = RecordedPrescription(sets: nil, repRange: nil)
}

// MARK: - Exercise Card

struct ExerciseCard: View {
    @Environment(\.modelContext) private var modelContext
    let exercise: WorkoutExercise
    /// The resolved answer to "what happened here?", built once by the parent. Every element
    /// that used to read `exercise.isCompleted` directly reads this instead, so the card can
    /// no longer contradict itself.
    let summary: ExerciseSessionSummary
    let weightSummary: ExerciseWeightEntry?
    /// The most recent *completed* session before today — drives the "last session"
    /// panel and the progression suggestion.
    let latestSetLogs: [SetLogEntry]
    /// Sets already logged for today's in-progress session — drives the inline logger.
    let sessionSetLogs: [SetLogEntry]
    /// All decoded performance sessions, used for the exercise-specific effort signal.
    let performanceHistory: [WorkoutPerformanceLogSnapshot]
    /// What the PREVIOUS session was prescribed, from that session's own record.
    ///
    /// The card grades whichever session `progressionReferenceSets` selected. When that is
    /// the previous one, grading it against `exercise.reps` scores old work by today's
    /// programming — change a lift from 12-15 to 15-20 and last month's good 14-rep sets
    /// retroactively become failures. This is that session's own answer.
    let previousPrescription: RecordedPrescription
    /// Whether this card is open. Ownership lives in the parent so the default (only the
    /// current lift open) can reason across exercises; the card just renders the state.
    let isExpanded: Bool
    let onToggle: () -> Void
    let onToggleExpanded: () -> Void
    /// Fired once, on the log that fills the last outstanding set. The parent owns the
    /// completion decision (it has to re-derive the whole day from it), so the card only
    /// reports that the exercise ran out of work to do.
    let onFinalSetLogged: () -> Void
    let onLogWeight: () -> Void
    /// Skip / substitute / modified selections are applied by the parent, not here: the
    /// day's completion state has to be re-derived from the same funnel that the
    /// completion checkmark uses, and the card cannot see its siblings.
    let onSetStatus: (ExerciseCompletionStatus) -> Void
    let onClearStatus: () -> Void
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
        sessionSetLogs.isEmpty ? latestSetLogs : sessionSetLogs
    }

    var progressionAnalysis: WorkingSetAnalysis {
        WorkingSetAnalysis.analyze(progressionReferenceSets)
    }

    /// The prescription belonging to the session `progressionReferenceSets` chose.
    ///
    /// Today's sets are trained under today's card, so `exercise` is the right answer for
    /// them. The previous session was trained under whatever the program said THEN, which is
    /// the only fair thing to grade it by. Falls back to the current prescription when that
    /// session predates the recording, which is exactly the old behaviour — never a refusal
    /// to coach.
    var gradedSessionPrescription: (repRange: RepRange, prescribedSets: Int?)? {
        let gradingToday = !sessionSetLogs.isEmpty
        let currentRange = RepRange.parse(exercise.reps)
        if gradingToday {
            guard let currentRange else { return nil }
            return (currentRange, exercise.sets > 0 ? exercise.sets : nil)
        }
        guard let range = previousPrescription.repRange ?? currentRange else { return nil }
        return (range, previousPrescription.sets)
    }

    /// Cross-session sanity check on the just-logged session. The intra-session anomaly
    /// detector needs 3+ sets to establish a center, so single-set isolation work (a rear-
    /// delt machine, a raise) has NOTHING guarding a fat-fingered entry — and that entry
    /// silently becomes the Best and the next progression baseline. Compare today's working
    /// load with last session's: an implausible one-week jump earns a soft "confirm or fix"
    /// (it never blocks). The ~10 lb floor keeps tiny-weight ratios (5→10) from over-firing;
    /// a ≥25% single-session jump is far beyond any step the engine would ever recommend.
    var historicalLoadAnomaly: (setNumber: Int, weight: Double, reference: Double)? {
        let today = WorkingSetAnalysis.analyze(sessionSetLogs)
        guard let todayWeight = today.workingWeight, todayWeight > 0,
              let top = today.topWorkingSet else { return nil }
        let prior = WorkingSetAnalysis.analyze(latestSetLogs)
        guard let priorWeight = prior.workingWeight, priorWeight > 0 else { return nil }
        guard todayWeight >= priorWeight * 1.25, todayWeight - priorWeight >= 10 else { return nil }
        return (top.setNumber, todayWeight, priorWeight)
    }

    /// True when this exercise sits inside a deload block. Deload weeks intentionally pull
    /// load back (roughly 10% under the prior block, stopping shy of failure), so the
    /// "add load / go heavier" cue is wrong here and is replaced by hold-back coaching.
    ///
    /// Read from the PROGRAM STRUCTURE, never from prose. This used to search the day name,
    /// the day notes, and the exercise notes for the word "deload", which meant a week-3 note
    /// saying "the deload doesn't come until next week" silenced the real progression banner on
    /// every card of the block's hardest day — and a genuine week-4 note, which the prompt asks
    /// NOT to label as a deload, left the deload week coaching ordinary load increases.
    ///
    /// A missing `day` resolves to false. Every exercise reaching this card was loaded THROUGH
    /// its day, so the nil case is a broken object graph rather than a real training state —
    /// and of the two wrong answers, "not a deload" at least leaves the evidence-based banner
    /// in charge instead of overriding it with hold-back coaching derived from nothing.
    var isDeloadContext: Bool {
        exercise.day?.isDeloadWeek ?? false
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

    /// Lives in `CoachingProse` so the day's session-note summary runs the SAME filter this
    /// card does. It previously existed only here, which is why the day note — rendered at the
    /// top of the very same screen — was the one piece of coaching text with no filter at all.
    private func coachingSentences(
        from note: String,
        hideProgressionCue: Bool,
        hideDeloadCue: Bool
    ) -> [String] {
        CoachingProse.filteredSentences(
            in: note,
            hideProgressionCue: hideProgressionCue,
            hideDeloadCue: hideDeloadCue
        )
    }

    var progressionSuggestion: ProgressionSuggestion? {
        // On a deload day, never tell the lifter to add weight — that contradicts the
        // prescription. Coach to hold the lighter load regardless of last session's reps.
        if isDeloadContext { return .deloadGuidance }
        guard let log = latestWeightLog else { return nil }
        guard let graded = gradedSessionPrescription else { return nil }
        let suggestion = ProgressionSuggestion.evaluate(
            analysis: progressionAnalysis,
            summaryRepsCompleted: log.repsCompleted,
            repRange: graded.repRange,
            lastWeight: log.weightLbs,
            exerciseName: exercise.exerciseName,
            performanceHistory: performanceHistory
        )
        // An unfinished session is not evidence that a load was easy. Before this, the
        // engine saw only the sets that exist and read "one good set" as a completed
        // prescription beaten — so stopping early was rewarded with heavier weight next
        // time. Gated on load increases alone: a hold or a reduce cue is still the right
        // answer mid-session, and only an increase can be *earned* by work not done.
        //
        // Silent when the prescription was never recorded. Comparing against today's set
        // count instead would accuse a lifter who correctly finished 2 of 2 last week of
        // quitting, purely because this week's card asks for 3.
        if let suggestion, suggestion.increasesLoad,
           let prescribed = graded.prescribedSets,
           progressionReferenceSets.count < prescribed {
            return .finishPrescribedSets(logged: progressionReferenceSets.count, prescribed: prescribed)
        }
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
            ExercisePrescriptionPillData(label: setsLabel(exercise.sets)),
            ExercisePrescriptionPillData(label: "\(exercise.reps) reps")
        ]
        if let tempo = displayTempo {
            items.append(
                ExercisePrescriptionPillData(
                    label: "Tempo \(tempo)",
                    explanation: tempoExplanation(tempo)
                )
            )
        }
        if let rir = displayTargetRIR {
            items.append(
                ExercisePrescriptionPillData(
                    label: "RIR \(rir)",
                    explanation: rirExplanation(rir)
                )
            )
        }
        return items
    }

    /// Reads the four digits back as the phases they represent, using this exercise's own
    /// numbers rather than a generic definition — "3-0-1-0" means nothing until someone says
    /// which 3 and which 1.
    private func tempoExplanation(_ tempo: String) -> String {
        // Trimmed per component: the structured field is compact, but the prose fallback
        // parsed out of a coaching note can arrive as "3 - 0 - 1 - 0" and would otherwise
        // render "Lower for 3  seconds".
        let phases = tempo
            .split(separator: "-")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard phases.count == 4 else {
            return "Seconds per phase of each rep: lowering, pause at the bottom, lifting, pause at the top."
        }
        func seconds(_ value: String) -> String {
            if value.uppercased() == "X" { return "as fast as you can control" }
            return value == "1" ? "1 second" : "\(value) seconds"
        }
        return """
        Seconds per phase of every rep:

        • Lower for \(seconds(phases[0]))
        • Pause at the bottom for \(seconds(phases[1]))
        • Lift for \(seconds(phases[2]))
        • Pause at the top for \(seconds(phases[3]))
        """
    }

    /// RIR is the effort target the whole programme is built on, so it earns a concrete
    /// reading rather than an expansion of the acronym.
    ///
    /// Takes a String because `displayTargetRIR` is one: the structured `targetRIR` field is
    /// an Int, but the prose fallback parsed out of the coaching note can be a range ("2-3").
    /// Read the leading number for the concrete sentence and fall back to the general
    /// definition when it isn't a plain integer.
    private func rirExplanation(_ rir: String) -> String {
        let leading = Int(rir.prefix { $0.isNumber })
        let tail: String
        switch leading {
        case 0: tail = "Take the set to the point where another rep would fail."
        case 1: tail = "Stop when you could manage one more rep, and no more."
        case 2: tail = "Stop when you could manage two more reps — hard, but not to failure."
        case 3: tail = "Stop well short of failure; this is a deliberate back-off."
        case .some(let value): tail = "Stop with \(value) reps still available."
        case nil: tail = "Stop before failure, leaving the listed number of reps in the tank."
        }
        return "Reps In Reserve: how many reps you should still have left when you rack the set.\n\n\(tail)"
    }

    /// The all-time best, with its reps, marked when it was set in THIS session.
    ///
    /// The marker is load-bearing and was nearly lost when the card-face strip that carried it
    /// was removed. "Last" excludes today and "Best" includes it, which is incoherent unless
    /// stated: a live card read "Last 40 lb x 15" above "Best 50 lb · 14 reps" where the 50 lb
    /// had been logged minutes earlier, while a notice four lines below asked the lifter to
    /// confirm that same 50 lb was not a mis-log. Saying which one it is costs three words.
    var bestSummaryText: String? {
        guard let bestWeightText else { return nil }
        let value = bestRepsTileText.map { "\(bestWeightText) · \($0)" } ?? bestWeightText
        return summary.best?.wasSetToday == true ? "\(value) — set today" : value
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedBody
            } else {
                collapsedRow
            }
        }
        // Green fill is earned by performed work, not by the day being settled. A lift skipped
        // for pain or ticked off with nothing logged keeps the neutral surface.
        .background(summary.deservesCleanCompletionTreatment ? TFColor.success.opacity(0.05) : TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(summary.deservesCleanCompletionTreatment ? TFColor.success.opacity(0.2) : Color.clear, lineWidth: 1)
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
        // The whole closed row is the target, not the caret in it — the caret is only the
        // affordance saying the row does something.
        .frame(minHeight: TFTapTarget.minimum)
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

                // A finished exercise has no rest left to run — hide the timer band. The
                // last set now completes the exercise on its own, so the band disappears
                // as that final rest would have started — which is correct: there is no
                // next set to rest for.
                if exercise.restSeconds > 0 && !exercise.isCompleted {
                    ExerciseRestTimerView(
                        exercise: exercise,
                        loggedSets: sessionSetLogs,
                        suggestedWeight: workingSetAnalysis.workingWeight,
                        suggestedReps: workingSetAnalysis.topWorkingSet?.reps,
                        targetRepsPlaceholder: RepRange.parse(exercise.reps)?.high,
                        onLogSet: { setNumber, weight, reps, rir in
                            logSetFromCard(setNumber: setNumber, weight: weight, reps: reps, rir: rir)
                        }
                    )
                }

                InlineSetLogger(
                    exercise: exercise,
                    loggedSets: sessionSetLogs,
                    suggestedWeight: workingSetAnalysis.workingWeight,
                    suggestedReps: workingSetAnalysis.topWorkingSet?.reps,
                    targetRepsPlaceholder: RepRange.parse(exercise.reps)?.high,
                    onLog: { setNumber, weight, reps, rir in
                        logSetFromCard(setNumber: setNumber, weight: weight, reps: reps, rir: rir)
                    },
                    onClear: { setNumber in
                        SetLoggingService.clearSet(setNumber: setNumber, for: exercise, modelContext: modelContext)
                    }
                )

                // Last session's loads and the personal best deliberately do NOT appear on
                // the card face. They were a third tinted strip under the set logger saying
                // what `Details` already says in full — per-set, with warm-up and anomaly
                // roles marked — so the card face repeated the weaker version of it. Details
                // covers both shapes: `setLogBreakdown` when previous sets exist, and
                // `ExerciseWeightSnapshotTile` when only a summary row does.

                // One guidance tile, not two banners: what to do about load, and how to
                // execute the reps. See `ExerciseGuidanceCard`.
                if progressionSuggestion != nil || !conciseCoachingNote.isEmpty {
                    ExerciseGuidanceCard(
                        suggestion: progressionSuggestion,
                        // Expanded view gets the filtered full note, not the raw one: the raw
                        // note can carry a generation-time progression cue that contradicts
                        // the live progression bullet rendered directly above it.
                        coachingText: showDetails ? detailedCoachingNote : conciseCoachingNote
                    )
                }

                // One tile for every warning about today's logging, not one tile each. A
                // load-sanity check plus two adherence flags used to stack as three separate
                // tinted boxes — three alarms for what is one conversation about the same
                // session, and enough height to push the rest of the card off screen.
                if !setNotices.isEmpty {
                    SetAnomalyNotice(texts: setNotices)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 14)

            // Reads the resolved state, not the stored status. A lift ticked off with fewer
            // sets than prescribed carries no status at all, so the old condition left it
            // wearing a plain green check identical to five genuinely completed lifts.
            if let qualifier = summary.qualifierLabel {
                completionStatusRow(
                    qualifier,
                    isSkip: summary.completionStatus?.isSkipped ?? false,
                    isClearable: summary.completionStatus != nil,
                    // A lift marked done with nothing logged leaves no trace for future
                    // programming. Naming that in the qualifier and then offering no way to
                    // fix it is a dead end, so the row carries the remedy.
                    needsLogging: summary.needsLoggingPrompt
                )
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

    /// The single place a set reaches storage from this card, used by BOTH the inline
    /// "Log sets" list and the full-screen rest timer's entry panel. Two entry points in the
    /// UI must never mean two ways of writing training data: they differ only in where the
    /// numbers were typed, so completion reporting and the rest-timer signal stay identical.
    private func logSetFromCard(setNumber: Int, weight: Double, reps: Int, rir: Double?) {
        guard SetLoggingService.logSet(
            setNumber: setNumber,
            weightLbs: weight,
            reps: reps,
            rir: rir,
            for: exercise,
            modelContext: modelContext
        ) else { return }
        // A finished set is when rest begins. The rest card decides what to do with this:
        // it starts a timer that is sitting still and leaves a running one alone.
        NotificationCenter.default.post(
            name: .tfWorkoutSetLogged,
            object: exercise.persistentModelID
        )
        reportFinalSetIfComplete(setNumber: setNumber)
    }

    /// Reports the log that fills the last outstanding set, so the exercise can tick itself
    /// off instead of asking the lifter to confirm what they just told the app.
    ///
    /// The count is derived from the set NUMBERS already on screen plus the one just written,
    /// not from a re-read: `sessionSetLogs` is the parent's `@Query`-backed array and does not
    /// yet include this set. That also makes the trigger idempotent — re-logging a set that
    /// was already filled leaves the union unchanged, so the "was it incomplete before?" test
    /// fails and nothing fires.
    private func reportFinalSetIfComplete(setNumber: Int) {
        // Never re-open a decision that is already made. A skipped lift is resolved too, and
        // logging a set on it must not silently convert the skip into a completion.
        guard !summary.state.isResolved else { return }

        // Mirrors `InlineSetLogger.programmedCount` so the tick lands exactly when the badge
        // reads N/N. Logging a set beyond the prescription raises the bar rather than leaving
        // a visibly unfinished counter on a card that has closed itself.
        func required(_ setNumbers: Set<Int>) -> Int {
            max(exercise.sets, setNumbers.max() ?? 0, 1)
        }

        let before = Set(sessionSetLogs.map { $0.setNumber })
        let after = before.union([setNumber])
        guard before.count < required(before), after.count >= required(after) else { return }
        onFinalSetLogged()
    }

    /// Every warning about today's logging, strongest signal first, for the single notice
    /// tile on the card face.
    ///
    /// An implausible load is decidable without any history, so it leads — it must not be
    /// shadowed by the two checks that need some. Only one load-sanity sentence is ever
    /// emitted: the three cases below are the same complaint seen through progressively
    /// weaker evidence, so saying all three would be saying it three times.
    ///
    /// The consequence differs by case and the copy must not overstate it. With 3+ sets the
    /// mis-log is ALSO an anomaly, so it is already excluded from the working load and does
    /// NOT become the best — only a set that survived as `.working` is actually driving
    /// progression. Prefer that one when it exists so the sentence and the set it points at
    /// agree.
    private var setNotices: [String] {
        var notices: [String] = []

        if let implausible = progressionAnalysis.implausibleSets.first(where: { $0.role == .working })
            ?? progressionAnalysis.implausibleSets.first {
            notices.append(
                implausible.role == .working
                    ? "Check Set \(implausible.setNumber): \(formatLoad(implausible.weightLbs)) looks like a typing slip. Fix it — left as-is it becomes your best and your next target."
                    : "Check Set \(implausible.setNumber): \(formatLoad(implausible.weightLbs)) looks like a typing slip. It's already being left out of your progression — fix it so your log reads right."
            )
        } else if let anomaly = progressionAnalysis.anomalies.first {
            let reference = progressionAnalysis.workingWeight ?? anomaly.weightLbs
            notices.append(
                "Check Set \(anomaly.setNumber): \(formatLoad(anomaly.weightLbs)) is well above your \(formatLoad(reference)) working sets. Confirm or fix the entry — it isn't used for progression."
            )
        } else if let hist = historicalLoadAnomaly {
            notices.append(
                "Check Set \(hist.setNumber): \(formatLoad(hist.weight)) is a big jump from last session's \(formatLoad(hist.reference)). Confirm it — a mis-log here would set a false best and skew your next target."
            )
        }

        // How today's work departed from what was prescribed. Descriptive only — the
        // progression bullet in the guidance tile above owns every statement about what to
        // load next. Still capped at two: grouping them removed the stacked boxes, not the
        // risk of a set-by-set list burying the card.
        notices.append(contentsOf: summary.adherence.prefix(2).map(\.noticeText))

        return notices
    }

    private var exerciseHeader: some View {
        HStack(spacing: 12) {
            Button {
                onToggle()
            } label: {
                // Three distinct marks, because "settled" and "performed" are different
                // things: a filled green check for work actually done as written, a filled
                // neutral check for a lift that is resolved but was skipped or left short,
                // and an empty circle for outstanding work.
                // Filled once resolved, but green ONLY for work performed as written. A lift
                // skipped for pain or ticked off with nothing logged reads as settled, not as
                // an achievement.
                Image(systemName: summary.state.isResolved ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(summary.deservesCleanCompletionTreatment ? TFColor.success : Color.secondary)
            }
            // A glyph is not a target. Both controls in this header were sized by their icon —
            // roughly 20pt for the circle and 12pt for the caret — sitting a few points apart
            // on the screen used mid-set with chalky hands. Missing the caret and hitting the
            // circle does not just fail, it marks the exercise complete.
            .frame(minWidth: TFTapTarget.minimum, minHeight: TFTapTarget.minimum)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel(exercise.isCompleted ? "Mark \(exercise.exerciseName) incomplete" : "Mark \(exercise.exerciseName) complete")

            VStack(alignment: .leading, spacing: 2) {
                // Completed exercises are dimmed, not struck through: a line through the
                // title reads as "deleted/cancelled," the opposite of "done." The green
                // check plus the muted color already communicate completion.
                Text(exercise.exerciseName)
                    .font(.subheadline.bold())
                    .foregroundStyle(summary.state.isResolved ? .secondary : .primary)

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
                    .frame(minWidth: TFTapTarget.minimum, minHeight: TFTapTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse \(exercise.exerciseName)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        // The name and the prescription pills are one unit — the pills say what to do with
        // the movement named directly above them. 10pt here plus 14pt of body padding put
        // 24pt between them, which read as two separate blocks.
        .padding(.bottom, 2)
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

            // Coaching provenance is deliberately NOT shown here. "Written by AI Coach" told
            // the lifter nothing they could act on mid-set, and its siblings ("Built by the
            // training engine") read as an apology for the cue they were about to follow.
            // `coachingSource` is still recorded on every exercise and still surfaced in the
            // generator lab, where auditing where a cue came from is the actual job.
        }
    }

    /// - Parameter isClearable: false when the qualifier was DERIVED rather than stored (a
    ///   lift ticked off with sets outstanding carries no `completionStatus`), in which case
    ///   there is nothing for a Clear button to clear.
    private func completionStatusRow(
        _ label: String,
        isSkip: Bool,
        isClearable: Bool,
        needsLogging: Bool = false
    ) -> some View {
        let tint = isSkip ? TFColor.danger : TFColor.warning
        return HStack(spacing: 6) {
            Image(systemName: isSkip ? "forward.fill" : "arrow.triangle.swap")
                .font(.caption2)
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(tint)
            Spacer()
            if needsLogging {
                Button {
                    onLogWeight()
                } label: {
                    Text("Log what you did")
                        .font(.caption2.bold())
                        .foregroundStyle(TFColor.accent)
                        .frame(minHeight: TFTapTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if isClearable {
                Button {
                    onClearStatus()
                } label: {
                    Text("Clear")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: TFTapTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(tint.opacity(0.06))
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
                        onSetStatus(status)
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

            if let best = bestSummaryText {
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
    let label: String
    /// Plain-language meaning, shown on tap. `nil` for chips that need no gloss — a set count
    /// and a rep range explain themselves.
    ///
    /// "Tempo 3-0-1-0" and "RIR 2" do not. They were inert notation with no affordance to
    /// learn them: fine for the person who configured the programme, a wall for anyone else
    /// and for that same person on a lift they have not touched in three months.
    var explanation: String? = nil

    /// Labels are unique within one prescription (one sets chip, one reps chip, one tempo,
    /// one RIR), so the label is the identity. This used to be keyed by the leading SF Symbol
    /// as well, which no longer exists.
    var id: String { label }
}

struct ExercisePrescriptionPillRow: View {
    let items: [ExercisePrescriptionPillData]

    /// Which chip is currently explaining itself. Held here rather than per-chip so opening
    /// one closes any other.
    @State private var explainingID: String?

    /// At accessibility sizes a chip cannot hold its line in half the card width, so the grid
    /// drops to one column rather than shrinking text toward illegibility.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columnCount: Int { dynamicTypeSize >= .accessibility1 ? 1 : 2 }

    /// One line at normal text sizes; the stacked grid only at accessibility sizes.
    ///
    /// HISTORY — read before "restoring" the grid
    /// ------------------------------------------
    /// Three layouts have shipped here. The first packed chips left-to-right and wrapped when
    /// full, which stranded RIR alone on a second row and — because chip widths follow their
    /// content ("6-10 reps" is narrower than "10-14 reps") — moved the wrap point and every
    /// x-position from card to card, so no two cards lined up while scrolling a day.
    ///
    /// The fix was a fixed two-column grid, which made position independent of content. That
    /// solved alignment but spent two 44pt rows plus spacing (~95pt) on four short values, on
    /// the one screen used mid-set. On a real day — see the Day 16 report — the prescription
    /// alone pushed the log button, the last-session panel and the cue below the fold, so
    /// reading what to do required scrolling away from the thing being read.
    ///
    /// This is the third: a single row, leading SF Symbols removed (they cost roughly 20pt of
    /// width each and carried no information the label did not already carry). It costs the
    /// cross-card column alignment the grid bought, which is a real loss but a smaller one —
    /// with a single row the chips still share a left edge, and only the interior boundaries
    /// drift. It buys back ~51pt on every exercise card.
    ///
    /// The 44pt tap target on the explainer chips is NOT part of the trade and must survive
    /// any future tightening here: it is what makes Tempo and RIR learnable rather than inert
    /// notation. Height is unchanged at 44pt; only the second row is gone.
    ///
    /// Accessibility sizes keep the stacked layout. One row cannot hold four chips once the
    /// text is that large, and shrinking to fit is precisely the wrong response to someone
    /// asking for bigger text.
    ///
    /// `ViewThatFits` rather than a width guess. A four-chip prescription carrying a full tempo
    /// string ("Tempo 3-0-1-0") measures within a few points of the card's content width on a
    /// standard phone and over it on a small one, so committing unconditionally to one row would
    /// buy the height back by scaling caption2 toward 8pt — unreadable at arm's length, mid-set,
    /// which is the only moment this row is ever read. One row when it genuinely fits, the
    /// stacked pair when it does not.
    var body: some View {
        if dynamicTypeSize >= .accessibility1 {
            stackedRows
        } else {
            ViewThatFits(in: .horizontal) {
                singleRow
                stackedRows
            }
        }
    }

    /// Natural widths, not equal cells: four equal columns would size every chip to the widest
    /// ("Tempo 3-0-1-0") and overflow the card, while natural widths let the short values stay
    /// short and leave the slack where it is needed.
    ///
    /// `fixedSize` on the horizontal axis is what makes `ViewThatFits` able to reject this
    /// layout: without it the chips would compress to fit any width offered, the row would
    /// always "fit", and the stacked fallback would be dead code.
    private var singleRow: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                chip(for: item, fillsCell: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 7) {
                    // Cell sizing lives in `chip(for:)` so it applies uniformly rather than
                    // being reapplied here per placement.
                    ForEach(row) { item in
                        chip(for: item, fillsCell: true)
                    }
                    // Keeps a short final row's cells the same width as every other row's, so
                    // a 3-chip prescription still aligns with a 4-chip one. At most one
                    // filler is ever needed (two columns, so a short row holds exactly one),
                    // which avoids a ForEach over a computed range.
                    if row.count < columnCount {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var rows: [[ExercisePrescriptionPillData]] {
        stride(from: 0, to: items.count, by: columnCount).map { start in
            Array(items[start..<min(start + columnCount, items.count)])
        }
    }

    @ViewBuilder
    private func chip(for item: ExercisePrescriptionPillData, fillsCell: Bool) -> some View {
        let content = HStack(spacing: 4) {
            Text(item.label)
                .font(.caption2.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                // The single row does NOT get a lower floor. `ViewThatFits` hands the row to
                // the stacked layout when it will not fit at this size, so scaling stays a
                // rounding allowance rather than the mechanism that makes one row possible —
                // which is what would have driven caption2 toward 8pt on a small phone.
                .minimumScaleFactor(0.82)
            // A quiet affordance: without it a tappable chip is indistinguishable from an
            // inert one, which is the state the whole row was in.
            if item.explanation != nil {
                Image(systemName: "questionmark.circle")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, fillsCell ? 9 : 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .clipShape(Capsule())

        // EVERY chip gets the same cell, interactive or not.
        //
        // The tap-target fix originally applied this minimum height only to chips that could
        // explain themselves, which made Tempo and RIR 44pt tall while "sets" and "reps"
        // stayed around 26pt. The layout top-aligns its items, so a taller chip renders its
        // capsule centred — roughly 9pt below its shorter neighbours. That is the misalignment
        // on the card: the two chips carrying a "?" visibly sat lower than the two without.
        //
        // Grouping equal-height chips into the same grid row would hide it, but only by luck
        // of the pairing. Uniform cells make alignment a property of every chip rather than of
        // how they happen to be arranged, so it holds for any future set of chips.
        //
        // Filling the cell width also gives the interactive chips a target of roughly the
        // half-card width rather than the glyph — comfortably past the 44pt minimum in the
        // dimension that is hard to hit — without adding any height to do it.
        //
        // In the single row there is no cell to fill: `maxWidth: .infinity` there would force
        // four equal columns and blow past the card's width. The chip takes its natural width
        // instead, which is still well past 44pt horizontally for every label shown here
        // ("RIR 1", the shortest, is ~68pt with its "?" and padding). The 44pt MINIMUM HEIGHT
        // stays on every chip in both layouts — that is the part that is load-bearing for
        // touch, and dropping it to save a few more points would re-break the tap target and
        // the top-alignment defect described above.
        let cell = content
            .frame(
                // Spelled `CGFloat.infinity` rather than `.infinity`: the parameter is
                // `CGFloat?`, and the leading-dot form does not infer through the Optional.
                maxWidth: fillsCell ? CGFloat.infinity : nil,
                minHeight: TFTapTarget.minimum,
                alignment: .leading
            )

        if let explanation = item.explanation {
            Button {
                TFHaptics.impact(.light)
                explainingID = item.id
            } label: {
                cell.contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .popover(
                    isPresented: Binding(
                        get: { explainingID == item.id },
                        // Guarded on identity: a dismissal callback arriving after another
                        // chip has claimed `explainingID` would otherwise close the new
                        // popover instead of the one that actually went away.
                        set: { if !$0, explainingID == item.id { explainingID = nil } }
                    )
                ) {
                    Text(explanation)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .padding()
                        .frame(maxWidth: 300)
                        .presentationCompactAdaptation(.popover)
                }
                .accessibilityLabel(item.label)
                .accessibilityHint("Double tap to explain")
        } else {
            cell.accessibilityElement(children: .combine)
        }
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
    /// Handed straight through to the full-screen timer's set-entry panel: the panel shows
    /// this session's sets and writes through `onLogSet`, which is the card's one and only
    /// save path. Nothing about set logging is duplicated here.
    let loggedSets: [SetLogEntry]
    let suggestedWeight: Double?
    let suggestedReps: Int?
    let targetRepsPlaceholder: Int?
    let onLogSet: (Int, Double, Int, Double?) -> Void

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
            // A confirmed set starts rest only if the clock is sitting still. It used to
            // restart from full unconditionally, which broke the common order of events:
            // finish the set, hit start yourself, then log the numbers a few seconds later
            // — and watch the countdown you were already running jump back to the top.
            // A timer that is already counting down is now left completely alone.
            guard let id = note.object as? PersistentIdentifier,
                  id == exercise.persistentModelID else { return }
            guard !isRestTimerActive else { return }
            didCompleteRestTimer = false
            remainingRestSeconds = exercise.restSeconds
            restEndDate = Date().addingTimeInterval(Double(remainingRestSeconds))
            isRestTimerActive = true
            startRestTimer()
        }
        .fullScreenCover(isPresented: $showExpandedRestTimer) {
            RestTimerFullscreen(
                exerciseName: exercise.exerciseName,
                prescriptionLabel: "\(exercise.sets) sets x \(exercise.reps) reps",
                timeText: restDisplayText,
                accent: timerAccent,
                isTimerActive: isRestTimerActive,
                progress: restProgress,
                programmedSets: exercise.sets,
                loggedSets: loggedSets,
                suggestedWeight: suggestedWeight,
                suggestedReps: suggestedReps,
                targetRepsPlaceholder: targetRepsPlaceholder,
                onLogSet: onLogSet,
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

/// Full-screen rest timer with an inline set-entry panel.
///
/// The panel exists so a working set never costs a swipe: the countdown stays on screen
/// while the numbers for the set just finished are typed and confirmed. It writes through
/// `onLogSet`, which is the card's SAME save path as the inline "Log sets" list — there is
/// deliberately no second way for training data to reach storage. A set confirmed here is
/// indistinguishable from one confirmed in the list, and appears there immediately.
///
/// Status text ("Paused"/"Running") and the "Exercise N" line are intentionally absent. The
/// clock and its buttons already say what state it is in, and the exercise name says which
/// lift it is; the space they used belongs to the set entry.
struct RestTimerFullscreen: View {
    let exerciseName: String
    let prescriptionLabel: String
    let timeText: String
    let accent: Color
    let isTimerActive: Bool
    let progress: Double
    let programmedSets: Int
    /// This session's sets, live from the card's query — so stepping back to an already
    /// logged set shows what was actually stored, not a stale local copy.
    let loggedSets: [SetLogEntry]
    let suggestedWeight: Double?
    let suggestedReps: Int?
    let targetRepsPlaceholder: Int?
    let onLogSet: (Int, Double, Int, Double?) -> Void
    let onToggle: () -> Void
    let onReset: () -> Void
    let onClose: () -> Void

    @State private var currentSet = 1
    @State private var didPickStartingSet = false
    @State private var draftWeight: [Int: String] = [:]
    @State private var draftReps: [Int: String] = [:]
    @State private var draftRIR: [Int: String] = [:]
    @FocusState private var focusedField: FieldKey?

    enum FieldKey: Hashable {
        case weight
        case reps
        case rir
    }

    /// Typing is the one state that reshapes this screen: the number pad covers the lower
    /// half of the phone, so the clock shrinks and the transport controls stand down rather
    /// than letting the countdown disappear behind the keyboard.
    private var isEditing: Bool { focusedField != nil }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, accent.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }

            VStack(spacing: isEditing ? 12 : 20) {
                HStack {
                    Button("Done") {
                        focusedField = nil
                        onClose()
                    }
                    .font(.headline.bold())
                    .foregroundStyle(.white.opacity(0.9))

                    Spacer()
                }

                Spacer(minLength: 0)

                Text(exerciseName)
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(prescriptionLabel)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)

                setEntryPanel

                Text(timeText)
                    // Rounded, not the default face: at 92pt the stock system digits read as
                    // a stopwatch readout dropped onto the screen. `monospacedDigit` still
                    // applies, so the clock keeps a fixed width and does not twitch as the
                    // seconds roll over.
                    .font(.system(size: isEditing ? 34 : 92, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if !isEditing {
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
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .animation(.easeOut(duration: 0.2), value: isEditing)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear {
            // Once per presentation. Re-picking on every redraw would drag the panel off a
            // set being edited the moment the query refreshed underneath it.
            guard !didPickStartingSet else { return }
            didPickStartingSet = true
            currentSet = firstUnloggedSet()
        }
        .statusBarHidden()
    }

    // MARK: - Set entry

    private var setEntryPanel: some View {
        VStack(spacing: 10) {
            // Every other line on this screen is centred, so the set stepper is too. The
            // "n/n logged" readout that used to sit at the trailing edge is gone: the card
            // this cover was opened from already carries that count, and here it only
            // competed for attention with the number actually being typed.
            HStack(spacing: 2) {
                stepButton("chevron.left", enabled: currentSet > 1) { step(-1) }

                Text("Set \(currentSet)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    // Fixed width so reaching set 10 does not shove the two chevrons apart.
                    .frame(minWidth: 62)

                stepButton("chevron.right", enabled: currentSet < totalSets) { step(1) }
            }

            // Sized to survive the narrowest phone once the trailing Spacer went away:
            // centred content has no slack to give back, so the fields and gaps are tighter
            // than the leading-aligned row they replaced.
            HStack(spacing: 6) {
                entryField(text: weightBinding, placeholder: "lb", key: .weight, wholeNumbers: false, width: 72)

                Text("\u{00D7}")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))

                entryField(text: repsBinding, placeholder: repsPlaceholder, key: .reps, wholeNumbers: true, width: 58)

                Text("reps")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    // A fixed gap, not a Spacer: a Spacer in a centred row expands and
                    // throws the whole group back out to the screen edges.
                    .padding(.trailing, 8)

                Text("RIR")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))

                entryField(text: rirBinding, placeholder: "\u{2014}", key: .rir, wholeNumbers: false, width: 48)

                Button {
                    confirmCurrentSet()
                } label: {
                    Image(systemName: isCurrentSetLogged ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(canConfirm ? Color.white : Color.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canConfirm)
                .accessibilityLabel(isCurrentSetLogged ? "Update set \(currentSet)" : "Confirm set \(currentSet)")
            }

            bodyweightToggle
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// Bodyweight is a choice you make, not a consolation prize for leaving the field blank.
    ///
    /// It used to appear only while the weight field was empty, which hid it in the two
    /// states that matter most: the field PRE-FILLS from history, so a movement loaded last
    /// session but done with no load today offered no way in at all, and a bodyweight set
    /// restored from history showed nothing to confirm that is what it was. The decimal pad
    /// cannot type "BW", so there was no fallback either.
    ///
    /// So it is always on screen and reads its own state: filled means this set is logging as
    /// bodyweight, tapping again empties the field so a number can be typed instead.
    private var bodyweightToggle: some View {
        Button {
            toggleBodyweight()
        } label: {
            Label("Bodyweight", systemImage: "figure.core.training")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isBodyweightSelected ? accent : Color.white.opacity(0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isBodyweightSelected ? Color.white : Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bodyweight, no external load")
        .accessibilityHint(isBodyweightSelected ? "Clears the weight so a load can be typed" : "Logs this set with no external load")
    }

    private var isBodyweightSelected: Bool {
        weightBinding.wrappedValue
            .trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare("BW") == .orderedSame
    }

    private func toggleBodyweight() {
        focusedField = nil
        TFHaptics.impact(.light)
        guard !isBodyweightSelected else {
            // Empty string, NOT nil: nil falls back to the history prefill, which is what
            // put "BW" there in the first place, so clearing would appear to do nothing.
            draftWeight[currentSet] = ""
            return
        }
        draftWeight[currentSet] = "BW"
        // A bodyweight movement usually has no load history to prefill reps from, so seed
        // the programmed target — otherwise the set dead-ends on a disabled checkmark.
        if repsBinding.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty,
           let target = targetRepsPlaceholder ?? suggestedReps {
            draftReps[currentSet] = "\(target)"
        }
    }

    /// Bare chevrons. The filled circles behind them read as two more controls parked next
    /// to the set number instead of part of it. Losing the circle loses the only thing that
    /// showed how big the target was, so the target is stated outright — and it is now the
    /// full 44pt minimum rather than the 30pt the artwork used to imply.
    private func stepButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Color.white.opacity(0.7) : Color.white.opacity(0.18))
                .frame(width: TFTapTarget.minimum, height: TFTapTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(systemName == "chevron.left" ? "Previous set" : "Next set")
    }

    private func entryField(text: Binding<String>, placeholder: String, key: FieldKey, wholeNumbers: Bool, width: CGFloat) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.white.opacity(0.35)))
            .keyboardType(wholeNumbers ? .numberPad : .decimalPad)
            .focused($focusedField, equals: key)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .tint(.white)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func step(_ delta: Int) {
        focusedField = nil
        currentSet = min(max(currentSet + delta, 1), totalSets)
    }

    private func confirmCurrentSet() {
        guard let weight = parsedWeight, let reps = parsedReps else { return }
        let confirmed = currentSet
        focusedField = nil
        TFHaptics.impact(.light)
        onLogSet(confirmed, weight, reps, parsedRIR)

        // The set that fills the prescription finishes the exercise, and the card owning this
        // cover collapses itself the instant that happens (`autoCompleteAfterFinalSet`) —
        // taking the presenter, and therefore this screen, with it. Leaving under our own
        // power turns a view yanked out mid-animation into an ordinary dismissal.
        let remaining = Set(1...totalSets).subtracting(Set(loggedSets.map(\.setNumber)).union([confirmed]))
        if remaining.isEmpty {
            onClose()
            return
        }

        // `loggedSets` has not refreshed yet at this instant, so the set just written is
        // added by hand when choosing where to land next.
        let next = firstUnloggedSet(alsoLogged: [confirmed])
        guard next != confirmed else { return }
        currentSet = next
        // Drop any stale draft so the new set falls back to prefill from real history.
        draftWeight[next] = nil
        draftReps[next] = nil
        draftRIR[next] = nil
    }

    // MARK: - Set bookkeeping

    /// Mirrors `InlineSetLogger.programmedCount`: a set logged beyond the prescription
    /// raises the bar rather than becoming unreachable from this panel.
    private var totalSets: Int {
        max(programmedSets, loggedSets.map(\.setNumber).max() ?? 0, 1)
    }

    private func loggedSet(_ n: Int) -> SetLogEntry? {
        loggedSets.first { $0.setNumber == n }
    }

    private var isCurrentSetLogged: Bool { loggedSet(currentSet) != nil }

    private func firstUnloggedSet(alsoLogged extra: Set<Int> = []) -> Int {
        let done = Set(loggedSets.map(\.setNumber)).union(extra)
        for n in 1...totalSets where !done.contains(n) { return n }
        return totalSets
    }

    // MARK: - Drafts & parsing (same rules as the inline logger)

    private var repsPlaceholder: String {
        targetRepsPlaceholder.map(String.init) ?? "reps"
    }

    private func defaultWeightText(_ n: Int) -> String {
        if let logged = loggedSet(n) {
            return WorkoutProgressionEngine.isBodyweightEquivalent(logged.weightLbs) ? "BW" : formatWeight(logged.weightLbs)
        }
        // nil = no history at all; leave it empty rather than inventing a load.
        guard let w = loggedSets.last?.weightLbs ?? suggestedWeight else { return "" }
        return WorkoutProgressionEngine.isBodyweightEquivalent(w) ? "BW" : formatWeight(w)
    }

    private func defaultRepsText(_ n: Int) -> String {
        if let logged = loggedSet(n) { return "\(logged.repsCompleted)" }
        if let r = loggedSets.last?.repsCompleted ?? suggestedReps, r > 0 { return "\(r)" }
        return ""
    }

    private func defaultRIRText(_ n: Int) -> String {
        guard let rir = loggedSet(n)?.rir else { return "" }
        return rir.rounded() == rir ? String(Int(rir)) : String(format: "%.1f", rir)
    }

    private var weightBinding: Binding<String> {
        let n = currentSet
        return Binding(get: { draftWeight[n] ?? defaultWeightText(n) }, set: { draftWeight[n] = $0 })
    }

    private var repsBinding: Binding<String> {
        let n = currentSet
        return Binding(get: { draftReps[n] ?? defaultRepsText(n) }, set: { draftReps[n] = $0 })
    }

    private var rirBinding: Binding<String> {
        let n = currentSet
        return Binding(get: { draftRIR[n] ?? defaultRIRText(n) }, set: { draftRIR[n] = $0 })
    }

    /// "BW" is the only way to log a 0 load; a typed number must be positive.
    private var parsedWeight: Double? {
        let t = weightBinding.wrappedValue.trimmingCharacters(in: .whitespaces)
        if t.caseInsensitiveCompare("BW") == .orderedSame { return 0 }
        guard let v = Double(t.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return v
    }

    private var parsedReps: Int? {
        let t = repsBinding.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard let v = Int(t), v > 0 else { return nil }
        return v
    }

    private var parsedRIR: Double? {
        let t = rirBinding.wrappedValue
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let v = Double(t), (0...6).contains(v) else { return nil }
        return v
    }

    private var canConfirm: Bool {
        parsedWeight != nil && parsedReps != nil
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
        // Markers come from `CoachingProse` so the validator cuts the briefing at exactly the
        // place this card does. Listed longest-first there, which matters: replacing "Warm-up:"
        // before "Warm-up checklist:" would leave a stray "checklist:" in the warm-up text.
        var normalized = text
        for marker in CoachingProse.warmupSectionMarkers {
            normalized = normalized.replacingOccurrences(of: marker, with: "|", options: .caseInsensitive)
        }

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

        // Only the LABEL form ("Moderate Weight:", "Week 2 Heavy Weight") is a prescription.
        // A bare adjective is ordinary coaching prose — "use a moderate load", "don't go heavy
        // here" — and reading it as a prescription both mislabels the exercise and, worse, used
        // to license the unconditional strip below that deleted the word out of the sentence.
        let intensity = firstCapture(in: trimmed, pattern: #"(?i)\b(light|moderate|heavy)\s+weight\b"#)
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
        // NO bare-adjective strip here. The two label forms above already remove the
        // prescription header. Deleting every "light"/"moderate"/"heavy" from the note body
        // rewrote real coaching into nonsense on the card — "Use a moderate load and control
        // the eccentric" rendered as "Use a load and control the eccentric", and "Don't go
        // heavy here" rendered as "Don't go here", which inverts a caution into an instruction.
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

    /// Shown when the graded session logged fewer sets than it was prescribed: the load was
    /// never tested against the full prescription, so nothing about it has been earned yet.
    ///
    /// Distinct from `completePrescribedSets`, which resolves a disagreement between an AI
    /// note and the structured set count. This one is a fact about work actually done.
    static func finishPrescribedSets(logged: Int, prescribed: Int) -> ProgressionSuggestion {
        ProgressionSuggestion(
            icon: "hand.raised.fill",
            text: "You logged \(logged) of \(setsLabel(prescribed)) — finish the prescription at this load before adding weight",
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

    /// "both sets finished under 15" vs "1 of 3 sets finished under 15".
    ///
    /// The distinction is the entire point of the sentence. One slipped set is an ordinary
    /// session and the load is fine; every set under the floor means the load is wrong for
    /// the prescribed range. The previous single phrasing ("a working set dropped to N")
    /// described both cases identically, so the harder one read as the milder one.
    ///
    /// Only ever called on the per-set branch, where `holdBelowRange` guarantees at least
    /// one miss; the zero case is defensive, not expected.
    private static func belowFloorPhrase(missed: Int, of total: Int, floor: Int) -> String {
        guard missed > 0, total > 0 else { return "a working set finished under \(floor)" }
        if missed < total {
            return "\(missed) of \(setsLabel(total)) finished under \(floor)"
        }
        switch total {
        case 1: return "your working set finished under \(floor)"
        case 2: return "both sets finished under \(floor)"
        default: return "all \(total) sets finished under \(floor)"
        }
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
        // Derived from `analysis` rather than from the decision, because the decision needs
        // it: whether this session is a one-off miss or a stall is part of what the verdict
        // IS, not a detail added afterwards.
        let belowFloorStreak = analysis.workingWeight.map {
            WorkoutProgressionEngine.belowFloorStreak(
                for: key,
                from: performanceHistory,
                workingWeight: $0,
                repFloor: repRange.low
            )
        } ?? 0
        guard let decision = WorkoutProgressionEngine.evaluate(
            analysis: analysis,
            summaryWeight: lastWeight,
            summaryReps: summaryRepsCompleted,
            repRange: repRange,
            effortSignal: effortSignal,
            belowFloorStreak: belowFloorStreak
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
                    ? "\(holdLabel) — \(belowFloorPhrase(missed: decision.belowFloorSetCount, of: decision.workingSetCount, floor: repRange.low)) (lowest was \(reps), target \(repRange.low)-\(repRange.high)); build every set to \(repRange.low) before adding"
                    : "Stay \(atLoad), focus on form and full ROM",
                color: TFColor.warning
            )
        case .reduceLoad:
            // A bodyweight movement has no load to take off, so the honest advice is to
            // regress the movement. The app must not name a specific regression it cannot
            // verify the lifter can do, so it says what it actually knows.
            guard !isBodyweight else {
                return ProgressionSuggestion(
                    icon: "arrow.down.circle.fill",
                    text: "Bodyweight has finished under \(repRange.low) reps \(decision.belowFloorStreak) sessions running — regress to an easier variation rather than repeating it",
                    color: TFColor.warning
                )
            }
            let easierText = formatWeight(
                WorkoutProgressionEngine.reducedLoad(from: decision.workingWeight, exerciseName: exerciseName)
            )
            return ProgressionSuggestion(
                icon: "arrow.down.circle.fill",
                text: "Drop to \(easierText) lb — \(weightText) lb has finished under \(repRange.low) reps \(decision.belowFloorStreak) sessions running; holding it has not brought the reps back",
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
                // Token, not a raw Color — every other suggestion here uses one (INC-7).
                color: TFColor.info
            )
        }
    }
}

/// The two things the card says about *how to train this lift*, in one tile: what to do
/// about load next time, and how to execute the reps.
///
/// They used to be two separately tinted banners with the last-session strip between them.
/// Under a single set logger that read as three competing coloured boxes mid-set, which is
/// exactly when the lifter has the least attention to spend deciding which one matters.
/// Nothing was cut — each sentence still gets its own bulleted line and its own icon — the
/// card just presents one block of guidance instead of a stack.
///
/// The tile is deliberately neutral rather than tinted. Two bullets that mean different
/// things cannot share one honest tint, and the icon still carries the colour signal:
/// green for "add load", amber for "hold", the lightbulb for the cue.
struct ExerciseGuidanceCard: View {
    /// Absent when there is not enough history to say anything about load yet.
    let suggestion: ProgressionSuggestion?
    /// Empty when the exercise carries no usable coaching note; the bullet is then omitted.
    let coachingText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let suggestion {
                bullet(
                    kind: "Progression",
                    icon: suggestion.icon,
                    tint: suggestion.color,
                    text: suggestion.text
                )
            }

            if !coachingText.isEmpty {
                // Only between two bullets — a leading or trailing rule on a single-bullet
                // tile would be a divider dividing nothing. Inset past the icon column so it
                // separates the sentences rather than boxing them.
                if suggestion != nil {
                    Divider().padding(.leading, 32)
                }
                bullet(
                    kind: "Coaching cue",
                    icon: "lightbulb.fill",
                    tint: TFColor.warning,
                    text: coachingText
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Fixed-width icon column so both bullets hang their text off the same left edge no
    /// matter how wide the two glyphs are.
    ///
    /// - Parameter kind: what this bullet IS — spoken by VoiceOver, never drawn. The two
    ///   sentences used to sit in separately tinted boxes with written headings ("Cue",
    ///   "Coaching"), which is how a screen reader told them apart. Sighted users get that
    ///   from the icon and the divider once they share a tile; a screen reader gets nothing
    ///   from either, so the heading has to survive as a label or the distinction is lost.
    private func bullet(kind: String, icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(tint)
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind): \(text)")
    }
}

/// One warning tile carrying one or more sentences about today's logging.
///
/// Several warnings can be true of the same session at once. Each in its own tinted box read
/// as a pile of separate alarms; one box with a rule between the lines reads as what it is —
/// a short list of things to check before moving on.
struct SetAnomalyNotice: View {
    let texts: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(TFColor.warning)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(texts.enumerated()), id: \.offset) { index, text in
                    if index > 0 {
                        Divider().opacity(0.5)
                    }
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
/// `ExercisePerformanceLog` for one exercise, scoped to one program day
/// (`WorkoutDay.dayNumber`) and to that day's own calendar date, so a same-named exercise
/// on a different day — or stray data from another date — never shows up as this card's
/// progress. Inline set-by-set logging and the bulk sheet both funnel through here so they
/// share one log per session instead of fragmenting it — which would skew the summary, the
/// personal best, and the anomaly analysis. The "previous session" lookup deliberately stays
/// cross-day so progression continuity tracks the exercise across the whole program.
///
/// "That day's own calendar date" is load-bearing, and it formerly read "today" instead. See
/// `sessionLog` for what that cost: every finished day reported that nothing had been logged.
///
/// Reads take a `@Query`-backed array (reactive UI). Writes fetch fresh from the
/// context so two quick taps cannot create a duplicate session log before the query
/// republishes.
@MainActor
enum SetLoggingService {

    // MARK: Reads (from a query-backed array)

    /// The one performance log holding this card's session, or nil when there is none.
    ///
    /// THE BUG THIS EXISTS TO FIX
    /// --------------------------
    /// This resolution used to be a single line — key, day number, and `loggedAt` on the same
    /// calendar day as `.now` — which silently encoded "the session being trained right now".
    /// Opening any day already trained therefore matched nothing, so a finished day showed
    /// "0/3", the "marked done with no sets logged" warning, and "Done · nothing logged", while
    /// the sets themselves sat untouched in the database. The giveaway on screen was the panel
    /// directly beneath, which rendered those very sets as "Last" — `previousSets` deliberately
    /// looks at other days, so the one lookup scoped to today found nothing and the one scoped
    /// to everything else found the session.
    ///
    /// Reads and writes both come through here so a card can never display one session and
    /// write into another.
    static func sessionLog(
        for exercise: WorkoutExercise,
        among logs: [ExercisePerformanceLog],
        on date: Date
    ) -> ExercisePerformanceLog? {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let dayNumber = exercise.day?.dayNumber ?? 0
        let matching = logs.filter {
            $0.canonicalExerciseKey == key && $0.workoutDayNumber == dayNumber
        }
        guard !matching.isEmpty else { return nil }

        // Sessions belong to a program; see `SessionLogResolution.belongsToProgram`.
        //
        // Empty means EMPTY — no falling back to the unscoped set. An earlier draft did, on the
        // theory that a restored backup might predate its program's creation date, and that
        // fallback was worse than the bug it guarded: on the first day of a new mesocycle every
        // day is untrained, so the scoped set is empty for every carried-over exercise, and the
        // fallback would hand back the ARCHIVED program's session — displaying old sets as
        // today's, and then, because writes resolve through this same function, merging new sets
        // into that old program's log and restamping it.
        let programStart = exercise.day?.program?.createdDate
        let pool = matching.filter {
            SessionLogResolution.belongsToProgram(logDate: $0.loggedAt, programStart: programStart)
        }
        guard !pool.isEmpty else { return nil }

        let index = SessionLogResolution.indexOfSession(
            candidateDates: pool.map(\.loggedAt),
            sessionDates: exercise.day?.sessionCalendarDates ?? [],
            viewingDate: date
        )
        return index.map { pool[$0] }
    }

    /// Sets logged for this card's session — today's while training, that day's when looking
    /// back at a day already trained.
    static func loggedSets(
        for exercise: WorkoutExercise,
        in logs: [ExercisePerformanceLog],
        on date: Date = .now
    ) -> [SetLogEntry] {
        let log = sessionLog(for: exercise, among: logs, on: date)
        return (log?.decodedSetLogs ?? []).sorted { $0.setNumber < $1.setNumber }
    }

    /// Most recent completed session strictly before THIS card's session — used for the "last
    /// session" panel and the progression suggestion (which targets the next session).
    ///
    /// Anchored to the day being viewed rather than to today. Anchoring to today was harmless
    /// only while the card could not show a past day's own sets: now that it can, a day trained
    /// three weeks ago would otherwise show a session from LAST week as what came "last" —
    /// a reference from that day's future, sitting under a progression suggestion built from it.
    static func previousSets(
        for exercise: WorkoutExercise,
        in logs: [ExercisePerformanceLog],
        on date: Date = .now
    ) -> [SetLogEntry] {
        (previousLog(for: exercise, in: logs, on: date)?.decodedSetLogs ?? [])
            .sorted { $0.setNumber < $1.setNumber }
    }

    /// The session `previousSets` reads from, as the log itself.
    ///
    /// Split out so callers can also ask what that session was PRESCRIBED, which is the only
    /// way to grade it against the range it actually ran under rather than today's. The
    /// resolution is unchanged and deliberately shared — two copies of this cutoff logic
    /// would be two chances for the sets and the prescription to come from different
    /// sessions.
    static func previousLog(
        for exercise: WorkoutExercise,
        in logs: [ExercisePerformanceLog],
        on date: Date = .now
    ) -> ExercisePerformanceLog? {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let current = sessionLog(for: exercise, among: logs, on: date)
        let cutoff = SessionLogResolution.previousSessionCutoff(
            currentSessionDate: current?.loggedAt,
            sessionDates: exercise.day?.sessionCalendarDates ?? [],
            viewingDate: date
        )
        return logs
            .filter {
                $0.canonicalExerciseKey == key
                    && !$0.setLogsJSON.isEmpty
                    // Identity is what guarantees the session on screen is never also the
                    // session before it. The cutoff is a chronology test, not a self-exclusion
                    // test; keeping the two jobs apart is what lets the cutoff stay tight
                    // enough to admit a genuinely earlier session from the same evening.
                    && $0 !== current
                    && $0.loggedAt < cutoff
            }
            .max { $0.loggedAt < $1.loggedAt }
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
        // Fetch first: whether this is the live session depends on what is already recorded
        // here, so the log has to be resolved before anything is decided about it.
        let dayLogs = storedDayLogs(for: exercise, modelContext: modelContext)
        let existing = sessionLog(for: exercise, among: dayLogs, on: date)
        let markers = sessionMarkers(for: exercise, dayLogs: dayLogs)
        let isLive = sessionIsLive(for: exercise, markers: markers, date: date)
        let stamp = sessionStamp(existing: existing, markers: markers, date: date, isLive: isLive)
        let log = existing ?? insertSessionLog(for: exercise, at: stamp, modelContext: modelContext)
        var sets = log.decodedSetLogs.filter { $0.setNumber != setNumber }
        sets.append(SetLogEntry(setNumber: setNumber, weightLbs: weightLbs, repsCompleted: reps, rir: rir))
        return apply(sets.sorted { $0.setNumber < $1.setNumber }, to: log, exercise: exercise, modelContext: modelContext, date: stamp, liveClockDate: isLive ? date : nil)
    }

    @discardableResult
    static func clearSet(
        setNumber: Int,
        for exercise: WorkoutExercise,
        modelContext: ModelContext,
        on date: Date = .now
    ) -> Bool {
        let dayLogs = storedDayLogs(for: exercise, modelContext: modelContext)
        guard let log = sessionLog(for: exercise, among: dayLogs, on: date) else { return true }
        let sets = log.decodedSetLogs.filter { $0.setNumber != setNumber }.sorted { $0.setNumber < $1.setNumber }
        if sets.isEmpty {
            modelContext.delete(log)
            return persist(modelContext)
        }
        let markers = sessionMarkers(for: exercise, dayLogs: dayLogs)
        let isLive = sessionIsLive(for: exercise, markers: markers, date: date)
        let stamp = sessionStamp(existing: log, markers: markers, date: date, isLive: isLive)
        return apply(sets, to: log, exercise: exercise, modelContext: modelContext, date: stamp, liveClockDate: isLive ? date : nil)
    }

    /// Replace this card's session with a full set list (the bulk sheet's save path).
    @discardableResult
    static func replaceSessionSets(
        _ sets: [SetLogEntry],
        for exercise: WorkoutExercise,
        modelContext: ModelContext,
        on date: Date = .now
    ) -> Bool {
        guard !sets.isEmpty else { return clearAllSessionSets(for: exercise, modelContext: modelContext, date: date) }
        let dayLogs = storedDayLogs(for: exercise, modelContext: modelContext)
        let existing = sessionLog(for: exercise, among: dayLogs, on: date)
        let markers = sessionMarkers(for: exercise, dayLogs: dayLogs)
        let isLive = sessionIsLive(for: exercise, markers: markers, date: date)
        let stamp = sessionStamp(existing: existing, markers: markers, date: date, isLive: isLive)
        let log = existing ?? insertSessionLog(for: exercise, at: stamp, modelContext: modelContext)
        return apply(sets.sorted { $0.setNumber < $1.setNumber }, to: log, exercise: exercise, modelContext: modelContext, date: stamp, liveClockDate: isLive ? date : nil)
    }

    // MARK: Internals

    private static func clearAllSessionSets(for exercise: WorkoutExercise, modelContext: ModelContext, date: Date) -> Bool {
        if let log = storedSessionLog(for: exercise, modelContext: modelContext, date: date) {
            modelContext.delete(log)
        }
        return persist(modelContext)
    }

    /// Everything already recorded against this exercise's DAY, fetched fresh from the context
    /// rather than from the query-backed array, so two quick taps cannot create a duplicate
    /// session log before the query republishes.
    ///
    /// The whole day, not just this exercise: `sessionMarkers` needs day-level evidence of when
    /// the session happened, and one fetch serves both that and the per-exercise lookup.
    private static func storedDayLogs(for exercise: WorkoutExercise, modelContext: ModelContext) -> [ExercisePerformanceLog] {
        let dayNumber = exercise.day?.dayNumber ?? 0
        let descriptor = FetchDescriptor<ExercisePerformanceLog>(
            predicate: #Predicate { $0.workoutDayNumber == dayNumber }
        )
        let logs = (try? modelContext.fetch(descriptor)) ?? []
        let programStart = exercise.day?.program?.createdDate
        return logs.filter {
            SessionLogResolution.belongsToProgram(logDate: $0.loggedAt, programStart: programStart)
        }
    }

    private static func storedSessionLog(for exercise: WorkoutExercise, modelContext: ModelContext, date: Date) -> ExercisePerformanceLog? {
        sessionLog(for: exercise, among: storedDayLogs(for: exercise, modelContext: modelContext), on: date)
    }

    /// Everything known about when this day's session happened — see
    /// `SessionLogResolution.sessionMarkers`.
    private static func sessionMarkers(for exercise: WorkoutExercise, dayLogs: [ExercisePerformanceLog]) -> [Date] {
        SessionLogResolution.sessionMarkers(
            clockStamps: exercise.day?.sessionCalendarDates ?? [],
            recordedLogDates: dayLogs.map(\.loggedAt)
        )
    }

    /// Whether the write is landing on the session being trained right now.
    ///
    /// Computed ONCE per write and threaded into everything that depends on it, so the stamp and
    /// the session clock can never disagree about which session this is.
    private static func sessionIsLive(
        for exercise: WorkoutExercise,
        markers: [Date],
        date: Date
    ) -> Bool {
        guard let day = exercise.day else { return false }
        // Open means "not deliberately finished and not yet rated" — necessary for a session to
        // be live, but nowhere near sufficient on its own. `SessionLogResolution.sessionIsLive`
        // explains why recency has to carry the rest.
        return SessionLogResolution.sessionIsLive(
            dayIsOpen: !day.isSessionClosed && day.feedbackSubmittedAt == nil,
            sessionDates: markers,
            writeDate: date
        )
    }

    /// When the work being recorded actually happened — see `SessionLogResolution.stamp` for
    /// the cases and why this is not simply `date`.
    private static func sessionStamp(
        existing: ExercisePerformanceLog?,
        markers: [Date],
        date: Date,
        isLive: Bool
    ) -> Date {
        SessionLogResolution.stamp(
            existingDate: existing?.loggedAt,
            sessionDates: markers,
            writeDate: date,
            sessionIsLive: isLive
        )
    }

    private static func insertSessionLog(for exercise: WorkoutExercise, at stamp: Date, modelContext: ModelContext) -> ExercisePerformanceLog {
        let log = ExercisePerformanceLog(
            loggedAt: stamp,
            exerciseName: exercise.exerciseName,
            weightLbs: 0,
            repsCompleted: nil,
            muscleTarget: exercise.muscleTarget,
            workoutDayNumber: exercise.day?.dayNumber ?? 0,
            prescribedSets: exercise.sets,
            prescribedReps: exercise.reps
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

    /// - Parameters:
    ///   - date: WHEN THE WORK HAPPENED — the session's stamp. Drives the log's own date and the
    ///     weight-summary record, so correcting a set on an old session leaves that session
    ///     where it belongs in the history.
    ///   - liveClockDate: WHEN THE TAP HAPPENED — real wall-clock — or nil when this write is not
    ///     landing on the session being trained right now.
    ///
    /// Two separate values because the session clock and the history stamp answer different
    /// questions, and each is wrong for the other's job:
    ///
    ///  * Passing the STAMP to `SessionLifecycle.noteSetLogged` freezes a live session's duration
    ///    the moment it crosses midnight — `noteSetLogged` ignores any date that is not today,
    ///    and a live session's stamp sits on yesterday from midnight onward.
    ///  * Passing the wall clock UNCONDITIONALLY corrupts old sessions. `noteSetLogged`'s own
    ///    guards are "not rated, not closed, date is today" — and the wall clock is always today,
    ///    while a day trained three weeks ago and never rated or finished passes the other two.
    ///    Correcting one of its sets would push its `sessionEndedAt` to now and report the
    ///    session as three weeks long. That path was hard to reach before, because a finished
    ///    day showed nothing logged to correct; this change is exactly what makes it ordinary.
    ///
    /// So liveness is decided once, by `sessionIsLive`, and the clock is only touched when the
    /// answer is yes.
    private static func apply(
        _ sets: [SetLogEntry],
        to log: ExercisePerformanceLog,
        exercise: WorkoutExercise,
        modelContext: ModelContext,
        date: Date,
        liveClockDate: Date?
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
        // Backfill only. A session already carrying a prescription keeps it: this same
        // funnel is how an OLD session gets corrected, and overwriting there would stamp
        // today's programming onto work done under a different one — the exact rewriting
        // of history this field exists to prevent.
        if log.recordedPrescribedSets == nil {
            log.prescribedSets = exercise.sets
        }
        if log.prescribedReps.isEmpty {
            log.prescribedReps = exercise.reps
        }

        let summary = summaryEntryOrCreate(for: exercise, weight: topWeight, reps: topReps, date: date, modelContext: modelContext)
        summary.applyLog(loggedAt: date, exerciseName: exercise.exerciseName, weightLbs: topWeight, repsCompleted: topReps, notes: summary.notes)

        if let liveClockDate {
            SessionLifecycle.noteSetLogged(for: exercise, at: liveClockDate)
        }

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
            // The decimal keyboard can't type "BW", so the option is offered explicitly. It
            // shows while the weight field is empty OR while this row is the one being
            // edited — that second case matters because the field PRE-FILLS from history, so
            // a movement loaded last session but done with no load today would otherwise
            // have no way in at all. It stands down once the row already reads "BW", and
            // never appears on rows sitting idle with a prefilled load.
            if !isBodyweightText(weightBinding(n).wrappedValue),
               weightBinding(n).wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty || focusedField == .weight(n) {
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

    private func isBodyweightText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("BW") == .orderedSame
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
