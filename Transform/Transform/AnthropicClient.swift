import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct AnthropicRequestContext {
    let feature: String
    let phase: String
    let weekNumber: Int?
    let metrics: [String: Int]

    var label: String {
        if let weekNumber {
            return "\(feature)-\(phase)-week\(weekNumber)"
        }
        return "\(feature)-\(phase)"
    }
}

final class AnthropicClient {
    static let shared = AnthropicClient()
    private let maxAttempts = 3

    /// Upper bound on concurrent requests this client will keep on the wire at once.
    /// Callers that fan out (the generator's parallel candidates) must stay at or below it —
    /// see `ClaudeService.parallelCandidates`, which clamps itself to this value. Anything
    /// above it gets queued by URLSession while its `timeoutIntervalForResource` clock is
    /// already running, which surfaces as a transport timeout that looks like an Anthropic
    /// fault. Keeping the constant here (rather than a bare literal in the session builder)
    /// is what stops the two from drifting apart silently.
    static let maxConcurrentRequests = 4
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Raised from 240/360 after a full-program generation timed out on the owner's phone
        // and surfaced as "the AI request timed out ... No recovery-engine week was applied".
        //
        // A timeout is the ONE transport failure this client deliberately does not retry
        // (`shouldRetry(error:)`), and that is the right call: the request may already have
        // completed and been billed on Anthropic's side, so retrying risks paying twice for one
        // program. It also cannot fit inside the resource ceiling — two 240s attempts exceed
        // 360s, and `timeoutIntervalForResource` starts when the task is resumed, so the retry
        // would die on the budget rather than on the wire.
        //
        // With no retry available, the ceiling itself has to be honest about how long the week 1
        // call actually takes. It emits one 7-day week like any other generation, but it is the
        // only one that runs on Opus rather than the lite model, so it is the slowest of them.
        // The ratio between the two is
        // preserved so a queued request still cannot burn its resource budget before reaching
        // the wire, which is the trap documented on `maxConcurrentRequests` below.
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 480
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        // The week generators fire `parallelCandidates` requests concurrently inside a task
        // group. A pool of 1 silently SERIALIZED them: candidate 2 sat queued until candidate 1
        // finished, so "parallel candidates" cost double the wall clock while the diagnostics
        // still reported a parallel fan-out. Worse, `timeoutIntervalForResource` starts when the
        // task is resumed, not when it reaches the wire — a queued candidate burned its resource
        // budget waiting and could fail with a transport timeout that had nothing to do with
        // Anthropic. Keep the ceiling small (this is a single-user app) but above the fan-out.
        configuration.httpMaximumConnectionsPerHost = Self.maxConcurrentRequests
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: configuration)
    }()
    private init() {}

    private var resolvedAPIKey: String {
        #if !canImport(UIKit)
        // Headless macOS integration tests cannot read the iPhone Keychain. This
        // runtime-only credential path is compiled out of the app target and keeps
        // CI secrets out of tracked files, build settings, and request diagnostics.
        if let raw = ProcessInfo.processInfo.environment["TRANSFORM_HEADLESS_ANTHROPIC_API_KEY"] {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                return key
            }
        }
        #endif
        return Config.anthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Public API

    /// Text-mode request. Returns concatenated `text` content blocks.
    func sendRequest(
        body: [String: Any],
        timeout: TimeInterval = 120,
        context: AnthropicRequestContext? = nil
    ) async throws -> String {
        let data = try await performRequest(body: body, timeout: timeout, requestKind: "text", context: context)

        let apiResponse = try JSONDecoder().decode(AnthropicResponse.self, from: data)

        if apiResponse.stopReason == "max_tokens" {
            throw ClaudeError.parseError("Response truncated: model hit max_tokens before finishing. The output JSON is incomplete.")
        }

        let text = apiResponse.content
            .compactMap { $0.type == .text ? $0.text : nil }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw ClaudeError.emptyResponse
        }
        return text
    }

    /// Tool-use / structured-output request. Returns the `input` JSON of the first `tool_use` block
    /// serialized as a JSON string, ready for `JSONDecoder`.
    ///
    /// Callers should pass a body that includes `tools` and `tool_choice` of type `"tool"` so the
    /// model is forced into a structured response.
    func sendStructuredRequest(
        body: [String: Any],
        toolName: String,
        timeout: TimeInterval = 120,
        context: AnthropicRequestContext? = nil,
        attemptLimit: Int? = nil
    ) async throws -> String {
        let data = try await performRequest(
            body: body,
            timeout: timeout,
            requestKind: "structured",
            context: context,
            attemptLimit: attemptLimit
        )

        let rootObject: Any
        do {
            rootObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            let short = String(String(describing: error).prefix(180))
            throw ClaudeError.parseError("Envelope parse failure: \(short)")
        }

        guard let root = rootObject as? [String: Any],
              let content = root["content"] as? [[String: Any]] else {
            throw ClaudeError.parseError("Envelope parse failure: missing content array")
        }

        let stopReason = root["stop_reason"] as? String ?? "unknown"
        if stopReason == "max_tokens" {
            throw ClaudeError.parseError("Tool protocol failure: model hit max_tokens before completing structured output — response is truncated")
        }

        // Find the tool_use block matching the requested tool.
        let toolBlock = content.first { block in
            (block["type"] as? String) == "tool_use" &&
            (block["name"] as? String) == toolName
        }

        // Fall back to any tool_use block if the name doesn't match (still safer than text parsing).
        let resolvedBlock = toolBlock ?? content.first { ($0["type"] as? String) == "tool_use" }

        guard let resolvedBlock,
              let input = resolvedBlock["input"] as? [String: Any] else {
            // If the model refused tool_use and returned text, bubble that up as a parse error
            // so the generator can fall back to procedural output rather than silently retrying.
            if let firstText = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
               !firstText.isEmpty {
                throw ClaudeError.parseError("Tool protocol failure: model returned text instead of tool_use: \(String(firstText.prefix(200)))")
            }
            throw ClaudeError.parseError("Tool protocol failure: no tool_use input found in response")
        }

        let inputData = try JSONSerialization.data(withJSONObject: input, options: [])
        guard let jsonString = String(data: inputData, encoding: .utf8) else {
            throw ClaudeError.parseError("Tool protocol failure: could not serialize tool_use input")
        }
        return jsonString
    }

    // MARK: - Shared HTTP

    private func performRequest(
        body: [String: Any],
        timeout: TimeInterval,
        requestKind: String,
        context: AnthropicRequestContext?,
        attemptLimit: Int? = nil
    ) async throws -> Data {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ClaudeError.apiError("Invalid API URL")
        }

        let apiKey = resolvedAPIKey
        guard !apiKey.isEmpty else {
            throw ClaudeError.apiError(Config.anthropicKeyStatus.requestFailureMessage)
        }

        let encodedBody = try JSONSerialization.data(withJSONObject: body)
        let requestID = String(UUID().uuidString.prefix(8))
        let startedAt = Date()
        let lifecycleAtStart = AppLifecycleMonitor.shared.snapshot()
        let profile = requestProfile(
            requestID: requestID,
            body: body,
            encodedBody: encodedBody,
            timeout: timeout,
            requestKind: requestKind,
            context: context
        )
        var startDetails = profile
        startDetails["lifecycle_start"] = lifecycleAtStart.phase.rawValue

        logRequest(
            requestID: requestID,
            event: "start",
            details: startDetails
        )

        let allowedAttempts = max(1, min(maxAttempts, attemptLimit ?? maxAttempts))
        for attempt in 1...allowedAttempts {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
                request.httpBody = encodedBody
                request.timeoutInterval = timeout

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ClaudeError.apiError("Invalid response")
                }

                if httpResponse.statusCode == 200 {
                    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    logRequest(
                        requestID: requestID,
                        event: "success",
                        details: [
                            "attempt": "\(attempt)",
                            "status": "\(httpResponse.statusCode)",
                            "response_bytes": "\(data.count)",
                            "duration_ms": "\(durationMs)",
                            "server_request_id": serverRequestID(from: httpResponse) ?? "n/a"
                        ]
                    )
                    return data
                }

                if shouldRetry(statusCode: httpResponse.statusCode), attempt < allowedAttempts {
                    let delayNanos = retryDelay(for: httpResponse, attempt: attempt)
                    logRequest(
                        requestID: requestID,
                        event: "retry_scheduled",
                        details: [
                            "attempt": "\(attempt)",
                            "status": "\(httpResponse.statusCode)",
                            "reason": "server_status",
                            "backoff_ms": "\(Int(delayNanos / 1_000_000))",
                            "server_request_id": serverRequestID(from: httpResponse) ?? "n/a"
                        ]
                    )
                    try await Task.sleep(nanoseconds: delayNanos)
                    continue
                }

                if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                    let message = errorResponse.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
                    logRequest(
                        requestID: requestID,
                        event: "http_failure",
                        details: [
                            "attempt": "\(attempt)",
                            "status": "\(httpResponse.statusCode)",
                            "category": failureCategory(
                                for: ClaudeError.apiError("(\(httpResponse.statusCode)) \(message)"),
                                lifecycleAtStart: lifecycleAtStart,
                                lifecycleAtEnd: AppLifecycleMonitor.shared.snapshot()
                            ),
                            "message": message.isEmpty ? "HTTP \(httpResponse.statusCode)" : message,
                            "server_request_id": serverRequestID(from: httpResponse) ?? "n/a"
                        ]
                    )
                    guard !message.isEmpty else {
                        throw ClaudeError.apiError("HTTP \(httpResponse.statusCode)")
                    }
                    throw ClaudeError.apiError("(\(httpResponse.statusCode)) \(message)")
                }
                logRequest(
                    requestID: requestID,
                    event: "http_failure",
                    details: [
                        "attempt": "\(attempt)",
                        "status": "\(httpResponse.statusCode)",
                        "category": failureCategory(
                            for: ClaudeError.apiError("HTTP \(httpResponse.statusCode)"),
                            lifecycleAtStart: lifecycleAtStart,
                            lifecycleAtEnd: AppLifecycleMonitor.shared.snapshot()
                        ),
                        "server_request_id": serverRequestID(from: httpResponse) ?? "n/a"
                    ]
                )
                throw ClaudeError.apiError("HTTP \(httpResponse.statusCode)")
            } catch {
                let lifecycleAtEnd = AppLifecycleMonitor.shared.snapshot()
                let category = failureCategory(
                    for: error,
                    lifecycleAtStart: lifecycleAtStart,
                    lifecycleAtEnd: lifecycleAtEnd
                )

                if shouldRetry(error: error), attempt < allowedAttempts {
                    logRequest(
                        requestID: requestID,
                        event: "retry_scheduled",
                        details: [
                            "attempt": "\(attempt)",
                            "category": category,
                            "error": normalizedErrorDescription(error),
                            "backoff_ms": "\(Int(backoff(attempt: attempt) / 1_000_000))",
                            "lifecycle_end": lifecycleAtEnd.phase.rawValue,
                            "lifecycle_changed": "\(lifecycleAtEnd.generation != lifecycleAtStart.generation)"
                        ]
                    )
                    try await Task.sleep(nanoseconds: backoff(attempt: attempt))
                    continue
                }

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                logRequest(
                    requestID: requestID,
                    event: "failure",
                    details: [
                        "attempt": "\(attempt)",
                        "category": category,
                        "error": normalizedErrorDescription(error),
                        "duration_ms": "\(durationMs)",
                        "lifecycle_end": lifecycleAtEnd.phase.rawValue,
                        "lifecycle_changed": "\(lifecycleAtEnd.generation != lifecycleAtStart.generation)",
                        "transition_age_ms": "\(max(0, Int(lifecycleAtEnd.lastTransitionAt.timeIntervalSince(startedAt) * 1000)))"
                    ]
                )
                throw error
            }
        }

        throw ClaudeError.apiError("Request failed after retry")
    }

    private func requestProfile(
        requestID: String,
        body: [String: Any],
        encodedBody: Data,
        timeout: TimeInterval,
        requestKind: String,
        context: AnthropicRequestContext?
    ) -> [String: String] {
        var details: [String: String] = [
            "request_id": requestID,
            "label": context?.label ?? requestKind,
            "request_kind": requestKind,
            "body_bytes": "\(encodedBody.count)",
            "timeout_s": "\(Int(timeout))"
        ]

        if let model = body["model"] as? String {
            details["model"] = model
        }
        if let maxTokens = body["max_tokens"] as? Int {
            details["max_tokens"] = "\(maxTokens)"
        }
        if let systemPrompt = body["system"] as? String {
            details["system_chars"] = "\(systemPrompt.count)"
        } else if let systemBlocks = body["system"] as? [[String: Any]] {
            // Prompt-cached requests send system as an array of text blocks.
            let totalChars = systemBlocks
                .compactMap { $0["text"] as? String }
                .reduce(0) { $0 + $1.count }
            details["system_chars"] = "\(totalChars)"
        }
        if let messages = body["messages"] as? [[String: Any]],
           let firstContent = messages.first?["content"] as? String {
            details["user_chars"] = "\(firstContent.count)"
        }
        if let toolChoice = body["tool_choice"] as? [String: Any],
           let toolName = toolChoice["name"] as? String {
            details["tool"] = toolName
        }
        if let context {
            details["feature"] = context.feature
            details["phase"] = context.phase
            if let weekNumber = context.weekNumber {
                details["week"] = "\(weekNumber)"
            }
            for key in context.metrics.keys.sorted() {
                if let value = context.metrics[key] {
                    details[key] = "\(value)"
                }
            }
        }

        return details
    }

    private func failureCategory(
        for error: Error,
        lifecycleAtStart: AppLifecycleSnapshot,
        lifecycleAtEnd: AppLifecycleSnapshot
    ) -> String {
        let lifecycleChanged = lifecycleAtEnd.generation != lifecycleAtStart.generation
        if lifecycleChanged && lifecycleAtEnd.phase != .active {
            return "app_lifecycle_interruption"
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "transport_timeout"
            case .networkConnectionLost:
                return lifecycleChanged ? "app_lifecycle_disconnect" : "transport_disconnect"
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "transport_unreachable"
            case .cancelled:
                return lifecycleChanged ? "app_lifecycle_cancelled" : "transport_cancelled"
            default:
                return "transport_error_\(urlError.code.rawValue)"
            }
        }

        if let claudeError = error as? ClaudeError {
            switch claudeError {
            case .apiError(let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("HTTP 408") || trimmed.contains("(408)") {
                    return "server_timeout"
                }
                if trimmed.contains("HTTP 429") || trimmed.contains("(429)") {
                    return "server_rate_limit"
                }
                if trimmed.contains("HTTP 5") || trimmed.hasPrefix("(5") {
                    return "server_disconnect_or_5xx"
                }
                return "api_error"
            case .parseError(let detail):
                if detail.hasPrefix("Envelope parse failure:") {
                    return "server_response_parse"
                }
                return "structured_output_parse"
            case .emptyResponse:
                return "empty_response"
            default:
                return "client_error"
            }
        }

        return lifecycleChanged ? "lifecycle_related_unknown" : "unknown_failure"
    }

    private func normalizedErrorDescription(_ error: Error) -> String {
        error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func serverRequestID(from response: HTTPURLResponse) -> String? {
        let keys = ["request-id", "x-request-id", "anthropic-request-id"]
        for key in keys {
            if let value = response.value(forHTTPHeaderField: key),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func logRequest(requestID: String, event: String, details: [String: String]) {
        let payload = details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[AnthropicClient][\(requestID)][\(event)] \(payload)")
    }

    /// Exponential backoff with a lower-bounded jitter window (half the nominal delay to the
    /// full delay — deliberately not AWS-style "full jitter", which can collapse toward an
    /// immediate retry). The generator fires several candidates concurrently; without jitter
    /// every one that hits the same 429/5xx retries at the identical instant, reproducing the
    /// burst that caused the throttle on every round instead of spreading it out.
    private func backoff(attempt: Int) -> UInt64 {
        let baseNanos: UInt64 = 1_000_000_000
        let multiplier = UInt64(1 << min(attempt - 1, 4))
        let ceiling = baseNanos * multiplier
        // Never drop below half the nominal delay — jitter should spread a burst, not defeat
        // the backoff.
        return UInt64.random(in: (ceiling / 2)...ceiling)
    }

    /// Honor the server's `retry-after` header (capped at 30s) when present, so a
    /// fixed exponential backoff doesn't immediately trigger another 429 during
    /// real rate limiting. Falls back to exponential backoff otherwise.
    private func retryDelay(for response: HTTPURLResponse, attempt: Int) -> UInt64 {
        if let retryAfter = response.value(forHTTPHeaderField: "retry-after"),
           let seconds = Double(retryAfter.trimmingCharacters(in: .whitespaces)),
           seconds > 0 {
            let directive = UInt64(min(seconds, 30) * 1_000_000_000)
            // Wait at least as long as the server asked, plus up to 1s of spread so
            // concurrent candidates do not all resume on the same tick.
            return directive + UInt64.random(in: 0...1_000_000_000)
        }
        return backoff(attempt: attempt)
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private func shouldRetry(error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return false
        }
        return error.isTransientNetworkFailure
    }
}

nonisolated struct AnthropicResponse: Codable {
    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

nonisolated struct ContentBlock: Codable {
    let type: Kind
    let text: String?

    enum Kind: Equatable {
        case text
        case toolUse
        case other(String)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = try container.decode(String.self, forKey: .type)

        switch rawType {
        case "text":
            type = .text
        case "tool_use":
            type = .toolUse
        default:
            type = .other(rawType)
        }

        text = try container.decodeIfPresent(String.self, forKey: .text)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch type {
        case .text:
            try container.encode("text", forKey: .type)
        case .toolUse:
            try container.encode("tool_use", forKey: .type)
        case .other(let rawValue):
            try container.encode(rawValue, forKey: .type)
        }

        try container.encodeIfPresent(text, forKey: .text)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

nonisolated private struct AnthropicErrorResponse: Decodable {
    let error: AnthropicErrorPayload
}

nonisolated private struct AnthropicErrorPayload: Decodable {
    let message: String
}

nonisolated enum ClaudeError: LocalizedError {
    case apiError(String)
    case emptyResponse
    case parseError(String)
    case noPhotos
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "API error: \(msg)"
        case .emptyResponse: return "No response from Claude"
        case .parseError(let detail): return "Parse error: \(detail)"
        case .noPhotos: return "No photos provided"
        case .invalidImage: return "Could not process image"
        }
    }
}

extension Error {
    var isTransientNetworkFailure: Bool {
        if let urlError = self as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        if let claudeError = self as? ClaudeError {
            switch claudeError {
            case .apiError(let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.contains("HTTP 408")
                    || trimmed.contains("(408)")
                    || trimmed.contains("HTTP 429")
                    || trimmed.contains("(429)")
                    || trimmed.contains("HTTP 5")
                    || trimmed.hasPrefix("(5")
                    || trimmed.contains("failed after retry")
            default:
                return false
            }
        }

        return false
    }

    var isStructuredResponseEnvelopeFailure: Bool {
        guard let claudeError = self as? ClaudeError else { return false }

        switch claudeError {
        case .parseError(let detail):
            return detail.hasPrefix("Envelope parse failure:")
        default:
            return false
        }
    }

    var isRecoverableStructuredOutputFailure: Bool {
        guard let claudeError = self as? ClaudeError else { return false }

        switch claudeError {
        case .emptyResponse:
            return true
        case .parseError(let detail):
            return detail.hasPrefix("Tool protocol failure:") || detail.hasPrefix("Tool payload decode failure")
        default:
            return false
        }
    }

    var isNutritionPayloadDecodeFailure: Bool {
        guard let claudeError = self as? ClaudeError else { return false }

        switch claudeError {
        case .parseError(let detail):
            return detail.hasPrefix("Could not decode nutrition response.")
                || detail.hasPrefix("Could not encode nutrition response as data.")
        default:
            return false
        }
    }
}
