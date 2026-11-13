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
//  The CoinJoin-sweep path below broadcasts inline — a post-auth
//  programmatic flow with no confirmation UI.
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
    static let maxInputsPerSweep = 500
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
    /// The primary BIP44 account, the one Core sends fund from.
    private static let bip44AccountIndex: UInt32 = 0

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
    static func buildAndSign(address: String, amount: UInt64) throws -> (tx: FinalizedCoreTransaction, txHash: Data) {
        try buildAndSign(recipients: [(address: address, amountDuffs: amount)])
    }

    /// Multi-recipient variant — used by the app-side BIP70 send, where a merchant request may
    /// carry several outputs. Build + sign via the same `CoreTransactionBuilder`
    /// path as the single-recipient variant; broadcast is deferred to `broadcast(_:)`.
    static func buildAndSign(recipients: [(address: String, amountDuffs: UInt64)]) throws -> (tx: FinalizedCoreTransaction, txHash: Data) {
        logger.info("💸 TXSEND :: building+signing \(recipients.count, privacy: .public) recipient(s) via PlatformWalletManager.coreWallet")

        let build = { @MainActor () throws -> FinalizedCoreTransaction in
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
            return try builder.finalizeAtomic(wallet: wallet, accountType: .allSpendable)
        }

        let tx: FinalizedCoreTransaction
        if Thread.isMainThread {
            tx = try MainActor.assumeIsolated { try build() }
        } else {
            var captured: Result<FinalizedCoreTransaction, Error> = .failure(SendError.walletNotReady("uninitialized result"))
            DispatchQueue.main.sync {
                captured = Result { try MainActor.assumeIsolated { try build() } }
            }
            tx = try captured.get()
        }

        let txData = try tx.serializedData()
        let txHash = computeTxHash(from: txData)
        logger.info("💸 TXSEND :: built+signed — txHash=\(txHash.map { String(format: "%02x", $0) }.joined(), privacy: .public) fee=\(tx.fee, privacy: .public) duffs size=\(txData.count, privacy: .public) bytes")
        return (tx, txHash)
    }

    /// Build + sign a MAYACHAIN-style swap deposit: vault payment at VOUT0, a zero-value
    /// OP_RETURN memo at VOUT1, and change returned to VIN0 when change exists.
    /// Nothing is broadcast — pass the result to `broadcast(_:)`.
    static func buildAndSignSwapDeposit(
        vaultAddress: String,
        amountDuffs: UInt64,
        memo: String
    ) throws -> (tx: FinalizedCoreTransaction, txHash: Data) {
        let memoData = Data(memo.utf8)
        guard memoData.count <= Self.maxSwapMemoBytes else {
            throw SendError.invalidSwapMemo("Swap memo is too long. Please refresh and try again.")
        }

        logger.info("💸 TXSEND :: building+signing MAYA swap deposit via PlatformWalletManager.coreWallet")

        let build = { @MainActor () throws -> (tx: FinalizedCoreTransaction, network: Network) in
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
            return (tx, network)
        }

        let built: (tx: FinalizedCoreTransaction, network: Network)
        if Thread.isMainThread {
            built = try MainActor.assumeIsolated { try build() }
        } else {
            var captured: Result<(tx: FinalizedCoreTransaction, network: Network), Error> =
                .failure(SendError.walletNotReady("uninitialized result"))
            DispatchQueue.main.sync {
                captured = Result { try MainActor.assumeIsolated { try build() } }
            }
            built = try captured.get()
        }

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
        logger.info("💸 TXSEND :: built+signed MAYA swap deposit — txHash=\(txHash.map { String(format: "%02x", $0) }.joined(), privacy: .public) fee=\(built.tx.fee, privacy: .public) duffs size=\(txData.count, privacy: .public) bytes")
        return (built.tx, txHash)
    }

    // MARK: - CoinJoin Sweep

    /// Outcome of a chunked sweep (the CoinJoin sweep, or the Core
    /// consolidation that shares its chunk loop).
    ///
    /// Each chunk is an independent transaction, so a sweep can end up partly
    /// done: some chunks broadcast while another fails to build, sign or
    /// broadcast. The txids alone cannot express that — a caller that only sees
    /// a non-empty array reports "your mixed coins were moved" while the failed
    /// chunks are still sitting in the CoinJoin account. So the failure travels
    /// with them, and the caller records the accepted transactions *and* still
    /// surfaces the partial state.
    struct SweepOutcome {
        /// Wire-order txids of the chunks that broadcast, in chunk order
        /// (matches `Transaction.txHashData`). The CoinJoin sweep records them
        /// in `CoinJoinWithdrawalStore`; the Core consolidation never does.
        let txids: [Data]
        /// How many chunks were not accepted, including the unknown ones.
        let failedChunkCount: Int
        /// The first failed chunk's error, preferring one that was not unknown
        /// (it says why coins are left); nil when every chunk broadcast.
        let firstFailure: Error?
        /// Wire-order txids of the chunks whose broadcast ended
        /// `transactionStatusUnknown`: they may have reached peers.
        let unknownTxids: [Data]

        /// Some chunks broadcast and some did not. A rejected chunk's coins
        /// remain in the CoinJoin account; an unknown chunk's were applied to
        /// the wallet before the broadcast waited for peers (see
        /// `WalletSendService.coinJoinSweepFailure`).
        var isPartial: Bool { !txids.isEmpty && failedChunkCount > 0 }
    }

    typealias CoinJoinSweepOutcome = SweepOutcome

    /// Thrown by `sweepCoinJoin` when no chunk was accepted and at least one
    /// ended `transactionStatusUnknown`; carries every such chunk's txid.
    struct CoinJoinSweepUnknownError: LocalizedError {
        /// Wire-order txids of the chunks whose outcome is unknown.
        let unknownTxids: [Data]
        /// The first unknown chunk's error.
        let underlying: Error
        /// Every chunk that was not accepted, unknown or not.
        let failedChunkCount: Int
        /// The first failed chunk's error that was not unknown, if any.
        let otherFailure: Error?

        var errorDescription: String? { underlying.localizedDescription }
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
    ///     address, resolved via `SwiftDashSDKReceiveAddressReader`, or a fresh
    ///     CoinJoin address for the Shielded consolidation).
    ///   - binding: When set, the sweep refuses to run unless this is still the
    ///     active wallet and network.
    ///   - outpoints: When set, only these UTXOs are spent (the ones still
    ///     unspent), and fewer than two of them are not swept: one input
    ///     would only pay a fee. The Shielded consolidation passes the final
    ///     ones it planned from: an unconfirmed input that never locks would
    ///     leave every coin swept with it behind a transaction that cannot
    ///     confirm.
    /// - Returns: A `CoinJoinSweepOutcome` carrying the broadcast chunks' txids
    ///   and any chunk failure. Throws only when nothing broadcast at all.
    static func sweepCoinJoin(
        to address: String, expecting binding: CoinJoinWalletBinding? = nil,
        outpoints: Set<CoinJoinOutpoint>? = nil
    ) throws -> CoinJoinSweepOutcome {
        logger.info("💸 TXSEND :: sweeping CoinJoin account → spendable balance")

        let sweep = { @MainActor () throws -> CoinJoinSweepOutcome in
            let host = SwiftDashSDKHost.shared
            guard let wallet = host.wallet, let manager = host.manager,
                  let network = host.runningNetwork else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            if let binding, binding != CoinJoinWalletBinding.current() {
                throw SendError.walletNotReady("the active wallet changed")
            }
            let core = try wallet.coreWallet()
            let utxos = Self.sweepUtxos(manager: manager, walletId: wallet.walletId, restrictedTo: outpoints)
            guard !utxos.isEmpty else {
                return SweepOutcome(txids: [], failedChunkCount: 0, firstFailure: nil, unknownTxids: [])
            }
            return try Self.sweepChunks(
                utxos, accountType: .coinJoin, accountIndex: Self.coinJoinAccountIndex,
                to: address, wallet: wallet, core: core, network: network, label: "coinjoin sweep")
        }

        let outcome = try onMain(sweep)
        logSweepBroadcast(outcome, label: "coinjoin sweep")
        return outcome
    }

    /// Spend `utxos` of one account to `address` in balanced ≤500-input
    /// chunks, one transaction each, and broadcast them.
    ///
    /// `useOnlyAddedInputs` is what makes the chunk the transaction's input
    /// set — the finalizer otherwise funds from the whole account regardless
    /// of what was seeded. `SelectionStrategy.all` makes core compute
    /// output = Σinputs − fee with no change (the addOutput amount is
    /// ignored); `finalizeAtomic` resolves dual-chain `/0/`+`/1/` signing.
    /// Partial-failure tolerant: keep the txs that broadcast, log the rest,
    /// and throw only if none was accepted (`CoinJoinSweepUnknownError` when
    /// one may still land). A mixed outcome is reported through
    /// `SweepOutcome`, not swallowed.
    @MainActor
    private static func sweepChunks(
        _ utxos: [PlatformWalletManager.AccountUtxo],
        accountType: CoreTransactionBuilder.AccountType,
        accountIndex: UInt32,
        to address: String,
        wallet: ManagedPlatformWallet,
        core: ManagedCoreWallet,
        network: Network,
        label: String
    ) throws -> SweepOutcome {
        var txids: [Data] = []
        var failedChunkCount = 0
        var firstOther: Error?
        // An unconfirmed broadcast may have reached peers: when nothing was
        // accepted it is the error reported, ahead of a rejection, so a
        // caller can tell it apart from "nothing moved".
        var firstUnknown: Error?
        var unknownTxids: [Data] = []
        for (index, chunk) in Self.balancedChunks(utxos, maxPerChunk: Self.maxInputsPerSweep).enumerated() {
            var chunkTxid: Data?
            do {
                let builder = try CoreTransactionBuilder(network: network)
                try builder.addInputs(
                    wallet: wallet, accountType: accountType,
                    accountIndex: accountIndex, utxos: chunk)
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
                    wallet: wallet, accountType: accountType,
                    accountIndex: accountIndex)
                // Serialize BEFORE broadcast — broadcasting consumes the handle.
                let txData = try tx.serializedData()
                // Wire (internal) byte order to match `Transaction.txHashData` /
                // `CoinJoinWithdrawalStore`: `computeTxHash` yields display order,
                // so reverse it back to wire order.
                let txid = Data(Self.computeTxHash(from: txData).reversed())
                chunkTxid = txid
                let outcome = try core.broadcastTransactionWithOutcome(tx)
                _ = try Self.requireAccepted(outcome)
                txids.append(txid)
            } catch {
                failedChunkCount += 1
                if case SendError.transactionStatusUnknown = error {
                    firstUnknown = firstUnknown ?? error
                    if let chunkTxid { unknownTxids.append(chunkTxid) }
                } else {
                    firstOther = firstOther ?? error
                }
                Self.logger.error(
                    "💸 TXSEND :: \(label, privacy: .public) chunk \(index + 1, privacy: .public) failed to broadcast, continuing: \(String(describing: error), privacy: .public)")
            }
        }
        if txids.isEmpty, let firstUnknown {
            throw CoinJoinSweepUnknownError(
                unknownTxids: unknownTxids, underlying: firstUnknown,
                failedChunkCount: failedChunkCount, otherFailure: firstOther)
        }
        if txids.isEmpty, let firstOther { throw firstOther }
        return SweepOutcome(
            txids: txids, failedChunkCount: failedChunkCount, firstFailure: firstOther ?? firstUnknown,
            unknownTxids: unknownTxids)
    }

    /// Runs `work` on the main actor: inline when already on main, else by a
    /// synchronous hop.
    private static func onMain<T>(_ work: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated { try work() }
        }
        var captured: Result<T, Error> = .failure(SendError.walletNotReady("uninitialized result"))
        DispatchQueue.main.sync {
            captured = Result { try MainActor.assumeIsolated { try work() } }
        }
        return try captured.get()
    }

    /// Logs a sweep's broadcast txids in display order (byte-reversed wire
    /// order), to match explorers.
    private static func logSweepBroadcast(_ outcome: SweepOutcome, label: String) {
        let hexes = outcome.txids.map { txid -> String in
            Data(txid.reversed()).map { String(format: "%02x", $0) }.joined()
        }
        logger.info("💸 TXSEND :: \(label, privacy: .public) broadcast — \(outcome.txids.count, privacy: .public) tx(s), \(outcome.failedChunkCount, privacy: .public) chunk(s) failed: \(hexes.joined(separator: ","), privacy: .public)")
    }

    // MARK: - Core consolidation (asset-lock input limit)

    /// Combine the BIP44 account-0 coins in `outpoints` onto `address` (a
    /// fresh BIP44 receive address of this wallet), so an asset lock can
    /// cover its amount with fewer inputs (`AssetLockInputPolicy`).
    ///
    /// Same chunk loop as `sweepCoinJoin`: ≤500 inputs per transaction,
    /// `useOnlyAddedInputs`, `.all`, 1000 sat/kB. The txids are not CoinJoin
    /// withdrawals and must never be recorded as such
    /// (`CoinJoinWithdrawalStore`): they are the wallet paying itself.
    ///
    /// - Parameters:
    ///   - binding: the sweep refuses to run unless this is still the active
    ///     wallet and network.
    ///   - outpoints: the coins to spend — the final ones the caller planned
    ///     from (an unconfirmed input that never locks would strand every coin
    ///     combined with it). Fewer than two still unspent are not combined.
    /// - Returns: the broadcast chunks' txids and any chunk failure. Throws
    ///   only when nothing broadcast at all.
    static func consolidateCoreAccount(
        to address: String, expecting binding: CoinJoinWalletBinding, outpoints: Set<CoinJoinOutpoint>
    ) throws -> SweepOutcome {
        logger.info("💸 TXSEND :: combining BIP44 coins for an asset lock")

        let consolidate = { @MainActor () throws -> SweepOutcome in
            let host = SwiftDashSDKHost.shared
            guard let wallet = host.wallet, let manager = host.manager,
                  let network = host.runningNetwork else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            guard binding == CoinJoinWalletBinding.current() else {
                throw SendError.walletNotReady("the active wallet changed")
            }
            let core = try wallet.coreWallet()
            guard let bip44 = Self.bip44AccountBalance(in: manager.accountBalances(for: wallet.walletId)) else {
                return SweepOutcome(txids: [], failedChunkCount: 0, firstFailure: nil, unknownTxids: [])
            }
            let utxos = Self.sweepInputs(
                manager.accountUtxos(for: wallet.walletId, balance: bip44).filter { !$0.isLocked },
                restrictedTo: outpoints
            ) { CoinJoinOutpoint(txid: $0.outpointTxid, vout: $0.outpointVout) }
            guard utxos.count >= 2 else {
                Self.logger.info(
                    "💸 TXSEND :: core consolidation — \(utxos.count, privacy: .public) of \(outpoints.count, privacy: .public) planned UTXO(s) still spendable, not combining")
                return SweepOutcome(txids: [], failedChunkCount: 0, firstFailure: nil, unknownTxids: [])
            }
            return try Self.sweepChunks(
                utxos, accountType: .bip44, accountIndex: Self.bip44AccountIndex,
                to: address, wallet: wallet, core: core, network: network, label: "core consolidation")
        }

        let outcome = try onMain(consolidate)
        logSweepBroadcast(outcome, label: "core consolidation")
        return outcome
    }

    /// The BIP44 account-0 balance descriptor among a wallet's
    /// `accountBalances`, which addresses the account for UTXO enumeration.
    private static func bip44AccountBalance(
        in balances: [PlatformWalletManager.AccountBalance]
    ) -> PlatformWalletManager.AccountBalance? {
        balances.first(where: isBip44Account0)
    }

    /// Whether `balance` describes BIP44 account 0, the account the Core
    /// consolidation spends.
    private static func isBip44Account0(_ balance: PlatformWalletManager.AccountBalance) -> Bool {
        balance.typeTag == Self.bip44TypeTag
            && balance.standardTag == Self.bip44StandardTag
            && balance.index == Self.bip44AccountIndex
    }

    /// Snapshot of the BIP44 account-0 spendable UTXOs with their finality —
    /// the same shape as `coinJoinUtxoState(expecting:)`, read off the
    /// account the Core consolidation spends and pays back into. Nil when the
    /// active wallet is not `binding`, no manager is bound, or the read can't
    /// be told apart from a failed one (`CoinJoinShieldPlanner.utxoReadIsUsable`:
    /// every wallet has this account, and one with a balance has UTXOs);
    /// `isLocked` rows are left out, as coin selection never spends them.
    @MainActor
    static func bip44UtxoState(expecting binding: CoinJoinWalletBinding) -> CoinJoinUtxoState? {
        let host = SwiftDashSDKHost.shared
        guard let manager = host.manager, CoinJoinWalletBinding.current() == binding else { return nil }
        let walletId = binding.walletId
        let balances = manager.accountBalances(for: walletId)
        guard let bip44 = bip44AccountBalance(in: balances) else { return nil }
        let utxos = manager.accountUtxos(for: walletId, balance: bip44)
        let balanceIsZero = bip44.confirmed == 0 && bip44.unconfirmed == 0 && bip44.immature == 0 && bip44.locked == 0
        guard CoinJoinShieldPlanner.utxoReadIsUsable(
            accountCount: balances.count, accountBalanceIsZero: balanceIsZero, utxoCount: utxos.count)
        else { return nil }
        let instantLocked = Set(manager.instantSendLockTxids(for: walletId))
        let entries = utxos
            .filter { !$0.isLocked }
            .map { utxo in
                CoinJoinUtxoState.Entry(
                    txid: utxo.outpointTxid,
                    vout: utxo.outpointVout,
                    valueDuffs: utxo.valueDuffs,
                    isFinal: CoinJoinShieldPlanner.isFinal(
                        height: utxo.height,
                        txid: utxo.outpointTxid,
                        instantLockedTxids: instantLocked))
            }
        return CoinJoinUtxoState(binding: binding, entries: entries)
    }

    /// `waitForCoinJoinUtxoState` over the BIP44 account-0 snapshot
    /// (`bip44UtxoState(expecting:)`), with the same contract.
    static func waitForBip44UtxoState(
        binding: CoinJoinWalletBinding,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 1,
        until isDone: @escaping (CoinJoinUtxoState) -> Bool
    ) async throws -> (state: CoinJoinUtxoState, satisfied: Bool)? {
        try await waitForUtxoState(
            binding: binding, timeout: timeout, pollInterval: pollInterval,
            read: { bip44UtxoState(expecting: $0) }, until: isDone)
    }

    // MARK: - CoinJoin consolidation (CoinJoin → Shielded over the asset-lock input cap)

    /// The CoinJoin account-0 balance descriptor (typeTag 1, index 0 — mirrors
    /// `SwiftDashSDKCoinJoinBalanceReader`) among a wallet's `accountBalances`,
    /// which addresses the account for UTXO and address-pool enumeration. Nil
    /// when the wallet has no CoinJoin account.
    private static func coinJoinAccountBalance(
        in balances: [PlatformWalletManager.AccountBalance]
    ) -> PlatformWalletManager.AccountBalance? {
        balances.first(where: {
            $0.typeTag == Self.coinJoinTypeTag && $0.index == Self.coinJoinAccountIndex
        })
    }

    /// The CoinJoin rows a sweep spends: the unlocked ones, only those in
    /// `outpoints` when it is set. None when there is nothing worth sweeping:
    /// no CoinJoin account, or fewer than two of the planned rows left.
    @MainActor
    private static func sweepUtxos(
        manager: PlatformWalletManager, walletId: Data, restrictedTo outpoints: Set<CoinJoinOutpoint>?
    ) -> [PlatformWalletManager.AccountUtxo] {
        // CoinJoin account-0 balance descriptor (mirrors
        // SwiftDashSDKCoinJoinBalanceReader: typeTag 1, index 0). Used only to
        // address the account for UTXO enumeration.
        guard let cjBalance = coinJoinAccountBalance(in: manager.accountBalances(for: walletId)) else { return [] }
        // Snapshot the account's spendable UTXOs (after the recovery scan has
        // materialized deep `/0/` + `/1/` addresses). `isLocked` rows are
        // left out, matching `coinJoinUtxoState(expecting:)`: coin
        // selection never spends them.
        let utxos = sweepInputs(
            manager.accountUtxos(for: walletId, balance: cjBalance).filter { !$0.isLocked },
            restrictedTo: outpoints
        ) { CoinJoinOutpoint(txid: $0.outpointTxid, vout: $0.outpointVout) }
        if let outpoints, utxos.count < 2 {
            logger.info(
                "💸 TXSEND :: coinjoin sweep — \(utxos.count, privacy: .public) of \(outpoints.count, privacy: .public) planned UTXO(s) still spendable, not sweeping")
            return []
        }
        return utxos
    }

    /// The CoinJoin account's descriptor and UTXO rows (locked ones included),
    /// or nil when the read can't be told apart from a failed one (see
    /// `CoinJoinShieldPlanner.utxoReadIsUsable`). An account that does not
    /// exist reads as no descriptor and no rows.
    @MainActor
    private static func coinJoinUtxoRows(
        manager: PlatformWalletManager, walletId: Data
    ) -> (balance: PlatformWalletManager.AccountBalance?, utxos: [PlatformWalletManager.AccountUtxo])? {
        let balances = manager.accountBalances(for: walletId)
        let cjBalance = coinJoinAccountBalance(in: balances)
        let utxos = cjBalance.map { manager.accountUtxos(for: walletId, balance: $0) } ?? []
        let balanceIsZero = cjBalance.map {
            $0.confirmed == 0 && $0.unconfirmed == 0 && $0.immature == 0 && $0.locked == 0
        }
        guard CoinJoinShieldPlanner.utxoReadIsUsable(
            accountCount: balances.count, accountBalanceIsZero: balanceIsZero, utxoCount: utxos.count)
        else { return nil }
        return (cjBalance, utxos)
    }

    /// The wallet and network a CoinJoin → Shielded move was authorized for.
    /// Each step of the move re-checks it, so a wallet or network switch while
    /// it runs stops the move instead of carrying it over to another wallet.
    struct CoinJoinWalletBinding: Equatable {
        let walletId: Data
        let network: Network

        /// The host's active wallet and network; nil when none is bound.
        @MainActor
        static func current() -> CoinJoinWalletBinding? {
            let host = SwiftDashSDKHost.shared
            guard let wallet = host.wallet, let network = host.runningNetwork else { return nil }
            return CoinJoinWalletBinding(walletId: wallet.walletId, network: network)
        }
    }

    /// A CoinJoin UTXO's outpoint; the txid is in wire order.
    struct CoinJoinOutpoint: Hashable {
        let txid: Data
        let vout: UInt32
    }

    /// The `rows` a sweep spends: those whose outpoint is in `outpoints`, or
    /// all of them when it is nil.
    static func sweepInputs<Row>(
        _ rows: [Row], restrictedTo outpoints: Set<CoinJoinOutpoint>?, outpoint: (Row) -> CoinJoinOutpoint
    ) -> [Row] {
        guard let outpoints else { return rows }
        return rows.filter { outpoints.contains(outpoint($0)) }
    }

    /// The CoinJoin account's spendable UTXO set, as `CoinJoinShieldPlanner`
    /// reads it.
    struct CoinJoinUtxoState {
        struct Entry {
            /// Wire-order txid (`AccountUtxo.outpointTxid`, the same order as
            /// `CoinJoinSweepOutcome.txids`).
            let txid: Data
            let vout: UInt32
            let valueDuffs: UInt64
            /// Confirmed or InstantSend-locked — what the drain builder
            /// accepts as an input (see `CoinJoinShieldPlanner.isFinal`).
            let isFinal: Bool

            var outpoint: CoinJoinOutpoint { CoinJoinOutpoint(txid: txid, vout: vout) }
        }

        let binding: CoinJoinWalletBinding
        let entries: [Entry]

        var count: Int { entries.count }
        var finalCount: Int { entries.reduce(0) { $0 + ($1.isFinal ? 1 : 0) } }
        var totalDuffs: UInt64 { entries.reduce(0) { $0 + $1.valueDuffs } }
        var txidFinality: [(txid: Data, isFinal: Bool)] { entries.map { ($0.txid, $0.isFinal) } }
        var finalOutpoints: Set<CoinJoinOutpoint> {
            Set(entries.lazy.filter(\.isFinal).map(\.outpoint))
        }
    }

    /// Snapshot of the CoinJoin account's spendable UTXOs with their finality.
    /// Nil when it can't be read: the host has no wallet or manager bound, the
    /// active wallet is not `binding`, or the SDK read looks failed (see
    /// `coinJoinUtxoRows`). An account that does not exist reads as empty.
    ///
    /// `isLocked` rows are left out: coin selection never spends them, so
    /// counting them would ask for a consolidation that has nothing to
    /// consolidate.
    @MainActor
    static func coinJoinUtxoState(expecting binding: CoinJoinWalletBinding) -> CoinJoinUtxoState? {
        let host = SwiftDashSDKHost.shared
        guard let manager = host.manager, CoinJoinWalletBinding.current() == binding else { return nil }
        let walletId = binding.walletId
        guard let rows = coinJoinUtxoRows(manager: manager, walletId: walletId) else { return nil }
        let instantLocked = Set(manager.instantSendLockTxids(for: walletId))
        let entries = rows.utxos
            .filter { !$0.isLocked }
            .map { utxo in
                CoinJoinUtxoState.Entry(
                    txid: utxo.outpointTxid,
                    vout: utxo.outpointVout,
                    valueDuffs: utxo.valueDuffs,
                    isFinal: CoinJoinShieldPlanner.isFinal(
                        height: utxo.height,
                        txid: utxo.outpointTxid,
                        instantLockedTxids: instantLocked))
            }
        return CoinJoinUtxoState(binding: binding, entries: entries)
    }

    /// A fresh receive address of this wallet's own CoinJoin account — the
    /// consolidation destination, so the mixed coins stay in the CoinJoin
    /// account until the drain asset lock spends them.
    ///
    /// Picked from the account's external (`.../0/index`) address pool: the
    /// lowest-index address the pool has not seen used and that holds no UTXO
    /// right now. Pool addresses are exactly what the SPV client watches —
    /// `monitored_script_pubkeys` walks every account's pool — so an output
    /// paid here is detected and lands back in the CoinJoin account, and its
    /// use moves the pool's gap forward like any other receive.
    @MainActor
    static func unusedCoinJoinAddress(for binding: CoinJoinWalletBinding) -> String? {
        let host = SwiftDashSDKHost.shared
        guard let manager = host.manager, CoinJoinWalletBinding.current() == binding else { return nil }
        let walletId = binding.walletId
        // A failed UTXO read would leave funded addresses looking unused.
        guard let rows = coinJoinUtxoRows(manager: manager, walletId: walletId),
              let cjBalance = rows.balance,
              let network = try? PaymentNetworkResolver.current()
        else { return nil }
        // Pool type 0 = External (see `AccountAddressPoolSnapshot.pool_type`).
        guard let external = manager.accountAddressPools(for: walletId, balance: cjBalance)
            .first(where: { $0.poolType == 0 })
        else { return nil }
        let fundedScripts = Set(rows.utxos.map(\.scriptPubkey))
        let candidates = external.addresses
            .filter { !$0.isUsed && !$0.address.isEmpty }
            .sorted { $0.addressIndex < $1.addressIndex }
        for candidate in candidates {
            guard let script = ScriptAddressCodec.scriptPubKey(forAddress: candidate.address, network: network),
                  !fundedScripts.contains(script)
            else { continue }
            let watched = external.addresses.count, gap = external.gapLimit
            logger.info(
                "💸 TXSEND :: coinjoin consolidation address index=\(candidate.addressIndex, privacy: .public) of \(watched, privacy: .public) watched (gap \(gap, privacy: .public))")
            return candidate.address
        }
        return nil
    }

    /// Poll `binding`'s CoinJoin UTXO state until `isDone` holds or `timeout`
    /// elapses. Returns the last snapshot and whether `isDone` held for it;
    /// nil when the active wallet is no longer `binding`, or when the last
    /// poll before the deadline could not read the state (a read that looks
    /// failed is retried, never taken as the answer, and an older snapshot is
    /// never returned in its place). Sleeps off the main actor between polls.
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled, even
    ///   if the last snapshot satisfied `isDone`.
    static func waitForCoinJoinUtxoState(
        binding: CoinJoinWalletBinding,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 1,
        until isDone: @escaping (CoinJoinUtxoState) -> Bool
    ) async throws -> (state: CoinJoinUtxoState, satisfied: Bool)? {
        try await waitForUtxoState(
            binding: binding, timeout: timeout, pollInterval: pollInterval,
            read: { coinJoinUtxoState(expecting: $0) }, until: isDone)
    }

    /// The poll behind `waitForCoinJoinUtxoState` and `waitForBip44UtxoState`:
    /// `read` is the snapshot to poll.
    private static func waitForUtxoState(
        binding: CoinJoinWalletBinding,
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        read readState: @escaping @MainActor (CoinJoinWalletBinding) -> CoinJoinUtxoState?,
        until isDone: @escaping (CoinJoinUtxoState) -> Bool
    ) async throws -> (state: CoinJoinUtxoState, satisfied: Bool)? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            try Task.checkCancellation()
            let read = await MainActor.run { () -> (bound: Bool, state: CoinJoinUtxoState?) in
                if let state = readState(binding) { return (true, state) }
                return (CoinJoinWalletBinding.current() == binding, nil)
            }
            try Task.checkCancellation()
            guard read.bound else { return nil }
            if let state = read.state, isDone(state) { return (state, true) }
            if Date() >= deadline { return read.state.map { ($0, false) } }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    /// Size-based fee estimate for a P2PKH send at the relay-minimum
    /// 1 duff/byte: base 10 + 148/input + 34 × 2 outputs (dest + change).
    /// Mirrors the legacy `chain.fee(forTxSize: tx.size + TX_OUTPUT_SIZE)`.
    /// Also the base of `AssetLockInputPolicy.estimatedFeeDuffs`.
    static func estimatedFee(inputCount: Int) -> UInt64 {
        UInt64(10 + inputCount * 148 + 2 * 34)
    }

    /// `estimatedFee` for `inputCount` inputs plus a +50 % margin, so the
    /// Max reserve never under-reserves.
    static func maxSendFeeReserve(forInputCount inputCount: Int) -> UInt64 {
        let base = estimatedFee(inputCount: inputCount)
        return base + base / 2
    }

    /// Fee reserve for a "Max" / all-funds core send, sized from the BIP44
    /// pooled accounts' actual spendable-UTXO count instead of a flat constant.
    ///
    /// The flat `WalletBalance.sendFeeReserveDuffs` (100_000 duffs) is a large
    /// worst-case over-estimate — a typical send costs ~1–2k duffs, so Max used
    /// to leave ~0.001 DASH behind as change. Here the reserve is the same
    /// size model as `estimatedFee` (1 duff/byte over the enumerated
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
        let dynamic = readSendPool { manager, walletId, pooled -> UInt64? in
            let count = pooled.reduce(0) { total, balance in
                total + manager.accountUtxos(for: walletId, balance: balance).count
            }
            guard count > 0 else { return nil }
            return maxSendFeeReserve(forInputCount: count)
        }
        return dynamic ?? WalletBalance.sendFeeReserveDuffs
    }

    /// The send pool's `confirmed` and `unconfirmed` sums over the same
    /// accounts `maxSendFeeReserveDuffs` enumerates, from one read. Immature
    /// coinbase and locked coins are left out — waiting a few minutes does not
    /// free them.
    ///
    /// `nil` when the accounts cannot be enumerated (no wallet/manager yet).
    static func sendPoolConfirmationSnapshot() -> SendPoolConfirmationSnapshot? {
        readSendPool { _, _, pooled in
            SendPoolConfirmationSnapshot(
                confirmedDuffs: pooled.reduce(0) { $0 + $1.confirmed },
                unconfirmedDuffs: pooled.reduce(0) { $0 + $1.unconfirmed })
        }
    }

    /// Runs `read` on the main actor over the accounts `.allSpendable` funds a
    /// send from, from any thread. `nil` when there is no wallet/manager or
    /// none of those accounts exists.
    ///
    /// Enumerates exactly what `.allSpendable` spends — BIP44 + BIP32 at the
    /// funding index, plus every DashPay receiving account. Sizing the fee
    /// reserve off BIP44 alone would under-reserve whenever the other sources
    /// contribute inputs, and Max would then price itself above what the
    /// builder can actually fund.
    private static func readSendPool<T: Sendable>(
        _ read: @escaping @MainActor (PlatformWalletManager, Data, [PlatformWalletManager.AccountBalance]) -> T?
    ) -> T? {
        let body = { @MainActor () -> T? in
            let host = SwiftDashSDKHost.shared
            guard let manager = host.manager, let wallet = host.wallet else { return nil }
            let walletId = wallet.walletId
            guard let pooled = Self.pooledAccountBalances(manager: manager, walletId: walletId) else { return nil }
            return read(manager, walletId, pooled)
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated { body() }
        }
        var captured: T?
        DispatchQueue.main.sync { captured = MainActor.assumeIsolated { body() } }
        return captured
    }

    // MARK: - Pooled Core UTXOs

    /// The accounts `.allSpendable` spends from — BIP44 + BIP32 at the
    /// funding index, plus every DashPay receiving account. Also the
    /// asset-lock funding set (`ASSET_LOCK_FUNDING_SOURCES` equals the send
    /// set SDK-side). Nil when the wallet has none of those accounts.
    @MainActor
    private static func pooledAccountBalances(
        manager: PlatformWalletManager, walletId: Data
    ) -> [PlatformWalletManager.AccountBalance]? {
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
        return pooled.isEmpty ? nil : pooled
    }

    /// A pooled Core coin as `AssetLockInputPolicy` counts it.
    struct PooledUtxo: Equatable {
        let valueDuffs: UInt64
        /// Confirmed or InstantSend-locked — the only coins an asset lock
        /// spends (`require_final_inputs()`).
        let isFinal: Bool
        /// In BIP44 account 0, the only account the Core consolidation
        /// (`consolidateCoreAccount`) spends.
        let isCombinable: Bool
    }

    /// The coins a Core-funded asset lock may spend: the UTXO rows of the
    /// pooled accounts (`pooledAccountBalances`) without the `isLocked` ones
    /// coin selection never spends. Nil when no wallet or manager is bound,
    /// or when the read can't be told apart from a failed one
    /// (`CoinJoinShieldPlanner.utxoReadIsUsable`): every wallet has its BIP44
    /// account, and an account with a balance has UTXOs.
    @MainActor
    static func pooledSpendableUtxos() -> [PooledUtxo]? {
        let host = SwiftDashSDKHost.shared
        guard let manager = host.manager, let wallet = host.wallet else { return nil }
        let walletId = wallet.walletId
        guard let pooled = pooledAccountBalances(manager: manager, walletId: walletId) else {
            logger.error("💸 TXSEND :: pooled UTXO read — no pooled account, treating the read as failed")
            return nil
        }
        let instantLocked = Set(manager.instantSendLockTxids(for: walletId))
        var coins: [PooledUtxo] = []
        for balance in pooled {
            let rows = manager.accountUtxos(for: walletId, balance: balance)
            let balanceIsZero = balance.confirmed == 0 && balance.unconfirmed == 0
                && balance.immature == 0 && balance.locked == 0
            guard CoinJoinShieldPlanner.utxoReadIsUsable(
                accountCount: pooled.count, accountBalanceIsZero: balanceIsZero, utxoCount: rows.count)
            else {
                logger.error("💸 TXSEND :: pooled UTXO read — an account with a balance returned no UTXOs, treating the read as failed")
                return nil
            }
            let isCombinable = isBip44Account0(balance)
            coins += rows
                .filter { !$0.isLocked }
                .map { utxo in
                    PooledUtxo(
                        valueDuffs: utxo.valueDuffs,
                        isFinal: CoinJoinShieldPlanner.isFinal(
                            height: utxo.height, txid: utxo.outpointTxid, instantLockedTxids: instantLocked),
                        isCombinable: isCombinable)
                }
        }
        return coins
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
    @discardableResult
    static func broadcast(_ tx: FinalizedCoreTransaction) throws -> CoreTransactionBroadcastOutcome {
        // Serialize for logging BEFORE submit — broadcasting consumes the handle.
        let displayHash = computeTxHash(from: try tx.serializedData())
            .map { String(format: "%02x", $0) }.joined()

        let submit = { @MainActor () throws -> CoreTransactionBroadcastOutcome in
            guard let wallet = SwiftDashSDKHost.shared.wallet else {
                throw SendError.walletNotReady("PlatformWalletManager wallet is not available")
            }
            let core = try wallet.coreWallet()
            return try core.broadcastTransactionWithOutcome(tx)
        }

        let outcome: CoreTransactionBroadcastOutcome
        if Thread.isMainThread {
            outcome = try MainActor.assumeIsolated { try submit() }
        } else {
            var captured: Result<CoreTransactionBroadcastOutcome, Error> =
                .failure(SendError.walletNotReady("uninitialized result"))
            DispatchQueue.main.sync {
                captured = Result { try MainActor.assumeIsolated { try submit() } }
            }
            outcome = try captured.get()
        }

        switch outcome {
        case .accepted(let txid):
            logger.info("💸 TXSEND :: broadcast accepted — sdkTxid=\(txid, privacy: .public) txHash=\(displayHash, privacy: .public)")
        case .rejected(let txid, let reason):
            logger.error("💸 TXSEND :: broadcast rejected — sdkTxid=\(txid, privacy: .public) txHash=\(displayHash, privacy: .public) reason=\(reason, privacy: .public)")
        case .unknown(let txid, let reason):
            logger.error("💸 TXSEND :: broadcast unknown — sdkTxid=\(txid, privacy: .public) txHash=\(displayHash, privacy: .public) reason=\(reason, privacy: .public)")
        }
        return outcome
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

    /// Partition `utxos` into balanced chunks each ≤ `maxPerChunk`
    /// (`maxInputsPerSweep` in production), preserving order — app-side
    /// chunking (no upstream key-wallet counterpart): `ceil(n / 500)`
    /// near-equal chunks, so no chunk is a lone sub-fee input.
    /// Examples: 500 → [500]; 501 → [251, 250]; 1000 → [500, 500].
    static func balancedChunks<T>(_ utxos: [T], maxPerChunk: Int) -> [[T]] {
        let n = utxos.count
        guard n > 0, maxPerChunk > 0 else { return [] }
        let numChunks = (n + maxPerChunk - 1) / maxPerChunk // ceil(n / max)
        let chunkSize = (n + numChunks - 1) / numChunks     // ceil(n / numChunks)
        var chunks: [[T]] = []
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
        case transactionRejected(txid: String, reason: String)
        case transactionStatusUnknown(txid: String, reason: String)

        var errorDescription: String? {
            switch self {
            case .invalidInput(let reason):
                return "Invalid transaction input: \(reason)"
            case .invalidSwapMemo(let reason):
                return reason
            case .walletNotReady(let reason):
                return "Wallet not ready: \(reason)"
            case .transactionRejected(_, let reason):
                return "The transaction wasn't sent. You can try again. \(reason)"
            case .transactionStatusUnknown(_, let reason):
                return "We couldn't confirm whether the transaction was accepted. Don't send it again; wait for wallet synchronization. \(reason)"
            }
        }
    }
}
