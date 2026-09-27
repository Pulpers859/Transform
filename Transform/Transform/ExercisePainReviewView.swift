import SwiftUI
import SwiftData

struct ExercisePainReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let programs: [WorkoutProgram]
    let beforeGeneration: Bool
    let onContinue: () -> Void
    @State private var choices: [String: String] = [:]
    @State private var saveError: String?
    @State private var clearedPreferences = Set<String>()

    private struct Preference: Identifiable {
        let id: String
        let source: String
        let replacement: String
    }

    private var preferences: [Preference] {
        var result: [String: Preference] = [:]
        for program in programs.sorted(by: { $0.createdDate > $1.createdDate }) {
            for day in program.sortedDays.reversed() {
                for exercise in day.sortedExercises where !exercise.preferredReplacementName.isEmpty {
                    let key = ExerciseWeightEntry.canonicalLookupKey(exercise.exerciseName)
                    if result[key] == nil {
                        result[key] = Preference(id: key, source: exercise.exerciseName, replacement: exercise.preferredReplacementName)
                    }
                }
            }
        }
        return result.values.filter { !clearedPreferences.contains($0.id) }.sorted { $0.source < $1.source }
    }

    private var items: [ExercisePainReview.Item] {
        let all = ExercisePainReview.reviewItems(from: programs, includeResolved: !beforeGeneration)
        return beforeGeneration ? all.filter(\.requiresReview) : all
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(beforeGeneration
                         ? "Review each movement before generating. Painful or uncertain movements stay excluded. Cancel will not start generation."
                         : "Change which movements are excluded from future generation. Your recorded pain and logged sets stay in your history.")
                    Text("Resolved means you choose to lift the restriction; it is not medical clearance. Existing workouts are not changed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if items.isEmpty {
                    Text("No recorded exercise pain to review.")
                }
                ForEach(items) { item in
                    Section(item.name) {
                        Picker("Current status", selection: Binding(
                            get: { choices[item.key] ?? (beforeGeneration ? "" : item.choice) },
                            set: { choices[item.key] = $0 }
                        )) {
                            if beforeGeneration { Text("Choose a status").tag("") }
                            Text("Still painful — exclude").tag("stillPainful")
                            Text("Not sure — exclude").tag("notSure")
                            Text("Resolved — allow again").tag("resolved")
                            Text("Avoid until I change it").tag("avoid")
                        }
                        .pickerStyle(.menu)
                    }
                }
                if !beforeGeneration {
                    Section("Preferred Replacements") {
                        if preferences.isEmpty { Text("No saved replacement preferences.") }
                        ForEach(preferences) { preference in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(preference.source) → \(preference.replacement)")
                                Button("Clear preference") { clearedPreferences.insert(preference.id) }
                                    .accessibilityLabel("Clear replacement preference for \(preference.source)")
                            }
                        }
                    }
                }
                if let saveError { Text(saveError).foregroundStyle(TFColor.danger) }
            }
            .navigationTitle(beforeGeneration ? "Pain Check-in" : "Exercise Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(beforeGeneration ? "Save & Generate" : "Save") { save() }
                        .disabled(beforeGeneration && !ExercisePainReview.canContinue(items: items, selections: choices))
                }
            }
        }
    }

    private func save() {
        guard !beforeGeneration || ExercisePainReview.canContinue(items: items, selections: choices) else {
            saveError = "Choose a status for every movement before generating."
            return
        }
        let records = programs.flatMap(\.sortedDays).flatMap(\.sortedExercises)
            .filter { $0.completionStatus == .skippedPain }
        let previous = records.map { ($0, $0.painReviewRaw) }
        let preferenceRecords = programs.flatMap(\.sortedDays).flatMap(\.sortedExercises)
            .filter { clearedPreferences.contains(ExerciseWeightEntry.canonicalLookupKey($0.exerciseName)) }
        let previousPreferences = preferenceRecords.map { ($0, $0.preferredReplacementName) }
        for record in preferenceRecords { record.preferredReplacementName = "" }
        for item in items {
            if let choice = choices[item.key] {
                ExercisePainReview.apply(choice: choice, to: item.key, programs: programs,
                    includePersistentAvoidances: !beforeGeneration)
            }
        }
        do {
            try modelContext.save()
            DataBackupManager.shared.writeAutomaticBackupCoalesced(using: modelContext)
            onContinue()
            dismiss()
        } catch {
            // Roll back only this sheet's edits, preserving unrelated pending model changes.
            for (record, value) in previous { record.painReviewRaw = value }
            for (record, value) in previousPreferences { record.preferredReplacementName = value }
            saveError = "Could not save this review. Nothing has been generated. Please try again."
        }
    }
}
