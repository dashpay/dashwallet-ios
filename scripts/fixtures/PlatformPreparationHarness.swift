import Foundation

// SDK and environment stand-ins only. The production host's preparation
// struct, methods, and error type are inserted unchanged by the test runner.
enum Network {
    case mainnet, testnet
}

struct ProtocolCompatibility {
    enum Status: CaseIterable {
        case unavailable, checking, checked
    }

    var generation: UInt64 = 1
    var status: Status = .checked
    var verifiedProtocolVersion: UInt32? = 14
    var effectiveProtocolVersion: UInt32 = 14
    var maximumSupportedProtocolVersion: UInt32 = 14
}

@MainActor
final class SDK {
    var snapshot = ProtocolCompatibility()
    var snapshotError: Error?

    func protocolCompatibility() throws -> ProtocolCompatibility {
        if let snapshotError { throw snapshotError }
        return snapshot
    }
}

struct ManagedPlatformWallet {
    let walletId: Data
}

@MainActor
enum WalletEnvironment {
    static var network = Network.mainnet
    static var networkKind: Network { network }
    static var selectedWalletID: Data?

    static func activeWalletId(for network: Network) -> Data? { selectedWalletID }
}

@MainActor
final class SwiftDashSDKHost {
    var sdk: SDK?
    var runningNetwork: Network?
    var wallet: ManagedPlatformWallet?
    var runtimeID = UUID()

    init(sdk: SDK, walletID: Data) {
        self.sdk = sdk
        self.runningNetwork = .mainnet
        self.wallet = ManagedPlatformWallet(walletId: walletID)
    }

    // EXTRACTED_PRODUCTION_METHODS
}
