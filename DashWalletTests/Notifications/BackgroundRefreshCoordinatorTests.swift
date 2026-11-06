//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit
import XCTest
@testable import dashpay

/// Drives the coordinator through the seams `NotificationsBootstrap`
/// injects: a fake scheduler records registration/submissions, a fake task
/// stands in for the unconstructible `BGAppRefreshTask`, and the sync wait,
/// runtime start/stop, and clock are injected closures.
@MainActor
final class BackgroundRefreshCoordinatorTests: XCTestCase {
    /// Long enough to never win a race, short enough to unwind promptly on
    /// cancellation (`Task.sleep` returns immediately once cancelled).
    private static let foreverNanos: UInt64 = 3_600_000_000_000

    private var scheduler: FakeBackgroundTaskScheduler!
    private var walletExists = true
    private var protectedDataAvailable = true
    private var runtimeStartResult = true
    private var runtimeStartCalls = 0
    /// The "still wanted" gate the run hands to the runtime bring-up, kept
    /// by `runtimeStartOverride` so a test can read it across an expiration.
    private var isRuntimeStartWanted: BackgroundRefreshStartGate?
    /// Invoked as the injected sync wait is entered, so a test can expire a
    /// run exactly once it is parked there.
    private var onWaitForSyncDone: (() -> Void)?
    private var runtimeStopCalls = 0
    private var runtimeRearmCalls = 0
    private var sweepCalls = 0
    private let fixedNow = Date(timeIntervalSince1970: 1_780_000_000)
    private var coordinator: BackgroundRefreshCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        scheduler = FakeBackgroundTaskScheduler()
        walletExists = true
        protectedDataAvailable = true
        runtimeStartResult = true
        runtimeStartCalls = 0
        isRuntimeStartWanted = nil
        onWaitForSyncDone = nil
        runtimeStopCalls = 0
        runtimeRearmCalls = 0
        sweepCalls = 0
    }

    override func tearDown() async throws {
        // Drop the observers registered in start() before the next test's
        // instance exists.
        coordinator = nil
        try await super.tearDown()
    }

    /// A cancellation-immune await: `withUnsafeContinuation` never resumes
    /// on task cancellation, mirroring the runtime's serial-queue bring-up
    /// that `run` awaits. `resolve` releases every current and later waiter.
    private final class ManualGate: @unchecked Sendable {
        private let lock = NSLock()
        private var resolved = false
        private var result = false
        private var continuations: [UnsafeContinuation<Bool, Never>] = []
        /// Invoked at the top of every `wait`, so a test can detect that
        /// the run body reached the blocked await.
        var onWait: (() -> Void)?

        func wait() async -> Bool {
            onWait?()
            return await withUnsafeContinuation { continuation in
                lock.lock()
                if resolved {
                    let value = result
                    lock.unlock()
                    continuation.resume(returning: value)
                } else {
                    continuations.append(continuation)
                    lock.unlock()
                }
            }
        }

        func resolve(_ value: Bool) {
            lock.lock()
            resolved = true
            result = value
            let waiting = continuations
            continuations = []
            lock.unlock()
            for continuation in waiting {
                continuation.resume(returning: value)
            }
        }
    }

    /// `syncDoneImmediately: true` resolves the sync wait at once (the
    /// deadline sleep never wins); `false` leaves the wait pending so only
    /// the deadline sleep — immediate by default in that mode — or an
    /// expiration can end it. `runtimeStartOverride` replaces the counted
    /// instant runtime start (the counter still ticks). `isEnabled` is passed
    /// explicitly: the build-level pause (`isEnabledInThisBuild`) must not
    /// decide what these tests exercise.
    private func makeCoordinator(isEnabled: Bool = true,
                                 syncDoneImmediately: Bool = true,
                                 deadlineSleepsForever: Bool = false,
                                 runtimeStartOverride: ((BackgroundRefreshStartGate) async -> Bool)? = nil) {
        coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            isEnabled: isEnabled,
            hasWallet: { [weak self] in self?.walletExists ?? false },
            isProtectedDataAvailable: { [weak self] in self?.protectedDataAvailable ?? true },
            runtimeStart: { @MainActor [weak self] gate in
                self?.runtimeStartCalls += 1
                self?.isRuntimeStartWanted = gate
                if let runtimeStartOverride {
                    return await runtimeStartOverride(gate)
                }
                return self?.runtimeStartResult ?? false
            },
            runtimeStop: { @MainActor [weak self] in
                self?.runtimeStopCalls += 1
            },
            runtimeRearm: { [weak self] in
                self?.runtimeRearmCalls += 1
            },
            waitForSyncDone: { @MainActor [weak self] in
                self?.onWaitForSyncDone?()
                if !syncDoneImmediately {
                    try? await Task.sleep(nanoseconds: Self.foreverNanos)
                }
            },
            postSyncProducerSweep: { @MainActor [weak self] in
                self?.sweepCalls += 1
            },
            sleep: { _ in
                if syncDoneImmediately || deadlineSleepsForever {
                    try? await Task.sleep(nanoseconds: Self.foreverNanos)
                }
            },
            now: { [fixedNow] in fixedNow })
    }

    /// Starts the coordinator, launches a fake task through the registered
    /// handler, and returns the task once it has been completed.
    private func runTask() async throws -> FakeBackgroundRefreshTask {
        coordinator.start()
        let handler = try XCTUnwrap(scheduler.launchHandlers[BackgroundRefreshCoordinator.taskIdentifier])
        let task = FakeBackgroundRefreshTask()
        let completed = expectation(description: "task completed")
        task.onSetTaskCompleted = { _ in completed.fulfill() }
        handler(task)
        await fulfillment(of: [completed], timeout: 5)
        return task
    }

    /// Fulfilled once the scheduler has recorded `count` submissions — the
    /// run body submits at its start and again at its end, so the second
    /// marks the body's completion.
    private func submissionsReach(_ count: Int) -> XCTestExpectation {
        let reached = expectation(description: "\(count) submissions")
        reached.assertForOverFulfill = false
        let scheduler = self.scheduler!
        if scheduler.submissions.count >= count {
            reached.fulfill()
        } else {
            scheduler.onSubmit = { _ in
                if scheduler.submissions.count >= count { reached.fulfill() }
            }
        }
        return reached
    }

    // MARK: Registration

    func testStartRegistersOnceWithTaskIdentifier() {
        makeCoordinator()

        coordinator.start()
        coordinator.start()

        XCTAssertEqual(scheduler.registeredIdentifiers, ["org.dashfoundation.dashpay.refresh"])
        XCTAssertEqual(scheduler.registeredIdentifiers, [BackgroundRefreshCoordinator.taskIdentifier])
    }

    // MARK: Scheduling on backgrounding

    func testBackgroundingSubmitsRequestWithEarliestBeginWhenWalletExists() throws {
        makeCoordinator()
        coordinator.start()

        coordinator.noteDidEnterBackground()

        XCTAssertEqual(scheduler.submissions.count, 1)
        let submission = try XCTUnwrap(scheduler.submissions.first)
        XCTAssertEqual(submission.identifier, BackgroundRefreshCoordinator.taskIdentifier)
        let earliest = try XCTUnwrap(submission.earliestBeginDate)
        XCTAssertEqual(earliest.timeIntervalSince(fixedNow), 15 * 60, accuracy: 1)
    }

    func testBackgroundingDoesNotSubmitWithoutWallet() {
        makeCoordinator()
        coordinator.start()
        walletExists = false

        coordinator.noteDidEnterBackground()

        XCTAssertTrue(scheduler.submissions.isEmpty)
    }

    func testBackgroundingSubmitsWhenLockedDeviceHidesTheWallet() {
        // Locked device: the wallet-presence keychain read fails and says "no
        // wallet". The chain must not end on that.
        makeCoordinator()
        coordinator.start()
        walletExists = false
        protectedDataAvailable = false

        coordinator.noteDidEnterBackground()

        XCTAssertEqual(scheduler.submissions.map(\.identifier), [BackgroundRefreshCoordinator.taskIdentifier])
    }

    func testDidEnterBackgroundNotificationSubmits() async {
        makeCoordinator()
        coordinator.start()
        let submitted = expectation(description: "request submitted")
        scheduler.onSubmit = { _ in submitted.fulfill() }

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        await fulfillment(of: [submitted], timeout: 2)
        XCTAssertEqual(scheduler.submissions.map(\.identifier), [BackgroundRefreshCoordinator.taskIdentifier])
    }

    // MARK: Task run — sync-done path

    func testRunAwaitsSyncDoneThenCompletesSuccessAndReschedules() async throws {
        makeCoordinator(syncDoneImmediately: true)

        let task = try await runTask()

        XCTAssertEqual(task.completions, [true])
        XCTAssertEqual(runtimeStartCalls, 1)
        XCTAssertEqual(sweepCalls, 1)
        // Submitted at the start of the run and again at its end.
        XCTAssertEqual(scheduler.submissions.map(\.identifier),
                       [BackgroundRefreshCoordinator.taskIdentifier, BackgroundRefreshCoordinator.taskIdentifier])
    }

    func testRunSubmitsNextRefreshBeforeStartingTheRuntime() async throws {
        var submissionsAtRuntimeStart: Int?
        makeCoordinator(syncDoneImmediately: true, runtimeStartOverride: { @MainActor [weak self] _ in
            submissionsAtRuntimeStart = self?.scheduler.submissions.count
            return true
        })

        _ = try await runTask()

        XCTAssertEqual(submissionsAtRuntimeStart, 1)
    }

    func testLockedDeviceSkipsSyncButKeepsTheChain() async throws {
        makeCoordinator(syncDoneImmediately: true)
        walletExists = false
        protectedDataAvailable = false

        let task = try await runTask()

        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(runtimeStartCalls, 0)
        XCTAssertEqual(runtimeStopCalls, 0)
        XCTAssertEqual(sweepCalls, 0)
        XCTAssertEqual(scheduler.submissions.map(\.identifier), [BackgroundRefreshCoordinator.taskIdentifier])
    }

    func testRunStopsRuntimeWhenProcessWasNeverActive() async throws {
        makeCoordinator(syncDoneImmediately: true)

        _ = try await runTask()

        // Never-foregrounded process: the runtime exists only for this run
        // and is torn down so persistence flushes and the process suspends.
        XCTAssertEqual(runtimeStopCalls, 1)
    }

    func testRunLeavesRuntimeAloneAfterForegroundSession() async throws {
        makeCoordinator(syncDoneImmediately: true)
        coordinator.start()
        coordinator.noteDidBecomeActive()

        let task = try await runTask()

        XCTAssertEqual(task.completions, [true])
        XCTAssertEqual(runtimeStopCalls, 0)
        XCTAssertEqual(runtimeRearmCalls, 0)
    }

    func testForegroundAfterBackgroundRunRearmsRuntime() async throws {
        makeCoordinator(syncDoneImmediately: true)

        _ = try await runTask()
        XCTAssertEqual(runtimeStopCalls, 1)

        coordinator.noteDidBecomeActive()

        XCTAssertEqual(runtimeRearmCalls, 1)

        // Only the run that stopped the runtime re-arms; later activations
        // are ordinary.
        coordinator.noteDidBecomeActive()
        XCTAssertEqual(runtimeRearmCalls, 1)
    }

    // MARK: Task run — deadline path

    func testDeadlineCompletesWithoutSuccess() async throws {
        // Sync never finishes; the deadline sleep returns immediately.
        makeCoordinator(syncDoneImmediately: false)

        let task = try await runTask()

        // No sync-done inside the deadline means the awaited sweep never
        // ran, so the run does not report success. Rows the sync did
        // persist are picked up by the producer's store and freshness rules
        // on the next open.
        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(sweepCalls, 0)
        XCTAssertEqual(runtimeStopCalls, 1)
        XCTAssertEqual(scheduler.submissions.count, 2)
    }

    func testRuntimeStartFailureCompletesWithoutSuccess() async throws {
        makeCoordinator(syncDoneImmediately: true)
        runtimeStartResult = false

        let task = try await runTask()

        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(sweepCalls, 0)
        // Teardown still runs: a half-started runtime must not keep the
        // process from suspending, and the runtime's stop is a safe no-op
        // when nothing is up.
        XCTAssertEqual(runtimeStopCalls, 1)
        XCTAssertEqual(scheduler.submissions.count, 2)
    }

    // MARK: Task run — expiration

    func testExpirationStopsWaitingAndCompletes() async throws {
        // Neither the sync wait nor the deadline sleep resolves on its own:
        // only the expiration handler can end this run.
        makeCoordinator(syncDoneImmediately: false, deadlineSleepsForever: true)
        coordinator.start()
        let handler = try XCTUnwrap(scheduler.launchHandlers[BackgroundRefreshCoordinator.taskIdentifier])
        let task = FakeBackgroundRefreshTask()
        let completed = expectation(description: "task completed")
        task.onSetTaskCompleted = { _ in completed.fulfill() }
        // The expiration path completes the task before the run body has
        // unwound; the tail re-submission marks the run body's end.
        let bodyEnded = submissionsReach(2)
        // Expire only once the run is actually parked on the sync wait —
        // expiring before the body starts is a different path (it never
        // reaches the runtime at all) and has its own test below.
        let waiting = expectation(description: "run parked on the sync wait")
        onWaitForSyncDone = { waiting.fulfill() }

        handler(task)
        await fulfillment(of: [waiting], timeout: 5)
        let expiration = try XCTUnwrap(task.expirationHandler)
        expiration()

        await fulfillment(of: [completed, bodyEnded], timeout: 5)
        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(sweepCalls, 0)
        // No teardown after expiration: the task was already completed.
        XCTAssertEqual(runtimeStopCalls, 0)
        XCTAssertFalse(coordinator.stoppedRuntimeAfterBackgroundRun)
        XCTAssertEqual(scheduler.submissions.count, 2)
    }

    func testExpirationDuringRuntimeStartCompletesPromptlyAndExactlyOnce() async throws {
        // The runtime bring-up await is non-cancellable in production (the
        // runtime's serial lifecycle queue); the gate reproduces that.
        let gate = ManualGate()
        makeCoordinator(syncDoneImmediately: true, runtimeStartOverride: { _ in await gate.wait() })
        coordinator.start()
        let handler = try XCTUnwrap(scheduler.launchHandlers[BackgroundRefreshCoordinator.taskIdentifier])
        let task = FakeBackgroundRefreshTask()
        let completed = expectation(description: "task completed")
        task.onSetTaskCompleted = { _ in completed.fulfill() }
        let startBlocked = expectation(description: "run parked on runtimeStart")
        gate.onWait = { startBlocked.fulfill() }

        handler(task)
        await fulfillment(of: [startBlocked], timeout: 5)

        // Only the expiration path can complete promptly now.
        let expiration = try XCTUnwrap(task.expirationHandler)
        expiration()

        await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(task.completions, [false])
        // The run body is still parked: no teardown yet.
        XCTAssertEqual(runtimeStopCalls, 0)

        // The next request was already submitted before the startup await,
        // so an expiry here does not end the chain.
        XCTAssertEqual(scheduler.submissions.count, 1)

        // Unblock the startup: the run body finishes without a second
        // completion of the already-completed task, and without a teardown
        // in time the system no longer grants.
        let bodyEnded = submissionsReach(2)
        gate.resolve(true)

        await fulfillment(of: [bodyEnded], timeout: 5)
        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(runtimeStopCalls, 0)
        XCTAssertFalse(coordinator.stoppedRuntimeAfterBackgroundRun)
        XCTAssertEqual(sweepCalls, 0)
    }

    /// Expiration before the run body has had a chance to start: the task
    /// is already handed back, so the body must not open a runtime bring-up
    /// in a process the system is about to suspend. The chain still gets its
    /// next request, which the body submits before anything else.
    func testExpirationBeforeTheBodyRunsNeverStartsTheRuntime() async throws {
        makeCoordinator(syncDoneImmediately: true)
        coordinator.start()
        let handler = try XCTUnwrap(scheduler.launchHandlers[BackgroundRefreshCoordinator.taskIdentifier])
        let task = FakeBackgroundRefreshTask()
        let completed = expectation(description: "task completed")
        task.onSetTaskCompleted = { _ in completed.fulfill() }
        // The body runs to its guard without suspending, so the run's single
        // submission marks that it has already returned.
        let bodyEnded = submissionsReach(1)

        handler(task)
        // Still on the main actor: the run task has not been given a chance
        // to execute between the handler returning and this expiry.
        try XCTUnwrap(task.expirationHandler)()

        await fulfillment(of: [completed, bodyEnded], timeout: 5)
        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(runtimeStartCalls, 0)
        XCTAssertEqual(runtimeStopCalls, 0)
        XCTAssertEqual(sweepCalls, 0)
        XCTAssertFalse(coordinator.stoppedRuntimeAfterBackgroundRun)
        XCTAssertEqual(scheduler.submissions.count, 1)
    }

    /// Expiration while the bring-up waits its turn on the runtime's serial
    /// lifecycle queue. Cancelling the run does not reach that queue, so the
    /// coordinator hands the bring-up an explicit "still wanted" gate, read
    /// on the queue immediately before the rebuild would begin.
    func testExpirationWhileTheRebuildIsQueuedWithdrawsIt() async throws {
        let gate = ManualGate()
        makeCoordinator(syncDoneImmediately: true, runtimeStartOverride: { _ in await gate.wait() })
        coordinator.start()
        let handler = try XCTUnwrap(scheduler.launchHandlers[BackgroundRefreshCoordinator.taskIdentifier])
        let task = FakeBackgroundRefreshTask()
        let completed = expectation(description: "task completed")
        task.onSetTaskCompleted = { _ in completed.fulfill() }
        let startBlocked = expectation(description: "run parked on runtimeStart")
        gate.onWait = { startBlocked.fulfill() }

        handler(task)
        await fulfillment(of: [startBlocked], timeout: 5)
        let isWanted = try XCTUnwrap(isRuntimeStartWanted)
        XCTAssertTrue(isWanted(), "a live run still wants its bring-up")

        try XCTUnwrap(task.expirationHandler)()
        await fulfillment(of: [completed], timeout: 5)

        XCTAssertFalse(isWanted(), "an expired run withdraws the queued bring-up")

        // And the parked body still unwinds without a second completion or a
        // teardown in time the system no longer grants.
        let bodyEnded = submissionsReach(2)
        gate.resolve(true)
        await fulfillment(of: [bodyEnded], timeout: 5)
        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(runtimeStopCalls, 0)
        XCTAssertEqual(sweepCalls, 0)
    }

    // MARK: Task run — no wallet

    func testNoWalletRunCompletesWithoutTouchingRuntime() async throws {
        makeCoordinator(syncDoneImmediately: true)
        walletExists = false

        let task = try await runTask()

        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(runtimeStartCalls, 0)
        XCTAssertEqual(runtimeStopCalls, 0)
        XCTAssertEqual(sweepCalls, 0)
        XCTAssertTrue(scheduler.submissions.isEmpty)
    }

    // MARK: Paused in this build

    /// Paused: the handler is still registered — a request submitted by an
    /// earlier build can launch this one, and a permitted identifier without
    /// a handler is a crash — and the pending request is withdrawn.
    func testPausedStartStillRegistersAndWithdrawsThePendingRequest() {
        makeCoordinator(isEnabled: false)

        coordinator.start()
        coordinator.start()

        XCTAssertEqual(scheduler.registeredIdentifiers, [BackgroundRefreshCoordinator.taskIdentifier])
        XCTAssertEqual(scheduler.cancelledIdentifiers, [BackgroundRefreshCoordinator.taskIdentifier])
    }

    func testPausedBackgroundingSubmitsNothingEvenWithAWalletOrALockedDevice() {
        makeCoordinator(isEnabled: false)
        coordinator.start()

        coordinator.noteDidEnterBackground()
        protectedDataAvailable = false
        coordinator.noteDidEnterBackground()

        XCTAssertTrue(scheduler.submissions.isEmpty)
    }

    /// A task delivered anyway (an earlier build's request that outran the
    /// cancel) completes at once: no runtime, no sync, no next request.
    func testPausedDeliveredTaskCompletesWithoutRuntimeOrSubmission() async throws {
        makeCoordinator(isEnabled: false)

        let task = try await runTask()

        XCTAssertEqual(task.completions, [true])
        XCTAssertEqual(runtimeStartCalls, 0)
        XCTAssertEqual(runtimeStopCalls, 0)
        XCTAssertEqual(sweepCalls, 0)
        XCTAssertTrue(scheduler.submissions.isEmpty)
    }
}

// MARK: - SyncCatchUpPolicy

/// The production rule `defaultSyncDoneWait` applies. The coordinator's own
/// tests drive the wait through an injected seam, so without these the rule
/// that decides whether a refresh hands its window back unused is untested.
final class SyncCatchUpPolicyTests: XCTestCase {
    func testAColdStartReturnsAsSoonAsSyncCompletes() {
        // The monitor was not done when the wait began, so the `.syncDone` now
        // on offer can only have been produced during this refresh.
        XCTAssertTrue(SyncCatchUpPolicy.completionIsFresh(
            startedDone: false, leftDone: false, tipHeight: 100, tipAtStart: 100))
    }

    func testAWarmResumeDoesNotAcceptThePreviousSessionsCompletion() {
        // A process resumed from suspension: the monitor still holds the
        // `.syncDone` it reached before backgrounding, and nothing new has
        // arrived. Returning here completes the BGTask immediately and gives
        // back the execution time the catch-up exists to use.
        XCTAssertFalse(SyncCatchUpPolicy.completionIsFresh(
            startedDone: true, leftDone: false, tipHeight: 100, tipAtStart: 100))
    }

    func testAWarmResumeAcceptsCompletionOnceTheTipAdvances() {
        // Progress arriving later is the proof the run is live, for a resume
        // where the chain moves without the monitor ever leaving `.syncDone`.
        XCTAssertTrue(SyncCatchUpPolicy.completionIsFresh(
            startedDone: true, leftDone: false, tipHeight: 101, tipAtStart: 100))
    }

    func testAWarmResumeAcceptsCompletionAfterAFreshSyncCycle() {
        // The monitor left `.syncDone` and came back, so this reading belongs
        // to a cycle inside this refresh.
        XCTAssertTrue(SyncCatchUpPolicy.completionIsFresh(
            startedDone: true, leftDone: true, tipHeight: 100, tipAtStart: 100))
    }
}
