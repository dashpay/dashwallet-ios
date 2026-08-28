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

import BackgroundTasks
import Foundation
import UIKit

// MARK: - BackgroundRefreshTaskHandle

/// The slice of `BGTask` the coordinator touches. `BGTask` has no public
/// initializer, so the run logic is written against this seam and tests
/// drive it with a fake — the same structural-trampoline shape
/// `NotificationLifecycle` uses for the unconstructible `UNNotification`.
protocol BackgroundRefreshTaskHandle: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: BackgroundRefreshTaskHandle {}

// MARK: - BackgroundTaskScheduling

/// Seam over `BGTaskScheduler`: registration and request submission are the
/// only calls the coordinator makes, and both are recorded by a fake in
/// tests (the real scheduler refuses double registration and rejects
/// submissions outside a real app process).
protocol BackgroundTaskScheduling: AnyObject {
    /// Register `launchHandler` for `identifier`. Returns whether the
    /// registration was accepted.
    func register(identifier: String, launchHandler: @escaping (BackgroundRefreshTaskHandle) -> Void) -> Bool
    /// Submit an app-refresh request for `identifier`, to run no earlier
    /// than `earliestBeginDate`.
    func submit(identifier: String, earliestBeginDate: Date?) throws
}

/// Production scheduler over `BGTaskScheduler.shared`.
final class SystemBackgroundTaskScheduler: BackgroundTaskScheduling {
    func register(identifier: String, launchHandler: @escaping (BackgroundRefreshTaskHandle) -> Void) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            launchHandler(task)
        }
    }

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }
}

// MARK: - BackgroundRefreshCoordinator

/// Owns the `BGAppRefreshTask` that runs a bounded sync while the app is
/// backgrounded, so incoming-transaction rows land and the notification
/// producers (which observe the persistence signals on their own) can post.
///
/// iOS runs app-refresh tasks opportunistically — minutes to hours after the
/// earliest-begin date, and rarely for seldom-opened apps. This converts
/// "notifications never arrive while the app is closed" into "they arrive
/// late", nothing stronger.
///
/// Task body: ensure the SDK runtime is up through the same serialized
/// lifecycle a normal launch uses (`SwiftDashSDKWalletRuntime` — never a
/// parallel bring-up; in a background launch, `didFinishLaunching`'s own
/// `startIfReady` has usually brought it up already and the ensure elides),
/// wait for `SyncingActivityMonitor` to reach `.syncDone` within a wall-clock
/// deadline, run one transaction-producer sweep so rows first seen during
/// this sync are posted before teardown, then stop the runtime — but only
/// when this process was launched into the background for the task. A
/// process the user foregrounded keeps its live runtime, exactly as if no
/// task had run.
@MainActor
final class BackgroundRefreshCoordinator {
    /// Must match the `BGTaskSchedulerPermittedIdentifiers` entry in both
    /// app Info.plists (`DashWallet/Info.plist`, `DashPay/dashpay-info.plist`).
    nonisolated static let taskIdentifier = "org.dashfoundation.dashpay.refresh"

    /// Earliest-begin distance for a submitted request. iOS treats it as a
    /// floor, not a schedule.
    nonisolated static let earliestBeginInterval: TimeInterval = 15 * 60

    /// Wall-clock budget for the sync wait, inside the ~30 s the system
    /// grants the task. The margin covers the runtime teardown and the
    /// producer sweep.
    nonisolated static let syncDeadline: TimeInterval = 20

    private let scheduler: BackgroundTaskScheduling
    private let hasWallet: () -> Bool
    /// Ensure the runtime is up via the serialized lifecycle; returns
    /// whether it is ready afterwards.
    private let runtimeStart: () async -> Bool
    /// Awaitable full teardown (persistence flushed on return).
    private let runtimeStop: () async -> Void
    /// Fire-and-forget restart, used when the user foregrounds a process
    /// whose runtime a background run stopped.
    private let runtimeRearm: () -> Void
    /// Suspends until `SyncingActivityMonitor` reads `.syncDone`; must
    /// return promptly when the surrounding task is cancelled.
    private let waitForSyncDone: () async -> Void
    /// One transaction-producer scan, awaited after `.syncDone` so rows the
    /// producer's sync gate dropped mid-sync are posted before teardown.
    private let postSyncProducerSweep: () async -> Void
    /// Cancellable sleep; the deadline clock.
    private let sleep: (TimeInterval) async -> Void
    private let now: () -> Date

    private var started = false
    /// True once this process has been frontmost. While false, a task run
    /// treats the runtime as its own background-launch responsibility and
    /// tears it down before completing.
    private(set) var hasBeenActive = false
    /// Set when a background run stopped the runtime; the next
    /// become-active restarts it. Nothing else restarts it automatically —
    /// `startIfReady` otherwise runs only in `didFinishLaunching` (which a
    /// resumed process skips) and behind the sync view's manual retry.
    private(set) var stoppedRuntimeAfterBackgroundRun = false
    private var observers: [NSObjectProtocol] = []

    init(scheduler: BackgroundTaskScheduling = SystemBackgroundTaskScheduler(),
         hasWallet: @escaping () -> Bool = { WalletEnvironment.hasWallet },
         runtimeStart: @escaping () async -> Bool = BackgroundRefreshCoordinator.defaultRuntimeStart,
         runtimeStop: @escaping () async -> Void = { await SwiftDashSDKWalletRuntime.shared.stopAndAwaitTeardown() },
         runtimeRearm: @escaping () -> Void = { SwiftDashSDKWalletRuntime.startIfReady() },
         waitForSyncDone: @escaping () async -> Void = BackgroundRefreshCoordinator.defaultSyncDoneWait,
         postSyncProducerSweep: @escaping () async -> Void,
         sleep: @escaping (TimeInterval) async -> Void = BackgroundRefreshCoordinator.defaultSleep,
         now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.hasWallet = hasWallet
        self.runtimeStart = runtimeStart
        self.runtimeStop = runtimeStop
        self.runtimeRearm = runtimeRearm
        self.waitForSyncDone = waitForSyncDone
        self.postSyncProducerSweep = postSyncProducerSweep
        self.sleep = sleep
        self.now = now
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Wiring

    /// Registers the launch handler and installs the app-lifecycle
    /// observers. Idempotent; called once by `NotificationsBootstrap`
    /// during `application(_:didFinishLaunching:)` — `BGTaskScheduler`
    /// requires registration before the launch method returns.
    func start() {
        guard !started else { return }
        started = true

        let registered = scheduler.register(identifier: Self.taskIdentifier) { [weak self] task in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleRefreshTask(task)
        }
        if !registered {
            DWLogger.log("BackgroundRefreshCoordinator: BGTask registration refused for \(Self.taskIdentifier)")
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.noteDidEnterBackground() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.noteDidBecomeActive() }
        })
    }

    // MARK: App-lifecycle handlers (trampolined from the observers above)

    /// Backgrounding: submit the next refresh request. Skipped without a
    /// wallet — there is nothing to sync and nothing to notify about.
    func noteDidEnterBackground() {
        scheduleNextRefresh()
    }

    /// The process is frontmost: task runs from here on must leave the
    /// runtime alone, and a runtime an earlier background run stopped is
    /// restarted through the same entry point launch uses.
    func noteDidBecomeActive() {
        hasBeenActive = true
        if stoppedRuntimeAfterBackgroundRun {
            stoppedRuntimeAfterBackgroundRun = false
            runtimeRearm()
        }
    }

    /// Submit a request to run no earlier than ~15 minutes from now. iOS
    /// may run it much later or not at all; each run re-submits.
    func scheduleNextRefresh() {
        guard hasWallet() else { return }
        do {
            try scheduler.submit(identifier: Self.taskIdentifier,
                                 earliestBeginDate: now().addingTimeInterval(Self.earliestBeginInterval))
        } catch {
            // Expected on simulators and when the OS has disabled
            // background refresh for the app; nothing to recover.
            DWLogger.log("BackgroundRefreshCoordinator: submit failed: \(error)")
        }
    }

    // MARK: Task run

    /// Launch-handler entry. Nonisolated so the expiration handler is
    /// assigned synchronously on the scheduler's queue; the run body is a
    /// cancellable main-actor task the handler cancels.
    nonisolated func handleRefreshTask(_ task: BackgroundRefreshTaskHandle) {
        let run = Task { @MainActor in
            await self.run(task)
        }
        task.expirationHandler = { run.cancel() }
    }

    /// The bounded background sync. Completes the task on every path;
    /// `success` means the sync reached `.syncDone` within the deadline and
    /// the post-sync producer sweep ran — a run that hit the deadline (or
    /// was expired, or had no wallet, or whose runtime failed to start)
    /// completes with `success: false`, because no notification work was
    /// finished. Rows a failed run did persist are not lost: the producer's
    /// store and freshness window admit them on the next open or run.
    private func run(_ task: BackgroundRefreshTaskHandle) async {
        guard hasWallet() else {
            task.setTaskCompleted(success: false)
            return
        }

        let ready = await runtimeStart()
        var success = false
        if ready, await syncDoneWithinDeadline() {
            await postSyncProducerSweep()
            success = true
        }

        // `hasBeenActive` is read here, not captured at run start: if the
        // user opened the app mid-run, the runtime now belongs to a live
        // session and stays up.
        if !hasBeenActive {
            await runtimeStop()
            if hasBeenActive {
                // Activated during the teardown await — restart immediately
                // instead of waiting for a become-active that already fired.
                runtimeRearm()
            } else {
                stoppedRuntimeAfterBackgroundRun = true
            }
        }

        scheduleNextRefresh()
        task.setTaskCompleted(success: success)
    }

    /// Race the sync-done wait against the deadline clock. Expiration
    /// cancels the surrounding task; both branches then return promptly and
    /// the result is forced to `false`.
    private func syncDoneWithinDeadline() async -> Bool {
        let wait = waitForSyncDone
        let sleep = self.sleep
        let deadline = Self.syncDeadline
        let synced = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await wait(); return true }
            group.addTask { await sleep(deadline); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        return synced && !Task.isCancelled
    }

    // MARK: Production defaults

    /// Bring-up through the runtime's serial lifecycle chain (the exact
    /// pipeline `didFinishLaunching`'s `startIfReady` feeds; the refresh
    /// elides when the runtime is already ready), then report readiness.
    @MainActor
    static func defaultRuntimeStart() async -> Bool {
        let runtime = SwiftDashSDKWalletRuntime.shared
        await runtime.rearmPlatformSync()
        guard case .success(let network) = runtime.resolveCurrentNetwork() else { return false }
        return runtime.isRuntimeReady(for: network)
    }

    /// Poll `SyncingActivityMonitor` until `.syncDone` (the module's sync
    /// gate — never SPV `state == .synced`). Cancellation exits the loop on
    /// the next tick; the caller's deadline bounds it regardless.
    static func defaultSyncDoneWait() async {
        while SyncingActivityMonitor.shared.state != .syncDone {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
        }
    }

    static func defaultSleep(_ interval: TimeInterval) async {
        guard interval > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}
