//
//  SwiftDashSDKTransactionSender.swift
//  DashWallet
//
//  Adapter around the SwiftDashSDK Core send path. Build + sign + broadcast
//  are done together via the core `CoreTransactionBuilder` (setFunding →
//  addOutput → buildSigned → broadcastTransaction). The legacy two-step
//  `buildAndSign` then `broadcast` shape used by `WalletSendService` /
//  `DWPaymentProcessor` is preserved here by routing the entire send through
//  `buildAndSign` and turning `broadcast(_:)` into a no-op. The user has
//  already authenticated by the time the build path runs (PIN auth fires in
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

    // MARK: - CoinJoin sweep constants (documented mirrors; core is the backstop)

    /// Max inputs per sweep transaction. 500 matches key-wallet's
    /// `MAX_STANDARD_TX_INPUTS`, which the builder hard-rejects if exceeded — so
    /// this cap is a proactive split, and a drifted value still fails safe (an
    /// error) rather than mis-signing.
    private static let maxInputsPerSweep = 500
    /// Relay-minimum fee rate: 1 duff/byte == 1000 duffs per kB.
    private static let feeRateSatPerKb: UInt64 = 1000
    /// `AccountBalance.typeTag` discriminant for CoinJoin (matches
    /// `SwiftDashSDKCoinJoinBalanceReader`).
    private static let coinJoinTypeTag: UInt8 = 1
    /// Only CoinJoin account 0 is created and swept (matches the balance reader).
    private static let coinJoinAccountIndex: UInt32 = 0

    // MARK: - Build & Sign (and broadcast)

    /// Build, sign, and broadcast a transaction that sends `amount` duffs to
    /// `address` via the core `CoreTransactionBuilder`. Exposed as the existing
    /// `WalletSendService` two-step API so it keeps working without surgery into
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
    /// carry several outputs. Build + sign + broadcast via the same
    /// `CoreTransactionBuilder` path as the single-recipient variant.
    static func buildAndSign(recipients: [(address: String, amountDuffs: UInt64)]) throws -> (txData: Data, fee: UInt64, txHash: Data) {
        logger.info("💸 TXSEND :: building+signing+broadcasting \(recipients.count, privacy: .public) recipient(s) via PlatformWalletManager.coreWallet")

        let send = { @MainActor () throws -> Data in
            guard let wallet = SwiftDashSDKHost.shared.wallet else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            let core = try wallet.coreWallet()
            // Build + sign + broadcast a standard BIP44 payment via the core
            // TransactionBuilder. `setFunding` auto-selects inputs and routes
            // change to the account's next internal address (single tx — normal
            // sends don't need chunking).
            let builder = try CoreTransactionBuilder()
            for recipient in recipients {
                try builder.addOutput(address: recipient.address, amountDuffs: recipient.amountDuffs)
            }
            try builder.setFunding(wallet: core, accountType: .bip44, accountIndex: 0)
            let tx = try builder.buildSigned(wallet: core, accountType: .bip44, accountIndex: 0)
            _ = try core.broadcastTransaction(tx)
            return tx.data
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
    /// BIP44 receive address), fully emptying the CoinJoin account across one or
    /// more transactions.
    ///
    /// Orchestrated app-side over the core `CoreTransactionBuilder`: enumerate the
    /// CoinJoin account's UTXOs, split them into balanced ≤500-input chunks, and
    /// drain each chunk with `SelectionStrategy.all` (core computes
    /// output = Σinputs − fee with no change; `buildSigned` resolves both the
    /// external `/0/` and internal `/1/` signing paths), then broadcast. A heavy
    /// mixer therefore produces several transactions.
    ///
    /// Used by the post-migration "move your mixed coins" flow: CoinJoin is no
    /// longer supported, so we move the user's mixed coins into their normal
    /// spendable balance.
    ///
    /// - Parameter address: Destination Dash address (the user's own BIP44
    ///   receive address, resolved via `SwiftDashSDKReceiveAddressReader`).
    /// - Returns: The **wire-order** txids of the broadcast sweep transactions
    ///   (one per chunk) — ready to record in `CoinJoinWithdrawalStore`
    ///   (matches `Transaction.txHashData`).
    static func sweepCoinJoin(to address: String) throws -> [Data] {
        logger.info("💸 TXSEND :: sweeping CoinJoin account → spendable balance")

        let sweep = { @MainActor () throws -> [Data] in
            let host = SwiftDashSDKHost.shared
            guard let wallet = host.wallet, let manager = host.manager else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            let core = try wallet.coreWallet()
            let walletId = wallet.walletId

            // CoinJoin account-0 balance descriptor (mirrors
            // SwiftDashSDKCoinJoinBalanceReader: typeTag 1, index 0). Used only to
            // address the account for UTXO enumeration.
            guard let cjBalance = manager.accountBalances(for: walletId).first(where: {
                $0.typeTag == Self.coinJoinTypeTag && $0.index == Self.coinJoinAccountIndex
            }) else {
                return []
            }

            // Snapshot the account's spendable UTXOs (after the recovery scan has
            // materialized deep `/0/` + `/1/` addresses).
            let utxos = manager.accountUtxos(for: walletId, balance: cjBalance)
            guard !utxos.isEmpty else { return [] }

            // Drain each balanced ≤500-input chunk to `address`. `SelectionStrategy.all`
            // makes core compute output = Σinputs − fee with no change (the addOutput
            // amount is ignored); `buildSigned` resolves dual-chain `/0/`+`/1/` signing.
            // Partial-failure tolerant: keep the txs that broadcast, log the rest, and
            // throw only if nothing broadcast at all (a re-run sweeps the remainder).
            var txids: [Data] = []
            var firstError: Error?
            for (index, chunk) in Self.balancedChunks(utxos).enumerated() {
                do {
                    let builder = try CoreTransactionBuilder()
                    try builder.addInputs(
                        wallet: core, accountType: .coinJoin,
                        accountIndex: Self.coinJoinAccountIndex, utxos: chunk)
                    try builder.setSelectionStrategy(.all)
                    try builder.setFeeRate(satPerKb: Self.feeRateSatPerKb)
                    // No setCurrentHeight: build_signed sets the height from the
                    // wallet's last_processed_height, overriding anything set here.
                    try builder.addOutput(address: address, amountDuffs: 0)
                    let tx = try builder.buildSigned(
                        wallet: core, accountType: .coinJoin,
                        accountIndex: Self.coinJoinAccountIndex)
                    _ = try core.broadcastTransaction(tx)
                    // Wire (internal) byte order to match `Transaction.txHashData` /
                    // `CoinJoinWithdrawalStore`: `computeTxHash` yields display order,
                    // so reverse it back to wire order.
                    txids.append(Data(Self.computeTxHash(from: tx.data).reversed()))
                } catch {
                    firstError = firstError ?? error
                    Self.logger.error(
                        "💸 TXSEND :: coinjoin sweep chunk \(index + 1, privacy: .public) failed to broadcast, continuing: \(String(describing: error), privacy: .public)")
                }
            }
            if txids.isEmpty, let error = firstError { throw error }
            return txids
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

    /// Partition `utxos` into balanced chunks each ≤ `maxInputsPerSweep`,
    /// preserving order — app-side chunking (no upstream key-wallet counterpart):
    /// `ceil(n / 500)` near-equal chunks, so no chunk is a lone sub-fee input.
    /// Examples: 500 → [500]; 501 → [251, 250]; 1000 → [500, 500].
    private static func balancedChunks(
        _ utxos: [PlatformWalletManager.AccountUtxo]
    ) -> [[PlatformWalletManager.AccountUtxo]] {
        let n = utxos.count
        guard n > 0 else { return [] }
        let numChunks = (n + maxInputsPerSweep - 1) / maxInputsPerSweep // ceil(n / 500)
        let chunkSize = (n + numChunks - 1) / numChunks                  // ceil(n / numChunks)
        var chunks: [[PlatformWalletManager.AccountUtxo]] = []
        var start = 0
        while start < n {
            let end = min(start + chunkSize, n)
            chunks.append(Array(utxos[start..<end]))
            start = end
        }
        return chunks
    }

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
