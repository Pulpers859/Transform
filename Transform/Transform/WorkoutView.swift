import SwiftUI
import SwiftData

/// Navigation target for the dashboard's training card: identifies a program
/// day by number so the route stays Hashable without dragging a @Model into
/// the navigation path.
nonisolated struct WorkoutDayRoute: Hashable {
    let dayNumber: Int
}

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkoutDeepLink.self) private var workoutDeepLink
    @Query(sort: \WorkoutProgram.createdDate, order: .reverse) private var programs: [WorkoutProgram]
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var analysisSessions: [BodyAnalysisSession]
    @Query(sort: \ExerciseWeightEntry.loggedAt, order: .reverse) private var exerciseWeightEntries: [ExerciseWeightEntry]
    @Query(sort: \ExercisePerformanceLog.loggedAt, order: .reverse) private var exercisePerformanceLogs: [ExercisePerformanceLog]

    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDeleteConfirm = false
    @State private var programToDelete: WorkoutProgram?
    @State private var showStartOverConfirm = false
    @State private var selectedWeek = 1
    @State private var showGeneratorLab = false
    @State private var generationTask: Task<Void, Never>?
    @State private var feedbackDay: WorkoutDay?
    @State private var analysisThumbnail: UIImage?
    @State private var lastSyncedProgramID: UUID?
    @State private var navPath = NavigationPath()

    var currentProgram: WorkoutProgram? { programs.first { !$0.isArchived } }
    var latestAnalysis: BodyAnalysisSession? { analysisSessions.first }
    var canUseAI: Bool { Config.hasAnthropicKey }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(spacing: 20) {
                    if let program = currentProgram {
                        programHeader(program)
                        generationStatusCard
                        validatorWarningsBanner(program)
                        weekSelector(program)
                        weekDaysList(program)
                        if program.canGenerateNextWeek {
                            generateNextWeekButton(program)
                        }
                        progressSummary(program)
                        dangerZone(program)
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .workoutTabBarClearance()
            .navigationTitle("Workout")
            .navigationDestination(for: WorkoutDayRoute.self) { route in
                if let program = currentProgram,
                   let day = program.sortedDays.first(where: { $0.dayNumber == route.dayNumber }) {
                    if day.isRestDay {
                        RestDayDetailView(day: day)
                    } else {
                        WorkoutDayDetailView(day: day)
                    }
                } else {
                    // Program changed between the dashboard tap and navigation.
                    ContentUnavailableView(
                        "Session Not Found",
                        systemImage: "figure.strengthtraining.traditional",
                        description: Text("This session is no longer part of the active program.")
                    )
                }
            }
            .task(id: latestAnalysis?.date) {
                if let data = latestAnalysis?.photoData {
                    analysisThumbnail = UIImage.downsampledImage(from: data, maxDimension: 60)
                }
            }
            .alert("Generation Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not generate program. Try again.")
            }
            .alert("Delete Program?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let program = programToDelete {
                        deleteProgram(program)
                    }
                }
                Button("Cancel", role: .cancel) {
                    programToDelete = nil
                }
            } message: {
                Text("This will permanently remove this workout program and all progress.")
            }
            .alert("Start Over?", isPresented: $showStartOverConfirm) {
                Button("Start Over", role: .destructive) {
                    if let result = latestAnalysis?.decodedResult {
                        startRegeneration(from: result, sourceAnalysisDate: latestAnalysis?.date)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This archives your current program and generates a brand-new Week 1. Your training history (weights, sets, skip patterns) is preserved. This uses AI generation credits.")
            }
            .sheet(isPresented: $showGeneratorLab) {
                WorkoutGeneratorLabView()
            }
            .sheet(item: $feedbackDay) { day in
                WorkoutSessionFeedbackSheet(day: day)
            }
            .onAppear {
                syncSelectedWeekWithCurrentProgram()
                consumePendingDeepLink()
            }
            .onChange(of: programs.map(\.id)) { _, _ in
                syncSelectedWeekWithCurrentProgram()
            }
            .onChange(of: currentProgram?.currentWeek) { _, _ in
                syncSelectedWeekWithCurrentProgram()
            }
            .onChange(of: workoutDeepLink.pendingDayNumber) { _, _ in
                consumePendingDeepLink()
            }
        }
    }

    /// Lands on the day page the dashboard's training card asked for: selects
    /// the week containing the day, then pushes its detail view.
    private func consumePendingDeepLink() {
        guard let dayNumber = workoutDeepLink.pendingDayNumber else { return }
        workoutDeepLink.pendingDayNumber = nil
        guard let program = currentProgram,
              program.sortedDays.contains(where: { $0.dayNumber == dayNumber }) else { return }
        selectedWeek = ((dayNumber - 1) / 7) + 1
        navPath = NavigationPath()
        navPath.append(WorkoutDayRoute(dayNumber: dayNumber))
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(TFColor.accent.opacity(0.5))
                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.3))

            VStack(spacing: 8) {
                Text("No Workout Program")
                    .font(TFTypography.cardTitle)
                    .fontWeight(.bold)
                Text("Generate a personalized 4-week program one week at a time, based on your latest body analysis.")
                    .font(TFTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let analysis = latestAnalysis, let result = analysis.decodedResult {
                VStack(spacing: TFSpacing.innerGap) {
                    HStack(spacing: TFSpacing.innerGap) {
                        if let image = analysisThumbnail {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: TFRadius.inner))
                        }

                        VStack(alignment: .leading, spacing: TFSpacing.microGap) {
                            Text("Latest Analysis")
                                .font(TFTypography.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(TFColor.accent)
                            Text(analysis.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !result.programmingPriorityAreas.isEmpty {
                                Text("Focus: " + result.programmingPriorityAreas.prefix(3).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .compactCard()

                    generateWeekOneButton(analysis: analysis, result: result)
                    generationStatusCard
                    if !canUseAI {
                        Text(Config.anthropicKeyInlineHelpText)
                            .font(.caption2)
                            .foregroundStyle(TFColor.danger)
                    }
                }
            } else {
                VStack(spacing: TFSpacing.tightGap) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Run a body analysis first to generate a tailored program.")
                        .font(TFTypography.body)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .compactCard()
            }

            Spacer()
        }
        .onLongPressGesture(minimumDuration: 1.2) {
            openGeneratorLab()
        }
    }

    func generateWeekOneButton(analysis: BodyAnalysisSession, result: BodyAnalysisResult) -> some View {
        Button {
            startFirstWeekGeneration(from: result, sourceAnalysisDate: analysis.date)
        } label: {
            HStack {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 4)
                    Text("Generating Week 1...")
                } else {
                    Image(systemName: "sparkles")
                    Text("Generate Week 1")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isGenerating ? TFColor.accent.opacity(0.6) : TFColor.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
            .bold()
        }
        .pressable()
        .disabled(isGenerating || !canUseAI)
    }

    // MARK: - Generation Status

    /// Live progress + cancel while an AI generation is in flight. Generation can run
    /// for minutes (parallel candidates, correction pass, fallback); a silent disabled
    /// button reads as a hang. The stage text comes from the same diagnostics the
    /// crash-recovery message uses.
    @ViewBuilder
    var generationStatusCard: some View {
        if isGenerating {
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    Text(WorkoutGenerationDiagnostics.currentStageDescription ?? "Contacting your AI coach…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    cancelGeneration()
                } label: {
                    Text("Cancel")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.danger)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(TFColor.danger.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(TFColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        TFHaptics.impact(.medium)
    }

    // MARK: - Program Header

    func programHeader(_ program: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(program.programName)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    programHeaderMetaLabel(
                        text: "\(program.daysPerWeek) days/week",
                        systemImage: "calendar"
                    )
                    programHeaderMetaLabel(
                        text: program.createdDate.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "clock"
                    )
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    programHeaderMetaLabel(
                        text: "\(program.daysPerWeek) days/week",
                        systemImage: "calendar"
                    )
                    programHeaderMetaLabel(
                        text: program.createdDate.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "clock"
                    )
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    programHeaderBadge(
                        program.splitType,
                        foreground: .orange,
                        background: TFColor.accent.opacity(0.15)
                    )
                    programHeaderBadge(
                        "Week \(program.currentWeek) of \(program.maxWeeks)",
                        foreground: .blue,
                        background: TFColor.info.opacity(0.15)
                    )
                    if let sourceBadge = generationSourceBadge(for: sourceSummaryForSelectedWeek(program)) {
                        programHeaderBadge(
                            sourceBadge.label,
                            foreground: sourceBadge.foreground,
                            background: sourceBadge.background
                        )
                    }
                }
                .padding(.vertical, 2)
                .padding(.trailing, 4)
            }
            .scrollClipDisabled()
            Text(summaryForSelectedWeek(program))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !program.focusAreas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Focus:")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        ForEach(program.focusAreas.components(separatedBy: ", ").prefix(5), id: \.self) { muscle in
                            Text(muscle)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(TFColor.accent.opacity(0.15))
                                .foregroundStyle(TFColor.accent)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.trailing, 4)
                }
                .scrollClipDisabled()
            }

        }
        .dashCard()
        .onLongPressGesture(minimumDuration: 1.2) {
            openGeneratorLab()
        }
    }

    /// Validator findings, translated for the person training.
    ///
    /// This used to render the raw validator strings, which are written as instructions to the
    /// model ("Trim redundant filler instead of stacking volume", "BASE-001 requires…"). That
    /// put generator diagnostics in a product surface and asked the owner to act on sentences
    /// addressed to Claude. The raw text still drives retry policy and the correction prompt —
    /// only the presentation changes here. See `WorkoutValidatorNotice`.
    @ViewBuilder
    func validatorWarningsBanner(_ program: WorkoutProgram) -> some View {
        let notices = WorkoutValidatorNotice.notices(fromWarningsText: program.validatorWarnings)
        if !notices.isEmpty {
            let severity = WorkoutValidatorNotice.summarySeverity(for: notices)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: TFSpacing.innerGap) {
                    ForEach(notices) { notice in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: noticeIcon(notice.severity))
                                    .font(.caption2)
                                    .foregroundStyle(noticeTint(notice.severity))
                                Text(notice.displayHeadline)
                                    .font(.caption.bold())
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(notice.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(noticeAccessibilityPrefix(notice.severity)). \(notice.displayHeadline). \(notice.detail)")
                    }

                    Text("Full technical detail is in the Generator Lab.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, TFSpacing.tightGap)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: noticeIcon(severity))
                        .font(.caption2)
                        .foregroundStyle(noticeTint(severity))
                    Text(noticeSummaryLabel(severity, count: notices.count))
                        .font(.caption.bold())
                        .foregroundStyle(noticeTint(severity))
                }
            }
            .padding(10)
            .background(noticeTint(severity).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        }
    }

    func noticeIcon(_ severity: WorkoutValidatorNotice.Severity) -> String {
        switch severity {
        case .tuning: return "slider.horizontal.3"
        case .headsUp: return "exclamationmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        }
    }

    func noticeTint(_ severity: WorkoutValidatorNotice.Severity) -> Color {
        switch severity {
        case .tuning: return TFColor.info
        case .headsUp: return TFColor.warning
        case .attention: return TFColor.danger
        }
    }

    func noticeSummaryLabel(_ severity: WorkoutValidatorNotice.Severity, count: Int) -> String {
        let noun = count == 1 ? "note" : "notes"
        switch severity {
        case .tuning: return "\(count) plan \(noun)"
        case .headsUp: return "\(count) thing\(count == 1 ? "" : "s") worth knowing"
        case .attention: return count == 1 ? "1 note needs a look" : "\(count) notes, one needs a look"
        }
    }

    func noticeAccessibilityPrefix(_ severity: WorkoutValidatorNotice.Severity) -> String {
        switch severity {
        case .tuning: return "Plan note"
        case .headsUp: return "Worth knowing"
        case .attention: return "Needs a look"
        }
    }

    // MARK: - Week Selector

    func weekSelector(_ program: WorkoutProgram) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...program.currentWeek, id: \.self) { week in
                    let weekDays = program.sortedDays.filter { $0.weekNumber == week }
                    let completed = weekDays.filter { $0.isCompleted }.count
                    let total = weekDays.count

                    Button {
                        selectedWeek = week
                    } label: {
                        VStack(spacing: 4) {
                            Text("Week \(week)")
                                .font(.caption.bold())
                            Text("\(completed)/\(total)")
                                .font(.caption2)
                                .foregroundStyle(selectedWeek == week ? .white.opacity(0.7) : .secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(selectedWeek == week ? TFColor.accent : TFColor.surface)
                        .foregroundStyle(selectedWeek == week ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // Locked future weeks
                if program.currentWeek < program.maxWeeks {
                    ForEach((program.currentWeek + 1)...program.maxWeeks, id: \.self) { week in
                        VStack(spacing: 4) {
                            Text("Week \(week)")
                                .font(.caption.bold())
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(TFColor.surfaceElevated)
                        .foregroundStyle(.tertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    // MARK: - Week Days List

    func weekDaysList(_ program: WorkoutProgram) -> some View {
        let weekDays = program.sortedDays.filter { $0.weekNumber == selectedWeek }

        return VStack(spacing: 10) {
            ForEach(weekDays) { day in
                if day.isRestDay {
                    NavigationLink(destination: RestDayDetailView(day: day)) {
                        RestDayCard(day: day, onToggle: { toggleDayCompletion(day) })
                    }
                } else {
                    NavigationLink(destination: WorkoutDayDetailView(day: day)) {
                        TrainingDayCard(day: day, onToggle: { toggleDayCompletion(day) })
                    }
                }
            }
        }
    }

    // MARK: - Generate Next Week Button

    func generateNextWeekButton(_ program: WorkoutProgram) -> some View {
        let nextWeek = program.currentWeek + 1
        let phaseLabel: String = {
            switch nextWeek {
            case 2: return "Volume Building"
            case 3: return "Peak Volume"
            case 4: return "Deload / Intensity Peak"
            default: return "Week \(nextWeek)"
            }
        }()

        return VStack(spacing: 8) {
            Button {
                startNextWeekGeneration(for: program)
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 4)
                        Text("Generating Week \(nextWeek)...")
                    } else {
                        Image(systemName: "sparkles")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Generate Week \(nextWeek)")
                                .font(.subheadline.bold())
                            Text(phaseLabel)
                                .font(.caption)
                                .opacity(0.8)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .opacity(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isGenerating ? TFColor.accent.opacity(0.6) : TFColor.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
            }
            .pressable()
            .disabled(isGenerating || !canUseAI)
        }
    }

    // MARK: - Progress Summary

    func progressSummary(_ program: WorkoutProgram) -> some View {
        let completedDays = program.days.filter { $0.isCompleted }.count
        let overallProgress = Double(completedDays) / Double(program.maxWeeks * 7)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                TFSectionLabel(text: "Program Progress")
                Spacer()
                Text("\(completedDays) of \(program.maxWeeks * 7) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(TFColor.accent.opacity(0.15))
                        .frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [TFColor.accent, TFColor.accentWarm],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * overallProgress, height: 8)
                        .animation(.easeOut(duration: 0.6), value: overallProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Int(overallProgress * 100))% complete")
                    .font(.caption.bold())
                    .foregroundStyle(TFColor.accent)
                Spacer()
                Text("Week \(program.currentWeek)/\(program.maxWeeks) generated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .dashCard()
    }

    // MARK: - Danger Zone

    func dangerZone(_ program: WorkoutProgram) -> some View {
        VStack(spacing: 12) {
            if latestAnalysis?.decodedResult != nil {
                Button {
                    showStartOverConfirm = true
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView().tint(TFColor.accent).scaleEffect(0.8)
                        }
                        Image(systemName: "arrow.clockwise")
                        Text(isGenerating ? "Regenerating..." : "Start Over (New Week 1)")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(TFColor.surface)
                    .foregroundStyle(TFColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
                }
                .pressable()
                .disabled(isGenerating || !canUseAI)
            }

            Button {
                programToDelete = program
                showDeleteConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Program")
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(TFColor.danger.opacity(0.1))
                .foregroundStyle(TFColor.danger)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
            }
            .pressable()
            .disabled(isGenerating)
        }
    }

    // MARK: - Logic: Generate Week 1

    @MainActor
    func startFirstWeekGeneration(from result: BodyAnalysisResult, sourceAnalysisDate: Date?) {
        guard !isGenerating else { return }
        isGenerating = true
        generationTask?.cancel()
        generationTask = Task {
            await generateFirstWeek(from: result, sourceAnalysisDate: sourceAnalysisDate)
        }
    }

    @MainActor
    func startNextWeekGeneration(for program: WorkoutProgram) {
        guard !isGenerating else { return }
        isGenerating = true
        generationTask?.cancel()
        generationTask = Task {
            await generateNextWeek(for: program)
        }
    }

    @MainActor
    func startRegeneration(from result: BodyAnalysisResult, sourceAnalysisDate: Date?) {
        guard !isGenerating else { return }
        isGenerating = true
        generationTask?.cancel()
        generationTask = Task {
            await regenerateProgram(from: result, sourceAnalysisDate: sourceAnalysisDate)
        }
    }

    @MainActor
    func generateFirstWeek(from result: BodyAnalysisResult, sourceAnalysisDate: Date?) async {
        isGenerating = true
        guard !Task.isCancelled else {
            isGenerating = false
            generationTask = nil
            return
        }
        WorkoutGenerationDiagnostics.start(feature: "Week 1 workout generation")
        defer {
            WorkoutGenerationDiagnostics.finish()
            isGenerating = false
            generationTask = nil
        }
        // Re-derive the structured sleep-recovery state at the moment of generation
        // so the tier decision never rides a window cached up to 3 days earlier.
        SleepTrendStore.refresh(using: modelContext)

        do {
            // Derived once and shared: the prompt history and the validator's structured
            // verdicts read the same decision for the same entry, so building it twice was
            // both wasted work and a chance for the two halves to disagree.
            let progressionLookup = makeProgressionLookup(performanceLogs: exercisePerformanceLogs)
            let performanceHistory = compactPerformanceHistory(from: exerciseWeightEntries, lookup: progressionLookup)
            let history = exerciseHistoryContext(from: programs)
            // `programs` includes archived mesocycles, so skip/pain patterns persist
            // across program boundaries.
            let generationResult = try await ClaudeService.shared.generateWeekOne(
                from: result,
                performanceHistory: performanceHistory,
                skipHistory: recurringSkipHistory(across: programs),
                exerciseHistory: history,
                progressionVerdicts: progressionVerdictContexts(from: exerciseWeightEntries, lookup: progressionLookup)
            )
            let response = generationResult.response
            try Task.checkCancellation()
            WorkoutGenerationDiagnostics.markStage("encoding generated week 1 program")

            guard
                let analysisJSONString = encodeJSONString(
                    result,
                    failureMessage: "Could not save the generated program because the analysis context could not be encoded."
                ),
                let weekJSON = encodeJSONString(
                    response,
                    failureMessage: "Could not save the generated program because the generated workout data could not be encoded."
                )
            else {
                return
            }

            guard !Task.isCancelled else { return }
            WorkoutGenerationDiagnostics.markStage("archiving prior programs")

            for program in programs where !program.isArchived {
                if program.hasCompletedExercises {
                    program.isArchived = true
                } else {
                    modelContext.delete(program)
                }
            }

            let warningsText = generationResult.validatorWarnings.joined(separator: "\n")
            let program = WorkoutProgram(
                programName: response.programName,
                programSummary: response.programSummary,
                splitType: response.splitType,
                daysPerWeek: response.daysPerWeek,
                totalDays: response.days.count,
                focusAreas: result.programmingPrioritySummary,
                sourceAnalysisDate: sourceAnalysisDate,
                programJSON: weekJSON,
                currentWeek: 1,
                maxWeeks: 4,
                analysisJSON: analysisJSONString,
                validatorWarnings: warningsText,
                lastGenerationBundle: generationResult.bundleText
            )
            modelContext.insert(program)
            program.setWeekSummary(response.programSummary, for: 1)

            insertDays(from: response.days, into: program)
            WorkoutGenerationDiagnostics.markStage("saving generated week 1 program to storage")

            guard PersistenceReporter.save(modelContext, operation: "generated week 1 workout program") else {
                modelContext.rollback()
                errorMessage = "Could not save the generated program. Please try again."
                showError = true
                TFHaptics.error()
                return
            }
            DataBackupManager.shared.scheduleAutomaticBackup(using: modelContext)
            WorkoutGenerationDiagnostics.markStage("finalizing generated week 1 program")
            selectedWeek = 1
            TFHaptics.success()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            showError = true
            TFHaptics.error()
        }
    }

    // MARK: - Logic: Generate Next Week

    @MainActor
    func generateNextWeek(for program: WorkoutProgram) async {
        isGenerating = true
        guard !Task.isCancelled else {
            isGenerating = false
            generationTask = nil
            return
        }
        let nextWeek = program.currentWeek + 1
        WorkoutGenerationDiagnostics.start(feature: "Week \(nextWeek) workout generation")
        defer {
            WorkoutGenerationDiagnostics.finish()
            isGenerating = false
            generationTask = nil
        }
        // Same generation-time re-derivation as week 1: the recovery tier must
        // reflect sleep as of now, not a cached window.
        SleepTrendStore.refresh(using: modelContext)

        do {
            WorkoutGenerationDiagnostics.markStage("requesting week \(nextWeek) program from AI")
            let progressionLookup = makeProgressionLookup(performanceLogs: exercisePerformanceLogs)
            let performanceHistory = compactPerformanceHistory(from: exerciseWeightEntries, lookup: progressionLookup)
            let history = exerciseHistoryContext(from: programs)
            let generationResult = try await ClaudeService.shared.generateNextWeek(
                weekNumber: nextWeek,
                previousWeekJSON: program.programJSON,
                analysisJSON: program.analysisJSON,
                splitType: program.splitType,
                programName: program.programName,
                performanceHistory: performanceHistory,
                sessionFeedbackSummary: sessionFeedbackSummary(
                    for: program,
                    weekNumber: program.currentWeek
                ),
                skipHistory: recurringSkipHistory(across: programs),
                exerciseHistory: history,
                progressionVerdicts: progressionVerdictContexts(from: exerciseWeightEntries, lookup: progressionLookup)
            )
            let response = generationResult.response
            try Task.checkCancellation()
            // The program may have been deleted while the request was in flight.
            guard program.modelContext != nil else { return }
            WorkoutGenerationDiagnostics.markStage("encoding generated week \(nextWeek) program")

            guard let weekJSON = encodeJSONString(
                response,
                failureMessage: "Could not save the generated week because the new workout data could not be encoded."
            ) else {
                return
            }

            let priorCurrentWeek = program.currentWeek
            let priorTotalDays = program.totalDays
            let priorSummary = program.programSummary
            let priorProgramJSON = program.programJSON
            let priorWarnings = program.validatorWarnings
            let priorWeekSummaries = program.weekSummariesJSON

            WorkoutGenerationDiagnostics.markStage("inserting generated week \(nextWeek) program")
            insertDays(from: response.days, into: program)

            program.currentWeek = nextWeek
            program.totalDays = program.days.count
            program.programJSON = weekJSON
            program.validatorWarnings = generationResult.validatorWarnings.joined(separator: "\n")
            program.lastGenerationBundle = generationResult.bundleText
            let weekSummaryText = response.weekSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !weekSummaryText.isEmpty {
                program.setWeekSummary(weekSummaryText, for: nextWeek)
            }

            WorkoutGenerationDiagnostics.markStage("saving generated week \(nextWeek) program to storage")
            guard PersistenceReporter.save(modelContext, operation: "generated next workout week") else {
                modelContext.rollback()
                program.currentWeek = priorCurrentWeek
                program.totalDays = priorTotalDays
                program.programSummary = priorSummary
                program.programJSON = priorProgramJSON
                program.validatorWarnings = priorWarnings
                program.weekSummariesJSON = priorWeekSummaries
                errorMessage = "Could not save the generated week. Please try again."
                showError = true
                TFHaptics.error()
                return
            }
            DataBackupManager.shared.scheduleAutomaticBackup(using: modelContext)
            WorkoutGenerationDiagnostics.markStage("finalizing generated week \(nextWeek) program")
            selectedWeek = nextWeek
            TFHaptics.success()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            showError = true
            TFHaptics.error()
        }
    }

    // MARK: - Logic: Regenerate (Start Over)

    @MainActor
    func regenerateProgram(from result: BodyAnalysisResult, sourceAnalysisDate: Date?) async {
        await generateFirstWeek(from: result, sourceAnalysisDate: sourceAnalysisDate)
    }

    // MARK: - Helpers

    func insertDays(from dayResponses: [WorkoutDayResponse], into program: WorkoutProgram) {
        for dayResponse in dayResponses {
            let day = WorkoutDay(
                dayNumber: dayResponse.dayNumber,
                dayName: dayResponse.dayName,
                muscleGroups: dayResponse.muscleGroups,
                isRestDay: dayResponse.isRestDay,
                notes: dayResponse.notes
            )
            day.program = program
            modelContext.insert(day)

            for (index, exerciseResponse) in dayResponse.exercises.enumerated() {
                let exercise = WorkoutExercise(
                    order: index,
                    exerciseName: exerciseResponse.exerciseName,
                    sets: exerciseResponse.sets,
                    reps: exerciseResponse.reps,
                    tempo: exerciseResponse.tempo,
                    restSeconds: exerciseResponse.restSeconds,
                    notes: exerciseResponse.notes,
                    muscleTarget: exerciseResponse.muscleTarget,
                    targetRIR: exerciseResponse.targetRIR,
                    coachingSource: exerciseResponse.coachingSource
                )
                exercise.day = day
                modelContext.insert(exercise)
            }
        }
    }

    func toggleDayCompletion(_ day: WorkoutDay) {
        let priorDayCompletion = day.isCompleted
        let priorExerciseCompletion = day.exercises.map { ($0, $0.isCompleted) }
        let priorEnd = day.sessionEndedAt
        let priorClosed = day.isSessionClosed

        day.isCompleted.toggle()
        // Keep exercise checks consistent with the day: completing checks all,
        // un-completing clears them (otherwise a single re-toggle instantly
        // re-completes the day).
        for exercise in day.exercises {
            exercise.isCompleted = day.isCompleted
        }
        // Ticking the day off from the week list is a finish tap like any other, so it
        // closes the session clock; un-ticking re-opens it for continued tracking.
        if day.isCompleted {
            if !day.isRestDay { SessionLifecycle.markSessionEnded(for: day) }
        } else {
            day.isSessionClosed = false
        }
        guard PersistenceReporter.save(modelContext, operation: "day completion toggle") else {
            modelContext.rollback()
            day.isCompleted = priorDayCompletion
            for (exercise, priorValue) in priorExerciseCompletion {
                exercise.isCompleted = priorValue
            }
            day.sessionEndedAt = priorEnd
            day.isSessionClosed = priorClosed
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.writeAutomaticBackupCoalesced(using: modelContext)
        TFHaptics.impact(.light)
        if day.isCompleted && !day.isRestDay {
            feedbackDay = day
        }
    }

    func sessionFeedbackSummary(for program: WorkoutProgram, weekNumber: Int) -> String? {
        // Include any non-rest day that EITHER has an explicit session rating OR has
        // exercises the user skipped / substituted / modified. Previously this required the
        // separate feedback sheet to be submitted, so skip selections silently never reached
        // the generator unless the user also rated the session. Skip data now flows on its own.
        func dayHasSkips(_ day: WorkoutDay) -> Bool {
            day.sortedExercises.contains { exercise in
                guard let status = exercise.completionStatus else { return false }
                return status != .completed
            }
        }

        let relevant = program.sortedDays.filter { day in
            guard day.weekNumber == weekNumber, !day.isRestDay else { return false }
            return day.hasSessionFeedback || dayHasSkips(day)
        }
        guard !relevant.isEmpty else { return nil }

        let feedbackLines = relevant.map { day in
            let skippedExercises = day.sortedExercises.filter { exercise in
                guard let status = exercise.completionStatus else { return false }
                return status != .completed
            }
            let skipSuffix: String
            if skippedExercises.isEmpty {
                skipSuffix = ""
            } else {
                let skipLines = skippedExercises.map { ex in
                    "\(ex.exerciseName) (\(ex.completionStatus?.shortLabel ?? "skipped"))"
                }.joined(separator: ", ")
                skipSuffix = " Skipped/modified: \(skipLines)."
            }

            var timingSuffix = ""
            if let start = day.sessionStartedAt, let end = day.sessionEndedAt {
                let hour = Calendar.current.component(.hour, from: start)
                let durationMin = Int(end.timeIntervalSince(start) / 60)
                if durationMin > 0 {
                    timingSuffix = " Session \(durationMin) min starting ~\(hour):00."
                }
            }

            let dayHeader = "Day \(day.dayNumber) \(day.dayName) [\(day.muscleGroups)]"

            // Without a submitted rating, the effort/stimulus/joint-pain/performance fields are
            // just zeroed defaults — reporting them as real ratings would mislead the model.
            guard day.hasSessionFeedback else {
                return "\(dayHeader): no session rating submitted.\(skipSuffix)\(timingSuffix)"
            }

            let performance = day.performanceRating?.rawValue ?? "Not rated"
            let note = day.sessionFeedbackNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let noteSuffix = note.isEmpty ? "" : " Note: \(String(note.prefix(160)))"
            return "\(dayHeader): effort \(day.sessionEffort)/5, stimulus \(day.stimulusQuality)/5, joint pain \(day.jointPain)/5, performance \(performance).\(noteSuffix)\(skipSuffix)\(timingSuffix)"
        }
        let feedbackSnapshots = relevant.compactMap { day -> WorkoutSessionFeedbackSnapshot? in
            guard day.hasSessionFeedback else { return nil }
            return WorkoutSessionFeedbackSnapshot(
                effort: day.sessionEffort,
                stimulus: day.stimulusQuality,
                jointPain: day.jointPain,
                performanceRawValue: day.performanceRating?.rawValue ?? ""
            )
        }
        guard !feedbackSnapshots.isEmpty else {
            return feedbackLines.joined(separator: "\n")
        }

        let governance = WorkoutEffortGovernance.guidance(
            for: WorkoutEffortGovernance.signal(from: feedbackSnapshots)
        )
        return (feedbackLines + [governance]).joined(separator: "\n")
    }

    /// Aggregates recurring skip / substitution / modification patterns across the supplied
    /// programs so persistent adherence signals — especially pain — survive across weeks AND
    /// across mesocycle boundaries, rather than being reset every program. Returns nil when
    /// there is nothing worth flagging.
    func recurringSkipHistory(across programs: [WorkoutProgram]) -> String? {
        var byExercise: [String: [ExerciseCompletionStatus: Int]] = [:]
        for program in programs {
            for day in program.sortedDays where !day.isRestDay {
                for exercise in day.sortedExercises {
                    guard let status = exercise.completionStatus, status != .completed else { continue }
                    let name = exercise.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    byExercise[name, default: [:]][status, default: 0] += 1
                }
            }
        }
        guard !byExercise.isEmpty else { return nil }

        struct Entry {
            let name: String
            let counts: [ExerciseCompletionStatus: Int]
            var total: Int { counts.values.reduce(0, +) }
            var painCount: Int { counts[.skippedPain] ?? 0 }
            // Surface a movement if the issue recurs, or if it ever caused pain (a safety signal
            // worth acting on even once).
            var isSignificant: Bool { total >= 2 || painCount >= 1 }
        }

        let reasonOrder: [ExerciseCompletionStatus] = [
            .skippedPain, .skippedEquipment, .skippedTime, .substituted, .completedModified
        ]

        let entries = byExercise
            .map { Entry(name: $0.key, counts: $0.value) }
            .filter { $0.isSignificant }
            .sorted { lhs, rhs in
                if lhs.painCount != rhs.painCount { return lhs.painCount > rhs.painCount }
                if lhs.total != rhs.total { return lhs.total > rhs.total }
                return lhs.name < rhs.name
            }
            .prefix(8) // cap prompt size / API cost; worst offenders come first

        guard !entries.isEmpty else { return nil }

        let lines = entries.map { entry -> String in
            let reasonParts = reasonOrder.compactMap { status -> String? in
                guard let count = entry.counts[status], count > 0 else { return nil }
                return "\(status.historyReason) \(count)x"
            }
            return "\(entry.name): \(reasonParts.joined(separator: ", "))"
        }
        return lines.joined(separator: "\n")
    }

    func exerciseHistoryContext(from programs: [WorkoutProgram]) -> ClaudeService.ExerciseHistoryContext {
        var painExercises = Set<String>()
        var equipmentSkipExercises = Set<String>()
        var priorMesocycleExercises = Set<String>()

        var painCounts: [String: Int] = [:]
        var equipmentCounts: [String: Int] = [:]

        for program in programs {
            let isArchived = program.isArchived
            for day in program.sortedDays where !day.isRestDay {
                for exercise in day.sortedExercises {
                    let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                    guard !key.isEmpty else { continue }

                    if isArchived {
                        priorMesocycleExercises.insert(key)
                    }

                    guard let status = exercise.completionStatus, status != .completed else { continue }
                    switch status {
                    case .skippedPain:
                        painCounts[key, default: 0] += 1
                    case .skippedEquipment:
                        equipmentCounts[key, default: 0] += 1
                    default:
                        break
                    }
                }
            }
        }

        for (key, count) in painCounts where count >= 1 {
            painExercises.insert(key)
        }
        for (key, count) in equipmentCounts where count >= 2 {
            equipmentSkipExercises.insert(key)
        }

        let activeCount = programs.filter { !$0.isArchived }.count
        let archivedCount = programs.filter { $0.isArchived }.count
        let mesocycleIndex = activeCount > 0 ? archivedCount : max(0, archivedCount - 1)

        return ClaudeService.ExerciseHistoryContext(
            painExercises: painExercises,
            equipmentSkipExercises: equipmentSkipExercises,
            priorMesocycleExercises: priorMesocycleExercises,
            mesocycleIndex: mesocycleIndex
        )
    }

    func deleteProgram(_ program: WorkoutProgram) {
        modelContext.delete(program)
        guard PersistenceReporter.save(modelContext, operation: "workout program deletion") else {
            modelContext.rollback()
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        selectedWeek = 1
        programToDelete = nil
        TFHaptics.impact(.medium)
    }

    func openGeneratorLab() {
        TFHaptics.impact(.soft)
        showGeneratorLab = true
    }

    func generationSourceBadge(for summary: String) -> (label: String, foreground: Color, background: Color)? {
        switch GeneratedContentSource.detect(in: summary) {
        case .aiCoach:
            return (GeneratedContentSource.aiCoach.label, .green, TFColor.success.opacity(0.15))
        case .recoveryEngine:
            return (GeneratedContentSource.recoveryEngine.label, .orange, TFColor.accent.opacity(0.15))
        case nil:
            return nil
        }
    }

    func summaryWithoutSourcePrefix(_ summary: String) -> String {
        GeneratedContentSource.strip(from: summary)
    }

    func programHeaderBadge(_ title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    func programHeaderMetaLabel(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// The stored summary the header is describing, WITH its source label intact.
    ///
    /// The badge and the summary text sit next to each other and must describe the same thing.
    /// They did not: the text was per-week while the badge read `programSummary`, which is
    /// written once when week 1 is created and never updated afterwards. So a week whose AI
    /// call failed and fell back to the training engine still wore a green "AI Coach" badge —
    /// and the per-week summary that would have said otherwise had its label stripped before
    /// display. Every honest signal was destroyed at the presentation boundary, on a screen
    /// where the exercise cards underneath simultaneously said "Built by the training engine".
    func sourceSummaryForSelectedWeek(_ program: WorkoutProgram) -> String {
        if let perWeek = program.weekSummary(for: selectedWeek), !perWeek.isEmpty {
            return perWeek
        }
        return program.programSummary
    }

    func summaryForSelectedWeek(_ program: WorkoutProgram) -> String {
        summaryWithoutSourcePrefix(sourceSummaryForSelectedWeek(program))
    }

    func syncSelectedWeekWithCurrentProgram() {
        guard let program = currentProgram else {
            selectedWeek = 1
            lastSyncedProgramID = nil
            return
        }

        let maxAvailableWeek = max(1, program.currentWeek)
        // Jump to the current week only when the program itself changed (first appear,
        // regeneration, deletion). onAppear also fires when popping back from a day
        // detail view — there, just clamp so the user's selected week isn't stomped.
        if lastSyncedProgramID != program.id {
            lastSyncedProgramID = program.id
            selectedWeek = maxAvailableWeek
            return
        }
        selectedWeek = min(max(1, selectedWeek), maxAvailableWeek)
    }

    /// Most recent logged entry per canonical exercise key — the shared source for both
    /// the prompt's history lines and the structured verdicts handed to the validator,
    /// so the two can never disagree about which entry represents an exercise.
    func recentPerformanceEntries(from entries: [ExerciseWeightEntry], limit: Int = 10) -> [ExerciseWeightEntry] {
        var seen = Set<String>()
        var recent: [ExerciseWeightEntry] = []
        for entry in entries where entry.weightLbs > 0 {
            if seen.insert(entry.canonicalExerciseKey).inserted {
                recent.append(entry)
                if recent.count >= limit { break }
            }
        }
        return recent
    }

    /// Everything the deterministic verdict engine needs, derived ONCE per generation.
    ///
    /// Both inputs used to be rebuilt per logged exercise: `decodedSetLogs` runs a full
    /// `JSONDecoder` pass on every access, and `prescribedRepRange` re-walked every program,
    /// day and exercise (recomputing canonical keys) for every lookup. Because
    /// `compactPerformanceHistory` also called `progressionVerdict`, which independently
    /// recomputed the same decision, tapping Generate did on the order of thirty full passes
    /// over the entire training history — synchronously, on the main actor, before the request
    /// was even sent. The cost grew with every workout the owner logged, which is exactly the
    /// kind of hitch that only shows up months in.
    struct ProgressionLookup {
        let snapshots: [WorkoutPerformanceLogSnapshot]
        let repRangesByKey: [String: RepRange]
        /// Set count the graded session actually ran, so a load consequence is quoted for the
        /// right amount of work. Resolved from the same session the rep range came from.
        let prescribedSetsByKey: [String: Int]
    }

    func makeProgressionLookup(performanceLogs: [ExercisePerformanceLog]) -> ProgressionLookup {
        let snapshots = performanceLogs.map {
            WorkoutPerformanceLogSnapshot(
                canonicalExerciseKey: $0.canonicalExerciseKey,
                loggedAt: $0.loggedAt,
                setLogs: $0.decodedSetLogs,
                prescribedReps: $0.prescribedReps,
                prescribedSets: $0.prescribedSets
            )
        }

        // Same traversal and same first-match-wins semantics the per-key scan had: `programs`
        // is newest-first and includes archived mesocycles, so the winning range is the one the
        // most recent program that ran the exercise prescribed. Unparseable reps are skipped
        // rather than claimed, exactly as before.
        var repRangesByKey: [String: RepRange] = [:]

        // What each exercise was ACTUALLY prescribed on the session being graded wins over
        // the program scan below. The scan answers "what does the newest program that ran
        // this lift ask for today", which is the wrong question about work already done:
        // moving a lift from 12-15 to 15-20 re-scored every past 14-rep set as a failure.
        //
        // Only the newest session with sets gets a vote, and it is decided either way. A
        // session that recorded no prescription must fall through to the program scan
        // rather than let an OLDER session's range stand in for it — borrowing a range from
        // a session nobody is grading is the same error in a different direction.
        var prescribedSetsByKey: [String: Int] = [:]
        var decidedFromLogs: Set<String> = []
        for snapshot in snapshots.sorted(by: { $0.loggedAt > $1.loggedAt }) {
            let key = snapshot.canonicalExerciseKey
            guard !decidedFromLogs.contains(key), !snapshot.setLogs.isEmpty else { continue }
            decidedFromLogs.insert(key)
            if let range = RepRange.parse(snapshot.prescribedReps) {
                repRangesByKey[key] = range
            }
            if snapshot.prescribedSets > 0 {
                prescribedSetsByKey[key] = snapshot.prescribedSets
            }
        }

        for program in programs {
            for day in program.sortedDays {
                for exercise in day.sortedExercises {
                    let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                    guard repRangesByKey[key] == nil,
                          let range = RepRange.parse(exercise.reps) else { continue }
                    repRangesByKey[key] = range
                }
            }
        }

        return ProgressionLookup(
            snapshots: snapshots,
            repRangesByKey: repRangesByKey,
            prescribedSetsByKey: prescribedSetsByKey
        )
    }

    func compactPerformanceHistory(
        from entries: [ExerciseWeightEntry],
        lookup: ProgressionLookup,
        limit: Int = 10
    ) -> String? {
        let recent = recentPerformanceEntries(from: entries, limit: limit)
        guard !recent.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return recent.map { entry in
            let decision = progressionDecision(for: entry, lookup: lookup)
            let weight = decision?.workingWeight ?? entry.weightLbs
            let reps = decision?.minimumWorkingReps ?? entry.repsCompleted
            var line = "- \(entry.exerciseName): \(Int(weight)) lb"
            if let reps { line += " x \(reps)" }
            line += " (\(formatter.string(from: entry.loggedAt)))"
            if let verdict = progressionVerdict(for: entry, decision: decision, lookup: lookup) {
                line += " — app verdict: \(verdict)"
            }
            if let consequences = loadConsequenceLine(for: entry, lookup: lookup) {
                line += "\n    \(consequences)"
            }
            return line
        }.joined(separator: "\n")
    }

    /// What the working load BECOMES for each rep range the model might choose.
    ///
    /// This is the whole point of the load-translation work: the model programs reps and sets
    /// but has never watched this lifter train, so it cannot know what a rep range costs in
    /// weight. Left to guess it produced the failure this exists to stop — prescribing a jump
    /// to 3x15-20 in the same week the engine said ADD LOAD, when the honest answer was less
    /// weight, not more.
    ///
    /// Giving the model these numbers is not a restriction on its programming; it is the one
    /// fact it structurally cannot derive. It chooses the prescription, then the app applies
    /// the matching load automatically whether the model reads this line or not — so a model
    /// that ignores it still cannot hurt the lifter. The line exists so the choice is INFORMED.
    ///
    /// Reserve is assumed to be 1 rep because the prescribed RIR of a past session is not yet
    /// recorded. That assumption is stated here rather than hidden: it biases every estimate
    /// slightly light, which is the safe direction, and it is the next thing worth storing.
    func loadConsequenceLine(for entry: ExerciseWeightEntry, lookup: ProgressionLookup) -> String? {
        let key = entry.canonicalExerciseKey
        let logs = WorkoutProgressionEngine.latestUsableSetLogs(for: key, from: lookup.snapshots)
        let analysis = WorkingSetAnalysis.analyze(logs)
        // Freshest capacity, not the lowest set: the model needs what this lifter can do on set
        // one, because that is what the translation converts. Feeding it a fatigued last set
        // would understate the yardstick on every exercise.
        guard let working = analysis.workingSets.max(by: { $0.reps < $1.reps }),
              let referenceLoad = analysis.workingWeight, referenceLoad > 0
        else { return nil }

        let sets = max(1, lookup.prescribedSetsByKey[key] ?? analysis.workingSets.count)
        let decay = WorkoutLoadTranslation.estimatedFatigueDecayPerSet(for: key, from: lookup.snapshots)
        let increment = WorkoutProgressionEngine.incrementLbs(forExerciseName: entry.exerciseName)
        let reference = WorkoutLoadTranslation.Reference(
            loadLbs: referenceLoad,
            repsAchieved: working.reps,
            reserveReps: working.rir ?? 1,
            hitPrescribedCeiling: lookup.repRangesByKey[key].map { working.reps >= $0.high } ?? false
        )

        let options: [(label: String, floor: Int)] = [("6-10", 6), ("10-14", 10), ("15-20", 15)]
        let rendered: [String] = options.compactMap { option in
            guard let outcome = WorkoutLoadTranslation.translate(
                reference: reference,
                target: .init(sets: sets, repFloor: option.floor, targetRIR: 1),
                fatigueDecayPerSet: decay,
                incrementLbs: increment
            ) else { return nil }
            return "\(option.label) reps -> \(formatWeight(outcome.recommendedLoadLbs)) lb"
        }
        guard !rendered.isEmpty else { return nil }

        return "at \(sets) set\(sets == 1 ? "" : "s") the app will set the load to: "
            + rendered.joined(separator: " | ")
            + " (more reps or more sets = less weight; the app applies this automatically)"
    }

    /// Structured verdicts for the validator's cue-vs-history rule — the enforcement half
    /// of the prompt-side verdict injection above (98349db). Built from the same entries
    /// and the same verdict logic that feed the prompt.
    func progressionVerdictContexts(
        from entries: [ExerciseWeightEntry],
        lookup: ProgressionLookup,
        limit: Int = 10
    ) -> [ClaudeService.ExerciseProgressionVerdict] {
        recentPerformanceEntries(from: entries, limit: limit).compactMap { entry in
            guard let decision = progressionDecision(for: entry, lookup: lookup) else { return nil }
            return ClaudeService.ExerciseProgressionVerdict(
                canonicalKey: entry.canonicalExerciseKey,
                exerciseName: entry.exerciseName,
                kind: decision.kind,
                weightLbs: decision.workingWeight,
                previousRepRange: lookup.repRangesByKey[entry.canonicalExerciseKey]
            )
        }
    }

    /// Deterministic next-step verdict for one logged exercise, mirroring the
    /// `ProgressionSuggestion` engine the workout screen shows the user. Injected into
    /// the generation prompt so the AI's written progression cue cannot contradict the
    /// live banner rendered next to it (seen live: coaching said "hold 70 lb in the
    /// 10-12 range" while the banner correctly said "add load" after 3x14). Uses the
    /// the latest usable per-set log when one exists, falling back to the summary reps for
    /// legacy records, and the rep range prescribed by the most recent program that ran
    /// the exercise.
    /// `decision` is passed in rather than recomputed: the caller already derived it for the
    /// same entry, and re-deriving it was half of the duplicated work described on
    /// `ProgressionLookup`.
    func progressionVerdict(
        for entry: ExerciseWeightEntry,
        decision: WorkoutProgressionDecision?,
        lookup: ProgressionLookup
    ) -> String? {
        guard let decision,
              let range = lookup.repRangesByKey[entry.canonicalExerciseKey]
        else { return nil }

        let weight = formatWeight(decision.workingWeight)
        switch decision.kind {
        case .addLoad:
            let next = formatWeight(
                WorkoutProgressionEngine.nextLoad(from: decision.workingWeight, exerciseName: entry.exerciseName)
            )
            return "beat the \(range.low)-\(range.high) rep target at \(weight) lb — cue ADDING LOAD; next achievable step is \(next) lb"
        case .holdBelowRange:
            return "fell below the \(range.low)-\(range.high) rep target — cue HOLDING \(weight) lb and building reps"
        case .reduceLoad:
            let easier = formatWeight(
                WorkoutProgressionEngine.reducedLoad(from: decision.workingWeight, exerciseName: entry.exerciseName)
            )
            return "stalled under the \(range.low)-\(range.high) rep target at \(weight) lb across repeated sessions — cue REDUCING LOAD to \(easier) lb"
        case .holdForRecovery:
            return "repeated low RIR at \(weight) lb — cue HOLDING LOAD to protect recovery before progressing"
        case .addRepsInRange:
            return "inside the \(range.low)-\(range.high) rep target at \(weight) lb — cue ADDING REPS before load"
        }
    }

    /// Single source of truth for the verdict decision so the prompt text above and the
    /// structured validator verdicts cannot drift apart.
    func progressionDecision(
        for entry: ExerciseWeightEntry,
        lookup: ProgressionLookup
    ) -> WorkoutProgressionDecision? {
        let key = entry.canonicalExerciseKey
        guard let range = lookup.repRangesByKey[key] else { return nil }
        let snapshots = lookup.snapshots
        let latestSetLogs = WorkoutProgressionEngine.latestUsableSetLogs(
            for: key,
            from: snapshots
        )
        let effortSignal = WorkoutProgressionEngine.effortSignal(
            for: key,
            from: snapshots
        )
        // Same stall test the card runs, from the same helper, so the prompt the AI is
        // given and the banner the lifter reads cannot disagree about whether a load has
        // stopped working.
        let streak = WorkingSetAnalysis.analyze(latestSetLogs).workingWeight.map {
            WorkoutProgressionEngine.belowFloorStreak(
                for: key,
                from: snapshots,
                workingWeight: $0,
                repFloor: range.low
            )
        } ?? 0
        return WorkoutProgressionEngine.evaluate(
            latestSetLogs: latestSetLogs,
            summaryWeight: entry.weightLbs,
            summaryReps: entry.repsCompleted,
            repRange: range,
            effortSignal: effortSignal,
            belowFloorStreak: streak
        )
    }

    func encodeJSONString<T: Encodable>(_ value: T, failureMessage: String) -> String? {
        do {
            let data = try JSONEncoder().encode(value)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw ClaudeError.parseError("Could not convert encoded workout JSON into UTF-8 text.")
            }
            return encoded
        } catch {
            errorMessage = failureMessage
            showError = true
            print("[WorkoutView] JSON encoding failed: \(error)")
            TFHaptics.error()
            return nil
        }
    }
}
