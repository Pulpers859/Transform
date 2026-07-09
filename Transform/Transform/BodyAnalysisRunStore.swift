import Foundation
import Observation

struct AnalysisRunContext: Identifiable {
    let id = UUID()
    let photos: [AnalysisPhoto]
    let inputContext: AnalysisInputContext
    let priorAnalysis: BodyAnalysisResult?
    let bodyweightLbs: Double?

    var photoAngles: [String] { photos.map(\.pose) }
    var photoCount: Int { photos.count }
}

@MainActor
@Observable
final class BodyAnalysisRunStore {
    private var analysisTask: Task<Void, Never>?

    private(set) var isRunning = false
    private(set) var activeRun: AnalysisRunContext?
    private(set) var completedRun: AnalysisRunContext?
    private(set) var result: BodyAnalysisResult?
    private(set) var validationReport: AnalysisValidationReport?
    var errorMessage: String?

    func start(_ runContext: AnalysisRunContext) {
        analysisTask?.cancel()
        activeRun = runContext
        completedRun = nil
        result = nil
        validationReport = nil
        errorMessage = nil
        isRunning = true

        analysisTask = Task { [weak self] in
            await self?.run(runContext)
        }
    }

    func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
        isRunning = false
        activeRun = nil
    }

    func clearCompletedPresentation() {
        result = nil
        validationReport = nil
        completedRun = nil
    }

    private func isCurrent(_ runContext: AnalysisRunContext) -> Bool {
        activeRun?.id == runContext.id
    }

    private func finish(_ runContext: AnalysisRunContext) {
        guard isCurrent(runContext) else { return }
        isRunning = false
        analysisTask = nil
        activeRun = nil
    }

    private func run(_ runContext: AnalysisRunContext) async {
        defer { finish(runContext) }

        do {
            let result = try await ClaudeService.shared.analyzeBody(
                photos: runContext.photos,
                inputContext: runContext.inputContext,
                priorAnalysis: runContext.priorAnalysis
            )
            try Task.checkCancellation()
            guard isCurrent(runContext) else { return }

            let report = BodyAnalysisValidator.validate(
                result,
                photoAngles: runContext.photoAngles,
                bodyweightLbs: runContext.bodyweightLbs
            )
            guard isCurrent(runContext) else { return }

            self.result = result
            validationReport = report
            completedRun = runContext
            TFHaptics.success()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(runContext) else { return }
            errorMessage = error.localizedDescription
            TFHaptics.error()
        }
    }
}
