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
    /// The active network's `PaymentNetwork` token.
    ///
    /// The token has two consumers with different needs: the script/address
    /// codecs, which care only about version bytes (devnet's are testnet's),
    /// and BIP70's `details.network` check, which compares payment networks
    /// for identity. Devnet therefore resolves to its own case rather than to
    /// `.testnet`. `ScriptAddressCodec` maps it back onto testnet's version
    /// bytes, so selected-input sends and address handling on devnet are
    /// unchanged; what changes is that a merchant request declaring `"test"`
    /// is now rejected as a network mismatch instead of being signed and
    /// broadcast by a host running on a devnet.
    static func current() throws -> PaymentNetwork {
        switch WalletEnvironment.networkKind {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        }
    }
}
