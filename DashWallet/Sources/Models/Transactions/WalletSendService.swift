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
    private let broadcastAction: () throws -> CoreTransactionBroadcastOutcome
    private let ensureOnlineAction: () throws -> Void

    /// A rejected or local failure returns to `ready`. An ambiguous network
    /// outcome is terminal for this prepared transaction: broadcasting it again
    /// could double-send if the first request actually reached Core.
    private let claimLock = NSLock()
    private var broadcastState = BroadcastState.ready

    init(
        txData: Data,
        txHash: Data,
        fee: UInt64,
        address: String,
        amount: UInt64,
        coreTransaction: CoreTransaction
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
    /// above remains the only path that holds a real `CoreTransaction`.
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
            let error = WalletSendService.makeError(
                code: .broadcastRejected,
                description: "The transaction wasn't sent. You can try again. \(reason)"
            )
            claimLock.lock()
            broadcastState = .ready
            claimLock.unlock()
            throw error

        case .unknown(_, let reason):
            let error = WalletSendService.makeError(
                code: .broadcastUnknown,
                description: "We couldn't confirm whether the transaction was accepted. Don't send it again; wait for wallet synchronization. \(reason)"
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

@objc(DWWalletSendService)
final class WalletSendService: NSObject {
    @objc(sharedService) static let shared = WalletSendService()

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-send-service")

    /// See `RecentSendsRegistry` — the send-success screen's fallback source.
    let recentSends = RecentSendsRegistry()

    private let sendAuthorizer = SendAuthorizer()

    private override init() {
        super.init()
    }

    /// Core sends are blocked until the L1 chain sync completes: before
    /// `.syncDone` the persisted UTXO set can be stale (already-spent inputs,
    /// missing recent funds), so a built tx could be rejected — or worse,
    /// double-spend a UTXO consumed while offline. Gate on
    /// `SyncingActivityMonitor` per the repo guardrail (never raw SPV state).
    /// UI entry points disable Continue with the same message; this is the
    /// boundary backstop for programmatic callers.
    private static func ensureChainSynced() throws {
        guard SyncingActivityMonitor.shared.state == .syncDone else {
            throw Self.makeError(
                code: .chainNotSynced,
                description: NSLocalizedString(
                    "Your wallet is still syncing with the Dash network. Sending will be available once syncing completes.",
                    comment: "Core send blocked until chain sync completes"))
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
        try Self.ensureChainSynced()
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
        inputSelector: SingleInputAddressSelector? = nil,
        adjustAmountDownwards: Bool = false,
        sessionAuthSufficient: Bool = false
    ) async throws -> Data {
        try Self.ensureChainSynced()
        // Also covers the selected-input path below, whose `buildAndSignFromAddress`
        // broadcasts internally and never reaches `PreparedStandardSend.broadcast()`.
        try Self.ensureOnline()
        if let inputSelector {
            Self.logger.info("💸 TXSEND :: routing to selected-input (SwiftDashSDK) path")
            try await sendAuthorizer.authorizeSend(spendAmount: amount, sessionAuthSufficient: sessionAuthSufficient)
            do {
                let (_, fee, txHash) = try await SwiftDashSDKTransactionSender.buildAndSignFromAddress(
                    fromAddress: inputSelector.address,
                    to: address,
                    amount: amount,
                    adjustAmountDownwards: adjustAmountDownwards
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
                    description: "The transaction wasn't sent. You can try again. \(reason)"
                )
            } catch SwiftDashSDKTransactionSender.SendError.transactionStatusUnknown(_, let reason) {
                throw Self.makeError(
                    code: .broadcastUnknown,
                    description: "We couldn't confirm whether the transaction was accepted. Don't send it again; wait for wallet synchronization. \(reason)"
                )
            }
        }

        let preparedSend = try await prepareStandardSendForConfirmation(
            address: address, amount: amount, sessionAuthSufficient: sessionAuthSufficient)
        try preparedSend.broadcast()
        return preparedSend.txidWire
    }

    /// Sweep the entire CoinJoin-account balance into the user's own BIP44
    /// spendable balance. The shared flow behind both post-migration sweep
    /// surfaces (the Home popup and the Settings row): authorize
    /// (PIN/biometric, reusing `sendAuthorizer`) → resolve the user's own
    /// receive address → sweep via `SwiftDashSDKTransactionSender` → force a
    /// CoinJoin-balance re-tally so both surfaces self-clear without waiting
    /// for the next SPV balance event.
    ///
    /// - Returns: the CoinJoin balance (duffs) that was swept, for the success
    ///   message; the on-chain amount delivered is this minus the network fee.
    @discardableResult
    func sweepCoinJoin() async throws -> UInt64 {
        let amount = await MainActor.run { SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs }
        guard amount > 0 else {
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "No CoinJoin balance to move"
            )
        }

        Self.logger.info("💸 TXSEND :: preparing CoinJoin sweep — balance \(amount, privacy: .public) duffs (\(Double(amount) / 1e8, privacy: .public) DASH)")
        try await sendAuthorizer.authorizeSend(spendAmount: amount)

        guard let destination = SwiftDashSDKReceiveAddressReader.receiveAddress() else {
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "Could not resolve a destination address for the CoinJoin sweep"
            )
        }

        Self.logger.info("💸 TXSEND :: CoinJoin sweep destination resolved \(destination, privacy: .public)")
        let txids = try SwiftDashSDKTransactionSender.sweepCoinJoin(to: destination)
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
        // record each directly.
        for txid in txids {
            CoinJoinWithdrawalStore.shared.record(txid: txid)
        }
        let recordedHexes: [String] = txids.map { (txid: Data) in
            txid.reversed().map { String(format: "%02x", $0) }.joined()
        }
        Self.logger.info("💸 TXSEND :: recorded \(txids.count, privacy: .public) sweep txid(s) in CoinJoinWithdrawalStore: \(recordedHexes.joined(separator: ","), privacy: .public)")

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
        try Self.ensureChainSynced()
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

        let (txid, feeDuffs) = try await context.wallet.sendDashPayPayment(
            fromIdentityId: context.ourId,
            toContactIdentityId: contactIdentityId,
            amountDuffs: amount,
            memo: memo)
        Self.logger.info("💸 TXSEND :: pay-to-contact broadcast, txid \(txid.map { String(format: "%02x", $0) }.joined(), privacy: .public), fee \(feeDuffs, privacy: .public) duffs")
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

    /// User-facing message for a CoinJoin sweep failure, or nil if the user
    /// simply cancelled authentication (callers stay silent). Centralizes the
    /// cancel predicate + copy so every sweep entry point behaves identically.
    static func coinJoinSweepUserMessage(for error: Error) -> String? {
        guard !isAuthenticationCancelledError(error as NSError) else { return nil }
        return NSLocalizedString(
            "Couldn't move your CoinJoin funds. Please try again.", comment: "CoinJoin")
    }

    private func buildPreparedStandardSend(address: String, amount: UInt64) throws -> PreparedStandardSend {
        let (tx, txHash) = try SwiftDashSDKTransactionSender.buildAndSign(address: address, amount: amount)

        return PreparedStandardSend(
            txData: tx.data,
            txHash: txHash,
            fee: tx.fee,
            address: address,
            amount: amount,
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
        case insufficientSelectedFunds = 3
        case coinJoinSweepUnavailable = 4
        case alreadyBroadcast = 5
        case dashPayPaymentUnavailable = 6
        case chainNotSynced = 7
        case offline = 8
        case broadcastRejected = 9
        case broadcastUnknown = 10
    }

    static let errorDomain = "org.dashfoundation.dash.wallet-send-service"

    static func makeError(code: ErrorCode, description: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
