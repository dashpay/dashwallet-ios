//
//  SwiftDashSDKAddressValidator.swift
//  DashWallet
//
//  Address-validation adapter — SwiftDashSDK is the sole authoritative source.
//
//  Stage history:
//    Stage 0 — Shadow:  called both libraries, returned DashSync result, logged mismatches
//    Stage 1 — Flipped: called both libraries, returned SwiftDashSDK result, logged mismatches
//    Stage 2 — Solo:    only SwiftDashSDK is called (current)
//    Stage 3 — Done:    adapter retired, call sites use SwiftDashSDK directly (future)
//
//  The DashSync parallel call and devnet fallback were removed after we verified
//  that DashSync's `[NSString isValidDashAddressOnChain:]` and rust-dashcore's
//  `Address::is_valid_for_network` use byte-identical logic for all networks
//  including devnet/evonet (both fall back to testnet's version bytes 140/19).
//

import Foundation
import SwiftDashSDK

@objc(DWSwiftDashSDKAddressValidator)
final class SwiftDashSDKAddressValidator: NSObject {

    /// Validates a Dash address against the given chain using SwiftDashSDK.
    ///
    /// - Parameters:
    ///   - address: The address string to validate. May be nil/empty.
    ///   - chain: The DashSync chain (mainnet/testnet/devnet) — used only for network mapping.
    /// - Returns: `true` iff the address is a valid Dash address for the chain.
    @objc(isValidDashAddress:onChain:)
    static func isValidDashAddress(_ address: String?, on chain: DSChain) -> Bool {
        guard let address = address, !address.isEmpty else {
            return false
        }
        return Address.validate(address, network: mapNetwork(chain.chainType.tag))
    }

    // MARK: - Network mapping

    private static func mapNetwork(_ tag: ChainType_Tag) -> KeyWalletNetwork {
        switch tag {
        case ChainType_MainNet: return .mainnet
        case ChainType_TestNet: return .testnet
        default:                return .devnet  // dashwallet's evonet — verified equivalent to .devnet
        }
    }
}
