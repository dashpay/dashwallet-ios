//
//  PaymentNetworkResolver.swift
//  DashWallet
//
//  BIP70 Layer 6 boundary — maps the app's active network to the Foundation-only
//  `PaymentNetwork` token the protocol core consumes. This is the L5/L6 seam: the pure core
//  never reads the app's network state; L6 resolves the token here and passes it in.
//

import Foundation

enum PaymentNetworkResolver {
    /// The active network, or throws `.walletNotReady` if it isn't a supported BIP70 network
    /// (devnet/unsupported).
    static func current() throws -> PaymentNetwork {
        switch WalletEnvironment.networkKind {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: throw BIP70Error.walletNotReady
        }
    }
}
