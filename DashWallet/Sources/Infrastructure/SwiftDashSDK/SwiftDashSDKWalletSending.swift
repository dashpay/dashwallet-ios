//
//  SwiftDashSDKWalletSending.swift
//  DashWallet
//
//  BIP70 Layer 6 adapter — implements the protocol-core `WalletSending` over the funded
//  SwiftDashSDK wallet (`SwiftDashSDKTransactionSender`).
//
//  `buildSignedTransaction` builds + signs only; the built `FinalizedCoreTransaction` rides
//  inside `PreparedSend.sdkTransaction` (opaque `AnyObject` — the protocol core stays
//  Foundation-only) until `broadcast(_:)` submits it. Discarding a prepared send abandons the
//  build and releases its reserved inputs (the handle's deinit), so a POST-failure retry that
//  rebuilds cannot double-select. `BIP70PaymentService.confirmAndSend` uses the final
//  BIP70-correct ordering: build/sign → Payment/ACK → broadcast.
//

import Foundation
import SwiftDashSDK

final class SwiftDashSDKWalletSending: WalletSending {

    func buildSignedTransaction(recipients: [(address: String, amountDuffs: UInt64)]) async throws -> PreparedSend {
        let (tx, txHash) = try SwiftDashSDKTransactionSender.buildAndSign(recipients: recipients)
        return PreparedSend(
            txData: try tx.serializedData(), fee: tx.fee, txHashDisplay: txHash, sdkTransaction: tx)
    }

    func broadcast(_ prepared: PreparedSend) async throws -> String {
        guard let tx = prepared.sdkTransaction as? FinalizedCoreTransaction else {
            throw SwiftDashSDKTransactionSender.SendError.invalidInput(
                "PreparedSend carries no SDK transaction handle")
        }
        let outcome = try SwiftDashSDKTransactionSender.broadcast(tx)
        _ = try SwiftDashSDKTransactionSender.requireAccepted(outcome)
        // Return contract is the display-order txid hex; keep the deterministic
        // app-computed value (the sender logs the SDK-reported txid alongside).
        return prepared.txHashDisplay.map { String(format: "%02x", $0) }.joined()
    }
}
