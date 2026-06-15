import SwiftUI
import SwiftData

struct WorkoutSessionFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let day: WorkoutDay

    @State private var effort: Int
    @State private var stimulus: Int
    @State private var pain: Int
    @State private var performance: WorkoutPerformanceRating
    @State private var notes: String
    @State private var sessionStartedAt: Date
    @State private var sessionEndedAt: Date

    init(day: WorkoutDay) {
        self.day = day
        _effort = State(initialValue: day.sessionEffort > 0 ? day.sessionEffort : 3)
        _stimulus = State(initialValue: day.stimulusQuality > 0 ? day.stimulusQuality : 3)
        _pain = State(initialValue: day.jointPain)
        _performance = State(initialValue: day.performanceRating ?? .same)
        _notes = State(initialValue: day.sessionFeedbackNotes)
        _sessionStartedAt = State(initialValue: day.sessionStartedAt ?? Calendar.current.date(byAdding: .hour, value: -1, to: .now) ?? .now)
        _sessionEndedAt = State(initialValue: day.sessionEndedAt ?? .now)
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

                ratingSection("Session effort", detail: "1 easy · 5 maximal", value: $effort, range: 1...5)
                ratingSection("Stimulus quality", detail: "How well the target muscles worked", value: $stimulus, range: 1...5)
                ratingSection("Joint pain", detail: "0 none · 5 severe", value: $pain, range: 0...5)

                Section {
                    DatePicker("Started", selection: $sessionStartedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Finished", selection: $sessionEndedAt, in: sessionStartedAt...Date(), displayedComponents: [.date, .hourAndMinute])
                    let durationMinutes = Int(sessionEndedAt.timeIntervalSince(sessionStartedAt) / 60)
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
                    Text("Tracking when you train helps identify your best time of day over time.")
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

    private func save() {
        let priorDate = day.feedbackSubmittedAt
        let priorEffort = day.sessionEffort
        let priorStimulus = day.stimulusQuality
        let priorPain = day.jointPain
        let priorPerformance = day.performanceRatingRaw
        let priorNotes = day.sessionFeedbackNotes
        let priorStartedAt = day.sessionStartedAt
        let priorEndedAt = day.sessionEndedAt

        day.feedbackSubmittedAt = .now
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
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
