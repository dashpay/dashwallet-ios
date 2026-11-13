import Foundation

/// One Platform write of the App Connect flow, with the values it carries
/// (ADR-0018).
enum PlatformWrite {
    /// Add `add` and disable `disable` public keys of the wallet identity.
    case updateKeys(add: [UInt32], disable: [UInt32])
    /// Publish the response document of the request with this hash.
    case publish(requestHash: Data)
    /// Disable the fence keys with these ids.
    case fence(keyIds: [UInt32])
    /// Delete the response document with this id.
    case deleteResponse(documentId: Data)

    /// The case label, the only part of a write a log line shows: the values
    /// can name keys and documents.
    var kind: String {
        switch self {
        case .updateKeys: return "updateKeys"
        case .publish: return "publish"
        case .fence: return "fence"
        case .deleteResponse: return "deleteResponse"
        }
    }
}

/// Runs a `PlatformWrite` through the one place that logs and times it
/// (ADR-0018): a start line before the write is submitted, one outcome line
/// after, and a timeout that ends a write which never returns.
///
/// The outcome says what the executor saw, not what Platform did. A write that
/// failed or timed out may still have landed, and one that was submitted may
/// not have; the caller's next read decides (spec AC-20, ADR-0018). The
/// executor never retries and never reports a write as landed or confirmed.
///
/// The submit and the timer run as separate tasks and the first to finish
/// decides; the loser is cancelled but not awaited. The real submits block
/// inside Rust and ignore cancellation, so `run` returns `timedOut` on time
/// while such a submit is still running; when that submit ends it logs a late
/// line and hands its outcome to the optional `onLateOutcome` of `run`. A submit
/// that ends after the caller cancelled gets neither.
struct AppConnectWriteExecutor {
    /// How long a write may run before it is reported `timedOut` (Roman,
    /// 2026-11-06).
    static let defaultTimeout: Duration = .seconds(60)

    /// What the executor saw of one write.
    enum Outcome {
        /// The submit returned without an error.
        case submitted
        /// The submit threw this error, or the caller was cancelled before the
        /// submit returned and this carries a `CancellationError`.
        case failed(Error)
        /// The submit had not returned when the timeout passed.
        case timedOut
    }

    private let timeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let log: @Sendable (String) -> Void
    private let submit: @Sendable (PlatformWrite) async throws -> Void

    /// `sleep` is the clock (`Task.sleep` in production, which throws when
    /// cancelled); `log` takes the caller's logger, so the lines reach the same
    /// export as the caller's own; `submit` sends the write.
    init(
        timeout: Duration = defaultTimeout,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        log: @escaping @Sendable (String) -> Void,
        submit: @escaping @Sendable (PlatformWrite) async throws -> Void
    ) {
        self.timeout = timeout
        self.sleep = sleep
        self.log = log
        self.submit = submit
    }

    /// `onLateOutcome` is called once, with `.submitted` or `.failed`, when the
    /// submit ends after `run` returned `.timedOut`; never otherwise.
    func run(
        _ write: PlatformWrite,
        onLateOutcome: (@Sendable (Outcome) async -> Void)? = nil
    ) async -> Outcome {
        let kind = write.kind
        log("platform write \(kind): start")

        let race = Race()
        let submit = submit
        let sleep = sleep
        let timeout = timeout
        let log = log
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
                let submitTask = Task {
                    let result: Outcome
                    do {
                        try await submit(write)
                        result = .submitted
                    } catch {
                        result = .failed(error)
                    }
                    guard !race.finish(result), race.endedByTimeout else { return }
                    switch result {
                    case .failed(let error):
                        log("platform write \(kind): late failed \(Self.logDescription(of: error))")
                    default:
                        log("platform write \(kind): late submitted")
                    }
                    await onLateOutcome?(result)
                }
                let timer = Task {
                    // Throws when cancelled: by the winner of the race (the finish
                    // is then dropped) or by the caller, whose cancellation the
                    // blocked submit ignores and which ends the race here.
                    do { try await sleep(timeout) } catch {
                        race.finish(.failed(CancellationError()))
                        return
                    }
                    race.finish(.timedOut)
                }
                race.start(continuation, cancelling: [submitTask, timer])
            }
        } onCancel: {
            race.cancelTasks()
        }

        switch outcome {
        case .submitted:
            log("platform write \(kind): submitted")
        case .failed(let error):
            log("platform write \(kind): failed \(Self.logDescription(of: error))")
        case .timedOut:
            log("platform write \(kind): timedOut")
        }
        return outcome
    }

    /// An error as a log line can carry it: its type, its case label and, for a
    /// consensus rejection, its code; never its text, which can name keys or
    /// identities (SAD §8 Logging).
    static func logDescription(of error: Error) -> String {
        var parts = [String(describing: type(of: error))]
        if let caseName = AssetLockFailureRecord.caseName(of: error) {
            parts.append(caseName)
        }
        if let refusal = PlatformDashConnectDataSource.consensusRefusal(from: error, at: Date()) {
            parts.append("code=\(refusal.code)")
        }
        return parts.joined(separator: " ")
    }
}

/// What the timer ended: the error a caller throws when it must fail on a
/// write that gave none of its own.
struct AppConnectWriteTimedOut: Error {}

extension AppConnectWriteExecutor.Outcome {
    /// The error of a write that did not return cleanly: the submit's own, or
    /// `AppConnectWriteTimedOut`. Nil for a submitted write.
    var failure: Error? {
        switch self {
        case .submitted: return nil
        case .failed(let error): return error
        case .timedOut: return AppConnectWriteTimedOut()
        }
    }
}

extension AppConnect {
    /// What a caller does after a write, decided from the outcome alone. A write
    /// that failed or timed out may still have landed (spec AC-20), so only a
    /// read of Platform settles it, except for the verdict of a consensus
    /// rejection of an identity update, which is final.
    enum WriteNextStep: Equatable {
        /// The submit returned without an error.
        case done
        /// Platform refused the identity update for good; record it on the intent.
        case recordRefusal(ConsensusRefusal)
        /// Read the identity: the update may have landed.
        case readIdentity
        /// Look the response document up: the publish or delete may have landed.
        case lookUpResponse
        /// Send nothing more; the next run reads and carries on.
        case stop
    }

    /// The step after `write` ended as `outcome`; `date` stamps a refusal.
    static func nextStep(
        after write: PlatformWrite, outcome: AppConnectWriteExecutor.Outcome, at date: Date
    ) -> WriteNextStep {
        if case .submitted = outcome { return .done }
        switch write {
        case .updateKeys:
            if case .failed(let error) = outcome,
               let refusal = PlatformDashConnectDataSource.consensusRefusal(from: error, at: date) {
                return .recordRefusal(refusal)
            }
            return .readIdentity
        case .publish, .deleteResponse:
            return .lookUpResponse
        case .fence:
            return .stop
        }
    }
}

/// Decides a race between the submit and the timer: the first `finish` resumes
/// the continuation, every later one is dropped. Cancels both tasks once decided.
private final class Race: @unchecked Sendable {
    typealias Waiter = CheckedContinuation<AppConnectWriteExecutor.Outcome, Never>

    private let lock = NSLock()
    private var continuation: Waiter?
    private var tasks: [Task<Void, Never>] = []
    private var outcome: AppConnectWriteExecutor.Outcome?
    private var cancelled = false

    /// Hands over the continuation and the tasks to cancel. If a task finished
    /// or the caller was cancelled before this ran, that already happened.
    func start(
        _ continuation: Waiter,
        cancelling tasks: [Task<Void, Never>]
    ) {
        let (decided, cancelNow) = lock.withLock { () -> (AppConnectWriteExecutor.Outcome?, Bool) in
            self.tasks = tasks
            if outcome == nil { self.continuation = continuation }
            return (outcome, outcome != nil || cancelled)
        }
        if cancelNow { tasks.forEach { $0.cancel() } }
        decided.map { continuation.resume(returning: $0) }
    }

    /// True when the timer decided the race.
    var endedByTimeout: Bool {
        lock.withLock {
            if case .timedOut? = outcome { return true }
            return false
        }
    }

    /// Returns whether this call decided the race.
    @discardableResult
    func finish(_ result: AppConnectWriteExecutor.Outcome) -> Bool {
        // Nil tasks: an earlier finish already decided.
        let (tasks, continuation) = lock.withLock { () -> ([Task<Void, Never>]?, Waiter?) in
            guard outcome == nil else { return (nil, nil) }
            outcome = result
            defer { self.continuation = nil }
            return (self.tasks, self.continuation)
        }
        tasks?.forEach { $0.cancel() }
        continuation?.resume(returning: result)
        return tasks != nil
    }

    func cancelTasks() {
        let tasks = lock.withLock { () -> [Task<Void, Never>] in
            cancelled = true
            return self.tasks
        }
        tasks.forEach { $0.cancel() }
    }
}
