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
                    .foregroundStyle(day.isCompleted ? TFColor.success : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(day.isCompleted ? "Mark Day \(day.dayNumber) incomplete" : "Mark Day \(day.dayNumber) complete")

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
                Text("\(day.activeExercises.count) exercise slots")
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
            RoundedRectangle(cornerRadius: TFRadius.cardCompact)
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
    /// Scales with Dynamic Type. The clearance was a flat 104pt while the floating tab bar it
    /// clears is built from text that grows — so at larger accessibility sizes the bar got
    /// taller, the inset did not, and the last card stayed permanently under it with no way
    /// to scroll further. `@ScaledMetric` ties the two together.
    ///
    /// This only governs how far the scroll can travel. Content passing UNDER the floating
    /// bar mid-scroll is inherent to a floating bar and is not what this fixes.
    @ScaledMetric(relativeTo: .caption) private var clearance: CGFloat = 104

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: clearance)
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
                    .foregroundStyle(day.isCompleted ? TFColor.success : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(day.isCompleted ? "Mark Day \(day.dayNumber) incomplete" : "Mark Day \(day.dayNumber) complete")

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
                .foregroundStyle(TFColor.sleep.opacity(0.5))
        }
        .padding(14)
        .background(day.isCompleted ? TFColor.success.opacity(0.05) : TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        .overlay(
            RoundedRectangle(cornerRadius: TFRadius.cardCompact)
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
                    ? "Rest and recover today."
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
        // Match WorkoutDayDetailView: hard top edge so scrolled content never reads
        // through the inline nav title.
        .scrollEdgeEffectStyle(.hard, for: .top)
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

    /// Rated sessions outside deload weeks; the rules live in `WorkoutTimingInsights`.
    private var timedSessions: [WorkoutTimingInsights.Session] {
        WorkoutTimingInsights.counted(allDays.compactMap { day in
            guard let start = day.sessionStartedAt, day.hasSessionFeedback else { return nil }
            let performance: Int
            switch day.performanceRating {
            case .better: performance = 1
            case .worse: performance = -1
            default: performance = 0
            }
            return WorkoutTimingInsights.Session(
                hour: Calendar.current.component(.hour, from: start),
                effort: day.sessionEffort,
                stimulus: day.stimulusQuality,
                performance: performance,
                isDeload: day.isDeloadWeek
            )
        })
    }

    private var hourBuckets: [WorkoutTimingInsights.Bucket] {
        WorkoutTimingInsights.buckets(timedSessions)
    }

    private var bestBucket: WorkoutTimingInsights.Bucket? {
        WorkoutTimingInsights.best(hourBuckets)
    }

    var body: some View {
        if timedSessions.count >= WorkoutTimingInsights.minimumSessions {
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
                            // A slot with too few sessions to compare is drawn faint, so a tall bar
                            // from one good session does not read as a result.
                            RoundedRectangle(cornerRadius: 4)
                                .fill(bucket.label == bestBucket?.label ? Color.orange
                                      : TFColor.accent.opacity(bucket.sessionCount >= WorkoutTimingInsights.minimumSessions ? 0.3 : 0.1))
                                .frame(height: max(8, CGFloat(min(bucket.score / WorkoutTimingInsights.maximumScore, 1)) * 60))

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
                        Text("Best results so far: **\(best.label.replacingOccurrences(of: "\n", with: " "))** — \(best.sessionCount) sessions, avg stimulus \(String(format: "%.1f", best.avgStimulus))/5")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if bestBucket == nil {
                    // Say why there is no best, so the card never just sits there.
                    let comparable = WorkoutTimingInsights.eligibleBuckets(hourBuckets).count
                    Text(comparable >= 2 ? "No time of day stands out yet."
                         : comparable == 1 ? "Only one time of day has enough sessions to compare so far."
                         : "Not enough sessions at any one time of day to compare yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if timedSessions.count < 10 {
                    Text("More sessions make this more accurate.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .dashCard()
        }
    }
}


