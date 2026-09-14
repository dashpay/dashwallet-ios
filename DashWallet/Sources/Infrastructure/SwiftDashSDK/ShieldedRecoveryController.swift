import Combine
import Foundation

/// Coalesces lifecycle recovery and forced passes. The injected operations
/// resolve the current runtime when called; this controller retains no SDK
/// handles. Preparation is admitted only when the owning Core runtime is ready.
@MainActor
final class ShieldedRecoveryController: ObservableObject {
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void

    @Published private(set) var lastError: String?
    private(set) var isActive = false
    private(set) var isOnline = false
    private var isForeground = true
    private var isSuspended = false
    private(set) var generation: UInt64 = 0
    private var operation: Task<Void, Never>?
    var isRecovering: Bool { operation != nil }
    private var debounce: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var retryAttempt = 0
    private var pendingSync = false
    private let canPrepare: @MainActor () -> Bool
    private let prepare: @MainActor () async throws -> Void
    private let sync: @MainActor () async throws -> Void
    private let isSyncing: @MainActor () -> Bool
    private let shouldRefreshOnForeground: @MainActor () -> Bool
    private let sleep: Sleep

    init(
        prepare: @escaping @MainActor () async throws -> Void,
        sync: @escaping @MainActor () async throws -> Void,
        isSyncing: @escaping @MainActor () -> Bool,
        canPrepare: @escaping @MainActor () -> Bool = { true },
        shouldRefreshOnForeground: @escaping @MainActor () -> Bool = { true },
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.canPrepare = canPrepare
        self.prepare = prepare
        self.sync = sync
        self.isSyncing = isSyncing
        self.shouldRefreshOnForeground = shouldRefreshOnForeground
        self.sleep = sleep
    }

    func start(isForeground: Bool) {
        guard !isActive || isSuspended else { return }
        isActive = true
        isSuspended = false
        self.isForeground = isForeground
        request(forceSync: false)
    }

    func connectivityChanged(isOnline: Bool) {
        let cameOnline = !self.isOnline && isOnline
        self.isOnline = isOnline
        if !isOnline {
            debounce?.cancel()
            debounce = nil
            return
        }
        guard isActive, cameOnline else { return }
        if isSuspended {
            pendingSync = true
            return
        }
        let expectedGeneration = generation
        debounce?.cancel()
        debounce = Task { [weak self] in
            guard let self else { return }
            do { try await self.sleep(0.5) } catch { return }
            guard !Task.isCancelled, self.generation == expectedGeneration else { return }
            self.debounce = nil
            self.request()
        }
    }

    func foregroundChanged(isForeground: Bool) {
        self.isForeground = isForeground
        if isForeground {
            request(forceSync: shouldRefreshOnForeground())
        } else {
            debounce?.cancel()
            debounce = nil
            retry?.cancel()
            retry = nil
        }
    }

    /// A manual network action must not acknowledge an offline no-op. Local
    /// preparation and reconnect recovery continue to use request directly.
    @discardableResult
    func requestManualSync() -> Bool {
        guard isActive, !isSuspended, isOnline, isForeground, canPrepare() else { return false }
        request()
        return true
    }

    func request(forceSync: Bool = true) {
        guard isActive, !isSuspended, isForeground, canPrepare() else { return }
        pendingSync = pendingSync || forceSync
        guard operation == nil else { return }
        retry?.cancel()
        retry = nil
        let expectedGeneration = generation
        operation = Task { [weak self] in
            guard let self, !Task.isCancelled, self.generation == expectedGeneration else { return }
            guard self.isForeground, self.canPrepare() else {
                self.abandonOperation(generation: expectedGeneration)
                return
            }
            do {
                try await self.prepare()
            } catch is CancellationError {
                self.abandonOperation(generation: expectedGeneration)
                return
            } catch {
                guard !Task.isCancelled, self.generation == expectedGeneration else { return }
                self.lastError = error.localizedDescription
                self.operation = nil
                self.scheduleInitializationRetry()
                return
            }
            guard !Task.isCancelled, self.generation == expectedGeneration else { return }
            self.retryAttempt = 0
            self.lastError = nil

            // Requests arriving during preparation are consumed by this pass.
            // Requests arriving during a pass leave at most one follow-up.
            while self.pendingSync && self.isOnline && self.isForeground && !self.isSyncing() {
                self.pendingSync = false
                do {
                    try await self.sync()
                    guard !Task.isCancelled, self.generation == expectedGeneration else { return }
                    self.lastError = nil
                } catch is CancellationError {
                    self.abandonOperation(generation: expectedGeneration)
                    return
                } catch {
                    guard !Task.isCancelled, self.generation == expectedGeneration else { return }
                    self.lastError = error.localizedDescription
                    // A failure alone does not enqueue a retry. Drain only
                    // an explicit request that arrived while this pass ran;
                    // otherwise the SDK's regular polling cadence takes over.
                }
                guard !Task.isCancelled, self.generation == expectedGeneration else { return }
            }
            self.operation = nil
        }
    }

    /// Called on the SDK's falling syncing edge. Reconnect while another pass
    /// was running leaves pendingSync set until that pass gives up the engine.
    func syncDidFinish() {
        guard pendingSync, isOnline, isForeground, !isSyncing() else { return }
        request()
    }

    /// Also guards work waiting on the runtime's separate lifecycle queue.
    func isCurrentSession(_ expectedGeneration: UInt64) -> Bool {
        isActive && !isSuspended && generation == expectedGeneration
    }

    /// Keep lifecycle observation and retry intent, but abandon work tied to
    /// the old runtime. Do not await operation: preparation may itself be
    /// waiting on the lifecycle queue that is performing this restart. Native
    /// operations are stopped/drained by the coordinator and SDK shutdown.
    func suspendForRuntimeRestart() {
        guard isActive else { return }
        generation &+= 1
        isSuspended = true
        pendingSync = pendingSync || operation != nil
        cancelTasks()
    }

    func stop() {
        generation &+= 1
        isActive = false
        isSuspended = false
        isOnline = false
        pendingSync = false
        retryAttempt = 0
        cancelTasks()
        lastError = nil
    }

    private func cancelTasks() {
        operation?.cancel()
        operation = nil
        debounce?.cancel()
        debounce = nil
        retry?.cancel()
        retry = nil
    }

    /// Scope changes deliberately abandon work without cancelling its Task.
    /// Do not surface those as errors or retry the obsolete wallet's pass.
    private func abandonOperation(generation expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        operation = nil
        pendingSync = false
        retryAttempt = 0
        lastError = nil
    }

    private func scheduleInitializationRetry() {
        guard isActive, !isSuspended, isForeground else { return }
        let delays: [TimeInterval] = [1, 2, 4, 8, 16, 30]
        let delay = delays[min(retryAttempt, delays.count - 1)]
        retryAttempt = min(retryAttempt + 1, delays.count - 1)
        let expectedGeneration = generation
        retry = Task { [weak self] in
            guard let self else { return }
            do { try await self.sleep(delay) } catch { return }
            guard !Task.isCancelled, self.generation == expectedGeneration else { return }
            self.retry = nil
            self.request(forceSync: false)
        }
    }
}
