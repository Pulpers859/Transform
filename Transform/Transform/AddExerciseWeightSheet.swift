import SwiftUI
import SwiftData

struct AddExerciseWeightSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: EntryField?

    let exercise: WorkoutExercise
    let weightSummary: ExerciseWeightEntry?
    var latestSetLogs: [SetLogEntry] = []
    var sessionSetLogs: [SetLogEntry] = []

    @State private var setLogs: [SetLogDraft] = []
    @State private var notes = ""
    @State private var loggedAt = Date()
    @State private var didSave = false

    private let quickAdjustments: [Double] = [-10, -5, -2.5, 2.5, 5, 10]

    struct SetLogDraft: Identifiable {
        let id = UUID()
        var setNumber: Int
        var weightText: String
        var repsText: String
        var rirText: String
        /// Machine assistance of the stored set this row came from (`SessionSetSheetRules.Row`).
        var assistLbs: Double? = nil
    }

    enum EntryField: Hashable {
        case weight(Int)
        case reps(Int)
        case rir(Int)
        case notes
    }

    /// What a save would store, under the rules both whole-session sheets share
    /// (`SessionSetSheetRules`): a row it cannot read blocks the save instead of being dropped.
    var sheetOutcome: SessionSetSheetRules.Outcome {
        SessionSetSheetRules.evaluate(setLogs.map {
            SessionSetSheetRules.Row(setNumber: $0.setNumber, weightText: $0.weightText,
                                     repsText: $0.repsText, rirText: $0.rirText, assistLbs: $0.assistLbs)
        })
    }

    var canSave: Bool {
        sheetOutcome.canSave
    }

    var isKeyboardActive: Bool {
        focusedField != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        exerciseCard
                        if let weightSummary {
                            targetsCard(summary: weightSummary)
                        }
                        setEntryCards
                        notesAndDateCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, isKeyboardActive ? 24 : 120)
                }
            }
            .navigationTitle("Edit Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveEntry() }
                        .bold()
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Save") { saveEntry() }
                        .bold()
                        .disabled(!canSave)
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardActive {
                    bottomSaveBar
                }
            }
            .animation(.easeOut(duration: 0.2), value: isKeyboardActive)
            .onAppear { initializeSets() }
        }
    }

    // MARK: - Exercise Header

    var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Exercise")

            Text(exercise.exerciseName)
                .font(.title3.bold())

            HStack(spacing: 8) {
                metricChip(icon: "square.stack.3d.up", text: setsLabel(exercise.sets))
                metricChip(icon: "arrow.left.arrow.right", text: "\(exercise.reps) target")
                if !exercise.muscleTarget.isEmpty {
                    metricChip(icon: "target", text: exercise.muscleTarget)
                }
            }
        }
        .padding(16)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Targets

    func targetsCard(summary: ExerciseWeightEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Targets")

            HStack(spacing: 0) {
                summarySegment(
                    title: "Last",
                    weight: summary.weightLbs,
                    reps: summary.repsCompleted,
                    date: summary.loggedAt,
                    accent: .orange
                ) {
                    applyWeightToAll(summary.weightLbs, reps: summary.repsCompleted)
                }

                Divider()
                    .padding(.vertical, 14)

                summarySegment(
                    title: "Best",
                    weight: resolvedBestWeight(from: summary),
                    reps: resolvedBestReps(from: summary),
                    date: resolvedBestDate(from: summary),
                    accent: TFColor.success
                ) {
                    applyWeightToAll(resolvedBestWeight(from: summary), reps: resolvedBestReps(from: summary))
                }
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
        }
        .padding(16)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    func summarySegment(
        title: String,
        weight: Double,
        reps: Int?,
        date: Date?,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(TFTypography.sectionTitle)
                    .foregroundStyle(accent)
                    .tracking(1.5)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatWeight(weight))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("lb")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }

                Text(reps.map { "\($0) reps" } ?? "Reps not logged")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(date?.formatted(date: .abbreviated, time: .shortened) ?? "No date")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("Tap to fill all sets")
                    .font(.caption2.bold())
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Set Entry Cards

    var setEntryCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("Sets")
                Spacer()
                Button {
                    addSet()
                } label: {
                    Label("Add Set", systemImage: "plus.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(setLogs.enumerated()), id: \.element.id) { index, draft in
                setRow(index: index, draft: draft)
            }

            if setLogs.count > 1 {
                HStack(spacing: 12) {
                    Button {
                        copyFirstSetToAll()
                    } label: {
                        Label("Copy Set 1 to all", systemImage: "doc.on.doc")
                            .font(.caption.bold())
                            .foregroundStyle(TFColor.accent)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if setLogs.count > exercise.sets {
                        Button {
                            removeLastSet()
                        } label: {
                            Label("Remove last", systemImage: "minus.circle")
                                .font(.caption.bold())
                                .foregroundStyle(TFColor.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(16)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    func setRow(index: Int, draft: SetLogDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Set \(draft.setNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(TFColor.accent)
                    .frame(width: 44, alignment: .leading)

                HStack(spacing: 4) {
                    TextField("0", text: $setLogs[index].weightText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight(index))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .frame(minWidth: 50)
                    Text("lb")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))

                quickAdjustButton(index: index)

                Text("\u{00D7}")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)

                HStack(spacing: 4) {
                    TextField("0", text: $setLogs[index].repsText)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .reps(index))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .frame(minWidth: 30)
                    Text("reps")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
            }

            HStack(spacing: 8) {
                if let assist = draft.assistLbs {
                    // Shown so an assisted set never reads as plain "BW" here. Kept on save
                    // while the weight stays bodyweight (`SessionSetSheetRules.Row.assistLbs`).
                    Text("Assisted · \(formatWeight(assist)) lb help")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Optional RIR")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                TextField("—", text: $setLogs[index].rirText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .rir(index))
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .padding(.vertical, 7)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
            }
        }
    }

    func quickAdjustButton(index: Int) -> some View {
        Menu {
            ForEach(quickAdjustments, id: \.self) { delta in
                Button {
                    nudgeSetWeight(at: index, by: delta)
                } label: {
                    Text(delta > 0 ? "+\(formatWeight(delta))" : "\(formatWeight(delta))")
                }
            }
        } label: {
            Image(systemName: "plusminus")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(8)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())
        }
    }

    // MARK: - Notes & Date

    var notesAndDateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("When")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                DatePicker(
                    "Logged at",
                    selection: $loggedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Notes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                TextField("Optional cue, machine setting, or effort note", text: $notes, axis: .vertical)
                    .focused($focusedField, equals: .notes)
                    .lineLimit(2...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(16)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Bottom Bar

    var bottomSaveBar: some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saveSummaryText)
                        .font(.headline)
                        .foregroundStyle(topLoadLooksImplausible ? TFColor.warning : .primary)
                    Text("\(validSetCount) of \(setLogs.count) sets logged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    saveEntry()
                } label: {
                    Text("Save Sets")
                        .font(.headline.bold())
                        .frame(minWidth: 120)
                        .padding(.vertical, 14)
                        .background(canSave ? TFColor.accent : TFColor.accent.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.card))
                }
                .pressable()
                .disabled(!canSave)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    var validSetCount: Int {
        sheetOutcome.sets.filter { $0.repsCompleted > 0 }.count
    }

    /// The heaviest entry currently drafted, if it is one at all.
    var draftTopSet: (weight: Double, reps: Int)? {
        sheetOutcome.sets.filter { $0.repsCompleted > 0 }
            .map { (weight: $0.weightLbs, reps: $0.repsCompleted) }
            .max(by: { $0.weight < $1.weight })
    }

    /// Caught here, before the save, rather than only in the card afterwards — this sheet is
    /// where the number is typed, and an entry saved from here becomes the stored best and
    /// the next session's target the moment it lands.
    var topLoadLooksImplausible: Bool {
        WorkingSetAnalysis.isImplausibleLoad(draftTopSet?.weight ?? 0)
    }

    var saveSummaryText: String {
        if let blocking = SessionSetSheetRules.blockingMessage(for: sheetOutcome) { return blocking }
        guard let top = draftTopSet else { return "Enter weight to save" }
        if topLoadLooksImplausible {
            return "\(formatWeight(top.weight)) lb — check this entry"
        }
        return "\(formatLoad(top.weight)) \u{00D7} \(top.reps) top set"
    }

    // MARK: - Actions

    /// The log already holding this card's session, if any.
    ///
    /// Resolved through `SetLoggingService` so the sheet and the inline logger cannot disagree
    /// about which log belongs to this card. They used to: this sheet matched on its own date
    /// field while the inline logger matched on today, so the two could write to different rows
    /// for the same exercise on the same day.
    func resolvedSessionLog(on date: Date = .now) -> ExercisePerformanceLog? {
        let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
        let dayNumber = exercise.day?.dayNumber ?? 0
        let descriptor = FetchDescriptor<ExercisePerformanceLog>(
            predicate: #Predicate { $0.canonicalExerciseKey == key && $0.workoutDayNumber == dayNumber }
        )
        let storedLogs = (try? modelContext.fetch(descriptor)) ?? []
        return SetLoggingService.sessionLog(for: exercise, among: storedLogs, on: date)
    }

    func initializeSets() {
        guard setLogs.isEmpty else { return }

        // Default the date to when this work happened, not to now. Reached from a day trained
        // last week ("Log what you did"), a today-stamped save would file that work under
        // today's date and leave a second session hanging off the same program day.
        //
        // An already-recorded session's OWN date wins over the day's stamps, and both win over
        // now. Without the first branch a day that predates the session clock — no stamps at all
        // — would keep the `.now` default, and since the save path overwrites `loggedAt`
        // unconditionally (the date picker below is a deliberate user choice and must be
        // honoured), merely opening this sheet on such a day and saving would drag a
        // weeks-old session forward to today.
        if let existing = resolvedSessionLog() {
            loggedAt = existing.loggedAt
        } else if let sessionDate = exercise.day?.sessionCalendarDates.first {
            loggedAt = sessionDate
        }

        // Resume the session already in progress if it exists, so the sheet shows the sets
        // already logged (e.g. via the inline logger) instead of overwriting them on save.
        if !sessionSetLogs.isEmpty {
            setLogs = sessionSetLogs
                .sorted { $0.setNumber < $1.setNumber }
                .map {
                    SetLogDraft(
                        setNumber: $0.setNumber,
                        weightText: SessionSetSheetRules.weightText(for: $0.weightLbs),
                        repsText: "\($0.repsCompleted)",
                        rirText: $0.rir.map(SessionSetSheetRules.rirText(for:)) ?? "",
                        assistLbs: $0.assistLbs
                    )
                }
            return
        }

        let count = max(exercise.sets, 1)
        // Seed from the representative working set, not the heaviest logged set, so a
        // prior anomaly or warm-up ramp does not pre-fill an unintended load.
        let analysis = WorkingSetAnalysis.analyze(latestSetLogs)
        let prefillWeight = analysis.workingWeight ?? weightSummary?.weightLbs
        let prefillReps = analysis.topWorkingSet?.reps ?? weightSummary?.repsCompleted

        // Last session done on the assistance machine: start this session assisted at the
        // same setting, so logging it here cannot quietly store it as plain bodyweight. The
        // setting itself is changed in the set logger, which has the Assisted switch.
        if AssistedProgression.supportsAssistance(exercise.exerciseName),
           let assisted = AssistedProgression.workingSets(latestSetLogs) {
            let reps = assisted.sets.map(\.repsCompleted).max()
            setLogs = (1...count).map { num in
                SetLogDraft(setNumber: num, weightText: SessionSetSheetRules.weightText(for: 0),
                            repsText: reps.map { String($0) } ?? "", rirText: "", assistLbs: assisted.assist)
            }
            return
        }

        setLogs = (1...count).map { num in
            SetLogDraft(
                setNumber: num,
                weightText: prefillWeight.map { SessionSetSheetRules.weightText(for: $0) } ?? "",
                repsText: prefillReps.map { String($0) } ?? "",
                rirText: ""
            )
        }
    }

    func addSet() {
        let nextNum = (setLogs.last?.setNumber ?? 0) + 1
        let lastWeight = setLogs.last?.weightText ?? ""
        let lastReps = setLogs.last?.repsText ?? ""
        // Carries the assistance with the copied text, or an added assisted set would be
        // stored as plain bodyweight.
        setLogs.append(SetLogDraft(setNumber: nextNum, weightText: lastWeight, repsText: lastReps, rirText: "",
                                   assistLbs: setLogs.last?.assistLbs))
    }

    func removeLastSet() {
        guard setLogs.count > 1 else { return }
        setLogs.removeLast()
    }

    func copyFirstSetToAll() {
        guard let first = setLogs.first else { return }
        for i in setLogs.indices {
            setLogs[i].weightText = first.weightText
            setLogs[i].repsText = first.repsText
            setLogs[i].rirText = first.rirText
            setLogs[i].assistLbs = first.assistLbs
        }
    }

    func applyWeightToAll(_ weight: Double, reps: Int?) {
        for i in setLogs.indices {
            setLogs[i].weightText = formatWeight(weight)
            setLogs[i].repsText = reps.map { String($0) } ?? ""
        }
    }

    func nudgeSetWeight(at index: Int, by delta: Double) {
        let base = SessionSetSheetRules.weight(from: setLogs[index].weightText) ?? weightSummary?.weightLbs ?? 0
        let updated = max(0, base + delta)
        guard updated > 0 else { return }
        setLogs[index].weightText = formatWeight(updated)
    }

    func saveEntry() {
        // Every non-empty row must be readable: this save overwrites the session's whole set
        // list, so a row left out here is a set deleted from history.
        let outcome = sheetOutcome
        guard outcome.canSave else { return }
        let validSets = outcome.sets
        // Guard against a fast double-tap inserting duplicate logs before dismiss.
        guard !didSave else { return }
        didSave = true

        // Best/summary load comes from the qualified working set so a lone anomalous set
        // cannot become a false PR. Raw per-set data is still preserved in setLogs below.
        let top = WorkingSetAnalysis.summaryTop(from: validSets)
        let topWeight = top?.weightLbs ?? validSets[0].weightLbs
        let topReps = top?.reps
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Resume the session already recorded for this card if one exists (e.g. started via the
        // inline logger) instead of inserting a duplicate log for the same exercise and day.
        if let existing = resolvedSessionLog(on: loggedAt) {
            existing.loggedAt = loggedAt
            existing.weightLbs = topWeight
            existing.repsCompleted = topReps
            existing.notes = trimmedNotes
            existing.muscleTarget = exercise.muscleTarget
            existing.setLogsJSON = ExercisePerformanceLog.encodeSetLogs(validSets)
            // Backfill only, matching the inline logger: a session that already recorded
            // its prescription keeps it, so resuming or correcting an older session never
            // restamps it with today's programming.
            if existing.recordedPrescribedSets == nil {
                existing.prescribedSets = exercise.sets
            }
            if existing.prescribedReps.isEmpty {
                existing.prescribedReps = exercise.reps
            }
            if existing.recordedTargetRIR == nil, let target = exercise.targetRIR {
                existing.prescribedTargetRIR = target
            }
        } else {
            let performanceLog = ExercisePerformanceLog(
                loggedAt: loggedAt,
                exerciseName: exercise.exerciseName,
                weightLbs: topWeight,
                repsCompleted: topReps,
                notes: trimmedNotes,
                muscleTarget: exercise.muscleTarget,
                workoutDayNumber: exercise.day?.dayNumber ?? 0,
                prescribedSets: exercise.sets,
                prescribedReps: exercise.reps,
                prescribedTargetRIR: exercise.targetRIR,
                setLogs: validSets
            )
            modelContext.insert(performanceLog)
        }

        // The Last/Best summary is built from unassisted sets only
        // (`ExercisePerformanceLog.summarySetLogs`); an all-assisted session leaves it alone.
        let summarySets = AssistedProgression.summarySets(validSets)
        let summaryTop = WorkingSetAnalysis.summaryTop(from: summarySets)
        if let summaryWeight = summaryTop?.weightLbs ?? summarySets.first?.weightLbs {
            let summaryReps = summaryTop?.reps
            if let weightSummary {
                weightSummary.applyLog(
                    loggedAt: loggedAt,
                    exerciseName: exercise.exerciseName,
                    weightLbs: summaryWeight,
                    repsCompleted: summaryReps,
                    notes: trimmedNotes
                )
            } else {
                let entry = ExerciseWeightEntry(
                    loggedAt: loggedAt,
                    exerciseName: exercise.exerciseName,
                    weightLbs: summaryWeight,
                    repsCompleted: summaryReps,
                    notes: trimmedNotes
                )
                modelContext.insert(entry)
            }
        }

        // This sheet writes performance logs directly instead of going through
        // SetLoggingService, so it has to advance the session clock itself — otherwise
        // work logged here is invisible to the session timer and the recorded duration
        // stops at whatever was last entered in the inline logger.
        SessionLifecycle.noteSetLogged(for: exercise, at: loggedAt)

        guard PersistenceReporter.save(modelContext, operation: "exercise set logging") else {
            modelContext.rollback()
            didSave = false
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        TFHaptics.success()
        dismiss()
    }

    // MARK: - Helpers

    func resolvedBestWeight(from summary: ExerciseWeightEntry) -> Double {
        summary.hasBestRecord ? summary.bestWeightLbs : summary.weightLbs
    }

    func resolvedBestDate(from summary: ExerciseWeightEntry) -> Date? {
        summary.bestLoggedAt ?? summary.loggedAt
    }

    func resolvedBestReps(from summary: ExerciseWeightEntry) -> Int? {
        summary.bestRepsCompleted ?? summary.repsCompleted
    }

    func formatRIR(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    func sectionLabel(_ text: String) -> some View {
        TFSectionLabel(text: text)
    }

    func metricChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(TFColor.accent.opacity(0.12))
        .foregroundStyle(TFColor.accent)
        .clipShape(Capsule())
    }

}
