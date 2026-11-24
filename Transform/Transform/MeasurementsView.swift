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

    /// Entries the number cards and charts use. A measurement marked non-standard (taken at an
    /// unusual time) is kept in the history list but left out here, as the entry form promises
    /// (council review 2026-11-23: the cards and charts used to include them).
    var standardMeasurements: [MeasurementEntry] { measurements.filter(\.isStandardMeasurement) }
    var latestMeasurement: MeasurementEntry? { standardMeasurements.first }
    var previousMeasurement: MeasurementEntry? { standardMeasurements.dropFirst().first }

    /// The same 7-day trend the Dashboard shows (council review 2026-11-23). This card used to
    /// show the last weigh-in minus the one before it, which jumps with water weight and
    /// disagreed with the Dashboard.
    var weightTrend: WeightTrendSnapshot {
        WeightTrendBuilder.build(from: weightEntries.map {
            AnalysisLoggedWeightPoint(date: $0.date, weightLbs: $0.weightLbs)
        })
    }

    /// Average of whichever sides were measured.
    static func bothSides(_ right: Double?, _ left: Double?) -> Double? {
        switch (right, left) {
        case let (r?, l?): return (r + l) / 2
        case let (r?, nil): return r
        case let (nil, l?): return l
        case (nil, nil): return nil
        }
    }

    /// Change in the two-side average, using only the sides measured BOTH times, so adding a
    /// left-arm number for the first time does not show up as growth.
    static func bothSidesChange(now: (Double?, Double?), before: (Double?, Double?)) -> Double? {
        let deltas = [(now.0, before.0), (now.1, before.1)].compactMap { pair -> Double? in
            guard let a = pair.0, let b = pair.1 else { return nil }
            return a - b
        }
        return deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count)
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
                            .foregroundStyle(TFColor.accent)
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
                            TFHaptics.impact(.heavy)
                            return
                        }
                        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
                    }
                    TFHaptics.impact(.medium)
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
                    .foregroundStyle(TFColor.accent)
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
                    // Same span as the waist row above it (since 2026-11-23); shown without a
                    // good/bad colour because whether a gain is good depends on the phase.
                    trendRow(
                        label: "Weight",
                        value: String(format: "%.1f lb", weight),
                        change: trend.weightChangeLbs,
                        unit: "lb",
                        invertDelta: true,
                        neutral: true
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
                Text("\(trend.sessionsCount) session(s) over \(trend.lookbackDays) day(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let ratio = trend.waistToWeightRatio {
                Text(ratio)
                    .font(.caption)
                    .foregroundStyle(TFColor.measurement)
                    .padding(.top, 2)
            }

            // Past 30 days the verdict stays, labelled with its age (scientist consult 2026-11-24).
            if trend.isStale(), let date = trend.latestEntryDate {
                Text("As of \(date.formatted(.dateTime.month(.abbreviated).day())) — measure again to update")
                    .font(.caption2)
                    .foregroundStyle(TFColor.warning)
            }

            Text(trend.confidenceReason)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .dashCard()
    }

    func trendRow(label: String, value: String?, change: Double?, unit: String, invertDelta: Bool, neutral: Bool = false) -> some View {
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
                    if neutral { return .secondary }
                    if invertDelta {
                        return change < 0 ? TFColor.success : TFColor.danger
                    }
                    return change > 0 ? TFColor.success : TFColor.danger
                }()
                Text("\(sign)\(String(format: "%.1f", change)) \(unit)")
                    .font(.caption.bold())
                    .foregroundStyle(color)
            } else {
                // nil is "no data for this span", which is not the same claim as "no change".
                Text(change == nil ? "No data" : "No change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func confidenceBadge(_ confidence: ProgressConfidence) -> some View {
        let color: Color = {
            switch confidence {
            case .high: return TFColor.success
            case .moderate: return TFColor.accent
            case .low: return TFColor.warning
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
            case .likelyFatLoss: return TFColor.success
            case .likelyRecomposition: return TFColor.info
            case .likelyMassGain: return TFColor.accent
            case .possibleNoise, .waistUpWeightSteady, .waistUpWeightDown: return TFColor.warning
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
                    delta: weightTrend.weeklyChangeLbs,
                    deltaUnit: "lb/wk",
                    icon: "scalemass.fill",
                    color: .orange,
                    // Coloured by the current phase, like the Dashboard's badge: a gain is good
                    // while gaining and bad while cutting.
                    deltaJudgement: TrainingPhase.resolve(currentTrendWeightLbs: weightTrend.currentTrendWeightLbs).isWeeklyChangeGood
                )

                MetricCard(
                    title: "Goal",
                    value: String(format: "%.0f", Config.bodyWeightGoalLbs),
                    unit: "lbs",
                    delta: latestWeight.map { $0.weightLbs - Config.bodyWeightGoalLbs },
                    deltaUnit: "to go",
                    icon: "target",
                    color: TFColor.info,
                    invertDelta: true
                )
            }

            // Say so when the newest entry is not what the cards show, so a waist just measured
            // at an unusual time is not mistaken for a lost entry.
            if let newest = measurements.first, !newest.isStandardMeasurement {
                Text("Your latest entry is marked non-standard, so these cards show your last standard one.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            color: TFColor.success
                        )
                    }
                }

                HStack(spacing: 12) {
                    if let arm = Self.bothSides(m.rightArmIn, m.leftArmIn) {
                        MetricCard(
                            title: m.rightArmIn != nil && m.leftArmIn != nil ? "Arms (avg)" : "Arm",
                            value: String(format: "%.1f", arm),
                            unit: "in",
                            delta: Self.bothSidesChange(now: (m.rightArmIn, m.leftArmIn), before: (prev.rightArmIn, prev.leftArmIn)),
                            deltaUnit: "in",
                            icon: "figure.strengthtraining.traditional",
                            color: TFColor.danger
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
                        .background(selectedChart == metric ? TFColor.accent : TFColor.surface)
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
            .background(TFColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
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
            pairedMeasurementChart(right: \.rightArmIn, left: \.leftArmIn, label: "Arm (in)")
        case .thighs:
            pairedMeasurementChart(right: \.rightThighIn, left: \.leftThighIn, label: "Thigh (in)")
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
            .foregroundStyle(TFColor.accent)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Date", entry.date),
                yStart: .value("Baseline", minWeight),
                yEnd: .value("Weight", entry.weightLbs)
            )
            .foregroundStyle(TFColor.accent.opacity(0.1))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", entry.date),
                y: .value("Weight", entry.weightLbs)
            )
            .foregroundStyle(TFColor.accent)
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

    /// Right and left as two lines (the arm and thigh charts used to plot the right side only).
    func pairedMeasurementChart(right: KeyPath<MeasurementEntry, Double?>, left: KeyPath<MeasurementEntry, Double?>, label: String) -> some View {
        let sorted = standardMeasurements.sorted { $0.date < $1.date }
        var points: [SidePoint] = []
        for entry in sorted {
            if let value = entry[keyPath: right] { points.append(SidePoint(date: entry.date, side: "Right", value: value)) }
            if let value = entry[keyPath: left] { points.append(SidePoint(date: entry.date, side: "Left", value: value)) }
        }
        let summary: String = {
            let parts = ["Right", "Left"].compactMap { side -> String? in
                let values = points.filter { $0.side == side }.map(\.value)
                guard let first = values.first, let last = values.last else { return nil }
                return "\(side.lowercased()) latest \(String(format: "%.1f", last)), \(String(format: "%+.1f", last - first)) since the first entry"
            }
            return parts.isEmpty ? "Not enough data yet" : parts.joined(separator: "; ")
        }()

        return Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value(label, point.value)
            )
            .foregroundStyle(by: .value("Side", point.side))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", point.date),
                y: .value(label, point.value)
            )
            .foregroundStyle(by: .value("Side", point.side))
            .symbolSize(30)
        }
        .chartForegroundStyleScale(["Right": TFColor.measurement, "Left": TFColor.accent])
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.caption2)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) trend chart, right and left")
        .accessibilityValue(summary)
    }

    func measurementChart(keyPath: KeyPath<MeasurementEntry, Double?>, label: String) -> some View {
        let sorted = standardMeasurements
            .sorted { $0.date < $1.date }
            .compactMap { entry -> (Date, Double)? in
                guard let val = entry[keyPath: keyPath] else { return nil }
                return (entry.date, val)
            }

        let chartSummary: String = {
            guard let first = sorted.first?.1, let last = sorted.last?.1 else {
                return "Not enough data yet"
            }
            return String(format: "latest %.1f, %+.1f since the first entry", last, last - first)
        }()

        return Chart(sorted, id: \.0) { (date, value) in
            LineMark(
                x: .value("Date", date),
                y: .value(label, value)
            )
            .foregroundStyle(TFColor.measurement)
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Date", date),
                y: .value(label, value)
            )
            .foregroundStyle(TFColor.measurement)
            .symbolSize(30)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.caption2)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) trend chart")
        .accessibilityValue(chartSummary)
    }

    // MARK: - History Section

    var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)

            if weightEntries.isEmpty && measurements.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "ruler")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(TFColor.measurement.opacity(0.5))
                    Text("No entries yet")
                        .font(TFTypography.cardTitle)
                    Text("Tap + to log your first measurement.")
                        .font(TFTypography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .compactCard()
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

/// One side's value on one date, for the right/left measurement charts.
struct SidePoint: Identifiable {
    let date: Date
    let side: String
    let value: Double
    var id: String { "\(date.timeIntervalSinceReferenceDate)-\(side)" }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let delta: Double?
    let deltaUnit: String
    let icon: String
    let color: Color
    var invertDelta: Bool = false
    /// When set, decides the colour instead of `invertDelta`: true good, false bad, nil neutral.
    var deltaJudgement: ((Double) -> Bool?)? = nil

    var deltaColor: Color {
        guard let d = delta else { return .secondary }
        if let deltaJudgement {
            switch deltaJudgement(d) {
            case .some(true): return TFColor.success
            case .some(false): return TFColor.danger
            case .none: return .secondary
            }
        }
        let isPositive = d > 0
        return (isPositive == !invertDelta) ? TFColor.success : TFColor.danger
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
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
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
                                    .foregroundStyle(TFColor.accent)
                            }
                            if let m = measurement {
                                HStack(spacing: 4) {
                                    Label("Measurements", systemImage: "ruler")
                                        .font(.caption)
                                        .foregroundStyle(TFColor.measurement)
                                    if !m.isStandardMeasurement {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(TFColor.warning)
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
                            .foregroundStyle(TFColor.accent)
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
                                    .foregroundStyle(TFColor.accent)
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
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
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
                .background(TFColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
