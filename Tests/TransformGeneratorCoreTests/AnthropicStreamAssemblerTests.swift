import Foundation
import XCTest
@testable import Transform

/// Week 1 generation timed out on the owner's phone at `duration_ms=480739` — the hard
/// wall-clock ceiling — because a non-streaming request gives no progress signal, so the
/// inactivity timer could never fire and a stopwatch was the only defence. The response now
/// streams, which means every paid week is reassembled from SSE fragments before anything else
/// sees it.
///
/// If that reassembly is wrong, a generation the owner paid for is lost. These drive it with
/// scripted transcripts in the shape the API actually sends.
final class AnthropicStreamAssemblerTests: XCTestCase {

    /// Feeds lines the way `URLSession.AsyncBytes.lines` does — one line at a time, `data:`
    /// prefixed, blank lines between events.
    private func assemble(_ lines: [String]) throws -> [String: Any] {
        var assembler = AnthropicStreamAssembler()
        for line in lines {
            try assembler.consume(line: line)
        }
        let data = try assembler.finish()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnthropicStreamAssembler.StreamError.malformed("result was not an object")
        }
        return object
    }

    private func event(_ json: String) -> [String] {
        ["event: ignored", "data: \(json)", ""]
    }

    private var messageStart: [String] {
        event(#"{"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-4-8","content":[],"stop_reason":null,"usage":{"input_tokens":9000}}}"#)
    }

    // MARK: - The structured path every paid week depends on

    /// The tool input arrives as JSON split across fragments that are individually meaningless.
    /// It must come back out as a real object under `input`, which is the exact field
    /// `sendStructuredRequest` reads.
    func testToolInputIsReassembledFromItsFragments() throws {
        let root = try assemble(
            messageStart
            + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"emit_workout_program","input":{}}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"days\": [{\"dayNum"}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"ber\": 1, \"name\": \"Push\"}]}"}}"#)
            + event(#"{"type":"content_block_stop","index":0}"#)
            + event(#"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":812}}"#)
            + event(#"{"type":"message_stop"}"#)
        )

        XCTAssertEqual(root["stop_reason"] as? String, "tool_use")

        let content = try XCTUnwrap(root["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "tool_use")
        XCTAssertEqual(content[0]["name"] as? String, "emit_workout_program")

        let input = try XCTUnwrap(content[0]["input"] as? [String: Any])
        let days = try XCTUnwrap(input["days"] as? [[String: Any]])
        XCTAssertEqual(days.first?["dayNumber"] as? Int, 1)
        XCTAssertEqual(days.first?["name"] as? String, "Push")
    }

    /// A fragment boundary can fall anywhere, including inside a string or an escape sequence.
    /// Concatenate-then-parse must be the only interpretation performed.
    func testFragmentBoundariesInsideStringsAndEscapesSurvive() throws {
        let root = try assemble(
            messageStart
            + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"emit_workout_program","input":{}}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"note\": \"3 sets \\"}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"u00d7 10\"}"}}"#)
            + event(#"{"type":"content_block_stop","index":0}"#)
            + event(#"{"type":"message_stop"}"#)
        )

        let content = try XCTUnwrap(root["content"] as? [[String: Any]])
        let input = try XCTUnwrap(content[0]["input"] as? [String: Any])
        XCTAssertEqual(input["note"] as? String, "3 sets × 10")
    }

    /// A tool block that closes having accumulated nothing means empty arguments, which is a
    /// legitimate response — not a parse failure to be thrown at the owner.
    func testAToolBlockWithNoFragmentsYieldsEmptyArgumentsRatherThanThrowing() throws {
        let root = try assemble(
            messageStart
            + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"emit_workout_program","input":{}}}"#)
            + event(#"{"type":"content_block_stop","index":0}"#)
            + event(#"{"type":"message_stop"}"#)
        )
        let content = try XCTUnwrap(root["content"] as? [[String: Any]])
        XCTAssertNotNil(content[0]["input"] as? [String: Any])
    }

    // MARK: - Text mode

    func testTextDeltasConcatenateInOrder() throws {
        let root = try assemble(
            messageStart
            + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Week one "}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"is ready."}}"#)
            + event(#"{"type":"content_block_stop","index":0}"#)
            + event(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#)
            + event(#"{"type":"message_stop"}"#)
        )
        let content = try XCTUnwrap(root["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["text"] as? String, "Week one is ready.")
    }

    /// Blocks must come back in index order regardless of how their events interleave.
    func testMultipleBlocksKeepTheirOrder() throws {
        let root = try assemble(
            messageStart
            + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
            + event(#"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t","name":"emit_workout_program","input":{}}}"#)
            + event(#"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"ok\":true}"}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"preamble"}}"#)
            + event(#"{"type":"content_block_stop","index":1}"#)
            + event(#"{"type":"content_block_stop","index":0}"#)
            + event(#"{"type":"message_stop"}"#)
        )
        let content = try XCTUnwrap(root["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "preamble")
        XCTAssertEqual(content[1]["type"] as? String, "tool_use")
    }

    // MARK: - The truncation the callers already guard against

    /// `sendStructuredRequest` throws on `stop_reason == "max_tokens"` because the output is
    /// incomplete. That signal arrives in `message_delta` and has to survive reassembly, or a
    /// truncated week ships as if it were whole.
    func testMaxTokensStopReasonSurvives() throws {
        let root = try assemble(
            messageStart
            + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"emit_workout_program","input":{}}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"days\":[]}"}}"#)
            + event(#"{"type":"content_block_stop","index":0}"#)
            + event(#"{"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":8192}}"#)
            + event(#"{"type":"message_stop"}"#)
        )
        XCTAssertEqual(root["stop_reason"] as? String, "max_tokens")
    }

    /// A connection dropped mid-tool-input must fail loudly. Silently returning the half of the
    /// week that arrived is the one outcome worse than an error the owner can retry.
    func testAStreamCutMidToolInputFailsRatherThanReturningHalfAWeek() {
        XCTAssertThrowsError(
            try assemble(
                messageStart
                + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"emit_workout_program","input":{}}}"#)
                + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"days\": [{\"dayNumber\": 1,"}}"#)
            )
        ) { error in
            guard case AnthropicStreamAssembler.StreamError.malformed = error else {
                return XCTFail("Expected a malformed-stream error, got \(error)")
            }
        }
    }

    /// A stream that produced no message at all must not reassemble into an empty success.
    func testAStreamThatNeverStartedIsAnError() {
        XCTAssertThrowsError(try assemble(event(#"{"type":"ping"}"#))) { error in
            guard case AnthropicStreamAssembler.StreamError.malformed = error else {
                return XCTFail("Expected a malformed-stream error, got \(error)")
            }
        }
    }

    /// An error delivered mid-stream arrives as an ordinary event on a 200 response, so nothing
    /// else would notice it.
    func testAnErrorEventIsSurfacedWithItsMessage() {
        XCTAssertThrowsError(
            try assemble(messageStart + event(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#))
        ) { error in
            guard case let AnthropicStreamAssembler.StreamError.apiError(type, message) = error else {
                return XCTFail("Expected an apiError, got \(error)")
            }
            XCTAssertEqual(type, "overloaded_error")
            XCTAssertEqual(message, "Overloaded")
        }
    }

    // MARK: - Stream housekeeping

    func testPingsBlankLinesAndDoneAreIgnored() throws {
        let root = try assemble(
            messageStart
            + ["", ": comment", "data: [DONE]"]
            + event(#"{"type":"ping"}"#)
            + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"fine"}}"#)
            + event(#"{"type":"content_block_stop","index":0}"#)
            + event(#"{"type":"message_stop"}"#)
        )
        let content = try XCTUnwrap(root["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["text"] as? String, "fine")
    }

    /// Usage arrives in two halves — input tokens at the start, output tokens at the end. Merging
    /// rather than replacing is what keeps cost diagnostics honest.
    func testUsageIsMergedRatherThanReplaced() throws {
        let root = try assemble(
            messageStart
            + event(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":812}}"#)
            + event(#"{"type":"message_stop"}"#)
        )
        let usage = try XCTUnwrap(root["usage"] as? [String: Any])
        XCTAssertEqual(usage["input_tokens"] as? Int, 9000)
        XCTAssertEqual(usage["output_tokens"] as? Int, 812)
    }

    /// An unrecognised delta kind must not take down a week the owner already paid for.
    func testAnUnknownDeltaKindIsIgnoredRatherThanFatal() throws {
        let root = try assemble(
            messageStart
            + event(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t","name":"emit_workout_program","input":{}}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"some_future_delta","value":1}}"#)
            + event(#"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"ok\":true}"}}"#)
            + event(#"{"type":"content_block_stop","index":0}"#)
            + event(#"{"type":"message_stop"}"#)
        )
        let content = try XCTUnwrap(root["content"] as? [[String: Any]])
        let input = try XCTUnwrap(content[0]["input"] as? [String: Any])
        XCTAssertEqual(input["ok"] as? Bool, true)
    }
}
