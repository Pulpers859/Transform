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

    enum ChartMetric: String, CaseIterable {
        case weight = "Weight"
        case waist = "Waist"
        case chest = "Chest"
        case arms = "Arms"
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
                        measurement: measurement
                    )
                    .contextMenu {
                        if let w = weight {
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
                            if measurement != nil {
                                Label("Measurements", systemImage: "ruler")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if expanded, let m = measurement {
                Divider()
                MeasurementDetailGrid(measurement: m)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
