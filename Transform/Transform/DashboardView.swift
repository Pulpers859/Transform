import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query(sort: \NutritionEntry.date, order: .reverse) private var allNutrition: [NutritionEntry]
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var analysisSessions: [BodyAnalysisSession]

    @State private var animateRings = false
    @State private var backupDocument = BackupDocument()
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showBackupAlert = false
    @State private var backupMessage = ""
    @State private var showAddWeightSheet = false
    @State private var showSettings = false

    // MARK: - Computed Props

    var todayNutrition: [NutritionEntry] {
        allNutrition.filter { Calendar.current.isDateInToday($0.date) }
    }

    var todayCalories: Int { todayNutrition.reduce(0) { $0 + $1.calories } }
    var todayProtein: Double { todayNutrition.reduce(0) { $0 + $1.proteinG } }
    var todayCarbs: Double { todayNutrition.reduce(0) { $0 + $1.carbsG } }
    var todayFat: Double { todayNutrition.reduce(0) { $0 + $1.fatG } }
    var latestAnalysis: BodyAnalysisResult? { analysisSessions.first?.decodedResult }
    var activeMacroTargets: DailyMacroTargets { MacroTargetResolver.resolve(from: latestAnalysis) }

    var currentWeight: Double? { weightEntries.first?.weightLbs }
    var previousWeight: Double? { weightEntries.dropFirst().first?.weightLbs }
    var weightDelta: Double? {
        guard let c = currentWeight, let p = previousWeight else { return nil }
        return c - p
    }

    var weightProgress: Double {
        guard let current = currentWeight else { return 0 }
        let start = weightEntries.last?.weightLbs ?? current
        let goal = Config.bodyWeightGoalLbs
        guard start != goal else { return 1.0 }
        return max(0, min(1.0, (current - start) / (goal - start)))
    }

    var weightSparkline: [WeightEntry] {
        Array(weightEntries.prefix(14).reversed())
    }

    var weightTrendDomain: ClosedRange<Double> {
        let values = weightSparkline.map(\.weightLbs)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let span = maxValue - minValue
        let minimumVisibleSpan = 4.0
        let paddedSpan = max(span * 1.35, minimumVisibleSpan)
        let center = (maxValue + minValue) / 2
        return (center - paddedSpan / 2)...(center + paddedSpan / 2)
    }

    var calorieProgress: Double {
        min(Double(todayCalories) / Double(activeMacroTargets.calories), 1.0)
    }

    var proteinProgress: Double {
        min(todayProtein / activeMacroTargets.proteinG, 1.0)
    }

    var remainingCaloriesToday: Int {
        activeMacroTargets.calories - todayCalories
    }

    var weekCalorieData: [(Date, Double)] {
        last7DaysCalories()
    }

    var weekAverageCalories: Double {
        weekCalorieData.map { $0.1 }.reduce(0, +) / max(Double(weekCalorieData.count), 1)
    }

    var caloriesByDay: [Date: Double] {
        let calendar = Calendar.current
        return allNutrition.reduce(into: [Date: Double]()) { totals, entry in
            let day = calendar.startOfDay(for: entry.date)
            totals[day, default: 0] += Double(entry.calories)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroHeader
                            .padding(.bottom, 24)

                        VStack(spacing: 16) {
                            todayRingsCard
                            weightCard
                            weekCalorieChart
                            bottomPadding
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileExporter(
                isPresented: $showExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: backupFileName
            ) { result in
                switch result {
                case .success:
                    backupMessage = "Backup exported successfully."
                    showBackupAlert = true
                case .failure(let error):
                    backupMessage = "Export failed: \(error.localizedDescription)"
                    showBackupAlert = true
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let data = try Data(contentsOf: url)
                        try DataBackupManager.shared.importBackup(from: data, into: modelContext)
                        backupMessage = "Backup imported successfully."
                    } catch {
                        backupMessage = "Import failed: \(error.localizedDescription)"
                    }
                    showBackupAlert = true
                case .failure(let error):
                    backupMessage = "Import failed: \(error.localizedDescription)"
                    showBackupAlert = true
                }
            }
            .alert("Backup", isPresented: $showBackupAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupMessage)
            }
            .sheet(isPresented: $showAddWeightSheet) {
                AddWeightSheet()
            }
            .sheet(isPresented: $showSettings) {
                AppSettingsView()
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.9).delay(0.2)) {
                    animateRings = true
                }
            }
        }
    }

    // MARK: - Hero Header

    var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color.black.opacity(0.92)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(height: 220)

            Canvas { context, size in
                let spacing: CGFloat = 28
                var x: CGFloat = 0
                while x < size.width {
                    var y: CGFloat = 0
                    while y < size.height {
                        let rect = CGRect(x: x, y: y, width: 1, height: 1)
                        context.fill(Path(rect), with: .color(.white.opacity(0.04)))
                        y += spacing
                    }
                    x += spacing
                }
            }
            .frame(height: 220)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: 4, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(greetingText)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(2)

                        Text("Transform.")
                            .font(.system(size: 36, weight: .black, design: .default))
                            .foregroundStyle(.white)
                    }
                }

                HStack(alignment: .center) {
                    Menu {
                        Button {
                            do {
                                backupDocument = try DataBackupManager.shared.exportDocument(using: modelContext)
                                showExporter = true
                            } catch {
                                backupMessage = "Could not prepare backup: \(error.localizedDescription)"
                                showBackupAlert = true
                            }
                        } label: {
                            Label("Export Backup", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            showImporter = true
                        } label: {
                            Label("Import Backup", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Backup", systemImage: "externaldrive.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.08))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: 220)
    }

    var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Today's Rings Card

    var todayRingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Today's Targets")

            HStack(spacing: 20) {
                ZStack {
                    AnimatedRing(
                        progress: animateRings ? min(todayFat / activeMacroTargets.fatG, 1.0) : 0,
                        color: .yellow,
                        size: 130,
                        lineWidth: 10
                    )
                    AnimatedRing(
                        progress: animateRings ? min(todayCarbs / activeMacroTargets.carbsG, 1.0) : 0,
                        color: .blue,
                        size: 106,
                        lineWidth: 10
                    )
                    AnimatedRing(
                        progress: animateRings ? min(todayProtein / activeMacroTargets.proteinG, 1.0) : 0,
                        color: .red,
                        size: 82,
                        lineWidth: 10
                    )

                    VStack(spacing: 0) {
                        Text("\(todayCalories)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                        Text("kcal")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 10) {
                    ringLegendRow(color: .orange, label: "Calories", value: "\(todayCalories)", target: "\(activeMacroTargets.calories)", unit: "kcal")
                    Divider()
                    ringLegendRow(color: .red, label: "Protein", value: "\(Int(todayProtein))", target: "\(Int(activeMacroTargets.proteinG))", unit: "g")
                    ringLegendRow(color: .blue, label: "Carbs", value: "\(Int(todayCarbs))", target: "\(Int(activeMacroTargets.carbsG))", unit: "g")
                    ringLegendRow(color: .yellow, label: "Fat", value: "\(Int(todayFat))", target: "\(Int(activeMacroTargets.fatG))", unit: "g")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Image(systemName: remainingCaloriesToday >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(remainingCaloriesToday >= 0 ? Color.green : Color.red)
                    .font(.caption)
                Text(remainingCaloriesToday >= 0
                     ? "\(remainingCaloriesToday) calories remaining today"
                     : "\(abs(remainingCaloriesToday)) calories over target")
                    .font(.caption)
                    .foregroundStyle(remainingCaloriesToday >= 0 ? Color.secondary : Color.red)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func ringLegendRow(color: Color, label: String, value: String, target: String, unit: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
            Text("/ \(target)\(unit)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Weight Card

    var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Body Weight")
                Spacer()
                Button {
                    showAddWeightSheet = true
                } label: {
                    Label("Log / Edit", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                if let delta = weightDelta {
                    deltaBadge(delta, invertGood: true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currentWeight.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                Text("lbs")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Goal: \(String(format: "%.0f", Config.bodyWeightGoalLbs)) lbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(weightProgress * 100))% there")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                            .frame(height: 6)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * (animateRings ? weightProgress : 0), height: 6)
                            .animation(.easeOut(duration: 1.0).delay(0.3), value: animateRings)
                    }
                }
                .frame(height: 6)
            }

            if weightSparkline.count > 1 {
                Text("Recent trend")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Chart(weightSparkline) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightLbs)
                    )
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightLbs)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(.orange.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(.orange.opacity(0.35))
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(.orange.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(.orange.opacity(0.35))
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: weightTrendDomain)
                .frame(height: 120)
            } else {
                Text("Log at least two entries to see your trend graph.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Week Calorie Chart

    var weekCalorieChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("7-Day Calories")

            Chart(weekCalorieData, id: \.0) { (date, cals) in
                BarMark(
                    x: .value("Day", date, unit: .day),
                    y: .value("Calories", cals)
                )
                .foregroundStyle(
                    Calendar.current.isDateInToday(date)
                    ? Color.orange
                    : Color.orange.opacity(0.35)
                )
                .cornerRadius(4)

                RuleMark(y: .value("Target", activeMacroTargets.calories))
                    .foregroundStyle(Color.orange.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 140)

            HStack(spacing: 4) {
                Text("7-day avg:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(Int(weekAverageCalories)) kcal")
                    .font(.caption2.bold())
                    .foregroundStyle(weekAverageCalories > Double(activeMacroTargets.calories) ? Color.red : Color.green)
                Text("· Target: \(activeMacroTargets.calories) kcal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if activeMacroTargets.source == .analysis {
                Text("Targets source: latest AI body analysis")
                    .font(.caption2)
                    .foregroundStyle(Color.orange.opacity(0.4))
            } else {
                Text("Targets source: fallback settings")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func last7DaysCalories() -> [(Date, Double)] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset -> (Date, Double)? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let day = calendar.startOfDay(for: date)
            let total = caloriesByDay[day] ?? 0
            return (date, total)
        }.reversed()
    }

    var bottomPadding: some View {
        Color.clear.frame(height: 20)
    }

    // MARK: - Helpers

    var backupFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "Transform_Backup_\(formatter.string(from: Date()))"
    }

    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.orange)
            .tracking(1.5)
    }

    func deltaBadge(_ delta: Double, invertGood: Bool = false) -> some View {
        let isGood = invertGood ? delta < 0 : delta > 0
        let sign = delta > 0 ? "+" : ""
        return Text("\(sign)\(String(format: "%.1f", delta)) lbs")
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isGood ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
            .foregroundStyle(isGood ? Color.green : Color.red)
            .clipShape(Capsule())
    }
}

// MARK: - Animated Ring

struct AnimatedRing: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: progress)
        }
        .frame(width: size, height: size)
    }
}
