import SwiftUI
import SwiftData

struct BodyAnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyAnalysisSession.date, order: .reverse) private var sessions: [BodyAnalysisSession]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weightEntries: [WeightEntry]
    @Query(sort: \NutritionEntry.date, order: .reverse) private var nutritionEntries: [NutritionEntry]
    @Query(sort: \ExerciseWeightEntry.loggedAt, order: .reverse) private var exerciseWeightEntries: [ExerciseWeightEntry]
    @Query(sort: \ExercisePerformanceLog.loggedAt, order: .reverse) private var exercisePerformanceLogs: [ExercisePerformanceLog]
    @Query(sort: \MeasurementEntry.date, order: .reverse) private var measurementEntries: [MeasurementEntry]

    // Multi-photo state
    @State private var photos: [AnalysisPhoto] = []
    @State private var currentPose = "Front"
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var capturedImage: UIImage?

    @State private var isAnalyzing = false
    @State private var analysisResult: BodyAnalysisResult?
    @State private var validationReport: AnalysisValidationReport?
    @State private var showResult = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showDeleteConfirm = false
    @State private var showMedicalGateAlert = false
    @State private var sessionToDelete: BodyAnalysisSession?
    @State private var analysisTask: Task<Void, Never>?
    @State private var showProgressContextDetails = false
    @AppStorage(AppSettingsKeys.analysisCheckInTrainingContext) private var analysisCheckInTrainingContext = Config.defaultAnalysisCheckInTrainingContext
    @AppStorage(AppSettingsKeys.analysisCheckInBodyweightTrend) private var analysisCheckInBodyweightTrend = Config.defaultAnalysisCheckInBodyweightTrend
    @AppStorage(AppSettingsKeys.analysisCheckInRecoverySleep) private var analysisCheckInRecoverySleep = Config.defaultAnalysisCheckInRecoverySleep
    @AppStorage(AppSettingsKeys.analysisCheckInStressSchedule) private var analysisCheckInStressSchedule = Config.defaultAnalysisCheckInStressSchedule
    @AppStorage(AppSettingsKeys.analysisCheckInSorenessPain) private var analysisCheckInSorenessPain = Config.defaultAnalysisCheckInSorenessPain
    @AppStorage(AppSettingsKeys.analysisCheckInNutritionAdherence) private var analysisCheckInNutritionAdherence = Config.defaultAnalysisCheckInNutritionAdherence
    @AppStorage(AppSettingsKeys.analysisCheckInHungerLevel) private var analysisCheckInHungerLevel = Config.defaultAnalysisCheckInHungerLevel
    @AppStorage(AppSettingsKeys.analysisCheckInEnergyLevel) private var analysisCheckInEnergyLevel = Config.defaultAnalysisCheckInEnergyLevel
    @AppStorage(AppSettingsKeys.analysisCheckInCravingsLevel) private var analysisCheckInCravingsLevel = Config.defaultAnalysisCheckInCravingsLevel
    @AppStorage(AppSettingsKeys.derivedSleepTrendSummary) private var derivedSleepTrendSummary = ""

    let poses = ["Front", "Back", "Side (Left)", "Side (Right)"]

    var unusedPoses: [String] {
        let used = Set(photos.map { $0.pose })
        return poses.filter { !used.contains($0) }
    }

    var canUseAI: Bool {
        Config.hasAnthropicKey
    }

    var hasCheckInContext: Bool {
        [
            analysisCheckInTrainingContext,
            analysisCheckInBodyweightTrend,
            analysisCheckInRecoverySleep,
            analysisCheckInStressSchedule,
            analysisCheckInSorenessPain,
            analysisCheckInNutritionAdherence
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || analysisCheckInHungerLevel > 0
            || analysisCheckInEnergyLevel > 0
            || analysisCheckInCravingsLevel > 0
    }

    var previousAnalysisSession: BodyAnalysisSession? {
        sessions.first
    }

    var previousAnalysisResult: BodyAnalysisResult? {
        previousAnalysisSession?.decodedResult
    }

    var automaticProgressSnapshot: AnalysisProgressSnapshot? {
        guard let previousAnalysisSession, let previousAnalysisResult else {
            return nil
        }

        let macroTargets = MacroTargetResolver.resolve(from: previousAnalysisResult)
        return AnalysisProgressSnapshotBuilder.build(
            previousAnalysisDate: previousAnalysisSession.date,
            previousPriorityAreas: previousAnalysisResult.programmingPriorityAreas,
            previousTopLeverageChange: previousAnalysisResult.topLeverageChange,
            weightPoints: weightPoints(since: previousAnalysisSession.date),
            nutritionDays: nutritionDaySummaries(since: previousAnalysisSession.date),
            macroTargets: AnalysisMacroTargetSnapshot(
                calories: macroTargets.calories,
                proteinG: macroTargets.proteinG,
                carbsG: macroTargets.carbsG,
                fatG: macroTargets.fatG
            ),
            exerciseEvents: exercisePerformanceEvents(),
            exerciseSnapshots: exerciseProgressSnapshots()
        )
    }

    var measurementTrendSnapshot: MeasurementTrendSnapshot? {
        let entries = measurementEntries.map { m in
            MeasurementTrendInput(
                date: m.date,
                waistIn: m.waistIn,
                neckIn: m.neckIn,
                hipsIn: m.hipsIn,
                chestIn: m.chestIn,
                rightArmIn: m.rightArmIn,
                leftArmIn: m.leftArmIn,
                rightThighIn: m.rightThighIn,
                leftThighIn: m.leftThighIn,
                isStandard: m.isStandardMeasurement,
                bodyweightLbs: nil
            )
        }
        guard !entries.isEmpty else { return nil }

        let wPoints = weightEntries.map {
            AnalysisLoggedWeightPoint(date: $0.date, weightLbs: $0.weightLbs)
        }

        let nutritionDayCount = nutritionDaySummaries(
            since: Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .now
        ).count

        return MeasurementTrendSnapshotBuilder.build(
            entries: entries,
            weightPoints: wPoints,
            nutritionDayCount: nutritionDayCount
        )
    }

    var analysisMeasurementSnapshot: AnalysisMeasurementSnapshot? {
        guard let trend = measurementTrendSnapshot else { return nil }
        return AnalysisMeasurementSnapshot(trend: trend)
    }

    var currentAnalysisInputContext: AnalysisInputContext {
        Config.analysisInputContext
            .withProgress(automaticProgressSnapshot)
            .withMeasurements(analysisMeasurementSnapshot)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    photoCollectionCard
                    checkInCard
                    if let automaticProgressSnapshot {
                        progressContextCard(snapshot: automaticProgressSnapshot)
                    }
                    measurementsSection
                    if !photos.isEmpty {
                        photoQualityCard
                        analyzeButton
                        if !canUseAI {
                            Text(Config.anthropicKeyInlineHelpText)
                                .font(.caption2)
                                .foregroundStyle(TFColor.danger)
                        }
                    }
                    if !sessions.isEmpty {
                        pastSessionsSection
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissToolbar()
            .navigationTitle("Body Analysis")
            .navigationDestination(isPresented: $showResult) {
                if let result = analysisResult {
                    BodyAnalysisResultView(
                        result: result,
                        photos: photos,
                        validationReport: validationReport,
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
                    TFHaptics.impact(.light)
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
            .alert("Medical Screening Notice", isPresented: $showMedicalGateAlert) {
                Button("Proceed Anyway") {
                    proceedWithAnalysis()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(Config.medicalScreeningGate.alerts.joined(separator: "\n\n"))
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
                    .foregroundStyle(TFColor.danger)
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
        .dashCard()
    }

    var emptyPhotoPlaceholder: some View {
        RoundedRectangle(cornerRadius: TFRadius.cardCompact)
            .fill(TFColor.surfaceElevated)
            .frame(height: 200)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(TFColor.accent)
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
                        .background(TFColor.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    Button {
                        photos.remove(at: index)
                        TFHaptics.impact(.light)
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
                            .background(currentPose == pose ? TFColor.accent : TFColor.surfaceElevated)
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
                .background(TFColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .foregroundStyle(.primary)
    }

    var checkInCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Check-In")
                        .font(.headline)
                    Text("This sharpens the analysis beyond photos by giving the model current recovery, adherence, and training context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") {
                    clearCheckIn()
                }
                .font(.caption)
                .foregroundStyle(TFColor.accent)
                .disabled(!hasCheckInContext)
            }

            VStack(spacing: 12) {
                checkInField(
                    "Current training context",
                    text: $analysisCheckInTrainingContext,
                    prompt: "e.g. deload week, first week back, pushing hard, stalled lifts"
                )
                checkInField(
                    "Bodyweight or visual trend",
                    text: $analysisCheckInBodyweightTrend,
                    prompt: "e.g. weight flat for 2 weeks, looking leaner, up 1 lb"
                )
                checkInField(
                    "Additional recovery or sleep context",
                    text: $analysisCheckInRecoverySleep,
                    prompt: "e.g. waking frequently, unusually fatigued, recovery nap helped"
                )
                if !derivedSleepTrendSummary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Sleep episodes added automatically", systemImage: "bed.double.fill")
                            .font(.caption.bold())
                            .foregroundStyle(TFColor.sleep)
                        Text(derivedSleepTrendSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(TFColor.sleep.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                checkInField(
                    "Stress and schedule pressure",
                    text: $analysisCheckInStressSchedule,
                    prompt: "e.g. several overnight shifts, easier week, travel"
                )
                checkInField(
                    "Soreness or pain flags",
                    text: $analysisCheckInSorenessPain,
                    prompt: "e.g. right shoulder cranky on incline press, no major pain"
                )
                checkInField(
                    "Nutrition adherence and appetite",
                    text: $analysisCheckInNutritionAdherence,
                    prompt: "e.g. hitting protein, missing calories on shift days, appetite low"
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Wellness Ratings")
                    .font(.subheadline.bold())
                Text("Rate 1–10 or leave at 0 (not set). These help the analysis calibrate nutrition and recovery recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                checkInRating("Hunger", value: $analysisCheckInHungerLevel, lowLabel: "Never hungry", highLabel: "Ravenous")
                checkInRating("Energy", value: $analysisCheckInEnergyLevel, lowLabel: "Exhausted", highLabel: "Great energy")
                checkInRating("Cravings", value: $analysisCheckInCravingsLevel, lowLabel: "None", highLabel: "Intense")
            }

            Text("This check-in persists until you clear or overwrite it, so keep it current before running a new analysis.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .dashCard()
    }

    @ViewBuilder
    func checkInField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(TFColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        }
    }

    @ViewBuilder
    func checkInRating(_ title: String, value: Binding<Int>, lowLabel: String, highLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.bold())
                Spacer()
                Text(value.wrappedValue > 0 ? "\(value.wrappedValue)/10" : "Not set")
                    .font(.caption.bold())
                    .foregroundStyle(value.wrappedValue > 0 ? .primary : .secondary)
            }
            HStack(spacing: 4) {
                Text(lowLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
                Stepper("", value: value, in: 0...10, step: 1)
                    .labelsHidden()
                Text(highLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(10)
        .background(TFColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    func progressContextCard(snapshot: AnalysisProgressSnapshot) -> some View {
        SectionCardLike {
            Label("Auto Progress Context", systemImage: "arrow.trianglehead.2.clockwise")
                .font(.headline)
                .foregroundStyle(TFColor.accent)

            CompactContextCard(
                intro: "Transform will use recent app data from since your last analysis instead of treating the new photos like an isolated snapshot.",
                summaryItems: snapshot.compactSummaryItems,
                detailSections: [
                    AnalysisContextSection(
                        title: "Progress Summary",
                        items: snapshot.detailSummaryItems
                    )
                ],
                isExpanded: $showProgressContextDetails
            )
        }
    }

    var measurementsSection: some View {
        VStack(spacing: 8) {
            if let trend = measurementTrendSnapshot {
                measurementContextCard(trend: trend)
            }
            NavigationLink {
                MeasurementsView()
            } label: {
                HStack {
                    Image(systemName: "ruler")
                        .font(.caption)
                        .foregroundStyle(TFColor.measurement)
                    Text(measurementEntries.isEmpty ? "Add Circumference Measurements" : "View All Measurements")
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(TFColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    func measurementContextCard(trend: MeasurementTrendSnapshot) -> some View {
        SectionCardLike {
            HStack {
                Label("Measurement Trend", systemImage: "ruler")
                    .font(.headline)
                    .foregroundStyle(TFColor.measurement)
                Spacer()
                measurementConfidenceBadge(trend.progressConfidence)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let waist = trend.latestWaistIn {
                    HStack {
                        Text("Waist")
                            .font(.caption.bold())
                        Spacer()
                        Text(String(format: "%.1f in", waist))
                            .font(.caption)
                        if let change = trend.waistChangeIn, abs(change) > 0.05 {
                            let sign = change > 0 ? "+" : ""
                            Text("\(sign)\(String(format: "%.1f", change))")
                                .font(.caption.bold())
                                .foregroundStyle(change < 0 ? TFColor.success : TFColor.danger)
                        }
                    }
                }

                if let weight = trend.latestWeightLbs {
                    HStack {
                        Text("Weight")
                            .font(.caption.bold())
                        Spacer()
                        Text(String(format: "%.1f lb", weight))
                            .font(.caption)
                        if let change = trend.weightChangeLbs, abs(change) > 0.1 {
                            let sign = change > 0 ? "+" : ""
                            Text("\(sign)\(String(format: "%.1f", change))")
                                .font(.caption.bold())
                                .foregroundStyle(change < 0 ? TFColor.success : TFColor.danger)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                measurementInterpretationBadge(trend.interpretation)
                Spacer()
                Text("\(trend.sessionsCount) session(s)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if trend.sessionsCount >= 2, let ratio = trend.waistToWeightRatio {
                Text(ratio)
                    .font(.caption)
                    .foregroundStyle(TFColor.measurement)
            }

            Text("This measurement data will be included in the analysis prompt to sharpen body composition assessment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func measurementConfidenceBadge(_ confidence: ProgressConfidence) -> some View {
        let color: Color = {
            switch confidence {
            case .high: return TFColor.success
            case .moderate: return TFColor.accent
            case .low: return TFColor.warning
            case .insufficient: return .secondary
            }
        }()
        return Text(confidence.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    func measurementInterpretationBadge(_ interpretation: MeasurementInterpretation) -> some View {
        let color: Color = {
            switch interpretation {
            case .likelyFatLoss: return TFColor.success
            case .likelyRecomposition: return TFColor.info
            case .likelyMassGain: return TFColor.accent
            case .possibleNoise: return TFColor.warning
            case .insufficientData: return .secondary
            case .stableNoChange: return .secondary
            }
        }()
        return Text(interpretation.rawValue)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    func SectionCardLike<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .dashCard()
    }

    // MARK: - Photo Quality Card

    var photoQualityCard: some View {
        let provided = Set(photos.map(\.pose))
        let allPoses = Set(poses)
        let missing = allPoses.subtracting(provided)

        return VStack(alignment: .leading, spacing: 10) {
            Label("Photo Quality Check", systemImage: "checklist")
                .font(.subheadline.bold())
                .foregroundStyle(TFColor.accent)

            VStack(alignment: .leading, spacing: 6) {
                qualityRow(label: "Full body visible", met: true)
                qualityRow(label: "Relaxed, not flexing", met: true)
                qualityRow(label: "Front angle", met: provided.contains("Front"))
                qualityRow(label: "Back angle", met: provided.contains("Back"))
                qualityRow(label: "Side angle(s)", met: provided.contains("Side (Left)") || provided.contains("Side (Right)"))
            }

            if !missing.isEmpty {
                let missingNames = missing.sorted().joined(separator: ", ")
                Text("Missing: \(missingNames) — assessment will be less confident for those regions.")
                    .font(.caption)
                    .foregroundStyle(TFColor.accent)
            } else {
                Text("All four angles covered — full confidence available.")
                    .font(.caption)
                    .foregroundStyle(TFColor.success)
            }
        }
        .padding()
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    func qualityRow(label: String, met: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? TFColor.success : .secondary)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(met ? .primary : .secondary)
        }
    }

    // MARK: - Analyze Button

    var analyzeButton: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .background(isAnalyzing ? TFColor.accent.opacity(0.6) : TFColor.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
                .bold()
            }
            .pressable()
            .disabled(isAnalyzing || !canUseAI)

            Text("Photo analysis is strongest for visible physique patterns and broad training priorities. It is more limited for injury, posture, metabolic, and adherence assessment without added history or check-in data.")
                .font(.caption)
                .foregroundStyle(.secondary)

            profileCompletenessIndicator
        }
    }

    private var profileCompletenessIndicator: some View {
        let completeness = Config.profileCompleteness
        return Group {
            if !completeness.missingFields.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: completeness.fraction >= 0.6 ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(completeness.fraction >= 0.85 ? TFColor.success : completeness.fraction >= 0.6 ? TFColor.accent : TFColor.danger)
                    Text(completeness.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Past Sessions with Delete

    var pastSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Past Analyses")
                    .font(.headline)
                Spacer()
                if sessions.count >= 2 {
                    NavigationLink(destination: PhotoComparisonView(sessions: sessions)) {
                        Label("Compare", systemImage: "photo.on.rectangle.angled")
                            .font(.caption.bold())
                            .foregroundStyle(TFColor.accent)
                    }
                }
            }

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
        let gate = Config.medicalScreeningGate
        if gate.level >= .caution && !gate.alerts.isEmpty {
            showMedicalGateAlert = true
            return
        }
        proceedWithAnalysis()
    }

    @MainActor
    func proceedWithAnalysis() {
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
            let result = try await ClaudeService.shared.analyzeBody(
                photos: photos,
                inputContext: currentAnalysisInputContext,
                priorAnalysis: previousAnalysisResult
            )
            try Task.checkCancellation()
            guard !Task.isCancelled else { return }
            let report = BodyAnalysisValidator.validate(
                result,
                photoAngles: photos.map(\.pose),
                bodyweightLbs: MacroTargetResolver.profileBodyweightLbs()
            )
            analysisResult = result
            validationReport = report
            showResult = true
            TFHaptics.success()
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            showError = true
            TFHaptics.error()
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
            TFHaptics.error()
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
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.scheduleAutomaticBackup(using: modelContext)
        photos.removeAll()
        currentPose = poses.first ?? "Front"
        analysisResult = nil
        showResult = false
        TFHaptics.success()
    }

    func deleteSession(_ session: BodyAnalysisSession) {
        modelContext.delete(session)
        guard PersistenceReporter.save(modelContext, operation: "analysis session deletion") else {
            modelContext.rollback()
            TFHaptics.error()
            return
        }
        DataBackupManager.shared.writeAutomaticBackup(using: modelContext)
        sessionToDelete = nil
        TFHaptics.impact(.medium)
    }

    func clearCheckIn() {
        analysisCheckInTrainingContext = Config.defaultAnalysisCheckInTrainingContext
        analysisCheckInBodyweightTrend = Config.defaultAnalysisCheckInBodyweightTrend
        analysisCheckInRecoverySleep = Config.defaultAnalysisCheckInRecoverySleep
        analysisCheckInStressSchedule = Config.defaultAnalysisCheckInStressSchedule
        analysisCheckInSorenessPain = Config.defaultAnalysisCheckInSorenessPain
        analysisCheckInNutritionAdherence = Config.defaultAnalysisCheckInNutritionAdherence
        analysisCheckInHungerLevel = Config.defaultAnalysisCheckInHungerLevel
        analysisCheckInEnergyLevel = Config.defaultAnalysisCheckInEnergyLevel
        analysisCheckInCravingsLevel = Config.defaultAnalysisCheckInCravingsLevel
    }

    func weightPoints(since startDate: Date) -> [AnalysisLoggedWeightPoint] {
        weightEntries
            .filter { $0.date >= startDate }
            .map { AnalysisLoggedWeightPoint(date: $0.date, weightLbs: $0.weightLbs) }
    }

    func nutritionDaySummaries(since startDate: Date) -> [AnalysisLoggedNutritionDay] {
        let calendar = Calendar.current
        let grouped = nutritionEntries
            .filter { $0.date >= startDate }
            .reduce(into: [Date: AnalysisLoggedNutritionDay]()) { partialResult, entry in
                let day = calendar.startOfDay(for: entry.date)
                let existing = partialResult[day] ?? AnalysisLoggedNutritionDay(
                    date: day,
                    calories: 0,
                    proteinG: 0,
                    carbsG: 0,
                    fatG: 0,
                    fiberG: 0,
                    mealCount: 0
                )
                partialResult[day] = AnalysisLoggedNutritionDay(
                    date: day,
                    calories: existing.calories + entry.calories,
                    proteinG: existing.proteinG + entry.proteinG,
                    carbsG: existing.carbsG + entry.carbsG,
                    fatG: existing.fatG + entry.fatG,
                    fiberG: existing.fiberG + entry.fiberG,
                    mealCount: existing.mealCount + 1
                )
            }

        return grouped.values.sorted { $0.date < $1.date }
    }

    func exerciseProgressSnapshots() -> [AnalysisExerciseProgressSnapshot] {
        exerciseWeightEntries.map { entry in
            AnalysisExerciseProgressSnapshot(
                exerciseName: entry.exerciseName,
                canonicalExerciseKey: entry.canonicalExerciseKey,
                latestWeightLbs: entry.weightLbs,
                latestDate: entry.loggedAt,
                bestWeightLbs: entry.hasBestRecord ? entry.bestWeightLbs : entry.weightLbs,
                bestLoggedAt: entry.hasBestRecord ? entry.bestLoggedAt : entry.loggedAt,
                bestRepsCompleted: entry.hasBestRecord ? entry.bestRepsCompleted : entry.repsCompleted
            )
        }
    }

    func exercisePerformanceEvents() -> [AnalysisExercisePerformanceEvent] {
        exercisePerformanceLogs.map { entry in
            AnalysisExercisePerformanceEvent(
                exerciseName: entry.exerciseName,
                canonicalExerciseKey: entry.canonicalExerciseKey,
                loggedAt: entry.loggedAt,
                weightLbs: entry.weightLbs,
                repsCompleted: entry.repsCompleted
            )
        }
    }
}

// MARK: - Past Session Row

struct PastSessionRow: View {
    let session: BodyAnalysisSession
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if let image = thumbnail {
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
                            .background(TFColor.accent.opacity(0.15))
                            .foregroundStyle(TFColor.accent)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(session.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(session.programmingPrioritySummary)
                    .font(.caption)
                    .foregroundStyle(TFColor.accent)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(TFColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
        .task {
            if thumbnail == nil {
                thumbnail = UIImage.downsampledImage(from: session.photoData, maxDimension: 56)
            }
        }
    }
}

// MARK: - Saved Analysis (Legacy — minimal data)

struct SavedAnalysisView: View {
    let session: BodyAnalysisSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = UIImage.downsampledImage(from: session.photoData, maxDimension: 400) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
                }

                SectionCard(title: "Assessment", icon: "doc.text") {
                    Text(session.analysisResult)
                }

                SectionCard(title: "Top Muscle Groups to Prioritize", icon: "flame.fill") {
                    Text(session.programmingPrioritySummary)
                        .foregroundStyle(TFColor.accent)
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

    @State private var showDebugPanel = false
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if showDebugPanel {
                    savedAnalysisDebugPanel
                }

                // Photo
                if let image = UIImage.downsampledImage(from: session.photoData, maxDimension: 400) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))

                        Text(session.pose)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(TFColor.accent)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }

                // Reuse the same layout as BodyAnalysisResultView
                AnalysisResultContent(result: result)
                    .onLongPressGesture(minimumDuration: 1.2) {
                        withAnimation { showDebugPanel.toggle() }
                        TFHaptics.impact(.soft)
                    }
            }
            .padding()
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
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

    var savedAnalysisDebugPanel: some View {
        let poses = session.pose.components(separatedBy: " + ")
        let report = BodyAnalysisValidator.validate(
            result,
            photoAngles: poses,
            bodyweightLbs: MacroTargetResolver.profileBodyweightLbs()
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Analysis Debug", systemImage: "ant.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(TFColor.measurement)
                Spacer()
                Button {
                    withAnimation { showDebugPanel = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            ValidationReportCard(report: report)

            HStack(spacing: 10) {
                savedDebugCopyButton(title: "Copy JSON", payload: savedAnalysisJSON)
            }
        }
        .padding()
        .background(TFColor.measurement.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: TFRadius.cardCompact))
    }

    func savedDebugCopyButton(title: String, payload: String) -> some View {
        Button {
            UIPasteboard.general.string = payload
            withAnimation(.easeOut(duration: 0.2)) {
                toastMessage = "\(title) copied"
            }
            TFHaptics.impact(.light)
        } label: {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(TFColor.measurement.opacity(0.12))
                .foregroundStyle(TFColor.measurement)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    var savedAnalysisJSON: String {
        guard let data = try? JSONEncoder().encode(result),
              let json = String(data: data, encoding: .utf8) else {
            return "(encoding failed)"
        }
        return json
    }
}
