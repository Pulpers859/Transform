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
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                photoColumn(index: $leftIndex, label: "Before")
                photoColumn(index: $rightIndex, label: "After")
            }
            .padding(.horizontal)

            if let leftResult = sessions[leftIndex].decodedResult,
               let rightResult = sessions[rightIndex].decodedResult {
                comparisonDetails(before: leftResult, after: rightResult)
            }

            Spacer()
        }
        .padding(.top)
    }

    func photoColumn(index: Binding<Int>, label: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let image = UIImage(data: sessions[index.wrappedValue].photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3/4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .tint(.orange)

            Text(sessions[index.wrappedValue].pose)
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
                        .foregroundStyle(.orange)

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
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text(after)
                            .font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
