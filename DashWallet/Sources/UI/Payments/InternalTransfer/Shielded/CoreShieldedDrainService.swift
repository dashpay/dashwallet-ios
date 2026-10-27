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

    /// The two fees behind `totalFeeCredits`, for both confirm sheets.
    @MainActor var feeBreakdownText: String {
        let coreFee = estimatedL1FeeDuffs.map { $0.dashAmount.formattedDashAmount } ?? "—"
        let poolFee = InternalTransferSummaryFigures.networkFeeFiat(credits: poolFeeCredits) ?? "—"
        return String(format: NSLocalizedString("Estimated Core fee: %@\nShielded pool fee: %@", comment: "Drain fee breakdown"), coreFee, poolFee)
    }
}

/// How both amount screens draw an active Max selection: an estimate, or the
/// intent while none is known. Digits only — the screens draw the symbol.
@MainActor
enum CoreShieldedDrainDisplay {
    static func dashAmount(estimatedRecipientCredits: UInt64?) -> String {
        guard let credits = estimatedRecipientCredits else {
            return NSLocalizedString("Max", comment: "Whole wallet intent")
        }
        return credits < 1000 ? "<0.00000001" : "≈ " + (credits / 1000).dashAmount.formattedDashAmountWithoutCurrencySymbol
    }

    static func fiatAmount(estimatedRecipientCredits: UInt64?, dashAmount: Decimal, currency: String) -> String {
        guard estimatedRecipientCredits != nil,
              let fiat = try? CurrencyExchanger.shared.convertDash(amount: dashAmount, to: currency)
        else { return "—" }
        return "≈ " + InternalTransferViewModel.formatTyped(fiat, fractionDigits: 2)
    }
}

/// What the app may claim about a drain operation from the SDK's outcome.
/// Every surface that renders a drain result switches on this, not on the
/// SDK enum, so one new case here reaches every screen.
///
/// TODO(drain-unverified-completion): the SDK records `completed` both from a
/// proof-backed consumption and from an unauthenticated "asset lock already
/// consumed" report (dashpay/dashwallet-ios#1230; proof-backed query in
/// dashpay/platform#5580). Once the SDK exposes that distinction, add a
/// `completedUnverified` case mapped from it, and render it as "status
/// unknown" instead of "Transfer complete" in every exhaustive switch.
enum CoreShieldedDrainVerdict: Equatable, Sendable {
    case notSent
    case pending(hasOutpoint: Bool)
    case completed
}

extension WalletDrainOutcome {
    var drainVerdict: CoreShieldedDrainVerdict {
        switch state {
        case .notSent: return .notSent
        case .pending: return .pending(hasOutpoint: outpoint != nil)
        case .completed: return .completed
        }
    }
}

/// What an asset-lock row says about the Max drain that built it
/// (`PersistentAssetLock.operationId`).
enum CoreShieldedDrainRowIdentity: Equatable, Sendable {
    /// No operation id: a lock no drain built.
    case none
    case operation(UUID)
    /// An operation id that is not a UUID: a drain row no marker can match.
    case malformed

    init(operationIdBytes bytes: Data?) {
        guard let bytes, !bytes.isEmpty else { self = .none; return }
        if let id = UUID(drainOperationIdBytes: bytes) { self = .operation(id) } else { self = .malformed }
    }
}

/// The durable marker as one resume attempt found it.
enum CoreShieldedDrainMarkerLookup: Sendable {
    case loaded(CoreShieldedDrainOperation?)
    /// The marker file cannot be a marker for this scope (undecodable, or
    /// another scope's content). Retrying will not change that.
    case corrupt
    /// The wallet or network is not ready, or the read failed in a way a
    /// retry can fix.
    case unavailable
}

/// Where a resume of an existing asset lock must pay. A Max drain's recipient
/// is recorded only in the app's marker: the SDK pays whatever recipient a
/// resume passes, so a drain row is resumed to the marker's recipient or not
/// at all.
enum CoreShieldedDrainResumeTarget: Equatable, Sendable {
    /// The wallet's own default Orchard address.
    case ownWallet
    case external(Data)
    /// A drain row whose recipient cannot be established.
    case refuse
    /// A drain row whose marker could not be read right now.
    case retryLater

    static func resolve(row: CoreShieldedDrainRowIdentity, marker: CoreShieldedDrainMarkerLookup) -> Self {
        switch row {
        case .none:
            return .ownWallet
        case .malformed:
            return .refuse
        case .operation(let rowOperationId):
            switch marker {
            case .unavailable:
                return .retryLater
            case .corrupt:
                return .refuse
            case .loaded(let operation):
                guard let operation, operation.id == rowOperationId else { return .refuse }
                switch operation.recipient {
                case .ownWallet: return .ownWallet
                case .external(let raw43): return .external(raw43)
                }
            }
        }
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

    /// The marker for the current wallet and network, classified for a
    /// resume: only content that cannot be a marker is `corrupt`.
    func markerLookup() -> (lookup: CoreShieldedDrainMarkerLookup, context: CoreShieldedDrainContext?) {
        let context: CoreShieldedDrainContext
        do {
            context = try Self.currentContext()
        } catch {
            return (.unavailable, nil)
        }
        do {
            return (.loaded(try store.load(context)), context)
        } catch is DecodingError {
            return (.corrupt, context)
        } catch CoreShieldedDrainFileStore.StoreError.contextMismatch {
            return (.corrupt, context)
        } catch {
            return (.unavailable, context)
        }
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

    /// The recipient is fixed here, before dispatch: it is the only durable
    /// record of where this operation's lock must go on a resume.
    func prepare(_ context: CoreShieldedDrainContext, recipient: CoreShieldedDrainRecipient) throws -> CoreShieldedDrainOperation {
        _ = try manager(for: context)
        guard try store.load(context) == nil else { throw CoreShieldedDrainFileStore.StoreError.pendingOperation }
        let operation = CoreShieldedDrainOperation(id: UUID(), context: context, recipient: recipient)
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
