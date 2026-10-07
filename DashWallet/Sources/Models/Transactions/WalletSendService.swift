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
    /// The wallet that signed the send and the chain it signed on, read in
    /// the same main-actor hop as the build: an unknown outcome is followed
    /// under them even if another wallet or chain is bound by then. Nil only
    /// in tests (it then falls back to what is bound).
    let origin: WalletChainScope?

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
        origin: WalletChainScope?,
        coreTransaction: FinalizedCoreTransaction
    ) {
        self.txData = txData
        self.txHash = txHash
        self.fee = fee
        self.address = address
        self.amount = amount
        self.origin = origin
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
        origin: WalletChainScope? = nil,
        ensureOnlineAction: @escaping () throws -> Void = {},
        broadcastAction: @escaping () throws -> CoreTransactionBroadcastOutcome
    ) {
        self.txData = txData
        self.txHash = txHash
        self.fee = fee
        self.address = address
        self.amount = amount
        self.origin = origin
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
            let error = WalletSendService.unknownOutcomeError(
                txidWire: txidWire, address: address, amount: amount, reason: reason, origin: origin)
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

/// Single-flight admission for CoinJoin sweeps (`WalletSendService.sweepCoinJoin`),
/// keyed by what a sweep is bound to — its wallet and chain. A call for the
/// key that is running joins that sweep and gets its result; a call for
/// another key waits for it to end, whatever its outcome, then starts its own.
/// The slot frees when the running sweep ends, failures included.
final class CoinJoinSweepAdmission<Key: Equatable> {
    private var running: (key: Key, task: Task<UInt64, Error>)?
    private let lock = NSLock()

    /// `sweep` runs only if this call starts the sweep for `key`.
    func run(_ key: Key, sweep: @escaping () async throws -> UInt64) async throws -> UInt64 {
        while true {
            let next: (task: Task<UInt64, Error>, isThisKeys: Bool) = lock.withLock {
                if let running {
                    return (running.task, running.key == key)
                }
                let started = Task { [self] in
                    defer { lock.withLock { running = nil } }
                    return try await sweep()
                }
                running = (key, started)
                return (started, true)
            }
            if next.isThisKeys {
                return try await next.task.value
            }
            _ = try? await next.task.value
        }
    }
}

@objc(DWWalletSendService)
final class WalletSendService: NSObject {
    @objc(sharedService) static let shared = WalletSendService()

    /// `userInfo` key carrying the SDK's own explanation of a broadcast
    /// outcome.
    ///
    /// Deliberately not `NSLocalizedDescriptionKey`: it is engineer-facing
    /// text and must never reach a dialog. Internal rather than file-private
    /// because the point of keeping it is that logging, error inspection and
    /// tests in other files can read it back.
    static let diagnosticKey = "org.dashfoundation.dash.send.diagnostic"

    /// `userInfo` key, true on a `broadcastUnknown` error whose send is
    /// followed in the history (`unknownOutcomeError`).
    static let followedKey = "org.dashfoundation.dash.send.followed"

    /// `userInfo` key, the wire-order txid (`Data`) of a `broadcastUnknown`
    /// send whose transaction is known (`unknownOutcomeError`).
    @objc static let unknownTxidWireKey = "org.dashfoundation.dash.send.unknownTxidWire"

    /// The txid of a send whose broadcast outcome is unknown, when it is known:
    /// a caller that books the send against its txid (an order, a swap gate)
    /// keeps doing so, as the transaction may still settle.
    static func unknownOutcomeTxidWire(of error: Error) -> Data? {
        let error = error as NSError
        guard isBroadcastUnknownError(error) else { return nil }
        return error.userInfo[unknownTxidWireKey] as? Data
    }

    /// See `RecentSendsRegistry` — the send-success screen's fallback source.
    let recentSends = RecentSendsRegistry()
    #if DASHPAY
    let unknownContactPaymentOutcomes = UnknownContactPaymentOutcomes()
    #endif

    private let sendAuthorizer = SendAuthorizer()
    /// The CoinJoin sweep in flight, if any — see `sweepCoinJoin()`.
    private let sweepAdmission = CoinJoinSweepAdmission<CoinJoinSweepKey>()

    private override init() {
        super.init()
    }

    /// A normal foreground catch-up must not delay a payment. Only the first
    /// historical sync after restoring a wallet blocks new Core spends.
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
            isResyncingWallet: DWGlobalOptions.sharedInstance().isResyncingWallet,
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
        DWLogger.log("💸 TXSEND :: preparing standard send")
        try Self.ensureInitialRestoreSyncCompleted()
        try await sendAuthorizer.authorizeSend(spendAmount: amount, sessionAuthSufficient: sessionAuthSufficient)
        let prepared = try buildPreparedStandardSend(address: address, amount: amount)
        DWLogger.log("💸 TXSEND :: standard send prepared")
        return prepared
    }

    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention).
    ///
    /// Holds routing for the network wait
    /// (`SwiftDashSDKTransactionSender.waitingForNetwork`).
    func send(
        address: String,
        amount: UInt64,
        inputSelector: SingleInputAddressSelector? = nil,
        adjustAmountDownwards: Bool = false,
        sessionAuthSufficient: Bool = false
    ) async throws -> Data {
        try await performSend(
            address: address, amount: amount, inputSelector: inputSelector,
            adjustAmountDownwards: adjustAmountDownwards, sessionAuthSufficient: sessionAuthSufficient,
            holdingRouting: true)
    }

    /// `send` without the routing hold. Used for CrowdNode's sends (hidden in
    /// this release; see `SendCoinsService.sendCoinsWithoutRoutingHold`).
    func sendWithoutRoutingHold(
        address: String,
        amount: UInt64,
        inputSelector: SingleInputAddressSelector? = nil,
        adjustAmountDownwards: Bool = false,
        sessionAuthSufficient: Bool = false
    ) async throws -> Data {
        try await performSend(
            address: address, amount: amount, inputSelector: inputSelector,
            adjustAmountDownwards: adjustAmountDownwards, sessionAuthSufficient: sessionAuthSufficient,
            holdingRouting: false)
    }

    private func performSend(
        address: String,
        amount: UInt64,
        inputSelector: SingleInputAddressSelector?,
        adjustAmountDownwards: Bool,
        sessionAuthSufficient: Bool,
        holdingRouting: Bool
    ) async throws -> Data {
        try Self.ensureInitialRestoreSyncCompleted()
        // Also covers the selected-input path below, whose `buildAndSignFromAddress`
        // broadcasts internally and never reaches `PreparedStandardSend.broadcast()`.
        try Self.ensureOnline()
        if let inputSelector {
            DWLogger.log("💸 TXSEND :: routing to selected-input (SwiftDashSDK) path")
            try await sendAuthorizer.authorizeSend(spendAmount: amount, sessionAuthSufficient: sessionAuthSufficient)
            do {
                let (_, fee, txHash) = try await SwiftDashSDKTransactionSender.buildAndSignFromAddress(
                    fromAddress: inputSelector.address,
                    to: address,
                    amount: amount,
                    adjustAmountDownwards: adjustAmountDownwards,
                    holdingRouting: holdingRouting
                )
                // buildAndSignFromAddress broadcasts internally; txHash is
                // display order — reverse to the wire-order registry key.
                let txidWire = Data(txHash.reversed())
                recentSends.record(
                    txidWire: txidWire, address: address, amount: amount, fee: fee)
                return txidWire
            } catch SwiftDashSDKTransactionSender.SendError.insufficientSelectedFunds(let selected, let amount, let fee) {
                throw Self.makeError(
                    code: .insufficientSelectedFunds,
                    description: "Not enough funds. Selected: \(selected), Amount: \(amount), Fee: \(fee)"
                )
            } catch SwiftDashSDKTransactionSender.SendError.transactionRejected(_, let reason) {
                throw Self.makeError(
                    code: .broadcastRejected,
                    description: BroadcastOutcomeCopy.rejected,
                    diagnostic: reason
                )
            } catch SwiftDashSDKTransactionSender.SendError.transactionStatusUnknown(let txid, let reason, let origin) {
                // `txid` is the display-order hash `buildAndSignFromAddress` computed.
                guard let txHash = Data(hex: txid), txHash.count == 32 else {
                    throw Self.makeError(
                        code: .broadcastUnknown,
                        description: BroadcastOutcomeCopy.unknown,
                        diagnostic: reason)
                }
                // The selected-input route is CrowdNode's: signal transactions
                // and amounts that may have been lowered by the fee, so it
                // settles without a "went through" notice.
                throw Self.unknownOutcomeError(
                    txidWire: Data(txHash.reversed()), address: address, amount: amount, reason: reason,
                    notifies: false, origin: origin)
            } catch {
                throw Self.sendBuildError(from: error)
            }
        }

        let preparedSend = try await prepareStandardSendForConfirmation(
            address: address, amount: amount, sessionAuthSufficient: sessionAuthSufficient)
        try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: holdingRouting) {
            try preparedSend.broadcast()
        }
        return preparedSend.txidWire
    }

    /// - Returns: the wire-order txid of the broadcast transaction
    ///   (`Transaction.txHashData` convention).
    ///
    /// Holds routing for the network wait
    /// (`SwiftDashSDKTransactionSender.waitingForNetwork`).
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
            try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: true) {
                try preparedSend.broadcast()
            }
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
    /// full sweep, and only then does this throw `.coinJoinSweepPartial` — the
    /// caller must not show "moved" over coins that are still in the account.
    ///
    /// - Returns: the CoinJoin balance (duffs) that was swept, for the success
    ///   message; the on-chain amount delivered is this minus the network fee.
    ///
    /// Single-flight per wallet: a sweep waits on the network for up to a
    /// minute per chunk, and four surfaces offer it (Home popup, Move Funds sheet,
    /// Settings, Tools). A call made while the same
    /// wallet's sweep is running joins it — no second PIN prompt, no second
    /// snapshot of coins the first is already spending — and gets its result.
    /// A call for another wallet waits for the running sweep to end, then
    /// starts its own.
    ///
    /// `onNetworkWait` is called on the main actor with true once the user has
    /// authorized and the sweep starts waiting on the network, and with false
    /// when it stops — for a surface with no progress state of its own. Only
    /// the call that starts the sweep gets it; a joining call shows nothing
    /// and gets the running sweep's result.
    ///
    /// Holds routing for the network wait
    /// (`SwiftDashSDKTransactionSender.waitingForNetwork`).
    @discardableResult
    func sweepCoinJoin(onNetworkWait: (@MainActor (Bool) -> Void)? = nil) async throws -> UInt64 {
        // Read once, here, in one hop: the destination, its wallet, its
        // network and its chain are what the sweep is bound to, and what a
        // later call joins on.
        let target = await MainActor.run { () -> CoinJoinSweepTarget? in
            guard let destination = SwiftDashSDKReceiveAddressReader.receiveDestination(),
                  let network = SwiftDashSDKHost.shared.runningNetwork,
                  let scope = WalletChainScope.bound, scope.walletId == destination.walletId else { return nil }
            return CoinJoinSweepTarget(address: destination.address, scope: scope, network: network)
        }
        guard let target else {
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "Could not resolve a destination address for the CoinJoin sweep"
            )
        }
        return try await sweepAdmission.run(CoinJoinSweepKey(scope: target.scope, network: target.network)) {
            [self] in try await performCoinJoinSweep(target, onNetworkWait: onNetworkWait)
        }
    }

    /// What a later call joins on: the same wallet on the same chain (two
    /// devnets share the wallet id and the `Network`).
    private struct CoinJoinSweepKey: Equatable {
        let scope: WalletChainScope
        let network: Network
    }

    private struct CoinJoinSweepTarget {
        let address: String
        /// The wallet `address` was read from and the chain it was read on.
        /// The network alone does not tell two devnets apart.
        let scope: WalletChainScope
        let network: Network
        var walletId: Data { scope.walletId }

        /// The user's persisted selection still names this wallet on this
        /// chain (the configured devnet included). Stays true through a
        /// restart of the same wallet.
        var isSelected: Bool {
            WalletEnvironment.networkKind == WalletEnvironment.networkKind(for: network)
                && WalletEnvironment.activeWalletId(for: WalletEnvironment.networkKind) == walletId
                && network.persistenceScope == scope.chain
        }

        /// The host runs this wallet on this chain right now.
        @MainActor var isRunning: Bool {
            WalletChainScope.bound == scope
        }
    }

    private static func coinJoinSweepInterruptedError() -> NSError {
        makeError(
            code: .coinJoinSweepInterrupted,
            description: "CoinJoin sweep stopped: its wallet is no longer selected")
    }

    /// Records a finished sweep's accepted chunks under the wallet that ran
    /// it, so the home screen groups them into the single "CoinJoin
    /// Withdrawals" cell — the sender returns wire-order txids (matching
    /// `PersistentTransaction.txid` / `Transaction.txHashData`) — and throws
    /// for an outcome with nothing to show for it.
    ///
    /// If the user switched to another wallet or network while the sweep ran,
    /// the chunks that went out stay with the wallet that left (unless it was
    /// removed meanwhile) and it throws `coinJoinSweepInterrupted`: no alert,
    /// the screen that started the sweep belongs to that wallet too.
    ///
    /// - Parameters:
    ///   - record: `(txid, walletId)` into the withdrawal store.
    static func recordCoinJoinSweepChunks(
        _ outcome: SwiftDashSDKTransactionSender.CoinJoinSweepOutcome,
        ofWallet walletId: Data,
        amount: UInt64,
        isWalletSelected: Bool,
        isWalletStored: () -> Bool,
        record: (_ txid: Data, _ walletId: Data) -> Void
    ) throws {
        let txids = outcome.txids
        guard isWalletSelected else {
            if isWalletStored() {
                for txid in txids {
                    record(txid, walletId)
                }
            }
            DWLogger.logError("💸 TXSEND :: CoinJoin sweep outcome dropped: its wallet is no longer selected; \(txids.count) chunk(s) went out")
            throw coinJoinSweepInterruptedError()
        }
        guard !txids.isEmpty else {
            if let failure = outcome.firstFailure {
                throw failure
            }
            // A reported-success sweep that produced no transaction is treated
            // as a failure, so the caller surfaces an error (the sweep alert)
            // rather than silently "succeeding" with the balance unchanged.
            DWLogger.logError("💸 TXSEND :: CoinJoin sweep returned no transactions for \(amount) duffs — treating as failure")
            throw makeError(
                code: .coinJoinSweepUnavailable,
                description: "CoinJoin sweep produced no transactions"
            )
        }
        for txid in txids {
            record(txid, walletId)
        }
    }

    private func performCoinJoinSweep(
        _ target: CoinJoinSweepTarget, onNetworkWait: (@MainActor (Bool) -> Void)?
    ) async throws -> UInt64 {
        // The balance shown in the PIN prompt must be the target wallet's: a
        // call that waited behind another wallet's sweep may find the user
        // back on yet another wallet.
        let amount = await MainActor.run { () -> UInt64? in
            guard target.isRunning else { return nil }
            return SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
        }
        guard let amount else {
            // Not running: either the user left this wallet (silent, as for a
            // sweep interrupted later) or it is restarting (a plain failure
            // the user can retry).
            guard target.isSelected else { throw Self.coinJoinSweepInterruptedError() }
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "The wallet is restarting; the CoinJoin sweep did not start")
        }
        guard amount > 0 else {
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "No CoinJoin balance to move"
            )
        }

        DWLogger.log("💸 TXSEND :: preparing CoinJoin sweep — balance \(amount) duffs (\(Double(amount) / 1e8) DASH)")
        try await sendAuthorizer.authorizeSend(spendAmount: amount)

        DWLogger.log("💸 TXSEND :: CoinJoin sweep destination resolved")
        // If the user switched to another wallet or network while the sweep
        // ran — before, between or during its chunks — its outcome belongs to
        // the wallet that left: keep the chunks that went out grouped under
        // that wallet (unless it was removed meanwhile) and show no alert; the
        // screen that started the sweep belongs to that wallet too. A restart
        // of the same wallet falls through and reports as usual.
        let outcome: SwiftDashSDKTransactionSender.CoinJoinSweepOutcome
        await MainActor.run { onNetworkWait?(true) }
        do {
            outcome = try await SwiftDashSDKTransactionSender.waitingForNetwork(holdingRouting: true) {
                try SwiftDashSDKTransactionSender.sweepCoinJoin(
                    to: target.address, under: target.scope, on: target.network)
            }
        } catch {
            await MainActor.run { onNetworkWait?(false) }
            guard target.isSelected else { throw Self.coinJoinSweepInterruptedError() }
            throw error
        }
        await MainActor.run { onNetworkWait?(false) }
        let txids = outcome.txids
        try Self.recordCoinJoinSweepChunks(
            outcome, ofWallet: target.walletId, amount: amount,
            isWalletSelected: target.isSelected,
            isWalletStored: { (try? SwiftDashSDKHost.persistedWalletIds())?.contains(target.walletId) == true },
            record: { CoinJoinWithdrawalStore.shared.record(txid: $0, walletId: $1) })
        let recordedHexes: [String] = txids.map { (txid: Data) in
            txid.reversed().map { String(format: "%02x", $0) }.joined()
        }
        DWLogger.log("💸 TXSEND :: recorded \(txids.count) sweep txid(s) in CoinJoinWithdrawalStore: \(recordedHexes.joined(separator: ","))")

        await MainActor.run {
            SwiftDashSDKWalletState.shared.refreshCoinJoinBalance()
            let post = SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
        DWLogger.log("💸 TXSEND :: post-sweep CoinJoin balance \(post) duffs (was \(amount))")
            // The per-network recovery flag is owned solely by the recovery scan-
            // completion path (SwiftDashSDKSPVCoordinator.maybeCompleteCoinJoinRecovery,
            // which marks recovered once the one-time wide scan reaches .synced). A
            // sweep may be partial across chunks and does NOT imply the wide scan
            // completed, so it must not mark recovered here — doing so would suppress
            // a legitimate re-widen after an interrupted scan.
        }

        // Everything above ran for the accepted chunks — the txids are in the
        // withdrawal store and the balance is re-tallied — so it is safe to fail
        // here. Reported as a failure because the coins the failed chunks hold
        // are still in the CoinJoin account: a re-run sweeps the remainder, and
        // a success screen would tell the user there is nothing left to move.
        if outcome.isPartial {
            DWLogger.logError(
                "💸 TXSEND :: CoinJoin sweep partial — \(txids.count) chunk(s) broadcast, \(outcome.failedChunkCount) failed, \(outcome.unattemptedChunkCount) not attempted: \(String(describing: outcome.firstFailure))")
            throw Self.makeError(
                code: .coinJoinSweepPartial,
                description: "CoinJoin sweep moved \(txids.count) of \(txids.count + outcome.failedChunkCount + outcome.unattemptedChunkCount) transactions"
            )
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
        DWLogger.log("💸 TXSEND :: pay-to-contact starting — \(amount) duffs")
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
        DWLogger.log("💸 TXSEND :: pay-to-contact broadcast, txid \(txid.map { String(format: "%02x", $0) }.joined()), fee \(feeDuffs) duffs")
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

    /// A `broadcastUnknown` error whose send is in the history on screen as
    /// "Waiting for the network". Without it (no active wallet, or the send's
    /// wallet is no longer the active one) the outcome is told with the
    /// error's own copy, and nothing points at the history.
    @objc(isFollowedUnknownOutcomeError:)
    static func isFollowedUnknownOutcomeError(_ error: NSError) -> Bool {
        isBroadcastUnknownError(error) && (error.userInfo[followedKey] as? Bool) == true
    }

    @objc(isFundsAwaitingNetworkError:)
    static func isFundsAwaitingNetworkError(_ error: NSError) -> Bool {
        error.domain == errorDomain && error.code == ErrorCode.fundsAwaitingNetwork.rawValue
    }

    /// Title for a send that cannot be built yet because the coins it needs
    /// wait for the network to confirm them (see `sendBuildError(from:)`).
    @objc static var fundsAwaitingNetworkTitle: String {
        NSLocalizedString("Payment can't be made yet", comment: "Send blocked until unconfirmed coins are confirmed")
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

    /// User-facing message for a CoinJoin sweep failure, or nil if the user
    /// simply cancelled authentication or the sweep's wallet stopped being the
    /// active one (callers stay silent). Centralizes the
    /// cancel predicate + copy so every sweep entry point behaves identically.
    ///
    /// A partial sweep gets its own copy: "try again" is still the right
    /// action, but telling the user nothing moved would contradict the
    /// transactions already in their history.
    static func coinJoinSweepUserMessage(for error: Error) -> String? {
        let nsError = error as NSError
        guard !isAuthenticationCancelledError(nsError) else { return nil }
        if nsError.domain == errorDomain, nsError.code == ErrorCode.coinJoinSweepInterrupted.rawValue {
            return nil
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
        let (tx, txHash, origin): (FinalizedCoreTransaction, Data, WalletChainScope)
        do {
            (tx, txHash, origin) = try SwiftDashSDKTransactionSender.buildAndSign(address: address, amount: amount)
        } catch {
            throw Self.sendBuildError(from: error)
        }

        return PreparedStandardSend(
            txData: try tx.serializedData(),
            txHash: txHash,
            fee: tx.fee,
            address: address,
            amount: amount,
            origin: origin,
            coreTransaction: tx
        )
    }

    private func buildPreparedSwapDeposit(vaultAddress: String, amount: UInt64, memo: String) throws -> PreparedStandardSend {
        let (tx, txHash, origin): (FinalizedCoreTransaction, Data, WalletChainScope)
        do {
            (tx, txHash, origin) = try SwiftDashSDKTransactionSender.buildAndSignSwapDeposit(
                vaultAddress: vaultAddress,
                amountDuffs: amount,
                memo: memo
            )
        } catch {
            throw Self.sendBuildError(from: error)
        }

        return PreparedStandardSend(
            txData: try tx.serializedData(),
            txHash: txHash,
            fee: tx.fee,
            address: vaultAddress,
            amount: amount,
            origin: origin,
            coreTransaction: tx
        )
    }
}

/// Timeout-guarded wrapper over `DSAuthenticationManager.authenticate(...)`. The bare
/// completion-based API never resumes if the PIN view controller fails to present silently
/// (no key window / app backgrounded / a sheet already presenting — DashSync's internal
/// `NSParameterAssert` is compiled out in Release), which would hang an awaiting `async` call
/// forever. This guarantees the continuation resumes exactly once: either from the callback or
/// from a watchdog. The 120s timeout is generous enough never to interrupt real PIN/biometric
/// entry — it only breaks an otherwise-infinite hang.
enum AuthenticationGate {
    enum Outcome { case ok, cancelled, failed, timedOut }

    /// `sessionAuthSufficient` restores the legacy `seedWithPrompt` semantic
    /// (`DSWallet.seedPhraseIfAuthenticated`, DSWallet.m:797) for programmatic
    /// protocol sends: an already-authenticated session (`didAuthenticate`,
    /// set by the lock-screen PIN/biometric unlock) passes without presenting
    /// any UI. Interactive gates keep the default `false` and prompt per send.
    static func authenticate(biometric: Bool,
                             sessionAuthSufficient: Bool = false,
                             spendAmount: UInt64? = nil,
                             timeout: TimeInterval = 120) async -> Outcome {
        if sessionAuthSufficient, AuthenticationService.shared.didAuthenticate {
            DWLogger.log("💸 TXSEND :: session-authenticated — skipping auth prompt")
            return .ok
        }
        return await withCheckedContinuation { continuation in
            var didResume = false
            func safeResume(_ outcome: Outcome) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: outcome)
            }

            // Watchdog: resume after the timeout if the modal never resolves
            // (no presentation anchor is handled inside the presenter, but a
            // wedged UI still can't be ruled out). Idempotent; serial on main.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { safeResume(.timedOut) }

            Task { @MainActor in
                let outcome = await AuthenticationService.shared.authenticate(
                    usingBiometrics: biometric, spendAmount: spendAmount)
                switch outcome {
                case .authenticated:
                    safeResume(.ok)
                case .cancelled:
                    safeResume(.cancelled)
                case .failed:
                    safeResume(.failed)
                }
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
            DWLogger.log("💸 TXSEND :: user authorized send")
            return
        case .cancelled:
            DWLogger.log("💸 TXSEND :: user cancelled authentication")
            throw WalletSendService.makeError(
                code: .authenticationCancelled,
                description: "Authentication cancelled"
            )
        case .failed, .timedOut:
            DWLogger.logError("💸 TXSEND :: authentication failed (\(outcome == .timedOut ? "timed out" : "failed"))")
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
        case insufficientSelectedFunds = 3
        case coinJoinSweepUnavailable = 4
        case alreadyBroadcast = 5
        case dashPayPaymentUnavailable = 6
        case initialRestoreSync = 7
        case offline = 8
        case broadcastRejected = 9
        case broadcastUnknown = 10
        case invalidSwapMemo = 11
        case coinJoinSweepPartial = 12
        case coinJoinSweepInterrupted = 13
        case fundsAwaitingNetwork = 14
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
        case .coreFundsAwaitingNetwork:
            return sendBuildError(from: error)
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
    /// Every send route ends in one of these, and there is more than one route
    /// — the prepared standard send and the selected-input / sweep path, which
    /// broadcasts inside `buildAndSignFromAddress` and never reaches
    /// `PreparedStandardSend.broadcast()`. They used to build the strings
    /// independently and drifted apart, so one route kept showing unlocalized
    /// English with the SDK's internal reason appended.
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

extension WalletSendService {
    /// Follows `txidWire`, whose broadcast got no answer, in the history as
    /// "Waiting for the network" (`PendingSendOutcomes`). Safe from any
    /// thread. For a route that has no error to hand back.
    ///
    /// - Parameters:
    ///   - otherAddresses: the other addresses of a BIP70 payment (its
    ///     further recipients, its URI's address): one followed send,
    ///     refusing a payment to any.
    ///   - origin: the wallet and chain that signed the send, together, so
    ///     a route cannot name one without the other; nil (tests only) falls
    ///     back to what is bound now.
    /// - Returns: whether its row is in the history on screen now — followed
    ///   under the bound wallet on the bound chain. A send followed under
    ///   another wallet or chain (one switched away from, or wiped, during
    ///   the network wait) returns false: nothing on screen would show it
    ///   waiting.
    @discardableResult
    static func followUnknownOutcome(
        txidWire: Data, address: String?, otherAddresses: [String] = [], amount: UInt64, notifies: Bool = true,
        origin: WalletChainScope?
    ) -> Bool {
        MainThread.sync {
            let recorded = PendingSendOutcomes.shared.recordUnknownOutcome(
                txidWire: txidWire, address: address, otherAddresses: otherAddresses, amount: amount,
                notifies: notifies, origin: origin)
            let bound = WalletChainScope.bound
            return recorded && bound != nil && (origin == nil || origin == bound)
        }
    }

    /// A broadcast of `txidWire` that ended with no answer from the network.
    ///
    /// Where a send with an unknown outcome is recorded: every route that
    /// knows its txid — the prepared standard send (plain sends, swap
    /// deposits, `SendCoinsService`), the selected-input send and the
    /// interactive BIP70 payment — maps the outcome here, and the send is
    /// followed in the history as "Waiting for the network"
    /// (`PendingSendOutcomes`). The error carries the txid
    /// (`unknownTxidWireKey`) for callers that book the send against it. A
    /// CoinJoin sweep chunk records itself (`SwiftDashSDKTransactionSender
    /// .sweepCoinJoin`); a contact payment's unknown outcome carries no txid
    /// from the SDK, so it is not followed.
    static func unknownOutcomeError(
        txidWire: Data, address: String?, otherAddresses: [String] = [], amount: UInt64, reason: String,
        notifies: Bool = true, origin: WalletChainScope?
    ) -> NSError {
        let followed = followUnknownOutcome(
            txidWire: txidWire, address: address, otherAddresses: otherAddresses, amount: amount,
            notifies: notifies, origin: origin)
        let error = makeError(code: .broadcastUnknown, description: BroadcastOutcomeCopy.unknown, diagnostic: reason)
        var userInfo = error.userInfo
        userInfo[unknownTxidWireKey] = txidWire
        if followed {
            userInfo[followedKey] = true
        }
        return NSError(domain: error.domain, code: error.code, userInfo: userInfo)
    }

    /// A build the SDK refused because the coins that would fund it are not
    /// confirmed yet — change of an earlier send the network has not taken, or
    /// a fresh incoming payment — becomes this service's
    /// `fundsAwaitingNetwork` with copy a user can act on. The SDK's own text
    /// (amounts in duffs, internal wording) goes to the diagnostic only. Every
    /// other error is returned untouched.
    static func sendBuildError(from error: Error) -> Error {
        guard case .coreFundsAwaitingNetwork(let detail) = error as? PlatformWalletError else {
            return error
        }
        DWLogger.log("💸 TXSEND :: build refused, funds await network confirmation: \(detail)")
        return makeError(
            code: .fundsAwaitingNetwork,
            description: NSLocalizedString(
                "Some of your funds are waiting for the network to confirm an earlier payment. Try again in a moment.",
                comment: "Send blocked until unconfirmed coins are confirmed"),
            diagnostic: detail)
    }
}
