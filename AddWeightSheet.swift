import SwiftUI
import SwiftData

struct AddWeightSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]

    @State private var selectedDate = Date()
    @State private var weightText = ""
    @State private var notes = ""
    @State private var existingEntryForDate: WeightEntry?
    @State private var validationMessage = ""
    @State private var showValidationAlert = false
    @State private var lastSyncedWeightText = ""
    @State private var lastSyncedNotes = ""

    var canSave: Bool {
        guard let weight = UserNumberParser.double(from: weightText) else { return false }
        return (50...999).contains(weight)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                Section("Weight") {
                    HStack {
                        TextField("e.g. 192.4", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("lbs")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(existingEntryForDate == nil ? "Log Weight" : "Edit Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .bold()
                    .disabled(!canSave)
                }
            }
            .onAppear {
                selectedDate = Calendar.current.startOfDay(for: selectedDate)
                syncExistingEntry()
            }
            .onChange(of: selectedDate) { _, _ in
                syncExistingEntry()
            }
            .alert("Invalid Weight", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    func syncExistingEntry() {
        let targetDay = Calendar.current.startOfDay(for: selectedDate)
        let existing = weightEntries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: targetDay) })
        existingEntryForDate = existing

        // Only auto-fill fields the user hasn't typed into since the last sync —
        // changing the date must not silently discard in-progress input.
        let weightUntouched = weightText == lastSyncedWeightText
        let notesUntouched = notes == lastSyncedNotes
        let syncedWeightText = existing.map { String(format: "%.1f", $0.weightLbs) } ?? ""
        let syncedNotes = existing?.notes ?? ""

        if weightUntouched {
            weightText = syncedWeightText
            lastSyncedWeightText = syncedWeightText
        }
        if notesUntouched {
            notes = syncedNotes
            lastSyncedNotes = syncedNotes
        }
    }

    func save() {
        guard let weight = UserNumberParser.double(from: weightText), (50...999).contains(weight) else {
            validationMessage = "Enter a body weight between 50 and 999 lb."
            showValidationAlert = true
            return
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDate = Calendar.current.startOfDay(for: selectedDate)

        if let existingEntryForDate {
            existingEntryForDate.date = normalizedDate
            existingEntryForDate.weightLbs = weight
            existingEntryForDate.notes = trimmedNotes
        } else {
            let entry = WeightEntry(
                date: normalizedDate,
                weightLbs: weight,
                notes: trimmedNotes
            )
            modelContext.insert(entry)
        }

        guard PersistenceReporter.save(modelContext, operation: "body weight entry") else {
            modelContext.rollback()
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        dismiss()
    }
}
