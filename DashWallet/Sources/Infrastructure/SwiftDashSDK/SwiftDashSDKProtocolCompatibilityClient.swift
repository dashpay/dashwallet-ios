import SwiftDashSDK

/// Marshals SDK snapshots for the host's lifecycle controller.
struct SwiftDashSDKProtocolCompatibilityClient: WalletProtocolCompatibilityClient {
    let sdk: SDK

    func beginCheck() throws -> UInt64 {
        try sdk.beginProtocolCompatibilityCheck()
    }

    func refresh(generation: UInt64) throws -> WalletProtocolCompatibility {
        map(try sdk.refreshProtocolCompatibility(generation: generation))
    }

    func snapshot() throws -> WalletProtocolCompatibility {
        map(try sdk.protocolCompatibility())
    }

    private func map(_ value: ProtocolCompatibility) -> WalletProtocolCompatibility {
        let status: WalletProtocolCompatibility.Status
        switch value.status {
        case .unavailable: status = .unavailable
        case .checking: status = .checking
        case .checked: status = .checked
        }
        return WalletProtocolCompatibility(
            generation: value.generation, status: status,
            verifiedVersion: value.verifiedProtocolVersion,
            effectiveVersion: value.effectiveProtocolVersion,
            maximumSupportedVersion: value.maximumSupportedProtocolVersion,
            newerProtocolAvailable: value.newerProtocolAvailable)
    }
}
