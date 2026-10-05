//
//  SwiftDashSDKTransactionSender.swift
//  DashWallet
//
//  Adapter around the SwiftDashSDK Core send path. Standard sends are a real
//  two-step: `buildAndSign` builds + signs via the core `CoreTransactionBuilder`
//  (addOutput → finalizeAtomic) and returns the held `FinalizedCoreTransaction`;
//  nothing is broadcast until the explicit `broadcast(_:)` call — made when the
//  user confirms on the payment sheet, or immediately after build for
//  programmatic sends. The atomic finalize selects AND reserves the funding
//  UTXOs in one native operation (no funding/signing race with a concurrent
//  build), so discarding a built-but-unconfirmed transaction is still safe:
//  releasing the handle abandons it Rust-side and returns the reserved inputs
//  to spendable. The user has already authenticated by the time the build path
//  runs (PIN auth fires in
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

    // 💸 TXSEND lines go through `DWLogger`, so they reach the "Share
    // application logs" export; an `os.Logger` line never does.

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
    /// MAYACHAIN memo standardness limit for OP_RETURN payloads.
    private static let maxSwapMemoBytes = 80

    // MARK: - Selected-input send constants

    /// `AccountBalance.typeTag` discriminant for the Standard account family.
    private static let bip44TypeTag: UInt8 = 0
    /// `AccountBalance.standardTag` discriminant for BIP44 within Standard.
    private static let bip44StandardTag: UInt8 = 0
    /// `StandardAccountTypeTagFFI.Bip32` — the other half of the Standard
    /// family that `.allSpendable` pools.
    private static let bip32StandardTag: UInt8 = 1
    /// `AccountTypeTagFFI.DashpayReceivingFunds`. Its sibling tag 13
    /// (`DashpayExternalAccount`) is a contact's watch-only coins and is NOT
    /// pooled — the local seed cannot sign them.
    private static let dashpayReceivingTypeTag: UInt8 = 12
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
    /// returned `FinalizedCoreTransaction` to `broadcast(_:)` once the send is
    /// confirmed; discarding it abandons the build and releases its reserved
    /// inputs.
    ///
    /// - Parameters:
    ///   - address: Destination Dash address (Base58Check).
    ///   - amount: Amount to send in duffs (1 DASH = 100_000_000 duffs).
    /// - Returns: Tuple of (the finalized transaction handle — exposes the
    ///   serialized bytes via `serializedData()` and the exact FFI fee in
    ///   `.fee`, 32-byte display-order txHash).
    static func buildAndSign(address: String, amount: UInt64) throws -> (tx: FinalizedCoreTransaction, txHash: Data, walletId: Data) {
        try buildAndSign(recipients: [(address: address, amountDuffs: amount)])
    }

    /// Multi-recipient variant — used by the app-side BIP70 send, where a merchant request may
    /// carry several outputs. Build + sign via the same `CoreTransactionBuilder`
    /// path as the single-recipient variant; broadcast is deferred to `broadcast(_:)`.
    ///
    /// - Returns: also the id of the wallet that signed, read in the same
    ///   main-actor hop as the build, so an outcome is booked under it.
    static func buildAndSign(recipients: [(address: String, amountDuffs: UInt64)]) throws -> (tx: FinalizedCoreTransaction, txHash: Data, walletId: Data) {
        DWLogger.log("💸 TXSEND :: building+signing \(recipients.count) recipient(s) via PlatformWalletManager.coreWallet")

        let build = { @MainActor () throws -> (FinalizedCoreTransaction, Data) in
            guard let wallet = SwiftDashSDKHost.shared.wallet,
                  let network = SwiftDashSDKHost.shared.runningNetwork else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            // Build + sign a standard payment via the core
            // TransactionBuilder. `finalizeAtomic` selects + reserves the
            // inputs and routes change to the account's next internal address
            // in one native operation (single tx — normal sends don't need
            // chunking).
            let builder = try CoreTransactionBuilder(network: network)
            for recipient in recipients {
                try builder.addOutput(address: recipient.address, amountDuffs: recipient.amountDuffs)
            }
            // `.allSpendable` pools BIP44 + BIP32 + every DashPay
            // contact-receiving account — the same set the home balance
            // already totals, so a send can spend everything the user is
            // shown. CoinJoin is excluded by construction (spending mixed
            // outputs beside transparent ones would undo the mixing), as are
            // a contact's watch-only external coins. Change returns to BIP44,
            // the first pooled source.
            return (try builder.finalizeAtomic(wallet: wallet, accountType: .allSpendable), wallet.walletId)
        }

        let (tx, walletId) = try MainThread.sync(build)

        let txData = try tx.serializedData()
        let txHash = computeTxHash(from: txData)
        DWLogger.log("💸 TXSEND :: built+signed — txHash=\(txHash.map { String(format: "%02x", $0) }.joined()) fee=\(tx.fee) duffs size=\(txData.count) bytes")
        return (tx, txHash, walletId)
    }

    /// Build + sign a MAYACHAIN-style swap deposit: vault payment at VOUT0, a zero-value
    /// OP_RETURN memo at VOUT1, and change returned to VIN0 when change exists.
    /// Nothing is broadcast — pass the result to `broadcast(_:)`.
    static func buildAndSignSwapDeposit(
        vaultAddress: String,
        amountDuffs: UInt64,
        memo: String
    ) throws -> (tx: FinalizedCoreTransaction, txHash: Data, walletId: Data) {
        let memoData = Data(memo.utf8)
        guard memoData.count <= Self.maxSwapMemoBytes else {
            throw SendError.invalidSwapMemo("Swap memo is too long. Please refresh and try again.")
        }

        DWLogger.log("💸 TXSEND :: building+signing MAYA swap deposit via PlatformWalletManager.coreWallet")

        let build = { @MainActor () throws -> (tx: FinalizedCoreTransaction, network: Network, walletId: Data) in
            guard let wallet = SwiftDashSDKHost.shared.wallet,
                  let network = SwiftDashSDKHost.shared.runningNetwork else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }

            let builder = try CoreTransactionBuilder(network: network)
            try builder.addOutput(address: vaultAddress, amountDuffs: amountDuffs)
            try builder.addOpReturn(memoData)
            try builder.preserveOutputOrder()
            try builder.changeToFirstInput()
            // Same pooled funding as a plain send — see `buildAndSign`.
            // `changeToFirstInput` stays correct under pooling: it routes to
            // whichever input BIP-69 puts at VIN0, whatever account it came
            // from, and the builder sizes the change output for the largest
            // eligible routing script.
            let tx = try builder.finalizeAtomic(wallet: wallet, accountType: .allSpendable)
            return (tx, network, wallet.walletId)
        }

        let built = try MainThread.sync(build)

        let txData = try built.tx.serializedData()
        try assertSwapDepositShape(
            txData: txData,
            feeDuffs: built.tx.fee,
            network: built.network,
            vaultAddress: vaultAddress,
            amountDuffs: amountDuffs,
            memoData: memoData
        )

        let txHash = computeTxHash(from: txData)
        DWLogger.log("💸 TXSEND :: built+signed MAYA swap deposit — txHash=\(txHash.map { String(format: "%02x", $0) }.joined()) fee=\(built.tx.fee) duffs size=\(txData.count) bytes")
        return (built.tx, txHash, built.walletId)
    }

    // MARK: - CoinJoin Sweep

    /// Outcome of a chunked CoinJoin sweep.
    ///
    /// Each chunk is an independent transaction, so a sweep can end up partly
    /// done: some chunks broadcast while another fails to build, sign or
    /// broadcast. The txids alone cannot express that — a caller that only sees
    /// a non-empty array reports "your mixed coins were moved" while the failed
    /// chunks are still sitting in the CoinJoin account. So the failure travels
    /// with them, and the caller records the accepted transactions *and* still
    /// surfaces the partial state.
    struct CoinJoinSweepOutcome {
        /// Wire-order txids of the chunks that broadcast, in chunk order —
        /// ready to record in `CoinJoinWithdrawalStore` (matches
        /// `Transaction.txHashData`).
        let txids: [Data]
        /// How many chunks did not broadcast.
        let failedChunkCount: Int
        /// The first failed chunk's error; nil when every chunk broadcast.
        let firstFailure: Error?
        /// Chunks never attempted because the swept wallet stopped running on
        /// the swept network first — a wallet or network switch, a wipe, or a
        /// restart of the same wallet. Not counted in `failedChunkCount`; the
        /// caller tells the cases apart by whether the swept wallet is still
        /// the selected one.
        let unattemptedChunkCount: Int

        /// Some chunks broadcast and some did not: coins remain in the CoinJoin
        /// account, and a re-run sweeps the remainder.
        var isPartial: Bool { !txids.isEmpty && failedChunkCount + unattemptedChunkCount > 0 }
    }

    /// Sweep the entire CoinJoin-account balance to `address` (the user's own
    /// BIP44 receive address), fully emptying the CoinJoin account across one or
    /// more transactions.
    ///
    /// Orchestrated app-side over the core `CoreTransactionBuilder`: enumerate the
    /// CoinJoin account's UTXOs, split them into balanced ≤500-input chunks, and
    /// drain each chunk with `SelectionStrategy.all` (core computes
    /// output = Σinputs − fee with no change; `finalizeAtomic` resolves both the
    /// external `/0/` and internal `/1/` signing paths), then broadcast. A heavy
    /// mixer therefore produces several transactions.
    ///
    /// Used by the post-migration "move your mixed coins" flow: CoinJoin is no
    /// longer supported, so we move the user's mixed coins into their normal
    /// spendable balance.
    ///
    /// - Parameters:
    ///   - address: Destination Dash address (the user's own BIP44 receive
    ///     address, from `SwiftDashSDKReceiveAddressReader.receiveDestination()`).
    ///   - walletId: The wallet `address` was read from.
    ///   - network: The network `address` belongs to. The sweep refuses to
    ///     start on any other wallet or network, so its coins never go to
    ///     another wallet's address.
    /// - Returns: A `CoinJoinSweepOutcome` carrying the broadcast chunks' txids,
    ///   any chunk failure, and the chunks a wallet change left unattempted.
    ///   Throws when the wallet or network no longer matches before the first
    ///   chunk, or when every attempted chunk failed and none was left
    ///   unattempted.
    static func sweepCoinJoin(
        to address: String, ofWallet walletId: Data, on network: Network
    ) throws -> CoinJoinSweepOutcome {
        assert(!Thread.isMainThread, "sweepCoinJoin waits for network acceptance of every chunk")
        DWLogger.log("💸 TXSEND :: sweeping CoinJoin account → spendable balance")

        // The host, the manager and its account reads are main-actor state, so
        // the snapshot is taken there. Everything after it stays on this thread.
        let utxos = try MainThread.sync { () throws -> [PlatformWalletManager.AccountUtxo] in
            let host = SwiftDashSDKHost.shared
            guard let wallet = host.wallet, let manager = host.manager else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            guard wallet.walletId == walletId, host.runningNetwork == network else {
                throw SendError.walletNotReady("the destination address belongs to another wallet or network")
            }

            // CoinJoin account-0 balance descriptor (mirrors
            // SwiftDashSDKCoinJoinBalanceReader: typeTag 1, index 0). Used only to
            // address the account for UTXO enumeration.
            guard let cjBalance = manager.accountBalances(for: wallet.walletId).first(where: {
                $0.typeTag == Self.coinJoinTypeTag && $0.index == Self.coinJoinAccountIndex
            }) else {
                return []
            }

            // Snapshot the account's spendable UTXOs (after the recovery scan has
            // materialized deep `/0/` + `/1/` addresses).
            return manager.accountUtxos(for: wallet.walletId, balance: cjBalance)
        }

        // Drain each balanced ≤500-input chunk to `address`. `useOnlyAddedInputs`
        // is what makes the chunk the transaction's input set — the finalizer
        // otherwise funds from the whole account regardless of what was seeded.
        // `SelectionStrategy.all` makes core compute output = Σinputs − fee with
        // no change (the addOutput amount is ignored); `finalizeAtomic` resolves
        // dual-chain `/0/`+`/1/` signing.
        let outcome = try sweepChunks(
            Self.balancedChunks(utxos),
            // Re-resolved per chunk: a restart of the same wallet publishes a new
            // handle, and the old one belongs to a stopped manager. The network
            // is checked with the id because the chunks' destination and
            // `network` were fixed when the sweep started.
            runningWallet: {
                MainThread.sync { () -> ManagedPlatformWallet? in
                    let host = SwiftDashSDKHost.shared
                    guard host.runningNetwork == network, let wallet = host.wallet,
                          wallet.walletId == walletId else { return nil }
                    return wallet
                }
            },
            broadcast: { chunk, wallet in
                let builder = try CoreTransactionBuilder(network: network)
                try builder.addInputs(
                    wallet: wallet, accountType: .coinJoin,
                    accountIndex: Self.coinJoinAccountIndex, utxos: chunk)
                // Without this the finalizer adds every unreserved UTXO of
                // the account on top of the chunk and `.all` takes the lot,
                // so the chunking below has no effect and an account over
                // the input cap fails on every chunk and every retry.
                try builder.useOnlyAddedInputs()
                try builder.setSelectionStrategy(.all)
                try builder.setFeeRate(satPerKb: Self.feeRateSatPerKb)
                // No setCurrentHeight: the finalizer sets the height from the
                // wallet's last_processed_height, overriding anything set here.
                try builder.addOutput(address: address, amountDuffs: 0)
                let tx = try builder.finalizeAtomic(
                    wallet: wallet, accountType: .coinJoin,
                    accountIndex: Self.coinJoinAccountIndex)
                // Serialize BEFORE broadcast — broadcasting consumes the handle.
                let txData = try tx.serializedData()
                // Wire (internal) byte order to match `Transaction.txHashData` /
                // `CoinJoinWithdrawalStore`: `computeTxHash` yields display order,
                // so reverse it back to wire order.
                let txidWire = Data(Self.computeTxHash(from: txData).reversed())
                let outcome = try wallet.coreWallet().broadcastTransactionWithOutcome(tx)
                do {
                    _ = try Self.requireAccepted(outcome)
                } catch SendError.transactionStatusUnknown(_, let reason, _) {
                    // No answer is not a failure: the chunk may well have gone
                    // out. It counts as sent (grouped with the sweep's other
                    // transactions) and its row reads "Waiting for the network"
                    // until it is locked or mined. It is a move within the wallet, not a payment:
                    // no repeat warning keys on it and it settles without the
                    // "went through" notice.
                    let amount = chunk.reduce(UInt64(0)) { $0 + $1.valueDuffs }
                    let followed = MainThread.sync {
                        PendingSendOutcomes.shared.recordUnknownOutcome(
                            txidWire: txidWire, address: nil, amount: amount, notifies: false, walletId: walletId)
                    }
                    DWLogger.log("💸 TXSEND :: coinjoin sweep chunk outcome unknown (\(reason)); followed=\(followed)")
                }
                return txidWire
            })

        // Log display-order hex (byte-reversed wire order) to match explorers.
        let hexes = outcome.txids.map { txid -> String in
            Data(txid.reversed()).map { String(format: "%02x", $0) }.joined()
        }
        DWLogger.log("💸 TXSEND :: coinjoin sweep broadcast — \(outcome.txids.count) tx(s), \(outcome.failedChunkCount) chunk(s) failed, \(outcome.unattemptedChunkCount) not attempted: \(hexes.joined(separator: ","))")
        return outcome
    }

    /// The chunk loop of `sweepCoinJoin`: broadcast each chunk with the swept
    /// wallet while it still runs, and stop at the first chunk it no longer
    /// does — the remaining chunks count as unattempted, the accepted ones
    /// keep their txids. Partial-failure tolerant: a chunk that fails is
    /// counted and the loop goes on, and it throws only if nothing broadcast
    /// and nothing was left unattempted (a re-run sweeps the remainder).
    ///
    /// - Parameters:
    ///   - runningWallet: the swept wallet's current handle, or nil once it
    ///     no longer runs on the swept network; asked before every chunk.
    ///   - broadcast: builds, signs and broadcasts one chunk; returns its
    ///     wire-order txid once the network accepted it.
    static func sweepChunks<Chunk, Wallet>(
        _ chunks: [Chunk],
        runningWallet: () -> Wallet?,
        broadcast: (Chunk, Wallet) throws -> Data
    ) throws -> CoinJoinSweepOutcome {
        var txids: [Data] = []
        var failedChunkCount = 0
        var firstError: Error?
        var unattemptedChunkCount = 0
        for (index, chunk) in chunks.enumerated() {
            guard let wallet = runningWallet() else {
                unattemptedChunkCount = chunks.count - index
                DWLogger.logError(
                    "💸 TXSEND :: coinjoin sweep stopped before chunk \(index + 1) of \(chunks.count): its wallet or network is no longer running")
                break
            }
            do {
                txids.append(try broadcast(chunk, wallet))
            } catch {
                failedChunkCount += 1
                firstError = firstError ?? error
                DWLogger.logError(
                    "💸 TXSEND :: coinjoin sweep chunk \(index + 1) failed to broadcast, continuing: \(String(describing: error))")
            }
        }
        if txids.isEmpty, unattemptedChunkCount == 0, let error = firstError { throw error }
        return CoinJoinSweepOutcome(
            txids: txids, failedChunkCount: failedChunkCount,
            firstFailure: firstError, unattemptedChunkCount: unattemptedChunkCount)
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
        adjustAmountDownwards: Bool,
        holdingRouting: Bool
    ) async throws -> (txData: Data, fee: UInt64, txHash: Data) {
        DWLogger.log("💸 TXSEND :: selected-input send — amount=\(amount) adjust=\(adjustAmountDownwards)")

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

        // Only the host lookup needs the main actor. The build is small (the
        // address's few UTXOs); the broadcast runs on a background queue
        // through the same wallet that signed.
        let (wallet, coreNetwork) = try await MainActor.run { () throws -> (ManagedPlatformWallet, Network) in
            guard let wallet = SwiftDashSDKHost.shared.wallet,
                  let network = SwiftDashSDKHost.shared.runningNetwork else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            return (wallet, network)
        }
        let builder = try CoreTransactionBuilder(network: coreNetwork)
        try builder.addInputs(
            wallet: wallet, accountType: .bip44,
            accountIndex: Self.bip44AccountIndex, utxos: utxos)
        try builder.addOutput(address: address, amountDuffs: sendAmount)
        // Required with `addInputs` (funding selection is what normally
        // routes change) — and the change MUST return to the sender address
        // so CrowdNode keeps recognizing the account.
        try builder.setChangeAddress(fromAddress)
        try builder.setFeeRate(satPerKb: Self.feeRateSatPerKb)
        let tx = try builder.finalizeAtomic(
            wallet: wallet, accountType: .bip44, accountIndex: Self.bip44AccountIndex)
        // Serialize BEFORE broadcast — broadcasting consumes the handle.
        let txData = try tx.serializedData()
        let exactFee = tx.fee
        let txHash = computeTxHash(from: txData)
        do {
            // CrowdNode, the only caller today, runs unheld
            // (`WalletSendService.sendWithoutRoutingHold`).
            _ = try Self.requireAccepted(try await waitingForNetwork(holdingRouting: holdingRouting) { try submit(tx, through: wallet) })
        } catch SendError.transactionStatusUnknown(_, let reason, _) {
            // Carry the app-computed hash (display order, as every other route
            // reports it) and the wallet that signed, so the caller can follow
            // the send by its txid under that wallet.
            throw SendError.transactionStatusUnknown(
                txid: txHash.map { String(format: "%02x", $0) }.joined(), reason: reason, walletId: wallet.walletId)
        }

        DWLogger.log("💸 TXSEND :: selected-input send broadcast — txHash=\(txHash.map { String(format: "%02x", $0) }.joined()) fee=\(exactFee) adjusted=\(adjusted) inputs=\(utxos.count)")
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
                DWLogger.log("💸 TXSEND :: selected-input UTXO wait — polls=\(polls) utxos=\(utxos.count) total=\(total) needed=\(minimumTotal)")
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

    /// Fee reserve for a "Max" / all-funds core send, sized from the BIP44
    /// pooled accounts' actual spendable-UTXO count instead of a flat constant.
    ///
    /// The flat `WalletBalance.sendFeeReserveDuffs` (100_000 duffs) is a large
    /// worst-case over-estimate — a typical send costs ~1–2k duffs, so Max used
    /// to leave ~0.001 DASH behind as change. Here the reserve is the same
    /// size model as `estimatedSignalFee` (1 duff/byte over the enumerated
    /// inputs) plus a **+50 % safety margin** so it can never *under*-reserve —
    /// an under-estimate would make the Max send fail to build.
    ///
    /// The enumerated set must stay in step with the `.allSpendable` funding
    /// `finalizeAtomic` uses: BIP44 + BIP32 at the funding index plus every
    /// DashPay receiving account, and never CoinJoin or a contact's watch-only
    /// external coins.
    ///
    /// Fail-safe: any inability to enumerate the accounts (no wallet/manager,
    /// no UTXOs) falls back to the flat reserve, i.e. the previous behaviour —
    /// the change never makes Max worse than before, only tighter when it can.
    static func maxSendFeeReserveDuffs() -> UInt64 {
        let read = { @MainActor () -> UInt64? in
            let host = SwiftDashSDKHost.shared
            guard let manager = host.manager, let wallet = host.wallet else { return nil }
            let walletId = wallet.walletId
            // Enumerate exactly what `.allSpendable` spends — BIP44 + BIP32 at
            // the funding index, plus every DashPay receiving account. Sizing
            // the reserve off BIP44 alone would under-reserve whenever the
            // other sources contribute inputs, and Max would then price itself
            // above what the builder can actually fund.
            let pooled = manager.accountBalances(for: walletId).filter { balance in
                if balance.typeTag == Self.bip44TypeTag {
                    // Standard family: BIP44 and BIP32 both resolve to the
                    // single account at the funding index.
                    let isStandardPooled = balance.standardTag == Self.bip44StandardTag
                        || balance.standardTag == Self.bip32StandardTag
                    return isStandardPooled && balance.index == Self.bip44AccountIndex
                }
                // Every DashPay receiving account, whatever its index.
                return balance.typeTag == Self.dashpayReceivingTypeTag
            }
            guard !pooled.isEmpty else { return nil }
            let count = pooled.reduce(0) { total, balance in
                total + manager.accountUtxos(for: walletId, balance: balance).count
            }
            guard count > 0 else { return nil }
            let base = estimatedSignalFee(inputCount: count)
            return base + base / 2 // +50 % margin — must never under-reserve
        }

        let dynamic = MainThread.sync(read)
        return dynamic ?? WalletBalance.sendFeeReserveDuffs
    }

    // MARK: - Broadcast

    /// Broadcast a transaction previously built by `buildAndSign`. Resolves the
    /// core wallet fresh at call time (never cached in the prepared object) and
    /// submits the held `FinalizedCoreTransaction` to the network.
    ///
    /// Consumes the handle on every attempt (the SDK's single-shot ownership
    /// token — no accidental rebroadcast): after a non-accepted outcome or a
    /// throw, rebuild via `buildAndSign` rather than retrying the same object;
    /// the reservation is reconciled Rust-side.
    ///
    /// - Parameter tx: The finalized transaction returned by `buildAndSign`.
    /// - Returns: The SDK's authoritative network-acceptance outcome.
    ///
    /// Blocks until the network answers — up to about a minute when no peer
    /// does — so it must not run on the main thread. From the main actor, use
    /// the `async` overload.
    /// - Parameter signedBy: the wallet that signed `tx`, when known: the
    ///   broadcast is refused (nothing leaves) if another wallet is active by
    ///   now, rather than submitted through it.
    @discardableResult
    static func broadcast(_ tx: FinalizedCoreTransaction, signedBy walletId: Data? = nil) throws -> CoreTransactionBroadcastOutcome {
        assert(!Thread.isMainThread, "broadcast waits for network acceptance; use the async overload")
        // Only the wallet lookup needs the main actor; the submit runs here.
        let wallet = try MainThread.sync { () throws -> ManagedPlatformWallet in
            guard let wallet = SwiftDashSDKHost.shared.wallet else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            if let walletId, wallet.walletId != walletId {
                throw SendError.walletNotReady("the wallet that signed this payment is no longer the active one")
            }
            return wallet
        }
        return try submit(tx, through: wallet)
    }

    /// Submit `tx` through `wallet`'s core wallet and log the outcome. Blocks
    /// for the network wait.
    private static func submit(
        _ tx: FinalizedCoreTransaction, through wallet: ManagedPlatformWallet
    ) throws -> CoreTransactionBroadcastOutcome {
        // Serialize for logging BEFORE submit — broadcasting consumes the handle.
        let displayHash = computeTxHash(from: try tx.serializedData())
            .map { String(format: "%02x", $0) }.joined()
        let outcome = try wallet.coreWallet().broadcastTransactionWithOutcome(tx)

        switch outcome {
        case .accepted(let txid):
            DWLogger.log("💸 TXSEND :: broadcast accepted — sdkTxid=\(txid) txHash=\(displayHash)")
        case .rejected(let txid, let reason):
            DWLogger.logError("💸 TXSEND :: broadcast rejected — sdkTxid=\(txid) txHash=\(displayHash) reason=\(reason)")
        case .unknown(let txid, let reason):
            DWLogger.logError("💸 TXSEND :: broadcast unknown — sdkTxid=\(txid) txHash=\(displayHash) reason=\(reason)")
        }
        return outcome
    }

    /// `broadcast(_:)` on a background queue, for callers on the main actor or
    /// in Swift concurrency. Holds routing for the network wait.
    @discardableResult
    static func broadcast(_ tx: FinalizedCoreTransaction) async throws -> CoreTransactionBroadcastOutcome {
        try await waitingForNetwork(holdingRouting: true) { try broadcast(tx) }
    }

    /// The async `broadcast(_:)` without the routing hold, for a broadcast
    /// whose payment already holds it or that runs with no payment on screen.
    static func broadcastWithoutRoutingHold(
        _ tx: FinalizedCoreTransaction, signedBy walletId: Data? = nil
    ) async throws -> CoreTransactionBroadcastOutcome {
        try await waitingForNetwork(holdingRouting: false) { try broadcast(tx, signedBy: walletId) }
    }

    /// Run blocking work that waits for the network (a broadcast, a sweep) on
    /// a background queue and await its result. On the main actor such a wait
    /// freezes the UI; inline in a Swift-concurrency task it holds one of the
    /// few cooperative threads for up to a minute.
    ///
    /// With `holdingRouting`, a `PaymentInFlightHold` covers the wait, so an
    /// incoming link cannot replace the screen while the send waits; the
    /// result's way back to the screen is covered by
    /// `PaymentInFlight.resultGracePeriod`. Only the wait: a PIN prompt before
    /// it holds nothing (when it shows, it is a presented screen).
    static func waitingForNetwork<T>(
        holdingRouting: Bool, _ work: @escaping () throws -> T
    ) async throws -> T {
        let hold = holdingRouting ? PaymentInFlightHold() : nil
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try work() }
                hold?.end()
                continuation.resume(with: result)
            }
        }
    }

    /// Require a positive Core acceptance verdict for programmatic send paths
    /// that do not expose the outcome enum directly. Rejected and unknown are
    /// deliberately different errors: rejected may be retried (by rebuilding —
    /// the finalized handle is consumed), while unknown must not be
    /// automatically broadcast again.
    static func requireAccepted(_ outcome: CoreTransactionBroadcastOutcome) throws -> String {
        switch outcome {
        case .accepted(let txid):
            return txid
        case .rejected(let txid, let reason):
            throw SendError.transactionRejected(txid: txid, reason: reason)
        case .unknown(let txid, let reason):
            throw SendError.transactionStatusUnknown(txid: txid, reason: reason)
        }
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

    private static func assertSwapDepositShape(
        txData: Data,
        feeDuffs: UInt64,
        network: Network,
        vaultAddress: String,
        amountDuffs: UInt64,
        memoData: Data
    ) throws {
        let decoded = try TransactionDecoder.decode(txData, network: network)
        guard decoded.outputs.count >= 2, decoded.outputs.count <= 3 else {
            throw SendError.invalidInput("swap deposit must have 2 or 3 outputs")
        }

        let vaultOutput = decoded.outputs[0]
        guard vaultOutput.address == vaultAddress, vaultOutput.valueDuffs == amountDuffs else {
            throw SendError.invalidInput("swap deposit VOUT0 does not match the requested vault payment")
        }

        let memoOutput = decoded.outputs[1]
        guard memoOutput.valueDuffs == 0,
              memoOutput.scriptPubkey.first == 0x6a,
              RawTransactionInspector.opReturnData(script: memoOutput.scriptPubkey) == memoData
        else {
            throw SendError.invalidInput("swap deposit VOUT1 does not contain the requested OP_RETURN memo")
        }

        if decoded.outputs.count == 3 {
            // `DecodedTransaction.Input.address` is recovered from a P2PKH-shaped scriptSig
            // and is nil for anything else. Every UTXO the pooled funding set can spend —
            // BIP44, BIP32, and DashPay contact-receiving — is P2PKH, so nil here means the
            // transaction is not the shape we asked for: refuse rather than skip the check.
            // Note VIN0 decides where MAYA sends a refund, so under pooling that can be a
            // DashPay receiving address rather than a BIP44 one. Still this wallet's own
            // seed-signable address, and still counted in its balance.
            guard let inputAddress = decoded.inputs.first?.address else {
                throw SendError.invalidInput("swap deposit VIN0 address could not be recovered")
            }
            let paymentNetwork = try PaymentNetworkResolver.current()
            guard let inputScript = ScriptAddressCodec.scriptPubKey(forAddress: inputAddress, network: paymentNetwork),
                  decoded.outputs[2].scriptPubkey == inputScript
            else {
                throw SendError.invalidInput("swap deposit VOUT2 does not return change to VIN0")
            }
        }

        guard feeDuffs >= UInt64(txData.count) else {
            throw SendError.invalidInput("swap deposit fee rate fell below the 1 duff/byte relay minimum")
        }
    }

    // MARK: - Errors

    enum SendError: LocalizedError {
        case invalidInput(String)
        case invalidSwapMemo(String)
        case walletNotReady(String)
        case insufficientSelectedFunds(selected: UInt64, amount: UInt64, fee: UInt64)
        case transactionRejected(txid: String, reason: String)
        /// `walletId`: the wallet that signed, when the thrower knows it (the
        /// selected-input send).
        case transactionStatusUnknown(txid: String, reason: String, walletId: Data? = nil)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let reason):
                return "Invalid transaction input: \(reason)"
            case .invalidSwapMemo(let reason):
                return reason
            case .walletNotReady(let reason):
                return "Wallet not ready: \(reason)"
            case .insufficientSelectedFunds(let selected, let amount, let fee):
                return "Not enough funds. Selected: \(selected), Amount: \(amount), Fee: \(fee)"
            case .transactionRejected(_, let reason):
                return "The transaction wasn't sent. You can try again. \(reason)"
            case .transactionStatusUnknown(_, let reason, _):
                return "We couldn't confirm whether the transaction was accepted. Don't send it again; wait for wallet synchronization. \(reason)"
            }
        }
    }
}
