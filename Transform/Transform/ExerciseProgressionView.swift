import SwiftUI
import SwiftData
import Charts

struct ExerciseProgressionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExercisePerformanceLog.loggedAt, order: .forward) private var allLogs: [ExercisePerformanceLog]
    @Query(sort: \ExerciseWeightEntry.loggedAt, order: .reverse) private var allWeightEntries: [ExerciseWeightEntry]
    let exerciseName: String
    let canonicalKey: String
    @State private var logToEdit: ExercisePerformanceLog?

    init(exerciseName: String) {
        self.exerciseName = exerciseName
        self.canonicalKey = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
    }

    var matchingLogs: [ExercisePerformanceLog] {
        allLogs.filter { $0.canonicalExerciseKey == canonicalKey && $0.weightLbs > 0 }
    }

    var chartPoints: [ProgressionPoint] {
        matchingLogs.map { log in
            ProgressionPoint(
                date: log.loggedAt,
                weightLbs: log.weightLbs,
                repsCompleted: log.repsCompleted,
                setLogs: log.decodedSetLogs
            )
        }
    }

    var estimatedOneRepMax: [ProgressionPoint] {
        chartPoints.compactMap { point in
            guard let reps = point.repsCompleted, reps > 0, reps <= 15 else { return nil }
            let brzycki = point.weightLbs * 36.0 / (37.0 - Double(reps))
            let epley = point.weightLbs * (1.0 + Double(reps) / 30.0)
            let e1rm = (brzycki + epley) / 2.0
            return ProgressionPoint(date: point.date, weightLbs: e1rm, repsCompleted: nil, setLogs: [])
        }
    }

    var weightChartSummary: String {
        guard let first = chartPoints.first?.weightLbs, let last = chartPoints.last?.weightLbs else {
            return "Not enough data yet"
        }
        return String(format: "latest %.1f pounds, %+.1f since the first logged set", last, last - first)
    }

    var e1rmChartSummary: String {
        guard let first = estimatedOneRepMax.first?.weightLbs, let last = estimatedOneRepMax.last?.weightLbs else {
            return "Not enough data yet"
        }
        return String(format: "latest %.0f pounds estimated, %+.0f since the first estimate", last, last - first)
    }

    var weightDomain: ClosedRange<Double> {
        let allWeights = chartPoints.map(\.weightLbs) + estimatedOneRepMax.map(\.weightLbs)
        guard let lo = allWeights.min(), let hi = allWeights.max() else { return 0...100 }
        let padding = max((hi - lo) * 0.15, 10)
        return (lo - padding)...(hi + padding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if chartPoints.count >= 2 {
                    weightChart
                    if !estimatedOneRepMax.isEmpty {
                        e1rmChart
                    }
                } else if chartPoints.count == 1 {
                    singleEntryCard
                } else {
                    emptyState
                }
                if !chartPoints.isEmpty {
                    logHistory
                }
            }
            .padding()
        }
        .navigationTitle("Progression")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $logToEdit) { log in
            EditPerformanceLogSheet(log: log) {
                recalculateWeightSummary()
            }
        }
    }

    func recalculateWeightSummary() {
        let logs = allLogs.filter { $0.canonicalExerciseKey == canonicalKey && $0.weightLbs > 0 }
        guard let latestLog = logs.max(by: { $0.loggedAt < $1.loggedAt }) else {
            if let entry = allWeightEntries.first(where: { $0.canonicalExerciseKey == canonicalKey }) {
                modelContext.delete(entry)
            }
            PersistenceReporter.save(modelContext, operation: "remove orphaned weight summary")
            return
        }

        let topWeight = ExercisePerformanceLog.topSetWeight(from: latestLog.decodedSetLogs) ?? latestLog.weightLbs
        let topReps = ExercisePerformanceLog.topSetReps(from: latestLog.decodedSetLogs) ?? latestLog.repsCompleted

        var bestWeight = 0.0
        var bestLogDate: Date?
        var bestReps: Int?
        var bestNotes = ""
        for log in logs {
            let w = ExercisePerformanceLog.topSetWeight(from: log.decodedSetLogs) ?? log.weightLbs
            if w > bestWeight + 0.001 || (abs(w - bestWeight) <= 0.001 && log.loggedAt > (bestLogDate ?? .distantPast)) {
                bestWeight = w
                bestLogDate = log.loggedAt
                bestReps = ExercisePerformanceLog.topSetReps(from: log.decodedSetLogs) ?? log.repsCompleted
                bestNotes = log.notes
            }
        }

        if let entry = allWeightEntries.first(where: { $0.canonicalExerciseKey == canonicalKey }) {
            entry.loggedAt = latestLog.loggedAt
            entry.weightLbs = topWeight
            entry.repsCompleted = topReps
            entry.notes = latestLog.notes
            entry.bestWeightLbs = bestWeight
            entry.bestLoggedAt = bestLogDate
            entry.bestRepsCompleted = bestReps
            entry.bestNotes = bestNotes
        } else {
            let entry = ExerciseWeightEntry(
                loggedAt: latestLog.loggedAt,
                exerciseName: latestLog.exerciseName,
                weightLbs: topWeight,
                repsCompleted: topReps,
                notes: latestLog.notes
            )
            entry.bestWeightLbs = bestWeight
            entry.bestLoggedAt = bestLogDate
            entry.bestRepsCompleted = bestReps
            entry.bestNotes = bestNotes
            modelContext.insert(entry)
        }

        PersistenceReporter.save(modelContext, operation: "recalculate weight summary after edit")
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exerciseName)
                .font(.title2.bold())
            Text("\(chartPoints.count) session\(chartPoints.count == 1 ? "" : "s") logged")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let first = chartPoints.first, let last = chartPoints.last, chartPoints.count >= 2 {
                let delta = last.weightLbs - first.weightLbs
                let days = max(Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1, 1)
                HStack(spacing: 12) {
                    progressBadge(
                        label: "Top set",
                        value: String(format: "%+.1f lb", delta),
                        color: delta >= 0 ? TFColor.success : TFColor.danger
                    )
                    progressBadge(
                        label: "Over",
                        value: "\(days) days",
                        color: .secondary
                    )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
    }

    func progressBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var weightChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            TFSectionLabel(text: "Top Set Weight")

            Chart(chartPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weightLbs)
                )
                .foregroundStyle(TFColor.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weightLbs)
                )
                .foregroundStyle(TFColor.accent)
                .symbolSize(30)
            }
            .chartYScale(domain: weightDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .frame(height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Top set weight trend chart")
            .accessibilityValue(weightChartSummary)
        }
        .dashCard()
    }

    var e1rmChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ESTIMATED 1RM")
                    .font(TFTypography.sectionTitle)
                    .foregroundStyle(TFColor.measurement)
                    .tracking(1.5)
                Spacer()
                Text("Epley formula")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Chart(estimatedOneRepMax) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("e1RM", point.weightLbs)
                )
                .foregroundStyle(TFColor.measurement.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("e1RM", point.weightLbs)
                )
                .foregroundStyle(TFColor.measurement)
                .symbolSize(20)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Estimated one-rep max trend chart")
            .accessibilityValue(e1rmChartSummary)
        }
        .dashCard()
    }

    var singleEntryCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundStyle(.orange.opacity(0.4))
            Text("Log at least 2 sessions to see progression charts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dumbbell")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(TFColor.accent.opacity(0.4))
                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.3))
            Text("No weight logs yet")
                .font(TFTypography.cardTitle)
            Text("Log weights during your workout to track progression over time.")
                .font(TFTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .dashCard()
    }

    var logHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TFSectionLabel(text: "Session History")
                Spacer()
                Text("Tap to edit")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(chartPoints.reversed()) { point in
                Button {
                    if let log = matchingLogs.first(where: { $0.loggedAt == point.date }) {
                        logToEdit = log
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.bold())
                            Spacer()
                            Text("\(formatWeight(point.weightLbs)) lb")
                                .font(.caption.bold())
                                .foregroundStyle(TFColor.accent)
                            if let reps = point.repsCompleted {
                                Text("\u{00D7} \(reps)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if !point.setLogs.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(point.setLogs) { set in
                                    Text("\(formatWeight(set.weightLbs))\u{00D7}\(set.repsCompleted)")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)

                if point.id != chartPoints.first?.id {
                    Divider()
                }
            }
        }
        .dashCard()
    }

    func formatWeight(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}

struct ProgressionPoint: Identifiable {
    let date: Date
    let weightLbs: Double
    let repsCompleted: Int?
    let setLogs: [SetLogEntry]

    var id: Date { date }
}

// MARK: - Edit Performance Log Sheet

struct EditPerformanceLogSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let log: ExercisePerformanceLog
    let onSave: () -> Void

    @State private var editableSets: [EditableSet] = []
    @State private var notes: String = ""
    @State private var showDeleteConfirmation = false

    struct EditableSet: Identifiable {
        let id = UUID()
        var setNumber: Int
        var weightText: String
        var repsText: String
    }

    var canSave: Bool {
        editableSets.contains { Double($0.weightText) != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.exerciseName)
                            .font(.title3.bold())
                        Text(log.loggedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TFColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))

                    VStack(alignment: .leading, spacing: 12) {
                        TFSectionLabel(text: "Sets")

                        ForEach(Array(editableSets.enumerated()), id: \.element.id) { index, _ in
                            HStack(spacing: 10) {
                                Text("Set \(editableSets[index].setNumber)")
                                    .font(.caption.bold())
                                    .foregroundStyle(TFColor.accent)
                                    .frame(width: 44, alignment: .leading)

                                HStack(spacing: 4) {
                                    TextField("0", text: $editableSets[index].weightText)
                                        .keyboardType(.decimalPad)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .frame(minWidth: 50)
                                    Text("lb")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))

                                Text("\u{00D7}")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)

                                HStack(spacing: 4) {
                                    TextField("0", text: $editableSets[index].repsText)
                                        .keyboardType(.numberPad)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .frame(minWidth: 30)
                                    Text("reps")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))

                                if editableSets.count > 1 {
                                    Button {
                                        editableSets.remove(at: index)
                                        renumberSets()
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(TFColor.danger)
                                            .padding(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(TFColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTES")
                            .font(TFTypography.sectionTitle)
                            .foregroundStyle(.secondary)
                            .tracking(1.5)

                        TextField("Optional notes", text: $notes, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
                    }
                    .padding()
                    .background(TFColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete This Entry", systemImage: "trash")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(TFColor.danger.opacity(0.1))
                            .foregroundStyle(TFColor.danger)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEdits() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .keyboardDismissToolbar()
            .confirmationDialog("Delete this log entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteLog() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove this session's data and recalculate your progression summary.")
            }
            .onAppear { loadFromLog() }
        }
    }

    func loadFromLog() {
        let sets = log.decodedSetLogs
        if sets.isEmpty {
            editableSets = [EditableSet(
                setNumber: 1,
                weightText: log.weightLbs > 0 ? formatWeight(log.weightLbs) : "",
                repsText: log.repsCompleted.map(String.init) ?? ""
            )]
        } else {
            editableSets = sets.map { set in
                EditableSet(
                    setNumber: set.setNumber,
                    weightText: formatWeight(set.weightLbs),
                    repsText: "\(set.repsCompleted)"
                )
            }
        }
        notes = log.notes
    }

    func saveEdits() {
        let validSets: [SetLogEntry] = editableSets.compactMap { draft in
            guard let w = Double(draft.weightText) else { return nil }
            let r = Int(draft.repsText) ?? 0
            return SetLogEntry(setNumber: draft.setNumber, weightLbs: w, repsCompleted: r)
        }
        guard !validSets.isEmpty else { return }

        let topWeight = ExercisePerformanceLog.topSetWeight(from: validSets) ?? validSets[0].weightLbs
        let topReps = ExercisePerformanceLog.topSetReps(from: validSets)

        log.weightLbs = topWeight
        log.repsCompleted = topReps
        log.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        log.setLogsJSON = ExercisePerformanceLog.encodeSetLogs(validSets)

        guard PersistenceReporter.save(modelContext, operation: "edit performance log") else {
            modelContext.rollback()
            return
        }
        onSave()
        dismiss()
    }

    func deleteLog() {
        modelContext.delete(log)
        guard PersistenceReporter.save(modelContext, operation: "delete performance log") else {
            modelContext.rollback()
            return
        }
        onSave()
        dismiss()
    }

    func renumberSets() {
        for i in editableSets.indices {
            editableSets[i].setNumber = i + 1
        }
    }

    func formatWeight(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}
