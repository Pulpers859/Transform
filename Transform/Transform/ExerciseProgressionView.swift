import SwiftUI
import SwiftData
import Charts

struct ExerciseProgressionView: View {
    @Query(sort: \ExercisePerformanceLog.loggedAt, order: .forward) private var allLogs: [ExercisePerformanceLog]
    let exerciseName: String
    let canonicalKey: String

    init(exerciseName: String) {
        self.exerciseName = exerciseName
        self.canonicalKey = ExerciseWeightEntry.canonicalLookupKey(exerciseName)
    }

    var matchingLogs: [ExercisePerformanceLog] {
        allLogs.filter { $0.canonicalExerciseKey == canonicalKey && $0.weightLbs > 0 }
    }

    var chartPoints: [ProgressionPoint] {
        matchingLogs.map { log in
            ProgressionPoint(
                date: log.loggedAt,
                weightLbs: log.weightLbs,
                repsCompleted: log.repsCompleted,
                setLogs: log.decodedSetLogs
            )
        }
    }

    var estimatedOneRepMax: [ProgressionPoint] {
        chartPoints.compactMap { point in
            guard let reps = point.repsCompleted, reps > 0, reps <= 30 else { return nil }
            let e1rm = point.weightLbs * (1 + Double(reps) / 30.0)
            return ProgressionPoint(date: point.date, weightLbs: e1rm, repsCompleted: nil, setLogs: [])
        }
    }

    var weightDomain: ClosedRange<Double> {
        let allWeights = chartPoints.map(\.weightLbs) + estimatedOneRepMax.map(\.weightLbs)
        guard let lo = allWeights.min(), let hi = allWeights.max() else { return 0...100 }
        let padding = max((hi - lo) * 0.15, 10)
        return (lo - padding)...(hi + padding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if chartPoints.count >= 2 {
                    weightChart
                    if !estimatedOneRepMax.isEmpty {
                        e1rmChart
                    }
                } else if chartPoints.count == 1 {
                    singleEntryCard
                } else {
                    emptyState
                }
                if !chartPoints.isEmpty {
                    logHistory
                }
            }
            .padding()
        }
        .navigationTitle("Progression")
        .navigationBarTitleDisplayMode(.inline)
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exerciseName)
                .font(.title2.bold())
            Text("\(chartPoints.count) session\(chartPoints.count == 1 ? "" : "s") logged")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let first = chartPoints.first, let last = chartPoints.last, chartPoints.count >= 2 {
                let delta = last.weightLbs - first.weightLbs
                let days = max(Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1, 1)
                HStack(spacing: 12) {
                    progressBadge(
                        label: "Top set",
                        value: String(format: "%+.1f lb", delta),
                        color: delta >= 0 ? .green : .red
                    )
                    progressBadge(
                        label: "Over",
                        value: "\(days) days",
                        color: .secondary
                    )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func progressBadge(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    var weightChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP SET WEIGHT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
                .tracking(1.5)

            Chart(chartPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weightLbs)
                )
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Weight", point.weightLbs)
                )
                .foregroundStyle(Color.orange)
                .symbolSize(30)
            }
            .chartYScale(domain: weightDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var e1rmChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ESTIMATED 1RM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.purple)
                    .tracking(1.5)
                Spacer()
                Text("Epley formula")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Chart(estimatedOneRepMax) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("e1RM", point.weightLbs)
                )
                .foregroundStyle(Color.purple.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("e1RM", point.weightLbs)
                )
                .foregroundStyle(Color.purple)
                .symbolSize(20)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            .frame(height: 160)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var singleEntryCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundStyle(.orange.opacity(0.4))
            Text("Log at least 2 sessions to see progression charts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("No weight logs yet for this exercise.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var logHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSION HISTORY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
                .tracking(1.5)

            ForEach(chartPoints.reversed()) { point in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(point.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.bold())
                        Spacer()
                        Text("\(formatWeight(point.weightLbs)) lb")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        if let reps = point.repsCompleted {
                            Text("\u{00D7} \(reps)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !point.setLogs.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(point.setLogs) { set in
                                Text("\(formatWeight(set.weightLbs))\u{00D7}\(set.repsCompleted)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
                .padding(.vertical, 6)

                if point.id != chartPoints.first?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func formatWeight(_ weight: Double) -> String {
        weight.rounded() == weight ? String(Int(weight)) : String(format: "%.1f", weight)
    }
}

struct ProgressionPoint: Identifiable {
    let date: Date
    let weightLbs: Double
    let repsCompleted: Int?
    let setLogs: [SetLogEntry]

    var id: Date { date }
}
