//
//  PaymentNetworkResolver.swift
//  DashWallet
//
//  BIP70 Layer 6 boundary — maps the app's active `DSChain` to the Foundation-only
//  `PaymentNetwork` token the protocol core consumes. This is the L5/L6 seam: the pure core
//  never reads `DWEnvironment`/`DSChain`; L6 resolves the token here and passes it in.
//

import Foundation

enum PaymentNetworkResolver {
    /// nil for an unsupported network (devnet/regtest) — callers map that to `.walletNotReady`.
    static func paymentNetwork(from chain: DSChain) -> PaymentNetwork? {
        if chain.isMainnet() { return .mainnet }
        if chain.isTestnet() { return .testnet }
        return nil
    }

    /// The active network, or throws `.walletNotReady` if it isn't a supported BIP70 network.
    static func current() throws -> PaymentNetwork {
        guard let network = paymentNetwork(from: DWEnvironment.sharedInstance().currentChain) else {
            throw BIP70Error.walletNotReady
        }
        return network
    }
}
