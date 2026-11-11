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
    /// reader, and the PIN/biometric gate. `requiresHTTPSFetch` makes the transport fetch the
    /// PaymentRequest over https only (see `PaymentProtocolTransport`).
    static func makeForCurrentWallet(requiresHTTPSFetch: Bool = false) -> BIP70PaymentService {
        BIP70PaymentService(
            transport: PaymentProtocolTransport(requiresHTTPSFetch: requiresHTTPSFetch),
            wallet: SwiftDashSDKWalletSending(),
            receiveAddress: SwiftDashSDKReceiveAddressProvider(),
            auth: BIP70SendAuthorizer())
    }
}
