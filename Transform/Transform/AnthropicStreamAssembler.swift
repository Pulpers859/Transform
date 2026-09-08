import Foundation

/// Rebuilds a complete Messages-API response object from a server-sent-event stream.
///
/// WHY THIS EXISTS
/// ---------------
/// Week 1 generation timed out on the owner's phone twice. The second time the log said it
/// plainly: `timeout_s=300`, `duration_ms=480739`. 480s is `timeoutIntervalForResource`, so the
/// request ran to the hard wall-clock ceiling and was killed — and because a NON-streaming
/// request delivers nothing until it delivers everything, `timeoutIntervalForRequest` (an
/// INACTIVITY timer) could never fire either. The client had no way to tell "Anthropic is
/// working" from "this connection is dead", so its only defence was a stopwatch, and the first
/// response to that was to raise the stopwatch from 240/360 to 300/480. It happened again.
///
/// Anthropic's own guidance is to stream any request with long input, long output, or a high
/// `max_tokens`, precisely because it prevents hitting request timeouts. This request is all
/// three: ~35KB of body, `max_tokens` 8192, forced tool use, on Opus. Streaming replaces the
/// stopwatch with a real progress signal — tokens arriving continuously reset the inactivity
/// timer, and a genuine stall now looks different from a slow answer.
///
/// WHY IT IS A SEPARATE, PURE TYPE
/// -------------------------------
/// The callers (`sendRequest`, `sendStructuredRequest`) parse a single `Data` blob and must not
/// change: one reads `content[].text`, the other digs out the `tool_use` block's `input`. So the
/// stream has to be reassembled back into exactly that shape. Doing it here — fed one line at a
/// time, with no URLSession anywhere near it — is what lets the reassembly be driven by scripted
/// transcripts in the headless harness rather than shipped correct-by-inspection over the one
/// code path that spends the owner's money.
struct AnthropicStreamAssembler {

    enum StreamError: Error, CustomStringConvertible {
        case apiError(type: String, message: String)
        case malformed(String)

        var description: String {
            switch self {
            case let .apiError(type, message):
                return "\(type): \(message)"
            case let .malformed(detail):
                return "Malformed stream: \(detail)"
            }
        }
    }

    /// One content block under construction. Text and tool input both arrive as fragments that
    /// mean nothing until concatenated, so they are accumulated as strings and only interpreted
    /// when the block closes.
    private struct PartialBlock {
        var raw: [String: Any]
        var text: String = ""
        var partialJSON: String = ""
    }

    private var message: [String: Any] = [:]
    private var blocks: [Int: PartialBlock] = [:]
    private var order: [Int] = []
    private var sawMessageStart = false
    private var sawMessageStop = false

    /// Every event this consumed, for diagnostics when a stream ends unusable.
    private(set) var eventCount = 0

    // MARK: - Feeding

    /// Consume one raw line of the SSE stream.
    ///
    /// `event:` lines are deliberately ignored: every `data:` payload carries its own `type`
    /// field, so dispatching on the payload needs one source of truth instead of two that can
    /// disagree. Blank lines are event separators and carry nothing.
    mutating func consume(line: String) throws {
        guard line.hasPrefix("data:") else { return }

        let payload = String(line.dropFirst("data:".count))
            .trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return }

        guard let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            throw StreamError.malformed("event payload was not a JSON object with a type")
        }

        eventCount += 1
        try apply(type: type, event: event)
    }

    private mutating func apply(type: String, event: [String: Any]) throws {
        switch type {
        case "message_start":
            guard let start = event["message"] as? [String: Any] else {
                throw StreamError.malformed("message_start carried no message")
            }
            message = start
            // The skeleton arrives with an empty content array; blocks are added as they stream.
            message["content"] = []
            sawMessageStart = true

        case "content_block_start":
            guard let index = event["index"] as? Int,
                  let block = event["content_block"] as? [String: Any] else {
                throw StreamError.malformed("content_block_start missing index or content_block")
            }
            blocks[index] = PartialBlock(raw: block)
            if !order.contains(index) { order.append(index) }

        case "content_block_delta":
            guard let index = event["index"] as? Int,
                  let delta = event["delta"] as? [String: Any] else {
                throw StreamError.malformed("content_block_delta missing index or delta")
            }
            guard var block = blocks[index] else {
                throw StreamError.malformed("delta for block \(index) that never started")
            }
            switch delta["type"] as? String {
            case "text_delta":
                block.text += (delta["text"] as? String) ?? ""
            case "input_json_delta":
                block.partialJSON += (delta["partial_json"] as? String) ?? ""
            case "thinking_delta":
                block.text += (delta["thinking"] as? String) ?? ""
            default:
                // An unrecognised delta kind is not fatal: a future block type the app does not
                // read must not take down a generation the owner already paid for.
                break
            }
            blocks[index] = block

        case "content_block_stop":
            guard let index = event["index"] as? Int else {
                throw StreamError.malformed("content_block_stop missing index")
            }
            try close(index: index)

        case "message_delta":
            if let delta = event["delta"] as? [String: Any] {
                for (key, value) in delta { message[key] = value }
            }
            // Streamed usage arrives in pieces; merge rather than replace so the input-token
            // count from `message_start` survives the output count from here.
            if let usage = event["usage"] as? [String: Any] {
                var merged = message["usage"] as? [String: Any] ?? [:]
                for (key, value) in usage { merged[key] = value }
                message["usage"] = merged
            }

        case "message_stop":
            sawMessageStop = true

        case "error":
            let error = event["error"] as? [String: Any]
            throw StreamError.apiError(
                type: error?["type"] as? String ?? "api_error",
                message: error?["message"] as? String ?? "The stream reported an error with no message."
            )

        case "ping":
            break

        default:
            break
        }
    }

    /// Turn a finished block's accumulated fragments into the field the callers actually read.
    private mutating func close(index: Int) throws {
        guard var block = blocks[index] else { return }

        switch block.raw["type"] as? String {
        case "tool_use":
            // The whole point of the structured path. Fragments concatenate into the tool input's
            // JSON; a block that closes with nothing accumulated means an empty argument object,
            // which is different from a malformed one and must not be treated as a parse failure.
            let json = block.partialJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if json.isEmpty {
                block.raw["input"] = [String: Any]()
            } else {
                guard let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw StreamError.malformed(
                        "tool_use input did not reassemble into JSON (\(json.count) chars)"
                    )
                }
                block.raw["input"] = object
            }
        case "text":
            block.raw["text"] = block.text
        case "thinking":
            block.raw["thinking"] = block.text
        default:
            if !block.text.isEmpty { block.raw["text"] = block.text }
        }

        blocks[index] = block
    }

    // MARK: - Finishing

    /// The reassembled response, in the same shape a non-streaming call would have returned.
    ///
    /// Blocks that never received their `content_block_stop` are still closed here. A stream cut
    /// off mid-block yields a truncated tool input that fails to parse, which surfaces as a parse
    /// error naming the real cause rather than a silently half-built week.
    mutating func finish() throws -> Data {
        guard sawMessageStart else {
            throw StreamError.malformed("stream ended before message_start (\(eventCount) events)")
        }

        for index in order where blocks[index] != nil {
            try close(index: index)
        }

        message["content"] = order.compactMap { blocks[$0]?.raw }

        if !sawMessageStop, message["stop_reason"] == nil {
            // Never invent `end_turn` for a stream that stopped early — the callers treat a
            // missing tool_use block as a protocol failure, which is the honest outcome.
            message["stop_reason"] = NSNull()
        }

        return try JSONSerialization.data(withJSONObject: message)
    }
}
