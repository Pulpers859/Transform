import SwiftUI
import SwiftData

struct AddExerciseWeightSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: EntryField?

    let exercise: WorkoutExercise
    let weightSummary: ExerciseWeightEntry?

    @State private var loggedAt = Date()
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var notes = ""

    private let quickAdjustments: [Double] = [-10, -5, -2.5, 2.5, 5, 10]
    private let suggestedReps: [Int] = [5, 6, 8, 10, 12, 15]

    enum EntryField {
        case weight
        case reps
        case notes
    }

    var canSave: Bool {
        parsedWeight != nil
    }

    var parsedWeight: Double? {
        let cleaned = weightText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    var parsedReps: Int? {
        let cleaned = repsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let reps = Int(cleaned), reps > 0 else { return nil }
        return reps
    }

    var isKeyboardActive: Bool {
        focusedField != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        exerciseCard
                        if let weightSummary {
                            targetsCard(summary: weightSummary)
                        }
                        entryCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, isKeyboardActive ? 24 : 120)
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveEntry()
                    }
                    .bold()
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Save") {
                        saveEntry()
                    }
                    .bold()
                    .disabled(!canSave)

                    Spacer()

                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardActive {
                    bottomSaveBar
                }
            }
            .animation(.easeOut(duration: 0.2), value: isKeyboardActive)
            .onAppear {
                guard weightText.isEmpty, let weightSummary else { return }
                weightText = formatWeight(weightSummary.weightLbs)
                if let reps = weightSummary.repsCompleted {
                    repsText = String(reps)
                }
            }
        }
    }

    var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Exercise")

            Text(exercise.exerciseName)
                .font(.title3.bold())

            HStack(spacing: 8) {
                metricChip(icon: "square.stack.3d.up", text: "\(exercise.sets) sets")
                metricChip(icon: "arrow.left.arrow.right", text: "\(exercise.reps) target")
                if !exercise.muscleTarget.isEmpty {
                    metricChip(icon: "target", text: exercise.muscleTarget)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    func targetsCard(summary: ExerciseWeightEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Targets")

            HStack(spacing: 0) {
                summarySegment(
                    title: "Last",
                    weight: summary.weightLbs,
                    reps: summary.repsCompleted,
                    date: summary.loggedAt,
                    accent: .orange
                ) {
                    applyLast(summary)
                }

                Divider()
                    .padding(.vertical, 14)

                summarySegment(
                    title: "Best",
                    weight: resolvedBestWeight(from: summary),
                    reps: resolvedBestReps(from: summary),
                    date: resolvedBestDate(from: summary),
                    accent: .green
                ) {
                    applyBest(summary)
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    func summarySegment(
        title: String,
        weight: Double,
        reps: Int?,
        date: Date?,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                    .tracking(1.2)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatWeight(weight))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("lb")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }

                Text(reps.map { "\($0) reps" } ?? "Reps not logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(date?.formatted(date: .abbreviated, time: .shortened) ?? "No date")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("Tap to use")
                    .font(.caption2.bold())
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var entryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("New Entry")

            VStack(alignment: .leading, spacing: 8) {
                Text("Weight")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight)
                        .font(.system(size: 40, weight: .black, design: .rounded))

                    Text("lb")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Quick Adjust")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(quickAdjustments, id: \.self) { delta in
                        Button {
                            nudgeWeight(by: delta)
                        } label: {
                            Text(delta > 0 ? "+\(formatWeight(delta))" : formatWeight(delta))
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(delta > 0 ? Color.orange.opacity(0.14) : Color.primary.opacity(0.06))
                                .foregroundStyle(delta > 0 ? Color.orange : Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Reps Completed")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                TextField("Optional", text: $repsText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .reps)
                    .font(.title3.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedReps, id: \.self) { rep in
                            Button {
                                repsText = String(rep)
                            } label: {
                                Text("\(rep)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(repsText == String(rep) ? Color.orange.opacity(0.18) : Color.primary.opacity(0.06))
                                    .foregroundStyle(repsText == String(rep) ? Color.orange : Color.primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("When")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                DatePicker(
                    "Logged at",
                    selection: $loggedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Notes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                TextField("Optional cue, machine setting, or effort note", text: $notes, axis: .vertical)
                    .focused($focusedField, equals: .notes)
                    .lineLimit(2...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    var bottomSaveBar: some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(parsedWeight.map { "\(formatWeight($0)) lb" } ?? "Enter a valid weight")
                        .font(.headline)
                    Text(parsedReps.map { "\($0) reps logged" } ?? "Reps optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    saveEntry()
                } label: {
                    Text("Save Entry")
                        .font(.headline.bold())
                        .frame(minWidth: 132)
                        .padding(.vertical, 14)
                        .background(canSave ? Color.orange : Color.orange.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!canSave)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    func resolvedBestWeight(from summary: ExerciseWeightEntry) -> Double {
        summary.hasBestRecord ? summary.bestWeightLbs : summary.weightLbs
    }

    func resolvedBestDate(from summary: ExerciseWeightEntry) -> Date? {
        summary.bestLoggedAt ?? summary.loggedAt
    }

    func resolvedBestReps(from summary: ExerciseWeightEntry) -> Int? {
        summary.bestRepsCompleted ?? summary.repsCompleted
    }

    func applyLast(_ summary: ExerciseWeightEntry) {
        weightText = formatWeight(summary.weightLbs)
        repsText = summary.repsCompleted.map(String.init) ?? ""
        notes = summary.notes
        loggedAt = Date()
    }

    func applyBest(_ summary: ExerciseWeightEntry) {
        weightText = formatWeight(resolvedBestWeight(from: summary))
        repsText = resolvedBestReps(from: summary).map(String.init) ?? ""
        notes = summary.hasBestRecord ? summary.bestNotes : summary.notes
        loggedAt = Date()
    }

    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.orange)
            .tracking(1.4)
    }

    func metricChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.12))
        .foregroundStyle(.orange)
        .clipShape(Capsule())
    }

    func nudgeWeight(by delta: Double) {
        let base = parsedWeight ?? weightSummary?.weightLbs ?? 0
        let updated = max(0, base + delta)
        guard updated > 0 else {
            weightText = ""
            return
        }
        weightText = formatWeight(updated)
    }

    func saveEntry() {
        guard let weight = parsedWeight else { return }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let weightSummary {
            weightSummary.applyLog(
                loggedAt: loggedAt,
                exerciseName: exercise.exerciseName,
                weightLbs: weight,
                repsCompleted: parsedReps,
                notes: trimmedNotes
            )
        } else {
            let entry = ExerciseWeightEntry(
                loggedAt: loggedAt,
                exerciseName: exercise.exerciseName,
                weightLbs: weight,
                repsCompleted: parsedReps,
                notes: trimmedNotes
            )
            modelContext.insert(entry)
        }

        guard PersistenceReporter.save(modelContext, operation: "exercise weight summary") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    func formatWeight(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return String(Int(weight))
        }
        return String(format: "%.1f", weight)
    }
}
