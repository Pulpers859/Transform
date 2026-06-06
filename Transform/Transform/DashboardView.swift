import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query(sort: \NutritionEntry.date, order: .reverse) private var allNutrition: [NutritionEntry]
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var analysisSessions: [BodyAnalysisSession]
    @Query(sort: \MeasurementEntry.date, order: .reverse) private var measurementEntries: [MeasurementEntry]
    @Query(sort: \SleepEntry.date, order: .reverse) private var sleepEntries: [SleepEntry]

    @State private var animateRings = false
    @State private var backupDocument = BackupDocument()
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showBackupAlert = false
    @State private var backupMessage = ""
    @State private var showAddWeightSheet = false
    @State private var showAddFoodSheet = false
    @State private var showSettings = false
    @State private var sleepEditorRequest: SleepEditorRequest?

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
        let minimumVisibleSpan = 6.0
        let paddedSpan = max(span * 1.6, minimumVisibleSpan)
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

    var sleepTrend: SleepTrendSnapshot? {
        SleepTrendBuilder.build(from: sleepEntries)
    }

    var sleepEntriesChangeToken: String {
        sleepEntries.map {
            "\($0.persistentModelID)-\($0.date.timeIntervalSince1970)-\($0.durationHours)-\($0.qualityRating)-\($0.shiftTypeRaw)-\($0.notes)"
        }
        .joined(separator: "|")
    }

    // MARK: - Adherence Metrics

    var last7DaysNutritionEntries: [NutritionEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allNutrition.filter { $0.date >= cutoff }
    }

    var loggedDaysCount: Int {
        let calendar = Calendar.current
        let days = Set(last7DaysNutritionEntries.map { calendar.startOfDay(for: $0.date) })
        return days.count
    }

    var proteinHitDays: Int {
        let calendar = Calendar.current
        let threshold = activeMacroTargets.proteinG * 0.90
        let grouped = Dictionary(grouping: last7DaysNutritionEntries) { calendar.startOfDay(for: $0.date) }
        return grouped.values.filter { entries in
            entries.reduce(0.0) { $0 + $1.proteinG } >= threshold
        }.count
    }

    // MARK: - Measurement Trend

    var dashboardMeasurementTrend: MeasurementTrendSnapshot? {
        let entries = measurementEntries.map { m in
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
        guard entries.count >= 2 else { return nil }
        let wPoints = weightEntries.map {
            AnalysisLoggedWeightPoint(date: $0.date, weightLbs: $0.weightLbs)
        }
        return MeasurementTrendSnapshotBuilder.build(entries: entries, weightPoints: wPoints)
    }

    // MARK: - Analysis Freshness

    var analysisDaysAgo: Int? {
        guard let date = analysisSessions.first?.date else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }

    // MARK: - Coaching Headline

    var proteinRate: Double {
        loggedDaysCount > 0 ? Double(proteinHitDays) / Double(loggedDaysCount) : 0
    }

    var proteinCaveat: String? {
        guard loggedDaysCount >= 3, proteinRate < 0.5 else { return nil }
        return "but protein is still the gap"
    }

    var coachingHeadline: (String, Color) {
        // Priority 1: Insufficient data
        if loggedDaysCount < 3 {
            return ("Log meals consistently — only \(loggedDaysCount)/7 days tracked this week", .orange)
        }

        // Priority 2: Risk flags
        if let trend = dashboardMeasurementTrend {
            if trend.interpretation == .likelyFatLoss,
               let rate = trend.weightChangeRatePerWeek, rate < -2.0 {
                return ("Fat loss is fast — consider slowing the deficit to protect performance", .orange)
            }
        }

        if let daysAgo = analysisDaysAgo, daysAgo > 56 {
            return ("AI targets are \(daysAgo) days old — consider re-analyzing before adjusting further", .orange)
        }

        // Priority 3: Major protein gap (standalone — before body trends)
        if proteinRate < 0.35 && loggedDaysCount >= 3 {
            return ("Protein is the priority — hitting target on only \(proteinHitDays)/\(loggedDaysCount) logged days", .orange)
        }

        // Priority 4: Body trends (with protein caveat when applicable)
        if let trend = dashboardMeasurementTrend {
            let caveat = proteinCaveat.map { " — \($0)" } ?? ""
            switch trend.interpretation {
            case .likelyRecomposition:
                return ("Waist trending down, weight stable\(caveat.isEmpty ? " — stay the course" : caveat)", caveat.isEmpty ? .green : .orange)
            case .likelyFatLoss:
                return ("Fat loss tracking well\(caveat.isEmpty ? " — waist and weight both down" : caveat)", caveat.isEmpty ? .green : .orange)
            case .possibleNoise:
                return ("Recent changes may be noise — keep logging for clarity", .secondary)
            case .likelyMassGain:
                if trend.waistToWeightRatio != nil && trend.waistChangeIn.map({ $0 <= 0.1 }) == true {
                    return ("Weight rising but waist controlled — check training performance before adjusting", .secondary)
                }
                return ("Weight and waist both rising — review targets if fat loss is the goal", .orange)
            default:
                break
            }
        }

        // Priority 5: Moderate protein gap (no body trend to attach to)
        if proteinRate < 0.5 && loggedDaysCount >= 3 {
            return ("Protein is the gap — hitting target on only \(proteinHitDays)/\(loggedDaysCount) logged days", .orange)
        }

        // Priority 6: Praise
        if proteinRate >= 0.7 && loggedDaysCount >= 5 {
            return ("Strong week — logging consistent, protein adherence solid", .green)
        }

        return ("Keep logging — consistency is what unlocks meaningful trends", .secondary)
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
                            coachingHeadlineCard
                            todayRingsCard
                            sleepRecoveryCard
                            weightAndRecompCard
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
            .sheet(isPresented: $showAddFoodSheet) {
                AddFoodSheet(selectedDate: .now, preselectedMeal: nextMealName)
            }
            .sheet(isPresented: $showSettings) {
                AppSettingsView()
            }
            .sheet(item: $sleepEditorRequest) { request in
                SleepEntryEditor(entry: request.entry)
            }
            .onAppear {
                SleepTrendStore.refresh(using: modelContext)
                withAnimation(.easeOut(duration: 0.9).delay(0.2)) {
                    animateRings = true
                }
            }
            .onChange(of: sleepEntriesChangeToken) { _, _ in
                SleepTrendStore.refresh(using: modelContext)
            }
        }
    }

    // MARK: - Next Meal Name

    var proteinRemainingG: Double {
        activeMacroTargets.proteinG - todayProtein
    }

    var nextMealName: String {
        let now = Date()

        if let lastMeal = todayNutrition.sorted(by: { $0.date < $1.date }).last {
            let hoursSinceLast = now.timeIntervalSince(lastMeal.date) / 3600
            if hoursSinceLast < 2 {
                return proteinRemainingG > 30 ? "Protein Snack" : "Snack"
            }
        }

        let loggedMeals = Set(todayNutrition.map { $0.mealName.lowercased() })
        if !loggedMeals.contains("breakfast") { return "Breakfast" }
        if !loggedMeals.contains("lunch") { return "Lunch" }
        if !loggedMeals.contains("dinner") { return "Dinner" }
        return proteinRemainingG > 30 ? "Protein Snack" : "Snack"
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

    // MARK: - Coaching Headline Card

    var coachingHeadlineCard: some View {
        let (message, color) = coachingHeadline
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 32)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Today's Rings Card

    var todayRingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionLabel("Today's Targets")
                Spacer()
                Button {
                    showAddFoodSheet = true
                } label: {
                    Label("Log Meal", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

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

            adherenceLine
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var adherenceLine: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Logged: \(loggedDaysCount)/7 days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                Text("Protein: \(proteinHitDays)/\(max(loggedDaysCount, 1)) days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
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

    // MARK: - Sleep & Recovery

    var sleepRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Sleep & Recovery")
                Spacer()
                Button {
                    sleepEditorRequest = SleepEditorRequest(entry: todaySleepEntry)
                } label: {
                    Label(todaySleepEntry == nil ? "Log Sleep" : "Edit Today", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }

            if let trend = sleepTrend {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(SleepFormatting.duration(trend.averageHours))
                        .font(.system(size: 38, weight: .black, design: .rounded))
                    Text("average")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Quality \(String(format: "%.1f", trend.averageQuality))/5")
                            .font(.caption.bold())
                        Text("\(trend.loggedDays)/7 days logged")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Chart(trend.entries) { entry in
                    BarMark(
                        x: .value("Day", entry.date, unit: .day),
                        y: .value("Hours", entry.durationHours)
                    )
                    .foregroundStyle(entry.durationHours < 6 ? Color.orange : Color.blue)
                    .cornerRadius(4)

                    RuleMark(y: .value("Reference", 7))
                        .foregroundStyle(Color.blue.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [4, 6, 8, 10]) {
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYScale(domain: 0...12)
                .frame(height: 110)

                HStack(spacing: 12) {
                    Label(
                        "\(trend.shortSleepDays) under 6h",
                        systemImage: trend.shortSleepDays > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(trend.shortSleepDays > 0 ? .orange : .green)

                    Label(
                        String(format: "%.1fh variability", trend.variabilityHours),
                        systemImage: "waveform.path.ecg"
                    )
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .font(.caption2)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "bed.double.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No sleep logged yet")
                            .font(.subheadline.bold())
                        Text("A 10-second daily log is enough to build useful recovery context.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            NavigationLink {
                SleepHistoryView()
            } label: {
                HStack {
                    Label("View and edit sleep history", systemImage: "clock.arrow.circlepath")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var todaySleepEntry: SleepEntry? {
        sleepEntries.first { Calendar.current.isDateInToday($0.date) }
    }

    // MARK: - Weight + Recomp Card

    var weightAndRecompCard: some View {
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
                    if let current = currentWeight {
                        let remaining = abs(current - Config.bodyWeightGoalLbs)
                        Text(String(format: "%.1f lb to goal", remaining))
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
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

            if let trend = dashboardMeasurementTrend, trend.latestWaistIn != nil {
                recompContextSection(trend: trend)
            } else if dashboardMeasurementTrend == nil || dashboardMeasurementTrend?.latestWaistIn == nil {
                Divider().padding(.vertical, 2)
                NavigationLink {
                    MeasurementsView()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "ruler")
                            .font(.caption2)
                            .foregroundStyle(.purple.opacity(0.6))
                        Text("Add waist measurement to unlock recomp context")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
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
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightLbs)
                    )
                    .foregroundStyle(Color.orange)
                    .symbolSize(12)

                    AreaMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightLbs)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange.opacity(0.1), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
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

    @ViewBuilder
    func recompContextSection(trend: MeasurementTrendSnapshot) -> some View {
        Divider()
            .padding(.vertical, 2)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ruler")
                    .font(.caption2)
                    .foregroundStyle(.purple)

                dashboardInterpretationBadge(trend.interpretation)

                if let waist = trend.latestWaistIn {
                    HStack(spacing: 2) {
                        Text("Waist \(String(format: "%.1f", waist))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let change = trend.waistChangeIn, abs(change) > 0.05 {
                            Text(String(format: "%+.1f", change))
                                .font(.caption2.bold())
                                .foregroundStyle(change < 0 ? .green : .red)
                        }
                    }
                }

                dashboardConfidenceBadge(trend.progressConfidence)

                Spacer()
            }

            if let signal = trend.waistToWeightRatio {
                Text(signal)
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
        }
    }

    func dashboardInterpretationBadge(_ interpretation: MeasurementInterpretation) -> some View {
        let color: Color = {
            switch interpretation {
            case .likelyFatLoss: return .green
            case .likelyRecomposition: return .blue
            case .likelyMassGain: return .orange
            case .possibleNoise: return .yellow
            case .insufficientData, .stableNoChange: return .secondary
            }
        }()
        return Text(interpretation.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    func dashboardConfidenceBadge(_ confidence: ProgressConfidence) -> some View {
        let color: Color = {
            switch confidence {
            case .high: return .green
            case .moderate: return .orange
            case .low: return .yellow
            case .insufficient: return .secondary
            }
        }()
        return Text(confidence.rawValue)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
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
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2)
                        }
                    }
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

            analysisFreshnessLine
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var analysisFreshnessLine: some View {
        HStack(spacing: 4) {
            if let daysAgo = analysisDaysAgo {
                let color: Color = daysAgo <= 30 ? .green : (daysAgo <= 45 ? .orange : .red)
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(color)
                Text("Last analysis: \(daysAgo) day(s) ago")
                    .font(.caption2)
                    .foregroundStyle(color)
                if daysAgo > 42 {
                    Text("· Consider re-analyzing")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("No body analysis yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if activeMacroTargets.source == .analysis {
                if let daysAgo = analysisDaysAgo {
                    let stale = daysAgo > 56
                    Text("AI targets · \(daysAgo)d")
                        .font(.caption2)
                        .foregroundStyle(stale ? .red.opacity(0.7) : .orange.opacity(0.6))
                } else {
                    Text("AI targets")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.6))
                }
            } else {
                Text("Config targets")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
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
