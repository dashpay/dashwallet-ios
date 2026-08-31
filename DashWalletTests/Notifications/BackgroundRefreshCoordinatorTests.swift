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
    private var runtimeStartResult = true
    private var runtimeStartCalls = 0
    private var runtimeStopCalls = 0
    private var runtimeRearmCalls = 0
    private var sweepCalls = 0
    private let fixedNow = Date(timeIntervalSince1970: 1_780_000_000)
    private var coordinator: BackgroundRefreshCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        scheduler = FakeBackgroundTaskScheduler()
        walletExists = true
        runtimeStartResult = true
        runtimeStartCalls = 0
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
    /// instant runtime start (the counter still ticks).
    private func makeCoordinator(syncDoneImmediately: Bool = true,
                                 deadlineSleepsForever: Bool = false,
                                 runtimeStartOverride: (() async -> Bool)? = nil) {
        coordinator = BackgroundRefreshCoordinator(
            scheduler: scheduler,
            hasWallet: { [weak self] in self?.walletExists ?? false },
            runtimeStart: { @MainActor [weak self] in
                self?.runtimeStartCalls += 1
                if let runtimeStartOverride {
                    return await runtimeStartOverride()
                }
                return self?.runtimeStartResult ?? false
            },
            runtimeStop: { @MainActor [weak self] in
                self?.runtimeStopCalls += 1
            },
            runtimeRearm: { [weak self] in
                self?.runtimeRearmCalls += 1
            },
            waitForSyncDone: {
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

        // No sync-done inside the deadline means the producers never saw an
        // open sync gate this run — no notification work finished, so the
        // run does not report success. Rows the sync did persist are picked
        // up by the producer's store and freshness rules on the next open.
        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(sweepCalls, 0)
        XCTAssertEqual(runtimeStopCalls, 1)
        XCTAssertEqual(scheduler.submissions.map(\.identifier), [BackgroundRefreshCoordinator.taskIdentifier])
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
        XCTAssertEqual(scheduler.submissions.count, 1)
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
        // unwound; the re-submission marks the run body's end.
        let submitted = expectation(description: "next refresh scheduled")
        scheduler.onSubmit = { _ in submitted.fulfill() }

        handler(task)
        let expiration = try XCTUnwrap(task.expirationHandler)
        expiration()

        await fulfillment(of: [completed, submitted], timeout: 5)
        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(sweepCalls, 0)
        XCTAssertEqual(runtimeStopCalls, 1)
        XCTAssertEqual(scheduler.submissions.count, 1)
    }

    func testExpirationDuringRuntimeStartCompletesPromptlyAndExactlyOnce() async throws {
        // The runtime bring-up await is non-cancellable in production (the
        // runtime's serial lifecycle queue); the gate reproduces that.
        let gate = ManualGate()
        makeCoordinator(syncDoneImmediately: true, runtimeStartOverride: { await gate.wait() })
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

        // Unblock the startup: the run body finishes in the background —
        // the background-launch teardown still runs — without a second
        // completion of the already-completed task.
        let submitted = expectation(description: "next refresh scheduled")
        scheduler.onSubmit = { _ in submitted.fulfill() }
        gate.resolve(true)

        await fulfillment(of: [submitted], timeout: 5)
        XCTAssertEqual(task.completions, [false])
        XCTAssertEqual(runtimeStopCalls, 1)
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
}
