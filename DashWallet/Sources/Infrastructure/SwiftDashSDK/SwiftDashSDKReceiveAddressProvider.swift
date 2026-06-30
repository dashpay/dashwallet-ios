//
//  SwiftDashSDKReceiveAddressProvider.swift
//  DashWallet
//
//  BIP70 Layer 6 adapter — implements the protocol-core `ReceiveAddressProviding` over the
//  existing `SwiftDashSDKReceiveAddressReader`, supplying the wallet's own next receive address
//  for the BIP70 `Payment.refund_to`. Returns nil when no wallet is bound yet (the service then
//  sends an empty refund_to rather than failing).
//

import Foundation

final class SwiftDashSDKReceiveAddressProvider: ReceiveAddressProviding {
    func receiveAddress() -> String? {
        SwiftDashSDKReceiveAddressReader.receiveAddress(on: DWEnvironment.sharedInstance().currentChain)
    }
}
