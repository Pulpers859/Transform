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
                    .foregroundStyle(isOver ? TFColor.danger : .primary)
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
                        .fill(isOver ? TFColor.danger : color)
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
                    .foregroundStyle(TFColor.accent)
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
                        .foregroundStyle(TFColor.accent)
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
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
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
                        .foregroundStyle(TFColor.protein)
                    Text("C: \(Int(entry.carbsG))g")
                        .foregroundStyle(TFColor.carbs)
                    Text("S: \(Int(entry.sugarG))g")
                        .foregroundStyle(.pink)
                    Text("Fi: \(Int(entry.fiberG))g")
                        .foregroundStyle(TFColor.success)
                    Text("F: \(Int(entry.fatG))g")
                        .foregroundStyle(TFColor.fat)
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
            return ("AI Coach", TFColor.success)
        case .recoveryEngine:
            return ("Recovery Engine", TFColor.accent)
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
                    .foregroundStyle(TFColor.success)
            }
        }
        .padding(10)
        .background(TFColor.surfaceElevated)
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

    var weekSourceBadge: (label: String, color: Color)? {
        switch GeneratedContentSource.detect(in: week.weekSummary) {
        case .aiCoach: return ("AI Coach", TFColor.success)
        case .recoveryEngine: return ("Recovery Engine", TFColor.accent)
        case .none: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(week.phaseFocus)
                        .font(.subheadline.bold())
                        .foregroundStyle(TFColor.accent)
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
            macroPill(label: "kcal", value: "\(template.totalCalories)", color: TFColor.accent)
            macroPill(label: "P", value: "\(template.totalProteinG)g", color: TFColor.protein)
            macroPill(label: "C", value: "\(template.totalCarbsG)g", color: TFColor.carbs)
            macroPill(label: "F", value: "\(template.totalFatG)g", color: TFColor.fat)
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
                    .foregroundStyle(TFColor.accent)
                Spacer()
                Text("\(meal.approxCalories) kcal")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Text(meal.primaryOption)
                .font(.caption)
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Text("P: \(meal.approxProteinG)g").foregroundStyle(TFColor.protein)
                Text("C: \(meal.approxCarbsG)g").foregroundStyle(TFColor.carbs)
                Text("F: \(meal.approxFatG)g").foregroundStyle(TFColor.fat)
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
        .background(TFColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct NutritionGroceryCategoryCard: View {
    let category: NutritionGroceryCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.category)
                .font(.subheadline.bold())
                .foregroundStyle(TFColor.accent)

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
        .background(TFColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Adherence Snapshot Card

struct AdherenceSnapshotCard: View {
    let metrics: NutritionAdherenceMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            loggedDaysRow

            if metrics.validDays >= 3 {
                complianceSection
            }

            if let range = metrics.proteinPerFeedingRange {
                proteinDistributionRow(range: range)
            }

            if metrics.weightDataPoints >= 2 {
                Divider()
                weightTrendSection
            }

            if metrics.primaryBottleneck != nil || metrics.nextActionRecommendation != nil {
                Divider()
                actionSection
            }
        }
        .dashCard()
    }

    private var headerRow: some View {
        HStack(alignment: .center) {
            Label("Adherence Snapshot", systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundStyle(TFColor.accent)
            Spacer()
            Text(metrics.dataQuality.rawValue)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(qualityColor.opacity(0.15))
                .foregroundStyle(qualityColor)
                .clipShape(Capsule())
        }
    }

    private var loggedDaysRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Logged Days (last \(metrics.lookbackDays)d)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(metrics.loggedDays) logged, \(metrics.validDays) valid")
                    .font(.caption.bold())
                    .foregroundStyle(qualityColor)
            }
            if metrics.hasIncompleteDayWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(TFColor.accent)
                    Text("\(metrics.incompleteDays) days look incomplete (<1000 kcal or <2 meals) — missing dinner or snacks?")
                        .font(.caption2)
                        .foregroundStyle(TFColor.accent)
                }
            }
        }
    }

    private var complianceSection: some View {
        VStack(spacing: 6) {
            if let rate = metrics.calorieHitRate {
                complianceRow(label: "Calorie Compliance", rate: rate, detail: "within ±10% of target")
            }
            if let rate = metrics.proteinHitRate {
                complianceRow(label: "Protein Compliance", rate: rate, detail: "≥90% of target")
            }
        }
    }

    private func complianceRow(label: String, rate: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((rate * 100).rounded()))%")
                    .font(.caption.bold())
                    .foregroundStyle(rate >= 0.6 ? TFColor.success : (rate >= 0.4 ? TFColor.warning : TFColor.danger))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(rate >= 0.6 ? TFColor.success : (rate >= 0.4 ? TFColor.warning : TFColor.danger))
                        .frame(width: geo.size.width * min(rate, 1.0), height: 6)
                }
            }
            .frame(height: 6)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func proteinDistributionRow(range: (low: Int, high: Int)) -> some View {
        HStack {
            Image(systemName: "fork.knife")
                .font(.caption2)
                .foregroundStyle(TFColor.protein)
            Text("Target: ~\(range.low)–\(range.high)g protein × 3–5 feedings")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var weightTrendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Weight Trend")
                    .font(.caption.bold())
                Spacer()
                Text(metrics.weightTrendStatus.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(trendStatusColor.opacity(0.15))
                    .foregroundStyle(trendStatusColor)
                    .clipShape(Capsule())
            }

            if let avg = metrics.currentWeeklyAverageWeight {
                HStack {
                    Text("Weekly avg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.1f", avg)) lb")
                        .font(.caption.bold())
                }
            }

            if let change = metrics.weeklyWeightChangeLbs {
                HStack {
                    Text("Rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(change > 0 ? "+" : "")\(String(format: "%.1f", change)) lb/week")
                        .font(.caption.bold())
                        .foregroundStyle(change > 0.2 ? TFColor.danger : (change < -0.2 ? TFColor.success : Color.primary))
                }
            }

            if let range = metrics.targetWeightLossRangeLbs {
                HStack {
                    Text("Target loss range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(String(format: "%.1f", range.low))–\(String(format: "%.1f", range.high)) lb/week")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Consider adjusting after 2+ consistent weeks off target.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bottleneck = metrics.primaryBottleneck {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Primary Bottleneck", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.protein)
                    Text(bottleneck)
                        .font(.caption)
                }
            }
            if let action = metrics.nextActionRecommendation {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Next Step", systemImage: "arrow.right.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.success)
                    Text(action)
                        .font(.caption)
                }
            }
        }
    }

    private var qualityColor: Color {
        switch metrics.dataQuality {
        case .veryLow, .low: return TFColor.danger
        case .moderate: return TFColor.warning
        case .good, .excellent: return TFColor.success
        }
    }

    private var trendStatusColor: Color {
        switch metrics.weightTrendStatus {
        case .onTrack: return TFColor.success
        case .tooFast, .gaining: return TFColor.danger
        case .tooSlow: return TFColor.warning
        case .unknown: return .gray
        }
    }
}
