//
//  SwiftDashSDKWalletSending.swift
//  DashWallet
//
//  BIP70 Layer 6 adapter — implements the protocol-core `WalletSending` over the funded
//  SwiftDashSDK wallet (`SwiftDashSDKTransactionSender`).
//
//  INTERIM ordering note: today's `buildAndSign` bundles build+sign+broadcast in one FFI call,
//  so `buildSignedTransaction` already broadcasts and `broadcast(_:)` is effectively a no-op
//  (it returns the txid the build step computed). When the additive build-without-broadcast
//  FFI lands, this adapter splits cleanly and `BIP70PaymentService.confirmAndSend` flips to
//  POST→broadcast (see `// TODO(P0 flip)` there). See DASHSYNC_MIGRATION.md row #22.
//

import Foundation

final class SwiftDashSDKWalletSending: WalletSending {

    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend {
        let (txData, fee, txHash) = try SwiftDashSDKTransactionSender.buildAndSign(recipients: recipients)
        return PreparedSend(txData: txData, fee: fee, txHashDisplay: txHash)
    }

    func broadcast(_ prepared: PreparedSend) async throws -> String {
        // Interim: a no-op — the tx was already broadcast at build time. Returns the display-order
        // txid hex computed during the build.
        try SwiftDashSDKTransactionSender.broadcast(prepared.txData)
        return prepared.txHashDisplay.map { String(format: "%02x", $0) }.joined()
    }
}
