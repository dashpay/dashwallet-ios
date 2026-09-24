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

// MARK: - BackgroundRefreshTaskCompletion

/// One-shot wrapper over a task's `setTaskCompleted`: the run body and the
/// expiration handler can both try to complete, from different threads, and
/// exactly the first call wins. Completing twice is a `BGTask` API violation.
/// `@unchecked Sendable`: the flag is lock-protected and
/// `BGTask.setTaskCompleted` is callable from any thread.
private final class BackgroundRefreshTaskCompletion: @unchecked Sendable {
    private let task: BackgroundRefreshTaskHandle
    private let lock = NSLock()
    private var completed = false

    init(_ task: BackgroundRefreshTaskHandle) {
        self.task = task
    }

    /// Whether the task has already been handed back. The expiration
    /// handler completes it before the run body reaches its own completion
    /// call, so during a run this reads as "the system has taken the window
    /// back" — the one cancellation signal that crosses into the runtime's
    /// serial lifecycle queue, where `Task.isCancelled` belongs to the
    /// queue's own task and not to this run.
    var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    /// Completes the task on the first call; every later call is a no-op.
    func complete(success: Bool) {
        lock.lock()
        let isFirst = !completed
        completed = true
        lock.unlock()
        if isFirst {
            task.setTaskCompleted(success: success)
        }
    }
}

// MARK: - BackgroundRefreshStartGate

/// "Is this run still wanted?", asked from inside the runtime's serial
/// lifecycle queue.
///
/// A nominal type rather than a bare closure parameter: the bring-up stores
/// the question and asks it later, on another queue, so it has to escape —
/// which a closure written directly into a function-type parameter cannot.
struct BackgroundRefreshStartGate {
    let isWanted: @MainActor () -> Bool

    @MainActor
    func callAsFunction() -> Bool { isWanted() }
}

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
    /// Withdraw a pending request for `identifier`, if any.
    func cancel(identifier: String)
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

    func cancel(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}

// MARK: - SyncCatchUpPolicy

/// When a `.syncDone` reading may be treated as belonging to THIS background
/// refresh.
///
/// Extracted from `BackgroundRefreshCoordinator.defaultSyncDoneWait` because
/// that function reads two shared singletons and the coordinator's tests drive
/// the wait through an injected seam — so the production rule, which is the
/// part that decides whether the task hands its execution window back
/// unused, had no coverage of its own.
enum SyncCatchUpPolicy {
    /// - `startedDone`: the monitor already read `.syncDone` when the wait
    ///   began — the warm-resume case, where the value can be the previous
    ///   session's and backgrounding never invalidated it.
    /// - `leftDone`: the monitor has since left `.syncDone`, so the reading
    ///   now on offer was produced by a cycle inside this refresh.
    /// - `tipHeight` / `tipAtStart`: an advancing tip is the other proof that
    ///   this run is live, for a resume where the chain moves without the
    ///   monitor ever leaving `.syncDone`.
    static func completionIsFresh(
        startedDone: Bool,
        leftDone: Bool,
        tipHeight: UInt32,
        tipAtStart: UInt32
    ) -> Bool {
        !startedDone || leftDone || tipHeight > tipAtStart
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
/// when this process was launched into the background for the task and the
/// system has not expired it. A process the user foregrounded keeps its live
/// runtime, exactly as if no task had run.
///
/// The next request is submitted at the start of every run, before any
/// work, and again at its end; a locked device skips the sync but keeps the
/// chain.
@MainActor
final class BackgroundRefreshCoordinator {
    /// Release safety valve. Background refresh is paused in this build
    /// until the locked-launch fix lands: a refresh launches the app while
    /// the device is locked, the mnemonic keychain
    /// (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) then reads as "no
    /// wallet", and the launch path offers Create/Recover over a funded
    /// wallet with the SDK runtime never started. Flip to `true` to
    /// re-enable once that fix has shipped. While paused, registration
    /// stays (see `start`), pending requests are withdrawn, nothing is
    /// submitted, and a delivered task completes without work.
    nonisolated static let isEnabledInThisBuild = false

    /// Production boundary stamp: only for a wallet whose foreground sync
    /// actually finished. Mid-sync the app has not seen everything up to now,
    /// so moving the floor forward would skip whatever the sync had not
    /// reached; leaving it put makes the next completed sweep cover it.
    nonisolated static let defaultMarkForegroundCaughtUp: () -> Void = {
        MainActor.assumeIsolated {
            guard SyncingActivityMonitor.shared.state == .syncDone else { return }
            DWGlobalOptions.sharedInstance().notificationCatchUpDate = Date()
        }
    }

    /// Production protected-data reader. `WalletStorage` keeps the mnemonic —
    /// the only wallet-presence signal (`WalletEnvironment.hasWallet`) — as
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so while the device is
    /// locked that read fails and reports "no wallet". A refresh cannot tell a
    /// locked wallet from a missing one without this.
    nonisolated static let defaultIsProtectedDataAvailable: () -> Bool = {
        MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable }
    }

    /// Must match the `BGTaskSchedulerPermittedIdentifiers` entry in both
    /// app Info.plists (`DashWallet/Info.plist`, `DashPay/dashpay-info.plist`).
    /// Those plists must also keep `fetch` in `UIBackgroundModes`: it is the
    /// capability `BGAppRefreshTask` runs under, and without it every
    /// `submit` fails with `BGTaskSchedulerErrorCodeNotPermitted`.
    nonisolated static let taskIdentifier = "org.dashfoundation.dashpay.refresh"

    /// Earliest-begin distance for a submitted request. iOS treats it as a
    /// floor, not a schedule.
    nonisolated static let earliestBeginInterval: TimeInterval = 15 * 60

    /// Wall-clock budget for the sync wait, inside the ~30 s the system
    /// grants the task. The margin covers the runtime teardown and the
    /// producer sweep.
    nonisolated static let syncDeadline: TimeInterval = 20

    private let scheduler: BackgroundTaskScheduling
    /// `isEnabledInThisBuild`, injected so both modes are testable.
    private let isEnabled: Bool
    /// Records the instant the foreground app stopped watching, as the floor
    /// for the next catch-up sweep. Injected so tests can observe it without
    /// touching user defaults.
    private let markForegroundCaughtUp: () -> Void
    private let hasWallet: () -> Bool
    /// Whether keychain items stored "when unlocked" are readable right now.
    private let isProtectedDataAvailable: () -> Bool
    /// Ensure the runtime is up via the serialized lifecycle; returns
    /// whether it is ready afterwards. The gate is re-read on that queue,
    /// immediately before the rebuild would begin, and a `false` reading
    /// withdraws it — see `run`.
    private let runtimeStart: (BackgroundRefreshStartGate) async -> Bool
    /// Awaitable full teardown (persistence flushed on return).
    private let runtimeStop: () async -> Void
    /// Fire-and-forget restart, used when the user foregrounds a process
    /// whose runtime a background run stopped.
    private let runtimeRearm: () -> Void
    /// Suspends until `SyncingActivityMonitor` reads `.syncDone`; must
    /// return promptly when the surrounding task is cancelled.
    private let waitForSyncDone: () async -> Void
    /// One transaction-producer scan, awaited after `.syncDone` so rows the
    /// sync persisted are posted before the runtime is torn down, rather
    /// than racing teardown on a signal-driven scan's own task.
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
         isEnabled: Bool = BackgroundRefreshCoordinator.isEnabledInThisBuild,
         hasWallet: @escaping () -> Bool = { WalletEnvironment.hasWallet },
         isProtectedDataAvailable: @escaping () -> Bool = BackgroundRefreshCoordinator.defaultIsProtectedDataAvailable,
         runtimeStart: @escaping (BackgroundRefreshStartGate) async -> Bool = BackgroundRefreshCoordinator.defaultRuntimeStart,
         runtimeStop: @escaping () async -> Void = { await SwiftDashSDKWalletRuntime.shared.stopAndAwaitTeardown() },
         runtimeRearm: @escaping () -> Void = { SwiftDashSDKWalletRuntime.startIfReady() },
         waitForSyncDone: @escaping () async -> Void = BackgroundRefreshCoordinator.defaultSyncDoneWait,
         postSyncProducerSweep: @escaping () async -> Void,
         markForegroundCaughtUp: @escaping () -> Void = BackgroundRefreshCoordinator.defaultMarkForegroundCaughtUp,
         sleep: @escaping (TimeInterval) async -> Void = BackgroundRefreshCoordinator.defaultSleep,
         now: @escaping () -> Date = Date.init) {
        self.scheduler = scheduler
        self.isEnabled = isEnabled
        self.markForegroundCaughtUp = markForegroundCaughtUp
        self.hasWallet = hasWallet
        self.isProtectedDataAvailable = isProtectedDataAvailable
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
        // Registration above is unconditional even while paused: a request
        // an earlier build submitted can still launch this one, and
        // `BGTaskScheduler` requires a handler for every permitted
        // identifier at that moment. The handler then only completes the
        // task; here the pending request is withdrawn so it does not.
        if !isEnabled {
            scheduler.cancel(identifier: Self.taskIdentifier)
            DWLogger.log("BackgroundRefreshCoordinator: background refresh is paused in this build; pending request withdrawn, none will be submitted")
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

    /// Backgrounding: submit the next refresh request (skipped only when no
    /// wallet exists — see `scheduleNextRefresh`).
    func noteDidEnterBackground() {
        // Give the catch-up sweep a boundary BEFORE the process suspends.
        //
        // Without one the first background refresh on a fresh or upgraded
        // install falls back to the producer's ten-minute freshness cutoff,
        // and iOS routinely runs that refresh much later than fifteen
        // minutes: a payment mined shortly after suspension is already too
        // old to pass, is dropped, and is then skipped for good when the
        // sweep advances the boundary to now. Stamping the moment the
        // foreground app stopped watching leaves nothing between the two.
        markForegroundCaughtUp()
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
    ///
    /// Skipped only when a wallet is provably absent. On a locked device the
    /// wallet-presence read fails and says "no wallet"; refusing to submit
    /// then ended the refresh chain until the user next opened the app, and
    /// app refreshes run almost exclusively while the device is locked.
    func scheduleNextRefresh() {
        guard isEnabled else { return }
        guard hasWallet() || !isProtectedDataAvailable() else { return }
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
    /// cancellable main-actor task the handler cancels. The handler also
    /// completes the task itself: cancellation unwinds the sync-deadline
    /// race promptly, but the runtime bring-up await runs on the runtime's
    /// non-cancellable serial lifecycle queue — the system must not wait
    /// that out. The shared one-shot completion makes whichever path gets
    /// there first the only one that completes; the run body still finishes
    /// afterwards (teardown included) with its completion call a no-op.
    nonisolated func handleRefreshTask(_ task: BackgroundRefreshTaskHandle) {
        let completion = BackgroundRefreshTaskCompletion(task)
        // Paused: no runtime, no sync, no next request. Completed as a
        // success — nothing failed, and a failure would only count against
        // the app's refresh budget for a task that is not meant to run.
        guard isEnabled else {
            DWLogger.log("BackgroundRefreshCoordinator: background refresh is paused in this build; completing the task without work")
            completion.complete(success: true)
            return
        }
        let run = Task { @MainActor in
            await self.run(completion: completion)
        }
        task.expirationHandler = {
            run.cancel()
            completion.complete(success: false)
        }
    }

    /// The bounded background sync. Completes the task on every path (an
    /// expired task was already completed by the expiration handler; the
    /// call here is then the one-shot's no-op); `success` means the sync
    /// reached `.syncDone` within the deadline and the post-sync producer
    /// sweep ran — a run that hit the deadline (or was expired, or had no
    /// wallet, or whose runtime failed to start) completes with
    /// `success: false`, because no notification work was finished. Rows a
    /// failed run did persist are not lost: the producer's store and
    /// freshness window admit them on the next open or run.
    private func run(completion: BackgroundRefreshTaskCompletion) async {
        // Before any work: a run the system expires, or one that bails out
        // below, must not be the end of the chain. A background-launched
        // process never sees `didEnterBackground`, so this and the tail
        // submission are the only places the next request comes from.
        scheduleNextRefresh()

        // Locked device: the wallet cannot be told apart from an absent one
        // (see `defaultIsProtectedDataAvailable`), so this run syncs nothing
        // and leaves the next request in place for a run after unlock.
        guard isProtectedDataAvailable() else {
            DWLogger.log("BackgroundRefreshCoordinator: protected data unavailable (device locked); skipping sync")
            completion.complete(success: false)
            return
        }
        guard hasWallet() else {
            completion.complete(success: false)
            return
        }

        // Expiration can land before this body reaches its first
        // suspension: `handleRefreshTask` installs the handler on the
        // scheduler's queue while the run task is still hopping to the main
        // actor. Beginning a bring-up then spends time the system has
        // already taken back, in a process it is about to suspend.
        guard !Task.isCancelled else {
            DWLogger.log("BackgroundRefreshCoordinator: expired before startup; skipping the runtime bring-up")
            completion.complete(success: false)
            return
        }

        // The bring-up runs on the runtime's serial lifecycle queue, which
        // cancelling this task does not reach. The gate is what does: it is
        // read on that queue immediately before the rebuild would start, so
        // an expiry that lands while the op waits its turn stops the rebuild
        // from beginning at all. An expiry mid-rebuild cannot stop it — the
        // runtime is then left up, exactly as a suspended foreground process
        // leaves it, for the reason spelled out at the teardown below.
        let ready = await runtimeStart(BackgroundRefreshStartGate { [completion] in !completion.isCompleted })
        var success = false
        // Re-checked here and not only inside `syncDoneWithinDeadline()`:
        // expiration can land between that check and the sweep, and the
        // expiration handler has already completed the task with
        // `success: false` by then. Sweeping after that spends time the
        // system has stopped granting.
        if ready, await syncDoneWithinDeadline(), !Task.isCancelled {
            await postSyncProducerSweep()
            success = true
        }

        // `hasBeenActive` is read here, not captured at run start: if the
        // user opened the app mid-run, the runtime now belongs to a live
        // session and stays up.
        //
        // Not after expiration either. The expiration handler has completed
        // the task by then, so a teardown started now would run its blocking
        // SPV stop in time the system no longer grants — possibly frozen
        // mid-call by suspension, and holding the main actor if the user
        // opens the app during it. The runtime is left as a suspended app
        // leaves it; the next foreground or run finds it up.
        if !hasBeenActive && !Task.isCancelled {
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
        completion.complete(success: success)
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
    /// elides when the runtime is already ready), then report Core readiness.
    ///
    /// Core, not full readiness: payments arrive over SPV, and requiring
    /// BLAST as well meant a Platform outage skipped the sync and the sweep in
    /// every background run although Core had synced.
    ///
    /// `gate` is handed to `rearmPlatformSync(if:)`, which re-reads it on the
    /// lifecycle queue just before the rebuild: a refresh the system has
    /// already expired withdraws its queued bring-up instead of starting SPV
    /// and BLAST in a process about to be suspended.
    @MainActor
    static func defaultRuntimeStart(while gate: BackgroundRefreshStartGate) async -> Bool {
        let runtime = SwiftDashSDKWalletRuntime.shared
        await runtime.rearmPlatformSync {
            gate() && WalletLifecycleTransitionState.shared.allowsAutomaticWalletPreparation
        }
        guard gate() else { return false }
        guard case .success(let network) = runtime.resolveCurrentNetwork() else { return false }
        return runtime.isCoreRuntimeReady(for: network)
    }

    /// Poll `SyncingActivityMonitor` until `.syncDone` (the module's sync
    /// gate — never SPV `state == .synced`), and only for a `.syncDone`
    /// that belongs to THIS refresh.
    ///
    /// A suspended process resumes with the monitor still holding the
    /// previous session's `.syncDone`: backgrounding does not invalidate it,
    /// and `runtimeStart` cannot be relied on to clear it either, because
    /// `SwiftDashSDKWalletRuntime.shouldSkipRefresh` elides the rebuild
    /// while the host, SPV and Platform coordinators are still marked
    /// running. Returning on that cached value completed the task
    /// immediately and handed back the execution window the refresh exists
    /// to use.
    ///
    /// So when the monitor is ALREADY done on entry, this waits for the
    /// runtime to prove it is live in this run — the tip advancing, or a
    /// fresh cycle that ends in `.syncDone` again. Nothing to catch up on is
    /// a legitimate outcome: the caller's deadline bounds the wait and its
    /// expiry is not treated as failure by itself.
    ///
    /// Main-actor isolated, explicitly: `SyncingActivityMonitor.state` fans
    /// out on main and `SwiftDashSDKSPVCoordinator.tipHeight` is `@Published`.
    /// The coordinator's deadline race calls this from a task-group child, and
    /// an async function hops to its own isolation on entry — so every read in
    /// the loop runs on main, and the 250 ms sleep releases it in between. The
    /// annotation keeps that true should the method ever leave this type.
    @MainActor
    static func defaultSyncDoneWait() async {
        let monitor = SyncingActivityMonitor.shared
        let startedDone = monitor.state == .syncDone
        let tipAtStart = SwiftDashSDKSPVCoordinator.shared.tipHeight
        var leftDone = false

        while true {
            if Task.isCancelled { return }
            let state = monitor.state
            if state != .syncDone {
                leftDone = true
            } else if SyncCatchUpPolicy.completionIsFresh(
                startedDone: startedDone,
                leftDone: leftDone,
                tipHeight: SwiftDashSDKSPVCoordinator.shared.tipHeight,
                tipAtStart: tipAtStart) {
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
        }
    }

    static func defaultSleep(_ interval: TimeInterval) async {
        guard interval > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}
