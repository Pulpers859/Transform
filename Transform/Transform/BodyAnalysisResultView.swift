import SwiftUI

// MARK: - Live Analysis Result View (after running analysis)

struct BodyAnalysisResultView: View {
    let result: BodyAnalysisResult
    let photos: [AnalysisPhoto]
    var validationReport: AnalysisValidationReport? = nil
    let onSave: () -> Void

    @State private var showDebugPanel = false
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                if showDebugPanel {
                    analysisDebugPanel
                }

                // Photo(s) display
                if photos.count == 1, let photo = photos.first {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(photo.pose)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(10)
                    }
                } else {
                    // Multi-photo thumbnail strip
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { photo in
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: photo.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 160, height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    Text(photo.pose)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.orange)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                        .padding(6)
                                }
                            }
                        }
                    }
                }

                // Shared analysis content
                AnalysisResultContent(result: result)
                    .onLongPressGesture(minimumDuration: 1.2) {
                        withAnimation { showDebugPanel.toggle() }
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }

                // Save button
                if let report = validationReport, !report.isUsable {
                    VStack(spacing: 6) {
                        Label("Cannot save — critical validation issues detected", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                        Text("Long-press the result to open the debug panel and review issues. Re-run the analysis to try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
                } else {
                    Button(action: {
                        onSave()
                    }) {
                        Label("Save Analysis", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .bold()
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle("Analysis Result")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.caption.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { toastMessage = nil }
                        }
                    }
            }
        }
    }

    // MARK: - Debug Panel (long-press to reveal)

    var analysisDebugPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Analysis Debug", systemImage: "ant.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.purple)
                Spacer()
                Button {
                    withAnimation { showDebugPanel = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if let report = validationReport {
                ValidationReportCard(report: report)
            } else {
                Text("No validation report available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                debugCopyButton(title: "Copy JSON", payload: analysisJSONBundle)
                debugCopyButton(title: "Copy Summary", payload: analysisSummaryBundle)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func debugCopyButton(title: String, payload: String) -> some View {
        Button {
            UIPasteboard.general.string = payload
            withAnimation(.easeOut(duration: 0.2)) {
                toastMessage = "\(title) copied"
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.purple.opacity(0.12))
                .foregroundStyle(.purple)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    var analysisJSONBundle: String {
        guard let data = try? JSONEncoder().encode(result),
              let json = String(data: data, encoding: .utf8) else {
            return "(encoding failed)"
        }
        return json
    }

    var analysisSummaryBundle: String {
        var lines: [String] = []
        lines.append("=== BODY ANALYSIS DEBUG BUNDLE ===")
        lines.append("Photos: \(photos.map(\.pose).joined(separator: ", "))")
        lines.append("")
        lines.append("--- Overall ---")
        lines.append(result.overallAssessment)
        lines.append("")
        lines.append("--- Body Fat ---")
        lines.append(result.estimatedBodyFat)
        lines.append("")
        lines.append("--- Top Leverage ---")
        lines.append(result.topLeverageChange)
        lines.append("")
        lines.append("--- Priority Muscles ---")
        lines.append(result.priorityMuscles.joined(separator: ", "))
        lines.append("")

        if let macros = result.macroTargets {
            lines.append("--- Macro Targets ---")
            lines.append("Calories: \(macros.calories), Protein: \(Int(macros.proteinG))g, Carbs: \(Int(macros.carbsG))g, Fat: \(Int(macros.fatG))g")
            if let rationale = macros.macroRationale {
                lines.append("Rationale: \(rationale)")
            }
            lines.append("")
        }

        if let intent = result.structuredTrainingIntent {
            lines.append("--- Training Intent ---")
            lines.append("Split: \(intent.splitRecommendation), Days: \(intent.weeklyTrainingDays)")
            for p in intent.priorities {
                lines.append("  \(p.area) [\(p.priorityLevel)]: \(p.weeklyDayTarget)d/wk, \(p.weeklyExerciseTarget) exercises, \(p.volumeBias) volume")
            }
            lines.append("")
        }

        lines.append("--- Regions ---")
        for r in result.regionBreakdown {
            lines.append("  \(r.region) [\(r.priority)]: \(r.assessment)")
        }
        lines.append("")

        if let report = validationReport, !report.issues.isEmpty {
            lines.append("--- Validation (\(report.issues.count) issues) ---")
            for issue in report.sortedIssues {
                lines.append("  [\(issue.severity.rawValue)] \(issue.field): \(issue.message)")
            }
        } else {
            lines.append("--- Validation: CLEAN ---")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Shared Analysis Content (used by both live + saved views)

struct AnalysisResultContent: View {
    let result: BodyAnalysisResult
    @State private var showContextDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Estimated body fat
            if !result.estimatedBodyFat.isEmpty {
                SectionCard(title: "Estimated Body Fat", icon: "percent") {
                    Text(result.estimatedBodyFat)
                        .font(.title2.bold())
                        .foregroundStyle(.orange)
                }
            }

            // Top leverage change
            if !result.topLeverageChange.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Highest Leverage Change", systemImage: "arrow.up.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(result.topLeverageChange)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding()
                .background(Color.orange)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            SectionCard(title: "Photo-Based Scope", icon: "info.circle") {
                Text(result.resolvedAnalysisLimitations)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let inputContext = result.inputContext {
                SectionCard(title: "Context Used", icon: "text.badge.checkmark") {
                    CompactContextCard(
                        intro: "The analysis used your saved profile, check-in, and recent progress context.",
                        summaryItems: inputContext.compactSummaryItems,
                        detailSections: inputContext.detailSections,
                        isExpanded: $showContextDetails
                    )
                }
            }

            // Overall assessment
            SectionCard(title: "Overall Assessment", icon: "figure.arms.open") {
                Text(result.overallAssessment)
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            // Region breakdown
            if !result.regionBreakdown.isEmpty {
                SectionCard(title: "Region Breakdown", icon: "list.bullet.clipboard") {
                    VStack(spacing: 10) {
                        ForEach(result.regionBreakdown) { region in
                            RegionRow(region: region)
                        }
                    }
                }
            }

            // Programming priorities
            if !result.programmingPriorityAreas.isEmpty {
                SectionCard(title: "Top Muscle Groups to Prioritize", icon: "flame.fill") {
                    Text("These are the main muscle groups the workout plan should prioritize with extra hypertrophy attention.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(items: result.programmingPriorityAreas) { muscle in
                        Text(muscle)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            // High-priority regions
            if !result.highPriorityRegionsToAddress.isEmpty {
                SectionCard(title: "High-Priority Regions to Address", icon: "exclamationmark.circle.fill") {
                    Text("These are the highest-need regions from the analysis overall. They may reflect body composition, posture, or presentation concerns, not just muscles that need more direct hypertrophy work.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    FlowLayout(items: result.highPriorityRegionsToAddress) { region in
                        Text(region)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.12))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
            }

            // Training
            if !result.resolvedTrainingAssessment.isEmpty || !result.workoutRecommendations.isEmpty {
                SectionCard(title: "Training", icon: "dumbbell.fill") {
                    if !result.resolvedTrainingAssessment.isEmpty {
                        Text(result.resolvedTrainingAssessment)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    if !result.workoutRecommendations.isEmpty {
                        if !result.resolvedTrainingAssessment.isEmpty {
                            Divider()
                        }
                        BulletList(items: result.workoutRecommendations)
                    }
                }
            }

            // Nutrition
            if !result.resolvedNutritionAssessment.isEmpty || !result.dietRecommendations.isEmpty || result.macroTargets != nil {
                SectionCard(title: "Nutrition", icon: "fork.knife") {
                    if !result.resolvedNutritionAssessment.isEmpty {
                        Text(result.resolvedNutritionAssessment)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    if !result.dietRecommendations.isEmpty {
                        if !result.resolvedNutritionAssessment.isEmpty {
                            Divider()
                        }
                        BulletList(items: result.dietRecommendations)
                    }
                    if let macros = result.macroTargets {
                        if !result.dietRecommendations.isEmpty || !result.resolvedNutritionAssessment.isEmpty {
                            Divider()
                        }
                        let resolved = MacroTargetResolver.resolve(from: result)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Recommended Macro Targets")
                                .font(.subheadline.bold())
                            Text("Calories: \(resolved.calories) kcal/day")
                            Text("Protein: \(Int(resolved.proteinG)) g/day")
                            Text("Carbs: \(Int(resolved.carbsG)) g/day")
                            Text("Fat: \(Int(resolved.fatG)) g/day")
                            if let rationale = macros.macroRationale,
                               !rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(rationale)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                            if resolved.wasAdjustedBySafetyFloor {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(resolved.floorAdjustments, id: \.self) { adjustment in
                                        Text(adjustment)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    }
                }
            }

            // Recovery & Risk
            if !result.resolvedRecoveryRiskAssessment.isEmpty
                || !result.posturalNotes.isEmpty
                || !result.injuryRiskNotes.isEmpty
                || !result.metabolicHealthNotes.isEmpty {
                SectionCard(title: "Recovery & Risk", icon: "heart.text.clipboard") {
                    if !result.resolvedRecoveryRiskAssessment.isEmpty {
                        Text(result.resolvedRecoveryRiskAssessment)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    let supportNotes = [
                        ("Postural Notes", result.posturalNotes),
                        ("Injury / Loading Risk", result.injuryRiskNotes),
                        ("Recovery / Energy Management", result.metabolicHealthNotes)
                    ].filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                    if !supportNotes.isEmpty {
                        if !result.resolvedRecoveryRiskAssessment.isEmpty {
                            Divider()
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(supportNotes, id: \.0) { note in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.0)
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                    Text(note.1)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }

            // Adherence
            if !result.resolvedAdherenceAssessment.isEmpty {
                SectionCard(title: "Adherence", icon: "brain.head.profile") {
                    Text(result.resolvedAdherenceAssessment)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct RegionRow: View {
    let region: RegionAssessment

    var priorityColor: Color {
        switch region.priority {
        case "High": return .red
        case "Medium": return .orange
        default: return .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(region.region)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(region.priority)
                        .font(.caption)
                        .foregroundStyle(priorityColor)
                }
                Text(region.assessment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.orange)
            content()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}").foregroundStyle(.orange)
                    Text(item).font(.subheadline)
                }
            }
        }
    }
}

struct CompactContextCard: View {
    let intro: String
    let summaryItems: [String]
    let detailSections: [AnalysisContextSection]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(intro)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !summaryItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summaryItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.orange)
                                .padding(.top, 6)
                            Text(item)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            if !detailSections.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(detailSections.enumerated()), id: \.offset) { _, section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                                ForEach(section.items, id: \.self) { item in
                                    Text("• \(item)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(isExpanded ? "Hide details" : "Show details")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

// MARK: - Validation Report Card

struct ValidationReportCard: View {
    let report: AnalysisValidationReport
    @State private var isExpanded = false

    private var headerColor: Color {
        switch report.highestSeverity {
        case .critical, .error: return .red
        case .warning: return .orange
        default: return .secondary
        }
    }

    private var headerIcon: String {
        switch report.highestSeverity {
        case .critical: return "xmark.octagon.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        default: return "info.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: headerIcon)
                        .foregroundStyle(headerColor)
                    Text(headerText)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.sortedIssues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(severityColor(issue.severity))
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(issue.severity.rawValue)] \(issue.field)")
                                    .font(.caption.bold())
                                    .foregroundStyle(severityColor(issue.severity))
                                Text(issue.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(headerColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var headerText: String {
        let counts = Dictionary(grouping: report.issues, by: \.severity)
        var parts: [String] = []
        if let c = counts[.critical]?.count, c > 0 { parts.append("\(c) critical") }
        if let e = counts[.error]?.count, e > 0 { parts.append("\(e) error\(e > 1 ? "s" : "")") }
        if let w = counts[.warning]?.count, w > 0 { parts.append("\(w) warning\(w > 1 ? "s" : "")") }
        if let i = counts[.info]?.count, i > 0 { parts.append("\(i) info") }
        return "Validation: \(parts.joined(separator: ", "))"
    }

    private func severityColor(_ severity: AnalysisValidationSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .error: return .red.opacity(0.8)
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}

struct FlowLayout<T: Hashable, Content: View>: View {
    let items: [T]
    let content: (T) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
