import SwiftUI
import SwiftData

// The 3-tap wake-time sleep composer.
//
// Design contract (owner-approved): every tap is a REPORT, never a confirmation of a
// prefilled guess. Duration, quality, and shift context are each one honest tap:
//  * duration chips center on the owner's own recent median (not a fixed 7h),
//  * quality keeps the full 1-5 scale the trend math depends on,
//  * shift chips are all visible with the *predicted* one listed first and hinted —
//    but never preselected, because for shift work the transition days (post-call,
//    night flip) are exactly where yesterday's value is most wrong.
// The full SleepEntryEditor remains the exception path (naps, post-call recovery,
// exact times, notes, edits). A future HealthKit import can replace the duration row
// with sensor data and shrink this to the two chips sensors can't answer.

struct SleepQuickLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SleepEntry.date, order: .reverse) private var episodes: [SleepEntry]

    /// Invoked when the user needs the full episode editor instead — with the
    /// existing episode to edit, or nil for a blank editor.
    let onOpenFullEditor: (SleepEntry?) -> Void

    @State private var selectedDuration: Double?
    @State private var selectedQuality: Int?
    @State private var selectedShift: SleepShiftType?
    @State private var overlapMessage = ""
    @State private var showOverlapAlert = false

    private static let qualityLabels = [1: "Terrible", 2: "Poor", 3: "Okay", 4: "Good", 5: "Excellent"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let existing = existingMainSleepOnCreditedDay {
                        alreadyLoggedNotice(for: existing)
                    }

                    chipSection(title: "How long did you sleep?") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(durationChoices, id: \.self) { hours in
                                    quickChip(
                                        label: SleepFormatting.duration(hours),
                                        isSelected: selectedDuration == hours
                                    ) { selectedDuration = hours }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }

                    chipSection(title: "How did it feel?") {
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { rating in
                                quickChip(
                                    label: "\(rating)",
                                    caption: Self.qualityLabels[rating],
                                    isSelected: selectedQuality == rating
                                ) { selectedQuality = rating }
                            }
                        }
                    }

                    chipSection(title: "Shift context") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(orderedShiftChoices) { shift in
                                quickChip(
                                    label: shift.rawValue,
                                    caption: shift == predictedShift ? "likely" : nil,
                                    isSelected: selectedShift == shift
                                ) { selectedShift = shift }
                            }
                        }
                    }

                    Button {
                        dismiss()
                        onOpenFullEditor(nil)
                    } label: {
                        Label("Exact times, naps & post-call…", systemImage: "slider.horizontal.3")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TFColor.sleep)

                    Text(saveExplanation)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .navigationTitle("Log Last Night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(
                            selectedDuration == nil || selectedQuality == nil || selectedShift == nil
                                || existingMainSleepOnCreditedDay != nil
                        )
                }
            }
            .alert("Overlapping Sleep Episode", isPresented: $showOverlapAlert) {
                Button("Open Full Editor") {
                    dismiss()
                    onOpenFullEditor(nil)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(overlapMessage)
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Wake-day crediting & double-log guard

    /// The wake-day this quick log would be credited to (yesterday when it is
    /// shortly after midnight — see SleepQuickLogPolicy).
    private var creditedWakeDayStart: Date {
        SleepQuickLogPolicy.creditedWakeDayStart(loggedAt: .now)
    }

    private var creditsPreviousWakeDay: Bool {
        creditedWakeDayStart < Calendar.current.startOfDay(for: .now)
    }

    /// A main sleep already recorded for the credited wake-day. Saving a second
    /// one would double-count the day (e.g. a 14h phantom day hiding a real
    /// restriction), so the sheet blocks it and routes to editing instead.
    private var existingMainSleepOnCreditedDay: SleepEntry? {
        let dayStart = creditedWakeDayStart
        return episodes.first {
            $0.episodeType == .mainSleep
                && Calendar.current.startOfDay(for: $0.resolvedEndDate) == dayStart
        }
    }

    private var saveExplanation: String {
        creditsPreviousWakeDay
            ? "It's after midnight, so this counts for yesterday — the sleep you woke from yesterday morning. Logging tonight's sleep? Wait until you wake up, or use the full editor."
            : "Saved as a main sleep ending now. Use the full editor for anything that ended earlier."
    }

    private func alreadyLoggedNotice(for existing: SleepEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                creditsPreviousWakeDay
                    ? "Yesterday already has a main sleep"
                    : "Today already has a main sleep",
                systemImage: "checkmark.circle.fill"
            )
            .font(.subheadline.bold())
            Text("\(SleepFormatting.duration(existing.resolvedDurationHours)) ending \(existing.resolvedEndDate.formatted(date: .abbreviated, time: .shortened)). Logging it twice would double-count the day, so edit that entry — or add naps and post-call sleep in the full editor.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                dismiss()
                onOpenFullEditor(existing)
            } label: {
                Label("Edit that entry", systemImage: "pencil")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(TFColor.sleep)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TFColor.sleep.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Choices

    /// Recent main-sleep episodes (14 days) used for the personal anchor and prediction.
    private var recentMainSleeps: [SleepEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        return episodes.filter { $0.episodeType == .mainSleep && $0.resolvedEndDate >= cutoff }
    }

    /// Duration chips centered on the owner's recent median main sleep (fallback 7h),
    /// half-hour steps, ±1.5h — so the common case is a single obvious tap.
    private var durationChoices: [Double] {
        let durations = recentMainSleeps.map(\.resolvedDurationHours).sorted()
        let median: Double
        if durations.isEmpty {
            median = 7.0
        } else if durations.count % 2 == 1 {
            median = durations[durations.count / 2]
        } else {
            median = (durations[durations.count / 2 - 1] + durations[durations.count / 2]) / 2
        }
        let anchor = min(max((median * 2).rounded() / 2, 5.5), 8.5)
        return stride(from: anchor - 1.5, through: anchor + 1.5, by: 0.5).map { $0 }
    }

    /// Most common shift context over the recent window (most recent wins ties).
    private var predictedShift: SleepShiftType {
        let recents = recentMainSleeps
        guard !recents.isEmpty else { return .off }
        var counts: [SleepShiftType: Int] = [:]
        for episode in recents {
            counts[episode.shiftType, default: 0] += 1
        }
        let best = counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            let lhsLatest = recents.first { $0.shiftType == lhs.key }?.resolvedEndDate ?? .distantPast
            let rhsLatest = recents.first { $0.shiftType == rhs.key }?.resolvedEndDate ?? .distantPast
            return lhsLatest < rhsLatest
        }
        return best?.key ?? .off
    }

    /// All shift contexts, predicted first — visible options, no preselection.
    private var orderedShiftChoices: [SleepShiftType] {
        let predicted = predictedShift
        return [predicted] + SleepShiftType.allCases.filter { $0 != predicted }
    }

    // MARK: - Save

    private func save() {
        guard let selectedDuration, let selectedQuality, let selectedShift else { return }
        // Re-checked at save time (not just render time): the sheet can sit open
        // across the midnight/cutoff boundary or a background sync.
        guard existingMainSleepOnCreditedDay == nil else { return }
        let end = SleepQuickLogPolicy.quickLogEnd(loggedAt: .now)
        let start = end.addingTimeInterval(-selectedDuration * 3600)

        if let conflict = episodes.first(where: { start < $0.resolvedEndDate && end > $0.resolvedStartDate }) {
            overlapMessage = "This overlaps the \(conflict.episodeType.rawValue.lowercased()) logged \(conflict.resolvedEndDate.formatted(date: .abbreviated, time: .shortened)). Use the full editor to set exact times."
            showOverlapAlert = true
            return
        }

        modelContext.insert(
            SleepEntry(
                startDate: start,
                endDate: end,
                qualityRating: selectedQuality,
                shiftType: selectedShift,
                episodeType: .mainSleep
            )
        )
        guard PersistenceReporter.save(modelContext, operation: "quick sleep log") else {
            modelContext.rollback()
            return
        }
        SleepTrendStore.refresh(using: modelContext)
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        dismiss()
    }

    // MARK: - Chip building blocks

    private func chipSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func quickChip(
        label: String,
        caption: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(label)
                    .font(.subheadline.bold())
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minWidth: 44)
            .background(isSelected ? TFColor.sleep : TFColor.sleep.opacity(0.12))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
