//
//  WalletSendService.swift
//  DashWallet
//
//  Shared send boundary for standard and selected-input SwiftDashSDK sends.
//

import Foundation
import OSLog
import SwiftDashSDK

/// Core-chain transaction constants the app needs without DashSync.
enum CoreTxConstants {
    /// DashSync's TX_MIN_OUTPUT_AMOUNT: TX_FEE_PER_B(1) × 3 × (TX_OUTPUT_SIZE(34) +
    /// TX_INPUT_SIZE(148)) = 546 duffs — the standard dust threshold; no txout below this.
    static let minOutputAmount: UInt64 = 546
}

@objc(DWPreparedStandardSend)
final class PreparedStandardSend: NSObject {
    @objc let txData: Data
    @objc let txHash: Data
    @objc let fee: UInt64
    @objc let address: String
    @objc let amount: UInt64

    /// Wire-order txid (`Transaction.txHashData` convention — the storage/
    /// metadata key order). `txHash` stays DISPLAY order (see `buildAndSign`);
    /// this accessor and the registry `record` calls are the only conversion
    /// points.
    @objc var txidWire: Data { Data(txHash.reversed()) }

    private enum BroadcastState {
        case ready
        case broadcasting
        case accepted
        case unknown(NSError)
    }

    /// Production captures the built SDK transaction in this closure; tests
    /// inject deterministic outcomes without manufacturing an FFI transaction.
    /// Discarding this prepared object abandons the build and releases its
    /// reserved inputs (the captured `FinalizedCoreTransaction`'s deinit).
    private let broadcastAction: () throws -> CoreTransactionBroadcastOutcome
    private let ensureOnlineAction: () throws -> Void

    /// A rejected or local failure returns to `ready`. An ambiguous network
    /// outcome is terminal for this prepared transaction: broadcasting it again
    /// could double-send if the first request actually reached Core.
    ///
    /// The captured `FinalizedCoreTransaction` is single-shot: the first
    /// `broadcastAction` invocation consumes it, so a `ready`-state retry after
    /// a rejected/failed attempt surfaces the SDK's already-consumed error
    /// instead of rebroadcasting (safe — no double send; the reservation is
    /// reconciled Rust-side) and the send must be re-prepared. Only failures
    /// BEFORE the broadcast (`ensureOnlineAction`) leave a retryable object.
    private let claimLock = NSLock()
    private var broadcastState = BroadcastState.ready

    init(
        txData: Data,
        txHash: Data,
        fee: UInt64,
        address: String,
        amount: UInt64,
        coreTransaction: FinalizedCoreTransaction
    ) {
        self.txData = txData
        self.txHash = txHash
        self.fee = fee
        self.address = address
        self.amount = amount
        self.broadcastAction = {
            try SwiftDashSDKTransactionSender.broadcast(coreTransaction)
        }
        self.ensureOnlineAction = {
            try WalletSendService.ensureOnline()
        }
        super.init()
    }

    /// Test seam for the broadcast state machine. The production initializer
    /// above remains the only path that holds a real `FinalizedCoreTransaction`.
    init(
        txData: Data,
        txHash: Data,
        fee: UInt64,
        address: String,
        amount: UInt64,
        ensureOnlineAction: @escaping () throws -> Void = {},
        broadcastAction: @escaping () throws -> CoreTransactionBroadcastOutcome
    ) {
        self.txData = txData
        self.txHash = txHash
        self.fee = fee
        self.address = address
        self.amount = amount
        self.ensureOnlineAction = ensureOnlineAction
        self.broadcastAction = broadcastAction
        super.init()
    }

    @objc(broadcastAndReturnError:)
    func broadcast() throws {
        claimLock.lock()
        switch broadcastState {
        case .ready:
            broadcastState = .broadcasting
            claimLock.unlock()
        case .unknown(let error):
            claimLock.unlock()
            throw error
        case .broadcasting, .accepted:
            claimLock.unlock()
            throw WalletSendService.makeError(
                code: .alreadyBroadcast,
                description: "Transaction was already broadcast or is being broadcast"
            )
        }

        let outcome: CoreTransactionBroadcastOutcome
        do {
            // Catches airplane mode toggled on the confirm sheet after the tx
            // was prepared. Claiming the state first ensures a stored unknown
            // result is returned without consulting changing network state.
            try ensureOnlineAction()
            outcome = try broadcastAction()
        } catch {
            claimLock.lock()
            broadcastState = .ready
            claimLock.unlock()
            throw error
        }

        switch outcome {
        case .accepted:
            claimLock.lock()
            broadcastState = .accepted
            claimLock.unlock()

            // `txHash` is display order (see `buildAndSign`); the registry keys
            // by wire order to match `Transaction.txHashData`.
            WalletSendService.shared.recentSends.record(
                txidWire: Data(txHash.reversed()), address: address, amount: amount, fee: fee)

        case .rejected(_, let reason):
            // Nothing reached the network, so the money is provably still
            // here — say that, because "wasn't sent" alone reads as a loss.
            let error = WalletSendService.makeError(
                code: .broadcastRejected,
                description: WalletSendService.BroadcastOutcomeCopy.rejected,
                diagnostic: reason
            )
            claimLock.lock()
            broadcastState = .ready
            claimLock.unlock()
            throw error

        case .unknown(_, let reason):
            // The old copy told the user to "wait for wallet synchronization"
            // without saying that the wallet is the thing doing the waiting —
            // and it appended the SDK's internal reason, so the dialog ended
            // in "SPV broadcast saw no acceptance signal before dash-spv's
            // acceptance timeout". Neither was actionable, and neither was
            // localized, so a customer on a non-English device got a wall of
            // English (support ticket 32189).
            //
            // What the copy promises is what the shipped SDK does: dash-spv
            // keeps retrying while the wallet is open. It deliberately does
            // NOT promise that retries survive closing the app —
            // launch-time re-registration is dashpay/platform#4659 and is
            // not in the SDK this builds against. See
            // `BroadcastOutcomeCopy.unknown` for when that qualifier can go.
            let error = WalletSendService.makeError(
                code: .broadcastUnknown,
                description: WalletSendService.BroadcastOutcomeCopy.unknown,
                diagnostic: reason
            )
            claimLock.lock()
            broadcastState = .unknown(error)
            claimLock.unlock()
            throw error
        }
    }
}

/// In-memory record of just-broadcast sends, keyed by wire-order txid.
/// Written at every broadcast-success point (standard, selected-input and
/// BIP70 sends); read by the send-success screen (`TxDetailModel`) as the
/// fallback while the Rust persister hasn't written the `PersistentTransaction`
/// row yet. Display-only data — never persisted, never fed back into the SDK.
final class RecentSendsRegistry {
    struct Entry {
        let address: String?
        let amount: UInt64
        let fee: UInt64
        /// Broadcast time — the honest "date" for a success screen shown
        /// before the row exists.
        let date: Date
    }

    private let lock = NSLock()
    private var entries: [Data: Entry] = [:]
    private var insertionOrder: [Data] = []
    /// Oldest-entry eviction bound; a session can't stack more success
    /// screens than this, and rows supersede entries within seconds anyway.
    private let capacity = 16

    /// - Parameter txidWire: wire-order txid (`Transaction.txHashData` byte
    ///   order). Broadcast callers hold display-order hashes — reverse first.
    func record(txidWire: Data, address: String?, amount: UInt64, fee: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if entries[txidWire] == nil {
            insertionOrder.append(txidWire)
            if insertionOrder.count > capacity {
                entries.removeValue(forKey: insertionOrder.removeFirst())
            }
        }
        entries[txidWire] = Entry(address: address, amount: amount, fee: fee, date: Date())
    }

    func entry(forTxidWire txid: Data) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[txid]
    }
}

#if DASHPAY
/// Contacts whose last payment came back with an unknown broadcast outcome.
///
/// The transaction may already be on the network with only the response lost,
/// so a second payment to the same contact could be a duplicate that no later
/// correction undoes. Held for the life of the process rather than a screen: a
/// flag on the amount step was cleared by backing out and reopening the same
/// contact. Never persisted — by the next launch a sync has had the chance to
/// show whether the first payment landed.
final class UnknownContactPaymentOutcomes {
    private let lock = NSLock()
    private var contactIdentityIds: Set<Data> = []

    func record(contactIdentityId: Data) {
        lock.lock()
        defer { lock.unlock() }
        contactIdentityIds.insert(contactIdentityId)
    }

    func contains(contactIdentityId: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return contactIdentityIds.contains(contactIdentityId)
    }
}
#endif

@objc(DWWalletSendService)
final class WalletSendService: NSObject {
    @objc(sharedService) static let shared = WalletSendService()

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-send-service")

    /// `userInfo` key carrying the SDK's own explanation of a broadcast
    /// outcome.
    ///
    /// Deliberately not `NSLocalizedDescriptionKey`: it is engineer-facing
    /// text and must never reach a dialog. Internal rather than file-private
    /// because the point of keeping it is that logging, error inspection and
    /// tests in other files can read it back.
    static let diagnosticKey = "org.dashfoundation.dash.send.diagnostic"

    /// See `RecentSendsRegistry` — the send-success screen's fallback source.
    let recentSends = RecentSendsRegistry()
    #if DASHPAY
    let unknownContactPaymentOutcomes = UnknownContactPaymentOutcomes()
    #endif

    private let sendAuthorizer = SendAuthorizer()

    private override init() {
        super.init()
    }

    /// A normal foreground catch-up must not delay a payment. Only the first
    /// historical sync after restoring a wallet blocks new Core spends.
    /// `isResyncingWallet` is the gate as the current network sees it
    /// (`DWGlobalOptions.isResyncingCurrentNetworkWallet`).
    static func isBlockedByInitialRestoreSync(
        isResyncingWallet: Bool,
        isChainSynced: Bool
    ) -> Bool {
        isResyncingWallet && !isChainSynced
    }

    /// Boundary backstop for programmatic callers. This runs before
    /// authentication and before inputs are selected or reserved.
    private static func ensureInitialRestoreSyncCompleted() throws {
        guard !isBlockedByInitialRestoreSync(
            isResyncingWallet: DWGlobalOptions.sharedInstance().isResyncingCurrentNetworkWallet,
            isChainSynced: SyncingActivityMonitor.shared.state == .syncDone
        ) else {
            throw Self.makeError(
                code: .initialRestoreSync,
                description: NSLocalizedString(
                    "Your restored wallet is completing its initial sync. Sending from your Transparent balance will be available once it finishes.",
                    comment: "Core send blocked during a restored wallet's initial sync"))
        }
    }

    /// Blocks a send when the device is offline. The SDK's broadcast accepts a
    /// tx offline (queuing it to send on reconnect) without throwing, so a send
    /// confirmed after airplane mode was enabled would silently "succeed" with
    /// no feedback — and a user who assumes it failed could retry into a
    /// double-spend. Fail loudly instead. Only blocks when the reachability
    /// monitor is live and reports offline; if monitoring hasn't started, falls
    /// through (fail-open) rather than block a send on an unknown signal.
    static func ensureOnline() throws {
        if NetworkReachability.shared.isMonitoring, !NetworkReachability.shared.isReachable {
            throw Self.makeError(
                code: .offline,
                description: NSLocalizedString(
                    "No internet connection. Reconnect to the network and try again.",
                    comment: "Send blocked while the device is offline"))
        }
    }

    func prepareStandardSendForConfirmation(address: String, amount: UInt64, sessionAuthSufficient: Bool = false) async throws -> PreparedStandardSend {
        Self.logger.info("💸 TXSEND :: preparing standard send")
        try Self.ensureInitialRestoreSyncCompleted()
        try await sendAuthorizer.authorizeSend(spendAmount: amount, sessionAuthSufficient: sessionAuthSufficient)
        let prepared = try buildPreparedStandardSend(address: address, amount: amount)
        Self.logger.info("💸 TXSEND :: standard send prepared")
        return prepared
    }

    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention).
    func send(
        address: String,
        amount: UInt64,
        sessionAuthSufficient: Bool = false
    ) async throws -> Data {
        try Self.ensureInitialRestoreSyncCompleted()
        try Self.ensureOnline()
        let preparedSend = try await prepareStandardSendForConfirmation(
            address: address, amount: amount, sessionAuthSufficient: sessionAuthSufficient)
        try preparedSend.broadcast()
        return preparedSend.txidWire
    }

    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention).
    func sendSwapDeposit(vaultAddress: String, amount: UInt64, memo: String) async throws -> Data {
        try Self.ensureInitialRestoreSyncCompleted()
        try Self.ensureOnline()
        try await sendAuthorizer.authorizeSend(spendAmount: amount)

        do {
            let preparedSend = try buildPreparedSwapDeposit(
                vaultAddress: vaultAddress,
                amount: amount,
                memo: memo
            )
            try preparedSend.broadcast()
            return preparedSend.txidWire
        } catch SwiftDashSDKTransactionSender.SendError.invalidSwapMemo(let reason) {
            throw Self.makeError(code: .invalidSwapMemo, description: reason)
        }
    }

    /// Sweep the entire CoinJoin-account balance into the user's own BIP44
    /// spendable balance. The shared flow behind both post-migration sweep
    /// surfaces (the Home popup and the Settings row): authorize
    /// (PIN/biometric, reusing `sendAuthorizer`) → resolve the user's own
    /// receive address → sweep via `SwiftDashSDKTransactionSender` → force a
    /// CoinJoin-balance re-tally so both surfaces self-clear without waiting
    /// for the next SPV balance event.
    ///
    /// A heavy mixer's account is swept across several independent chunk
    /// transactions, so the sweep can end up partly done. In that case the
    /// accepted chunks are recorded and the balance re-tallied exactly as on a
    /// full sweep, and only then does this throw the error
    /// `coinJoinSweepFailure` picks (`.coinJoinSweepPartial` or
    /// `.broadcastUnknown`) — the caller must not show "moved" over coins that
    /// are still in the account or not yet confirmed.
    ///
    /// - Returns: the CoinJoin balance (duffs) that was swept, for the success
    ///   message; the on-chain amount delivered is this minus the network fee.
    /// - Parameter binding: the wallet and network to sweep; the sweep refuses
    ///   to run unless it is still the active one. Nil pins the wallet active
    ///   on entry.
    @discardableResult
    func sweepCoinJoin(
        expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding? = nil
    ) async throws -> UInt64 {
        // The pin and the amount are read in one hop. The amount is the
        // published CoinJoin balance, which can lag a wallet switch; the
        // sweep itself spends only the pinned wallet's UTXOs.
        let (pinned, amount) = try await MainActor.run {
            () throws -> (SwiftDashSDKTransactionSender.CoinJoinWalletBinding, UInt64) in
            guard let current = SwiftDashSDKTransactionSender.CoinJoinWalletBinding.current(),
                  binding == nil || binding == current else {
                throw SwiftDashSDKTransactionSender.SendError.walletNotReady("the active wallet changed")
            }
            return (current, SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs)
        }
        guard amount > 0 else {
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "No CoinJoin balance to move"
            )
        }

        Self.logger.info("💸 TXSEND :: preparing CoinJoin sweep — balance \(amount, privacy: .public) duffs (\(Double(amount) / 1e8, privacy: .public) DASH)")
        try await sendAuthorizer.authorizeSend(spendAmount: amount)

        guard let resolved = SwiftDashSDKReceiveAddressReader.receiveDestination() else {
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "Could not resolve a destination address for the CoinJoin sweep"
            )
        }
        // The address must be the pinned wallet's own; the sweep itself
        // re-checks that wallet is still the active one.
        if resolved.walletId != pinned.walletId {
            throw SwiftDashSDKTransactionSender.SendError.walletNotReady("the active wallet changed")
        }
        let destination = resolved.address

        Self.logger.info("💸 TXSEND :: CoinJoin sweep destination resolved \(destination, privacy: .public)")
        let outcome: SwiftDashSDKTransactionSender.CoinJoinSweepOutcome
        do {
            outcome = try SwiftDashSDKTransactionSender.sweepCoinJoin(to: destination, expecting: pinned)
        } catch let error as SwiftDashSDKTransactionSender.CoinJoinSweepUnknownError {
            // These may still land: tag them like accepted ones.
            Self.recordSweepTxids(error.unknownTxids)
            // The wallet applied them locally; re-tally so the balance shows it.
            await MainActor.run { SwiftDashSDKWalletState.shared.refreshCoinJoinBalance() }
            let counts = "\(error.failedChunkCount) failed (\(error.unknownTxids.count) unknown)"
            Self.logger.error("💸 TXSEND :: CoinJoin sweep incomplete — nothing accepted, \(counts, privacy: .public)")
            throw Self.coinJoinSweepFailure(
                acceptedCount: 0, failedChunkCount: error.failedChunkCount,
                unknownChunkCount: error.unknownTxids.count,
                reason: Self.sweepChunkFailureReason(error.otherFailure ?? error.underlying)) ?? error
        }
        let txids = outcome.txids
        guard !txids.isEmpty else {
            // A reported-success sweep that produced no transaction is treated
            // as a failure, so the caller surfaces an error (the sweep alert)
            // rather than silently "succeeding" with the balance unchanged.
            Self.logger.error("💸 TXSEND :: CoinJoin sweep returned no transactions for \(amount, privacy: .public) duffs — treating as failure")
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "CoinJoin sweep produced no transactions"
            )
        }
        // Tag every sweep tx's txid so the home screen groups them into the
        // single "CoinJoin Withdrawals" cell. A large UTXO set is swept across
        // multiple transactions (chunks); the sender returns wire-order txids
        // (matching PersistentTransaction.txid / Transaction.txHashData), so
        // record each directly — the unknown-outcome chunks too, which may
        // still land.
        Self.recordSweepTxids(txids + outcome.unknownTxids)

        await MainActor.run {
            SwiftDashSDKWalletState.shared.refreshCoinJoinBalance()
            let post = SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
        Self.logger.info("💸 TXSEND :: post-sweep CoinJoin balance \(post, privacy: .public) duffs (was \(amount, privacy: .public))")
            // The per-network recovery flag is owned solely by the recovery scan-
            // completion path (SwiftDashSDKSPVCoordinator.maybeCompleteCoinJoinRecovery,
            // which marks recovered once the one-time wide scan reaches .synced). A
            // sweep may be partial across chunks and does NOT imply the wide scan
            // completed, so it must not mark recovered here — doing so would suppress
            // a legitimate re-widen after an interrupted scan.
        }

        // Everything above ran for the accepted chunks — the txids are in the
        // withdrawal store and the balance is re-tallied — so it is safe to fail
        // here. Reported as a failure because a success screen would say every
        // coin moved: a rejected chunk's coins are still in the account, and an
        // unknown chunk's are not confirmed yet.
        if let failure = Self.coinJoinSweepFailure(
            acceptedCount: txids.count, failedChunkCount: outcome.failedChunkCount,
            unknownChunkCount: outcome.unknownTxids.count,
            reason: outcome.firstFailure.map(Self.sweepChunkFailureReason)) {
            let diagnostic = failure.userInfo[Self.diagnosticKey] as? String ?? "-"
            Self.logger.error("💸 TXSEND :: CoinJoin sweep incomplete (code \(failure.code, privacy: .public)) — \(diagnostic, privacy: .public)")
            throw failure
        }
        return amount
    }

#if DASHPAY
    /// DashPay pay-to-contact (migration Row #18 phase 6). The caller
    /// shows its confirmation UI FIRST — the user's explicit "Pay" tap
    /// is what invokes this — then this method runs the spend-auth
    /// gate (same `sendAuthorizer` as every other spend) and the
    /// single-shot SDK payment: `sendDashPayPayment` derives the
    /// contact's DIP-15 receive address Rust-side from the registered
    /// external contact account, builds, signs, and broadcasts
    /// atomically. There is no separate prepare/broadcast split on
    /// this path, so it must never be called before the user
    /// confirms. The network fee is computed SDK-side on top of
    /// `amount`; callers cap input at `WalletBalance.maxSendable`.
    ///
    /// - Returns: the 32-byte transaction id plus the exact network
    ///   fee (duffs) of the broadcast transaction, from the builder.
    @discardableResult
    func sendToContact(
        contactIdentityId: Data,
        amount: UInt64,
        memo: String? = nil
    ) async throws -> (txid: Data, feeDuffs: UInt64) {
        Self.logger.info("💸 TXSEND :: pay-to-contact starting — \(amount, privacy: .public) duffs")
        // Refused before the PIN prompt: see `UnknownContactPaymentOutcomes`.
        if unknownContactPaymentOutcomes.contains(contactIdentityId: contactIdentityId) {
            throw Self.makeError(
                code: .broadcastUnknown,
                description: "A previous payment to this contact could not be confirmed. Don't send it again; wait for wallet synchronization."
            )
        }
        try Self.ensureInitialRestoreSyncCompleted()
        // spendAmount engages the biometric spending limit (C7.4) —
        // without it the gate is non-monetary and Face ID alone would
        // authorize a contact payment of any size.
        try await sendAuthorizer.authorizeSend(spendAmount: amount)

        let context: (wallet: ManagedPlatformWallet, ourId: Data)? = await MainActor.run {
            guard let wallet = SwiftDashSDKHost.shared.wallet,
                  let ourId = DWCurrentUserIdentityInfo.shared.identityId else {
                return nil
            }
            return (wallet, ourId)
        }
        guard let context else {
            throw Self.makeError(
                code: .dashPayPaymentUnavailable,
                description: "Wallet or DashPay identity is not ready"
            )
        }

        let (txid, feeDuffs): (Data, UInt64)
        do {
            (txid, feeDuffs) = try await context.wallet.sendDashPayPayment(
                fromIdentityId: context.ourId,
                toContactIdentityId: contactIdentityId,
                amountDuffs: amount,
                memo: memo)
        } catch {
            let mapped = Self.contactPaymentError(from: error)
            if Self.isBroadcastUnknownError(mapped as NSError) {
                unknownContactPaymentOutcomes.record(contactIdentityId: contactIdentityId)
            }
            throw mapped
        }
        Self.logger.info("💸 TXSEND :: pay-to-contact broadcast, txid \(txid.map { String(format: "%02x", $0) }.joined(), privacy: .public), fee \(feeDuffs, privacy: .public) duffs")
        // The send-success screen resolves the amount from this registry while
        // the Rust persister hasn't written the transaction row yet — same as
        // every other broadcast-success point. `txid` is already wire order
        // (Rust hands back `to_raw_hash().to_byte_array()`), which is the
        // registry's key convention. No address: the DIP-15 receive address is
        // derived inside Rust and never crosses the FFI boundary.
        recentSends.record(txidWire: txid, address: nil, amount: amount, fee: feeDuffs)
        return (txid: txid, feeDuffs: feeDuffs)
    }
#endif

    @objc(prepareStandardSendForConfirmationWithAddress:amount:completion:)
    func prepareStandardSendForConfirmation(
        address: String,
        amount: UInt64,
        completion: @escaping (PreparedStandardSend?, NSError?) -> Void
    ) {
        Task {
            do {
                let preparedSend = try await prepareStandardSendForConfirmation(address: address, amount: amount)
                await MainActor.run {
                    completion(preparedSend, nil)
                }
            } catch {
                await MainActor.run {
                    completion(nil, error as NSError)
                }
            }
        }
    }

    @objc(isAuthenticationCancelledError:)
    static func isAuthenticationCancelledError(_ error: NSError) -> Bool {
        error.domain == errorDomain && error.code == ErrorCode.authenticationCancelled.rawValue
    }

    @objc(isBroadcastRejectedError:)
    static func isBroadcastRejectedError(_ error: NSError) -> Bool {
        error.domain == errorDomain && error.code == ErrorCode.broadcastRejected.rawValue
    }

    @objc(isBroadcastUnknownError:)
    static func isBroadcastUnknownError(_ error: NSError) -> Bool {
        error.domain == errorDomain && error.code == ErrorCode.broadcastUnknown.rawValue
    }

    /// ObjC facade over `AuthenticationGate` for completion-based callers
    /// (DWPaymentProcessor's broadcast paths). Reads the user's biometric
    /// preference like every other spend gate, and guarantees the completion
    /// fires exactly once, on the main actor — a silently-non-presenting PIN
    /// prompt reports as not-authenticated after the watchdog instead of
    /// never calling back.
    @objc(authenticateSpendWithCompletion:)
    static func authenticateSpend(completion: @escaping (_ authenticated: Bool, _ cancelled: Bool) -> Void) {
        Task { @MainActor in
            let outcome = await AuthenticationGate.authenticate(
                biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled)
            completion(outcome == .ok, outcome == .cancelled)
        }
    }

    /// Tag sweep txids (wire order) so the home screen groups them into the
    /// single "CoinJoin Withdrawals" cell — the unknown-outcome chunks too,
    /// which may still land.
    private static func recordSweepTxids(_ txids: [Data]) {
        for txid in txids {
            CoinJoinWithdrawalStore.shared.record(txid: txid)
        }
        let hexes = txids.map { Data($0.reversed()).map { String(format: "%02x", $0) }.joined() }
        logger.info("💸 TXSEND :: recorded \(txids.count, privacy: .public) sweep txid(s) in CoinJoinWithdrawalStore: \(hexes.joined(separator: ","), privacy: .public)")
    }

    /// An error's type and code for the exported log. Not its description:
    /// send and builder errors quote txids, outpoints and addresses, which
    /// lead to the wallet's own addresses (the sender's os.Logger keeps the
    /// detail, outside the export).
    static func logSummary(of error: Error) -> String {
        let nsError = error as NSError
        return "\(type(of: error)) \(nsError.domain) #\(nsError.code)"
    }

    /// A failed sweep for the exported log: `logSummary(of:)` plus what it
    /// says without a txid — the diagnostic `coinJoinSweepFailure` attached,
    /// a send error's reason, or this service's own description.
    static func coinJoinSweepLogLine(for error: Error) -> String {
        let nsError = error as NSError
        let detail: String?
        if let diagnostic = nsError.userInfo[diagnosticKey] as? String {
            detail = diagnostic
        } else if error is SwiftDashSDKTransactionSender.SendError {
            detail = sweepChunkFailureReason(error)
        } else if nsError.domain == errorDomain {
            detail = nsError.localizedDescription
        } else {
            detail = nil
        }
        return logSummary(of: error) + (detail.map { " (\($0))" } ?? "")
    }

    /// A chunk's broadcast error for the diagnostic: the SDK's reason for a
    /// rejected or unknown outcome, without the txid it also carries, or for
    /// a wallet that is not ready; anything else (a builder error may quote
    /// an outpoint) as `logSummary(of:)`.
    static func sweepChunkFailureReason(_ error: Error) -> String {
        switch error {
        case SwiftDashSDKTransactionSender.SendError.transactionStatusUnknown(_, let reason):
            return "unknown: \(reason)"
        case SwiftDashSDKTransactionSender.SendError.transactionRejected(_, let reason):
            return "rejected: \(reason)"
        case SwiftDashSDKTransactionSender.SendError.walletNotReady(let reason):
            return "wallet not ready: \(reason)"
        default:
            return logSummary(of: error)
        }
    }

    /// The error a sweep with failed chunks surfaces; nil when none failed,
    /// or when none was accepted or unknown (the sender throws that case's
    /// chunk error itself and never gets here).
    ///
    /// - Every failed chunk ended unknown: `.broadcastUnknown`, not offered
    ///   again. The wallet applies a transaction before it waits for peers, so
    ///   those coins already read as spent and a re-run has nothing to sweep.
    /// - Otherwise, when a chunk was accepted or may still land: partial. The
    ///   other failed chunks' coins are still in the CoinJoin account, and a
    ///   re-run sweeps only them. An unknown chunk counts as moved here, as
    ///   the re-tallied balance and the withdrawal history already show it.
    ///
    /// The diagnostic carries the chunk counts and `reason` (one failed
    /// chunk's error).
    static func coinJoinSweepFailure(
        acceptedCount: Int, failedChunkCount: Int, unknownChunkCount: Int, reason: String? = nil
    ) -> NSError? {
        guard failedChunkCount > 0 else { return nil }
        let diagnostic = "CoinJoin sweep: \(acceptedCount) accepted, \(unknownChunkCount) unknown, "
            + "\(failedChunkCount - unknownChunkCount) failed otherwise" + (reason.map { "; \($0)" } ?? "")
        if unknownChunkCount == failedChunkCount {
            return makeError(
                code: .broadcastUnknown,
                description: BroadcastOutcomeCopy.coinJoinSweepUnknown,
                diagnostic: diagnostic)
        }
        guard acceptedCount > 0 || unknownChunkCount > 0 else { return nil }
        return makeError(code: .coinJoinSweepPartial, description: "CoinJoin sweep incomplete", diagnostic: diagnostic)
    }

    /// Whether a failed CoinJoin sweep may be offered again right away: not
    /// when its transactions may all still land.
    static func isCoinJoinSweepRetryable(_ error: Error) -> Bool {
        !isBroadcastUnknownError(error as NSError)
    }

    /// User-facing message for a CoinJoin sweep failure, or nil if the user
    /// simply cancelled authentication (callers stay silent). Centralizes the
    /// cancel predicate + copy so every sweep entry point behaves identically.
    ///
    /// A partial sweep gets its own copy: "try again" is still the right
    /// action, but telling the user nothing moved would contradict the
    /// transactions already in their history. An unknown outcome keeps its
    /// own "don't send it again" copy.
    static func coinJoinSweepUserMessage(for error: Error) -> String? {
        let nsError = error as NSError
        guard !isAuthenticationCancelledError(nsError) else { return nil }
        if isBroadcastUnknownError(nsError) {
            return nsError.localizedDescription
        }
        if nsError.domain == errorDomain, nsError.code == ErrorCode.coinJoinSweepPartial.rawValue {
            return NSLocalizedString(
                "Some of your CoinJoin funds were moved. Please try again to move the rest.",
                comment: "CoinJoin")
        }
        return NSLocalizedString(
            "Couldn't move your CoinJoin funds. Please try again.", comment: "CoinJoin")
    }

    private func buildPreparedStandardSend(address: String, amount: UInt64) throws -> PreparedStandardSend {
        let (tx, txHash) = try SwiftDashSDKTransactionSender.buildAndSign(address: address, amount: amount)

        return PreparedStandardSend(
            txData: try tx.serializedData(),
            txHash: txHash,
            fee: tx.fee,
            address: address,
            amount: amount,
            coreTransaction: tx
        )
    }

    private func buildPreparedSwapDeposit(vaultAddress: String, amount: UInt64, memo: String) throws -> PreparedStandardSend {
        let (tx, txHash) = try SwiftDashSDKTransactionSender.buildAndSignSwapDeposit(
            vaultAddress: vaultAddress,
            amountDuffs: amount,
            memo: memo
        )

        return PreparedStandardSend(
            txData: try tx.serializedData(),
            txHash: txHash,
            fee: tx.fee,
            address: vaultAddress,
            amount: amount,
            coreTransaction: tx
        )
    }
}

/// The prompt `AuthenticationGate` drives and cancels: the session flag and
/// the presenting entry point. Production is `AuthenticationService.shared`.
@MainActor
protocol SendAuthenticationPrompting: AnyObject {
    var didAuthenticate: Bool { get }
    func authenticate(usingBiometrics: Bool, spendAmount: UInt64?) async -> AuthenticationService.AuthOutcome
}

extension AuthenticationService: SendAuthenticationPrompting {}

/// A timeout cancels this request's PIN/biometric prompt and waits for its
/// dismissal before returning, so callers can safely restore their overlay.
enum AuthenticationGate {
    enum Outcome { case ok, cancelled, failed, timedOut }

    /// `sessionAuthSufficient` restores the legacy `seedWithPrompt` semantic
    /// (`DSWallet.seedPhraseIfAuthenticated`, DSWallet.m:797) for programmatic
    /// protocol sends: an already-authenticated session (`didAuthenticate`,
    /// set by the lock-screen PIN/biometric unlock) passes without presenting
    /// any UI. Interactive gates keep the default `false` and prompt per send.
    @MainActor
    static func authenticate(biometric: Bool,
                             sessionAuthSufficient: Bool = false,
                             spendAmount: UInt64? = nil,
                             timeout: TimeInterval = 120,
                             prompt: any SendAuthenticationPrompting = AuthenticationService.shared) async -> Outcome {
        if sessionAuthSufficient, prompt.didAuthenticate {
            WalletSendService.logger.info("💸 TXSEND :: session-authenticated — skipping auth prompt")
            return .ok
        }
        return await withCheckedContinuation { continuation in
            var didResume = false
            func safeResume(_ outcome: Outcome) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: outcome)
            }

            var didTimeOut = false
            let authentication = Task { @MainActor in
                let outcome = await prompt.authenticate(
                    usingBiometrics: biometric, spendAmount: spendAmount)
                if didTimeOut {
                    safeResume(.timedOut)
                    return
                }
                switch outcome {
                case .authenticated:
                    safeResume(.ok)
                case .cancelled:
                    safeResume(.cancelled)
                case .failed:
                    safeResume(.failed)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !didResume else { return }
                didTimeOut = true
                authentication.cancel()
            }
        }
    }
}

private final class SendAuthorizer {
    /// `spendAmount` enforces the biometric spending limit (Bug #3): a
    /// send over the remaining allowance skips biometrics and requires the
    /// PIN; a biometric-authorized send decrements the allowance. Nil for
    /// non-monetary gates.
    @MainActor
    func authorizeSend(spendAmount: UInt64? = nil, sessionAuthSufficient: Bool = false) async throws {
        let outcome = await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            sessionAuthSufficient: sessionAuthSufficient,
            spendAmount: spendAmount)

        switch outcome {
        case .ok:
            WalletSendService.logger.info("💸 TXSEND :: user authorized send")
            return
        case .cancelled:
            WalletSendService.logger.info("💸 TXSEND :: user cancelled authentication")
            throw WalletSendService.makeError(
                code: .authenticationCancelled,
                description: "Authentication cancelled"
            )
        case .failed, .timedOut:
            WalletSendService.logger.error("💸 TXSEND :: authentication failed (\(outcome == .timedOut ? "timed out" : "failed"))")
            throw WalletSendService.makeError(
                code: .authenticationFailed,
                description: "Authentication failed"
            )
        }
    }
}

private extension WalletSendService {
    enum ErrorCode: Int {
        case authenticationCancelled = 1
        case authenticationFailed = 2
        case coinJoinSweepUnavailable = 4
        case alreadyBroadcast = 5
        case dashPayPaymentUnavailable = 6
        case initialRestoreSync = 7
        case offline = 8
        case broadcastRejected = 9
        case broadcastUnknown = 10
        case invalidSwapMemo = 11
        case coinJoinSweepPartial = 12
    }

    static let errorDomain = "org.dashfoundation.dash.wallet-send-service"

    /// Translate the SDK's contact-payment errors into ones the app acts on.
    ///
    /// A broadcast outcome the SDK could not confirm becomes this service's
    /// `broadcastUnknown`, which `sendToContact` turns into a per-contact lock
    /// and the amount step into a terminal state — the SDK's own error type
    /// matched neither. A definitive rejection becomes `broadcastRejected`.
    ///
    /// A contact's DIP-15 external account is built in the background from the
    /// counterparty's contact request; until it exists the SDK fails the send
    /// with "Invalid identity data: No DashpayExternalAccount found for contact
    /// <id> — call register_external_contact_account first". That reached users
    /// verbatim in an alert: it names an API only the SDK can call, so it reads
    /// as an instruction for something they cannot do.
    ///
    /// Mapped here rather than at the presentation layer so the diagnostic stops
    /// at the boundary that owns the SDK call, and every present and future
    /// caller of `sendToContact` gets the same treatment. Deliberately narrow —
    /// anything else is returned untouched rather than hidden behind a generic
    /// message.
    static func contactPaymentError(from error: Error) -> Error {
        // The SDK reports the broadcast outcome in its own error type; the rest
        // of the app — the amount step's terminal state included — recognises
        // it only in this service's domain, the same codes a standard send gets.
        switch error as? PlatformWalletError {
        case .transactionBroadcastUnconfirmed(let reason):
            return makeError(
                code: .broadcastUnknown,
                description: "We couldn't confirm whether the transaction was accepted. Don't send it again; wait for wallet synchronization. \(reason)"
            )
        case .transactionBroadcastRejected(let reason):
            return makeError(
                code: .broadcastRejected,
                description: "The transaction wasn't sent. You can try again. \(reason)"
            )
        default:
            break
        }
        let description = error.localizedDescription
        guard description.contains("DashpayExternalAccount")
            || description.contains("register_external_contact_account")
        else {
            return error
        }
        return makeError(
            code: .dashPayPaymentUnavailable,
            description: NSLocalizedString(
                "This contact's payment channel isn't ready yet. It's still being set up in the background — please try again in a few minutes.",
                comment: "DashPay Contacts"))
    }

    /// The two broadcast outcomes a user can be shown, in one place.
    ///
    /// Every send route ends in one of these, and there is more than one
    /// route, so the strings live here rather than in each route: built
    /// independently, they drift apart, and one route ends up showing
    /// unlocalized English with the SDK's internal reason appended.
    enum BroadcastOutcomeCopy {
        /// Nothing reached the network, so the money is provably still here —
        /// say that, because "wasn't sent" alone reads as a loss.
        static var rejected: String {
            NSLocalizedString(
                "The transaction wasn't sent, so nothing left your wallet. You can try again.",
                comment: "Send failed before any bytes reached the network")
        }

        /// The transaction went out and no acceptance signal came back.
        ///
        /// The retry this promises is the one the shipped SDK actually
        /// performs: dash-spv keeps rebroadcasting a transaction it is
        /// tracking, for as long as the process lives. That is also why the
        /// copy says "while it's open" rather than making an unqualified
        /// promise — closing the app ends the retry today, and telling the
        /// user otherwise would be worse than the old wording, because they
        /// would close it believing the wallet had the situation in hand.
        ///
        /// dashpay/platform#4659 re-registers unconfirmed sends for rebroadcast
        /// at every launch, which makes closing the app harmless. This sentence
        /// stays true either way; it can lose the qualifier once that ships.
        static var unknown: String {
            NSLocalizedString(
                "We couldn't confirm the transaction reached the network. Don't send it again — the wallet keeps trying while it's open, and your balance will update as soon as it goes through.",
                comment: "Send dispatched but no network acceptance signal arrived")
        }

        /// `unknown` for a CoinJoin sweep, whose chunks were not all
        /// confirmed. Same "while it's open" qualifier, for the same reason.
        static var coinJoinSweepUnknown: String {
            NSLocalizedString(
                "We couldn't confirm all of your CoinJoin funds reached the network. Don't move them again — the wallet keeps trying while it's open, and your balance will update as soon as they go through.",
                comment: "CoinJoin sweep dispatched but no network acceptance signal arrived for some of it")
        }
    }

    static func makeError(
        code: ErrorCode,
        description: String,
        diagnostic: String? = nil
    ) -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: description]
        if let diagnostic, !diagnostic.isEmpty {
            userInfo[diagnosticKey] = diagnostic
        }
        return NSError(
            domain: errorDomain,
            code: code.rawValue,
            userInfo: userInfo
        )
    }
}

// MARK: - Initial restore sync gate

/// The persisted "first historical sync after a restore" gate: the
/// `DWGlobalOptions.resyncingWallet` flag plus the network scopes whose
/// historical scans armed it. `scopes == nil` means every network (the
/// phrase restore provisions the phrase on all of them); keychain recovery
/// arms one `persistenceScope` at a time. Pure, so the arm, clear and block
/// rules are testable without `NSUserDefaults`; `DWGlobalOptions` maps it
/// onto its two keys.
struct InitialRestoreSyncGate: Equatable {
    var isArmed: Bool
    /// Armed scopes, sorted; `nil` = every network. Ignored while disarmed.
    var scopes: [String]?

    static let disarmed = InitialRestoreSyncGate(isArmed: false, scopes: nil)
    static let everyNetwork = InitialRestoreSyncGate(isArmed: true, scopes: nil)

    /// Arm for `scope`. An every-network arm is never narrowed, and a
    /// second network joins the first instead of replacing it: keychain
    /// recovery runs on every network whose rows are missing, and each of
    /// those scans has to finish before its own network may spend.
    func arming(scope: String) -> InitialRestoreSyncGate {
        if isArmed, scopes == nil { return self }
        var armed = Set(isArmed ? (scopes ?? []) : [])
        armed.insert(scope)
        return InitialRestoreSyncGate(isArmed: true, scopes: armed.sorted())
    }

    /// `.syncDone` on `scope`: lifts an every-network arm, or that one
    /// scope's arm, leaving the other networks' arms in place. An unknown
    /// scope lifts nothing it cannot attribute.
    func clearing(scope: String?) -> InitialRestoreSyncGate {
        guard isArmed, let scopes else { return .disarmed }
        guard let scope else { return self }
        let remaining = scopes.filter { $0 != scope }
        return remaining.isEmpty ? .disarmed : InitialRestoreSyncGate(isArmed: true, scopes: remaining)
    }

    /// Whether the gate blocks Core spends on `scope`. An unknown current
    /// network is treated as blocked: unknown readiness must not spend.
    func blocks(scope: String?) -> Bool {
        guard isArmed else { return false }
        guard let scopes, let scope else { return true }
        return scopes.contains(scope)
    }
}
