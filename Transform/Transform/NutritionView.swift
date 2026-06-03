import SwiftUI
import SwiftData
import Charts

struct NutritionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NutritionEntry.date, order: .reverse) private var allEntries: [NutritionEntry]
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var analysisSessions: [BodyAnalysisSession]
    @Query(sort: \SavedNutritionProtocol.updatedAt, order: .reverse) private var savedNutritionProtocols: [SavedNutritionProtocol]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]

    @State private var selectedDate = Date()
    @State private var showAddSheet = false
    @State private var preselectedMeal = "Breakfast"
    @State private var entryToDelete: NutritionEntry?
    @State private var showDeleteConfirm = false
    @State private var pendingCopyMeal: String?
    @State private var showCopyConflictDialog = false
    @State private var nutritionProgram: NutritionProgramResponse?
    @State private var followupWeeks: [NutritionWeekResponse] = []
    @State private var selectedWeek: Int = 1
    @State private var selectedTemplate: NutritionTemplateSelection = .training
    @State private var isGeneratingNutrition = false
    @State private var nutritionErrorMessage = ""
    @State private var generationProgress: String = ""
    @State private var nutritionGenerationTask: Task<Void, Never>?
    @AppStorage("nutrition_shift_work_mode") private var shiftWorkModeRaw = ShiftWorkNutritionMode.normal.rawValue

    let mealOrder = ["Breakfast", "Lunch", "Dinner", "Snack"]

    var todayEntries: [NutritionEntry] {
        allEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var groupedEntries: [(String, [NutritionEntry])] {
        mealOrder.compactMap { meal in
            let entries = todayEntries.filter { $0.mealName == meal }
            return entries.isEmpty ? nil : (meal, entries)
        }
    }

    var totalCalories: Int { todayEntries.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { todayEntries.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { todayEntries.reduce(0) { $0 + $1.carbsG } }
    var totalSugar: Double { todayEntries.reduce(0) { $0 + $1.sugarG } }
    var totalFiber: Double { todayEntries.reduce(0) { $0 + $1.fiberG } }
    var totalFat: Double { todayEntries.reduce(0) { $0 + $1.fatG } }
    var canUseAI: Bool { Config.hasAnthropicKey }
    var latestAnalysis: BodyAnalysisResult? { analysisSessions.first?.decodedResult }
    var activeMacroTargets: DailyMacroTargets { MacroTargetResolver.resolve(from: latestAnalysis) }
    var remainingCalories: Int { activeMacroTargets.calories - totalCalories }

    // Heuristic cap: keep added/free sugars under ~10% of calories (aligned with broad public-
    // health guidance) and also below ~35% of total carbs so the carb budget still leaves room
    // for starch and fiber. This is a practical nutrition guardrail, not a hypertrophy-specific law.
    var sugarTargetG: Double {
        min((Double(activeMacroTargets.calories) * 0.10) / 4.0, activeMacroTargets.carbsG * 0.35)
    }

    // Mixed evidence + heuristic target: 14 g / 1000 kcal is a standard fiber anchor, with a
    // 30 g floor for most adults. The +5 g bump when the analysis flags insulin/glycemic issues
    // is a pragmatic coaching adjustment rather than a high-confidence hard rule.
    var fiberTargetG: Double {
        var base = max((Double(activeMacroTargets.calories) / 1000.0) * 14.0, 30.0)
        if let latest = latestAnalysis,
           latest.metabolicHealthNotes.localizedCaseInsensitiveContains("insulin") ||
           latest.metabolicHealthNotes.localizedCaseInsensitiveContains("glycemic") {
            base += 5
        }
        return min(base, activeMacroTargets.carbsG)
    }

    var selectedShiftWorkMode: ShiftWorkNutritionMode {
        ShiftWorkNutritionMode(rawValue: shiftWorkModeRaw) ?? .normal
    }

    var adherenceMetrics: NutritionAdherenceMetrics {
        let lookback = 30
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookback, to: Date()) ?? Date()
        let recentNutritionDays = nutritionDaySummaries(since: cutoff)
        let recentWeightPoints = weightEntries
            .filter { $0.date >= cutoff }
            .map { AnalysisLoggedWeightPoint(date: $0.date, weightLbs: $0.weightLbs) }
        return NutritionAdherenceMetricsBuilder.build(
            nutritionDays: recentNutritionDays,
            weightPoints: recentWeightPoints,
            macroTargets: activeMacroTargets,
            lookbackDays: lookback
        )
    }

    private func nutritionDaySummaries(since startDate: Date) -> [AnalysisLoggedNutritionDay] {
        let calendar = Calendar.current
        let grouped = allEntries
            .filter { $0.date >= startDate }
            .reduce(into: [Date: AnalysisLoggedNutritionDay]()) { partialResult, entry in
                let day = calendar.startOfDay(for: entry.date)
                let existing = partialResult[day] ?? AnalysisLoggedNutritionDay(
                    date: day, calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, mealCount: 0
                )
                partialResult[day] = AnalysisLoggedNutritionDay(
                    date: day,
                    calories: existing.calories + entry.calories,
                    proteinG: existing.proteinG + entry.proteinG,
                    carbsG: existing.carbsG + entry.carbsG,
                    fatG: existing.fatG + entry.fatG,
                    fiberG: existing.fiberG + entry.fiberG,
                    mealCount: existing.mealCount + 1
                )
            }
        return grouped.values.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dateNavigator
                    macroRingsCard
                    macroBarCard
                    AdherenceSnapshotCard(metrics: adherenceMetrics)
                    groceryPlannerCard
                    mealLogSection
                }
                .padding()
            }
            .navigationTitle("Nutrition")
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
                AddFoodSheet(selectedDate: selectedDate, preselectedMeal: preselectedMeal)
            }
            .alert("Delete Entry?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete {
                        deleteEntry(entry)
                    }
                }
                Button("Cancel", role: .cancel) {
                    entryToDelete = nil
                }
            } message: {
                if let entry = entryToDelete {
                    Text("Delete \(entry.notes.isEmpty ? "this entry" : entry.notes)?")
                }
            }
            .confirmationDialog(
                "This meal already has entries today.",
                isPresented: $showCopyConflictDialog,
                titleVisibility: .visible
            ) {
                Button("Replace Existing", role: .destructive) {
                    if let meal = pendingCopyMeal {
                        copyYesterdayMeal(meal, mode: .replaceExisting)
                    }
                    pendingCopyMeal = nil
                }
                Button("Append Anyway") {
                    if let meal = pendingCopyMeal {
                        copyYesterdayMeal(meal, mode: .append)
                    }
                    pendingCopyMeal = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingCopyMeal = nil
                }
            } message: {
                if let meal = pendingCopyMeal {
                    Text("Choose how to copy yesterday's \(meal.lowercased()) into today.")
                }
            }
            .onAppear {
                loadSavedNutritionProtocolIfNeeded()
            }
            .onChange(of: savedNutritionProtocols.count) { _, _ in
                loadSavedNutritionProtocolIfNeeded()
            }
            .onDisappear {
                nutritionGenerationTask?.cancel()
                nutritionGenerationTask = nil
                isGeneratingNutrition = false
                generationProgress = ""
            }
        }
    }

    // MARK: - Date Navigator

    var dateNavigator: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.orange)
                    .padding(8)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(isToday ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.headline)
                Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                guard !isToday else { return }
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(isToday ? Color.secondary : Color.orange)
                    .padding(8)
            }
            .disabled(isToday)
        }
        .padding(.horizontal, 4)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    // MARK: - Macro Rings

    var macroRingsCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                ZStack {
                    MacroRing(
                        value: Double(totalCalories),
                        target: Double(activeMacroTargets.calories),
                        color: .orange,
                        lineWidth: 14,
                        size: 140
                    )

                    VStack(spacing: 2) {
                        Text("\(totalCalories)")
                            .font(.title2.bold())
                        Text("of \(activeMacroTargets.calories)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(remainingCalories >= 0 ? "\(remainingCalories)" : "\(abs(remainingCalories))")
                        .font(.title3.bold())
                        .foregroundStyle(remainingCalories >= 0 ? Color.green : Color.red)
                    Text(remainingCalories >= 0 ? "remaining" : "over")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider().padding(.vertical, 4)

                    miniMacroRow(label: "F", value: totalFat, target: activeMacroTargets.fatG, color: .yellow)
                    miniMacroRow(label: "C", value: totalCarbs, target: activeMacroTargets.carbsG, color: .blue)
                    miniMacroRow(label: "Fi", value: totalFiber, target: fiberTargetG, color: .green)
                    miniMacroRow(label: "S", value: totalSugar, target: sugarTargetG, color: .pink)
                    miniMacroRow(label: "P", value: totalProtein, target: activeMacroTargets.proteinG, color: .red)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    func miniMacroRow(label: String, value: Double, target: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(value))g")
                .font(.caption.bold())
            Text("/ \(Int(target))g")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Macro Bar Card

    var macroBarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Macros")
                .font(.headline)

            MacroProgressBar(
                label: "Calories",
                value: Double(totalCalories),
                target: Double(activeMacroTargets.calories),
                color: .orange,
                unit: "kcal"
            )
            MacroProgressBar(label: "Fat", value: totalFat, target: activeMacroTargets.fatG, color: .yellow)
            MacroProgressBar(label: "Total Carbs", value: totalCarbs, target: activeMacroTargets.carbsG, color: .blue)
            MacroProgressBar(label: "Fiber", value: totalFiber, target: fiberTargetG, color: .green)
            MacroProgressBar(label: "Sugars", value: totalSugar, target: sugarTargetG, color: .pink)
            MacroProgressBar(label: "Protein", value: totalProtein, target: activeMacroTargets.proteinG, color: .red)

            Text("Carbs are split into fiber and sugars with analysis-aware targets.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text(
                activeMacroTargets.source == .analysis
                ? "Targets source: latest AI body analysis"
                : "Targets source: Config fallback (run a new Body Analysis to populate AI macro targets)"
            )
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Grocery / Nutrition Planner

    var currentWeek: NutritionWeekResponse? {
        if selectedWeek == 1 { return nutritionProgram?.weekOne }
        return followupWeeks.first { $0.weekNumber == selectedWeek }
    }

    var generateButtonTitle: String {
        if nutritionProgram == nil { return "Generate 4-Week Nutrition Protocol" }
        return "Regenerate 4-Week Protocol"
    }

    var groceryPlannerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("AI 4-Week Nutrition Protocol", systemImage: "cart.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Text("Body-analysis driven")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }

            Text("A full 4-week nutrition protocol built from your latest Body Analysis. Includes Training Day + Rest Day templates (5 training / 2 rest assumed), 4 meals each, and a weekly grocery list. Mesocycle-aware progression across weeks.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if latestAnalysis == nil {
                Text("Run a Body Analysis first — this protocol is generated from its expert recommendations.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Schedule Mode")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Schedule Mode", selection: $shiftWorkModeRaw) {
                    ForEach(ShiftWorkNutritionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(.orange)
            }

            if selectedShiftWorkMode != .normal {
                Text(selectedShiftWorkMode.mealTimingGuidance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                startNutritionGeneration()
            } label: {
                HStack {
                    if isGeneratingNutrition {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 4)
                        Text(generationProgress.isEmpty ? "Generating…" : generationProgress)
                    } else {
                        Image(systemName: "sparkles")
                        Text(generateButtonTitle)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background((isGeneratingNutrition || !canUseAI || latestAnalysis == nil) ? Color.orange.opacity(0.5) : Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .bold()
            }
            .disabled(isGeneratingNutrition || !canUseAI || latestAnalysis == nil)

            if !canUseAI {
                Text(Config.anthropicKeyInlineHelpText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if !nutritionErrorMessage.isEmpty {
                Text(nutritionErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if let program = nutritionProgram {
                NutritionProgramHeader(program: program)

                weekSelector

                if let week = currentWeek {
                    NutritionWeekDetail(
                        week: week,
                        selectedTemplate: $selectedTemplate
                    )
                }
            } else {
                Text("Generate once. The plan is built from your Body Analysis — week 1 on Opus, weeks 2-4 on Sonnet for progression.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var weekSelector: some View {
        let availableWeeks = [1] + followupWeeks.map { $0.weekNumber }.sorted()
        return VStack(alignment: .leading, spacing: 6) {
            Text("Week")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(availableWeeks, id: \.self) { week in
                    Button {
                        selectedWeek = week
                    } label: {
                        Text("Week \(week)")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedWeek == week ? Color.orange : Color(.tertiarySystemBackground))
                            .foregroundStyle(selectedWeek == week ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Meal Log

    var mealLogSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Meals")
                .font(.headline)

            if todayEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange.opacity(0.5))
                    Text("No meals logged yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tap + to add your first meal")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(groupedEntries, id: \.0) { meal, entries in
                    MealGroupView(
                        mealName: meal,
                        entries: entries,
                        onDelete: { entry in
                            entryToDelete = entry
                            showDeleteConfirm = true
                        },
                        onAddMore: {
                            preselectedMeal = meal
                            showAddSheet = true
                        }
                    )
                }
            }

            quickAddButtons
        }
    }

    var quickAddButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Add")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(mealOrder, id: \.self) { meal in
                    Button(meal) {
                        preselectedMeal = meal
                        showAddSheet = true
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                    .foregroundStyle(.primary)
                }
            }

            copyYesterdayButtons
        }
    }

    var copyYesterdayButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Copy Yesterday")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(mealOrder, id: \.self) { meal in
                        let hasYesterday = !yesterdayEntries(for: meal).isEmpty
                        Button("Copy \(meal)") {
                            handleCopyYesterdayTap(meal)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(hasYesterday ? Color.orange.opacity(0.15) : Color(.tertiarySystemBackground))
                        .clipShape(Capsule())
                        .foregroundStyle(hasYesterday ? Color.orange : Color.secondary)
                        .disabled(!hasYesterday)
                    }
                }
            }
        }
    }

    func deleteEntry(_ entry: NutritionEntry) {
        modelContext.delete(entry)
        guard PersistenceReporter.save(modelContext, operation: "nutrition entry deletion") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        entryToDelete = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func yesterdayEntries(for meal: String) -> [NutritionEntry] {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else {
            return []
        }
        return allEntries.filter {
            $0.mealName == meal && Calendar.current.isDate($0.date, inSameDayAs: yesterday)
        }
    }

    func todayEntries(for meal: String) -> [NutritionEntry] {
        allEntries.filter {
            $0.mealName == meal && Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    func handleCopyYesterdayTap(_ meal: String) {
        guard !yesterdayEntries(for: meal).isEmpty else { return }
        if todayEntries(for: meal).isEmpty {
            copyYesterdayMeal(meal, mode: .append)
        } else {
            pendingCopyMeal = meal
            showCopyConflictDialog = true
        }
    }

    func copyYesterdayMeal(_ meal: String, mode: CopyMealMode) {
        let entriesToCopy = yesterdayEntries(for: meal)
        guard !entriesToCopy.isEmpty else { return }

        if mode == .replaceExisting {
            for existing in todayEntries(for: meal) {
                modelContext.delete(existing)
            }
        }

        for source in entriesToCopy {
            let copied = NutritionEntry(
                date: selectedDate,
                mealName: meal,
                calories: source.calories,
                proteinG: source.proteinG,
                carbsG: source.carbsG,
                fatG: source.fatG,
                notes: source.notes,
                sugarG: source.sugarG,
                fiberG: source.fiberG
            )
            modelContext.insert(copied)
        }

        guard PersistenceReporter.save(modelContext, operation: "copy yesterday meals") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    func startNutritionGeneration() {
        nutritionGenerationTask?.cancel()
        nutritionGenerationTask = Task {
            await generateNutritionProtocol()
        }
    }

    @MainActor
    func generateNutritionProtocol() async {
        guard canUseAI, let analysis = latestAnalysis else { return }

        let priorProgram = nutritionProgram
        let priorFollowups = followupWeeks

        guard !Task.isCancelled else { return }
        isGeneratingNutrition = true
        nutritionErrorMessage = ""
        generationProgress = "Generating Week 1 (Opus)…"
        defer {
            if !Task.isCancelled {
                isGeneratingNutrition = false
                generationProgress = ""
                nutritionGenerationTask = nil
            }
        }

        do {
            let generated = try await buildNutritionProtocol(from: analysis)
            try Task.checkCancellation()
            guard !Task.isCancelled else { return }

            nutritionProgram = generated.program
            followupWeeks = generated.followupWeeks
            selectedWeek = 1
            saveNutritionProtocolToStore(program: generated.program, followups: generated.followupWeeks)
            if let warning = generated.partialGenerationWarning {
                nutritionErrorMessage = warning
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            nutritionErrorMessage = "Generation failed: \(error.localizedDescription)"
            nutritionProgram = priorProgram
            followupWeeks = priorFollowups
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func buildNutritionProtocol(from analysis: BodyAnalysisResult) async throws -> NutritionProtocolBuildResult {
        let metrics = adherenceMetrics
        let shiftMode = selectedShiftWorkMode
        let program = try await ClaudeService.shared.generateNutritionWeekOne(
            from: analysis,
            adherenceMetrics: metrics,
            shiftWorkMode: shiftMode
        )
        var followupWeeks: [NutritionWeekResponse] = []
        var warningMessage: String?
        guard let initialWeekJSON = encodeWeekToJSON(program.weekOne) else {
            return NutritionProtocolBuildResult(
                program: program,
                followupWeeks: [],
                partialGenerationWarning: "Week 1 generated, but its saved JSON context could not be encoded, so weeks 2-4 were skipped."
            )
        }
        var previousWeekJSON = initialWeekJSON

        for week in 2...4 {
            await MainActor.run {
                generationProgress = "Generating Week \(week) (Sonnet)…"
            }

            do {
                let nextWeek = try await ClaudeService.shared.generateNutritionNextWeek(
                    weekNumber: week,
                    previousWeekJSON: previousWeekJSON,
                    analysisResult: analysis,
                    adherenceMetrics: metrics,
                    shiftWorkMode: shiftMode
                )
                try Task.checkCancellation()
                followupWeeks.append(nextWeek)
                guard let encodedWeek = encodeWeekToJSON(nextWeek) else {
                    warningMessage = "Week \(week) generated, but its saved JSON context could not be encoded, so later weeks were skipped."
                    break
                }
                previousWeekJSON = encodedWeek
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warningMessage = "Week \(week) did not generate: \(error.localizedDescription). Earlier weeks are still available."
                break
            }
        }

        return NutritionProtocolBuildResult(
            program: program,
            followupWeeks: followupWeeks,
            partialGenerationWarning: warningMessage
        )
    }

    func encodeWeekToJSON(_ week: NutritionWeekResponse) -> String? {
        encodeJSONString(week, context: "nutrition week")
    }

    func encodeProgramToJSON(_ program: NutritionProgramResponse) -> String? {
        encodeJSONString(program, context: "nutrition program")
    }

    func encodeFollowupsToJSON(_ followups: [NutritionWeekResponse]) -> String? {
        encodeJSONString(followups, context: "nutrition follow-up weeks")
    }

    func decodeProgramFromJSON(_ json: String) -> NutritionProgramResponse? {
        decodeJSON(NutritionProgramResponse.self, from: json, context: "saved nutrition program")
    }

    func decodeFollowupsFromJSON(_ json: String) -> [NutritionWeekResponse] {
        decodeJSON([NutritionWeekResponse].self, from: json, context: "saved nutrition follow-up weeks") ?? []
    }

    func loadSavedNutritionProtocolIfNeeded() {
        guard nutritionProgram == nil else { return }
        guard let saved = savedNutritionProtocols.first else {
            return
        }
        guard let decodedProgram = decodeProgramFromJSON(saved.programJSON) else {
            return
        }

        nutritionProgram = decodedProgram
        followupWeeks = decodeFollowupsFromJSON(saved.followupWeeksJSON)

        let availableWeeks = Set([1] + followupWeeks.map(\.weekNumber))
        if !availableWeeks.contains(selectedWeek) {
            selectedWeek = 1
        }
    }

    func saveNutritionProtocolToStore(program: NutritionProgramResponse, followups: [NutritionWeekResponse]) {
        guard let programJSON = encodeProgramToJSON(program),
              let followupsJSON = encodeFollowupsToJSON(followups) else {
            nutritionErrorMessage = "Could not save the nutrition protocol because its JSON payload could not be encoded."
            return
        }

        let now = Date()
        if let existing = savedNutritionProtocols.first {
            existing.updatedAt = now
            existing.programJSON = programJSON
            existing.followupWeeksJSON = followupsJSON
            for stale in savedNutritionProtocols.dropFirst() {
                modelContext.delete(stale)
            }
        } else {
            let saved = SavedNutritionProtocol(
                createdAt: now,
                updatedAt: now,
                programJSON: programJSON,
                followupWeeksJSON: followupsJSON
            )
            modelContext.insert(saved)
        }

        guard PersistenceReporter.save(modelContext, operation: "saved nutrition protocol") else {
            modelContext.rollback()
            nutritionErrorMessage = "Could not save the nutrition protocol. Please try again."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        // Keep the expensive full-export backup out of the AI-generation completion path.
    }

    func encodeJSONString<T: Encodable>(_ value: T, context: String) -> String? {
        do {
            let data = try JSONEncoder().encode(value)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ClaudeError.parseError("Could not convert encoded \(context) into UTF-8 text.")
            }
            return text
        } catch {
            print("[NutritionView] Failed to encode \(context): \(error)")
            return nil
        }
    }

    func decodeJSON<T: Decodable>(_ type: T.Type, from json: String, context: String) -> T? {
        guard let data = json.data(using: .utf8) else {
            print("[NutritionView] Failed to decode \(context): input was not valid UTF-8.")
            return nil
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("[NutritionView] Failed to decode \(context): \(error)")
            return nil
        }
    }

}

struct NutritionProtocolBuildResult {
    let program: NutritionProgramResponse
    let followupWeeks: [NutritionWeekResponse]
    let partialGenerationWarning: String?
}
