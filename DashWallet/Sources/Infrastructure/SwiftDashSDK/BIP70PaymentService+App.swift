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
    /// reader, and the PIN/biometric gate. `requiresHTTPS` makes every request of the transport
    /// https only (see `PaymentProtocolTransport`); it has no default, so each caller chooses.
    static func makeForCurrentWallet(requiresHTTPS: Bool) -> BIP70PaymentService {
        BIP70PaymentService(
            transport: PaymentProtocolTransport(requiresHTTPS: requiresHTTPS),
            wallet: SwiftDashSDKWalletSending(),
            receiveAddress: SwiftDashSDKReceiveAddressProvider(),
            auth: BIP70SendAuthorizer())
    }
}
