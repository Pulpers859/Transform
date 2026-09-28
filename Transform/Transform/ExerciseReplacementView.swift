import SwiftUI
import SwiftData

/// User-initiated, network-free replacement. Logs retain their identity; returning to an
/// earlier exercise reuses its card and adds only outstanding work to its logged sets.
struct ExerciseReplacementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var programs: [WorkoutProgram]
    let exercise: WorkoutExercise
    @State private var selection = ""
    @State private var preferFuture = false
    @State private var equipmentAvailable = false
    @State private var errorMessage: String?

    private var candidates: [String] {
        ExerciseReplacement.candidates(for: exercise, avoidedKeys: ExercisePainReview.activeKeys(from: programs))
    }

    private var loggedSets: [SetLogEntry] {
        let logs = (try? modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())) ?? []
        return SetLoggingService.loggedSets(for: exercise, in: logs)
    }

    private var canPreferFuture: Bool {
        ExerciseReplacement.compatible(originalName: exercise.exerciseName, candidateName: selection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Replacing \(exercise.exerciseName)") {
                    Text("\(max(0, exercise.sets - Set(loggedSets.map(\.setNumber)).count)) sets remain. Logged sets stay under the original exercise. The replacement uses its own weight history; choose a new load if it has none.")
                    Text("A compatible exercise is not a guarantee of pain-free movement. Stop if it causes pain.")
                        .foregroundStyle(.secondary)
                    Text("You can return to an earlier alternative in this slot. Its logged sets remain saved. Exercises skipped in this session stay excluded so their skip and pain records are preserved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Choose an available alternative") {
                    if candidates.isEmpty {
                        Text("No compatible alternative is available for this slot. You can cancel and skip the remaining work; the app will not force a mismatched replacement.")
                    }
                    ForEach(candidates, id: \.self) { name in
                        Button {
                            selection = name
                            equipmentAvailable = false
                            preferFuture = false
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if selection == name { Image(systemName: "checkmark").foregroundStyle(TFColor.accent) }
                            }
                        }.foregroundStyle(.primary)
                            .accessibilityAddTraits(selection == name ? .isSelected : [])
                    }
                }
                if !selection.isEmpty {
                    Section("Scope") {
                        Toggle("Equipment is available to me", isOn: $equipmentAvailable)
                        Toggle("Prefer this in future workouts", isOn: $preferFuture)
                            .disabled(!canPreferFuture)
                        if !canPreferFuture {
                            Text("Available to return to today. It does not meet the planner's future-substitution limits.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(preferFuture
                             ? "A preference, not a guarantee: future plans still check muscle targets, pain flags, and set limits. Change it in Exercise Preferences."
                             : "Just today. Future workouts keep their existing selection rules.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(TFColor.danger) }
            }
            .navigationTitle("Replace Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") { replace() }
                        .disabled(selection.isEmpty || !equipmentAvailable || !candidates.contains(selection))
                }
            }
        }
    }

    private func replace() {
        do {
            // Fetch again when committing: the picker snapshot is not authority for logs.
            let logs = try modelContext.fetch(FetchDescriptor<ExercisePerformanceLog>())
            let numbers = Set(SetLoggingService.loggedSets(for: exercise, in: logs).map(\.setNumber))
            _ = try ExerciseReplacement.replace(exercise, with: selection, loggedSetNumbers: numbers,
                preferFuture: preferFuture, avoidedKeys: ExercisePainReview.activeKeys(from: programs), modelContext: modelContext)
            DataBackupManager.shared.writeAutomaticBackupCoalesced(using: modelContext)
            TFHaptics.impact(.light)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            TFHaptics.error()
        }
    }
}
