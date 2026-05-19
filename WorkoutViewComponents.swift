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
                        .foregroundStyle(.orange)
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
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
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
        .background(day.isCompleted ? Color.green.opacity(0.05) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(day.isCompleted ? Color.green.opacity(0.2) : Color.clear, lineWidth: 1)
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
                        .foregroundStyle(.orange)
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
        .background(day.isCompleted ? Color.green.opacity(0.05) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(day.isCompleted ? Color.green.opacity(0.2) : Color.clear, lineWidth: 1)
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
                        .foregroundStyle(.orange)
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
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
                .tracking(1.2)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
