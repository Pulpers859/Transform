import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutProgram.createdDate, order: .reverse) private var programs: [WorkoutProgram]
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var analysisSessions: [BodyAnalysisSession]

    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDeleteConfirm = false
    @State private var programToDelete: WorkoutProgram?
    @State private var selectedWeek = 1
    @State private var showGeneratorLab = false
    @State private var generationTask: Task<Void, Never>?
    @AppStorage("workout_readiness_mode") private var readinessModeRaw = WorkoutReadinessMode.normal.rawValue

    var currentProgram: WorkoutProgram? { programs.first }
    var latestAnalysis: BodyAnalysisSession? { analysisSessions.first }
    var canUseAI: Bool { Config.hasAnthropicKey }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let program = currentProgram {
                        programHeader(program)
                        weekSelector(program)
                        weekDiffBanner(program)
                        weekDaysList(program)
                        if program.canGenerateNextWeek {
                            readinessModePicker
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
            .sheet(isPresented: $showGeneratorLab) {
                WorkoutGeneratorLabView()
            }
            .onAppear {
                syncSelectedWeekWithCurrentProgram()
            }
            .onChange(of: programs.map(\.id)) { _, _ in
                syncSelectedWeekWithCurrentProgram()
            }
            .onChange(of: currentProgram?.currentWeek) { _, _ in
                syncSelectedWeekWithCurrentProgram()
            }
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 56))
                .foregroundStyle(.orange.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Workout Program")
                    .font(.title2.bold())
                Text("Generate a personalized 4-week program one week at a time, based on your latest body analysis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let analysis = latestAnalysis, let result = analysis.decodedResult {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        if let image = UIImage(data: analysis.photoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Latest Analysis")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
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
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    readinessModePicker
                    generateWeekOneButton(analysis: analysis, result: result)
                    if !canUseAI {
                        Text(Config.anthropicKeyInlineHelpText)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Run a body analysis first to generate a tailored program.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .onLongPressGesture(minimumDuration: 1.2) {
            openGeneratorLab()
        }
    }

    var readinessModePicker: some View {
        let selectedMode = WorkoutReadinessMode(rawValue: readinessModeRaw) ?? .normal
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Readiness", systemImage: "heart.text.clipboard")
                    .font(.subheadline)
                Spacer()
                Picker("Readiness", selection: $readinessModeRaw) {
                    ForEach(WorkoutReadinessMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(.orange)
            }
            if selectedMode != .normal {
                Text(selectedMode.programmingGuidance)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .background(isGenerating ? Color.orange.opacity(0.6) : Color.orange)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .bold()
        }
        .disabled(isGenerating || !canUseAI)
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
                        background: Color.orange.opacity(0.15)
                    )
                    programHeaderBadge(
                        "Week \(program.currentWeek) of \(program.maxWeeks)",
                        foreground: .blue,
                        background: Color.blue.opacity(0.15)
                    )
                    if let sourceBadge = generationSourceBadge(for: program.programSummary) {
                        programHeaderBadge(
                            sourceBadge.label,
                            foreground: sourceBadge.foreground,
                            background: sourceBadge.background
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            Text(summaryWithoutSourcePrefix(program.programSummary))
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
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            validatorWarningsBanner(program)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onLongPressGesture(minimumDuration: 1.2) {
            openGeneratorLab()
        }
    }

    @ViewBuilder
    func validatorWarningsBanner(_ program: WorkoutProgram) -> some View {
        let warnings = program.validatorWarnings
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !warnings.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { index, warning in
                        Text("\(index + 1). \(warning)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("\(warnings.count) validator warning\(warnings.count == 1 ? "" : "s")")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .background(selectedWeek == week ? Color.orange : Color(.secondarySystemBackground))
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
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.tertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    // MARK: - Week Diff Banner

    @ViewBuilder
    func weekDiffBanner(_ program: WorkoutProgram) -> some View {
        if selectedWeek >= 2 {
            let currentWeekDays = program.sortedDays.filter { $0.weekNumber == selectedWeek }
            let previousWeekDays = program.sortedDays.filter { $0.weekNumber == selectedWeek - 1 }

            if !currentWeekDays.isEmpty && !previousWeekDays.isEmpty {
                let currentResponses = currentWeekDays.map { day in
                    WorkoutDayResponse(
                        dayNumber: ((day.dayNumber - 1) % 7) + 1,
                        dayName: day.dayName,
                        muscleGroups: day.muscleGroups,
                        isRestDay: day.isRestDay,
                        notes: day.notes,
                        exercises: day.sortedExercises.map { ex in
                            WorkoutExerciseResponse(
                                exerciseName: ex.exerciseName,
                                sets: ex.sets,
                                reps: ex.reps,
                                tempo: ex.tempo,
                                restSeconds: ex.restSeconds,
                                notes: ex.notes,
                                muscleTarget: ex.muscleTarget
                            )
                        }
                    )
                }
                let previousResponses = previousWeekDays.map { day in
                    WorkoutDayResponse(
                        dayNumber: ((day.dayNumber - 1) % 7) + 1,
                        dayName: day.dayName,
                        muscleGroups: day.muscleGroups,
                        isRestDay: day.isRestDay,
                        notes: day.notes,
                        exercises: day.sortedExercises.map { ex in
                            WorkoutExerciseResponse(
                                exerciseName: ex.exerciseName,
                                sets: ex.sets,
                                reps: ex.reps,
                                tempo: ex.tempo,
                                restSeconds: ex.restSeconds,
                                notes: ex.notes,
                                muscleTarget: ex.muscleTarget
                            )
                        }
                    )
                }

                let diff = ClaudeService.shared.weekDiff(
                    currentDays: currentResponses,
                    previousDays: previousResponses
                )

                if !diff.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(diff) { entry in
                                HStack(spacing: 8) {
                                    diffIcon(entry.kind)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.exerciseName)
                                            .font(.caption.bold())
                                        Text("\(entry.kind.rawValue) — \(entry.detail)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("D\(entry.dayNumber)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                                .foregroundStyle(.cyan)
                            Text("\(diff.count) change\(diff.count == 1 ? "" : "s") from Week \(selectedWeek - 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                        }
                    }
                    .padding(10)
                    .background(Color.cyan.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    func diffIcon(_ kind: ClaudeService.WeekDiffKind) -> some View {
        Group {
            switch kind {
            case .added:
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
            case .removed:
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            case .setsChanged:
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .foregroundStyle(.orange)
            case .repsChanged:
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .foregroundStyle(.purple)
            }
        }
        .font(.caption)
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
                .background(isGenerating ? Color.orange.opacity(0.6) : Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isGenerating || !canUseAI)
        }
    }

    // MARK: - Progress Summary

    func progressSummary(_ program: WorkoutProgram) -> some View {
        let completedDays = program.days.filter { $0.isCompleted }.count
        let overallProgress = Double(completedDays) / Double(program.maxWeeks * 7)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PROGRAM PROGRESS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .tracking(1.5)
                Spacer()
                Text("\(completedDays) of \(program.maxWeeks * 7) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                        .frame(height: 8)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .yellow],
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
                    .foregroundStyle(.orange)
                Spacer()
                Text("Week \(program.currentWeek)/\(program.maxWeeks) generated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Danger Zone

    func dangerZone(_ program: WorkoutProgram) -> some View {
        VStack(spacing: 12) {
            if let result = latestAnalysis?.decodedResult {
                Button {
                    startRegeneration(from: result, sourceAnalysisDate: latestAnalysis?.date)
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView().tint(.orange).scaleEffect(0.8)
                        }
                        Image(systemName: "arrow.clockwise")
                        Text(isGenerating ? "Regenerating..." : "Start Over (New Week 1)")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
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

        do {
            let generationResult = try await ClaudeService.shared.generateWeekOne(from: result)
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
            WorkoutGenerationDiagnostics.markStage("replacing stored week 1 program")

            for program in programs {
                modelContext.delete(program)
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

            insertDays(from: response.days, into: program)
            WorkoutGenerationDiagnostics.markStage("saving generated week 1 program to storage")

            guard PersistenceReporter.save(modelContext, operation: "generated week 1 workout program") else {
                modelContext.rollback()
                errorMessage = "Could not save the generated program. Please try again."
                showError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            // The generated program is already persisted here. Keep the expensive full-export
            // backup off the live AI generation path so a backup write cannot masquerade as a
            // workout-generation crash.
            WorkoutGenerationDiagnostics.markStage("finalizing generated week 1 program")
            selectedWeek = 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            showError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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

        do {
            WorkoutGenerationDiagnostics.markStage("requesting week \(nextWeek) program from AI")
            let generationResult = try await ClaudeService.shared.generateNextWeek(
                weekNumber: nextWeek,
                previousWeekJSON: program.programJSON,
                analysisJSON: program.analysisJSON,
                splitType: program.splitType,
                programName: program.programName
            )
            let response = generationResult.response
            try Task.checkCancellation()
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

            WorkoutGenerationDiagnostics.markStage("inserting generated week \(nextWeek) program")
            insertDays(from: response.days, into: program)

            program.currentWeek = nextWeek
            program.totalDays = program.days.count
            if !response.weekSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                program.programSummary = response.weekSummary
            }
            program.programJSON = weekJSON
            program.validatorWarnings = generationResult.validatorWarnings.joined(separator: "\n")
            program.lastGenerationBundle = generationResult.bundleText

            WorkoutGenerationDiagnostics.markStage("saving generated week \(nextWeek) program to storage")
            guard PersistenceReporter.save(modelContext, operation: "generated next workout week") else {
                modelContext.rollback()
                program.currentWeek = priorCurrentWeek
                program.totalDays = priorTotalDays
                program.programSummary = priorSummary
                program.programJSON = priorProgramJSON
                program.validatorWarnings = priorWarnings
                errorMessage = "Could not save the generated week. Please try again."
                showError = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            WorkoutGenerationDiagnostics.markStage("finalizing generated week \(nextWeek) program")
            selectedWeek = nextWeek
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            showError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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
                    muscleTarget: exerciseResponse.muscleTarget
                )
                exercise.day = day
                modelContext.insert(exercise)
            }
        }
    }

    func toggleDayCompletion(_ day: WorkoutDay) {
        let priorDayCompletion = day.isCompleted
        let priorExerciseCompletion = day.exercises.map(\.isCompleted)

        day.isCompleted.toggle()
        if day.isCompleted {
            for exercise in day.exercises {
                exercise.isCompleted = true
            }
        }
        guard PersistenceReporter.save(modelContext, operation: "day completion toggle") else {
            modelContext.rollback()
            day.isCompleted = priorDayCompletion
            for (exercise, priorValue) in zip(day.exercises, priorExerciseCompletion) {
                exercise.isCompleted = priorValue
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func deleteProgram(_ program: WorkoutProgram) {
        modelContext.delete(program)
        guard PersistenceReporter.save(modelContext, operation: "workout program deletion") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        selectedWeek = 1
        programToDelete = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func openGeneratorLab() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        showGeneratorLab = true
    }

    func generationSourceBadge(for summary: String) -> (label: String, foreground: Color, background: Color)? {
        switch GeneratedContentSource.detect(in: summary) {
        case .aiCoach:
            return (GeneratedContentSource.aiCoach.label, .green, Color.green.opacity(0.15))
        case .recoveryEngine:
            return (GeneratedContentSource.recoveryEngine.label, .orange, Color.orange.opacity(0.15))
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

    func syncSelectedWeekWithCurrentProgram() {
        guard let program = currentProgram else {
            selectedWeek = 1
            return
        }

        let maxAvailableWeek = max(1, program.currentWeek)
        if selectedWeek < 1 || selectedWeek > maxAvailableWeek {
            selectedWeek = maxAvailableWeek
        }
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
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return nil
        }
    }
}
