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
    func shieldedResumeFundFromAssetLock(walletId: Data, outPointTxid: Data, outPointVout: UInt32,
                                         recipients: [ShieldedFundFromAssetLockRecipient]) async throws {
        calls += 1
        receivedTxid = outPointTxid
        if let error { throw error }
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
    let environment: Environment
    var authorizations = 0
    var onAuthorize: (() -> Void)?
    init(environment: Environment) { self.environment = environment }
    func beginTransfer() -> Bool { phase == .idle }
    func resolveEnvironment() throws -> Environment { environment }
    func authorize() async throws { authorizations += 1; onAuthorize?() }
    func performPrepared(_ body: () async throws -> Void) async throws { try await body() }
    func handleFailure(_ error: Error) { phase = .failed }
    func handleSpendError(_ error: Error, manager: TestManager) { phase = .submittedUnconfirmed }
    func scheduleShieldedResync(manager: TestManager) {}
    // PRODUCTION_METHODS
}
