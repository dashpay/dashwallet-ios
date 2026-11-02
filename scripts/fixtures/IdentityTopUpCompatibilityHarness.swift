import Foundation

enum SDKError: Error { case networkError(String) }
enum PlatformWalletError: Error {
    case transactionBroadcastUnconfirmed(String)
    case shieldedSpendUnconfirmed(String)
    case walletOperation(String)
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
    enum FundingSource { case transparent, platform, shielded }
    var stepLabel: String?
    var isProcessing = false
    var submittedUnconfirmed = false
    var errorMessage: String?
    let authorizer = TestAuthorizer()
    // PRODUCTION_TOP_UP
}
