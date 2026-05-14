//
//  NSString+SwiftDashSDKAddress.swift
//  DashWallet
//
//  Co-located @objc bridge that validates a Dash address against a
//  `DSChain` by routing through SwiftDashSDK's `Address.validate`.
//  Replaces the standalone `DWSwiftDashSDKAddressValidator` adapter —
//  migration row #2 (Address validation) is now ✅ Done.
//
//  The `dw_` prefix avoids collision with DashSync's
//  `isValidDashAddressOnChain:` NSString category in `NSString+Dash.h`.
//

import Foundation
import SwiftDashSDK

extension NSString {
    @objc(dw_isValidDashAddressOnChain:)
    func dw_isValidDashAddressOnChain(_ chain: DSChain) -> Bool {
        let address = self as String
        guard !address.isEmpty else { return false }
        return Address.validate(address, network: chain.dw_swiftDashSDKNetwork)
    }
}

fileprivate extension DSChain {
    var dw_swiftDashSDKNetwork: SwiftDashSDK.Network {
        switch chainType.tag {
        case ChainType_MainNet: return .mainnet
        case ChainType_TestNet: return .testnet
        default:                return .devnet
        }
    }
}
