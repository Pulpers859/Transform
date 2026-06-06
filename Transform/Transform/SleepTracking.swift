import Foundation
import SwiftData
import SwiftUI
import Charts

enum SleepShiftType: String, CaseIterable, Identifiable {
    case day = "Day Shift"
    case night = "Night Shift"
    case postCall = "Post-Call"
    case off = "Off / No Shift"

    var id: String { rawValue }
}

enum SleepFormatting {
    static func duration(_ hours: Double) -> String {
        let totalMinutes = Int(round(hours * 60))
        let wholeHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(wholeHours)h" : "\(wholeHours)h \(minutes)m"
    }
}

struct SleepTrendSnapshot {
    let entries: [SleepEntry]
    let averageHours: Double
    let averageQuality: Double
    let variabilityHours: Double
    let shortSleepDays: Int

    var loggedDays: Int { entries.count }

    var promptSummary: String {
        guard !entries.isEmpty else { return "" }
        let shiftCounts = Dictionary(grouping: entries, by: \.shiftType).mapValues(\.count)
        let shiftText = shiftCounts
            .sorted { $0.value > $1.value }
            .map { "\($0.key.rawValue): \($0.value)" }
            .joined(separator: ", ")
        return String(
            format: "Dated sleep log, last 7 days: %.1f hours average across %d logged days, average quality %.1f/5, day-to-day variability %.1f hours, %d night(s) under 6 hours. Shift context: %@.",
            averageHours,
            loggedDays,
            averageQuality,
            variabilityHours,
            shortSleepDays,
            shiftText
        )
    }
}

enum SleepTrendBuilder {
    static func build(from allEntries: [SleepEntry], now: Date = .now) -> SleepTrendSnapshot? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let recent = allEntries
            .filter { $0.date >= cutoff && $0.date < tomorrow }
            .sorted { $0.date < $1.date }
        guard !recent.isEmpty else { return nil }

        let durations = recent.map(\.durationHours)
        let averageHours = durations.reduce(0, +) / Double(durations.count)
        let variance = durations
            .map { pow($0 - averageHours, 2) }
            .reduce(0, +) / Double(durations.count)
        let qualities = recent.map { Double($0.qualityRating) }

        return SleepTrendSnapshot(
            entries: recent,
            averageHours: averageHours,
            averageQuality: qualities.reduce(0, +) / Double(qualities.count),
            variabilityHours: sqrt(variance),
            shortSleepDays: recent.filter { $0.durationHours < 6 }.count
        )
    }
}

enum SleepTrendStore {
    static var currentSummary: String {
        UserDefaults.standard.string(forKey: AppSettingsKeys.derivedSleepTrendSummary) ?? ""
    }

    static func refresh(using modelContext: ModelContext) {
        do {
            let entries = try modelContext.fetch(FetchDescriptor<SleepEntry>())
            let summary = SleepTrendBuilder.build(from: entries)?.promptSummary ?? ""
            UserDefaults.standard.set(summary, forKey: AppSettingsKeys.derivedSleepTrendSummary)
        } catch {
            print("[SleepTrend] Could not refresh derived sleep context: \(error.localizedDescription)")
        }
    }
}

struct SleepEditorRequest: Identifiable {
    let id = UUID()
    let entry: SleepEntry?
}

struct SleepEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SleepEntry.date, order: .reverse) private var sleepEntries: [SleepEntry]

    let entry: SleepEntry?

    @State private var selectedDate = Date()
    @State private var hours = 7.0
    @State private var quality = 3
    @State private var shiftType = SleepShiftType.off
    @State private var notes = ""
    @State private var conflictingEntry: SleepEntry?
    @FocusState private var notesFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Sleep date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text(SleepFormatting.duration(hours))
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                        Slider(value: $hours, in: 0.5...16, step: 0.25)
                            .tint(.blue)
                    }

                    Picker("Sleep quality", selection: $quality) {
                        Text("1 - Very poor").tag(1)
                        Text("2 - Poor").tag(2)
                        Text("3 - Fair").tag(3)
                        Text("4 - Good").tag(4)
                        Text("5 - Excellent").tag(5)
                    }

                    Picker("Shift context", selection: $shiftType) {
                        ForEach(SleepShiftType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                } header: {
                    Text("Sleep")
                } footer: {
                    Text("Use the date you woke from the main sleep period. Naps can be mentioned in the note.")
                }

                Section("Optional Note") {
                    TextField("Awakenings, nap, unusual fatigue...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($notesFocused)
                }

                if conflictingEntry != nil {
                    Section {
                        Label(
                            entry == nil
                                ? "An entry already exists for this date. Saving will update it."
                                : "An entry already exists for this date. Saving will merge into that date and remove the original entry.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(entry == nil ? "Log Sleep" : "Edit Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { notesFocused = false }
                }
            }
            .onAppear {
                if let entry {
                    selectedDate = entry.date
                    hours = entry.durationHours
                    quality = entry.qualityRating
                    shiftType = entry.shiftType
                    notes = entry.notes
                } else {
                    selectedDate = Calendar.current.startOfDay(for: .now)
                    syncConflict()
                }
            }
            .onChange(of: selectedDate) { _, _ in syncConflict() }
        }
    }

    private func syncConflict() {
        let target = Calendar.current.startOfDay(for: selectedDate)
        conflictingEntry = sleepEntries.first { candidate in
            if let entry, candidate === entry { return false }
            return Calendar.current.isDate(candidate.date, inSameDayAs: target)
        }
        guard entry == nil, let conflictingEntry else { return }
        hours = conflictingEntry.durationHours
        quality = conflictingEntry.qualityRating
        shiftType = conflictingEntry.shiftType
        notes = conflictingEntry.notes
    }

    private func save() {
        let target = conflictingEntry ?? entry
        let normalizedDate = Calendar.current.startOfDay(for: selectedDate)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let target {
            target.date = normalizedDate
            target.durationHours = hours
            target.qualityRating = quality
            target.shiftType = shiftType
            target.notes = trimmedNotes
            if let entry, target !== entry {
                modelContext.delete(entry)
            }
        } else {
            modelContext.insert(
                SleepEntry(
                    date: normalizedDate,
                    durationHours: hours,
                    qualityRating: quality,
                    shiftType: shiftType,
                    notes: trimmedNotes
                )
            )
        }

        guard PersistenceReporter.save(modelContext, operation: "sleep entry") else {
            modelContext.rollback()
            return
        }
        SleepTrendStore.refresh(using: modelContext)
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        dismiss()
    }
}

struct SleepHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SleepEntry.date, order: .reverse) private var sleepEntries: [SleepEntry]

    @State private var editorRequest: SleepEditorRequest?
    @State private var entryToDelete: SleepEntry?

    var body: some View {
        List {
            if sleepEntries.isEmpty {
                ContentUnavailableView(
                    "No Sleep Entries",
                    systemImage: "bed.double",
                    description: Text("Log sleep from the Dashboard to begin seeing recovery trends.")
                )
            } else {
                ForEach(sleepEntries) { entry in
                    Button {
                        editorRequest = SleepEditorRequest(entry: entry)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.subheadline.bold())
                                Text("\(entry.shiftType.rawValue) · Quality \(entry.qualityRating)/5")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !entry.notes.isEmpty {
                                    Text(entry.notes)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(SleepFormatting.duration(entry.durationHours))
                                .font(.title3.bold())
                                .foregroundStyle(.blue)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            entryToDelete = entry
                        }
                    }
                }
            }
        }
        .navigationTitle("Sleep History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRequest = SleepEditorRequest(entry: nil)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .sheet(item: $editorRequest) { request in
            SleepEntryEditor(entry: request.entry)
        }
        .alert("Delete Sleep Entry?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { deleteEntry() }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("This removes the entry from sleep trends and future analysis context.")
        }
    }

    private func deleteEntry() {
        guard let entryToDelete else { return }
        modelContext.delete(entryToDelete)
        guard PersistenceReporter.save(modelContext, operation: "sleep entry deletion") else {
            modelContext.rollback()
            return
        }
        SleepTrendStore.refresh(using: modelContext)
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        self.entryToDelete = nil
    }
}
