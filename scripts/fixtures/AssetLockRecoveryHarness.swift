import Foundation
import OSLog

enum WalletEnvironment {
    static var activeWalletIdHex: String?
}
enum PlatformWalletError: Error {
    case assetLockAlreadyConsumed
    case shieldedSpendUnconfirmed
    case transactionBroadcastUnconfirmed(String)
    case walletOperation(String)
}
struct ShieldedFundFromAssetLockRecipient {
    let recipientRaw43: Data
    let credits: UInt64?
}
typealias PlatformWalletManager = TestManager

@MainActor
final class TestManager {
    var error: Error?
    var calls = 0
    var receivedTxid: Data?
    var receivedVout: UInt32?
    var receivedRecipients: [ShieldedFundFromAssetLockRecipient] = []
    func shieldedResumeFundFromAssetLock(walletId: Data, outPointTxid: Data, outPointVout: UInt32,
                                         recipients: [ShieldedFundFromAssetLockRecipient]) async throws {
        calls += 1
        receivedTxid = outPointTxid
        receivedVout = outPointVout
        receivedRecipients = recipients
        if let error { throw error }
    }
}
@MainActor final class SwiftDashSDKHost {
    static let shared = SwiftDashSDKHost()
    var manager: TestManager?
}

// Dependency seam for the drain context check added by develop. Recovery
// tests must explicitly supply an outcome instead of fabricating a manager.
@MainActor
struct CoreShieldedDrainService {
    enum TestError: Error { case contextChanged }
    static var marker: CoreShieldedDrainMarkerLookup = .unavailable
    func markerLookup() -> (CoreShieldedDrainMarkerLookup, CoreShieldedDrainContext?) { (Self.marker, nil) }
    static var resolveManager: ((CoreShieldedDrainContext) throws -> TestManager)?
    func manager(for context: CoreShieldedDrainContext) throws -> TestManager {
        guard let resolveManager = Self.resolveManager else { throw TestError.contextChanged }
        return try resolveManager(context)
    }
}
@MainActor
final class ShieldedTxLookup {
    static let shared = ShieldedTxLookup()
    func refresh(reason: String) async {}
}
extension Notification.Name {
    static let swiftDashSDKTransactionProjectionDidChange = Notification.Name("projection")
}
@MainActor
final class ShieldedTransferCoordinator {
    enum CoordinatorError: Error {
        case transferFailed(Error), authCancelled, drainRecipientUnavailable, drainRecipientUnknown, noWallet
        var errorDescription: String? { "Authentication cancelled" }
    }
    enum Phase: Equatable { case idle, proving, broadcasting, success, submittedUnconfirmed, failed(String) }
    enum ResumeReport { case alreadyConsumed }
    struct Environment {
        let manager: TestManager
        let walletId: Data
        let shieldedRecipient: Data
        var network: String { "testnet" }
        var modelContainer: Void { () }
    }
    static var rowLookup: (() -> CoreShieldedDrainRowIdentity?)?
    static func drainRowIdentity(outPointTxidWire: Data, vout: UInt32, walletId: Data, in container: Void) -> CoreShieldedDrainRowIdentity? {
        guard let rowLookup else { preconditionFailure("Test must configure the asset-lock row") }
        return rowLookup()
    }
    static let logger = Logger(subsystem: "RecoveryHarness", category: "test")
    var phase: Phase = .idle
    var lastResumeReport: ResumeReport?
    var lastFailure: Error?
    var lastAssetLockContext: CoreShieldedDrainContext?
    var lastAssetLockOutPoint: (txidWire: Data, vout: UInt32)?
    let environment: Environment
    var authorizations = 0
    var onAuthorize: (() -> Void)?
    var authorizationError: Error?
    init(environment: Environment) { self.environment = environment }
    func beginTransfer() -> Bool { phase == .idle }
    func resolveEnvironment() throws -> Environment { environment }
    func authorize() async throws {
        authorizations += 1
        onAuthorize?()
        if let authorizationError { throw authorizationError }
    }
    func stopAssetLockPolling() {}
    func handleFailure(_ error: Error) {
        phase = .failed(error is CancellationError ? CoordinatorError.authCancelled.errorDescription! : "test failure")
    }
    enum Funding { case coinJoinDrain }
    var newAssetLockCalls = 0
    func performAssetLock(funding: Funding) async { newAssetLockCalls += 1 }
    func scheduleShieldedResync(manager: TestManager) {}
    func schedulePlatformResync() {}
    // PRODUCTION_METHODS
}

// Actual caller retry methods are inserted by the runner. Presentation and
// fresh-send boundaries only record calls; native work uses the coordinator above.
@MainActor final class SwiftDashSDKWalletState {
    static let shared = SwiftDashSDKWalletState()
    func refreshCoinJoinBalance() {}
}
@MainActor final class CoinJoinRetryHarness {
    enum Destination { case shielded }
    enum Stage: Equatable {
        case choice, shielding, success(Destination), submittedUnconfirmed
        case failed(message: String, destination: Destination)
    }
    var stage: Stage = .choice
    var isInFlight = false
    let coordinator: ShieldedTransferCoordinator
    var newDrainCalls: Int { coordinator.newAssetLockCalls }
    init(_ coordinator: ShieldedTransferCoordinator) { self.coordinator = coordinator }
    var binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding?
    var unresumedLock: (txidWire: Data, vout: UInt32)?
    enum Preparation { case authorizing }
    var preparation: Preparation?
    var consolidationSent = false
    static let genericFailureMessage = "test failure"
    nonisolated static var unresumedLockMessage: String { "Resume the existing lock" }
    static func log(_ message: String) {}
    func unobservedConsolidationRefusal() -> String? { preconditionFailure("Unexpected fresh drain") }
    struct Plan {
        struct State { let binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding }
        let state: State?
        let needsPreparation: Bool
        let description: String
    }
    static func plan(expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding?) -> Plan {
        preconditionFailure("Unexpected fresh drain planning")
    }
    func authorizeShieldedMove() async -> Bool { preconditionFailure("Unexpected fresh drain authorization") }
    func prepareForDrain(needed: Bool, from state: Plan.State) async -> Bool { preconditionFailure("Unexpected fresh drain preparation") }
    func drainToShielded(expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding) async { preconditionFailure("Unexpected second drain") }
    // COINJOIN_HELPERS
    // COINJOIN_MOVE
    // COINJOIN_FINISH
    // COINJOIN_RETRY
}

@MainActor final class SendRetryHarness {
    enum Route { case coreToShielded, platformToShielded }
    var route: Route = .platformToShielded
    var isCoreDrain = false
    var destinationRaw43: Data?
    let coordinator: ShieldedTransferCoordinator
    var cancellations = 0
    var confirmations = 0
    init(_ coordinator: ShieldedTransferCoordinator) { self.coordinator = coordinator }
    func onCancel() { cancellations += 1 }
    func confirm() { confirmations += 1 }
    // SEND_RETRY
}

@MainActor enum SwiftDashSDKTransactionSender {
    struct CoinJoinWalletBinding: Equatable {
        let walletId: Data
        let network: String
        static var selected: Self?
        static func current() -> Self? { selected }
    }
}
