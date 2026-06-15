import SwiftUI
import SwiftData
import Foundation

struct WorkoutDayDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExerciseWeightEntry.loggedAt, order: .reverse) private var allWeightLogs: [ExerciseWeightEntry]
    @Query(sort: \ExercisePerformanceLog.loggedAt, order: .reverse) private var allPerformanceLogs: [ExercisePerformanceLog]
    let day: WorkoutDay
    @State private var exerciseForWeightLogging: WorkoutExercise?
    @State private var feedbackDay: WorkoutDay?

    var completedExerciseCount: Int {
        day.sortedExercises.filter { $0.isCompleted }.count
    }

    var totalExerciseCount: Int {
        day.exercises.count
    }

    var exerciseProgress: Double {
        totalExerciseCount > 0 ? Double(completedExerciseCount) / Double(totalExerciseCount) : 0
    }

    var sessionNoteSections: SessionNoteSections {
        SessionNoteSections.parse(day.notes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dayHeader
                if !day.notes.isEmpty {
                    sessionNotes
                }
                if day.isCompleted {
                    sessionFeedbackCard
                }
                exerciseList
            }
            .padding()
        }
        .workoutTabBarClearance()
        .navigationTitle("Day \(day.dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exerciseForWeightLogging) { exercise in
            AddExerciseWeightSheet(
                exercise: exercise,
                weightSummary: weightSummary(for: exercise)
            )
        }
        .sheet(item: $feedbackDay) { selectedDay in
            WorkoutSessionFeedbackSheet(day: selectedDay)
        }
    }

    // MARK: - Day Header

    var dayHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.dayName)
                        .font(.title2.bold())
                    Text(day.muscleGroups)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                weekBadge
            }

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(TFColor.accent.opacity(0.15))
                            .frame(height: 6)
                        Capsule()
                            .fill(TFColor.accent)
                            .frame(width: geo.size.width * exerciseProgress, height: 6)
                            .animation(.easeOut(duration: 0.4), value: exerciseProgress)
                    }
                }
                .frame(height: 6)

                Text("\(completedExerciseCount)/\(totalExerciseCount)")
                    .font(.caption.bold())
                    .foregroundStyle(TFColor.accent)
                    .frame(width: 36)
            }
        }
        .dashCard()
    }

    var weekBadge: some View {
        Text("Week \(day.weekNumber)")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(TFColor.accent.opacity(0.15))
            .foregroundStyle(TFColor.accent)
            .clipShape(Capsule())
    }

    // MARK: - Session Notes

    var sessionNotes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Session Notes", systemImage: "note.text")
                .font(.headline)
                .foregroundStyle(TFColor.accent)

            if !sessionNoteSections.summary.isEmpty {
                Text(sessionNoteSections.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !sessionNoteSections.warmupSteps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warm-up Checklist")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)

                    ForEach(sessionNoteSections.warmupSteps, id: \.self) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(TFColor.accent)
                                .padding(.top, 6)

                            Text(step)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    var sessionFeedbackCard: some View {
        Button {
            feedbackDay = day
        } label: {
            HStack(spacing: 12) {
                Image(systemName: day.hasSessionFeedback ? "checkmark.bubble.fill" : "bubble.left.and.exclamationmark.bubble.right")
                    .foregroundStyle(day.hasSessionFeedback ? TFColor.success : TFColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.hasSessionFeedback ? "Session Feedback" : "Add Session Feedback")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(day.hasSessionFeedback
                         ? "Effort \(day.sessionEffort)/5 · Stimulus \(day.stimulusQuality)/5 · Pain \(day.jointPain)/5 · \(day.performanceRating?.rawValue ?? "Not rated")"
                         : "Four quick ratings help calibrate next week.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(TFColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Exercise List

    var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            TFSectionLabel(text: "Exercises")

            ForEach(day.sortedExercises) { exercise in
                ExerciseCard(
                    exercise: exercise,
                    weightSummary: weightSummary(for: exercise),
                    latestSetLogs: latestSetLogs(for: exercise),
                    onToggle: { toggleExercise(exercise) },
                    onLogWeight: { exerciseForWeightLogging = exercise }
                )
            }
        }
    }

    func toggleExercise(_ exercise: WorkoutExercise) {
        let previousExerciseState = exercise.isCompleted
        let previousDayState = day.isCompleted
        exercise.isCompleted.toggle()

        let allDone = day.exercises.allSatisfy { $0.isCompleted }
        if allDone != day.isCompleted {
            day.isCompleted = allDone
        }

        guard PersistenceReporter.save(modelContext, operation: "exercise completion toggle") else {
            modelContext.rollback()
            exercise.isCompleted = previousExerciseState
            day.isCompleted = previousDayState
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if day.isCompleted && !previousDayState {
            feedbackDay = day
        }
    }

    func weightSummary(for exercise: WorkoutExercise) -> ExerciseWeightEntry? {
        ExerciseWeightStore.summary(for: exercise, within: allWeightLogs)
    }

    func latestSetLogs(for exercise: WorkoutExercise) -> [SetLogEntry] {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        guard let latest = allPerformanceLogs.first(where: {
            $0.canonicalExerciseKey == key && !$0.setLogsJSON.isEmpty
        }) else { return [] }
        return latest.decodedSetLogs
    }
}

// MARK: - Exercise Card

struct ExerciseCard: View {
    @Environment(\.modelContext) private var modelContext
    let exercise: WorkoutExercise
    let weightSummary: ExerciseWeightEntry?
    let latestSetLogs: [SetLogEntry]
    let onToggle: () -> Void
    let onLogWeight: () -> Void

    @State private var isRestTimerActive = false
    @State private var remainingRestSeconds = 0
    @State private var restTimerTask: Task<Void, Never>?
    @State private var showExpandedRestTimer = false
    @State private var didCompleteRestTimer = false
    @State private var restEndDate: Date?

    var latestWeightLog: ExerciseWeightEntry? {
        weightSummary
    }

    var bestWeightText: String? {
        guard let latestWeightLog else { return nil }
        let bestWeight = latestWeightLog.hasBestRecord ? latestWeightLog.bestWeightLbs : latestWeightLog.weightLbs
        return "\(formatWeight(bestWeight)) lb"
    }

    var lastRepsTileText: String? {
        latestWeightLog?.repsCompleted.map { "\($0) reps" }
    }

    var bestRepsTileText: String? {
        guard let latestWeightLog else { return nil }
        let bestReps = latestWeightLog.hasBestRecord ? (latestWeightLog.bestRepsCompleted ?? latestWeightLog.repsCompleted) : latestWeightLog.repsCompleted
        return bestReps.map { "\($0) reps" }
    }

    var parsedPrescription: ExercisePrescription? {
        ExercisePrescription.parse(from: exercise.notes)
    }

    var progressionSuggestion: ProgressionSuggestion? {
        guard let log = latestWeightLog else { return nil }
        let repRange = RepRange.parse(exercise.reps)
        guard let repRange else { return nil }
        return ProgressionSuggestion.evaluate(
            setLogs: latestSetLogs,
            summaryRepsCompleted: log.repsCompleted,
            repRange: repRange,
            lastWeight: log.weightLbs,
            exercise: exercise
        )
    }

    var cleanedCoachingNote: String {
        if let parsedPrescription {
            return parsedPrescription.cleanedNotes
        }
        return exercise.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayTempo: String? {
        let structuredTempo = exercise.tempo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !structuredTempo.isEmpty {
            return structuredTempo
        }
        return parsedPrescription?.tempo
    }

    var restDisplayText: String {
        if didCompleteRestTimer {
            return "00:00"
        }
        if isRestTimerActive {
            return formatCountdown(remainingRestSeconds)
        }
        if remainingRestSeconds != exercise.restSeconds {
            return formatCountdown(remainingRestSeconds)
        }
        return formatRest(exercise.restSeconds)
    }

    var restStatusLabel: String {
        if didCompleteRestTimer {
            return "Complete"
        }
        if isRestTimerActive {
            return "Running"
        }
        if remainingRestSeconds != exercise.restSeconds {
            return "Paused"
        }
        return "Rest"
    }

    var restProgress: Double {
        guard exercise.restSeconds > 0 else { return 0 }
        if didCompleteRestTimer {
            return 1
        }
        let clampedRemaining = min(max(remainingRestSeconds, 0), exercise.restSeconds)
        return 1 - (Double(clampedRemaining) / Double(exercise.restSeconds))
    }

    var timerAccent: Color {
        if didCompleteRestTimer {
            return TFColor.success
        }
        if isRestTimerActive {
            return remainingRestSeconds <= 15 ? TFColor.danger : TFColor.accent
        }
        if remainingRestSeconds != exercise.restSeconds {
            return TFColor.warning
        }
        return TFColor.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    onToggle()
                } label: {
                    Image(systemName: exercise.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(exercise.isCompleted ? TFColor.success : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(exercise.isCompleted ? "Mark \(exercise.exerciseName) incomplete" : "Mark \(exercise.exerciseName) complete")

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.exerciseName)
                        .font(.subheadline.bold())
                        .strikethrough(exercise.isCompleted, color: .secondary)
                        .foregroundStyle(exercise.isCompleted ? .secondary : .primary)

                    if !exercise.muscleTarget.isEmpty {
                        Text(exercise.muscleTarget)
                            .font(.caption2)
                            .foregroundStyle(TFColor.accent)
                    }
                }

                Spacer()

                Text("#\(exercise.order + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 14)

            if exercise.restSeconds > 0 {
                restTimerPanel
                Divider().padding(.horizontal, 14)
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    ExerciseStat(icon: "square.stack.3d.up", label: "Sets", value: "\(exercise.sets)")
                    ExerciseStat(icon: "arrow.up.arrow.down", label: "Reps", value: exercise.reps)
                    if let tempo = displayTempo {
                        ExerciseStat(icon: "metronome", label: "Tempo", value: tempo)
                    }
                }

                if !latestSetLogs.isEmpty {
                    setLogBreakdown
                } else if latestWeightLog != nil {
                    ExerciseWeightSnapshotTile(
                        lastWeightText: latestWeightLog.map { "\(formatWeight($0.weightLbs)) lb" } ?? "-",
                        lastRepsText: lastRepsTileText,
                        bestWeightText: bestWeightText ?? "-",
                        bestRepsText: bestRepsTileText
                    )
                }

                if let suggestion = progressionSuggestion {
                    ProgressionSuggestionBadge(suggestion: suggestion)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let parsedPrescription {
                Divider().padding(.horizontal, 14)
                HStack(alignment: .center) {
                    Text(parsedPrescription.intensityLabel)
                        .font(parsedPrescription.intensity == .light ? .caption : .caption.bold())
                        .foregroundStyle(parsedPrescription.intensity.color)

                    Spacer()

                    if let rirValue = parsedPrescription.rir {
                        Text("RIR \(rirValue)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider().padding(.horizontal, 14)
            if let status = exercise.completionStatus, status != .completed {
                HStack(spacing: 6) {
                    Image(systemName: status.isSkipped ? "forward.fill" : "arrow.triangle.swap")
                        .font(.caption2)
                        .foregroundStyle(status.isSkipped ? TFColor.danger : TFColor.warning)
                    Text(status.shortLabel)
                        .font(.caption2.bold())
                        .foregroundStyle(status.isSkipped ? TFColor.danger : TFColor.warning)
                    Spacer()
                    Button {
                        exercise.completionStatus = nil
                        if status.isSkipped { exercise.isCompleted = false }
                        PersistenceReporter.save(modelContext, operation: "clear exercise status")
                    } label: {
                        Text("Clear")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(status.isSkipped ? TFColor.danger.opacity(0.06) : TFColor.warning.opacity(0.06))
            }

            Divider().padding(.horizontal, 14)
            HStack {
                Button {
                    onLogWeight()
                } label: {
                    Label("Log Sets", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(ExerciseCompletionStatus.allCases.filter { $0 != .completed }) { status in
                        Button {
                            exercise.completionStatus = status
                            if status.isSkipped {
                                exercise.isCompleted = true
                            }
                            PersistenceReporter.save(modelContext, operation: "set exercise status")
                        } label: {
                            Text(status.rawValue)
                        }
                    }
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                NavigationLink {
                    ExerciseProgressionView(exerciseName: exercise.exerciseName)
                } label: {
                    Label("Progression", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }

                if let latestWeightLog {
                    Text(latestWeightLog.loggedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let latestWeightLog,
               !latestWeightLog.notes.isEmpty {
                Divider().padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 4) {
                    if !latestWeightLog.notes.isEmpty {
                        Text(latestWeightLog.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            if !cleanedCoachingNote.isEmpty {
                Divider().padding(.horizontal, 14)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(TFColor.warning)
                    Text(cleanedCoachingNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(exercise.isCompleted ? TFColor.success.opacity(0.05) : TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(exercise.isCompleted ? TFColor.success.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .onAppear {
            if remainingRestSeconds == 0 && !didCompleteRestTimer {
                remainingRestSeconds = exercise.restSeconds
            }
            // Resume the loop if a timer is running but its task was torn down
            // (e.g. after the fullscreen cover dismissed this card).
            if isRestTimerActive && restTimerTask == nil {
                startRestTimer()
            }
        }
        // Intentionally no stopRestTimer() here: the fullscreen cover fires
        // onDisappear on this card, and killing the loop there froze a running
        // timer. The loop is bounded and reads the wall clock, so it is safe to
        // let it run.
        .fullScreenCover(isPresented: $showExpandedRestTimer) {
            RestTimerFullscreen(
                exerciseName: exercise.exerciseName,
                exerciseNumber: exercise.order + 1,
                prescriptionLabel: "\(exercise.sets) sets x \(exercise.reps) reps",
                statusLabel: restStatusLabel,
                timeText: restDisplayText,
                accent: timerAccent,
                isTimerActive: isRestTimerActive,
                progress: restProgress,
                onToggle: { toggleRestTimer() },
                onReset: { resetRestTimer() },
                onClose: { showExpandedRestTimer = false }
            )
        }
    }

    var setLogBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST SESSION")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .tracking(1)

            ForEach(latestSetLogs) { set in
                HStack(spacing: 8) {
                    Text("Set \(set.setNumber)")
                        .font(.caption2.bold())
                        .foregroundStyle(TFColor.accent)
                        .frame(width: 38, alignment: .leading)
                    Text("\(formatWeight(set.weightLbs)) lb")
                        .font(.caption.bold())
                        .frame(width: 65, alignment: .trailing)
                    Text("\u{00D7}")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(set.repsCompleted) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let best = bestWeightText {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(TFColor.warning)
                    Text("Best: \(best)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    var restTimerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Rest Timer:")
                    .font(.title3)
                    .foregroundStyle(.primary)
                Text(restDisplayText)
                    .font(.title3.bold())
                    .foregroundStyle(timerAccent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 58, alignment: .leading)
                Spacer()

                Button {
                    showExpandedRestTimer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(timerAccent.opacity(0.14))
                    Capsule()
                        .fill(timerAccent)
                        .frame(width: geo.size.width * max(0, min(restProgress, 1)))
                }
            }
            .frame(height: 8)

            HStack(spacing: 10) {
                Button {
                    toggleRestTimer()
                } label: {
                    Label(isRestTimerActive ? "Pause" : (remainingRestSeconds != exercise.restSeconds ? "Resume" : "Start Rest"), systemImage: isRestTimerActive ? "pause.fill" : "play.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(timerAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
                }
                .buttonStyle(.plain)

                Button {
                    resetRestTimer()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.06))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rest timer: \(restStatusLabel), \(restDisplayText)")
    }

    func toggleRestTimer() {
        if isRestTimerActive {
            pauseRestTimer()
            return
        }

        if didCompleteRestTimer {
            didCompleteRestTimer = false
            remainingRestSeconds = exercise.restSeconds
        }

        if remainingRestSeconds <= 0 || remainingRestSeconds > exercise.restSeconds {
            remainingRestSeconds = exercise.restSeconds
        }
        restEndDate = Date().addingTimeInterval(Double(remainingRestSeconds))
        isRestTimerActive = true
        startRestTimer()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func startRestTimer() {
        stopRestTimer()
        restTimerTask = Task { @MainActor in
            while isRestTimerActive && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                tickRestTimer()
            }
        }
    }

    func stopRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
    }

    func pauseRestTimer() {
        if let endDate = restEndDate {
            remainingRestSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        }
        restEndDate = nil
        isRestTimerActive = false
        stopRestTimer()
    }

    func resetRestTimer() {
        pauseRestTimer()
        didCompleteRestTimer = false
        remainingRestSeconds = exercise.restSeconds
    }

    func tickRestTimer() {
        guard isRestTimerActive, let endDate = restEndDate else {
            stopRestTimer()
            return
        }

        // Derive the countdown from the wall clock so it stays correct across
        // phone lock / app suspension instead of decrementing per tick.
        let remaining = Int(ceil(endDate.timeIntervalSinceNow))
        if remaining > 0 {
            if remaining != remainingRestSeconds {
                remainingRestSeconds = remaining
            }
            return
        }

        pauseRestTimer()
        remainingRestSeconds = 0
        didCompleteRestTimer = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func formatCountdown(_ seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let min = clamped / 60
        let sec = clamped % 60
        return String(format: "%02d:%02d", min, sec)
    }

    func formatRest(_ seconds: Int) -> String {
        if seconds >= 60 {
            let min = seconds / 60
            let sec = seconds % 60
            return sec > 0 ? "\(min)m \(sec)s" : "\(min)m"
        }
        return "\(seconds)s"
    }

    func formatWeight(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return String(Int(weight))
        }
        return String(format: "%.1f", weight)
    }
}

// MARK: - Exercise Stat

struct ExerciseStat: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundStyle(TFColor.accent)
                .frame(height: 16)

            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }
}

struct ExerciseWeightSnapshotTile: View {
    let lastWeightText: String
    let lastRepsText: String?
    let bestWeightText: String
    let bestRepsText: String?

    var body: some View {
        HStack(spacing: 0) {
            weightColumn(title: "Last", value: lastWeightText, reps: lastRepsText)
            Divider()
                .padding(.vertical, 10)
            weightColumn(title: "Best", value: bestWeightText, reps: bestRepsText)
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    func weightColumn(title: String, value: String, reps: String?) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if let reps, !reps.isEmpty {
                Text(reps)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}

struct RestTimerFullscreen: View {
    let exerciseName: String
    let exerciseNumber: Int
    let prescriptionLabel: String
    let statusLabel: String
    let timeText: String
    let accent: Color
    let isTimerActive: Bool
    let progress: Double
    let onToggle: () -> Void
    let onReset: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, accent.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button("Done") {
                        onClose()
                    }
                    .font(.headline.bold())
                    .foregroundStyle(.white.opacity(0.9))

                    Spacer()
                }

                Spacer()

                Text("Exercise \(exerciseNumber)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))

                Text(exerciseName)
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                Text(prescriptionLabel)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)

                Text(statusLabel.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                    .tracking(2)

                Text(timeText)
                    .font(.system(size: 92, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * max(0, min(progress, 1)))
                    }
                }
                .frame(height: 12)

                HStack(spacing: 12) {
                    Button {
                        onToggle()
                    } label: {
                        Label(isTimerActive ? "Pause" : "Start / Resume", systemImage: isTimerActive ? "pause.fill" : "play.fill")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .foregroundStyle(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }

                    Button {
                        onReset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .statusBarHidden()
    }
}

struct SessionNoteSections {
    let summary: String
    let warmupSteps: [String]

    static func parse(_ raw: String) -> SessionNoteSections {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SessionNoteSections(summary: "", warmupSteps: [])
        }

        if let delimitedSections = parseDelimitedWarmupSections(from: trimmed) {
            return delimitedSections
        }

        if let embeddedSections = parseEmbeddedWarmupSections(from: trimmed) {
            return embeddedSections
        }

        return SessionNoteSections(summary: trimmed, warmupSteps: [])
    }

    private static func parseDelimitedWarmupSections(from text: String) -> SessionNoteSections? {
        let normalized = text
            .replacingOccurrences(of: "Warm-up checklist:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Warm up checklist:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Warm-up:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Warm up:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Mobility/activation:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Mobility:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Activation:", with: "|", options: .caseInsensitive)
            .replacingOccurrences(of: "Prime with:", with: "|", options: .caseInsensitive)

        let chunks = normalized
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard chunks.count > 1 else {
            return nil
        }

        let summary = chunks.first ?? ""
        let instructionText = chunks.dropFirst().joined(separator: " ")
        let steps = splitWarmupSteps(from: instructionText)

        return SessionNoteSections(summary: summary, warmupSteps: steps)
    }

    private static func parseEmbeddedWarmupSections(from text: String) -> SessionNoteSections? {
        guard let triggerRange = text.range(
            of: #"(?i)(?:warm[\s-]*up with|begin with|start with|prime with)\s+"#,
            options: .regularExpression
        ) else {
            return nil
        }

        let summaryPrefix = text[..<triggerRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let warmupAndRemainder = String(text[triggerRange.upperBound...])

        let delimiters = [" — ", " – ", ";", "."]
        let endIndex = delimiters
            .compactMap { delimiter in
                warmupAndRemainder.range(of: delimiter).map { $0.lowerBound }
            }
            .min()

        let warmupListText: String
        let trailingGuidance: String
        if let endIndex {
            warmupListText = String(warmupAndRemainder[..<endIndex])
            trailingGuidance = String(warmupAndRemainder[endIndex...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        } else {
            warmupListText = warmupAndRemainder
            trailingGuidance = ""
        }

        let steps = splitWarmupSteps(from: warmupListText)
        guard !steps.isEmpty else {
            return nil
        }

        let summary = [summaryPrefix, trailingGuidance]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SessionNoteSections(summary: summary, warmupSteps: steps)
    }

    private static func splitWarmupSteps(from text: String) -> [String] {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: " then ", with: ", ", options: .caseInsensitive)
            .replacingOccurrences(of: " plus ", with: ", ", options: .caseInsensitive)
            .replacingOccurrences(of: " and ", with: ", ", options: .caseInsensitive)
            .replacingOccurrences(of: "\n•", with: "\n")
            .replacingOccurrences(of: "\n-", with: "\n")

        return cleaned
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map {
                $0.replacingOccurrences(of: "Emphasis today:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            .filter { !$0.isEmpty }
    }
}

enum WorkoutIntensity: String {
    case light
    case moderate
    case heavy

    var color: Color {
        switch self {
        case .light: return TFColor.success
        case .moderate: return TFColor.warning
        case .heavy: return TFColor.danger
        }
    }
}

struct ExercisePrescription {
    let week: Int?
    let intensity: WorkoutIntensity
    let rir: String?
    let tempo: String?
    let cleanedNotes: String

    var intensityLabel: String {
        var left = ""
        if let week {
            left = "Week \(week)"
        }

        let intensityText: String
        switch intensity {
        case .light:
            intensityText = "Light Weight"
        case .moderate:
            intensityText = "Moderate Weight"
        case .heavy:
            intensityText = "Heavy Weight"
        }

        if left.isEmpty {
            return intensityText
        }
        return "\(left) \(intensityText)"
    }

    static func parse(from rawNotes: String) -> ExercisePrescription? {
        let trimmed = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let weekString = firstCapture(in: trimmed, pattern: #"(?i)\bweek\s*(\d+)\b"#)
        let week = weekString.flatMap(Int.init)

        guard let intensityMatch = firstCapture(in: trimmed, pattern: #"(?i)\b(light|moderate|heavy)\b"#)?.lowercased(),
              let intensity = WorkoutIntensity(rawValue: intensityMatch) else {
            return nil
        }

        let rir = firstCapture(in: trimmed, pattern: #"(?i)\bRIR\b\s*[:\-]?\s*(\d+(?:\.\d+)?)\b"#)
            ?? firstCapture(in: trimmed, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*RIR\b"#)
            ?? firstCapture(in: trimmed, pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*reps?\s+in\s+reserve\b"#)
        let tempo = firstCapture(in: trimmed, pattern: #"(?i)\btempo\b\s*[:\-]?\s*([0-9Xx](?:\s*-\s*[0-9Xx]){3})\b"#)?
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        var cleaned = trimmed
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bweek\s*\d+\s*(light|moderate|heavy)\s+weight\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b(light|moderate|heavy)\s+weight\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bweek\s*\d+\b\s*[:\-]?\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b(light|moderate|heavy)\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\bRIR\b\s*[:\-]?\s*\d+(?:\.\d+)?\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b\d+(?:\.\d+)?\s*RIR\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\b\d+(?:\.\d+)?\s*reps?\s+in\s+reserve\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(?i)\btempo\b\s*[:\-]?\s*[0-9Xx](?:\s*-\s*[0-9Xx]){3}\b"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\.\s*[:\-]\s*"#, with: ". ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^\s*[:\-]\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-"))

        return ExercisePrescription(
            week: week,
            intensity: intensity,
            rir: rir,
            tempo: tempo,
            cleanedNotes: cleaned
        )
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let value = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Progression Suggestion

struct RepRange {
    let low: Int
    let high: Int

    static func parse(_ reps: String) -> RepRange? {
        let cleaned = reps
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        if cleaned.contains("-") {
            let parts = cleaned.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, parts[0] > 0, parts[1] >= parts[0] else { return nil }
            return RepRange(low: parts[0], high: parts[1])
        }

        if let single = Int(cleaned), single > 0 {
            return RepRange(low: single, high: single)
        }

        return nil
    }
}

struct ProgressionSuggestion {
    let icon: String
    let text: String
    let color: Color

    static func evaluate(
        setLogs: [SetLogEntry],
        summaryRepsCompleted: Int?,
        repRange: RepRange,
        lastWeight: Double,
        exercise: WorkoutExercise
    ) -> ProgressionSuggestion? {
        let isCompound = exercise.sets >= 3 && (
            exercise.muscleTarget.lowercased().contains("back") ||
            exercise.muscleTarget.lowercased().contains("chest") ||
            exercise.muscleTarget.lowercased().contains("quad") ||
            exercise.muscleTarget.lowercased().contains("glute") ||
            exercise.muscleTarget.lowercased().contains("hamstring")
        )
        let increment = isCompound ? 5.0 : 2.5

        if !setLogs.isEmpty {
            let workingSets = setLogs.filter { abs($0.weightLbs - lastWeight) < 0.01 }
            let setsAtOrAboveTop = workingSets.filter { $0.repsCompleted >= repRange.high }.count
            let setsInRange = workingSets.filter { $0.repsCompleted >= repRange.low }.count
            let setsBelowRange = workingSets.filter { $0.repsCompleted < repRange.low }.count
            let totalWorking = workingSets.count
            let majorityThreshold = max(1, Int(ceil(Double(totalWorking) * 0.67)))

            if setsAtOrAboveTop >= majorityThreshold {
                let suggestedWeight = lastWeight + increment
                return ProgressionSuggestion(
                    icon: "arrow.up.circle.fill",
                    text: "Increase to \(formatWeight(suggestedWeight)) lb next session",
                    color: TFColor.success
                )
            }

            if setsAtOrAboveTop > 0 && setsAtOrAboveTop < majorityThreshold {
                let needed = majorityThreshold - setsAtOrAboveTop
                return ProgressionSuggestion(
                    icon: "flame.fill",
                    text: "Strong top set — hit \(repRange.high) on \(needed) more set\(needed == 1 ? "" : "s") before increasing",
                    color: TFColor.accent
                )
            }

            if setsBelowRange > 0 && setsBelowRange == totalWorking {
                return ProgressionSuggestion(
                    icon: "arrow.down.circle.fill",
                    text: "Stay at \(formatWeight(lastWeight)) lb, focus on form and full ROM",
                    color: TFColor.warning
                )
            }

            if setsInRange == totalWorking && setsAtOrAboveTop == 0 {
                let minReps = workingSets.map(\.repsCompleted).min() ?? repRange.low
                return ProgressionSuggestion(
                    icon: "arrow.right.circle.fill",
                    text: "On track — build all sets to \(repRange.high) reps (lowest was \(minReps))",
                    color: TFColor.info
                )
            }

            let avgReps = workingSets.map(\.repsCompleted).reduce(0, +) / max(1, totalWorking)
            if avgReps < repRange.low {
                return ProgressionSuggestion(
                    icon: "arrow.down.circle.fill",
                    text: "Stay at \(formatWeight(lastWeight)) lb, focus on form and full ROM",
                    color: TFColor.warning
                )
            }

            return ProgressionSuggestion(
                icon: "arrow.right.circle.fill",
                text: "On track — aim for \(repRange.high) reps across all sets",
                color: .blue
            )
        }

        guard let repsCompleted = summaryRepsCompleted else { return nil }

        if repsCompleted >= repRange.high {
            let suggestedWeight = lastWeight + increment
            return ProgressionSuggestion(
                icon: "arrow.up.circle.fill",
                text: "Increase to \(formatWeight(suggestedWeight)) lb next session",
                color: TFColor.success
            )
        }

        if repsCompleted < repRange.low {
            return ProgressionSuggestion(
                icon: "arrow.down.circle.fill",
                text: "Stay at \(formatWeight(lastWeight)) lb, focus on form and full ROM",
                color: .yellow
            )
        }

        return ProgressionSuggestion(
            icon: "arrow.right.circle.fill",
            text: "On track — aim for \(repsCompleted + 1)-\(repRange.high) reps next session",
            color: .blue
        )
    }

    private static func formatWeight(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}

struct ProgressionSuggestionBadge: View {
    let suggestion: ProgressionSuggestion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: suggestion.icon)
                .font(.caption2)
                .foregroundStyle(suggestion.color)
            Text(suggestion.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(suggestion.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
