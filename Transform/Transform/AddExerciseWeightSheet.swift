import SwiftUI
import SwiftData

struct AddExerciseWeightSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: EntryField?

    let exercise: WorkoutExercise
    let weightSummary: ExerciseWeightEntry?
    var latestSetLogs: [SetLogEntry] = []
    var todaysSetLogs: [SetLogEntry] = []

    @State private var setLogs: [SetLogDraft] = []
    @State private var notes = ""
    @State private var loggedAt = Date()
    @State private var didSave = false

    private let quickAdjustments: [Double] = [-10, -5, -2.5, 2.5, 5, 10]

    struct SetLogDraft: Identifiable {
        let id = UUID()
        var setNumber: Int
        var weightText: String
        var repsText: String
        var rirText: String
    }

    enum EntryField: Hashable {
        case weight(Int)
        case reps(Int)
        case rir(Int)
        case notes
    }

    var canSave: Bool {
        setLogs.contains { parsedWeight(from: $0.weightText) != nil }
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
                        setEntryCards
                        notesAndDateCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, isKeyboardActive ? 24 : 120)
                }
            }
            .navigationTitle("Edit Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveEntry() }
                        .bold()
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Save") { saveEntry() }
                        .bold()
                        .disabled(!canSave)
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardActive {
                    bottomSaveBar
                }
            }
            .animation(.easeOut(duration: 0.2), value: isKeyboardActive)
            .onAppear { initializeSets() }
        }
    }

    // MARK: - Exercise Header

    var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Exercise")

            Text(exercise.exerciseName)
                .font(.title3.bold())

            HStack(spacing: 8) {
                metricChip(icon: "square.stack.3d.up", text: setsLabel(exercise.sets))
                metricChip(icon: "arrow.left.arrow.right", text: "\(exercise.reps) target")
                if !exercise.muscleTarget.isEmpty {
                    metricChip(icon: "target", text: exercise.muscleTarget)
                }
            }
        }
        .padding(16)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Targets

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
                    applyWeightToAll(summary.weightLbs, reps: summary.repsCompleted)
                }

                Divider()
                    .padding(.vertical, 14)

                summarySegment(
                    title: "Best",
                    weight: resolvedBestWeight(from: summary),
                    reps: resolvedBestReps(from: summary),
                    date: resolvedBestDate(from: summary),
                    accent: TFColor.success
                ) {
                    applyWeightToAll(resolvedBestWeight(from: summary), reps: resolvedBestReps(from: summary))
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
        }
        .padding(16)
        .background(TFColor.surface)
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
                    .font(TFTypography.sectionTitle)
                    .foregroundStyle(accent)
                    .tracking(1.5)

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

                Text("Tap to fill all sets")
                    .font(.caption2.bold())
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Set Entry Cards

    var setEntryCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Sets")
                Spacer()
                Button {
                    addSet()
                } label: {
                    Label("Add Set", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(setLogs.enumerated()), id: \.element.id) { index, draft in
                setRow(index: index, draft: draft)
            }

            if setLogs.count > 1 {
                HStack(spacing: 12) {
                    Button {
                        copyFirstSetToAll()
                    } label: {
                        Label("Copy Set 1 to all", systemImage: "doc.on.doc")
                            .font(.caption.bold())
                            .foregroundStyle(TFColor.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if setLogs.count > exercise.sets {
                        Button {
                            removeLastSet()
                        } label: {
                            Label("Remove last", systemImage: "minus.circle")
                                .font(.caption.bold())
                                .foregroundStyle(TFColor.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    func setRow(index: Int, draft: SetLogDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Set \(draft.setNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(TFColor.accent)
                    .frame(width: 44, alignment: .leading)

                HStack(spacing: 4) {
                    TextField("0", text: $setLogs[index].weightText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight(index))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .frame(minWidth: 50)
                    Text("lb")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))

                quickAdjustButton(index: index)

                Text("\u{00D7}")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)

                HStack(spacing: 4) {
                    TextField("0", text: $setLogs[index].repsText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .reps(index))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .frame(minWidth: 30)
                    Text("reps")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
            }

            HStack(spacing: 8) {
                Spacer()
                Text("Optional RIR")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                TextField("—", text: $setLogs[index].rirText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .rir(index))
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .padding(.vertical, 7)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
            }
        }
    }

    func quickAdjustButton(index: Int) -> some View {
        Menu {
            ForEach(quickAdjustments, id: \.self) { delta in
                Button {
                    nudgeSetWeight(at: index, by: delta)
                } label: {
                    Text(delta > 0 ? "+\(formatWeight(delta))" : "\(formatWeight(delta))")
                }
            }
        } label: {
            Image(systemName: "plusminus")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(8)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())
        }
    }

    // MARK: - Notes & Date

    var notesAndDateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Bottom Bar

    var bottomSaveBar: some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saveSummaryText)
                        .font(.headline)
                    Text("\(validSetCount) of \(setLogs.count) sets logged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    saveEntry()
                } label: {
                    Text("Save Sets")
                        .font(.headline.bold())
                        .frame(minWidth: 120)
                        .padding(.vertical, 14)
                        .background(canSave ? TFColor.accent : TFColor.accent.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
                }
                .pressable()
                .disabled(!canSave)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    var validSetCount: Int {
        setLogs.filter { parsedWeight(from: $0.weightText) != nil && parsedReps(from: $0.repsText) != nil }.count
    }

    var saveSummaryText: String {
        let valid = setLogs.compactMap { draft -> (Double, Int)? in
            guard let w = parsedWeight(from: draft.weightText),
                  let r = parsedReps(from: draft.repsText) else { return nil }
            return (w, r)
        }
        guard let top = valid.max(by: { $0.0 < $1.0 }) else { return "Enter weight to save" }
        return "\(formatWeight(top.0)) lb \u{00D7} \(top.1) top set"
    }

    // MARK: - Actions

    func initializeSets() {
        guard setLogs.isEmpty else { return }

        // Resume today's in-progress session if it exists, so the sheet shows the sets
        // already logged (e.g. via the inline logger) instead of overwriting them on save.
        if !todaysSetLogs.isEmpty {
            setLogs = todaysSetLogs
                .sorted { $0.setNumber < $1.setNumber }
                .map {
                    SetLogDraft(
                        setNumber: $0.setNumber,
                        weightText: formatWeight($0.weightLbs),
                        repsText: "\($0.repsCompleted)",
                        rirText: $0.rir.map(formatRIR) ?? ""
                    )
                }
            return
        }

        let count = max(exercise.sets, 1)
        // Seed from the representative working set, not the heaviest logged set, so a
        // prior anomaly or warm-up ramp does not pre-fill an unintended load.
        let analysis = WorkingSetAnalysis.analyze(latestSetLogs)
        let prefillWeight = analysis.workingWeight ?? weightSummary?.weightLbs
        let prefillReps = analysis.topWorkingSet?.reps ?? weightSummary?.repsCompleted

        setLogs = (1...count).map { num in
            SetLogDraft(
                setNumber: num,
                weightText: prefillWeight.map { formatWeight($0) } ?? "",
                repsText: prefillReps.map { String($0) } ?? "",
                rirText: ""
            )
        }
    }

    func addSet() {
        let nextNum = (setLogs.last?.setNumber ?? 0) + 1
        let lastWeight = setLogs.last?.weightText ?? ""
        let lastReps = setLogs.last?.repsText ?? ""
        setLogs.append(SetLogDraft(setNumber: nextNum, weightText: lastWeight, repsText: lastReps, rirText: ""))
    }

    func removeLastSet() {
        guard setLogs.count > 1 else { return }
        setLogs.removeLast()
    }

    func copyFirstSetToAll() {
        guard let first = setLogs.first else { return }
        for i in setLogs.indices {
            setLogs[i].weightText = first.weightText
            setLogs[i].repsText = first.repsText
            setLogs[i].rirText = first.rirText
        }
    }

    func applyWeightToAll(_ weight: Double, reps: Int?) {
        for i in setLogs.indices {
            setLogs[i].weightText = formatWeight(weight)
            setLogs[i].repsText = reps.map { String($0) } ?? ""
        }
    }

    func nudgeSetWeight(at index: Int, by delta: Double) {
        let base = parsedWeight(from: setLogs[index].weightText) ?? weightSummary?.weightLbs ?? 0
        let updated = max(0, base + delta)
        guard updated > 0 else { return }
        setLogs[index].weightText = formatWeight(updated)
    }

    func saveEntry() {
        let validSets: [SetLogEntry] = setLogs.compactMap { draft in
            guard let w = parsedWeight(from: draft.weightText) else { return nil }
            let r = parsedReps(from: draft.repsText) ?? 0
            return SetLogEntry(
                setNumber: draft.setNumber,
                weightLbs: w,
                repsCompleted: r,
                rir: parsedRIR(from: draft.rirText)
            )
        }
        guard !validSets.isEmpty else { return }
        // Guard against a fast double-tap inserting duplicate logs before dismiss.
        guard !didSave else { return }
        didSave = true

        // Best/summary load comes from the qualified working set so a lone anomalous set
        // cannot become a false PR. Raw per-set data is still preserved in setLogs below.
        let top = WorkingSetAnalysis.summaryTop(from: validSets)
        let topWeight = top?.weightLbs ?? validSets[0].weightLbs
        let topReps = top?.reps
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Resume the same-day session if one already exists (e.g. started via the inline
        // logger) instead of inserting a duplicate log for the same exercise and day.
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let dayNumber = exercise.day?.dayNumber ?? 0
        let descriptor = FetchDescriptor<ExercisePerformanceLog>(
            predicate: #Predicate { $0.canonicalExerciseKey == key && $0.workoutDayNumber == dayNumber }
        )
        let sameDayLog = (try? modelContext.fetch(descriptor))?.first {
            Calendar.current.isDate($0.loggedAt, inSameDayAs: loggedAt)
        }

        if let existing = sameDayLog {
            existing.loggedAt = loggedAt
            existing.weightLbs = topWeight
            existing.repsCompleted = topReps
            existing.notes = trimmedNotes
            existing.muscleTarget = exercise.muscleTarget
            existing.setLogsJSON = ExercisePerformanceLog.encodeSetLogs(validSets)
        } else {
            let performanceLog = ExercisePerformanceLog(
                loggedAt: loggedAt,
                exerciseName: exercise.exerciseName,
                weightLbs: topWeight,
                repsCompleted: topReps,
                notes: trimmedNotes,
                muscleTarget: exercise.muscleTarget,
                workoutDayNumber: dayNumber,
                setLogs: validSets
            )
            modelContext.insert(performanceLog)
        }

        if let weightSummary {
            weightSummary.applyLog(
                loggedAt: loggedAt,
                exerciseName: exercise.exerciseName,
                weightLbs: topWeight,
                repsCompleted: topReps,
                notes: trimmedNotes
            )
        } else {
            let entry = ExerciseWeightEntry(
                loggedAt: loggedAt,
                exerciseName: exercise.exerciseName,
                weightLbs: topWeight,
                repsCompleted: topReps,
                notes: trimmedNotes
            )
            modelContext.insert(entry)
        }

        guard PersistenceReporter.save(modelContext, operation: "exercise set logging") else {
            modelContext.rollback()
            didSave = false
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        TFHaptics.success()
        dismiss()
    }

    // MARK: - Helpers

    func resolvedBestWeight(from summary: ExerciseWeightEntry) -> Double {
        summary.hasBestRecord ? summary.bestWeightLbs : summary.weightLbs
    }

    func resolvedBestDate(from summary: ExerciseWeightEntry) -> Date? {
        summary.bestLoggedAt ?? summary.loggedAt
    }

    func resolvedBestReps(from summary: ExerciseWeightEntry) -> Int? {
        summary.bestRepsCompleted ?? summary.repsCompleted
    }

    func parsedWeight(from text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    func parsedReps(from text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let reps = Int(cleaned), reps > 0 else { return nil }
        return reps
    }

    func parsedRIR(from text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), (0...6).contains(value) else { return nil }
        return value
    }

    func formatRIR(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    func sectionLabel(_ text: String) -> some View {
        TFSectionLabel(text: text)
    }

    func metricChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(TFColor.accent.opacity(0.12))
        .foregroundStyle(TFColor.accent)
        .clipShape(Capsule())
    }

}
