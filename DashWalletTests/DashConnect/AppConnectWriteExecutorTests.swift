import Foundation
import XCTest
@testable import dashpay
@testable import SwiftDashSDK

/// The one executor every Platform write goes through (ADR 0009, T11):
/// it logs the start and the outcome of each write, ends a hung write after the
/// timeout, and reports only what it saw (`submitted`, `failed`, `timedOut`).
/// Whether the write landed is decided by the caller's next read, never here
/// (spec AC-20, ADR 0004).
///
/// Rules the tests hold it to:
/// - Spec §6 Write traceability: "100 % of Platform writes log their start and
///   outcome" - one start line before the submit runs and one outcome line after,
///   each naming the write kind.
/// - SAD §8 Logging: an error is logged as type, case and a consensus rejection's
///   code, never its text.
/// - SAD §11 / T11 edge case: a write that never returns is ended by a timeout;
///   Roman set it to 60 seconds (2026-11-06).
final class AppConnectWriteExecutorTests: XCTestCase {
    private let sentinel = "SENTINEL-error-text-must-not-be-logged"

    /// Every write kind with the minimal values its case carries, and the kind
    /// name the log lines must show.
    private let writes: [(write: PlatformWrite, kind: String)] = [
        (.updateKeys(add: [3, 4], disable: [2]), "updateKeys"),
        (.publish(requestHash: Data([0x01, 0x02, 0x03])), "publish"),
        (.fence(keyIds: [5, 6]), "fence"),
        (.deleteResponse(documentId: Data([0x0A, 0x0B])), "deleteResponse")
    ]

    func testLogDescriptionNamesTheTypeAndNeverTheMessage() {
        struct Boom: LocalizedError {
            var errorDescription: String? { "SENTINEL-error-text-must-not-be-logged" }
        }

        let line = AppConnectWriteExecutor.logDescription(of: Boom())

        XCTAssertTrue(line.contains("Boom"), "the type name is logged: \(line)")
        XCTAssertFalse(line.contains("SENTINEL"), "the message must not be logged: \(line)")
    }

    // MARK: - Submitted

    func testSubmittedWriteReportsSubmittedAndLogsStartAndOutcome() async {
        for (write, kind) in writes {
            let probe = Probe()
            let executor = probe.executor(neverTimesOut: true) { _ in }

            let outcome = await executor.run(write)

            guard case .submitted = outcome else {
                XCTFail("\(kind): expected .submitted, got \(outcome)")
                continue
            }
            let lines = probe.lines
            XCTAssertEqual(lines.count, 2, "\(kind): one start and one outcome line, got \(lines)")
            XCTAssertTrue(lines.allSatisfy { $0.contains(kind) }, "\(kind): every line names the write kind: \(lines)")
            XCTAssertTrue(lines.last?.contains("submitted") ?? false, "\(kind): outcome line says submitted: \(lines)")
        }
    }

    func testStartIsLoggedBeforeTheSubmitRuns() async {
        let probe = Probe()
        let executor = probe.executor(neverTimesOut: true) { _ in probe.noteLinesAtSubmit() }

        _ = await executor.run(.fence(keyIds: [1]))

        XCTAssertEqual(probe.linesAtSubmit, 1, "the start line is written before the write is submitted")
    }

    // MARK: - Failed

    func testFailedWriteReportsTheErrorAndLogsStartAndOutcome() async {
        for (write, kind) in writes {
            let probe = Probe()
            let executor = probe.executor(neverTimesOut: true) { _ in throw SDKError.networkError(self.sentinel) }

            let outcome = await executor.run(write)

            guard case .failed(let error) = outcome else {
                XCTFail("\(kind): expected .failed, got \(outcome)")
                continue
            }
            guard case SDKError.networkError(let message) = error else {
                XCTFail("\(kind): the submit's own error is returned, got \(error)")
                continue
            }
            XCTAssertEqual(message, sentinel)
            let lines = probe.lines
            XCTAssertEqual(lines.count, 2, "\(kind): one start and one outcome line, got \(lines)")
            XCTAssertTrue(lines.allSatisfy { $0.contains(kind) }, "\(kind): every line names the write kind: \(lines)")
            XCTAssertTrue(lines.last?.contains("failed") ?? false, "\(kind): outcome line says failed: \(lines)")
        }
    }

    func testFailureLogsTypeAndCaseNeverTheText() async {
        let probe = Probe()
        let executor = probe.executor(neverTimesOut: true) { _ in throw SDKError.networkError(self.sentinel) }

        _ = await executor.run(.updateKeys(add: [3], disable: []))

        let outcomeLine = probe.lines.last ?? ""
        XCTAssertTrue(outcomeLine.contains("SDKError"), "the error type is logged: \(outcomeLine)")
        XCTAssertTrue(outcomeLine.contains("networkError"), "the error case is logged: \(outcomeLine)")
        XCTAssertFalse(probe.lines.joined().contains(sentinel), "the error text is never logged: \(probe.lines)")
    }

    func testConsensusRejectionLogsItsCodeNeverItsText() async {
        let probe = Probe()
        let rejection = SDKError.consensusRejection(PlatformConsensusError(code: 10_534, kind: .basic), sentinel)
        let executor = probe.executor(neverTimesOut: true) { _ in throw rejection }

        _ = await executor.run(.publish(requestHash: Data([0x01])))

        let outcomeLine = probe.lines.last ?? ""
        XCTAssertTrue(outcomeLine.contains("consensusRejection"), "the error case is logged: \(outcomeLine)")
        XCTAssertTrue(outcomeLine.contains("10534"), "the consensus code is logged: \(outcomeLine)")
        XCTAssertFalse(probe.lines.joined().contains(sentinel), "the rejection text is never logged: \(probe.lines)")
    }

    func testErrorThatIsNotAnSDKErrorLogsItsTypeAndCaseNeverItsText() async {
        let probe = Probe()
        let executor = probe.executor(neverTimesOut: true) { _ in throw SentinelError.refused(self.sentinel) }

        _ = await executor.run(.deleteResponse(documentId: Data([0x0A])))

        let outcomeLine = probe.lines.last ?? ""
        XCTAssertTrue(outcomeLine.contains("SentinelError"), "the error type is logged: \(outcomeLine)")
        XCTAssertTrue(outcomeLine.contains("refused"), "the error case is logged: \(outcomeLine)")
        XCTAssertFalse(probe.lines.joined().contains(sentinel), "the error text is never logged: \(probe.lines)")
    }

    func testLocalizedDescriptionOfAnErrorIsNeverLogged() async {
        let probe = Probe()
        let executor = probe.executor(neverTimesOut: true) { _ in throw DescribedError(text: self.sentinel) }

        _ = await executor.run(.fence(keyIds: [1]))

        XCTAssertFalse(probe.lines.joined().contains(sentinel), "the error's description is never logged: \(probe.lines)")
    }

    // MARK: - Timed out

    func testWriteThatNeverReturnsTimesOutAndLogsStartAndOutcome() async {
        for (write, kind) in writes {
            let probe = Probe()
            let executor = probe.executor(neverTimesOut: false) { _ in
                // Suspends until the executor cancels it.
                try await Task.sleep(for: .seconds(1_000_000))
            }

            let outcome = await executor.run(write)

            guard case .timedOut = outcome else {
                XCTFail("\(kind): expected .timedOut, got \(outcome)")
                continue
            }
            let lines = probe.lines
            XCTAssertEqual(lines.count, 2, "\(kind): one start and one outcome line, got \(lines)")
            XCTAssertTrue(lines.allSatisfy { $0.contains(kind) }, "\(kind): every line names the write kind: \(lines)")
            XCTAssertTrue(lines.last?.contains("timedOut") ?? false, "\(kind): outcome line says timedOut: \(lines)")
            XCTAssertEqual(probe.requestedSleeps, [.seconds(60)], "\(kind): the clock is asked for the 60 second timeout")
        }
    }

    /// The real submits block inside Rust and ignore Swift cancellation, so the
    /// timeout must end `run` without waiting for the submit to return. A late
    /// finish of the submit writes no further line: the outcome line already
    /// said `timedOut`, and the caller's next read decides what landed.
    func testTimeoutEndsRunWhileTheSubmitIgnoresCancellation() async {
        let probe = Probe()
        let blocked = BlockedSubmit()
        let executor = probe.executor(neverTimesOut: false) { _ in await blocked.waitIgnoringCancellation() }
        let returned = expectation(description: "run returned while the submit was still blocked")
        let result = OutcomeBox()

        Task {
            result.set(await executor.run(.updateKeys(add: [3], disable: [])))
            returned.fulfill()
        }
        await fulfillment(of: [returned], timeout: 5)
        blocked.release()
        await blocked.waitUntilSubmitReturned()

        guard case .timedOut = result.value else {
            XCTFail("expected .timedOut while the submit never returned, got \(String(describing: result.value))")
            return
        }
        XCTAssertEqual(probe.lines.count, 2, "no line is written when the submit finishes late: \(probe.lines)")
        XCTAssertTrue(probe.lines.last?.contains("timedOut") ?? false, "outcome line says timedOut: \(probe.lines)")
    }

    /// R15: cancelling the caller while the submit is blocked (the real
    /// submits ignore cancellation) still ends `run`, with a cancellation.
    func testCancellingTheCallerWhileTheSubmitIsBlockedStillEndsRun() async {
        let gate = CallerCancelSubmit()
        let executor = AppConnectWriteExecutor(
            sleep: { try await Task.sleep(for: $0) }, log: { _ in },
            submit: { _ in await gate.block() })
        let ended = expectation(description: "run returned")
        let box = OutcomeBox()
        let task = Task {
            let outcome = await executor.run(.fence(keyIds: [1]))
            box.set(outcome)
            ended.fulfill()
        }
        await gate.waitUntilBlocked()

        task.cancel()
        await fulfillment(of: [ended], timeout: 2)
        gate.release()

        guard case .failed(let error)? = box.value else {
            return XCTFail("expected .failed(CancellationError), got \(String(describing: box.value))")
        }
        XCTAssertTrue(error is CancellationError)
    }

    func testDefaultTimeoutIsSixtySeconds() {
        XCTAssertEqual(AppConnectWriteExecutor.defaultTimeout, .seconds(60))
    }

    // MARK: - Landed without confirm

    /// A write that landed on Platform but whose submit reported an error is
    /// still `.failed`: the executor has no way to say "landed"; the caller's
    /// next read decides (AC-20: the connection is then listed as Confirming).
    func testLandedWithoutConfirmIsStillReportedAsFailedAndNeverGuessed() async {
        let probe = Probe()
        let landed = Landed()
        let executor = probe.executor(neverTimesOut: true) { _ in
            landed.mark()
            throw SDKError.timeout(self.sentinel)
        }

        let outcome = await executor.run(.updateKeys(add: [3], disable: []))

        XCTAssertTrue(landed.isMarked, "the write reached Platform")
        // An exhaustive switch with no default: the outcome has exactly these
        // three cases, so a "landed" or "guessed" case fails to compile here.
        switch outcome {
        case .submitted: XCTFail("a submit that threw is not reported as submitted")
        case .failed: break
        case .timedOut: XCTFail("a submit that threw is not reported as timed out")
        }
        XCTAssertEqual(probe.submitCount, 1, "the executor does not retry or re-submit on its own")
        let lines = probe.lines.joined(separator: "\n").lowercased()
        XCTAssertFalse(lines.contains("landed"), "the log never claims the write landed: \(probe.lines)")
        XCTAssertFalse(lines.contains("confirmed"), "the log never claims the write was confirmed: \(probe.lines)")
    }
}

// MARK: - Scaffold

private enum SentinelError: Error {
    case refused(String)
}

private struct DescribedError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

/// Records what the executor wrote to its log sink and asked of its clock, and
/// builds the executor under test around the recorded closures.
private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    private var _sleeps: [Duration] = []
    private var _submitCount = 0
    private var _linesAtSubmit: Int?

    var lines: [String] { lock.withLock { _lines } }
    var requestedSleeps: [Duration] { lock.withLock { _sleeps } }
    var submitCount: Int { lock.withLock { _submitCount } }
    var linesAtSubmit: Int? { lock.withLock { _linesAtSubmit } }

    func noteLinesAtSubmit() {
        lock.withLock { _linesAtSubmit = _lines.count }
    }

    /// `neverTimesOut` true: the clock never fires, so the submit decides.
    /// False: the clock fires at once, as if the whole timeout had passed.
    func executor(
        neverTimesOut: Bool,
        submit: @escaping @Sendable (PlatformWrite) async throws -> Void
    ) -> AppConnectWriteExecutor {
        AppConnectWriteExecutor(
            sleep: { [self] duration in
                lock.withLock { _sleeps.append(duration) }
                if neverTimesOut { try await Task.sleep(for: .seconds(1_000_000)) }
            },
            log: { [self] line in lock.withLock { _lines.append(line) } },
            submit: { [self] write in
                lock.withLock { _submitCount += 1 }
                try await submit(write)
            })
    }
}

private final class Landed: @unchecked Sendable {
    private let lock = NSLock()
    private var marked = false
    var isMarked: Bool { lock.withLock { marked } }
    func mark() { lock.withLock { marked = true } }
}

/// A submit that ignores cancellation: it waits on a continuation only
/// `release()` resumes, as a call blocked inside Rust would.
private final class BlockedSubmit: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var returned = false
    private var returnWaiter: CheckedContinuation<Void, Never>?

    func waitIgnoringCancellation() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if released { return true }
                self.continuation = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            returned = true
            defer { returnWaiter = nil }
            return returnWaiter
        }
        waiter?.resume()
    }

    func release() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume()
    }

    /// Suspends until the submit has returned, or returns at once if it already did.
    /// Also returns at once if the submit never started, so a failed run cannot hang the test.
    func waitUntilSubmitReturned() async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if returned { return true }
                returnWaiter = waiter
                return false
            }
            if resumeNow { waiter.resume() }
        }
    }
}

private final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: AppConnectWriteExecutor.Outcome?

    var value: AppConnectWriteExecutor.Outcome? { lock.withLock { outcome } }
    func set(_ newValue: AppConnectWriteExecutor.Outcome) { lock.withLock { outcome = newValue } }
}

/// A submit that ignores cancellation until released.
private final class CallerCancelSubmit: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var started = false

    func block() async {
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                started = true
                if released { return true }
                continuation = waiter
                return false
            }
            if resumeNow { waiter.resume() }
        }
    }

    func waitUntilBlocked() async {
        while !lock.withLock({ started }) { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func release() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            defer { continuation = nil }
            return continuation
        }
        waiter?.resume()
    }
}
