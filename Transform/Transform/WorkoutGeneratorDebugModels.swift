import Foundation

enum WorkoutGeneratorDebugMode: String, CaseIterable, Identifiable {
    case liveAI = "Live AI"
    case procedural = "Procedural"
    case validatorReplay = "Validator Replay"

    var id: String { rawValue }

    var usesAPI: Bool {
        self == .liveAI
    }

    var description: String {
        switch self {
        case .liveAI:
            return "Runs the real AI generator with retries, validation, and fallback. Uses API credits."
        case .procedural:
            return "Skips the API and builds the week from the Recovery Engine logic only."
        case .validatorReplay:
            return "Replays sanitize and validator logic against supplied JSON without spending credits."
        }
    }

    var actionTitle: String {
        switch self {
        case .liveAI:
            return "Run Live AI"
        case .procedural:
            return "Run Procedural"
        case .validatorReplay:
            return "Replay Validator"
        }
    }
}

enum WorkoutGeneratorDebugStage: String, CaseIterable, Identifiable {
    case weekOne = "Week 1"
    case nextWeek = "Next Week"

    var id: String { rawValue }
}

struct WorkoutGeneratorDebugAttempt: Identifiable {
    let id = UUID()
    let attemptNumber: Int
    let rawPayload: String?
    let sanitizedPayload: String?
    let validatorIssues: [String]
    let outcome: String
}

struct WorkoutGeneratorDebugReport: Identifiable {
    let id = UUID()
    let stage: WorkoutGeneratorDebugStage
    let mode: WorkoutGeneratorDebugMode
    let weekNumber: Int
    let usedAPI: Bool
    let sourceLabel: String
    let acceptedWithWarnings: Bool
    let usedFallback: Bool
    let displayTitle: String
    let splitType: String
    let analysisSummary: String
    let trainingIntentSummary: String
    let blueprintSummary: String
    let previousWeekReference: String?
    let systemPrompt: String
    let userPrompt: String
    let warnings: [String]
    let finalIssues: [String]
    let attempts: [WorkoutGeneratorDebugAttempt]
    let replayInputJSON: String?
    let terminalError: String?
    let finalJSON: String
    let previewSummary: String
    let previewDays: [WorkoutDayResponse]

    var hasTerminalError: Bool {
        if let terminalError {
            return !terminalError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    var hasFinalPayload: Bool {
        !finalJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sourceDisplayName: String {
        let trimmed = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    var validatorReportText: String {
        if finalIssues.isEmpty {
            return "No validator issues."
        }
        return finalIssues.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    var warningsText: String {
        if warnings.isEmpty {
            return "No warnings."
        }
        return warnings.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    var attemptSummaryText: String {
        if attempts.isEmpty {
            return "No attempt trace recorded."
        }

        return attempts.map { attempt in
            var lines: [String] = [
                "Attempt \(attempt.attemptNumber): \(attempt.outcome)"
            ]
            if !attempt.validatorIssues.isEmpty {
                lines.append("Issues:")
                lines.append(contentsOf: attempt.validatorIssues.map { "- \($0)" })
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    var bundleText: String {
        var lines: [String] = [
            "Stage: \(stage.rawValue)",
            "Mode: \(mode.rawValue)",
            "Week: \(weekNumber)",
            "Used API: \(usedAPI ? "Yes" : "No")",
            "Source: \(sourceDisplayName)",
            "Accepted With Warnings: \(acceptedWithWarnings ? "Yes" : "No")",
            "Used Fallback: \(usedFallback ? "Yes" : "No")",
            "Title: \(displayTitle)",
            "Split: \(splitType)",
            "",
        ]

        if let terminalError, !terminalError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Terminal Error:")
            lines.append(terminalError)
            lines.append("")
        }

        lines.append(contentsOf: [
            "Warnings:",
            warningsText,
            "",
            "Validator Issues:",
            validatorReportText,
            "",
            "Analysis Summary:",
            analysisSummary,
            "",
            "Training Intent:",
            trainingIntentSummary,
            "",
            "Blueprint:",
            blueprintSummary
        ])

        if let previousWeekReference, !previousWeekReference.isEmpty {
            lines.append("")
            lines.append("Previous Week Reference:")
            lines.append(previousWeekReference)
        }

        lines.append("")
        lines.append("System Prompt:")
        lines.append(systemPrompt)
        lines.append("")
        lines.append("User Prompt:")
        lines.append(userPrompt)
        lines.append("")
        lines.append("Attempt Trace:")
        lines.append(attemptSummaryText)

        if let replayInputJSON, !replayInputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("Replay Input JSON:")
            lines.append(replayInputJSON)
        }

        lines.append("")
        lines.append("Final JSON:")
        lines.append(finalJSON)

        return lines.joined(separator: "\n")
    }
}
