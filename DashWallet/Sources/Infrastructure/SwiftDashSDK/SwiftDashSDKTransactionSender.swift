//
//  SwiftDashSDKTransactionSender.swift
//  DashWallet
//
//  Adapter around the SwiftDashSDK Core send path. The SDK refactor
//  collapsed `buildSignedTransaction` + `broadcast` into a single
//  `coreWallet().sendToAddresses(...)` FFI call (build + sign + broadcast
//  bundled). The legacy two-step `buildAndSign` then `broadcast` shape
//  used by `WalletSendService` / `DWPaymentProcessor` is preserved here
//  by routing the entire send through `buildAndSign` and turning
//  `broadcast(_:)` into a no-op. The user has already authenticated by
//  the time the build path runs (PIN auth fires in
//  `WalletSendService.prepareStandardSendForConfirmation`), and the
//  payment-output broadcast path stamps `alreadyAuthorized` so it doesn't
//  re-prompt.
//
//  This file intentionally does NOT import DashSync.
//

import CommonCrypto
import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKTransactionSender)
final class SwiftDashSDKTransactionSender: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.transaction-sender")

    // MARK: - Build & Sign (and broadcast)

    /// Build, sign, and broadcast a transaction that sends `amount` duffs to
    /// `address`. The SDK's `coreWallet().sendToAddresses(...)` is a single
    /// FFI call that does all three; we call it here so the existing
    /// `WalletSendService` two-step API keeps working without surgery into
    /// the surrounding ObjC payment processor.
    ///
    /// - Parameters:
    ///   - address: Destination Dash address (Base58Check).
    ///   - amount: Amount to send in duffs (1 DASH = 100_000_000 duffs).
    /// - Returns: Tuple of (serialized signed tx bytes, fee in duffs, 32-byte txHash).
    static func buildAndSign(address: String, amount: UInt64) throws -> (txData: Data, fee: UInt64, txHash: Data) {
        try buildAndSign(recipients: [(address: address, amountDuffs: amount)])
    }

    /// Multi-recipient variant — used by the app-side BIP70 send, where a merchant request may
    /// carry several outputs. Build + sign + broadcast are bundled by the same
    /// `coreWallet().sendToAddresses(...)` FFI call as the single-recipient path.
    static func buildAndSign(recipients: [(address: String, amountDuffs: UInt64)]) throws -> (txData: Data, fee: UInt64, txHash: Data) {
        logger.info("💸 TXSEND :: building+signing+broadcasting \(recipients.count, privacy: .public) recipient(s) via PlatformWalletManager.coreWallet")

        let send = { @MainActor () throws -> Data in
            guard let wallet = SwiftDashSDKHost.shared.wallet else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            let core = try wallet.coreWallet()
            return try core.sendToAddresses(
                accountType: .bip44,
                accountIndex: 0,
                recipients: recipients)
        }

        let txData: Data
        if Thread.isMainThread {
            txData = try MainActor.assumeIsolated { try send() }
        } else {
            var captured: Result<Data, Error> = .failure(SendError.walletNotReady("uninitialized result"))
            DispatchQueue.main.sync {
                captured = Result { try MainActor.assumeIsolated { try send() } }
            }
            txData = try captured.get()
        }

        let txHash = computeTxHash(from: txData)
        // Approximate fee at the standard 1000 duff/kB rate (1 duff/byte).
        // The actual fee — settled by the FFI when constructing the tx —
        // is within ±a few duffs of `txData.count` for typical 1-in-2-out
        // sends. We expose this for the preview UI; callers that need the
        // exact value can parse it from `DSTransaction.feeUsed` once the
        // tx is registered with DashSync's chain context.
        let fee = UInt64(txData.count)
        logger.info("💸 TXSEND :: send broadcast — txHash=\(txHash.map { String(format: "%02x", $0) }.joined(), privacy: .public) fee≈\(fee, privacy: .public) duffs")
        return (txData, fee, txHash)
    }

    // MARK: - CoinJoin Sweep

    /// Sweep the entire CoinJoin-account balance to `address` (the user's own
    /// BIP44 receive address), fully emptying the CoinJoin account. Build +
    /// sign + broadcast are bundled by the SDK's
    /// `coreWallet().sweepCoinJoinAccount(...)` FFI call, which splits the
    /// sweep across one or more transactions when the UTXO set is too large
    /// for a single relayable transaction (a heavy mixer).
    ///
    /// Used by the post-migration "move your mixed coins" flow: CoinJoin is no
    /// longer supported, so we move the user's mixed coins into their normal
    /// spendable balance.
    ///
    /// - Parameter address: Destination Dash address (the user's own BIP44
    ///   receive address, resolved via `SwiftDashSDKReceiveAddressReader`).
    /// - Returns: The **wire-order** txids of the broadcast sweep transactions
    ///   (one per chunk), as provided by the SDK — ready to record in
    ///   `CoinJoinWithdrawalStore` (matches `Transaction.txHashData`).
    static func sweepCoinJoin(to address: String) throws -> [Data] {
        logger.info("💸 TXSEND :: sweeping CoinJoin account → spendable balance")

        let sweep = { @MainActor () throws -> [Data] in
            guard let wallet = SwiftDashSDKHost.shared.wallet else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            let core = try wallet.coreWallet()
            return try core.sweepCoinJoinAccount(accountIndex: 0, destination: address)
        }

        let txids: [Data]
        if Thread.isMainThread {
            txids = try MainActor.assumeIsolated { try sweep() }
        } else {
            var captured: Result<[Data], Error> = .failure(SendError.walletNotReady("uninitialized result"))
            DispatchQueue.main.sync {
                captured = Result { try MainActor.assumeIsolated { try sweep() } }
            }
            txids = try captured.get()
        }

        // Log display-order hex (byte-reversed wire order) to match explorers.
        let hexes = txids.map { txid -> String in
            Data(txid.reversed()).map { String(format: "%02x", $0) }.joined()
        }
        logger.info("💸 TXSEND :: coinjoin sweep broadcast — \(txids.count, privacy: .public) tx(s): \(hexes.joined(separator: ","), privacy: .public)")
        return txids
    }

    // MARK: - Broadcast

    /// No-op. The transaction was already broadcast by `buildAndSign` —
    /// the SDK's send path bundles build + sign + broadcast into a single
    /// FFI call, so there is nothing left to do here. Kept around so the
    /// legacy two-step caller surface (`PreparedStandardSend.broadcast()`,
    /// `DWPaymentProcessor.performSwiftDashSDKBroadcast`) stays
    /// compilable. If a future SDK exposes a separated build/broadcast
    /// pair, this becomes the broadcast call.
    ///
    /// - Parameter txData: Serialized signed transaction bytes (ignored).
    static func broadcast(_ txData: Data) throws {
        _ = txData
        logger.info("💸 TXSEND :: broadcast no-op — tx was already broadcast at buildAndSign time")
    }

    // MARK: - Helpers

    /// Compute txHash from raw transaction bytes.
    ///
    /// Standard Bitcoin/Dash txid: double SHA-256, byte-reversed.
    /// Matches `SendViewModel.computeTxid` in the SwiftDashSDK example app.
    private static func computeTxHash(from txData: Data) -> Data {
        var hash1 = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        var hash2 = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        txData.withUnsafeBytes { ptr in
            hash1.withUnsafeMutableBytes { out in
                _ = CC_SHA256(ptr.baseAddress, CC_LONG(txData.count), out.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        hash1.withUnsafeBytes { ptr in
            hash2.withUnsafeMutableBytes { out in
                _ = CC_SHA256(ptr.baseAddress, CC_LONG(hash1.count), out.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return Data(hash2.reversed())
    }

    // MARK: - Errors

    enum SendError: LocalizedError {
        case invalidInput(String)
        case walletNotReady(String)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let reason):
                return "Invalid transaction input: \(reason)"
            case .walletNotReady(let reason):
                return "Wallet not ready: \(reason)"
            }
        }
    }
}
