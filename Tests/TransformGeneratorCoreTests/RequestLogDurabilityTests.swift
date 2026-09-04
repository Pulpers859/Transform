import Foundation
import XCTest
@testable import Transform

/// `AnthropicClient.logRequest` was a bare `print`. On the owner's phone nothing reads stdout, so
/// the request profile, every retry with its reason and backoff, the failure category and the
/// lifecycle phase at the moment a generation broke all existed for an instant and were gone. A
/// failure he reported could not be investigated after the fact, only guessed at.
///
/// These tests pin the bounded, on-device log that now keeps that evidence — and, just as
/// importantly, pin what it must NOT keep.
@MainActor
final class RequestLogDurabilityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WorkoutGenerationDiagnostics.clearRequestLog()
    }

    override func tearDown() {
        WorkoutGenerationDiagnostics.clearRequestLog()
        super.tearDown()
    }

    func testAnEventSurvivesBeingWritten() {
        WorkoutGenerationDiagnostics.recordRequestEvent("[AnthropicClient][abc][failure] category=transport_timeout")

        let events = WorkoutGenerationDiagnostics.recentRequestEvents
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].contains("category=transport_timeout"), events[0])
    }

    /// A timeline is only useful if it reads in order.
    func testEventsAreKeptOldestFirst() {
        for index in 1...5 {
            WorkoutGenerationDiagnostics.recordRequestEvent("event-\(index)")
        }

        let events = WorkoutGenerationDiagnostics.recentRequestEvents
        XCTAssertEqual(events.count, 5)
        XCTAssertTrue(events.first?.contains("event-1") == true, "\(events)")
        XCTAssertTrue(events.last?.contains("event-5") == true, "\(events)")
    }

    /// Unbounded growth in `UserDefaults` would be a slow leak on the owner's device. The cap must
    /// drop the OLDEST entries — the newest ones are the ones describing the failure he just hit.
    func testTheLogIsCappedAndDropsTheOldestFirst() {
        let overflow = WorkoutGenerationDiagnostics.requestLogCapacity + 25
        for index in 1...overflow {
            WorkoutGenerationDiagnostics.recordRequestEvent("event-\(index)")
        }

        let events = WorkoutGenerationDiagnostics.recentRequestEvents
        XCTAssertEqual(events.count, WorkoutGenerationDiagnostics.requestLogCapacity)
        XCTAssertTrue(
            events.last?.contains("event-\(overflow)") == true,
            "The most recent event must survive: \(events.suffix(2))"
        )
        XCTAssertFalse(
            events.contains { $0.contains("event-1 ") || $0.hasSuffix("event-1") },
            "The oldest events must be the ones dropped"
        )
    }

    /// One pathological error string must not crowd out the history around it, which is usually
    /// the more useful part of the record.
    func testAnEnormousEventIsTruncatedRatherThanStoredWhole() {
        WorkoutGenerationDiagnostics.recordRequestEvent(String(repeating: "x", count: 10_000))

        let stored = WorkoutGenerationDiagnostics.recentRequestEvents.first ?? ""
        XCTAssertLessThan(stored.count, 1_000, "A single event should not be able to grow without bound")
        XCTAssertTrue(stored.hasSuffix("…"), "Truncation should be visible rather than silent")
    }

    func testBlankEventsAreIgnored() {
        WorkoutGenerationDiagnostics.recordRequestEvent("")
        WorkoutGenerationDiagnostics.recordRequestEvent("   \n  ")

        XCTAssertTrue(WorkoutGenerationDiagnostics.recentRequestEvents.isEmpty)
    }

    func testClearingEmptiesTheLog() {
        WorkoutGenerationDiagnostics.recordRequestEvent("something")
        XCTAssertFalse(WorkoutGenerationDiagnostics.recentRequestEvents.isEmpty)

        WorkoutGenerationDiagnostics.clearRequestLog()
        XCTAssertTrue(WorkoutGenerationDiagnostics.recentRequestEvents.isEmpty)
    }

    func testTheLogRendersAsPastableText() {
        WorkoutGenerationDiagnostics.recordRequestEvent("first")
        WorkoutGenerationDiagnostics.recordRequestEvent("second")

        let text = WorkoutGenerationDiagnostics.requestLogText
        XCTAssertTrue(text.contains("first"))
        XCTAssertTrue(text.contains("second"))
        XCTAssertEqual(text.components(separatedBy: "\n").count, 2)
    }

    /// Every event is timestamped, because "it failed on the third retry" is only actionable next
    /// to when that happened relative to the run.
    func testEveryEventIsTimestamped() {
        WorkoutGenerationDiagnostics.recordRequestEvent("[AnthropicClient][id][start] model=claude-opus-5")

        let stored = WorkoutGenerationDiagnostics.recentRequestEvents.first ?? ""
        // ISO8601 without fractional seconds: 2026-09-04T23:36:08Z
        let prefix = String(stored.prefix(20))
        XCTAssertNotNil(
            ISO8601DateFormatter().date(from: prefix),
            "Expected a leading ISO8601 timestamp, got: \(stored.prefix(40))"
        )
    }
}
