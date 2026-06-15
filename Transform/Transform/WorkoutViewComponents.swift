import SwiftUI
import SwiftData

struct TrainingDayCard: View {
    let day: WorkoutDay
    let onToggle: () -> Void

    private var includesDirectCoreWork: Bool {
        day.exercises.contains(where: isDirectCoreExercise)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle()
            } label: {
                Image(systemName: day.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(day.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Day \(day.dayNumber)")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)
                    Text(day.dayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(day.muscleGroups)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if includesDirectCoreWork {
                        Text("Core")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(TFColor.accent.opacity(0.15))
                            .foregroundStyle(TFColor.accent)
                            .clipShape(Capsule())
                    }
                }
                Text("\(day.exercises.count) exercises")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(day.isCompleted ? TFColor.success.opacity(0.05) : TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(day.isCompleted ? TFColor.success.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    private func isDirectCoreExercise(_ exercise: WorkoutExercise) -> Bool {
        let combined = "\(exercise.exerciseName) \(exercise.muscleTarget)".lowercased()
        let exclusionKeywords = [
            "farmer", "carry", "walk", "suitcase", "yoke"
        ]
        if exclusionKeywords.contains(where: combined.contains) {
            return false
        }

        let keywords = [
            "core", "abs", "abdominal", "oblique", "serratus", "crunch",
            "plank", "pallof", "rollout", "dead bug", "hollow",
            "leg raise", "knee raise", "ab wheel"
        ]
        return keywords.contains { combined.contains($0) }
    }
}

private struct WorkoutTabBarClearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 104)
        }
    }
}

extension View {
    func workoutTabBarClearance() -> some View {
        modifier(WorkoutTabBarClearanceModifier())
    }
}

// MARK: - Rest Day Card

struct RestDayCard: View {
    let day: WorkoutDay
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle()
            } label: {
                Image(systemName: day.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(day.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Day \(day.dayNumber)")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)
                    Text("Rest / Recovery")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                if !day.notes.isEmpty {
                    Text(day.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "bed.double.fill")
                .font(.caption)
                .foregroundStyle(.blue.opacity(0.5))
        }
        .padding(14)
        .background(day.isCompleted ? TFColor.success.opacity(0.05) : TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(day.isCompleted ? TFColor.success.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}

struct RestDayDetailView: View {
    let day: WorkoutDay

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Day \(day.dayNumber)")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)
                    Text(day.dayName)
                        .font(.title3.bold())
                    Text("Rest / Recovery")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                detailCard(
                    title: "Recovery Focus",
                    text: day.notes.isEmpty
                    ? "No additional guidance was provided for this recovery day."
                    : day.notes
                )

                detailCard(
                    title: "Status",
                    text: day.isCompleted
                    ? "Marked complete."
                    : "Not marked complete yet."
                )

                Spacer(minLength: 16)
            }
            .padding()
        }
        .workoutTabBarClearance()
        .navigationTitle("Recovery Day")
        .navigationBarTitleDisplayMode(.inline)
    }

    func detailCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TFSectionLabel(text: title)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }
}

// MARK: - Workout Timing Insights Card

struct WorkoutTimingInsightsCard: View {
    @Query(sort: \WorkoutDay.dayNumber) private var allDays: [WorkoutDay]

    private var timedSessions: [(hour: Int, effort: Int, stimulus: Int, performance: WorkoutPerformanceRating?)] {
        allDays.compactMap { day in
            guard let start = day.sessionStartedAt, day.hasSessionFeedback else { return nil }
            let hour = Calendar.current.component(.hour, from: start)
            return (hour, day.sessionEffort, day.stimulusQuality, day.performanceRating)
        }
    }

    private var hourBuckets: [TimeBucket] {
        guard timedSessions.count >= 3 else { return [] }
        let bucketRanges: [(label: String, range: ClosedRange<Int>)] = [
            ("Early AM\n5-8", 5...8),
            ("Morning\n9-11", 9...11),
            ("Midday\n12-14", 12...14),
            ("Afternoon\n15-17", 15...17),
            ("Evening\n18-20", 18...20),
            ("Night\n21+", 21...23)
        ]
        return bucketRanges.compactMap { bucket in
            let sessions = timedSessions.filter { bucket.range.contains($0.hour) }
            guard !sessions.isEmpty else { return nil }
            let avgStimulus = Double(sessions.map(\.stimulus).reduce(0, +)) / Double(sessions.count)
            let avgEffort = Double(sessions.map(\.effort).reduce(0, +)) / Double(sessions.count)
            let betterCount = sessions.filter { $0.performance == .better }.count
            let worseCount = sessions.filter { $0.performance == .worse }.count
            let score = avgStimulus * 0.5 + (5.0 - avgEffort) * 0.2 + Double(betterCount - worseCount) * 0.3
            return TimeBucket(label: bucket.label, sessionCount: sessions.count, avgStimulus: avgStimulus, avgEffort: avgEffort, score: score)
        }
    }

    private var bestBucket: TimeBucket? {
        hourBuckets.max(by: { $0.score < $1.score })
    }

    var body: some View {
        if timedSessions.count >= 3 {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(TFColor.accent)
                    TFSectionLabel(text: "Workout Timing")
                    Spacer()
                    Text("\(timedSessions.count) sessions")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(hourBuckets, id: \.label) { bucket in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(bucket.label == bestBucket?.label ? Color.orange : TFColor.accent.opacity(0.3))
                                .frame(height: max(8, CGFloat(bucket.score / 5.0) * 60))

                            Text("\(bucket.sessionCount)")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text(bucket.label)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 100)

                if let best = bestBucket {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                        Text("Best results: **\(best.label.replacingOccurrences(of: "\n", with: " "))** — avg stimulus \(String(format: "%.1f", best.avgStimulus))/5, effort \(String(format: "%.1f", best.avgEffort))/5")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if timedSessions.count < 10 {
                    Text("Patterns become more reliable with more logged sessions. Keep tracking!")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .dashCard()
        }
    }
}

private struct TimeBucket {
    let label: String
    let sessionCount: Int
    let avgStimulus: Double
    let avgEffort: Double
    let score: Double
}
