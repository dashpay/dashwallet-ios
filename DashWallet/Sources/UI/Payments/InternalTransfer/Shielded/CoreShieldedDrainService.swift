import Foundation
import SwiftDashSDK

/// Confirmation carries intent and an immutable estimate, never a rounded fiat
/// amount to be used as the amount of a whole-wallet spend.
struct CoreShieldedDrainConfirmation: Equatable {
    let context: CoreShieldedDrainContext
    let candidateBalanceDuffs: UInt64
    let estimatedRecipientCredits: UInt64?
    let estimatedL1FeeDuffs: UInt64?
    let poolFeeCredits: UInt64

    var totalFeeCredits: UInt64? {
        guard let estimatedL1FeeDuffs else { return nil }
        let l1 = estimatedL1FeeDuffs.multipliedReportingOverflow(by: 1000)
        let total = l1.partialValue.addingReportingOverflow(poolFeeCredits)
        return l1.overflow || total.overflow ? nil : total.partialValue
    }
}

@MainActor
struct CoreShieldedDrainService {
    // Process-wide because separate screens share the same operation file.
    // Covers the interval before the SDK worker has registered its context;
    // after restart the SDK's durable-before-dispatch gate resolves absence.
    private static var activeOperations: Set<UUID> = []
    let store: any CoreShieldedDrainStoring
    init(store: any CoreShieldedDrainStoring = CoreShieldedDrainFileStore()) { self.store = store }

    static func currentContext() throws -> CoreShieldedDrainContext {
        guard WalletLifecycleTransitionState.shared.phase == .idle,
              let wallet = SwiftDashSDKHost.shared.wallet,
              let network = SwiftDashSDKHost.shared.runningNetwork,
              network == WalletEnvironment.network else { throw ServiceError.unavailable }
        return CoreShieldedDrainContext(walletId: wallet.walletId, networkScope: network.persistenceScope)
    }

    func manager(for context: CoreShieldedDrainContext) throws -> PlatformWalletManager {
        guard try Self.currentContext() == context,
              let manager = SwiftDashSDKHost.shared.manager else { throw ServiceError.contextChanged }
        return manager
    }

    /// The SDK can reconcile a recorded transfer against verified scan data.
    /// Status lookup never creates a lock or broadcasts a transaction.
    /// Preserve terminal evidence for recovery callers even after clearing the
    /// marker: an authenticated completion must not remain an unresolved toast.
    func status(for operation: CoreShieldedDrainOperation) async throws -> WalletDrainOutcome {
        let context = operation.context
        if Self.activeOperations.contains(operation.id) {
            return WalletDrainOutcome(state: .pending, outpoint: nil, error: nil)
        }
        let manager = try manager(for: context)
        let result = try await manager.shieldedWalletDrainStatus(walletId: context.walletId, operationId: operation.id)
        _ = try self.manager(for: context)
        if result.state != .pending { try store.remove(operation) }
        if result.state == .completed {
            await ShieldedTxLookup.shared.refresh(reason: "wallet-drain-reconciled")
            _ = try self.manager(for: context)
            NotificationCenter.default.post(name: .swiftDashSDKTransactionProjectionDidChange, object: nil)
        }
        return result
    }

    func pending(_ context: CoreShieldedDrainContext) async throws -> WalletDrainOutcome? {
        guard let status = try await operationStatus(context), status.outcome.state == .pending else { return nil }
        return status.outcome
    }

    /// Recovery retains this exact UUID across authorization, even if another
    /// status reader clears the completed marker while the PIN prompt is open.
    /// A verified terminal result is returned too: checking status can itself
    /// complete recovery, before any authorization or rebroadcast is needed.
    func operationStatus(_ context: CoreShieldedDrainContext) async throws
        -> (operation: CoreShieldedDrainOperation, outcome: WalletDrainOutcome)? {
        guard let operation = try store.load(context) else { return nil }
        let outcome = try await status(for: operation)
        return (operation, outcome)
    }

    func prepare(_ context: CoreShieldedDrainContext) throws -> CoreShieldedDrainOperation {
        _ = try manager(for: context)
        guard try store.load(context) == nil else { throw CoreShieldedDrainFileStore.StoreError.pendingOperation }
        let operation = CoreShieldedDrainOperation(id: UUID(), context: context)
        try store.save(operation)
        Self.activeOperations.insert(operation.id)
        return operation
    }

    func settle(_ operation: CoreShieldedDrainOperation, outcome: WalletDrainOutcome) throws {
        defer { Self.activeOperations.remove(operation.id) }
        if outcome.state != .pending { try store.remove(operation) }
    }

    enum ServiceError: LocalizedError {
        case unavailable, contextChanged, requiresSync
        var errorDescription: String? {
            switch self {
            case .unavailable: return NSLocalizedString("Wallet unavailable. Try again.", comment: "Core drain")
            case .contextChanged: return NSLocalizedString("The wallet or network changed. Select Max again.", comment: "Core drain")
            case .requiresSync: return NSLocalizedString("Wait until the chain is fully synced to make transfers", comment: "Core drain")
            }
        }
    }
}
