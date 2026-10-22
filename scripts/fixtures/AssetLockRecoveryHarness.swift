import Foundation
import OSLog

enum WalletEnvironment {
    static var activeWalletIdHex: String?
}
enum PlatformWalletError: Error {
    case assetLockAlreadyConsumed
    case shieldedSpendUnconfirmed
}
struct ShieldedFundFromAssetLockRecipient {
    let recipientRaw43: Data
    let credits: UInt64?
}
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
enum WalletOperationPreparationError: Error { case expired(String) }
@MainActor final class SwiftDashSDKHost {
    struct PlatformPreparation { let walletId: Data }
    static let shared = SwiftDashSDKHost()
    var recoveryPreparation: ((PlatformPreparation) throws -> PlatformPreparation)?
    func preparePlatformRecoveryOperation(matching original: PlatformPreparation) throws -> PlatformPreparation {
        guard let recoveryPreparation else {
            throw WalletOperationPreparationError.expired("Configure the preparation boundary for this test")
        }
        return try recoveryPreparation(original)
    }
}
// Dependency seam for the drain context check added by develop. Recovery
// tests must explicitly supply an outcome instead of fabricating a manager.
struct CoreShieldedDrainContext {
    let walletId: Data
    let networkScope: String
}
@MainActor
struct CoreShieldedDrainService {
    enum TestError: Error { case contextChanged }
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
    enum Phase: Equatable { case idle, proving, broadcasting, success, submittedUnconfirmed, failed }
    enum ResumeReport { case alreadyConsumed }
    struct Environment {
        let manager: TestManager
        let walletId: Data
        let shieldedRecipient: Data
    }
    static let logger = Logger(subsystem: "RecoveryHarness", category: "test")
    var phase: Phase = .idle
    var lastResumeReport: ResumeReport?
    var lastFailure: Error?
    var confirmationPreparation: Result<SwiftDashSDKHost.PlatformPreparation, Error>?
    var operationPreparation: SwiftDashSDKHost.PlatformPreparation?
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
    func performPrepared(_ body: () async throws -> Void) async throws { try await body() }
    func handleFailure(_ error: Error) { phase = .failed }
    func handleSpendError(_ error: Error, manager: TestManager) { phase = .submittedUnconfirmed }
    func scheduleShieldedResync(manager: TestManager) {}
    // PRODUCTION_METHODS
}
