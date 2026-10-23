import Foundation

// SDK and environment stand-ins only. The production host's preparation
// struct, methods, and error type are inserted unchanged by the test runner.
enum Network {
    case mainnet, testnet
}

struct ProtocolVersionInfo {
    var verifiedVersion: UInt32? = 14
    var effectiveVersion: UInt32 = 14
    var maximumSupportedVersion: UInt32 = 14
}

@MainActor
final class SDK {
    var snapshot = ProtocolVersionInfo()
    var snapshotError: Error?

    func protocolVersionInfo() throws -> ProtocolVersionInfo {
        if let snapshotError { throw snapshotError }
        return snapshot
    }
}

struct ManagedPlatformWallet {
    let walletId: Data
}

@MainActor
enum WalletEnvironment {
    static var network: Network? = .mainnet
    static var networkKind: Network? { network }
    static var selectedWalletID: Data?

    static func activeWalletId(for network: Network?) -> Data? { selectedWalletID }
}

@MainActor
final class SwiftDashSDKHost {
    static var shared = SwiftDashSDKHost(sdk: SDK(), walletID: Data([1]))
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

// Only the resume/auth boundary is controlled; retry, reset and host context
// validation are extracted unchanged from production. No spend is performed.
@MainActor final class RetryCoordinator {
    enum Phase { case idle, signing, failed(String) }
    var phase: Phase = .failed("previous failure")
    var confirmationPreparation: Result<SwiftDashSDKHost.PlatformPreparation, Error>?
    var operationPreparation: SwiftDashSDKHost.PlatformPreparation?
    var lastAssetLockOutPoint: (txidWire: Data, vout: UInt32)?
    var lastFailure: Error?
    var lastResumeReport: Int?
    var attempted: [(Data, UInt32, Data?)] = []
    var authorized: [(Data, UInt32, Data?)] = []
    var onAuthorize: () -> Void = {}
    func stopAssetLockPolling() {}
    func handleFailure(_ error: Error) { lastFailure = error; phase = .failed(error.localizedDescription) }
    func resumeAssetLock(outPointTxidWire: Data, outPointVout: UInt32, recipientRaw43: Data?,
                         retryUnverifiedConsumption: Bool = false) async {
        phase = .signing
        attempted.append((outPointTxidWire, outPointVout, recipientRaw43))
        onAuthorize()
        do {
            try SwiftDashSDKHost.shared.validatePlatformOperation(confirmationPreparation!.get())
            authorized.append((outPointTxidWire, outPointVout, recipientRaw43))
            throw NSError(domain: "controlled-resume-failure", code: 1)
        } catch { handleFailure(error) }
    }
    // RETRY_METHOD
    // RESET_METHOD
}
