import SwiftUI
import SwiftData

enum NutritionTemplateSelection: String, CaseIterable, Identifiable {
    case training = "Training Day"
    case rest = "Rest Day"
    var id: String { rawValue }
}

enum CopyMealMode {
    case append
    case replaceExisting
}

// MARK: - Macro Ring

struct MacroRing: View {
    let value: Double
    let target: Double
    let color: Color
    let lineWidth: CGFloat
    let size: CGFloat

    var progress: Double {
        min(value / max(target, 1), 1.0)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Macro Progress Bar

struct MacroProgressBar: View {
    let label: String
    let value: Double
    let target: Double
    let color: Color
    let unit: String

    var progress: Double { min(value / max(target, 1), 1.0) }
    var isOver: Bool { value > target }

    init(label: String, value: Double, target: Double, color: Color, unit: String = "g") {
        self.label = label
        self.value = value
        self.target = target
        self.color = color
        self.unit = unit
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.subheadline.bold())
                    .foregroundStyle(isOver ? .red : .primary)
                Text("/ \(Int(target))\(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.15))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOver ? Color.red : color)
                        .frame(width: geo.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Meal Group

struct MealGroupView: View {
    let mealName: String
    let entries: [NutritionEntry]
    let onDelete: (NutritionEntry) -> Void
    let onAddMore: () -> Void

    var totalCals: Int { entries.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { entries.reduce(0) { $0 + $1.proteinG } }

    var mealIcon: String {
        switch mealName {
        case "Breakfast": return "sunrise.fill"
        case "Lunch": return "sun.max.fill"
        case "Dinner": return "moon.stars.fill"
        default: return "takeoutbag.and.cup.and.straw.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(mealName, systemImage: mealIcon)
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Text("\(totalCals) kcal")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("· \(Int(totalProtein))g P")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    onAddMore()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().padding(.horizontal, 12)

            ForEach(entries) { entry in
                FoodRowView(entry: entry, onDelete: { onDelete(entry) })
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Food Row (with delete button via context menu)

struct FoodRowView: View {
    let entry: NutritionEntry
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.notes.isEmpty ? "Food item" : entry.notes)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("P: \(Int(entry.proteinG))g")
                        .foregroundStyle(.red)
                    Text("C: \(Int(entry.carbsG))g")
                        .foregroundStyle(.blue)
                    Text("S: \(Int(entry.sugarG))g")
                        .foregroundStyle(.pink)
                    Text("Fi: \(Int(entry.fiberG))g")
                        .foregroundStyle(.green)
                    Text("F: \(Int(entry.fatG))g")
                        .foregroundStyle(.yellow)
                }
                .font(.caption2)
            }

            Spacer()

            Text("\(entry.calories)")
                .font(.subheadline.bold())
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Nutrition Program UI

struct NutritionProgramHeader: View {
    let program: NutritionProgramResponse

    var sourceBadge: (label: String, color: Color)? {
        switch GeneratedContentSource.detect(in: program.programSummary) {
        case .aiCoach:
            return ("AI Coach", .green)
        case .recoveryEngine:
            return ("Recovery Engine", .orange)
        case nil:
            return nil
        }
    }

    var summaryStripped: String {
        GeneratedContentSource.strip(from: program.programSummary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(program.programName)
                    .font(.subheadline.bold())
                Spacer()
                if let badge = sourceBadge {
                    Text(badge.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badge.color.opacity(0.15))
                        .foregroundStyle(badge.color)
                        .clipShape(Capsule())
                }
            }
            Text(summaryStripped)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !program.proteinCoverageNote.isEmpty {
                Text(program.proteinCoverageNote)
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct NutritionWeekDetail: View {
    let week: NutritionWeekResponse
    @Binding var selectedTemplate: NutritionTemplateSelection

    var template: DailyNutritionTemplate {
        selectedTemplate == .training ? week.trainingDay : week.restDay
    }

    var weekSummaryStripped: String {
        GeneratedContentSource.strip(from: week.weekSummary)
    }

    // Per-week provenance: a fallback week inside an AI program must stay visible.
    var weekSourceBadge: (label: String, color: Color)? {
        switch GeneratedContentSource.detect(in: week.weekSummary) {
        case .aiCoach:
            return ("AI Coach", .green)
        case .recoveryEngine:
            return ("Recovery Engine", .orange)
        case nil:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(week.phaseFocus)
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                    Spacer()
                    if let badge = weekSourceBadge {
                        Text(badge.label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badge.color.opacity(0.15))
                            .foregroundStyle(badge.color)
                            .clipShape(Capsule())
                    }
                }
                Text(weekSummaryStripped)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !week.coachNotes.isEmpty {
                    Text(week.coachNotes)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.top, 2)
                }
            }

            Picker("Day Type", selection: $selectedTemplate) {
                ForEach(NutritionTemplateSelection.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            NutritionTemplateMacroRow(template: template)

            Text("Meals")
                .font(.subheadline.bold())
            ForEach(template.meals) { meal in
                NutritionMealCard(meal: meal)
            }

            Divider().padding(.vertical, 2)

            Text("Weekly Grocery List")
                .font(.subheadline.bold())
            Text("Quantities scaled for 5 training + 2 rest days.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(week.weeklyGrocery) { category in
                NutritionGroceryCategoryCard(category: category)
            }
        }
    }
}

struct NutritionTemplateMacroRow: View {
    let template: DailyNutritionTemplate

    var body: some View {
        HStack(spacing: 8) {
            macroPill(label: "kcal", value: "\(template.totalCalories)", color: .orange)
            macroPill(label: "P", value: "\(template.totalProteinG)g", color: .red)
            macroPill(label: "C", value: "\(template.totalCarbsG)g", color: .blue)
            macroPill(label: "F", value: "\(template.totalFatG)g", color: .yellow)
        }
    }

    func macroPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct NutritionMealCard: View {
    let meal: MealSlotResponse

    var mealIcon: String {
        switch meal.mealName {
        case "Breakfast": return "sunrise.fill"
        case "Lunch": return "sun.max.fill"
        case "Dinner": return "moon.stars.fill"
        default: return "takeoutbag.and.cup.and.straw.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(meal.mealName, systemImage: mealIcon)
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Text("\(meal.approxCalories) kcal")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Text(meal.primaryOption)
                .font(.caption)
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Text("P: \(meal.approxProteinG)g").foregroundStyle(.red)
                Text("C: \(meal.approxCarbsG)g").foregroundStyle(.blue)
                Text("F: \(meal.approxFatG)g").foregroundStyle(.yellow)
            }
            .font(.caption2.bold())

            if !meal.timingNote.isEmpty {
                Text(meal.timingNote)
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            if !meal.substitutions.isEmpty {
                Text("Swap: \(meal.substitutions.joined(separator: " • "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct NutritionGroceryCategoryCard: View {
    let category: NutritionGroceryCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.category)
                .font(.subheadline.bold())
                .foregroundStyle(.orange)

            ForEach(category.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("• \(item.name)")
                            .font(.caption.bold())
                        Spacer()
                        Text(item.quantity)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    if !item.rationale.isEmpty {
                        Text(item.rationale)
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    if !item.substitutions.isEmpty {
                        Text("Swap: \(item.substitutions.joined(separator: " • "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
