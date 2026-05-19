import SwiftUI
import SwiftData

struct BodyAnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var sessions: [BodyAnalysisSession]

    // Multi-photo state
    @State private var photos: [AnalysisPhoto] = []
    @State private var currentPose = "Front"
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var capturedImage: UIImage?

    @State private var isAnalyzing = false
    @State private var analysisResult: BodyAnalysisResult?
    @State private var showResult = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDeleteConfirm = false
    @State private var sessionToDelete: BodyAnalysisSession?
    @State private var analysisTask: Task<Void, Never>?

    let poses = ["Front", "Back", "Side (Left)", "Side (Right)"]

    var unusedPoses: [String] {
        let used = Set(photos.map { $0.pose })
        return poses.filter { !used.contains($0) }
    }

    var canUseAI: Bool {
        Config.hasAnthropicKey
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    photoCollectionCard
                    if !photos.isEmpty {
                        analyzeButton
                        if !canUseAI {
                            Text("Set your API key in Config to run AI analysis.")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    if !sessions.isEmpty {
                        pastSessionsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Body Analysis")
            .navigationDestination(isPresented: $showResult) {
                if let result = analysisResult {
                    BodyAnalysisResultView(
                        result: result,
                        photos: photos,
                        onSave: { saveSession(result: result) }
                    )
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(selectedImage: $capturedImage, sourceType: .camera)
            }
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePicker(selectedImage: $capturedImage, sourceType: .photoLibrary)
            }
            .onChange(of: capturedImage) { _, newImage in
                if let img = newImage {
                    let photo = AnalysisPhoto(image: img, pose: currentPose)
                    photos.append(photo)
                    capturedImage = nil
                    // Auto-advance to next unused pose
                    if let nextPose = unusedPoses.first {
                        currentPose = nextPose
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .onDisappear {
                analysisTask?.cancel()
                analysisTask = nil
                isAnalyzing = false
            }
            .alert("Analysis Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .alert("Delete Analysis?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        deleteSession(session)
                    }
                }
                Button("Cancel", role: .cancel) {
                    sessionToDelete = nil
                }
            } message: {
                Text("This will permanently remove this analysis and its photo.")
            }
        }
    }

    // MARK: - Multi-Photo Collection Card

    var photoCollectionCard: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Physique Photos")
                        .font(.headline)
                    Text("\(photos.count) of 4 angles · More angles = better analysis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !photos.isEmpty {
                    Button("Clear All") {
                        photos.removeAll()
                        currentPose = "Front"
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

            // Photo grid
            if photos.isEmpty {
                emptyPhotoPlaceholder
            } else {
                photoGrid
            }

            // Add more photos if we have room
            if photos.count < 4 {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Photo tip: stand relaxed and neutral (not flexing/posing) with consistent lighting for the most accurate analysis.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                addPhotoSection
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    var emptyPhotoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.tertiarySystemBackground))
            .frame(height: 200)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text("Add photos for analysis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Front + Back + Sides recommended")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
    }

    var photoGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Pose badge
                    Text(photo.pose)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    Button {
                        photos.remove(at: index)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .black.opacity(0.5))
                            .padding(6)
                    }
                }
            }
        }
    }

    var addPhotoSection: some View {
        VStack(spacing: 10) {
            // Pose selector for next photo
            if !unusedPoses.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Next:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(unusedPoses, id: \.self) { pose in
                            Button(pose) {
                                currentPose = pose
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(currentPose == pose ? Color.orange : Color(.tertiarySystemBackground))
                            .foregroundStyle(currentPose == pose ? .white : .primary)
                            .clipShape(Capsule())
                            .font(.caption.bold())
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                photoButton(label: "Camera", icon: "camera.fill") {
                    showCamera = true
                }
                photoButton(label: "Library", icon: "photo.fill") {
                    showPhotoLibrary = true
                }
            }
        }
    }

    func photoButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Analyze Button

    var analyzeButton: some View {
        Button {
            startAnalysis()
        } label: {
            HStack {
                if isAnalyzing {
                    ProgressView()
                        .tint(.white)
                        .padding(.trailing, 4)
                    Text("Analyzing \(photos.count) photo\(photos.count == 1 ? "" : "s")...")
                } else {
                    Image(systemName: "sparkles")
                    Text("Analyze My Physique")
                    if photos.count > 1 {
                        Text("(\(photos.count) photos)")
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isAnalyzing ? Color.orange.opacity(0.6) : Color.orange)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .bold()
        }
        .disabled(isAnalyzing || !canUseAI)
    }

    // MARK: - Past Sessions with Delete

    var pastSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Analyses")
                .font(.headline)

            ForEach(sessions.prefix(10)) { session in
                NavigationLink(destination: savedAnalysisDestination(session)) {
                    PastSessionRow(session: session)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        sessionToDelete = session
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sessionToDelete = session
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    func savedAnalysisDestination(_ session: BodyAnalysisSession) -> some View {
        if let result = session.decodedResult {
            SavedFullAnalysisView(session: session, result: result)
        } else {
            SavedAnalysisView(session: session)
        }
    }

    // MARK: - Logic

    @MainActor
    func startAnalysis() {
        analysisTask?.cancel()
        analysisTask = Task {
            await runAnalysis()
        }
    }

    @MainActor
    func runAnalysis() async {
        guard !Task.isCancelled else { return }
        isAnalyzing = true
        defer {
            if !Task.isCancelled {
                isAnalyzing = false
                analysisTask = nil
            }
        }

        do {
            let result = try await ClaudeService.shared.analyzeBody(photos: photos)
            try Task.checkCancellation()
            guard !Task.isCancelled else { return }
            analysisResult = result
            showResult = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            showError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func saveSession(result: BodyAnalysisResult) {
        // Use first photo as the thumbnail
        guard let firstPhoto = photos.first,
              let imageData = firstPhoto.image.jpegData(compressionQuality: 0.7) else { return }

        let poseLabel = photos.map { $0.pose }.joined(separator: " + ")

        // Encode full result as JSON for storage
        let jsonString: String
        do {
            let jsonData = try JSONEncoder().encode(result)
            guard let encoded = String(data: jsonData, encoding: .utf8) else {
                throw ClaudeError.parseError("Could not convert encoded analysis JSON into UTF-8 text.")
            }
            jsonString = encoded
        } catch {
            errorMessage = "Could not save this analysis because the full result could not be encoded."
            showError = true
            print("[BodyAnalysisView] Failed to encode analysis result for storage: \(error)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        let session = BodyAnalysisSession(
            photoData: imageData,
            pose: poseLabel,
            analysisResult: result.overallAssessment,
            priorityMuscles: result.programmingPrioritySummary,
            dietRecommendation: result.dietRecommendations.first ?? "",
            analysisJSON: jsonString,
            photoCount: photos.count
        )
        modelContext.insert(session)
        guard PersistenceReporter.save(modelContext, operation: "analysis session") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        photos.removeAll()
        currentPose = poses.first ?? "Front"
        analysisResult = nil
        showResult = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func deleteSession(_ session: BodyAnalysisSession) {
        modelContext.delete(session)
        guard PersistenceReporter.save(modelContext, operation: "analysis session deletion") else {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        sessionToDelete = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Past Session Row

struct PastSessionRow: View {
    let session: BodyAnalysisSession

    var body: some View {
        HStack(spacing: 12) {
            if let image = UIImage(data: session.photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.pose)
                        .font(.subheadline.bold())
                    if session.photoCount > 1 {
                        Text("\(session.photoCount) photos")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(session.programmingPrioritySummary)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Saved Analysis (Legacy — minimal data)

struct SavedAnalysisView: View {
    let session: BodyAnalysisSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = UIImage(data: session.photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                SectionCard(title: "Assessment", icon: "doc.text") {
                    Text(session.analysisResult)
                }

                SectionCard(title: "Top Muscle Groups to Prioritize", icon: "flame.fill") {
                    Text(session.programmingPrioritySummary)
                        .foregroundStyle(.orange)
                }

                SectionCard(title: "Diet Note", icon: "fork.knife") {
                    Text(session.dietRecommendation)
                }
            }
            .padding()
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Saved Full Analysis (New — full JSON data)

struct SavedFullAnalysisView: View {
    let session: BodyAnalysisSession
    let result: BodyAnalysisResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Photo
                if let image = UIImage(data: session.photoData) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(session.pose)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }

                // Reuse the same layout as BodyAnalysisResultView
                AnalysisResultContent(result: result)
            }
            .padding()
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
    }
}
