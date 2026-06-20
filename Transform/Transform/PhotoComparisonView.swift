import SwiftUI
import SwiftData

struct PhotoComparisonView: View {
    let sessions: [BodyAnalysisSession]

    @State private var leftIndex: Int = 0
    @State private var rightIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            if sessions.count < 2 {
                ContentUnavailableView(
                    "Need More Analyses",
                    systemImage: "photo.on.rectangle",
                    description: Text("Complete at least 2 body analyses to compare photos over time.")
                )
            } else {
                comparisonContent
            }
        }
        .navigationTitle("Photo Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            leftIndex = min(sessions.count - 1, 1)
            rightIndex = 0
        }
    }

    var comparisonContent: some View {
        // Clamp at point of use: stored indices can fall out of bounds if `sessions`
        // shrinks (e.g. an analysis is deleted) while this view is on screen.
        let safeLeft = min(max(leftIndex, 0), sessions.count - 1)
        let safeRight = min(max(rightIndex, 0), sessions.count - 1)
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                photoColumn(index: $leftIndex, label: "Before")
                photoColumn(index: $rightIndex, label: "After")
            }
            .padding(.horizontal)

            if let leftResult = sessions[safeLeft].decodedResult,
               let rightResult = sessions[safeRight].decodedResult {
                comparisonDetails(before: leftResult, after: rightResult)
            }

            Spacer()
        }
        .padding(.top)
        .onChange(of: sessions.count) { _, newCount in
            leftIndex = min(max(leftIndex, 0), max(newCount - 1, 0))
            rightIndex = min(max(rightIndex, 0), max(newCount - 1, 0))
        }
    }

    func photoColumn(index: Binding<Int>, label: String) -> some View {
        let safeIndex = min(max(index.wrappedValue, 0), sessions.count - 1)
        return VStack(spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let image = UIImage.downsampledImage(from: sessions[safeIndex].photoData, maxDimension: 400) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("\(label) photo, \(sessions[safeIndex].date.formatted(date: .abbreviated, time: .omitted)), \(sessions[safeIndex].pose)")
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemBackground))
                    .aspectRatio(3/4, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.quaternary)
                    }
            }

            Picker("", selection: index) {
                ForEach(sessions.indices, id: \.self) { i in
                    Text(sessions[i].date.formatted(date: .abbreviated, time: .omitted))
                        .tag(i)
                }
            }
            .pickerStyle(.menu)
            .tint(TFColor.accent)

            Text(sessions[safeIndex].pose)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    func comparisonDetails(before: BodyAnalysisResult, after: BodyAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            HStack(spacing: 16) {
                metricCard(title: "Body Fat", before: before.estimatedBodyFat, after: after.estimatedBodyFat)
                metricCard(title: "Top Leverage Change", before: before.topLeverageChange, after: after.topLeverageChange)
            }
            .padding(.horizontal)

            if before.priorityMuscles != after.priorityMuscles {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Priority Shift")
                        .font(.caption.bold())
                        .foregroundStyle(TFColor.accent)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Before")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(before.priorityMuscles.joined(separator: ", "))
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("After")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(after.priorityMuscles.joined(separator: ", "))
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    func metricCard(title: String, before: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            if before == after {
                Text(after)
                    .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                        Text(before)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(TFColor.accent)
                            .frame(width: 6, height: 6)
                        Text(after)
                            .font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
