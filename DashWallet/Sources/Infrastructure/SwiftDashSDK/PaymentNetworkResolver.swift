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
    /// The active network's `PaymentNetwork` token. The token encodes address
    /// version bytes (see `ScriptAddressCodec`), and devnet shares testnet's,
    /// so devnet maps to `.testnet` — this keeps the selected-input send and
    /// script/address codecs working on devnet. (No BIP70 merchant exists on
    /// a devnet; such a request simply fails at the network layer.)
    static func current() throws -> PaymentNetwork {
        switch WalletEnvironment.networkKind {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .testnet
        }
    }
}
