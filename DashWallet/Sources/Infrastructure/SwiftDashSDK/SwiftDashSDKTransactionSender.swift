//
//  SwiftDashSDKTransactionSender.swift
//  DashWallet
//
//  Adapter around the SwiftDashSDK Core send path. Standard sends are a real
//  two-step: `buildAndSign` builds + signs via the core `CoreTransactionBuilder`
//  (setFunding → addOutput → buildSigned) and returns the held `CoreTransaction`;
//  nothing is broadcast until the explicit `broadcast(_:)` call — made when the
//  user confirms on the payment sheet, or immediately after build for
//  programmatic sends. Discarding a built-but-unconfirmed transaction is safe:
//  the build reserves no UTXOs (its only residue is one internal change-address
//  index advance, reclaimed by the gap-limit scan). The user has already
//  authenticated by the time the build path runs (PIN auth fires in
//  `WalletSendService.prepareStandardSendForConfirmation`), and the
//  payment-output broadcast path stamps `alreadyAuthorized` so it doesn't
//  re-prompt.
//
//  The selected-input (CrowdNode) and CoinJoin-sweep paths below broadcast
//  inline — post-auth programmatic flows with no confirmation UI.
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

    // MARK: - Selected-input send constants

    /// `AccountBalance.typeTag` discriminant for the Standard account family.
    private static let bip44TypeTag: UInt8 = 0
    /// `AccountBalance.standardTag` discriminant for BIP44 within Standard.
    private static let bip44StandardTag: UInt8 = 0
    /// Signal sends spend from the primary BIP44 account.
    private static let bip44AccountIndex: UInt32 = 0
    /// How long to wait for a just-broadcast funding output to appear in the
    /// SDK's UTXO set (the local mempool apply is async relative to
    /// `broadcastTransaction` returning).
    private static let selectedInputUtxoTimeout: TimeInterval = 30
    /// Poll interval for the UTXO wait above.
    private static let selectedInputPollInterval: TimeInterval = 0.5

    // MARK: - Build & Sign

    /// Build and sign a transaction that sends `amount` duffs to `address` via
    /// the core `CoreTransactionBuilder`. Nothing is broadcast — pass the
    /// returned `CoreTransaction` to `broadcast(_:)` once the send is confirmed.
    ///
    /// - Parameters:
    ///   - address: Destination Dash address (Base58Check).
    ///   - amount: Amount to send in duffs (1 DASH = 100_000_000 duffs).
    /// - Returns: Tuple of (the built transaction — carries the serialized bytes
    ///   in `.data` and the exact FFI fee in `.fee`, 32-byte display-order txHash).
    static func buildAndSign(address: String, amount: UInt64) throws -> (tx: CoreTransaction, txHash: Data) {
        try buildAndSign(recipients: [(address: address, amountDuffs: amount)])
    }

    /// Multi-recipient variant — used by the app-side BIP70 send, where a merchant request may
    /// carry several outputs. Build + sign via the same `CoreTransactionBuilder`
    /// path as the single-recipient variant; broadcast is deferred to `broadcast(_:)`.
    static func buildAndSign(recipients: [(address: String, amountDuffs: UInt64)]) throws -> (tx: CoreTransaction, txHash: Data) {
        logger.info("💸 TXSEND :: building+signing \(recipients.count, privacy: .public) recipient(s) via PlatformWalletManager.coreWallet")

        let build = { @MainActor () throws -> CoreTransaction in
            guard let wallet = SwiftDashSDKHost.shared.wallet,
                  let network = SwiftDashSDKHost.shared.runningNetwork else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            // Build + sign a standard BIP44 payment via the core
            // TransactionBuilder. `setFunding` auto-selects inputs and routes
            // change to the account's next internal address (single tx — normal
            // sends don't need chunking).
            let builder = try CoreTransactionBuilder(network: network)
            for recipient in recipients {
                try builder.addOutput(address: recipient.address, amountDuffs: recipient.amountDuffs)
            }
            try builder.setFunding(wallet: wallet, accountType: .bip44, accountIndex: 0)
            return try builder.buildSigned(wallet: wallet, accountType: .bip44, accountIndex: 0)
        }

        let tx: CoreTransaction
        if Thread.isMainThread {
            tx = try MainActor.assumeIsolated { try build() }
        } else {
            var captured: Result<CoreTransaction, Error> = .failure(SendError.walletNotReady("uninitialized result"))
            DispatchQueue.main.sync {
                captured = Result { try MainActor.assumeIsolated { try build() } }
            }
            tx = try captured.get()
        }

        let txHash = computeTxHash(from: tx.data)
        logger.info("💸 TXSEND :: built+signed — txHash=\(txHash.map { String(format: "%02x", $0) }.joined(), privacy: .public) fee=\(tx.fee, privacy: .public) duffs size=\(tx.data.count, privacy: .public) bytes")
        return (tx, txHash)
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
    ///   (matches `Transaction.txHashData`) — plus the net duffs delivered to
    ///   `address` (Σ chunk inputs − Σ chunk fees, broadcast chunks only). The
    ///   CoinJoin → Shielded flow locks exactly this net amount afterwards.
    static func sweepCoinJoin(to address: String) throws -> (txids: [Data], netDuffs: UInt64) {
        logger.info("💸 TXSEND :: sweeping CoinJoin account → spendable balance")

        let sweep = { @MainActor () throws -> (txids: [Data], netDuffs: UInt64) in
            let host = SwiftDashSDKHost.shared
            guard let wallet = host.wallet, let manager = host.manager,
                  let network = host.runningNetwork else {
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
                return ([], 0)
            }

            // Snapshot the account's spendable UTXOs (after the recovery scan has
            // materialized deep `/0/` + `/1/` addresses).
            let utxos = manager.accountUtxos(for: walletId, balance: cjBalance)
            guard !utxos.isEmpty else { return ([], 0) }

            // Drain each balanced ≤500-input chunk to `address`. `SelectionStrategy.all`
            // makes core compute output = Σinputs − fee with no change (the addOutput
            // amount is ignored); `buildSigned` resolves dual-chain `/0/`+`/1/` signing.
            // Partial-failure tolerant: keep the txs that broadcast, log the rest, and
            // throw only if nothing broadcast at all (a re-run sweeps the remainder).
            var txids: [Data] = []
            var netDuffs: UInt64 = 0
            var firstError: Error?
            for (index, chunk) in Self.balancedChunks(utxos).enumerated() {
                do {
                    let builder = try CoreTransactionBuilder(network: network)
                    try builder.addInputs(
                        wallet: wallet, accountType: .coinJoin,
                        accountIndex: Self.coinJoinAccountIndex, utxos: chunk)
                    try builder.setSelectionStrategy(.all)
                    try builder.setFeeRate(satPerKb: Self.feeRateSatPerKb)
                    // No setCurrentHeight: build_signed sets the height from the
                    // wallet's last_processed_height, overriding anything set here.
                    try builder.addOutput(address: address, amountDuffs: 0)
                    let tx = try builder.buildSigned(
                        wallet: wallet, accountType: .coinJoin,
                        accountIndex: Self.coinJoinAccountIndex)
                    _ = try core.broadcastTransaction(tx)
                    // Wire (internal) byte order to match `Transaction.txHashData` /
                    // `CoinJoinWithdrawalStore`: `computeTxHash` yields display order,
                    // so reverse it back to wire order.
                    txids.append(Data(Self.computeTxHash(from: tx.data).reversed()))
                    // `.all` drain: single output = Σ chunk inputs − exact fee.
                    let chunkInputs = chunk.reduce(UInt64(0)) { $0 + $1.valueDuffs }
                    netDuffs += chunkInputs > tx.fee ? chunkInputs - tx.fee : 0
                } catch {
                    firstError = firstError ?? error
                    Self.logger.error(
                        "💸 TXSEND :: coinjoin sweep chunk \(index + 1, privacy: .public) failed to broadcast, continuing: \(String(describing: error), privacy: .public)")
                }
            }
            if txids.isEmpty, let error = firstError { throw error }
            return (txids, netDuffs)
        }

        let result: (txids: [Data], netDuffs: UInt64)
        if Thread.isMainThread {
            result = try MainActor.assumeIsolated { try sweep() }
        } else {
            var captured: Result<(txids: [Data], netDuffs: UInt64), Error> =
                .failure(SendError.walletNotReady("uninitialized result"))
            DispatchQueue.main.sync {
                captured = Result { try MainActor.assumeIsolated { try sweep() } }
            }
            result = try captured.get()
        }

        // Log display-order hex (byte-reversed wire order) to match explorers.
        let hexes = result.txids.map { txid -> String in
            Data(txid.reversed()).map { String(format: "%02x", $0) }.joined()
        }
        logger.info("💸 TXSEND :: coinjoin sweep broadcast — \(result.txids.count, privacy: .public) tx(s), net \(result.netDuffs, privacy: .public) duffs: \(hexes.joined(separator: ","), privacy: .public)")
        return result
    }

    /// Wait for the BIP44 account-0 UTXOs sitting on `address` to reach
    /// `minimumTotal` duffs, tolerating the SDK's async local-mempool apply of
    /// just-broadcast transactions (same polling contract as the selected-input
    /// send). Returns the observed total (which may be below `minimumTotal` if
    /// the timeout elapsed — the caller decides sufficiency).
    ///
    /// Used by the CoinJoin → Shielded flow to wait for the sweep's outputs to
    /// become spendable before funding the shield asset lock from them.
    static func waitForFunds(onAddress address: String, minimumTotal: UInt64) async throws -> UInt64 {
        let network: PaymentNetwork
        do {
            network = try PaymentNetworkResolver.current()
        } catch {
            throw SendError.walletNotReady("unsupported network for UTXO wait")
        }
        guard let script = ScriptAddressCodec.scriptPubKey(forAddress: address, network: network) else {
            throw SendError.invalidInput("cannot derive scriptPubKey for the address")
        }
        let utxos = try await waitForAddressUtxos(script: script, minimumTotal: minimumTotal)
        return utxos.reduce(UInt64(0)) { $0 + $1.valueDuffs }
    }

    // MARK: - Selected-input send (CrowdNode signal txs)

    /// Build, sign, and broadcast a transaction funded ONLY from UTXOs sitting
    /// on `fromAddress`, with change returned to `fromAddress`.
    ///
    /// SwiftDashSDK replacement for the retired DashSync
    /// `LegacySelectedInputSendExecutor`. CrowdNode identifies the user by the
    /// address its signal transactions originate from, so both the inputs and
    /// the change must stay on the account address, and the destination output
    /// must carry the exact signal amount (`apiOffset + ApiCode`).
    ///
    /// Semantic delta vs legacy: the legacy path spent ALL outputs of specific
    /// candidate transactions matching the address; this path spends from the
    /// address's current UTXO pool. Same sender address, change back to it —
    /// the CrowdNode-visible semantics hold.
    ///
    /// Freshness: signup/deposit spend a just-broadcast top-up output. The SDK
    /// applies its own broadcasts to the local mempool asynchronously (0-conf
    /// outputs are spendable once applied), so the UTXO set is polled until
    /// the required funds appear or `selectedInputUtxoTimeout` elapses.
    ///
    /// - Parameters:
    ///   - fromAddress: The address whose UTXOs fund the send and receive the change.
    ///   - address: Destination Dash address (Base58Check).
    ///   - amount: Amount to send in duffs — passed through untouched unless
    ///     `adjustAmountDownwards` fires.
    ///   - adjustAmountDownwards: Mirror of the legacy executor's single retry:
    ///     when the address balance can't cover `amount + fee`, send
    ///     `amount − fee` instead (used by the confirmation-forward).
    /// - Returns: Tuple of (serialized signed tx bytes, exact fee in duffs, 32-byte txHash).
    static func buildAndSignFromAddress(
        fromAddress: String,
        to address: String,
        amount: UInt64,
        adjustAmountDownwards: Bool
    ) async throws -> (txData: Data, fee: UInt64, txHash: Data) {
        logger.info("💸 TXSEND :: selected-input send — amount=\(amount, privacy: .public) adjust=\(adjustAmountDownwards, privacy: .public)")

        // Resolve the sender address to its P2PKH/P2SH script for byte-exact
        // UTXO matching (`AccountUtxo` carries scriptPubkey, not an address).
        // The resolver keeps this file free of DashSync imports.
        let network: PaymentNetwork
        do {
            network = try PaymentNetworkResolver.current()
        } catch {
            throw SendError.walletNotReady("unsupported network for selected-input send")
        }
        guard let script = ScriptAddressCodec.scriptPubKey(forAddress: fromAddress, network: network) else {
            throw SendError.invalidInput("cannot derive scriptPubKey for the funding address")
        }

        // Wait for the address's UTXOs to cover the send (tolerates the async
        // mempool apply of a just-broadcast top-up). For adjust-downwards sends
        // any funds at all are workable — the amount shrinks to fit.
        let minimumTotal = adjustAmountDownwards ? 1 : amount + estimatedSignalFee(inputCount: 1)
        let utxos = try await waitForAddressUtxos(script: script, minimumTotal: minimumTotal)

        // Deterministic legacy-parity pre-adjust: same size-based estimate as
        // `chain.fee(forTxSize:)` at the relay-minimum rate, single-shot
        // adjustment exactly like the legacy executor's one retry. `.all`
        // drain is deliberately avoided — it would over-send whenever the
        // address balance exceeds the signal amount.
        let selected = utxos.reduce(UInt64(0)) { $0 + $1.valueDuffs }
        let feeEstimate = estimatedSignalFee(inputCount: utxos.count)
        let adjusted = amount + feeEstimate > selected
        if adjusted, !(adjustAmountDownwards && amount > feeEstimate) {
            throw SendError.insufficientSelectedFunds(selected: selected, amount: amount, fee: feeEstimate)
        }
        let sendAmount = adjusted ? amount - feeEstimate : amount

        let (txData, exactFee): (Data, UInt64) = try await MainActor.run {
            guard let wallet = SwiftDashSDKHost.shared.wallet,
                  let network = SwiftDashSDKHost.shared.runningNetwork else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            let core = try wallet.coreWallet()
            let builder = try CoreTransactionBuilder(network: network)
            try builder.addInputs(
                wallet: wallet, accountType: .bip44,
                accountIndex: Self.bip44AccountIndex, utxos: utxos)
            try builder.addOutput(address: address, amountDuffs: sendAmount)
            // Required with `addInputs` (`setFunding` is what normally routes
            // change) — and the change MUST return to the sender address so
            // CrowdNode keeps recognizing the account.
            try builder.setChangeAddress(fromAddress)
            try builder.setFeeRate(satPerKb: Self.feeRateSatPerKb)
            let tx = try builder.buildSigned(
                wallet: wallet, accountType: .bip44, accountIndex: Self.bip44AccountIndex)
            _ = try core.broadcastTransaction(tx)
            return (tx.data, tx.fee)
        }

        let txHash = computeTxHash(from: txData)
        logger.info("💸 TXSEND :: selected-input send broadcast — txHash=\(txHash.map { String(format: "%02x", $0) }.joined(), privacy: .public) fee=\(exactFee, privacy: .public) adjusted=\(adjusted, privacy: .public) inputs=\(utxos.count, privacy: .public)")
        return (txData, exactFee, txHash)
    }

    /// The BIP44 account-0 UTXOs sitting on `script`, unlocked only.
    /// Byte-exact scriptPubkey compare — no per-UTXO address decoding.
    @MainActor
    private static func addressUtxos(script: Data) throws -> [PlatformWalletManager.AccountUtxo] {
        let host = SwiftDashSDKHost.shared
        guard let wallet = host.wallet, let manager = host.manager else {
            throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
        }
        // BIP44 account-0 balance descriptor (mirrors the sweep's CoinJoin
        // descriptor resolution above).
        guard let bip44 = manager.accountBalances(for: wallet.walletId).first(where: {
            $0.typeTag == Self.bip44TypeTag
                && $0.standardTag == Self.bip44StandardTag
                && $0.index == Self.bip44AccountIndex
        }) else {
            return []
        }
        return manager.accountUtxos(for: wallet.walletId, balance: bip44)
            .filter { !$0.isLocked && $0.scriptPubkey == script }
    }

    /// Poll `addressUtxos` until their sum covers `minimumTotal` or the
    /// timeout elapses; returns the last snapshot either way (the caller
    /// decides insufficiency). Sleeps off-main between polls.
    private static func waitForAddressUtxos(
        script: Data, minimumTotal: UInt64
    ) async throws -> [PlatformWalletManager.AccountUtxo] {
        let deadline = Date().addingTimeInterval(selectedInputUtxoTimeout)
        var polls = 0
        while true {
            polls += 1
            let utxos = try await MainActor.run { try addressUtxos(script: script) }
            let total = utxos.reduce(UInt64(0)) { $0 + $1.valueDuffs }
            if total >= minimumTotal || Date() >= deadline {
                logger.info("💸 TXSEND :: selected-input UTXO wait — polls=\(polls, privacy: .public) utxos=\(utxos.count, privacy: .public) total=\(total, privacy: .public) needed=\(minimumTotal, privacy: .public)")
                return utxos
            }
            try await Task.sleep(nanoseconds: UInt64(selectedInputPollInterval * 1_000_000_000))
        }
    }

    /// Size-based fee estimate for a signal send at the relay-minimum
    /// 1 duff/byte: base 10 + 148/input + 34 × 2 outputs (dest + change).
    /// Mirrors the legacy `chain.fee(forTxSize: tx.size + TX_OUTPUT_SIZE)`.
    private static func estimatedSignalFee(inputCount: Int) -> UInt64 {
        UInt64(10 + inputCount * 148 + 2 * 34)
    }

    // MARK: - Broadcast

    /// Broadcast a transaction previously built by `buildAndSign`. Resolves the
    /// core wallet fresh at call time (never cached in the prepared object) and
    /// submits the held `CoreTransaction`'s bytes to the network.
    ///
    /// - Parameter tx: The built transaction returned by `buildAndSign`.
    /// - Returns: The txid string reported by the SDK.
    @discardableResult
    static func broadcast(_ tx: CoreTransaction) throws -> String {
        let submit = { @MainActor () throws -> String in
            guard let wallet = SwiftDashSDKHost.shared.wallet else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            let core = try wallet.coreWallet()
            return try core.broadcastTransaction(tx)
        }

        let txid: String
        if Thread.isMainThread {
            txid = try MainActor.assumeIsolated { try submit() }
        } else {
            var captured: Result<String, Error> = .failure(SendError.walletNotReady("uninitialized result"))
            DispatchQueue.main.sync {
                captured = Result { try MainActor.assumeIsolated { try submit() } }
            }
            txid = try captured.get()
        }

        // Log both: the SDK-reported txid string and the app-computed
        // display-order hash (the SDK string's byte order is unverified).
        let displayHash = computeTxHash(from: tx.data).map { String(format: "%02x", $0) }.joined()
        logger.info("💸 TXSEND :: broadcast — sdkTxid=\(txid, privacy: .public) txHash=\(displayHash, privacy: .public)")
        return txid
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
        case insufficientSelectedFunds(selected: UInt64, amount: UInt64, fee: UInt64)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let reason):
                return "Invalid transaction input: \(reason)"
            case .walletNotReady(let reason):
                return "Wallet not ready: \(reason)"
            case .insufficientSelectedFunds(let selected, let amount, let fee):
                return "Not enough funds. Selected: \(selected), Amount: \(amount), Fee: \(fee)"
            }
        }
    }
}
