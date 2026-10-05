//
//  BIP70PaymentService+App.swift
//  DashWallet
//
//  BIP70 Layer 6 — the single construction site that wires the pure `BIP70PaymentService`
//  (L1–L5) to the app's real wallet/receive/auth adapters. Kept out of the pure
//  PaymentProtocol/ folder so the core stays SDK-free.
//

import Foundation

extension BIP70PaymentService {
    /// Builds a service backed by the funded SwiftDashSDK wallet, the app's receive-address
    /// reader, and the PIN/biometric gate.
    static func makeForCurrentWallet() -> BIP70PaymentService {
        let service = BIP70PaymentService(
            wallet: SwiftDashSDKWalletSending(),
            receiveAddress: SwiftDashSDKReceiveAddressProvider(),
            auth: BIP70SendAuthorizer())
        // A payment the merchant acknowledged whose broadcast then got no
        // answer is followed in the history like any send.
        service.onDetachedBroadcastUnknown = { txHashDisplay, amount, address, reason in
            _ = WalletSendService.unknownOutcomeError(
                txidWire: Data(txHashDisplay.reversed()), address: address, amount: amount, reason: reason)
        }
        return service
    }
}
