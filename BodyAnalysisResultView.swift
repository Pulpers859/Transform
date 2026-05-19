import SwiftUI

// MARK: - Live Analysis Result View (after running analysis)

struct BodyAnalysisResultView: View {
    let result: BodyAnalysisResult
    let photos: [AnalysisPhoto]
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

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

                // Save button
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
            .padding()
        }
        .navigationTitle("Analysis Result")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared Analysis Content (used by both live + saved views)

struct AnalysisResultContent: View {
    let result: BodyAnalysisResult

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

            // Workout recommendations (Exercise Physiologist)
            if !result.workoutRecommendations.isEmpty {
                SectionCard(title: "Training Focus", icon: "dumbbell.fill") {
                    SpecialistBadge(name: "Exercise Physiologist", color: .blue)
                    BulletList(items: result.workoutRecommendations)
                }
            }

            // Diet recommendations (Sports Dietitian)
            if !result.dietRecommendations.isEmpty {
                SectionCard(title: "Diet Recommendations", icon: "fork.knife") {
                    SpecialistBadge(name: "Sports Dietitian", color: .green)
                    BulletList(items: result.dietRecommendations)
                }
            }

            if let macros = result.macroTargets {
                SectionCard(title: "Recommended Macro Targets", icon: "target") {
                    SpecialistBadge(name: "Sports Dietitian", color: .green)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Calories: \(macros.calories) kcal/day")
                        Text("Protein: \(Int(macros.proteinG)) g/day")
                        Text("Carbs: \(Int(macros.carbsG)) g/day")
                        Text("Fat: \(Int(macros.fatG)) g/day")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                }
            }

            // Metabolic health (Physician)
            if !result.metabolicHealthNotes.isEmpty {
                SectionCard(title: "Metabolic Health", icon: "heart.text.clipboard") {
                    SpecialistBadge(name: "Sports Medicine Physician", color: .red)
                    Text(result.metabolicHealthNotes)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            // Injury risk (Physician)
            if !result.injuryRiskNotes.isEmpty {
                SectionCard(title: "Injury Risk Assessment", icon: "exclamationmark.shield") {
                    SpecialistBadge(name: "Sports Medicine Physician", color: .red)
                    Text(result.injuryRiskNotes)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            // Psychological insights (Sport Psychologist)
            if !result.psychologicalInsights.isEmpty {
                SectionCard(title: "Behavioral & Adherence", icon: "brain.head.profile") {
                    SpecialistBadge(name: "Sport Psychologist", color: .purple)
                    Text(result.psychologicalInsights)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            // Postural notes
            if !result.posturalNotes.isEmpty {
                SectionCard(title: "Postural Notes", icon: "person.fill") {
                    Text(result.posturalNotes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Specialist Badge

struct SpecialistBadge: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.caption2.bold())
                .foregroundStyle(color)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.bottom, 4)
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
