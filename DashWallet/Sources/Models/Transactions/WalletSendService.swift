//
//  WalletSendService.swift
//  DashWallet
//
//  Shared send boundary for standard SwiftDashSDK sends and the remaining
//  DashSync-only selected-input fallback.
//

import Foundation
import OSLog

@objc(DWPreparedStandardSend)
final class PreparedStandardSend: NSObject {
    @objc let txData: Data
    @objc let txHash: Data
    @objc let fee: UInt64
    @objc let transaction: DSTransaction
    @objc let address: String
    @objc let amount: UInt64

    init(
        txData: Data,
        txHash: Data,
        fee: UInt64,
        transaction: DSTransaction,
        address: String,
        amount: UInt64
    ) {
        self.txData = txData
        self.txHash = txHash
        self.fee = fee
        self.transaction = transaction
        self.address = address
        self.amount = amount
    }

    @objc(broadcastAndReturnError:)
    func broadcast() throws {
        try SwiftDashSDKTransactionSender.broadcast(txData)
    }
}

@objc(DWWalletSendService)
final class WalletSendService: NSObject {
    @objc(sharedService) static let shared = WalletSendService()

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-send-service")

    private let sendAuthorizer = SendAuthorizer()
    private let legacySelectedInputSendExecutor = LegacySelectedInputSendExecutor()

    private override init() {
        super.init()
    }

    func prepareStandardSendForConfirmation(address: String, amount: UInt64) async throws -> PreparedStandardSend {
        Self.logger.info("💸 TXSEND :: preparing standard send")
        try await sendAuthorizer.authorizeSend()
        let prepared = try buildPreparedStandardSend(address: address, amount: amount)
        Self.logger.info("💸 TXSEND :: standard send prepared")
        return prepared
    }

    func send(
        address: String,
        amount: UInt64,
        inputSelector: SingleInputAddressSelector? = nil,
        adjustAmountDownwards: Bool = false
    ) async throws -> DSTransaction {
        if let inputSelector {
            Self.logger.info("💸 TXSEND :: routing to selected-input (DashSync) path")
            try await sendAuthorizer.authorizeSend()
            return try await legacySelectedInputSendExecutor.send(
                address: address,
                amount: amount,
                inputSelector: inputSelector,
                adjustAmountDownwards: adjustAmountDownwards
            )
        }

        let preparedSend = try await prepareStandardSendForConfirmation(address: address, amount: amount)
        try preparedSend.broadcast()
        return preparedSend.transaction
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

        Self.logger.info("💸 TXSEND :: CJTEST preparing CoinJoin sweep — balance \(amount, privacy: .public) duffs (\(Double(amount) / 1e8, privacy: .public) DASH)")
        try await sendAuthorizer.authorizeSend()

        guard let destination = SwiftDashSDKReceiveAddressReader.receiveAddress(
            on: DWEnvironment.sharedInstance().currentChain
        ) else {
            throw Self.makeError(
                code: .coinJoinSweepUnavailable,
                description: "Could not resolve a destination address for the CoinJoin sweep"
            )
        }

        Self.logger.info("💸 TXSEND :: CJTEST CoinJoin sweep destination resolved \(destination, privacy: .public)")
        let txids = try SwiftDashSDKTransactionSender.sweepCoinJoin(to: destination)
        guard !txids.isEmpty else {
            // A reported-success sweep that produced no transaction is treated
            // as a failure, so the caller surfaces an error (the sweep alert)
            // rather than silently "succeeding" with the balance unchanged.
            Self.logger.error("💸 TXSEND :: CJTEST CoinJoin sweep returned no transactions for \(amount, privacy: .public) duffs — treating as failure")
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
        Self.logger.info("💸 TXSEND :: CJTEST recorded \(txids.count, privacy: .public) sweep txid(s) in CoinJoinWithdrawalStore: \(recordedHexes.joined(separator: ","), privacy: .public)")

        await MainActor.run {
            SwiftDashSDKWalletState.shared.refreshCoinJoinBalance()
            let post = SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
            Self.logger.info("💸 TXSEND :: CJTEST post-sweep CoinJoin balance \(post, privacy: .public) duffs (was \(amount, privacy: .public))")
            // The per-network recovery flag is owned solely by the recovery scan-
            // completion path (SwiftDashSDKSPVCoordinator.maybeCompleteCoinJoinRecovery,
            // which marks recovered once the one-time wide scan reaches .synced). A
            // sweep may be partial across chunks and does NOT imply the wide scan
            // completed, so it must not mark recovered here — doing so would suppress
            // a legitimate re-widen after an interrupted scan.
        }
        return amount
    }

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

    /// User-facing message for a CoinJoin sweep failure, or nil if the user
    /// simply cancelled authentication (callers stay silent). Centralizes the
    /// cancel predicate + copy so every sweep entry point behaves identically.
    static func coinJoinSweepUserMessage(for error: Error) -> String? {
        guard !isAuthenticationCancelledError(error as NSError) else { return nil }
        return NSLocalizedString(
            "Couldn't move your CoinJoin funds. Please try again.", comment: "CoinJoin")
    }

    private func buildPreparedStandardSend(address: String, amount: UInt64) throws -> PreparedStandardSend {
        let (txData, fee, txHash) = try SwiftDashSDKTransactionSender.buildAndSign(address: address, amount: amount)
        let chain = DWEnvironment.sharedInstance().currentChain
        let transaction = DSTransaction(message: txData, on: chain)

        return PreparedStandardSend(
            txData: txData,
            txHash: txHash,
            fee: fee,
            transaction: transaction,
            address: address,
            amount: amount
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

    static func authenticate(biometric: Bool, timeout: TimeInterval = 120) async -> Outcome {
        await withCheckedContinuation { continuation in
            var didResume = false
            func safeResume(_ outcome: Outcome) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: outcome)
            }

            // Watchdog: resume after the timeout if the callback never arrives (silent
            // non-presentation). It harmlessly no-ops once auth has resumed (safeResume is
            // idempotent). The watchdog and the auth callback both run on the main queue, so
            // `didResume` is accessed serially — no lock needed.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { safeResume(.timedOut) }

            DispatchQueue.main.async {
                DSAuthenticationManager.sharedInstance().authenticate(
                    withPrompt: nil,
                    usingBiometricAuthentication: biometric,
                    alertIfLockout: true
                ) { authenticatedOrSuccess, _, cancelled in
                    safeResume(cancelled ? .cancelled : (authenticatedOrSuccess ? .ok : .failed))
                }
            }
        }
    }
}

private final class SendAuthorizer {
    @MainActor
    func authorizeSend() async throws {
        let outcome = await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled)

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

private final class LegacySelectedInputSendExecutor {
    func send(
        address: String,
        amount: UInt64,
        inputSelector: SingleInputAddressSelector,
        adjustAmountDownwards: Bool
    ) async throws -> DSTransaction {
        let chain = DWEnvironment.sharedInstance().currentChain
        let account = DWEnvironment.sharedInstance().currentAccount
        let transactionManager = DWEnvironment.sharedInstance().currentChainManager.transactionManager
        let transaction = DSTransaction(on: chain)

        let balance = inputSelector.selectFor(tx: transaction)
        transaction.addOutputAddress(address, amount: amount)
        let feeAmount = chain.fee(forTxSize: UInt(transaction.size) + UInt(TX_OUTPUT_SIZE))

        if amount + feeAmount > balance {
            if adjustAmountDownwards && amount > feeAmount {
                return try await send(
                    address: address,
                    amount: amount - feeAmount,
                    inputSelector: inputSelector,
                    adjustAmountDownwards: false
                )
            }

            throw WalletSendService.makeError(
                code: .insufficientSelectedFunds,
                description: "Not enough funds. Selected: \(balance), Amount: \(amount), Fee: \(feeAmount)"
            )
        }

        let change = balance - (amount + feeAmount)
        if change > 0 {
            transaction.addOutputAddress(inputSelector.address, amount: change)
            transaction.sortOutputsAccordingToBIP69()
        }

        account.sign(transaction)
        account.register(transaction, saveImmediately: false)
        WalletSendService.logger.info("💸 TXSEND :: publishing selected-input tx via DashSync")
        try await transactionManager.publishTransaction(transaction)
        return transaction
    }
}

private extension WalletSendService {
    enum ErrorCode: Int {
        case authenticationCancelled = 1
        case authenticationFailed = 2
        case insufficientSelectedFunds = 3
        case coinJoinSweepUnavailable = 4
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
