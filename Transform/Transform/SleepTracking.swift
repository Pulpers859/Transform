import Foundation
import SwiftData
import SwiftUI

enum SleepEpisodeType: String, CaseIterable, Identifiable {
    case mainSleep = "Main Sleep"
    case nap = "Nap"
    case recoverySleep = "Post-Call Recovery"

    var id: String { rawValue }
}

enum SleepShiftType: String, CaseIterable, Identifiable {
    case day = "Day Shift"
    case night = "Night Shift"
    case onCall = "On Call"
    case postNight = "Post-Night Shift"
    case postCall = "Post-Call"
    case disrupted = "Travel / Disrupted"
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

struct DailySleepSummary: Identifiable {
    let date: Date
    let episodes: [SleepEntry]
    let totalHours: Double
    let mainSleepHours: Double
    let napHours: Double
    let averageQuality: Double

    var id: Date { date }
}

struct SleepTrendSnapshot {
    let days: [DailySleepSummary]
    let sevenDayAverageHours: Double
    let threeDayAverageHours: Double
    let averageQuality: Double
    let variabilityHours: Double
    let underSixHours: Int
    let underFiveHours: Int
    let qualityDurationMismatchDays: Int
    let hasRecentPostCallRecovery: Bool
    let shiftCounts: [SleepShiftType: Int]
    let acuteLoggedDays: Int

    var loggedDays: Int { days.count }

    /// The structured, dated form of this snapshot consumed by the workout generator's
    /// recovery modulation (see RecoveryState.swift).
    func recoveryState(builtAt: Date = .now) -> SleepRecoveryState {
        SleepRecoveryState(
            builtAt: builtAt,
            threeDayAverageHours: threeDayAverageHours,
            sevenDayAverageHours: sevenDayAverageHours,
            acuteLoggedDays: acuteLoggedDays,
            loggedDays: loggedDays,
            daysUnderFive: underFiveHours,
            daysUnderSix: underSixHours,
            variabilityHours: variabilityHours,
            recentPostCall: hasRecentPostCallRecovery
        )
    }

    var variabilityLabel: String {
        switch variabilityHours {
        case ..<0.75: return "Low"
        case ..<1.5: return "Moderate"
        default: return "High"
        }
    }

    var promptSummary: String {
        guard !days.isEmpty else { return "" }
        let shiftText = shiftCounts
            .sorted { $0.value > $1.value }
            .map { "\($0.key.rawValue): \($0.value)" }
            .joined(separator: ", ")
        let mismatchText = qualityDurationMismatchDays > 0
            ? " \(qualityDurationMismatchDays) day(s) had duration-quality mismatch, so do not infer recovery from hours alone."
            : ""
        let postCallText = hasRecentPostCallRecovery
            ? " A post-call recovery episode occurred within the last 3 days."
            : ""
        let acuteText = acuteLoggedDays > 0
            ? String(format: "3-day average %.1f hours across %d logged day(s)", threeDayAverageHours, acuteLoggedDays)
            : "3-day average unavailable because no recent days were logged"

        return String(
            format: "Dated sleep episodes aggregated by wake date: %@; 7-day average %.1f hours across %d logged days; quality %.1f/5; variability %.1f hours (%@); %d day(s) under 6 hours and %d under 5 hours. Shift context: %@.%@%@",
            acuteText,
            sevenDayAverageHours,
            loggedDays,
            averageQuality,
            variabilityHours,
            variabilityLabel,
            underSixHours,
            underFiveHours,
            shiftText,
            mismatchText,
            postCallText
        )
    }
}

enum SleepTrendBuilder {
    static func build(from episodes: [SleepEntry], now: Date = .now) -> SleepTrendSnapshot? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let recentEpisodes = episodes.filter {
            let wakeDate = $0.resolvedEndDate
            return wakeDate >= cutoff && wakeDate < tomorrow
        }

        let grouped = Dictionary(grouping: recentEpisodes) {
            calendar.startOfDay(for: $0.resolvedEndDate)
        }
        let days = grouped.map { date, dayEpisodes in
            let duration = dayEpisodes.reduce(0) { $0 + $1.resolvedDurationHours }
            let weightedQuality = dayEpisodes.reduce(0.0) {
                $0 + Double($1.qualityRating) * max($1.resolvedDurationHours, 0.25)
            } / max(dayEpisodes.reduce(0.0) { $0 + max($1.resolvedDurationHours, 0.25) }, 0.25)
            return DailySleepSummary(
                date: date,
                episodes: dayEpisodes.sorted { $0.resolvedStartDate < $1.resolvedStartDate },
                totalHours: duration,
                mainSleepHours: dayEpisodes
                    .filter { $0.episodeType == .mainSleep }
                    .reduce(0) { $0 + $1.resolvedDurationHours },
                napHours: dayEpisodes
                    .filter { $0.episodeType == .nap }
                    .reduce(0) { $0 + $1.resolvedDurationHours },
                averageQuality: weightedQuality
            )
        }
        .sorted { $0.date < $1.date }
        guard !days.isEmpty else { return nil }

        let totals = days.map(\.totalHours)
        let sevenDayAverage = totals.reduce(0, +) / Double(totals.count)
        let threeDayCutoff = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let acuteDays = days.filter { $0.date >= threeDayCutoff }
        let threeDayAverage = acuteDays.isEmpty
            ? 0
            : acuteDays.map(\.totalHours).reduce(0, +) / Double(acuteDays.count)
        let variance = totals.map { pow($0 - sevenDayAverage, 2) }.reduce(0, +) / Double(totals.count)
        let averageQuality = days.map(\.averageQuality).reduce(0, +) / Double(days.count)
        let qualityDurationMismatch = days.filter {
            ($0.totalHours >= 7 && $0.averageQuality <= 2) || ($0.totalHours < 6 && $0.averageQuality >= 4)
        }.count
        let recentPostCall = recentEpisodes.contains {
            $0.resolvedEndDate >= threeDayCutoff
                && ($0.episodeType == .recoverySleep || $0.shiftType == .postCall)
        }
        let shiftCounts = Dictionary(grouping: recentEpisodes, by: \.shiftType).mapValues(\.count)

        return SleepTrendSnapshot(
            days: days,
            sevenDayAverageHours: sevenDayAverage,
            threeDayAverageHours: threeDayAverage,
            averageQuality: averageQuality,
            variabilityHours: sqrt(variance),
            underSixHours: days.filter { $0.totalHours < 6 }.count,
            underFiveHours: days.filter { $0.totalHours < 5 }.count,
            qualityDurationMismatchDays: qualityDurationMismatch,
            hasRecentPostCallRecovery: recentPostCall,
            shiftCounts: shiftCounts,
            acuteLoggedDays: acuteDays.count
        )
    }
}

enum SleepTrendStore {
    static func refresh(using modelContext: ModelContext) {
        do {
            let episodes = try modelContext.fetch(FetchDescriptor<SleepEntry>())
            let snapshot = SleepTrendBuilder.build(from: episodes)
            UserDefaults.standard.set(
                snapshot?.promptSummary ?? "",
                forKey: AppSettingsKeys.derivedSleepTrendSummary
            )
            // Structured, dated companion to the prose summary. The generator's recovery
            // modulation reads ONLY this (never the prose), so a stale summary string can
            // no longer silently constrain future programs.
            if let encoded = snapshot?.recoveryState().encodedJSON() {
                UserDefaults.standard.set(encoded, forKey: AppSettingsKeys.derivedSleepRecoveryState)
            } else {
                UserDefaults.standard.removeObject(forKey: AppSettingsKeys.derivedSleepRecoveryState)
            }
        } catch {
            print("[SleepTrend] Could not refresh derived sleep context: \(error.localizedDescription)")
        }
    }
}

enum SleepEpisodeMigration {
    private static let migrationCompleteKey = "transform.sleepEpisodeMigrationV1Complete"

    static func migrateIfNeeded(using modelContext: ModelContext) throws {
        if UserDefaults.standard.bool(forKey: migrationCompleteKey) {
            return
        }
        let entries = try modelContext.fetch(FetchDescriptor<SleepEntry>())
        var changed = false
        for entry in entries where entry.startDate == nil || entry.endDate == nil {
            let proposedEnd = Calendar.current.date(
                bySettingHour: 8,
                minute: 0,
                second: 0,
                of: entry.date
            ) ?? entry.date
            let end = min(proposedEnd, Date())
            let start = end.addingTimeInterval(-max(entry.durationHours, 0.5) * 3600)
            entry.updateTiming(start: start, end: end)
            entry.episodeType = .mainSleep
            changed = true
        }
        if changed {
            try modelContext.save()
        }
        UserDefaults.standard.set(true, forKey: migrationCompleteKey)
    }
}

struct SleepEditorRequest: Identifiable {
    let id = UUID()
    let episode: SleepEntry?
}

struct SleepEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SleepEntry.date, order: .reverse) private var existingEpisodes: [SleepEntry]

    let episode: SleepEntry?

    @State private var fellAsleepDate = Calendar.current.date(byAdding: .hour, value: -7, to: Date()) ?? Date()
    @State private var wakeDate = Date()
    @State private var quality = 3
    @State private var shiftType = SleepShiftType.off
    @State private var episodeType = SleepEpisodeType.mainSleep
    @State private var notes = ""
    @State private var validationMessage = ""
    @State private var showValidationAlert = false
    @FocusState private var notesFocused: Bool

    var durationHours: Double {
        max(wakeDate.timeIntervalSince(fellAsleepDate) / 3600, 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Episode", selection: $episodeType) {
                        ForEach(SleepEpisodeType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    DatePicker("Fell asleep", selection: $fellAsleepDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])

                    DatePicker("Woke up", selection: $wakeDate, in: fellAsleepDate...Date(), displayedComponents: [.date, .hourAndMinute])

                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(SleepFormatting.duration(durationHours))
                            .font(.headline)
                            .foregroundStyle(durationHours < 0.25 ? TFColor.danger : TFColor.sleep)
                    }

                    Picker("Sleep quality", selection: $quality) {
                        Text("1 - Terrible").tag(1)
                        Text("2 - Poor").tag(2)
                        Text("3 - Okay").tag(3)
                        Text("4 - Good").tag(4)
                        Text("5 - Excellent").tag(5)
                    }

                    Picker("Shift context", selection: $shiftType) {
                        ForEach(SleepShiftType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                } header: {
                    Text("Sleep Episode")
                } footer: {
                    Text("Log each main sleep, nap, or post-call recovery period separately. Trends combine episodes by the date you woke.")
                }

                Section("Optional Note") {
                    TextField("Awakenings, unusual fatigue, interruption...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($notesFocused)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(episode == nil ? "Log Sleep" : "Edit Sleep")
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
                guard let episode else {
                    wakeDate = .now
                    fellAsleepDate = Calendar.current.date(byAdding: .hour, value: -7, to: .now) ?? .now
                    return
                }
                wakeDate = episode.resolvedEndDate
                fellAsleepDate = episode.resolvedEndDate.addingTimeInterval(-episode.resolvedDurationHours * 3600)
                quality = episode.qualityRating
                shiftType = episode.shiftType
                episodeType = episode.episodeType
                notes = episode.notes
            }
            .onChange(of: episodeType) { oldValue, newValue in
                guard episode == nil else { return }
                let currentDuration = durationHours
                if oldValue == .mainSleep && newValue == .nap && currentDuration > 3 {
                    fellAsleepDate = wakeDate.addingTimeInterval(-1 * 3600)
                } else if newValue == .recoverySleep && currentDuration > 6 {
                    fellAsleepDate = wakeDate.addingTimeInterval(-4 * 3600)
                } else if oldValue != .mainSleep && newValue == .mainSleep && currentDuration < 3 {
                    fellAsleepDate = wakeDate.addingTimeInterval(-7 * 3600)
                }
            }
            .alert("Overlapping Sleep Episode", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = fellAsleepDate
        if existingEpisodes.contains(where: { candidate in
            if let episode, candidate === episode { return false }
            return start < candidate.resolvedEndDate && wakeDate > candidate.resolvedStartDate
        }) {
            validationMessage = "This time overlaps another recorded sleep episode. Edit the existing episode or adjust these times before saving."
            showValidationAlert = true
            return
        }

        if let episode {
            episode.updateTiming(start: start, end: wakeDate)
            episode.qualityRating = quality
            episode.shiftType = shiftType
            episode.episodeType = episodeType
            episode.notes = trimmedNotes
        } else {
            modelContext.insert(
                SleepEntry(
                    startDate: start,
                    endDate: wakeDate,
                    qualityRating: quality,
                    shiftType: shiftType,
                    episodeType: episodeType,
                    notes: trimmedNotes
                )
            )
        }

        guard PersistenceReporter.save(modelContext, operation: "sleep episode") else {
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
    @Query(sort: \SleepEntry.date, order: .reverse) private var episodes: [SleepEntry]

    @State private var editorRequest: SleepEditorRequest?
    @State private var episodeToDelete: SleepEntry?

    var trend: SleepTrendSnapshot? {
        SleepTrendBuilder.build(from: episodes)
    }

    var body: some View {
        List {
            if let trend {
                Section("Recent Recovery") {
                    HStack {
                        sleepMetric(
                            "3-Day",
                            trend.acuteLoggedDays > 0
                                ? SleepFormatting.duration(trend.threeDayAverageHours)
                                : "--"
                        )
                        sleepMetric("7-Day", SleepFormatting.duration(trend.sevenDayAverageHours))
                        sleepMetric("Quality", String(format: "%.1f/5", trend.averageQuality))
                    }

                    HStack {
                        Label("\(trend.underSixHours) under 6h", systemImage: "moon.zzz.fill")
                        Spacer()
                        Label("\(trend.variabilityLabel) variability", systemImage: "waveform.path.ecg")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let latestDay = trend.days.last {
                        Text(
                            "Latest wake day: \(SleepFormatting.duration(latestDay.mainSleepHours)) main"
                                + (latestDay.napHours > 0 ? " + \(SleepFormatting.duration(latestDay.napHours)) naps" : "")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            if episodes.isEmpty {
                ContentUnavailableView(
                    "No Sleep Episodes",
                    systemImage: "bed.double",
                    description: Text("Log a main sleep or nap to begin seeing recovery trends.")
                )
            } else {
                ForEach(episodes) { episode in
                    Button {
                        editorRequest = SleepEditorRequest(episode: episode)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(episode.episodeType.rawValue)
                                    .font(.subheadline.bold())
                                Text("\(episode.resolvedEndDate.formatted(date: .abbreviated, time: .shortened)) · Quality \(episode.qualityRating)/5")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(episode.shiftType.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if !episode.notes.isEmpty {
                                    Text(episode.notes)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(SleepFormatting.duration(episode.resolvedDurationHours))
                                .font(.title3.bold())
                                .foregroundStyle(TFColor.sleep)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            episodeToDelete = episode
                        }
                    }
                }
            }
        }
        .navigationTitle("Sleep History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorRequest = SleepEditorRequest(episode: nil)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(TFColor.sleep)
                }
            }
        }
        .sheet(item: $editorRequest) { request in
            SleepEntryEditor(episode: request.episode)
        }
        .alert("Delete Sleep Episode?", isPresented: Binding(
            get: { episodeToDelete != nil },
            set: { if !$0 { episodeToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) { deleteEpisode() }
            Button("Cancel", role: .cancel) { episodeToDelete = nil }
        } message: {
            Text("This removes the episode from sleep trends and future analysis context.")
        }
    }

    private func sleepMetric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func deleteEpisode() {
        guard let episodeToDelete else { return }
        modelContext.delete(episodeToDelete)
        guard PersistenceReporter.save(modelContext, operation: "sleep episode deletion") else {
            modelContext.rollback()
            return
        }
        SleepTrendStore.refresh(using: modelContext)
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        self.episodeToDelete = nil
    }
}
