import Combine
import Foundation

/// Coalesces lifecycle recovery and forced passes. The injected operations
/// resolve the current runtime when called; this controller retains no SDK
/// handles and can also recover a runtime that failed before manager creation.
@MainActor
final class ShieldedRecoveryController: ObservableObject {
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void

    @Published private(set) var lastError: String?
    private(set) var isActive = false
    private(set) var isOnline = false
    private var isForeground = true
    private(set) var generation: UInt64 = 0
    private var operation: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var retryAttempt = 0
    private var pendingSync = false
    private let prepare: @MainActor () async throws -> Void
    private let sync: @MainActor () async throws -> Void
    private let isSyncing: @MainActor () -> Bool
    private let sleep: Sleep

    init(
        prepare: @escaping @MainActor () async throws -> Void,
        sync: @escaping @MainActor () async throws -> Void,
        isSyncing: @escaping @MainActor () -> Bool,
        sleep: @escaping Sleep = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.prepare = prepare
        self.sync = sync
        self.isSyncing = isSyncing
        self.sleep = sleep
    }

    func start(isForeground: Bool) {
        guard !isActive else { return }
        isActive = true
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
            request()
        } else {
            retry?.cancel()
            retry = nil
        }
    }

    func request(forceSync: Bool = true) {
        guard isActive else { return }
        pendingSync = pendingSync || forceSync
        guard operation == nil else { return }
        retry?.cancel()
        retry = nil
        let expectedGeneration = generation
        operation = Task { [weak self] in
            guard let self, !Task.isCancelled, self.generation == expectedGeneration else { return }
            do {
                try await self.prepare()
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
        isActive && generation == expectedGeneration
    }

    func stop() {
        generation &+= 1
        isActive = false
        isOnline = false
        pendingSync = false
        retryAttempt = 0
        operation?.cancel()
        operation = nil
        debounce?.cancel()
        debounce = nil
        retry?.cancel()
        retry = nil
        lastError = nil
    }

    private func scheduleInitializationRetry() {
        guard isActive, isForeground else { return }
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
