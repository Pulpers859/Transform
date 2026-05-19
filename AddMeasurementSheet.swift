import SwiftUI
import SwiftData

struct AddMeasurementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var chestText = ""
    @State private var waistText = ""
    @State private var hipsText = ""
    @State private var neckText = ""
    @State private var rightArmText = ""
    @State private var leftArmText = ""
    @State private var rightThighText = ""
    @State private var leftThighText = ""
    @State private var bodyFatText = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var alsoSaveWeightEntry = false
    @State private var validationMessage = ""
    @State private var showValidationAlert = false

    var hasValidWeightInput: Bool {
        guard let weight = Double(weightText) else { return false }
        return (50...999).contains(weight)
    }

    var canSave: Bool {
        !allMeasurementsEmpty || (alsoSaveWeightEntry && hasValidWeightInput)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                Section("Body Weight") {
                    HStack {
                        TextField("e.g. 192.4", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text("lbs")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Also save as weight log entry", isOn: $alsoSaveWeightEntry)
                    Text("Weight logs are stored separately, so this stays explicit instead of creating a hidden duplicate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Measurements (inches)") {
                    MeasurementField(label: "Chest", text: $chestText)
                    MeasurementField(label: "Waist", text: $waistText)
                    MeasurementField(label: "Hips", text: $hipsText)
                    MeasurementField(label: "Neck", text: $neckText)
                    MeasurementField(label: "Right Arm", text: $rightArmText)
                    MeasurementField(label: "Left Arm", text: $leftArmText)
                    MeasurementField(label: "Right Thigh", text: $rightThighText)
                    MeasurementField(label: "Left Thigh", text: $leftThighText)
                }

                Section("Body Fat %") {
                    HStack {
                        TextField("e.g. 17.5", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .alert("Invalid Entry", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    var allMeasurementsEmpty: Bool {
        [chestText, waistText, hipsText, neckText,
         rightArmText, leftArmText, rightThighText, leftThighText, bodyFatText]
            .allSatisfy { $0.isEmpty }
    }

    func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDate = Calendar.current.startOfDay(for: selectedDate)
        var weightToSave: Double?

        if alsoSaveWeightEntry {
            guard hasValidWeightInput, let weight = Double(weightText) else {
                validationMessage = "Enter a body weight between 50 and 999 lb or turn off the separate weight-log toggle."
                showValidationAlert = true
                return
            }
            weightToSave = weight
        }

        if !allMeasurementsEmpty {
            if let message = firstInvalidMeasurementMessage() {
                validationMessage = message
                showValidationAlert = true
                return
            }
        }

        if let weightToSave {
            let entry = WeightEntry(date: normalizedDate, weightLbs: weightToSave, notes: trimmedNotes)
            modelContext.insert(entry)
        }

        if !allMeasurementsEmpty {
            let m = MeasurementEntry(date: normalizedDate)
            m.chestIn = Double(chestText)
            m.waistIn = Double(waistText)
            m.hipsIn = Double(hipsText)
            m.neckIn = Double(neckText)
            m.rightArmIn = Double(rightArmText)
            m.leftArmIn = Double(leftArmText)
            m.rightThighIn = Double(rightThighText)
            m.leftThighIn = Double(leftThighText)
            m.bodyFatPct = Double(bodyFatText)
            m.notes = trimmedNotes
            modelContext.insert(m)
        }

        guard PersistenceReporter.save(modelContext, operation: "body measurements") else {
            modelContext.rollback()
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        dismiss()
    }

    func firstInvalidMeasurementMessage() -> String? {
        let inchFields: [(String, String)] = [
            ("Chest", chestText),
            ("Waist", waistText),
            ("Hips", hipsText),
            ("Neck", neckText),
            ("Right Arm", rightArmText),
            ("Left Arm", leftArmText),
            ("Right Thigh", rightThighText),
            ("Left Thigh", leftThighText)
        ]

        for (label, rawValue) in inchFields {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let value = Double(trimmed), (5...100).contains(value) else {
                return "\(label) must be between 5 and 100 inches."
            }
        }

        let trimmedBodyFat = bodyFatText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBodyFat.isEmpty {
            guard let value = Double(trimmedBodyFat), (2...80).contains(value) else {
                return "Body fat must be between 2% and 80%."
            }
        }

        return nil
    }
}

struct MeasurementField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("--", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("in")
                .foregroundStyle(.secondary)
        }
    }
}
