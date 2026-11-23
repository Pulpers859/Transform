import SwiftUI
import SwiftData

struct WorkoutSessionFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let day: WorkoutDay
    /// What the session did, shown above the ratings (`WorkoutDayDetailView.sessionRecap`).
    var recap: [RecapLine] = []

    struct RecapLine: Identifiable {
        let name: String
        let loggedSets: Int
        let plannedSets: Int
        let skipped: Bool
        let newBest: String?
        /// A day can hold the same exercise twice, so the name is not an identity.
        let id = UUID()
    }

    @State private var effort: Int
    @State private var stimulus: Int
    @State private var pain: Int
    @State private var performance: WorkoutPerformanceRating
    @State private var notes: String
    @State private var sessionStartedAt: Date
    @State private var sessionEndedAt: Date

    init(day: WorkoutDay, recap: [RecapLine] = []) {
        self.day = day
        self.recap = recap
        // Unrated sessions start with NO effort or stimulus chosen (council review 2026-11-23).
        // Both used to start at 3, so tapping Save without touching them stored 3/3 as if the
        // lifter had chosen it, and those ratings feed next week's weight hold and the Workout
        // Timing card. 0 is "not chosen"; Save waits for a real choice.
        _effort = State(initialValue: day.sessionEffort)
        _stimulus = State(initialValue: day.stimulusQuality)
        _pain = State(initialValue: day.jointPain)
        _performance = State(initialValue: day.performanceRating ?? .same)
        _notes = State(initialValue: day.sessionFeedbackNotes)
        // Both stamps are normally auto-tracked. When a session has no start at all —
        // nothing logged, timer never tapped — fall back to the warm-up lead rather than
        // the old flat hour: an unknown session should open as a visibly small placeholder
        // to adjust, not as a plausible-looking 60 minutes the athlete might just save.
        let end = day.sessionEndedAt ?? .now
        let fallbackStart = end.addingTimeInterval(-Double(SessionLifecycle.inferredWarmupLeadMinutes) * 60)
        _sessionStartedAt = State(initialValue: day.sessionStartedAt ?? fallbackStart)
        _sessionEndedAt = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(day.dayName)
                        .font(.headline)
                    Text(day.muscleGroups)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !recap.isEmpty {
                    Section("Today") {
                        ForEach(recap) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(line.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(line.skipped ? "Skipped" : "\(line.loggedSets)/\(line.plannedSets) sets")
                                        .font(.caption.bold())
                                        .foregroundStyle(line.skipped || line.loggedSets < line.plannedSets ? Color.secondary : TFColor.success)
                                }
                                if let best = line.newBest {
                                    Label(best, systemImage: "trophy.fill")
                                        .font(.caption.bold())
                                        .foregroundStyle(TFColor.success)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                ratingSection("Session effort", detail: effort == 0 ? "1 easy · 5 maximal. Pick one to save." : "1 easy · 5 maximal", value: $effort, range: 1...5)
                ratingSection("Stimulus quality", detail: stimulus == 0 ? "How well the target muscles worked. Pick one to save." : "How well the target muscles worked", value: $stimulus, range: 1...5)
                ratingSection("Joint pain", detail: "0 none · 5 severe", value: $pain, range: 0...5)

                Section {
                    DatePicker("Started", selection: $sessionStartedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Finished", selection: $sessionEndedAt, in: sessionStartedAt...Date(), displayedComponents: [.date, .hourAndMinute])
                        // Moving Started past Finished pulls Finished along, so the picker never
                        // shows a time different from the one that would be saved (the picker's
                        // range only constrains new selections). Independent audit, 2026-11-18.
                        .onChange(of: sessionStartedAt) { _, newStart in
                            if sessionEndedAt < newStart { sessionEndedAt = newStart }
                        }
                    // Rounded, not truncated: a 22:50 session reading "22 min" looks like
                    // an off-by-one against the two clock times displayed right above it.
                    let durationMinutes = Int((sessionEndedAt.timeIntervalSince(sessionStartedAt) / 60).rounded())
                    if durationMinutes > 0 {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text("\(durationMinutes) min")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Workout time")
                } footer: {
                    if timesAreOrdered {
                        Text("Timed from ~10 min before your first set to when you finished. Adjust if needed.")
                    } else {
                        Text("Finished is before Started. Move one of them to save.")
                            .foregroundStyle(TFColor.danger)
                    }
                }

                Section("Performance") {
                    Picker("Compared with expected", selection: $performance) {
                        ForEach(WorkoutPerformanceRating.allCases) { rating in
                            Text(rating.rawValue).tag(rating)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Optional note") {
                    TextField("What felt unusually good or limited you?", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(day.hasSessionFeedback ? "Edit Feedback" : "Session Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!timesAreOrdered || !ratingsChosen)
                }
            }
        }
    }

    private func ratingSection(
        _ title: String,
        detail: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        Section {
            HStack {
                ForEach(Array(range), id: \.self) { rating in
                    Button {
                        value.wrappedValue = rating
                    } label: {
                        Text("\(rating)")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(value.wrappedValue == rating ? TFColor.accent : Color(.tertiarySystemFill))
                            .foregroundStyle(value.wrappedValue == rating ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text(detail)
        }
    }

    /// Moving "Started" past "Finished" used to save a session that ends before it begins,
    /// which every duration reader then treats as unknown. The Finished picker's lower bound
    /// follows Started, but only for new selections; the value already chosen can sit below it.
    private var timesAreOrdered: Bool {
        sessionEndedAt >= sessionStartedAt
    }

    private var ratingsChosen: Bool {
        effort > 0 && stimulus > 0
    }

    private func save() {
        guard timesAreOrdered, ratingsChosen else { return }
        let priorDate = day.feedbackSubmittedAt
        let priorEffort = day.sessionEffort
        let priorStimulus = day.stimulusQuality
        let priorPain = day.jointPain
        let priorPerformance = day.performanceRatingRaw
        let priorNotes = day.sessionFeedbackNotes
        let priorStartedAt = day.sessionStartedAt
        let priorEndedAt = day.sessionEndedAt
        let priorClosed = day.isSessionClosed

        day.feedbackSubmittedAt = .now
        // Rating the session settles it: nothing may move the clock afterwards, including
        // a set correction typed later.
        day.isSessionClosed = true
        day.sessionEffort = effort
        day.stimulusQuality = stimulus
        day.jointPain = pain
        day.performanceRating = performance
        day.sessionFeedbackNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        day.sessionStartedAt = sessionStartedAt
        day.sessionEndedAt = sessionEndedAt

        guard PersistenceReporter.save(modelContext, operation: "workout session feedback") else {
            modelContext.rollback()
            day.feedbackSubmittedAt = priorDate
            day.sessionEffort = priorEffort
            day.stimulusQuality = priorStimulus
            day.jointPain = priorPain
            day.performanceRatingRaw = priorPerformance
            day.sessionFeedbackNotes = priorNotes
            day.sessionStartedAt = priorStartedAt
            day.sessionEndedAt = priorEndedAt
            day.isSessionClosed = priorClosed
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        TFHaptics.success()
        dismiss()
    }
}
