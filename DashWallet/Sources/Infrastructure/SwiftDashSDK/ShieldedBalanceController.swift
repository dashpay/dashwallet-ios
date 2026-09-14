import Combine
import Foundation

/// A locally restored amount has the same reservation-aware semantics as a
/// refreshed amount, but does not claim that the current chain tip was read.
public enum ShieldedBalanceState: Equatable, Sendable {
    case unavailable
    case restored(UInt64)
    case refreshed(UInt64)

    public var credits: UInt64? {
        switch self {
        case .unavailable: return nil
        case .restored(let credits), .refreshed(let credits): return credits
        }
    }

    public var isAvailable: Bool { credits != nil }

    var cached: Self {
        credits.map(Self.restored) ?? .unavailable
    }
}

/// Owns the display snapshot across manager retries. Loading is injected so
/// ordering, cancellation and wallet isolation can be tested without the FFI.
@MainActor
final class ShieldedBalanceController: ObservableObject {
    struct Scope: Equatable {
        let walletId: Data
        let network: String
    }

    @Published private(set) var state: ShieldedBalanceState = .unavailable
    @Published private(set) var lastError: String?
    @Published private(set) var syncStartError: String?
    private(set) var isPrepared = false
    /// Native binding can succeed even when a local balance read times out.
    private(set) var isBound = false
    private var scope: Scope?
    private var owner: ObjectIdentifier?
    private var generation: UInt64 = 0
    private var revision: UInt64 = 0
    private var restoration: Task<Void, Never>?

    func restore(
        scope nextScope: Scope,
        owner nextOwner: ObjectIdentifier,
        bind: @escaping @MainActor () throws -> Void = {},
        load: @escaping @MainActor () async throws -> ShieldedBalanceState
    ) async {
        if scope == nextScope, owner == nextOwner {
            if let restoration {
                await restoration.value
                return
            }
            if isPrepared { return }
        } else {
            detach()
            if scope != nextScope {
                state = .unavailable
                lastError = nil
            }
            scope = nextScope
            owner = nextOwner
        }

        generation &+= 1
        let expectedGeneration = generation
        let expectedRevision = revision
        let task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                guard let self, self.generation == expectedGeneration else { return }
                if !self.isBound {
                    try bind()
                    self.isBound = true
                }
                let loaded = try await load()
                guard !Task.isCancelled,
                      self.generation == expectedGeneration else { return }
                self.isPrepared = true
                self.lastError = nil
                // A sync result delivered during the disk read is newer.
                if self.revision == expectedRevision { self.state = loaded }
            } catch is CancellationError {
                // Detach invalidates this read; the destination owns display.
            } catch {
                guard let self, !Task.isCancelled,
                      self.generation == expectedGeneration else { return }
                self.lastError = error.localizedDescription
            }
        }
        restoration = task
        await task.value
        if generation == expectedGeneration { restoration = nil }
    }

    /// The app can deliver two successful binds during launch. Retry only the
    /// snapshot read when its delivery crossed a bind, before starting SPV;
    /// configuration and binding themselves must not be repeated here.
    static func readLocalSnapshot<Value>(
        load: @MainActor () async throws -> Value,
        isBindingChange: (Error) -> Bool
    ) async throws -> Value {
        var remainingBindRetries = 2
        while true {
            try Task.checkCancellation()
            do {
                return try await load()
            } catch {
                try Task.checkCancellation()
                guard !(error is CancellationError), remainingBindRetries > 0,
                      isBindingChange(error) else { throw error }
                remainingBindRetries -= 1
            }
        }
    }

    func accept(credits: UInt64) {
        revision &+= 1
        state = .refreshed(credits)
    }

    func recordSyncStartFailure(_ message: String) {
        syncStartError = message
    }

    func recordSyncStarted() {
        syncStartError = nil
    }

    func markStale() {
        state = state.cached
    }

    /// A manager retry preserves the selected wallet's amount and failure reason.
    func detach() {
        generation &+= 1
        restoration?.cancel()
        restoration = nil
        owner = nil
        isPrepared = false
        isBound = false
        syncStartError = nil
        markStale()
    }

    func invalidateUnless(scope selectedScope: Scope?) {
        if scope != selectedScope { clear() }
    }

    func clear() {
        detach()
        scope = nil
        lastError = nil
        state = .unavailable
    }
}
