import SwiftUI
import SwiftData

struct AddFoodSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FavoriteFood.createdAt, order: .reverse) private var favorites: [FavoriteFood]

    let selectedDate: Date
    let preselectedMeal: String

    @State private var selectedMeal: String
    @State private var foodName = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var sugar = ""
    @State private var fiber = ""
    @State private var fat = ""
    @State private var saveAsFavorite = false

    @State private var aiDescription = ""
    @State private var isEstimating = false
    @State private var showAIAssist = false
    @State private var aiError: String?
    @State private var showAIError = false
    @State private var showAdvancedMacros = false
    @State private var isLoggingQuickEntry = false
    @State private var searchHistoryEntries: [NutritionEntry] = []
    @State private var mealHistoryEntries: [NutritionEntry] = []
    @State private var estimationTask: Task<Void, Never>?
    @State private var validationMessage = ""
    @State private var showValidationAlert = false
    @FocusState private var focusedMacroField: NutritionMacroField?

    let meals = ["Breakfast", "Lunch", "Dinner", "Snack"]
    let searchHistoryFetchLimit = 300
    let mealHistoryFetchLimit = 250

    init(selectedDate: Date, preselectedMeal: String) {
        self.selectedDate = selectedDate
        self.preselectedMeal = preselectedMeal
        _selectedMeal = State(initialValue: preselectedMeal)
    }

    var canSave: Bool {
        guard !trimmedFoodName.isEmpty,
              let parsedCalories = Int(calories.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return (0...7000).contains(parsedCalories)
    }

    var canUseAI: Bool {
        Config.hasAnthropicKey
    }

    var trimmedFoodName: String {
        foodName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var memorySuggestions: [FoodMemoryItem] {
        let query = trimmedFoodName.lowercased()
        guard !query.isEmpty else { return [] }

        var bestByName: [String: FoodMemoryItem] = [:]

        // Start with logged nutrition history as the default memory source.
        for entry in searchHistoryEntries {
            let name = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard bestByName[key] == nil else { continue }

            bestByName[key] = FoodMemoryItem(
                name: name,
                mealName: entry.mealName,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                sugarG: entry.sugarG,
                fiberG: entry.fiberG,
                fatG: entry.fatG,
                source: .history,
                lastUsedAt: entry.date
            )
        }

        // Favorites override history when names match.
        for favorite in favorites {
            let name = favorite.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            bestByName[key] = FoodMemoryItem(
                name: name,
                mealName: favorite.mealName,
                calories: favorite.calories,
                proteinG: favorite.proteinG,
                carbsG: favorite.carbsG,
                sugarG: favorite.sugarG,
                fiberG: favorite.fiberG,
                fatG: favorite.fatG,
                source: .favorite,
                lastUsedAt: favorite.createdAt
            )
        }

        return bestByName.values
            .filter { $0.name.lowercased().contains(query) }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.name.lowercased().hasPrefix(query)
                let rhsPrefix = rhs.name.lowercased().hasPrefix(query)
                if lhsPrefix != rhsPrefix { return lhsPrefix && !rhsPrefix }

                let lhsMealMatch = lhs.mealName == selectedMeal
                let rhsMealMatch = rhs.mealName == selectedMeal
                if lhsMealMatch != rhsMealMatch { return lhsMealMatch && !rhsMealMatch }

                if lhs.source != rhs.source { return lhs.source == .favorite }
                return lhs.lastUsedAt > rhs.lastUsedAt
            }
            .prefix(6)
            .map { $0 }
    }

    var frequentMealItems: [FoodMemoryItem] {
        var buckets: [String: (count: Int, latest: NutritionEntry)] = [:]
        for entry in mealHistoryEntries where entry.mealName == selectedMeal {
            let name = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            if let existing = buckets[key] {
                let newest = entry.date > existing.latest.date ? entry : existing.latest
                buckets[key] = (existing.count + 1, newest)
            } else {
                buckets[key] = (1, entry)
            }
        }

        return buckets.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.latest.date > rhs.latest.date
            }
            .prefix(6)
            .map {
                FoodMemoryItem(
                    name: $0.latest.notes,
                    mealName: selectedMeal,
                    calories: $0.latest.calories,
                    proteinG: $0.latest.proteinG,
                    carbsG: $0.latest.carbsG,
                    sugarG: $0.latest.sugarG,
                    fiberG: $0.latest.fiberG,
                    fatG: $0.latest.fatG,
                    source: .history,
                    lastUsedAt: $0.latest.date
                )
            }
    }

    var recentMealItems: [FoodMemoryItem] {
        mealHistoryEntries
            .sorted { $0.date > $1.date }
            .reduce(into: [FoodMemoryItem]()) { items, entry in
                guard items.count < 5 else { return }
                let name = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                if items.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    return
                }
                items.append(
                    FoodMemoryItem(
                        name: name,
                        mealName: selectedMeal,
                        calories: entry.calories,
                        proteinG: entry.proteinG,
                        carbsG: entry.carbsG,
                        sugarG: entry.sugarG,
                        fiberG: entry.fiberG,
                        fatG: entry.fatG,
                        source: .history,
                        lastUsedAt: entry.date
                    )
                )
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Picker("Meal Type", selection: $selectedMeal) {
                        ForEach(meals, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Food Details") {
                    TextField("Food name (e.g. Chicken & Rice)", text: $foodName)
                        .textInputAutocapitalization(.words)

                    if !memorySuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("From your food memory")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(memorySuggestions) { item in
                                Button {
                                    applyMemoryItem(item)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(item.name)
                                                    .foregroundStyle(.primary)
                                                Text(item.mealName)
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.15))
                                                    .foregroundStyle(.orange)
                                                    .clipShape(Capsule())
                                                if item.source == .favorite {
                                                    Image(systemName: "star.fill")
                                                        .font(.caption2)
                                                        .foregroundStyle(.yellow)
                                                }
                                            }
                                            Text("\(item.calories) kcal · P \(Int(item.proteinG)) · C \(Int(item.carbsG)) · F \(Int(item.fatG))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.down.circle")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Section("Calories & Macros") {
                    MacroInputRow(
                        label: "Calories",
                        unit: "kcal",
                        text: $calories,
                        field: .calories,
                        focusedField: $focusedMacroField,
                        nextField: .fat
                    )
                    MacroInputRow(
                        label: "Fat",
                        unit: "g",
                        text: $fat,
                        field: .fat,
                        focusedField: $focusedMacroField,
                        nextField: .carbs
                    )
                    MacroInputRow(
                        label: "Total Carbs",
                        unit: "g",
                        text: $carbs,
                        field: .carbs,
                        focusedField: $focusedMacroField,
                        nextField: showAdvancedMacros ? .fiber : .protein
                    )
                    if showAdvancedMacros {
                        MacroInputRow(
                            label: "Fiber",
                            unit: "g",
                            text: $fiber,
                            field: .fiber,
                            focusedField: $focusedMacroField,
                            nextField: .sugar
                        )
                        MacroInputRow(
                            label: "Sugars",
                            unit: "g",
                            text: $sugar,
                            field: .sugar,
                            focusedField: $focusedMacroField,
                            nextField: .protein
                        )
                    }
                    MacroInputRow(
                        label: "Protein",
                        unit: "g",
                        text: $protein,
                        field: .protein,
                        focusedField: $focusedMacroField,
                        nextField: nil
                    )

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAdvancedMacros.toggle()
                        }
                        if !showAdvancedMacros && (focusedMacroField == .fiber || focusedMacroField == .sugar) {
                            focusedMacroField = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showAdvancedMacros ? "chevron.up.circle.fill" : "chevron.down.circle")
                                .foregroundStyle(.orange)
                            Text(showAdvancedMacros ? "Hide Advanced (Fiber, Sugars)" : "Show Advanced (Fiber, Sugars)")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }

                fastAddSection

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if !showAIAssist {
                            Button {
                                showAIAssist = true
                            } label: {
                                Label("Estimate with AI", systemImage: "sparkles")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            Text("Describe what you ate")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("e.g. 6oz grilled chicken, 1 cup white rice, broccoli", text: $aiDescription, axis: .vertical)
                                .lineLimit(2...4)

                            Button {
                                startMacroEstimation()
                            } label: {
                                HStack {
                                    if isEstimating {
                                        ProgressView().tint(.white).scaleEffect(0.8)
                                    }
                                    Text(isEstimating ? "Estimating..." : "Estimate Macros")
                                        .font(.subheadline.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(aiDescription.isEmpty || isEstimating ? Color.orange.opacity(0.4) : Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .disabled(aiDescription.isEmpty || isEstimating || !canUseAI)

                            if !canUseAI {
                                Text(Config.anthropicKeyInlineHelpText)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("AI Assist")
                } footer: {
                    Text("Describe your meal and Claude will estimate the macros. You can edit before saving.")
                }

                Section {
                    Toggle("Save as favorite food", isOn: $saveAsFavorite)
                        .tint(.orange)
                }
            }
            .navigationTitle("Add Food")
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
            }
        .alert("Estimation Failed", isPresented: $showAIError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiError ?? "Could not estimate macros. Check your API key and try again.")
        }
        .alert("Invalid Entry", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage)
        }
        .onAppear {
            refreshMealHistoryEntries()
            refreshSearchHistoryEntries()
        }
        .onChange(of: selectedMeal) { _, _ in
            refreshMealHistoryEntries()
        }
        .onChange(of: foodName) { _, _ in
            refreshSearchHistoryEntries()
        }
        .onDisappear {
            estimationTask?.cancel()
            estimationTask = nil
            isEstimating = false
        }
    }

    var fastAddSection: some View {
        Section("Fast Add") {
            if frequentMealItems.isEmpty && recentMealItems.isEmpty {
                Text("As you log \(selectedMeal.lowercased()), your frequent and recent items will appear here for one-tap logging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !frequentMealItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Frequent \(selectedMeal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(frequentMealItems) { item in
                            quickLogRow(item: item)
                        }
                    }
                }

                if !recentMealItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent \(selectedMeal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(recentMealItems) { item in
                            quickLogRow(item: item)
                        }
                    }
                }
            }
        }
    }

    func quickLogRow(item: FoodMemoryItem) -> some View {
        HStack(spacing: 10) {
            Button {
                applyMemoryItem(item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(item.calories) kcal · P \(Int(item.proteinG)) · C \(Int(item.carbsG)) · F \(Int(item.fatG))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                quickLogItem(item)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .disabled(isLoggingQuickEntry)
        }
    }

    // MARK: - AI Estimation

    @MainActor
    func startMacroEstimation() {
        estimationTask?.cancel()
        estimationTask = Task {
            await estimateMacros()
        }
    }

    @MainActor
    func estimateMacros() async {
        guard !Task.isCancelled else { return }
        isEstimating = true
        defer {
            if !Task.isCancelled {
                isEstimating = false
                estimationTask = nil
            }
        }

        let prompt = """
        Estimate the nutritional content of this meal: "\(aiDescription)"

        Respond ONLY with valid JSON, no preamble:
        {
          "foodName": "Short descriptive name",
          "calories": 450,
          "proteinG": 38.0,
          "carbsG": 45.0,
          "sugarG": 7.0,
          "fiberG": 5.0,
          "fatG": 10.0
        }

        Be realistic and specific. Use standard portion sizes if not specified.
        """

        let requestBody: [String: Any] = [
            "model": Config.claudeModelLite,
            "max_tokens": 300,
            "messages": [["role": "user", "content": prompt]]
        ]

        do {
            let text = try await AnthropicClient.shared.sendRequest(body: requestBody, timeout: 90)
            try Task.checkCancellation()

            let cleaned = ClaudeService.extractJSON(from: text)

            guard let jsonData = cleaned.data(using: .utf8) else {
                throw ClaudeError.parseError("Could not decode response")
            }

            let result = try JSONDecoder().decode(MacroEstimate.self, from: jsonData)

            guard !Task.isCancelled else { return }

            // Clamp to the same ranges the Save button validates against, so a wild
            // estimate can't silently disable Save.
            foodName = result.foodName
            calories = "\(min(max(result.calories, 0), 7000))"
            protein = String(format: "%.0f", min(max(result.proteinG, 0), 500))
            carbs = String(format: "%.0f", min(max(result.carbsG, 0), 1000))
            sugar = String(format: "%.0f", min(max(result.sugarG ?? 0, 0), 300))
            fiber = String(format: "%.0f", min(max(result.fiberG ?? 0, 0), 150))
            fat = String(format: "%.0f", min(max(result.fatG, 0), 500))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            aiError = error.localizedDescription
            showAIError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - Save

    func refreshSearchHistoryEntries() {
        let query = trimmedFoodName
        guard !query.isEmpty else {
            searchHistoryEntries = []
            return
        }

        // Filter at the store level so each keystroke fetches only matching rows
        // instead of pulling the most recent searchHistoryFetchLimit entries and
        // discarding the bulk in memory. localizedStandardContains is case- and
        // diacritic-insensitive — a superset of the in-memory name filter applied
        // to these results, so the displayed suggestions are unchanged.
        var descriptor = FetchDescriptor<NutritionEntry>(
            predicate: #Predicate { $0.notes.localizedStandardContains(query) },
            sortBy: [SortDescriptor(\NutritionEntry.date, order: .reverse)]
        )
        descriptor.fetchLimit = searchHistoryFetchLimit
        do {
            searchHistoryEntries = try modelContext.fetch(descriptor)
        } catch {
            searchHistoryEntries = []
            print("[AddFoodSheet] Failed to refresh search history entries: \(error)")
        }
    }

    func refreshMealHistoryEntries() {
        let selectedMealName = selectedMeal
        var descriptor = FetchDescriptor<NutritionEntry>(
            predicate: #Predicate { $0.mealName == selectedMealName },
            sortBy: [SortDescriptor(\NutritionEntry.date, order: .reverse)]
        )
        descriptor.fetchLimit = mealHistoryFetchLimit
        do {
            mealHistoryEntries = try modelContext.fetch(descriptor)
        } catch {
            mealHistoryEntries = []
            print("[AddFoodSheet] Failed to refresh meal history entries: \(error)")
        }
    }

    func applyMemoryItem(_ item: FoodMemoryItem) {
        selectedMeal = item.mealName
        foodName = item.name
        calories = "\(item.calories)"
        protein = String(format: "%.0f", item.proteinG)
        carbs = String(format: "%.0f", item.carbsG)
        sugar = String(format: "%.0f", item.sugarG)
        fiber = String(format: "%.0f", item.fiberG)
        fat = String(format: "%.0f", item.fatG)
    }

    func quickLogItem(_ item: FoodMemoryItem) {
        guard !isLoggingQuickEntry else { return }
        isLoggingQuickEntry = true
        defer { isLoggingQuickEntry = false }

        let entry = NutritionEntry(
            date: selectedDate,
            mealName: selectedMeal,
            calories: item.calories,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            notes: item.name,
            sugarG: item.sugarG,
            fiberG: item.fiberG
        )
        modelContext.insert(entry)
        guard PersistenceReporter.save(modelContext, operation: "quick food log") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismiss()
    }

    func saveFavoriteIfNeeded(
        name: String,
        mealName: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        sugar: Double,
        fiber: Double,
        fat: Double
    ) {
        guard saveAsFavorite else { return }

        if let existing = favorites.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.mealName == mealName
        }) {
            existing.calories = calories
            existing.proteinG = protein
            existing.carbsG = carbs
            existing.sugarG = sugar
            existing.fiberG = fiber
            existing.fatG = fat
            existing.createdAt = .now
        } else {
            let favorite = FavoriteFood(
                name: name,
                mealName: mealName,
                calories: calories,
                proteinG: protein,
                carbsG: carbs,
                sugarG: sugar,
                fiberG: fiber,
                fatG: fat
            )
            modelContext.insert(favorite)
        }
    }

    func save() {
        guard let payload = validatedPayload() else { return }

        let entry = NutritionEntry(
            date: selectedDate,
            mealName: selectedMeal,
            calories: payload.calories,
            proteinG: payload.protein,
            carbsG: payload.carbs,
            fatG: payload.fat,
            notes: payload.name,
            sugarG: payload.sugar,
            fiberG: payload.fiber
        )
        modelContext.insert(entry)

        saveFavoriteIfNeeded(
            name: payload.name,
            mealName: selectedMeal,
            calories: payload.calories,
            protein: payload.protein,
            carbs: payload.carbs,
            sugar: payload.sugar,
            fiber: payload.fiber,
            fat: payload.fat
        )

        guard PersistenceReporter.save(modelContext, operation: "food entry") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        dismiss()
    }

    func validatedPayload() -> (
        name: String,
        calories: Int,
        protein: Double,
        carbs: Double,
        sugar: Double,
        fiber: Double,
        fat: Double
    )? {
        let trimmedName = trimmedFoodName
        guard !trimmedName.isEmpty else {
            validationMessage = "Enter a food name before saving."
            showValidationAlert = true
            return nil
        }

        guard let parsedCalories = validatedInt(calories, fieldName: "Calories", range: 0...7000) else {
            return nil
        }
        guard let parsedProtein = validatedDouble(protein, fieldName: "Protein", range: 0...500) else {
            return nil
        }
        guard let parsedCarbs = validatedDouble(carbs, fieldName: "Total carbs", range: 0...1000) else {
            return nil
        }
        guard let parsedSugar = validatedDouble(sugar, fieldName: "Sugars", range: 0...300) else {
            return nil
        }
        guard let parsedFiber = validatedDouble(fiber, fieldName: "Fiber", range: 0...150) else {
            return nil
        }
        guard let parsedFat = validatedDouble(fat, fieldName: "Fat", range: 0...500) else {
            return nil
        }

        guard parsedSugar <= parsedCarbs + 0.001 else {
            validationMessage = "Sugars cannot exceed total carbs."
            showValidationAlert = true
            return nil
        }

        guard parsedFiber <= parsedCarbs + 0.001 else {
            validationMessage = "Fiber cannot exceed total carbs."
            showValidationAlert = true
            return nil
        }

        return (
            name: trimmedName,
            calories: parsedCalories,
            protein: parsedProtein,
            carbs: parsedCarbs,
            sugar: parsedSugar,
            fiber: parsedFiber,
            fat: parsedFat
        )
    }

    func validatedInt(_ rawValue: String, fieldName: String, range: ClosedRange<Int>) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "\(fieldName) is required."
            showValidationAlert = true
            return nil
        }
        guard let value = Int(trimmed), range.contains(value) else {
            validationMessage = "\(fieldName) must be between \(range.lowerBound) and \(range.upperBound)."
            showValidationAlert = true
            return nil
        }
        return value
    }

    func validatedDouble(_ rawValue: String, fieldName: String, range: ClosedRange<Double>) -> Double? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 0
        }
        guard let value = Double(trimmed), range.contains(value) else {
            validationMessage = "\(fieldName) must be between \(Int(range.lowerBound)) and \(Int(range.upperBound))."
            showValidationAlert = true
            return nil
        }
        return value
    }
}

enum NutritionMacroField: Hashable {
    case calories
    case fat
    case carbs
    case fiber
    case sugar
    case protein
}

struct MacroInputRow: View {
    let label: String
    let unit: String
    @Binding var text: String
    let field: NutritionMacroField
    var focusedField: FocusState<NutritionMacroField?>.Binding
    let nextField: NutritionMacroField?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused(focusedField, equals: field)
                .submitLabel(nextField == nil ? .done : .next)
                .onSubmit {
                    focusedField.wrappedValue = nextField
                }
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField.wrappedValue = field
        }
    }
}

nonisolated struct MacroEstimate: Codable {
    let foodName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let sugarG: Double?
    let fiberG: Double?
    let fatG: Double

    private enum CodingKeys: String, CodingKey {
        case foodName, calories, proteinG, carbsG, sugarG, fiberG, fatG
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        foodName = try container.decode(String.self, forKey: .foodName)
        // Tolerate the model returning calories as a decimal (e.g. 450.0).
        if let intCalories = try? container.decode(Int.self, forKey: .calories) {
            calories = intCalories
        } else {
            calories = Int((try container.decode(Double.self, forKey: .calories)).rounded())
        }
        proteinG = try container.decode(Double.self, forKey: .proteinG)
        carbsG = try container.decode(Double.self, forKey: .carbsG)
        sugarG = try container.decodeIfPresent(Double.self, forKey: .sugarG)
        fiberG = try container.decodeIfPresent(Double.self, forKey: .fiberG)
        fatG = try container.decode(Double.self, forKey: .fatG)
    }
}

struct FoodMemoryItem: Identifiable {
    enum Source {
        case favorite
        case history
    }

    let name: String
    let mealName: String
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let sugarG: Double
    let fiberG: Double
    let fatG: Double
    let source: Source
    let lastUsedAt: Date

    var id: String {
        "\(name.lowercased())|\(mealName.lowercased())"
    }
}
