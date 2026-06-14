import SwiftUI
import SwiftData
import Charts

struct MeasurementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query(sort: \MeasurementEntry.date, order: .reverse) private var measurements: [MeasurementEntry]

    @State private var showAddSheet = false
    @State private var selectedChart: ChartMetric = .weight
    @State private var showDeleteConfirm = false
    @State private var weightToDelete: WeightEntry?
    @State private var measurementToDelete: MeasurementEntry?
    @State private var weightToEdit: WeightEntry?

    enum ChartMetric: String, CaseIterable {
        case weight = "Weight"
        case waist = "Waist"
        case chest = "Chest"
        case arms = "Arms"
        case thighs = "Thighs"
    }

    var latestWeight: WeightEntry? { weightEntries.first }
    var previousWeight: WeightEntry? { weightEntries.dropFirst().first }
    var latestMeasurement: MeasurementEntry? { measurements.first }
    var previousMeasurement: MeasurementEntry? { measurements.dropFirst().first }

    var weightDelta: Double? {
        guard let current = latestWeight?.weightLbs,
              let previous = previousWeight?.weightLbs else { return nil }
        return current - previous
    }

    var measurementTrend: MeasurementTrendSnapshot? {
        let entries = measurements.map { m in
            MeasurementTrendInput(
                date: m.date,
                waistIn: m.waistIn,
                neckIn: m.neckIn,
                hipsIn: m.hipsIn,
                chestIn: m.chestIn,
                rightArmIn: m.rightArmIn,
                leftArmIn: m.leftArmIn,
                rightThighIn: m.rightThighIn,
                leftThighIn: m.leftThighIn,
                isStandard: m.isStandardMeasurement,
                bodyweightLbs: nil
            )
        }
        guard !entries.isEmpty else { return nil }

        let weightPoints = weightEntries.map {
            AnalysisLoggedWeightPoint(date: $0.date, weightLbs: $0.weightLbs)
        }

        return MeasurementTrendSnapshotBuilder.build(
            entries: entries,
            weightPoints: weightPoints
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let trend = measurementTrend, trend.sessionsCount >= 2 {
                        trendInterpretationCard(trend: trend)
                    }
                    summaryCards
                    chartSection
                    historySection
                }
                .padding()
            }
            .navigationTitle("Body Metrics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddMeasurementSheet()
            }
            .sheet(item: $weightToEdit) { entry in
                EditWeightSheet(entry: entry)
            }
            .alert("Delete Entry?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    var deletedSomething = false
                    if let w = weightToDelete {
                        modelContext.delete(w)
                        weightToDelete = nil
                        deletedSomething = true
                    }
                    if let m = measurementToDelete {
                        modelContext.delete(m)
                        measurementToDelete = nil
                        deletedSomething = true
                    }
                    if deletedSomething {
                        guard PersistenceReporter.save(modelContext, operation: "measurement history deletion") else {
                            modelContext.rollback()
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            return
                        }
                        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                Button("Cancel", role: .cancel) {
                    weightToDelete = nil
                    measurementToDelete = nil
                }
            } message: {
                Text("This will permanently remove this entry.")
            }
        }
    }

    // MARK: - Trend Interpretation Card

    func trendInterpretationCard(trend: MeasurementTrendSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Trend Analysis", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Spacer()
                confidenceBadge(trend.progressConfidence)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let waist = trend.latestWaistIn {
                    trendRow(
                        label: "Waist",
                        value: String(format: "%.1f in", waist),
                        change: trend.waistChangeIn,
                        unit: "in",
                        invertDelta: true
                    )
                }

                if let weight = trend.latestWeightLbs {
                    trendRow(
                        label: "Weight",
                        value: String(format: "%.1f lb", weight),
                        change: trend.weightChangeLbs,
                        unit: "lb",
                        invertDelta: true
                    )
                }

                if let chest = trend.chestChangeIn {
                    trendRow(label: "Chest", value: nil, change: chest, unit: "in", invertDelta: false)
                }

                if let arm = trend.armChangeIn {
                    trendRow(label: "Arms", value: nil, change: arm, unit: "in", invertDelta: false)
                }
            }

            Divider()

            HStack(spacing: 8) {
                interpretationBadge(trend.interpretation)
                Spacer()
                Text("\(trend.sessionsCount) session(s) over \(trend.lookbackDays) days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let ratio = trend.waistToWeightRatio {
                Text(ratio)
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .padding(.top, 2)
            }

            Text(trend.confidenceReason)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func trendRow(label: String, value: String?, change: Double?, unit: String, invertDelta: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption.bold())
                .frame(width: 50, alignment: .leading)
            if let value {
                Text(value)
                    .font(.caption)
            }
            Spacer()
            if let change, abs(change) > 0.05 {
                let sign = change > 0 ? "+" : ""
                let color: Color = {
                    if invertDelta {
                        return change < 0 ? .green : .red
                    }
                    return change > 0 ? .green : .red
                }()
                Text("\(sign)\(String(format: "%.1f", change)) \(unit)")
                    .font(.caption.bold())
                    .foregroundStyle(color)
            } else {
                Text("No change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func confidenceBadge(_ confidence: ProgressConfidence) -> some View {
        let color: Color = {
            switch confidence {
            case .high: return .green
            case .moderate: return .orange
            case .low: return .yellow
            case .insufficient: return .secondary
            }
        }()
        return Text(confidence.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    func interpretationBadge(_ interpretation: MeasurementInterpretation) -> some View {
        let color: Color = {
            switch interpretation {
            case .likelyFatLoss: return .green
            case .likelyRecomposition: return .blue
            case .likelyMassGain: return .orange
            case .possibleNoise: return .yellow
            case .insufficientData: return .secondary
            case .stableNoChange: return .secondary
            }
        }()
        return Text(interpretation.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Summary Cards

    var summaryCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricCard(
                    title: "Weight",
                    value: latestWeight.map { String(format: "%.1f", $0.weightLbs) } ?? "--",
                    unit: "lbs",
                    delta: weightDelta,
                    deltaUnit: "lbs",
                    icon: "scalemass.fill",
                    color: .orange
                )

                MetricCard(
                    title: "Goal",
                    value: String(format: "%.0f", Config.bodyWeightGoalLbs),
                    unit: "lbs",
                    delta: latestWeight.map { $0.weightLbs - Config.bodyWeightGoalLbs },
                    deltaUnit: "to go",
                    icon: "target",
                    color: .blue,
                    invertDelta: true
                )
            }

            if let m = latestMeasurement, let prev = previousMeasurement {
                HStack(spacing: 12) {
                    if let waist = m.waistIn {
                        MetricCard(
                            title: "Waist",
                            value: String(format: "%.1f", waist),
                            unit: "in",
                            delta: prev.waistIn.map { waist - $0 },
                            deltaUnit: "in",
                            icon: "ruler",
                            color: .purple,
                            invertDelta: true
                        )
                    }

                    if let chest = m.chestIn {
                        MetricCard(
                            title: "Chest",
                            value: String(format: "%.1f", chest),
                            unit: "in",
                            delta: prev.chestIn.map { chest - $0 },
                            deltaUnit: "in",
                            icon: "arrow.left.and.right",
                            color: .green
                        )
                    }
                }

                HStack(spacing: 12) {
                    if let arm = m.rightArmIn {
                        MetricCard(
                            title: "Arm",
                            value: String(format: "%.1f", arm),
                            unit: "in",
                            delta: prev.rightArmIn.map { arm - $0 },
                            deltaUnit: "in",
                            icon: "figure.strengthtraining.traditional",
                            color: .red
                        )
                    }

                    if let bf = m.bodyFatPct {
                        MetricCard(
                            title: "Body Fat",
                            value: String(format: "%.1f", bf),
                            unit: "%",
                            delta: prev.bodyFatPct.map { bf - $0 },
                            deltaUnit: "%",
                            icon: "percent",
                            color: .orange,
                            invertDelta: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - Chart Section

    var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChartMetric.allCases, id: \.self) { metric in
                        Button(metric.rawValue) {
                            selectedChart = metric
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selectedChart == metric ? Color.orange : Color(.secondarySystemBackground))
                        .foregroundStyle(selectedChart == metric ? .white : .primary)
                        .clipShape(Capsule())
                        .font(.subheadline.bold())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedChart.rawValue + " Over Time")
                    .font(.headline)

                chartView
                    .frame(height: 180)
                    .padding(.top, 4)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    var chartView: some View {
        switch selectedChart {
        case .weight:
            weightChart
        case .waist:
            measurementChart(keyPath: \.waistIn, label: "Waist (in)")
        case .chest:
            measurementChart(keyPath: \.chestIn, label: "Chest (in)")
        case .arms:
            measurementChart(keyPath: \.rightArmIn, label: "Arm (in)")
        case .thighs:
            measurementChart(keyPath: \.rightThighIn, label: "Thigh (in)")
        }
    }

    var weightChart: some View {
        let sorted = weightEntries.sorted { $0.date < $1.date }
        let minWeight = (sorted.map(\.weightLbs).min() ?? 0) - 2
        return Chart(sorted) { entry in
            LineMark(
                x: .value("Date", entry.date),
                y: .value("Weight", entry.weightLbs)
            )
            .foregroundStyle(Color.orange)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Date", entry.date),
                yStart: .value("Baseline", minWeight),
                yEnd: .value("Weight", entry.weightLbs)
            )
            .foregroundStyle(Color.orange.opacity(0.1))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", entry.date),
                y: .value("Weight", entry.weightLbs)
            )
            .foregroundStyle(Color.orange)
            .symbolSize(30)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.caption2)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    func measurementChart(keyPath: KeyPath<MeasurementEntry, Double?>, label: String) -> some View {
        let sorted = measurements
            .sorted { $0.date < $1.date }
            .compactMap { entry -> (Date, Double)? in
                guard let val = entry[keyPath: keyPath] else { return nil }
                return (entry.date, val)
            }

        return Chart(sorted, id: \.0) { (date, value) in
            LineMark(
                x: .value("Date", date),
                y: .value(label, value)
            )
            .foregroundStyle(Color.purple)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", date),
                y: .value(label, value)
            )
            .foregroundStyle(Color.purple)
            .symbolSize(30)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.caption2)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    // MARK: - History Section

    var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)

            if weightEntries.isEmpty && measurements.isEmpty {
                Text("No entries yet. Tap + to log your first measurement.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(mergedDates().prefix(10), id: \.self) { date in
                    let weight = weightEntries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })
                    let measurement = measurements.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })

                    HistoryRowView(
                        date: date,
                        weight: weight,
                        measurement: measurement,
                        onEditWeight: { entry in
                            weightToEdit = entry
                        }
                    )
                    .contextMenu {
                        if let w = weight {
                            Button {
                                weightToEdit = w
                            } label: {
                                Label("Edit Weight", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                weightToDelete = w
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Weight", systemImage: "scalemass")
                            }
                        }
                        if let m = measurement {
                            Button(role: .destructive) {
                                measurementToDelete = m
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Measurements", systemImage: "ruler")
                            }
                        }
                    }
                }
            }
        }
    }

    func mergedDates() -> [Date] {
        var dates = Set<String>()
        var result: [Date] = []
        let formatter = DateFormatter()
        formatter.dateStyle = .short

        for entry in weightEntries {
            let key = formatter.string(from: entry.date)
            if dates.insert(key).inserted { result.append(entry.date) }
        }
        for entry in measurements {
            let key = formatter.string(from: entry.date)
            if dates.insert(key).inserted { result.append(entry.date) }
        }
        return result.sorted { $0 > $1 }
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let delta: Double?
    let deltaUnit: String
    let icon: String
    let color: Color
    var invertDelta: Bool = false

    var deltaColor: Color {
        guard let d = delta else { return .secondary }
        let isPositive = d > 0
        return (isPositive == !invertDelta) ? .green : .red
    }

    var deltaText: String {
        guard let d = delta, d != 0 else { return "No change" }
        let sign = d > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", d)) \(deltaUnit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                if let d = delta, d != 0 {
                    Text(deltaText)
                        .font(.caption.bold())
                        .foregroundStyle(deltaColor)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - History Row

struct HistoryRowView: View {
    let date: Date
    let weight: WeightEntry?
    let measurement: MeasurementEntry?
    var onEditWeight: ((WeightEntry) -> Void)?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        HStack(spacing: 12) {
                            if let w = weight {
                                Label(String(format: "%.1f lbs", w.weightLbs), systemImage: "scalemass")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if let m = measurement {
                                HStack(spacing: 4) {
                                    Label("Measurements", systemImage: "ruler")
                                        .font(.caption)
                                        .foregroundStyle(.purple)
                                    if !m.isStandardMeasurement {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.yellow)
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if expanded {
                Divider()

                if let w = weight {
                    HStack {
                        Label(String(format: "%.1f lbs", w.weightLbs), systemImage: "scalemass.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                        if !w.notes.isEmpty {
                            Text(w.notes)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let onEditWeight {
                            Button {
                                onEditWeight(w)
                            } label: {
                                Label("Edit", systemImage: "pencil.circle.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let m = measurement {
                    MeasurementDetailGrid(measurement: m)
                    if let timing = m.measurementTiming {
                        Text("Timing: \(timingDisplayName(timing))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func timingDisplayName(_ timing: String) -> String {
        switch timing {
        case "morning_fasted": return "Morning (fasted)"
        case "morning_postmeal": return "Morning (post-meal)"
        case "post_training": return "Post-Training"
        case "post_shift": return "Post-Shift"
        case "evening": return "Evening"
        default: return timing.capitalized
        }
    }
}

struct EditWeightSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var allWeightEntries: [WeightEntry]
    @Bindable var entry: WeightEntry

    @State private var weightText: String
    @State private var notes: String
    @State private var selectedDate: Date
    @State private var showConflictAlert = false

    init(entry: WeightEntry) {
        self.entry = entry
        _weightText = State(initialValue: String(format: "%.1f", entry.weightLbs))
        _notes = State(initialValue: entry.notes)
        _selectedDate = State(initialValue: entry.date)
    }

    var canSave: Bool {
        guard let weight = Double(weightText) else { return false }
        return (50...999).contains(weight)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                Section("Weight") {
                    HStack {
                        TextField("e.g. 192.4", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("lbs")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Edit Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .keyboardDismissToolbar()
        }
        .alert("Date Conflict", isPresented: $showConflictAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A weight entry already exists for that date. Change the date or edit the other entry instead.")
        }
    }

    func save() {
        guard let weight = Double(weightText), (50...999).contains(weight) else { return }
        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        if !Calendar.current.isDate(entry.date, inSameDayAs: targetDate),
           allWeightEntries.contains(where: { $0.id != entry.id && Calendar.current.isDate($0.date, inSameDayAs: targetDate) }) {
            showConflictAlert = true
            return
        }
        entry.weightLbs = weight
        entry.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.date = targetDate
        guard PersistenceReporter.saveWithBackup(modelContext, operation: "edit weight entry") else { return }
        dismiss()
    }
}

struct MeasurementDetailGrid: View {
    let measurement: MeasurementEntry

    var fields: [(String, Double?)] {
        [
            ("Chest", measurement.chestIn),
            ("Waist", measurement.waistIn),
            ("Hips", measurement.hipsIn),
            ("Neck", measurement.neckIn),
            ("R Arm", measurement.rightArmIn),
            ("L Arm", measurement.leftArmIn),
            ("R Thigh", measurement.rightThighIn),
            ("L Thigh", measurement.leftThighIn),
            ("R Calf", measurement.rightCalfIn),
            ("L Calf", measurement.leftCalfIn),
            ("Body Fat", measurement.bodyFatPct)
        ]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(fields.filter { $0.1 != nil }, id: \.0) { field in
                VStack(spacing: 2) {
                    if let value = field.1 {
                        Text(String(format: "%.1f", value))
                            .font(.subheadline.bold())
                    }
                    Text(field.0)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
