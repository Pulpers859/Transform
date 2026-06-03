import SwiftUI
import SwiftData
import UIKit

struct WorkoutGeneratorLabView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var analysisSessions: [BodyAnalysisSession]
    @Query(sort: \WorkoutProgram.createdDate, order: .reverse) private var programs: [WorkoutProgram]
    @FocusState private var focusedEditor: EditorField?

    @State private var selectedStage: WorkoutGeneratorDebugStage = .weekOne
    @State private var selectedMode: WorkoutGeneratorDebugMode = .lastGeneration
    @State private var selectedAnalysisSourceIndex = 0
    @State private var targetWeekNumber = 2
    @State private var splitType = ""
    @State private var programName = ""
    @State private var analysisJSON = ""
    @State private var previousWeekJSON = ""
    @State private var replayJSON = ""
    @State private var isRunning = false
    @State private var report: WorkoutGeneratorDebugReport?
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var toastMessage: String?
    @State private var didSeed = false
    @State private var showAnalysisEditor = false
    @State private var showPreviousWeekEditor = false
    @State private var showReplayEditor = false
    @State private var decodedAnalysis: BodyAnalysisResult?
    @State private var analysisValidationTask: Task<Void, Never>?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var runTask: Task<Void, Never>?

    enum EditorField: Hashable {
        case analysis
        case previousWeek
        case replay
    }

    var currentProgram: WorkoutProgram? {
        programs.first
    }

    private var analysisSourceOptions: [WorkoutGeneratorAnalysisSourceOption] {
        var options: [WorkoutGeneratorAnalysisSourceOption] = []

        if let currentProgram,
           !currentProgram.analysisJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options.append(programAnalysisSourceOption(for: currentProgram))
        }

        options.append(contentsOf: analysisSessions.map(savedAnalysisSourceOption(for:)))
        return options
    }

    private var selectedAnalysisSource: WorkoutGeneratorAnalysisSourceOption? {
        guard analysisSourceOptions.indices.contains(selectedAnalysisSourceIndex) else { return nil }
        return analysisSourceOptions[selectedAnalysisSourceIndex]
    }

    var selectedAnalysisSummary: String {
        selectedAnalysisSource?.summary ?? "No analysis snapshot selected."
    }

    var liveAICreditWarning: String {
        "Live AI mode uses API credits and can retry up to 3 times before procedural fallback."
    }

    var canUseAI: Bool {
        Config.hasAnthropicKey
    }

    var canRun: Bool {
        if selectedMode == .lastGeneration {
            return currentProgram?.lastGenerationBundle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        if decodedAnalysis == nil {
            return false
        }

        if selectedMode == .liveAI && !canUseAI {
            return false
        }

        if selectedStage == .nextWeek {
            let hasCoreContext = !splitType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !programName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !previousWeekJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasCoreContext {
                return false
            }
            if selectedMode == .validatorReplay {
                return !replayJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }

        if selectedMode == .validatorReplay {
            return !replayJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    introCard
                    runConfigurationCard
                    analysisSourceCard

                    if selectedStage == .nextWeek {
                        nextWeekContextCard
                    }

                    jsonEditorsCard
                    runButton

                    if let report {
                        resultsCard(report)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Generator Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismissLab()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedEditor = nil
                    }
                }
            }
            .overlay(alignment: .top) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert("Generator Lab", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                seedStateIfNeeded(force: false)
            }
            .onDisappear {
                analysisValidationTask?.cancel()
                toastDismissTask?.cancel()
                runTask?.cancel()
            }
            .onChange(of: analysisSessions.count) { _, _ in
                syncSelectionBounds()
                refreshAnalysisJSONFromSelection()
            }
            .onChange(of: programs.count) { _, _ in
                syncSelectionBounds()
                refreshAnalysisJSONFromSelection()
                if previousWeekJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    seedProgramContextFromCurrentProgram()
                }
            }
            .onChange(of: selectedAnalysisSourceIndex) { _, _ in
                refreshAnalysisJSONFromSelection()
            }
            .onChange(of: analysisJSON) { _, _ in
                scheduleAnalysisValidation()
            }
            .onChange(of: selectedStage) { _, newStage in
                if newStage == .weekOne {
                    if targetWeekNumber < 2 {
                        targetWeekNumber = 2
                    }
                } else {
                    seedProgramContextFromCurrentProgram()
                }
            }
        }
    }

    var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Internal sandbox for workout generation, validator replay, and procedural fallback checks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                statPill(title: "Saved Analyses", value: "\(analysisSessions.count)")
                statPill(title: "Programs", value: "\(programs.count)")
                statPill(title: "Default Mode", value: selectedMode.rawValue)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    var runConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Run Configuration")

            Picker("Stage", selection: $selectedStage) {
                ForEach(WorkoutGeneratorDebugStage.allCases) { stage in
                    Text(stage.rawValue).tag(stage)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text("Mode")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Picker("Mode", selection: $selectedMode) {
                    ForEach(WorkoutGeneratorDebugMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text(selectedMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedMode == .liveAI {
                warningBanner(text: liveAICreditWarning, color: .orange)
                if !canUseAI {
                    warningBanner(text: Config.anthropicKeyInlineHelpText, color: .red)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    var analysisSourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Analysis Source")

            if analysisSourceOptions.isEmpty {
                Text("Save at least one body analysis or generate a workout program to seed the lab with real context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Analysis Snapshot", selection: $selectedAnalysisSourceIndex) {
                    ForEach(Array(analysisSourceOptions.enumerated()), id: \.offset) { index, option in
                        Text(option.label).tag(index)
                    }
                }
                .pickerStyle(.menu)

                Text(selectedAnalysisSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    var nextWeekContextCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Next Week Context")

            HStack(spacing: 12) {
                contextField(title: "Program Name", text: $programName)
                contextField(title: "Split Type", text: $splitType)
            }

            Stepper(value: $targetWeekNumber, in: 2...4) {
                HStack {
                    Text("Target Week")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Week \(targetWeekNumber)")
                        .font(.subheadline.bold())
                }
            }

            if let currentProgram {
                Text("Current program context: \(currentProgram.programName), week \(currentProgram.currentWeek)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    var jsonEditorsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Editable Inputs")

            DisclosureGroup(isExpanded: $showAnalysisEditor) {
                VStack(alignment: .leading, spacing: 10) {
                    jsonEditor(text: $analysisJSON, minHeight: 180, field: .analysis)
                    Button("Reset From Selected Analysis") {
                        refreshAnalysisJSONFromSelection()
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                }
                .padding(.top, 8)
            } label: {
                editorHeader(title: "Analysis JSON", detail: "\(analysisJSON.count) chars")
            }

            if selectedStage == .nextWeek {
                DisclosureGroup(isExpanded: $showPreviousWeekEditor) {
                    VStack(alignment: .leading, spacing: 10) {
                        jsonEditor(text: $previousWeekJSON, minHeight: 180, field: .previousWeek)
                        Button("Reset From Current Program") {
                            refreshPreviousWeekJSONFromCurrentProgram()
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    }
                    .padding(.top, 8)
                } label: {
                    editorHeader(title: "Previous Week JSON", detail: "\(previousWeekJSON.count) chars")
                }
            }

            if selectedMode == .validatorReplay {
                DisclosureGroup(isExpanded: $showReplayEditor) {
                    VStack(alignment: .leading, spacing: 10) {
                        jsonEditor(text: $replayJSON, minHeight: 220, field: .replay)

                        HStack {
                            Button("Load Final JSON From Last Result") {
                                replayJSON = report?.finalJSON ?? replayJSON
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.orange)

                            Spacer()

                            if selectedStage == .nextWeek, let currentProgram {
                                Button("Load Current Program JSON") {
                                    replayJSON = currentProgram.programJSON
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    editorHeader(title: "Replay Candidate JSON", detail: "\(replayJSON.count) chars")
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    var runButton: some View {
        Button {
            focusedEditor = nil
            runTask?.cancel()
            runTask = Task { await runLab() }
        } label: {
            HStack {
                if isRunning {
                    ProgressView()
                        .tint(.white)
                    Text("Running…")
                } else {
                    Image(systemName: selectedMode == .liveAI ? "bolt.fill" : "waveform.path.ecg")
                    Text("\(selectedMode.actionTitle) • \(selectedStage.rawValue)")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canRun ? Color.orange : Color.orange.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .font(.headline.bold())
        }
        .buttonStyle(.plain)
        .disabled(isRunning || !canRun)
    }

    func resultsCard(_ report: WorkoutGeneratorDebugReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Result")
                        .font(.headline)
                    Text("\(report.mode.rawValue) • \(report.stage.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                sourceBadge(for: report)
            }

            HStack(spacing: 10) {
                statPill(title: "Week", value: "\(report.weekNumber)")
                statPill(title: "Fallback", value: report.usedFallback ? "Yes" : "No")
                statPill(title: "Issues", value: "\(report.finalIssues.count)")
            }

            Text(report.previewSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let terminalError = report.terminalError,
               !terminalError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warningBanner(text: terminalError, color: .red)
            }

            HStack(spacing: 10) {
                copyButton(title: "Copy Bundle", payload: report.bundleText)
                if report.hasFinalPayload {
                    copyButton(title: "Copy Final JSON", payload: report.finalJSON)
                }
                copyButton(title: "Copy Validator", payload: report.validatorReportText)
            }

            if !report.warnings.isEmpty {
                warningBanner(text: report.warningsText, color: .yellow)
            }

            disclosureBlock(title: "Validator Issues", subtitle: "\(report.finalIssues.count)") {
                if report.finalIssues.isEmpty {
                    Text("No validator issues.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(report.finalIssues.enumerated()), id: \.offset) { index, issue in
                            Text("\(index + 1). \(issue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            disclosureBlock(title: "Attempt Trace", subtitle: "\(report.attempts.count)") {
                if report.attempts.isEmpty {
                    Text("No attempt trace for this mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(report.attempts) { attempt in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Attempt \(attempt.attemptNumber)")
                                    .font(.caption.bold())
                                Text(attempt.outcome)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !attempt.validatorIssues.isEmpty {
                                    ForEach(Array(attempt.validatorIssues.enumerated()), id: \.offset) { _, issue in
                                        Text("• \(issue)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }

            disclosureBlock(title: "Prompt Context", subtitle: "Blueprint + prompts") {
                VStack(alignment: .leading, spacing: 12) {
                    promptSection(title: "Analysis Summary", text: report.analysisSummary)
                    promptSection(title: "Training Intent", text: report.trainingIntentSummary)
                    promptSection(title: "Blueprint", text: report.blueprintSummary)
                    if let previousWeekReference = report.previousWeekReference {
                        promptSection(title: "Previous Week Reference", text: previousWeekReference)
                    }
                    promptSection(title: "System Prompt", text: report.systemPrompt)
                    promptSection(title: "User Prompt", text: report.userPrompt)
                }
            }

            if !report.previewDays.isEmpty {
                disclosureBlock(title: "Preview Days", subtitle: "\(report.previewDays.count)") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(report.previewDays.sorted { $0.dayNumber < $1.dayNumber }, id: \.dayNumber) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Day \(day.dayNumber) • \(day.dayName)")
                                    .font(.subheadline.bold())
                                Text(day.muscleGroups)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if day.isRestDay {
                                    Text("Rest / Recovery")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                } else {
                                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { index, exercise in
                                        Text("\(index + 1). \(exercise.exerciseName) • \(exercise.sets)x\(exercise.reps)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    func runLab() async {
        if selectedMode == .lastGeneration {
            await loadLastGenerationReport()
            return
        }

        guard let analysis = decodedAnalysis else {
            presentError("The analysis JSON could not be decoded into a valid BodyAnalysisResult.")
            return
        }

        isRunning = true
        defer { isRunning = false }

        do {
            let generatedReport: WorkoutGeneratorDebugReport
            switch selectedStage {
            case .weekOne:
                generatedReport = try await ClaudeService.shared.debugGenerateWeekOne(
                    from: analysis,
                    mode: selectedMode,
                    replayJSON: selectedMode == .validatorReplay ? replayJSON : nil
                )
            case .nextWeek:
                generatedReport = try await ClaudeService.shared.debugGenerateNextWeek(
                    weekNumber: targetWeekNumber,
                    previousWeekJSON: previousWeekJSON,
                    analysisJSON: analysisJSON,
                    splitType: splitType.trimmingCharacters(in: .whitespacesAndNewlines),
                    programName: programName.trimmingCharacters(in: .whitespacesAndNewlines),
                    mode: selectedMode,
                    replayJSON: selectedMode == .validatorReplay ? replayJSON : nil
                )
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                report = generatedReport
            }
        } catch is CancellationError {
            return
        } catch {
            presentError(error.localizedDescription)
        }
    }

    @MainActor
    func loadLastGenerationReport() async {
        guard let program = currentProgram else {
            presentError("No current program found.")
            return
        }

        let bundle = program.lastGenerationBundle
        guard !bundle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presentError("No stored generation report. Generate a workout first.")
            return
        }

        let warnings = program.validatorWarnings
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let previewDays = ClaudeService.shared.decodePreviousWeekDays(from: program.programJSON)

        var lastReport = WorkoutGeneratorDebugReport(
            stage: program.currentWeek == 1 ? .weekOne : .nextWeek,
            mode: .lastGeneration,
            weekNumber: program.currentWeek,
            usedAPI: true,
            sourceLabel: ClaudeService.shared.sourceLabel(from: program.programSummary, fallback: "[AI Coach]"),
            acceptedWithWarnings: !warnings.isEmpty,
            usedFallback: program.programSummary.contains("[Recovery Engine]"),
            displayTitle: program.programName,
            splitType: program.splitType,
            analysisSummary: "(stored in bundle)",
            trainingIntentSummary: "(stored in bundle)",
            blueprintSummary: "(stored in bundle)",
            previousWeekReference: nil,
            systemPrompt: "(stored in bundle)",
            userPrompt: "(stored in bundle)",
            warnings: warnings,
            finalIssues: warnings,
            attempts: [],
            replayInputJSON: nil,
            terminalError: nil,
            finalJSON: program.programJSON,
            previewSummary: program.programSummary,
            previewDays: previewDays
        )
        lastReport.storedBundleText = bundle
        report = lastReport
    }

    func seedStateIfNeeded(force: Bool) {
        guard force || !didSeed else { return }
        didSeed = true
        selectedAnalysisSourceIndex = 0
        syncSelectionBounds()
        refreshAnalysisJSONFromSelection()
        seedProgramContextFromCurrentProgram()
    }

    func syncSelectionBounds() {
        if !analysisSourceOptions.isEmpty {
            selectedAnalysisSourceIndex = min(selectedAnalysisSourceIndex, analysisSourceOptions.count - 1)
        } else {
            selectedAnalysisSourceIndex = 0
        }
    }

    func seedProgramContextFromCurrentProgram() {
        if let currentProgram {
            splitType = currentProgram.splitType
            programName = currentProgram.programName
            targetWeekNumber = min(max(currentProgram.currentWeek + 1, 2), 4)
            previousWeekJSON = currentProgram.programJSON
        } else {
            splitType = splitType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Adaptive Hypertrophy Split" : splitType
            programName = programName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Debug Program" : programName
        }
    }

    func refreshAnalysisJSONFromSelection() {
        guard let selectedAnalysisSource else {
            analysisJSON = ""
            decodedAnalysis = nil
            return
        }

        analysisJSON = selectedAnalysisSource.analysisJSON
        scheduleAnalysisValidation(immediate: true)
    }

    func refreshPreviousWeekJSONFromCurrentProgram() {
        previousWeekJSON = currentProgram?.programJSON ?? ""
    }

    func decodeAnalysisFromEditor() -> BodyAnalysisResult? {
        let trimmed = analysisJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BodyAnalysisResult.self, from: data)
    }

    func scheduleAnalysisValidation(immediate: Bool = false) {
        analysisValidationTask?.cancel()

        let applyValidation = {
            decodedAnalysis = decodeAnalysisFromEditor()
        }

        if immediate {
            applyValidation()
            return
        }

        let currentJSON = analysisJSON
        analysisValidationTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            let decoded: BodyAnalysisResult?
            let trimmed = currentJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                decoded = nil
            } else if let data = trimmed.data(using: .utf8) {
                decoded = try? JSONDecoder().decode(BodyAnalysisResult.self, from: data)
            } else {
                decoded = nil
            }

            await MainActor.run {
                guard analysisJSON == currentJSON else { return }
                decodedAnalysis = decoded
            }
        }
    }

    func prettyJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ClaudeError.parseError("Could not convert encoded JSON into text.")
        }
        return string
    }

    func analysisLabel(for session: BodyAnalysisSession) -> String {
        let date = session.date.formatted(date: .abbreviated, time: .shortened)
        let focus = Array(session.programmingPriorityAreas.prefix(2)).joined(separator: ", ")
        let cleanedFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedFocus.isEmpty ? date : "\(date) • \(cleanedFocus)"
    }

    private func savedAnalysisSourceOption(for session: BodyAnalysisSession) -> WorkoutGeneratorAnalysisSourceOption {
        let json: String
        if !session.analysisJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            json = session.analysisJSON
        } else if let result = session.decodedResult,
                  let encoded = try? prettyJSONString(result) {
            json = encoded
        } else {
            json = ""
        }

        let priorities = Array(session.programmingPriorityAreas.prefix(3)).joined(separator: ", ")
        let focus = priorities.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = focus.isEmpty
            ? "Saved body-analysis session from \(session.date.formatted(date: .abbreviated, time: .shortened))."
            : "Saved body-analysis session from \(session.date.formatted(date: .abbreviated, time: .shortened)) focused on \(focus)."

        return WorkoutGeneratorAnalysisSourceOption(
            label: analysisLabel(for: session),
            summary: summary,
            analysisJSON: json
        )
    }

    private func programAnalysisSourceOption(for program: WorkoutProgram) -> WorkoutGeneratorAnalysisSourceOption {
        let programDate = program.createdDate.formatted(date: .abbreviated, time: .shortened)
        let analysisDate = program.sourceAnalysisDate?.formatted(date: .abbreviated, time: .shortened)
        let focus = program.focusAreas.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusSuffix = focus.isEmpty ? "" : " • \(focus)"

        let summary: String
        if let analysisDate, !analysisDate.isEmpty {
            summary = "Embedded analysis snapshot from the current workout program created \(programDate). Original analysis date: \(analysisDate)."
        } else {
            summary = "Embedded analysis snapshot from the current workout program created \(programDate)."
        }

        return WorkoutGeneratorAnalysisSourceOption(
            label: "Current Program • \(programDate)\(focusSuffix)",
            summary: summary,
            analysisJSON: program.analysisJSON
        )
    }

    func copyToClipboard(_ payload: String, confirmation: String) {
        UIPasteboard.general.string = payload
        withAnimation(.easeOut(duration: 0.2)) {
            toastMessage = confirmation
        }
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    toastMessage = nil
                }
            }
        }
    }

    func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.orange)
            .tracking(1.3)
    }

    func statPill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func warningBanner(text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func contextField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    func editorHeader(title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
            Spacer()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func jsonEditor(text: Binding<String>, minHeight: CGFloat, field: EditorField) -> some View {
        TextEditor(text: text)
            .font(.system(.caption, design: .monospaced))
            .focused($focusedEditor, equals: field)
            .frame(minHeight: minHeight)
            .padding(8)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    func disclosureBlock<Content: View>(title: String, subtitle: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func promptSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    func copyButton(title: String, payload: String) -> some View {
        Button {
            copyToClipboard(payload, confirmation: "\(title) copied")
        } label: {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.12))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    func sourceBadge(for report: WorkoutGeneratorDebugReport) -> some View {
        let isTerminalFailure = report.hasTerminalError
        return Text(report.sourceDisplayName)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isTerminalFailure
                    ? Color.red.opacity(0.15)
                    : (report.usedFallback ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
            )
            .foregroundStyle(isTerminalFailure ? .red : (report.usedFallback ? .orange : .green))
            .clipShape(Capsule())
    }

    func dismissLab() {
        runTask?.cancel()
        toastDismissTask?.cancel()
        analysisValidationTask?.cancel()
        dismiss()
    }
}

private struct WorkoutGeneratorAnalysisSourceOption {
    let label: String
    let summary: String
    let analysisJSON: String
}
