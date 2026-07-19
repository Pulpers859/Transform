import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DayClock.self) private var dayClock
    @Environment(WorkoutDeepLink.self) private var workoutDeepLink
    @Binding var selectedTab: AppTab

    // Weight history is deliberately unbounded: the trend line and goal-anchor
    // resolution both legitimately read deep history. The high-churn stores
    // (nutrition, sleep) are bounded at the query level instead — the dashboard
    // only ever renders short windows of them.
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query private var recentNutrition: [NutritionEntry]
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var analysisSessions: [BodyAnalysisSession]
    @Query(sort: \MeasurementEntry.date, order: .reverse) private var measurementEntries: [MeasurementEntry]
    @Query private var sleepEpisodes: [SleepEntry]
    @Query(sort: \SavedNutritionProtocol.updatedAt, order: .reverse) private var savedNutritionProtocols: [SavedNutritionProtocol]
    @Query(sort: \WorkoutProgram.createdDate, order: .reverse) private var programs: [WorkoutProgram]

    @State private var animateRings = false
    @State private var showAddWeightSheet = false
    @State private var showAddFoodSheet = false
    @State private var showSettings = false
    @State private var sleepEditorRequest: SleepEditorRequest?
    @State private var quickSleepLogPresented = false
    @State private var headlineExpanded = false
    @State private var lastBackupDate: Date?

    init(selectedTab: Binding<AppTab>) {
        _selectedTab = selectedTab
        // The dashboard renders at most ~8 days of nutrition (today's rings +
        // the 7-day chart) and the sleep trend builder's recent windows, so
        // fetching entire multi-year histories per render is pure waste.
        let nutritionCutoff = Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? .distantPast
        _recentNutrition = Query(
            filter: #Predicate<NutritionEntry> { $0.date >= nutritionCutoff },
            sort: [SortDescriptor(\NutritionEntry.date, order: .reverse)]
        )
        let sleepCutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? .distantPast
        _sleepEpisodes = Query(
            filter: #Predicate<SleepEntry> { $0.date >= sleepCutoff },
            sort: [SortDescriptor(\SleepEntry.date, order: .reverse)]
        )
    }

    // MARK: - Computed Props

    var todayNutrition: [NutritionEntry] {
        recentNutrition.filter { Calendar.current.isDate($0.date, inSameDayAs: dayClock.today) }
    }

    var todayCalories: Int { todayNutrition.reduce(0) { $0 + $1.calories } }
    var todayProtein: Double { todayNutrition.reduce(0) { $0 + $1.proteinG } }
    var todayCarbs: Double { todayNutrition.reduce(0) { $0 + $1.carbsG } }
    var todayFat: Double { todayNutrition.reduce(0) { $0 + $1.fatG } }
    var latestAnalysis: BodyAnalysisResult? { analysisSessions.first?.decodedResult }
    var activeMacroTargets: DailyMacroTargets {
        MacroTargetResolver.resolve(
            from: latestAnalysis,
            bodyweightLbs: weightTrend.currentTrendWeightLbs,
            adaptiveOverride: savedNutritionProtocols.first?.appliedMacroOverride
        )
    }

    var currentWeight: Double? { weightEntries.first?.weightLbs }

    var weightTrend: WeightTrendSnapshot {
        WeightTrendBuilder.build(
            from: weightEntries.map {
                AnalysisLoggedWeightPoint(date: $0.date, weightLbs: $0.weightLbs)
            }
        )
    }

    var displayedWeightPoints: [SmoothedWeightPoint] {
        Array(weightTrend.points.suffix(21))
    }

    var weightTrendDomain: ClosedRange<Double> {
        let values = displayedWeightPoints.flatMap { [$0.rawWeightLbs, $0.trendWeightLbs] }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let span = maxValue - minValue
        let minimumVisibleSpan = 6.0
        let paddedSpan = max(span * 1.6, minimumVisibleSpan)
        let center = (maxValue + minValue) / 2
        return (center - paddedSpan / 2)...(center + paddedSpan / 2)
    }

    // MARK: - Training Phase & Goal Progress

    var trainingPhase: TrainingPhase {
        TrainingPhase.resolve(currentTrendWeightLbs: weightTrend.currentTrendWeightLbs)
    }

    var weightGoalState: WeightGoalState {
        WeightGoalProgressResolver.resolve(
            trendPoints: weightTrend.points.map { (date: $0.date, trendWeightLbs: $0.trendWeightLbs) },
            goalLbs: Config.bodyWeightGoalLbs,
            anchorDate: AppSettingsStore.bodyWeightGoalSetAt
        )
    }

    var remainingCaloriesToday: Int {
        activeMacroTargets.calories - todayCalories
    }

    // MARK: - Week Calories

    struct DayCalorieDatum: Identifiable {
        let id: Date
        let date: Date
        let calories: Double
        let isLogged: Bool
    }

    var caloriesByDay: [Date: Double] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -8, to: dayClock.today) ?? dayClock.today
        return recentNutrition.lazy.filter { $0.date >= cutoff }.reduce(into: [Date: Double]()) { totals, entry in
            let day = calendar.startOfDay(for: entry.date)
            totals[day, default: 0] += Double(entry.calories)
        }
    }

    var weekCalorieData: [DayCalorieDatum] {
        let calendar = Calendar.current
        let byDay = caloriesByDay
        return (0..<7).compactMap { offset -> DayCalorieDatum? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: dayClock.today) else { return nil }
            let day = calendar.startOfDay(for: date)
            if let total = byDay[day] {
                return DayCalorieDatum(id: day, date: day, calories: total, isLogged: true)
            }
            return DayCalorieDatum(id: day, date: day, calories: 0, isLogged: false)
        }.reversed()
    }

    /// Average over days that were actually logged. Unlogged days must not
    /// drag the average down into a false "under target" green — a week with
    /// three logged days is an adherence problem, not a calorie deficit.
    var weekAverageCalories: Double? {
        let logged = weekCalorieData.filter(\.isLogged)
        guard !logged.isEmpty else { return nil }
        return logged.map(\.calories).reduce(0, +) / Double(logged.count)
    }

    var weekLoggedDayCount: Int {
        weekCalorieData.filter(\.isLogged).count
    }

    var sleepTrend: SleepTrendSnapshot? {
        SleepTrendBuilder.build(from: sleepEpisodes)
    }

    var sleepEntriesChangeToken: String {
        sleepEpisodes.map {
            "\($0.persistentModelID)-\($0.resolvedStartDate.timeIntervalSince1970)-\($0.resolvedEndDate.timeIntervalSince1970)-\($0.qualityRating)-\($0.shiftTypeRaw)-\($0.episodeTypeRaw)-\($0.notes)"
        }
        .joined(separator: "|")
    }

    // MARK: - Adherence Metrics

    var last7DaysNutritionEntries: [NutritionEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: dayClock.today) ?? dayClock.today
        return recentNutrition.filter { $0.date >= cutoff }
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

    var analysisFreshness: AnalysisFreshness? {
        analysisDaysAgo.map { AnalysisFreshness.resolve(daysAgo: $0) }
    }

    func freshnessColor(_ freshness: AnalysisFreshness) -> Color {
        switch freshness {
        case .fresh: return TFColor.success
        case .aging: return TFColor.accent
        case .stale: return TFColor.danger
        }
    }

    // MARK: - Training Card State

    var currentProgram: WorkoutProgram? { programs.first { !$0.isArchived } }

    var nextTrainingDay: WorkoutDay? {
        currentProgram?.latestWeekDays.first { !$0.isCompleted }
    }

    // MARK: - Coaching Headline

    enum CoachAction {
        case logMeal
        case logSleep
        case reanalyze
    }

    struct CoachingVerdict {
        let message: String
        let color: Color
        let action: CoachAction?
        let actionLabel: String?
    }

    var proteinRate: Double {
        loggedDaysCount > 0 ? Double(proteinHitDays) / Double(loggedDaysCount) : 0
    }

    var proteinCaveat: String? {
        guard loggedDaysCount >= 3, proteinRate < 0.5 else { return nil }
        return "but protein is still the gap"
    }

    var coachingVerdict: CoachingVerdict {
        // Priority 1: Insufficient data
        if loggedDaysCount < 3 {
            return CoachingVerdict(
                message: "Log meals consistently — only \(loggedDaysCount)/7 days tracked this week",
                color: TFColor.accent,
                action: .logMeal,
                actionLabel: "Log a meal"
            )
        }

        // Priority 2: Risk flags
        if let trend = dashboardMeasurementTrend {
            if trend.interpretation == .likelyFatLoss,
               let rate = trend.weightChangeRatePerWeek, rate < -2.0 {
                return CoachingVerdict(
                    message: "Fat loss is fast — consider slowing the deficit to protect performance",
                    color: TFColor.accent,
                    action: nil,
                    actionLabel: nil
                )
            }
        }

        if let daysAgo = analysisDaysAgo, AnalysisFreshness.resolve(daysAgo: daysAgo) == .stale {
            return CoachingVerdict(
                message: "AI targets are \(daysAgo) days old — consider re-analyzing before adjusting further",
                color: TFColor.accent,
                action: .reanalyze,
                actionLabel: "Open Analysis"
            )
        }

        // Priority 3: Acute recovery constraint
        if let sleepTrend, sleepTrend.acuteLoggedDays >= 2 {
            if sleepTrend.threeDayAverageHours < 5 {
                return CoachingVerdict(
                    message: "Acute sleep restriction — keep today's training submaximal and trim low-priority fatigue",
                    color: TFColor.accent,
                    action: .logSleep,
                    actionLabel: "Log sleep"
                )
            }
            if sleepTrend.hasRecentPostCallRecovery || sleepTrend.underFiveHours > 0 {
                return CoachingVerdict(
                    message: "Recovery is constrained — prioritize technique, hydration, and an achievable session today",
                    color: TFColor.accent,
                    action: .logSleep,
                    actionLabel: "Log sleep"
                )
            }
        }

        // Priority 4: Major protein gap (standalone — before body trends)
        if proteinRate < 0.35 && loggedDaysCount >= 3 {
            return CoachingVerdict(
                message: "Protein is the priority — hitting target on only \(proteinHitDays)/\(loggedDaysCount) logged days",
                color: TFColor.accent,
                action: .logMeal,
                actionLabel: "Log a meal"
            )
        }

        // Priority 5: Body trends (with protein caveat when applicable)
        if let trend = dashboardMeasurementTrend {
            let caveat = proteinCaveat.map { " — \($0)" } ?? ""
            switch trend.interpretation {
            case .likelyRecomposition:
                return CoachingVerdict(
                    message: "Waist trending down, weight stable\(caveat.isEmpty ? " — stay the course" : caveat)",
                    color: caveat.isEmpty ? TFColor.success : TFColor.accent,
                    action: caveat.isEmpty ? nil : .logMeal,
                    actionLabel: caveat.isEmpty ? nil : "Log a meal"
                )
            case .likelyFatLoss:
                return CoachingVerdict(
                    message: "Fat loss tracking well\(caveat.isEmpty ? " — waist and weight both down" : caveat)",
                    color: caveat.isEmpty ? TFColor.success : TFColor.accent,
                    action: caveat.isEmpty ? nil : .logMeal,
                    actionLabel: caveat.isEmpty ? nil : "Log a meal"
                )
            case .possibleNoise:
                return CoachingVerdict(
                    message: "Recent changes may be noise — keep logging for clarity",
                    color: .secondary,
                    action: nil,
                    actionLabel: nil
                )
            case .likelyMassGain:
                if trend.waistToWeightRatio != nil && trend.waistChangeIn.map({ $0 <= 0.1 }) == true {
                    return CoachingVerdict(
                        message: "Weight rising but waist controlled — check training performance before adjusting",
                        color: .secondary,
                        action: nil,
                        actionLabel: nil
                    )
                }
                return CoachingVerdict(
                    message: "Weight and waist both rising — review targets if fat loss is the goal",
                    color: TFColor.accent,
                    action: nil,
                    actionLabel: nil
                )
            default:
                break
            }
        }

        // Priority 6: Moderate protein gap (no body trend to attach to)
        if proteinRate < 0.5 && loggedDaysCount >= 3 {
            return CoachingVerdict(
                message: "Protein is the gap — hitting target on only \(proteinHitDays)/\(loggedDaysCount) logged days",
                color: TFColor.accent,
                action: .logMeal,
                actionLabel: "Log a meal"
            )
        }

        // Priority 7: Praise
        if proteinRate >= 0.7 && loggedDaysCount >= 5 {
            return CoachingVerdict(
                message: "Strong week — logging consistent, protein adherence solid",
                color: TFColor.success,
                action: nil,
                actionLabel: nil
            )
        }

        return CoachingVerdict(
            message: "Keep logging — consistency is what unlocks meaningful trends",
            color: .secondary,
            action: nil,
            actionLabel: nil
        )
    }

    /// The inputs the verdict was computed from, surfaced on expansion so the
    /// single-line coaching call is explainable instead of an opaque decree.
    var coachingEvidence: [String] {
        var lines: [String] = []
        lines.append("Logged \(loggedDaysCount)/7 days this week")
        if loggedDaysCount > 0 {
            lines.append("Protein target hit on \(proteinHitDays)/\(loggedDaysCount) logged days")
        }
        if let trend = dashboardMeasurementTrend, let change = trend.waistChangeIn, abs(change) > 0.05 {
            lines.append(String(format: "Waist %+.1f in over the trend window", change))
        }
        if let sleepTrend, sleepTrend.acuteLoggedDays > 0 {
            lines.append("3-day sleep average \(SleepFormatting.duration(sleepTrend.threeDayAverageHours))")
        }
        if let daysAgo = analysisDaysAgo {
            lines.append("Body analysis \(daysAgo)d old")
        }
        return lines
    }

    func performCoachAction(_ action: CoachAction) {
        TFHaptics.impact(.light)
        switch action {
        case .logMeal:
            showAddFoodSheet = true
        case .logSleep:
            quickSleepLogPresented = true
        case .reanalyze:
            selectedTab = .analysis
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

                        VStack(spacing: TFSpacing.cardGap) {
                            coachingHeadlineCard
                                .cardEntrance(index: 0)
                            trainingTodayCard
                                .cardEntrance(index: 1)
                            todayRingsCard
                                .cardEntrance(index: 2)
                            weightAndRecompCard
                                .cardEntrance(index: 3)
                            sleepRecoveryCard
                                .cardEntrance(index: 4)
                            WorkoutTimingInsightsCard()
                                .cardEntrance(index: 5)
                            weekCalorieChart
                                .cardEntrance(index: 6)
                            bottomPadding
                        }
                        .padding(.horizontal, TFSpacing.horizontalMargin)
                    }
                }
                .ignoresSafeArea(edges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
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
                SleepEntryEditor(episode: request.episode)
            }
            .sheet(isPresented: $quickSleepLogPresented) {
                SleepQuickLogSheet { episode in
                    sleepEditorRequest = SleepEditorRequest(episode: episode)
                }
            }
            .onAppear {
                SleepTrendStore.refresh(using: modelContext)
                autoImportSleepIfEnabled()
                lastBackupDate = DataBackupManager.shared.lastAutomaticBackupDate
                withAnimation(.easeOut(duration: 0.9).delay(0.2)) {
                    animateRings = true
                }
            }
            .onChange(of: sleepEntriesChangeToken) { _, _ in
                SleepTrendStore.refresh(using: modelContext)
            }
            .onChange(of: showSettings) { _, isPresented in
                if !isPresented {
                    lastBackupDate = DataBackupManager.shared.lastAutomaticBackupDate
                }
            }
        }
    }

    // MARK: - Apple Health sleep sync

    /// Pull recent sleep from Apple Health when the user enabled the source, throttled so
    /// returning to the dashboard doesn't re-query every time. The import is idempotent
    /// (it never overwrites a manual log and updates its own rows in place), and the
    /// SwiftData insert propagates through the sleep @Query, so the rings react on their
    /// own — no explicit refresh needed here.
    private func autoImportSleepIfEnabled() {
        guard UserDefaults.standard.bool(forKey: AppSettingsKeys.healthKitSleepImportEnabled) else { return }
        if let last = UserDefaults.standard.object(forKey: AppSettingsKeys.healthKitSleepLastImport) as? Date,
           Date().timeIntervalSince(last) < 15 * 60 {
            return
        }
        Task {
            await SleepHealthKitService.shared.importRecentSleep(into: modelContext)
        }
    }

    // MARK: - Next Meal Name

    var proteinRemainingG: Double {
        activeMacroTargets.proteinG - todayProtein
    }

    var nextMealName: String {
        let now = Date()

        if let lastMeal = todayNutrition.max(by: { $0.date < $1.date }) {
            let hoursSinceLast = now.timeIntervalSince(lastMeal.date) / 3600
            if hoursSinceLast < 2 {
                return proteinRemainingG > 30 ? "Protein Snack" : "Snack"
            }
        }

        // Time of day decides the default so custom meal names (post-call
        // meals, shift snacks) can't force "Breakfast" at 8pm; the logged-name
        // check only prevents suggesting a meal that was already logged.
        let loggedMeals = Set(todayNutrition.map { $0.mealName.lowercased() })
        let hour = Calendar.current.component(.hour, from: now)
        let windowMeal: String
        switch hour {
        case 4..<11: windowMeal = "Breakfast"
        case 11..<16: windowMeal = "Lunch"
        case 16..<22: windowMeal = "Dinner"
        default: windowMeal = proteinRemainingG > 30 ? "Protein Snack" : "Snack"
        }
        if !loggedMeals.contains(windowMeal.lowercased()) { return windowMeal }
        if hour < 16, !loggedMeals.contains("lunch") { return "Lunch" }
        if !loggedMeals.contains("dinner") { return "Dinner" }
        return proteinRemainingG > 30 ? "Protein Snack" : "Snack"
    }

    // MARK: - Hero Header

    var heroHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [TFColor.accent, TFColor.accentWarm],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(greetingText)
                        .font(TFTypography.greeting)
                        .foregroundStyle(.white.opacity(0.5))
                        .textCase(.uppercase)
                        .tracking(2)

                    Text("Transform.")
                        .font(TFTypography.heroTitle)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, TFColor.accentWarm],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }

            HStack(alignment: .center) {
                backupStatusChip

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                        .font(TFTypography.chipLabel)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                Spacer()

                // Border-only on purpose: filled capsules in this header mean
                // "tappable"; the date is a read-only chip.
                Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                    .font(TFTypography.datePill)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .bottomLeading)
        .background {
            ZStack {
                LinearGradient(
                    colors: [TFColor.heroGradientBottom, TFColor.heroGradientTop],
                    startPoint: .bottom,
                    endPoint: .top
                )

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
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [TFColor.accent.opacity(0.6), TFColor.accentWarm.opacity(0.15), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
        }
    }

    /// Data-safety status, not an action menu: shows how stale the rolling
    /// automatic backup is and deep-links to Settings, where the export/import
    /// actions now live. Turns amber when the newest backup is old enough to
    /// matter in a recovery.
    var backupStatusChip: some View {
        let staleAfterDays = 3
        let daysAgo = lastBackupDate.map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
        }
        let isStale = daysAgo.map { $0 >= staleAfterDays } ?? true
        let text: String = {
            guard let daysAgo else { return "No backup yet" }
            if daysAgo == 0 { return "Backed up today" }
            return "Backup \(daysAgo)d ago"
        }()

        return Button {
            showSettings = true
        } label: {
            Label(text, systemImage: isStale ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.checkmark")
                .font(TFTypography.chipLabel)
                .foregroundStyle(isStale ? TFColor.warning : .white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Backup status: \(text). Opens Settings.")
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
        let verdict = coachingVerdict
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                TFHaptics.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    headlineExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(verdict.color)
                        .frame(width: 4, height: 36)
                    Text(verdict.message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(headlineExpanded ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if headlineExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .padding(.vertical, 8)

                    ForEach(coachingEvidence, id: \.self) { line in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(verdict.color.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let action = verdict.action, let label = verdict.actionLabel {
                        Button {
                            performCoachAction(action)
                        } label: {
                            Label(label, systemImage: "arrow.right.circle.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(verdict.color == .secondary ? TFColor.accent : verdict.color)
                        .padding(.top, 6)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: TFRadius.cardCompact)
                .fill(verdict.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TFRadius.cardCompact)
                .strokeBorder(verdict.color.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Coaching: \(verdict.message). Double-tap to \(headlineExpanded ? "hide" : "show") the evidence behind this.")
    }

    // MARK: - Training Today Card

    /// Deliberately compact: one glanceable line about the next session that
    /// deep-links to the actual day page in the Workout tab, instead of a full
    /// program card crowding the dashboard.
    var trainingTodayCard: some View {
        Button {
            TFHaptics.impact(.light)
            if let day = nextTrainingDay {
                workoutDeepLink.pendingDayNumber = day.dayNumber
            }
            selectedTab = .workout
        } label: {
            HStack(spacing: TFSpacing.innerGap) {
                Image(systemName: trainingCardIcon)
                    .font(.title3)
                    .foregroundStyle(TFColor.accent)
                    .frame(width: 38, height: 38)
                    .background(TFColor.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.inner))

                VStack(alignment: .leading, spacing: 2) {
                    Text(trainingCardTitle)
                        .font(TFTypography.cardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(trainingCardSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .compactCard()
            .contentShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        }
        .pressable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training: \(trainingCardTitle). \(trainingCardSubtitle). Opens the Workout tab.")
    }

    var trainingCardIcon: String {
        guard currentProgram != nil else { return "figure.strengthtraining.traditional" }
        guard let day = nextTrainingDay else { return "checkmark.seal.fill" }
        return day.isRestDay ? "bed.double.fill" : "figure.strengthtraining.traditional"
    }

    var trainingCardTitle: String {
        guard currentProgram != nil else { return "No active program" }
        guard let day = nextTrainingDay else { return "Week complete" }
        if day.isRestDay { return "Rest day" }
        return day.dayName.isEmpty ? "Next session" : day.dayName
    }

    var trainingCardSubtitle: String {
        guard let program = currentProgram else {
            return "Generate your next mesocycle in the Workout tab"
        }
        guard let day = nextTrainingDay else {
            return program.canGenerateNextWeek
                ? "All sessions done — generate week \(program.currentWeek + 1) when ready"
                : "Mesocycle finished — start a new program when ready"
        }
        if day.isRestDay {
            return "Recovery: mobility, light cardio · Week \(program.currentWeek)"
        }
        let groups = day.muscleGroups.isEmpty ? "Training" : day.muscleGroups
        return "\(groups) · \(day.exercises.count) exercises · Week \(program.currentWeek)"
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
                .tint(TFColor.accent)
            }

            HStack(spacing: 20) {
                ZStack {
                    AnimatedRing(
                        progress: animateRings ? safeRatio(todayFat, activeMacroTargets.fatG) : 0,
                        color: TFColor.fat,
                        size: 130,
                        lineWidth: 10
                    )
                    AnimatedRing(
                        progress: animateRings ? safeRatio(todayCarbs, activeMacroTargets.carbsG) : 0,
                        color: TFColor.carbs,
                        size: 106,
                        lineWidth: 10
                    )
                    AnimatedRing(
                        progress: animateRings ? safeRatio(todayProtein, activeMacroTargets.proteinG) : 0,
                        color: TFColor.protein,
                        size: 82,
                        lineWidth: 10
                    )

                    VStack(spacing: 0) {
                        Text("\(todayCalories)")
                            .font(TFTypography.ringValue)
                        Text("kcal")
                            .font(TFTypography.ringUnit)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 140, height: 140)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Today's macros: \(todayCalories) of \(activeMacroTargets.calories) calories, \(Int(todayProtein)) of \(Int(activeMacroTargets.proteinG)) grams protein, \(Int(todayCarbs)) of \(Int(activeMacroTargets.carbsG)) grams carbs, \(Int(todayFat)) of \(Int(activeMacroTargets.fatG)) grams fat")

                VStack(alignment: .leading, spacing: 10) {
                    // Calories is the ring-center number, not a ring — styled as
                    // a summary row so the legend doesn't advertise a fourth
                    // ring that doesn't exist.
                    HStack(spacing: 8) {
                        Text("Calories")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(todayCalories)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("/ \(activeMacroTargets.calories)kcal")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Divider()
                    ringLegendRow(color: TFColor.protein, label: "Protein", value: "\(Int(todayProtein))", target: "\(Int(activeMacroTargets.proteinG))", unit: "g")
                    ringLegendRow(color: TFColor.carbs, label: "Carbs", value: "\(Int(todayCarbs))", target: "\(Int(activeMacroTargets.carbsG))", unit: "g")
                    ringLegendRow(color: TFColor.fat, label: "Fat", value: "\(Int(todayFat))", target: "\(Int(activeMacroTargets.fatG))", unit: "g")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Image(systemName: remainingCaloriesToday >= 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(remainingCaloriesToday >= 0 ? TFColor.success : TFColor.danger)
                    .font(.caption)
                Text(remainingCaloriesToday >= 0
                     ? "\(remainingCaloriesToday) calories remaining today"
                     : "\(abs(remainingCaloriesToday)) calories over target")
                    .font(.caption)
                    .foregroundStyle(remainingCaloriesToday >= 0 ? Color.secondary : TFColor.danger)
                Spacer()
            }
            .padding(.top, 2)

            adherenceLine
        }
        .heroCard()
    }

    func safeRatio(_ value: Double, _ target: Double) -> Double {
        guard target > 0 else { return 0 }
        return value / target
    }

    var adherenceLine: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 9))
                    .foregroundStyle(TFColor.accent)
                Text("Logged: \(loggedDaysCount)/7")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TFColor.accent.opacity(0.08))
            .clipShape(Capsule())

            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(TFColor.protein)
                Text(loggedDaysCount > 0 ? "Protein: \(proteinHitDays)/\(loggedDaysCount)" : "Protein: —")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(TFColor.protein.opacity(0.08))
            .clipShape(Capsule())

            Spacer()
        }
    }

    func ringLegendRow(color: Color, label: String, value: String, target: String, unit: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3, height: 18)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text("/ \(target)\(unit)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Sleep & Recovery

    /// Whether the wake-day a quick log would be credited to (yesterday shortly
    /// after midnight — see SleepQuickLogPolicy) already has a main sleep. Drives
    /// the "log it in 3 taps" nudge so it doesn't fire at 12:30 AM for a night
    /// that was already logged yesterday morning.
    var creditedWakeDayHasMainSleep: Bool {
        let dayStart = SleepQuickLogPolicy.creditedWakeDayStart(loggedAt: .now)
        return sleepEpisodes.contains {
            $0.episodeType == .mainSleep
                && Calendar.current.startOfDay(for: $0.resolvedEndDate) == dayStart
        }
    }

    /// The recovery tier the next generated program will apply, with its audit line —
    /// the same decision function the generator uses, so the card cannot drift from behavior.
    @ViewBuilder
    func recoveryModulationLine(for trend: SleepTrendSnapshot) -> some View {
        let decision = SleepRecoveryPolicy.decision(from: trend.recoveryState())
        let presentation: (label: String, icon: String, color: Color) = {
            switch decision.tier {
            case .ready:
                return ("Recovery ready — full volume targets", "checkmark.circle.fill", TFColor.success)
            case .constrained:
                return ("Next program: volume capped mid-band", "gauge.medium", TFColor.accent)
            case .restricted:
                return ("Next program: volume pulled to band floor", "arrow.down.circle.fill", TFColor.danger)
            case .insufficientData:
                return ("Recovery adjustment off — \(decision.audit)", "questionmark.circle", Color.secondary)
            }
        }()
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.label)
                    .font(.caption.bold())
                if decision.tier == .constrained || decision.tier == .restricted {
                    Text(decision.audit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: presentation.icon)
        }
        .foregroundStyle(presentation.color)
    }

    var sleepRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TFSectionLabel(text: "Sleep & Recovery", color: TFColor.sleep)
                Spacer()
                Button {
                    quickSleepLogPresented = true
                } label: {
                    Label("Log Sleep", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(TFColor.sleep)
            }

            if let trend = sleepTrend {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(SleepFormatting.duration(trend.sevenDayAverageHours)) average")
                            .font(.title3.bold())
                        Text(
                            trend.acuteLoggedDays > 0
                                ? "Recent 3-day: \(SleepFormatting.duration(trend.threeDayAverageHours)) · \(trend.acuteLoggedDays)/3 logged"
                                : "No sleep logged in the last 3 days"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Quality \(String(format: "%.1f", trend.averageQuality))/5")
                            .font(.caption.bold())
                        Text("\(trend.loggedDays)/7 days logged")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Label(
                        "\(trend.underSixHours) short",
                        systemImage: trend.underSixHours > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(trend.underSixHours > 0 ? TFColor.accent : TFColor.success)

                    Label(
                        "\(trend.variabilityLabel) variability",
                        systemImage: "waveform.path.ecg"
                    )
                    .foregroundStyle(.secondary)

                    if trend.hasRecentPostCallRecovery {
                        Label("Post-call", systemImage: "cross.case.fill")
                            .foregroundStyle(TFColor.sleep)
                    }

                    Spacer()
                }
                .font(.caption2)

                recoveryModulationLine(for: trend)

                if !creditedWakeDayHasMainSleep {
                    Button {
                        quickSleepLogPresented = true
                    } label: {
                        Label("Last night not logged yet — log it in 3 taps", systemImage: "moon.stars.fill")
                            .font(.caption.bold())
                            .foregroundStyle(TFColor.sleep)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: TFSpacing.innerGap) {
                    Image(systemName: "bed.double.fill")
                        .font(.title2)
                        .foregroundStyle(TFColor.sleep)
                        .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.3))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No sleep logged yet")
                            .font(TFTypography.cardTitle)
                        Text("A 10-second daily log is enough to build useful recovery context.")
                            .font(TFTypography.body)
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
                .foregroundStyle(TFColor.sleep)
            }
            .buttonStyle(.plain)
        }
        .dashCard()
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
                .tint(TFColor.accent)
                if let delta = weightTrend.weeklyChangeLbs {
                    deltaBadge(delta)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(currentWeight.map { String(format: "%.1f", $0) } ?? "--")
                    .font(TFTypography.heroMetric)
                    .foregroundStyle(.primary)
                Text("lbs")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TFColor.accent.opacity(0.6))
                    .padding(.bottom, 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current weight: \(currentWeight.map { String(format: "%.1f", $0) } ?? "no data") pounds")
            if let trend = weightTrend.currentTrendWeightLbs {
                Text("7-day trend \(String(format: "%.1f", trend)) lb · \(weightTrend.dataQuality.rawValue) data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            goalProgressSection

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
                            .foregroundStyle(TFColor.measurement.opacity(0.6))
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

            if displayedWeightPoints.count > 1 {
                HStack {
                    Text("Raw weight + 7-day trend")
                    Spacer()
                    if let weeklyPct = weightTrend.weeklyChangePct {
                        Text(String(format: "%+.2f%% / week", weeklyPct))
                    }
                }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Chart(displayedWeightPoints) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Raw weight", entry.rawWeightLbs),
                        series: .value("Series", "Raw")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Raw weight", entry.rawWeightLbs)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .symbolSize(10)

                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Trend weight", entry.trendWeightLbs),
                        series: .value("Series", "7-day trend")
                    )
                    .foregroundStyle(TFColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(TFColor.accent.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(TFColor.accent.opacity(0.35))
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(TFColor.accent.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(TFColor.accent.opacity(0.35))
                        AxisValueLabel()
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: weightTrendDomain)
                .frame(height: 120)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Body weight trend chart")
                .accessibilityValue(weightChartAccessibilitySummary)
            } else {
                Text("Log at least two entries to see your trend graph.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .heroCard()
    }

    // MARK: - Goal Progress Section

    var goalBarFraction: Double {
        switch weightGoalState {
        case .approaching(let progress, _): return progress
        case .atGoal, .pastGoal: return 1.0
        case .noData: return 0
        }
    }

    var goalStatusText: String {
        switch weightGoalState {
        case .approaching(_, let remaining):
            return String(format: "%.1f lb to goal", remaining)
        case .atGoal:
            return "At goal"
        case .pastGoal(let overshoot):
            return String(format: "%.1f lb past goal", overshoot)
        case .noData:
            return ""
        }
    }

    var goalStatusColor: Color {
        switch weightGoalState {
        case .approaching: return TFColor.accent
        case .atGoal: return TFColor.success
        case .pastGoal: return TFColor.warning
        case .noData: return .secondary
        }
    }

    @ViewBuilder
    var goalProgressSection: some View {
        if case .noData = weightGoalState {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Goal: \(String(format: "%.0f", Config.bodyWeightGoalLbs)) lbs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(goalStatusText)
                        .font(.caption.bold())
                        .foregroundStyle(goalStatusColor)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(TFColor.accent.opacity(0.12))
                            .frame(height: 7)
                        Capsule()
                            .fill(goalBarGradient)
                            .frame(width: geo.size.width * (animateRings ? goalBarFraction : 0), height: 7)
                            .animation(.easeOut(duration: 1.0).delay(0.3), value: animateRings)
                    }
                }
                .frame(height: 6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Goal \(String(format: "%.0f", Config.bodyWeightGoalLbs)) pounds: \(goalStatusText)")
        }
    }

    var goalBarGradient: LinearGradient {
        switch weightGoalState {
        case .atGoal:
            return LinearGradient(colors: [TFColor.success, TFColor.success.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        case .pastGoal:
            return LinearGradient(colors: [TFColor.accentWarm, TFColor.warning], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [TFColor.accent, TFColor.accentWarm], startPoint: .leading, endPoint: .trailing)
        }
    }

    @ViewBuilder
    func recompContextSection(trend: MeasurementTrendSnapshot) -> some View {
        Divider()
            .padding(.vertical, 2)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ruler")
                    .font(.caption2)
                    .foregroundStyle(TFColor.measurement)

                dashboardInterpretationBadge(trend.interpretation)

                if let waist = trend.latestWaistIn {
                    HStack(spacing: 2) {
                        Text("Waist \(String(format: "%.1f", waist))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let change = trend.waistChangeIn, abs(change) > 0.05 {
                            Text(String(format: "%+.1f", change))
                                .font(.caption2.bold())
                                .foregroundStyle(change < 0 ? TFColor.success : TFColor.danger)
                        }
                    }
                }

                dashboardConfidenceBadge(trend.progressConfidence)

                Spacer()
            }

            if let signal = trend.waistToWeightRatio {
                Text(signal)
                    .font(.caption2)
                    .foregroundStyle(TFColor.measurement)
            }
        }
    }

    func dashboardInterpretationBadge(_ interpretation: MeasurementInterpretation) -> some View {
        let color: Color = {
            switch interpretation {
            case .likelyFatLoss: return TFColor.success
            case .likelyRecomposition: return TFColor.info
            case .likelyMassGain: return TFColor.accent
            case .possibleNoise: return TFColor.warning
            case .insufficientData, .stableNoChange: return .secondary
            }
        }()
        return Text(interpretation.rawValue)
            .font(TFTypography.badgeLabel)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    func dashboardConfidenceBadge(_ confidence: ProgressConfidence) -> some View {
        let color: Color = {
            switch confidence {
            case .high: return TFColor.success
            case .moderate: return TFColor.warning
            case .low: return TFColor.accent
            case .insufficient: return .secondary
            }
        }()
        return Text(confidence.rawValue)
            .font(TFTypography.badgeLabel)
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

            Chart {
                ForEach(weekCalorieData) { day in
                    if day.isLogged {
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Calories", day.calories)
                        )
                        .foregroundStyle(
                            Calendar.current.isDate(day.date, inSameDayAs: dayClock.today)
                            ? TFColor.accent
                            : TFColor.accent.opacity(0.35)
                        )
                        .cornerRadius(4)
                    } else {
                        // Short gray stub so an unlogged day reads as "no data"
                        // instead of blending into the axis like a fasted day.
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Calories", Double(activeMacroTargets.calories) * 0.04)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .cornerRadius(2)
                    }
                }

                RuleMark(y: .value("Target", activeMacroTargets.calories))
                    .foregroundStyle(TFColor.accent.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(Calendar.current.isDate(date, inSameDayAs: dayClock.today) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("7-day calorie intake chart")
            .accessibilityValue(weekCalorieAccessibilitySummary)

            weekAverageLine

            analysisFreshnessLine
        }
        .dashCard()
    }

    var weekAverageLine: some View {
        HStack(spacing: 4) {
            if let average = weekAverageCalories {
                // Judge the average against target only with enough logged days
                // to mean something, and judge it phase-aware: over target is
                // the plan in a gaining phase, not a failure.
                let color: Color = {
                    guard weekLoggedDayCount >= 4 else { return .secondary }
                    return trainingPhase.isCalorieAverageGood(
                        average: average,
                        target: Double(activeMacroTargets.calories)
                    ) ? TFColor.success : TFColor.danger
                }()
                Text("Avg:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(Int(average)) kcal")
                    .font(.caption2.bold())
                    .foregroundStyle(color)
                Text("across ^[\(weekLoggedDayCount) logged day](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("· Target: \(activeMacroTargets.calories) kcal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No days logged this week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    var analysisFreshnessLine: some View {
        HStack(spacing: 4) {
            if let daysAgo = analysisDaysAgo, let freshness = analysisFreshness {
                let color = freshnessColor(freshness)
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(color)
                Text("Last analysis: ^[\(daysAgo) day](inflect: true) ago")
                    .font(.caption2)
                    .foregroundStyle(color)
                if freshness == .stale {
                    Text("· Consider re-analyzing")
                        .font(.caption2)
                        .foregroundStyle(TFColor.accent)
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

            if activeMacroTargets.source == .adaptiveReview {
                Text("Adaptive targets")
                    .font(.caption2)
                    .foregroundStyle(TFColor.success.opacity(0.75))
            } else if activeMacroTargets.source == .analysis {
                if let daysAgo = analysisDaysAgo {
                    let stale = analysisFreshness == .stale
                    Text("AI targets · \(daysAgo)d")
                        .font(.caption2)
                        .foregroundStyle(stale ? TFColor.danger.opacity(0.7) : TFColor.accent.opacity(0.6))
                } else {
                    Text("AI targets")
                        .font(.caption2)
                        .foregroundStyle(TFColor.accent.opacity(0.6))
                }
            } else {
                Text("Config targets")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    var bottomPadding: some View {
        Color.clear.frame(height: 20)
    }

    // MARK: - Chart Accessibility Summaries

    var weightChartAccessibilitySummary: String {
        var parts: [String] = []
        if let trend = weightTrend.currentTrendWeightLbs {
            parts.append("7-day trend \(String(format: "%.1f", trend)) pounds")
        }
        if let weekly = weightTrend.weeklyChangeLbs {
            parts.append(String(format: "%+.1f pounds per week", weekly))
        }
        return parts.isEmpty ? "Not enough data yet" : parts.joined(separator: ", ")
    }

    var weekCalorieAccessibilitySummary: String {
        guard let average = weekAverageCalories else {
            return "No days logged this week. Target \(activeMacroTargets.calories) calories."
        }
        return "Average \(Int(average)) calories across \(weekLoggedDayCount) logged days, against a target of \(activeMacroTargets.calories)"
    }

    // MARK: - Helpers

    func sectionLabel(_ text: String) -> some View {
        TFSectionLabel(text: text)
    }

    /// Colors the weekly change by whether it moves toward the goal for the
    /// current training phase — never by a hardcoded "loss is good" rule. A
    /// change inside the noise band renders neutral, not red.
    func deltaBadge(_ delta: Double) -> some View {
        let verdict = trainingPhase.isWeeklyChangeGood(delta)
        let badgeColor: Color = {
            switch verdict {
            case .some(true): return TFColor.success
            case .some(false): return TFColor.danger
            case .none: return .secondary
            }
        }()
        let icon: String = {
            if delta > 0.05 { return "arrow.up.right" }
            if delta < -0.05 { return "arrow.down.right" }
            return "arrow.right"
        }()
        let sign = delta > 0 ? "+" : ""
        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text("\(sign)\(String(format: "%.1f", delta)) lbs")
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(badgeColor.opacity(0.15))
        .foregroundStyle(badgeColor)
        .clipShape(Capsule())
        .accessibilityLabel("Weekly change \(sign)\(String(format: "%.1f", delta)) pounds")
    }
}

// MARK: - Animated Ring

struct AnimatedRing: View {
    /// May exceed 1.0 — overshoot renders as a darker second lap (the Apple
    /// rings idiom) instead of being clamped invisible, so an over-target fat
    /// or protein day is distinguishable from a perfectly-hit one.
    let progress: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    private var baseProgress: Double { min(progress, 1.0) }
    private var overflowProgress: Double { min(max(progress - 1.0, 0), 1.0) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: baseProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: baseProgress)
            Circle()
                .trim(from: 0, to: overflowProgress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .brightness(-0.25)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: overflowProgress)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
