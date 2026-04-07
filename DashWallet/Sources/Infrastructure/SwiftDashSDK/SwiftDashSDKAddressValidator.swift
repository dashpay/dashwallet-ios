//
//  SwiftDashSDKAddressValidator.swift
//  DashWallet
//
//  Shadow-mode adapter for DashSync ↔ SwiftDashSDK address-validation parity.
//
//  Stage 0 (this PR): calls BOTH libraries on every validation request,
//  logs any disagreement via os.log, and returns DashSync's authoritative
//  result. Bug-for-bug compatible with the existing implementation.
//
//  Stage 1 (follow-up PR after shadow logs are clean): flip the return
//  statement to `sdkResult` so SwiftDashSDK becomes authoritative. No
//  call-site change required.
//
//  Stage 2/3 (future): drop the DashSync call, then inline the
//  SwiftDashSDK call directly at call sites and delete this adapter.
//

import Foundation
import SwiftDashSDK
import os

@objc(DWSwiftDashSDKAddressValidator)
final class SwiftDashSDKAddressValidator: NSObject {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.address-validation"
    )

    /// Shadow-mode validation. Returns DashSync's result; logs any
    /// disagreement with SwiftDashSDK via `os.log`.
    ///
    /// - Parameters:
    ///   - address: The address string to validate. May be nil/empty.
    ///   - chain: The DashSync chain (mainnet/testnet/devnet).
    /// - Returns: `true` iff DashSync says the address is valid for the chain.
    @objc(isValidDashAddress:onChain:)
    static func isValidDashAddress(_ address: String?, on chain: DSChain) -> Bool {
        // 1. DashSync side — authoritative for now.
        let dashSyncResult = (address as NSString?)?.isValidDashAddress(on: chain) ?? false

        // 2. SwiftDashSDK side — shadow.
        guard let address = address, !address.isEmpty else {
            return dashSyncResult
        }
        guard let network = mapNetwork(chain.chainType.tag) else {
            // DevNet / unknown chain — SwiftDashSDK doesn't know about
            // dashwallet's specific evonet, fall back silently to DashSync.
            return dashSyncResult
        }

        let sdkResult = Address.validate(address, network: network)

        if sdkResult != dashSyncResult {
            logger.warning("address validation mismatch — address=\(address, privacy: .public) network=\(network.debugName, privacy: .public) ds=\(dashSyncResult, privacy: .public) sdk=\(sdkResult, privacy: .public)")
        }

        return dashSyncResult
    }

    // MARK: - Network mapping

    private static func mapNetwork(_ tag: ChainType_Tag) -> KeyWalletNetwork? {
        switch tag {
        case ChainType_MainNet: return .mainnet
        case ChainType_TestNet: return .testnet
        default: return nil  // DevNet / evonet → fall back to DashSync only
        }
    }
}

private extension KeyWalletNetwork {
    var debugName: String {
        switch self {
        case .mainnet: return "mainnet"
        case .testnet: return "testnet"
        case .regtest: return "regtest"
        case .devnet:  return "devnet"
        }
    }
}
