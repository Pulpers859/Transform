import XCTest
@testable import Transform

/// Pins the rule that decides whether a timed-out Anthropic request may be retried.
///
/// This is a money test. Retrying a request that already reached Anthropic pays for the same
/// generation twice, and the first version of this rule did exactly that: it asked only "did
/// this task ever wait for connectivity", so a signal blip at the START of a request that then
/// uploaded, was billed, and later timed out on genuine model latency counted as "free to
/// retry". The invariant is narrower — a stall AND no body bytes on the wire.
final class ConnectivityRetryTests: XCTestCase {

    private func recorder(waited: Bool, sentBytes: Bool) -> ConnectivityWaitRecorder {
        let subject = ConnectivityWaitRecorder()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://example.invalid")!)
        if waited {
            subject.urlSession(session, taskIsWaitingForConnectivity: task)
        }
        if sentBytes {
            subject.urlSession(session, task: task, didSendBodyData: 512,
                               totalBytesSent: 512, totalBytesExpectedToSend: 4096)
        }
        task.cancel()
        session.invalidateAndCancel()
        return subject
    }

    /// The only state that licenses a retry.
    func testAStallWithNothingSentIsFreeToRetry() {
        let subject = recorder(waited: true, sentBytes: false)
        XCTAssertTrue(subject.isFreeToRetry)
        XCTAssertTrue(subject.didWaitForConnectivity)
    }

    /// The bug this test exists for: a blip, then a successful upload, then a slow-model timeout.
    /// Anthropic generated and billed it. Retrying would pay twice.
    func testAStallFollowedByAnUploadIsNotFreeToRetry() {
        let subject = recorder(waited: true, sentBytes: true)
        XCTAssertFalse(subject.isFreeToRetry,
                       "Body bytes went out, so the request may have been served and billed")
        XCTAssertTrue(subject.didWaitForConnectivity,
                      "The stall is still worth RECORDING even when it cannot license a retry")
    }

    /// Genuine model slowness with no connectivity trouble: the original no-retry rule stands.
    func testAPlainTimeoutWithNoStallIsNotFreeToRetry() {
        XCTAssertFalse(recorder(waited: false, sentBytes: false).isFreeToRetry)
        XCTAssertFalse(recorder(waited: false, sentBytes: true).isFreeToRetry)
    }

    /// A zero-byte progress callback is not evidence the request reached anyone.
    func testAZeroByteProgressReportDoesNotVoidTheClaim() {
        let subject = ConnectivityWaitRecorder()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://example.invalid")!)
        subject.urlSession(session, taskIsWaitingForConnectivity: task)
        subject.urlSession(session, task: task, didSendBodyData: 0,
                           totalBytesSent: 0, totalBytesExpectedToSend: 4096)
        task.cancel()
        session.invalidateAndCancel()
        XCTAssertTrue(subject.isFreeToRetry)
    }

    /// Once bytes are out the claim stays void; no later callback may resurrect it.
    func testTheClaimIsNotResurrectedByLaterCallbacks() {
        let subject = ConnectivityWaitRecorder()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://example.invalid")!)
        subject.urlSession(session, task: task, didSendBodyData: 512,
                           totalBytesSent: 512, totalBytesExpectedToSend: 4096)
        subject.urlSession(session, taskIsWaitingForConnectivity: task)
        task.cancel()
        session.invalidateAndCancel()
        XCTAssertFalse(subject.isFreeToRetry,
                       "A stall recorded AFTER the upload must not make a billed request look free")
    }

    func testAFreshRecorderClaimsNothing() {
        let subject = ConnectivityWaitRecorder()
        XCTAssertFalse(subject.isFreeToRetry)
        XCTAssertFalse(subject.didWaitForConnectivity)
    }
}
