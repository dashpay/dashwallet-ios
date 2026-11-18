import Foundation

enum SDKError: Error { case stateTransitionResultUnconfirmed(String); case networkError(String) }
enum PlatformWalletError: Error {
    case transactionBroadcastUnconfirmed(String)
    case shieldedSpendUnconfirmed(String)
    case walletOperation(String)
    case assetLockTooManyInputs
}

enum TestBoundaryError: Error { case unusedRoute }
struct ModelContainer {}
struct TestAuthorizer { func authorize() async throws {} }
extension UInt64 {
    var dashAmount: UInt64 { self }
    var formattedDashAmountWithoutCurrencySymbol: String { String(self) }
}
struct MnemonicResolver {}
struct KeychainSigner { init(modelContainer: ModelContainer) {} }
enum SwiftDashSDKContactsService { enum ServiceError: Error { case noWallet } }
enum AddressTransformer {
    static func parseBech32mAddress(_ address: String) -> Data? { Data(repeating: 1, count: 21) }
}
enum PlatformPaymentIdentityFundingPolicy {
    static let creditsPerDuff: UInt64 = 1_000
    static let feeHeadroomCredits: UInt64 = 5
    enum PlanningError: Error { case insufficient(UInt64, UInt64) }
    static func candidates(walletId: Data, modelContainer: ModelContainer) throws -> [Int] {
        throw TestBoundaryError.unusedRoute
    }
    static func makeInputs(candidates: [Int], targetCredits: UInt64) throws -> [ManagedPlatformWallet.IdentityAddressInput] {
        throw TestBoundaryError.unusedRoute
    }
}

@MainActor final class ManagedPlatformWallet {
    struct IdentityAddressInput { let addressType: UInt8; let hash: Data; let credits: UInt64 }
    let walletId = Data([1])
    var topUpCalls = 0
    var failure: Error?
    var afterTopUp: () -> Void = {}
    func topUpIdentityWithFunding(identityId: Data, amountDuffs: UInt64, accountIndex: Int) async throws -> UInt64 {
        throw TestBoundaryError.unusedRoute
    }
    func topUpFromAddresses(
        identityId: Data, inputs: [IdentityAddressInput], addressSigner: KeychainSigner
    ) async throws -> UInt64 {
        topUpCalls += 1
        if let failure { throw failure }
        afterTopUp()
        return 97
    }
}

@MainActor final class NativeManager {
    var unshieldCalls = 0
    var failure: Error?
    var afterUnshield: () -> Void = {}
    func shieldedUnshield(
        walletId: Data, resolver: MnemonicResolver, account: Int, toPlatformAddress: String,
        amount: UInt64
    ) async throws {
        unshieldCalls += 1
        if let failure { throw failure }
        afterUnshield()
    }
}

@MainActor final class SwiftDashSDKHost {
    static let shared = SwiftDashSDKHost()
    var wallet: ManagedPlatformWallet? = ManagedPlatformWallet()
    var manager: NativeManager? = NativeManager()
    var modelContainer: ModelContainer? = ModelContainer()

}

@MainActor final class PlatformAddressSyncCoordinator {
    struct Address { let address: String }
    struct Addresses { var nextReceiveAddress: Address? = .init(address: "destination") }
    static let shared = PlatformAddressSyncCoordinator()
    var derivedAddresses = Addresses()
    func refreshShieldedBalanceAfterSpend(using manager: NativeManager) {}
    func syncNow() async {}
}

@MainActor final class IdentityTopUpViewModel {
    // PRODUCTION_FUNDING_SOURCE
    var stepLabel: String?
    var isProcessing = false
    var submittedUnconfirmed = false
    var movedToPlatform = false
    var errorMessage: String?
    var inputLimitCheck: AssetLockInputLimit.Check?
    let authorizer = TestAuthorizer()
    // PRODUCTION_TOP_UP
}

// SDK and logging edges for the production input-limit policy.
enum ShieldedTransferCoordinator {
    enum CoordinatorError: Error { case transferFailed(Error) }
}
enum DWIdentityRegistrationCoordinator {
    enum CoordinatorError: Error { case identityRegistration(Error), identityTopUp(Error), purchase(Error) }
}
enum DWLogger {
    static func log(_ message: String, className: String) {}
}
enum SwiftDashSDKTransactionSender {
    static let maxInputsPerSweep = 500
    // PRODUCTION_SENDER_HELPERS
    struct Coin { let isFinal: Bool; let valueDuffs: UInt64; let isCombinable: Bool }
    @MainActor static var coins: [Coin]?
    @MainActor static func pooledSpendableUtxos() -> [Coin]? { coins }
}

enum CoinJoinShieldPlanner { static let maxAssetLockInputs = 100 }

// The runner's post-authorization identity dispatch and outcome handling are
// production methods; request metadata irrelevant to that dispatch is omitted.
enum ChainNetwork { case core, platform, shielded }
struct IdentityTopUpTransfer { let identityId: Data; let source: ChainNetwork }
struct InternalTransferRequest { let amountDuffsUnsigned: UInt64 }
@MainActor final class InternalTransferRunner {
    var phase: Phase = .idle
    var notice: Notice?
    // PRODUCTION_RUNNER
}
