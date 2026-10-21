import Foundation

enum SDKError: Error { case networkError(String) }
enum WalletOperationPreparationError: Error { case expired(String) }
enum PlatformWalletError: Error {
    case transactionBroadcastUnconfirmed(String)
    case walletOperation(String)
}

struct ModelContainer {}
struct MnemonicResolver {}
struct KeychainSigner { init(modelContainer: ModelContainer) {} }
enum SwiftDashSDKContactsService { enum ServiceError: Error { case noWallet } }
enum AddressTransformer {
    static func parseBech32mAddress(_ address: String) -> Data? { Data(repeating: 1, count: 21) }
}
enum PlatformPaymentIdentityFundingPolicy {
    static let creditsPerDuff: UInt64 = 1_000
    static let feeHeadroomCredits: UInt64 = 5
}

@MainActor final class ManagedPlatformWallet {
    struct IdentityAddressInput { let addressType: UInt8; let hash: Data; let credits: UInt64 }
    let walletId = Data([1])
    var topUpCalls = 0
    var failure: Error?
    var afterTopUp: () -> Void = {}
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
    struct PlatformPreparation: Sendable { let operationVersion: Int }
    static let shared = SwiftDashSDKHost()
    var wallet: ManagedPlatformWallet? = ManagedPlatformWallet()
    var manager: NativeManager? = NativeManager()
    var checkGeneration = 0
    var operationVersion = 0
    var scopeCalls = 0
    var rejectScopeCall: Int?
    func validatePlatformOperation(_ preparation: PlatformPreparation) throws {
        if preparation.operationVersion != operationVersion {
            throw WalletOperationPreparationError.expired("Changed")
        }
    }
    func withPlatformOperation<T>(
        preparation: PlatformPreparation, operation: () async throws -> T
    ) async throws -> T {
        scopeCalls += 1
        try validatePlatformOperation(preparation)
        if rejectScopeCall == scopeCalls {
            throw WalletOperationPreparationError.expired("Changed at scope admission")
        }
        return try await operation()
    }
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
    var stepLabel: String?
    // PRODUCTION_TOP_UP
}
