import SwiftUI
import SwiftData

struct AddMeasurementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]

    @State private var weightText = ""
    @State private var chestText = ""
    @State private var waistText = ""
    @State private var hipsText = ""
    @State private var neckText = ""
    @State private var rightArmText = ""
    @State private var leftArmText = ""
    @State private var rightThighText = ""
    @State private var leftThighText = ""
    @State private var rightCalfText = ""
    @State private var leftCalfText = ""
    @State private var bodyFatText = ""
    @State private var notes = ""
    @State private var selectedDate = Date()
    @State private var alsoSaveWeightEntry = false
    @State private var validationMessage = ""
    @State private var showValidationAlert = false
    @State private var showAdvanced = false
    @State private var selectedTiming = "morning_fasted"
    @State private var isStandardMeasurement = true
    @State private var validationIssues: [MeasurementValidator.Issue] = []

    let timingOptions = [
        ("morning_fasted", "Morning (fasted)"),
        ("morning_postmeal", "Morning (post-meal)"),
        ("post_training", "Post-Training"),
        ("post_shift", "Post-Shift"),
        ("evening", "Evening"),
        ("other", "Other")
    ]

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
                protocolSection
                dateSection

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

                coreMeasurementsSection
                advancedMeasurementsSection
                contextSection

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

                if !validationIssues.isEmpty {
                    validationSection
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .alert("Invalid Entry", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .onChange(of: waistText) { _, _ in runLiveValidation() }
            .onChange(of: chestText) { _, _ in runLiveValidation() }
            .onChange(of: neckText) { _, _ in runLiveValidation() }
            .onChange(of: hipsText) { _, _ in runLiveValidation() }
            .onChange(of: rightArmText) { _, _ in runLiveValidation() }
            .onChange(of: leftArmText) { _, _ in runLiveValidation() }
            .onChange(of: rightThighText) { _, _ in runLiveValidation() }
            .onChange(of: leftThighText) { _, _ in runLiveValidation() }
            .onChange(of: rightCalfText) { _, _ in runLiveValidation() }
            .onChange(of: leftCalfText) { _, _ in runLiveValidation() }
        }
    }

    // MARK: - Protocol Section

    var protocolSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Measurement Protocol", systemImage: "checkmark.shield")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    protocolRow("Measure in the morning if possible")
                    protocolRow("Stand relaxed, not vacuumed or flexed")
                    protocolRow("Tape snug but not compressing skin")
                    protocolRow("Waist at navel after normal exhale")
                    protocolRow("Take each measurement twice if unsure")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    func protocolRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .padding(.top, 5)
            Text(text)
        }
    }

    var dateSection: some View {
        Section("Date") {
            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
    }

    // MARK: - Core Measurements

    var coreMeasurementsSection: some View {
        Section {
            MeasurementField(label: "Waist (at navel)", text: $waistText)
            MeasurementField(label: "Neck", text: $neckText)
            MeasurementField(label: "Hips", text: $hipsText)
        } header: {
            Text("Core Measurements (inches)")
        } footer: {
            Text("Core measurements are enough for recomposition tracking. Waist at navel is the most important single measurement.")
        }
    }

    // MARK: - Advanced Measurements

    var advancedMeasurementsSection: some View {
        Section {
            DisclosureGroup("Advanced Measurements", isExpanded: $showAdvanced) {
                MeasurementField(label: "Chest", text: $chestText)
                MeasurementField(label: "Right Arm", text: $rightArmText)
                MeasurementField(label: "Left Arm", text: $leftArmText)
                MeasurementField(label: "Right Thigh", text: $rightThighText)
                MeasurementField(label: "Left Thigh", text: $leftThighText)
                MeasurementField(label: "Right Calf", text: $rightCalfText)
                MeasurementField(label: "Left Calf", text: $leftCalfText)
            }
        } footer: {
            Text("Optional for proportion tracking. Not needed every session.")
        }
    }

    // MARK: - Context

    var contextSection: some View {
        Section {
            Picker("Timing", selection: $selectedTiming) {
                ForEach(timingOptions, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }

            Toggle("Standard measurement", isOn: $isStandardMeasurement)

            if !isStandardMeasurement {
                Text("Non-standard measurements are flagged in trend analysis so they don't create false progress or regression signals.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Measurement Context")
        } footer: {
            Text("Timing and standardization help the trend engine filter noise from real changes.")
        }
    }

    // MARK: - Validation

    var validationSection: some View {
        Section("Validation Notes") {
            ForEach(Array(validationIssues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(severityColor(issue.severity))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func severityColor(_ severity: AnalysisValidationSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    // MARK: - Logic

    var allMeasurementsEmpty: Bool {
        [chestText, waistText, hipsText, neckText,
         rightArmText, leftArmText, rightThighText, leftThighText,
         rightCalfText, leftCalfText, bodyFatText]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func runLiveValidation() {
        validationIssues = MeasurementValidator.validate(
            waistIn: Double(waistText),
            neckIn: Double(neckText),
            hipsIn: Double(hipsText),
            chestIn: Double(chestText),
            rightArmIn: Double(rightArmText),
            leftArmIn: Double(leftArmText),
            rightThighIn: Double(rightThighText),
            leftThighIn: Double(leftThighText),
            rightCalfIn: Double(rightCalfText),
            leftCalfIn: Double(leftCalfText)
        )
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
            if let existing = weightEntries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: normalizedDate) }) {
                existing.weightLbs = weightToSave
                existing.notes = trimmedNotes
            } else {
                let entry = WeightEntry(date: normalizedDate, weightLbs: weightToSave, notes: trimmedNotes)
                modelContext.insert(entry)
            }
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
            m.rightCalfIn = Double(rightCalfText)
            m.leftCalfIn = Double(leftCalfText)
            m.bodyFatPct = Double(bodyFatText)
            m.notes = trimmedNotes
            m.measurementTiming = selectedTiming
            m.isStandardMeasurement = isStandardMeasurement
            modelContext.insert(m)
        }

        guard PersistenceReporter.save(modelContext, operation: "body measurements") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            ("Left Thigh", leftThighText),
            ("Right Calf", rightCalfText),
            ("Left Calf", leftCalfText)
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
