//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation

private extension Error {
    var isUserAuthenticationCancellation: Bool {
        // `DashSpendError` is not Equatable, so match the case with `if case` instead of `==`.
        // `.some(...)` matches through the optional from `as?` (same form as `.previousSwapPending` below).
        if case .some(.authenticationCancelled) = self as? DashSpendError { return true }
        return false
    }
}

// MARK: - MayaSuccessTrigger

/// Controls when the success screen is shown to the user.
///
/// **ONE-LINER Product switch** — change `OrderPreviewViewModel.successTrigger`.
enum MayaSuccessTrigger {
    /// Optimistic (default). Show success as soon as the Dash tx is InstantSend-locked
    /// (~5-10 s after broadcast). Mirrors Android's intent. Polling continues in background
    /// to track the real backend outcome (`backendOutcome`).
    case onISLock

    /// Show success once Maya has observed the inbound Dash tx on-chain (regardless of
    /// whether the outbound transfer to the destination chain has completed).
    case onObserved

    /// Conservative. Show success only when `observedTx.status == "done"` — i.e. funds
    /// have arrived at the destination chain. Previous behaviour.
    case onDone

    /// Show success once the submitted Dash transaction receives its first block
    /// confirmation on the Dash network (>= 1 confirmation), i.e. the Blockchair-style
    /// "In block …, Confirmations: 1" state. Detected locally via DashSync — no external
    /// explorer. Maya API polling keeps running only to record `backendOutcome`; it never
    /// drives the user-facing success.
    case onDashConfirmation
}

// MARK: - MayaBackendOutcome

/// The true backend state of the swap as reported by Maya's API.
/// Never causes the user-facing `swapStatus` to regress — it is updated AFTER
/// success has already been shown, so the UI is never yanked away.
/// A post-success refund is recorded here for future surfacing in tx history.
enum MayaBackendOutcome: Equatable {
    case pending                          // Maya has not reached a terminal state yet
    case done(outHashes: [String])        // funds arrived at destination chain
    case refunded                         // Maya returned DASH to sender ("refunded"/"aborted")
}

// MARK: - MayaSwapStatus

enum MayaSwapStatus: Equatable {
    case idle
    case pendingConfirmation    // Dash tx broadcast, waiting for block
    case processingSwap         // Maya has observed the Dash tx, swap running
    case completed(outHashes: [String])
    case failed(reason: String)
}

@MainActor
final class OrderPreviewViewModel: ObservableObject {
    private enum Constants {
        static let submitCountdownSeconds = 10
        static let minimumTolerance = Decimal(string: "0.00000001")!
        static let targetToleranceFraction = Decimal(string: "0.001")!
    }

    private struct QuotePoint {
        let dashSatoshis: Int64
        let quote: SwapQuoteResult
        let net: Decimal
        let fee: Decimal
    }

    // ── PRODUCT CONFIG ──────────────────────────────────────────────────────
    /// Change this ONE LINE to control when the success screen appears.
    static let successTrigger: MayaSuccessTrigger = .onISLock
    // ────────────────────────────────────────────────────────────────────────

    let coin: MayaCryptoCurrency
    let address: String
    let fromDashAmount: String
    let fromFiatAmount: String

    @Published var toAmount: String = "—"
    @Published var purchaseAmount: String = "—"
    @Published var purchaseFiatAmount: String?
    @Published var mayaFee: String = "—"
    @Published var mayaFeeFiatAmount: String?
    @Published var totalAmount: String = "—"
    @Published var executionNetwork: String = "—"
    @Published var remainingSubmitSeconds: Int = Constants.submitCountdownSeconds
    @Published var isSubmitting: Bool = false
    @Published var isRefreshing: Bool = false
    // True while a fresh quote is being fetched for the failure-screen "Retry" action.
    @Published var isRetrying: Bool = false
    // Records that the Dash transaction was submitted to the blockchain network.
    // This does NOT confirm Maya swap completion — that requires separate on-chain confirmation.
    @Published var submittedTxId: String?
    @Published var swapStatus: MayaSwapStatus = .idle
    @Published var pendingSwapAlertMessage: String?
    /// The true backend outcome from Maya's API, tracked independently of `swapStatus`.
    /// Updated by background polling after early success is shown.
    /// Never causes the success screen to be removed — only recorded for tx history.
    @Published var backendOutcome: MayaBackendOutcome = .pending

    /// Deep-link to the provider's hosted transaction tracker (nil for Maya).
    var trackerURL: URL? {
        guard let txid = submittedTxId, !txid.isEmpty else { return nil }
        return swapProvider.trackerURL(for: txid, depositAddress: lastDepositAddress)
    }

    /// NEAR Intents routes can remain genuinely in-flight for much longer than Maya routes.
    /// Drive the pending-screen note from the execution network already chosen by the quote.
    var isSlowRoute: Bool {
        executionNetwork.localizedCaseInsensitiveContains("near")
    }

    var resolvedExecutionNetwork: String {
        let trimmed = executionNetwork.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "—" ? swapProvider.displayName : trimmed
    }

    /// Fee-row label varies by provider: Maya keeps the network-specific label while
    /// SwapKit uses a generic "Fee" label.
    var feeLabel: String {
        swapProvider.usesGenericFeeLabel
            ? NSLocalizedString("Fee", comment: "Swap order preview")
            : (
                executionNetwork == "—"
                    ? NSLocalizedString("Swap fee", comment: "Maya/SwapKit order preview")
                    : String(format: NSLocalizedString("%@ fee", comment: "Maya/SwapKit order preview"), executionNetwork)
            )
    }

    var usesGenericFeeLabel: Bool {
        swapProvider.usesGenericFeeLabel
    }

    var confirmButtonText: String {
        if remainingSubmitSeconds > 0 {
            return String(
                format: NSLocalizedString("Confirm (%lds)", comment: "Maya"),
                CLong(remainingSubmitSeconds)
            )
        } else {
            return NSLocalizedString("Refresh quote", comment: "Maya")
        }
    }

    private var dashSatoshis: Int64
    // Fiat value of 1 destination coin, in `fiatCurrencyCode`. Used to derive the Purchase/fee
    // fiat lines. <= 0 means the rate is unavailable → those lines are hidden.
    private let cryptoFiatRate: Decimal
    private let fiatCurrencyCode: String
    private let targetReceiveAmount: Decimal?
    private var quote: SwapQuoteResult
    private var countdownCancellable: AnyCancellable?
    private let sendCoinsService = SendCoinsService()
    private let swapProvider: SwapProvider
    private var pollingTask: Task<Void, Never>?
    private var isLockCancellable: AnyCancellable?
    // Strong reference to the broadcast Dash tx. DashSync mutates its `blockHeight` in place
    // when the tx is included in a block, which the confirmation observer re-reads on each
    // transaction-status notification.
    private var submittedTransaction: DSTransaction?
    private var confirmationCancellable: AnyCancellable?
    private var didInitialLoad = false
    private var lastDepositAddress: String?

    init(
        coin: MayaCryptoCurrency,
        address: String,
        dashSatoshis: Int64,
        fromDashAmount: String,
        fromFiatAmount: String,
        cryptoFiatRate: Decimal,
        fiatCurrencyCode: String,
        targetReceiveAmount: Decimal? = nil,
        initialQuote: SwapQuoteResult,
        swapProvider: SwapProvider = MayaSwapProvider()
    ) {
        self.coin = coin
        self.address = address
        self.dashSatoshis = dashSatoshis
        self.fromDashAmount = fromDashAmount
        self.fromFiatAmount = fromFiatAmount
        self.cryptoFiatRate = cryptoFiatRate
        self.fiatCurrencyCode = fiatCurrencyCode
        self.targetReceiveAmount = targetReceiveAmount
        self.swapProvider = swapProvider
        self.quote = initialQuote
        applyQuote(initialQuote)
    }

    deinit {
        countdownCancellable?.cancel()
        pollingTask?.cancel()
        isLockCancellable?.cancel()
        confirmationCancellable?.cancel()
    }

    func handlePrimaryAction() async {
        if remainingSubmitSeconds > 0 {
            await submitSwap()
        } else {
            await refreshQuoteForDisplay()
        }
    }

    func onAppearLoad() async {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        await refreshQuoteForDisplay()
    }

    func resetToIdle() {
        pollingTask?.cancel()
        pollingTask = nil
        isLockCancellable?.cancel()
        isLockCancellable = nil
        confirmationCancellable?.cancel()
        confirmationCancellable = nil
        submittedTransaction = nil
        swapStatus = .idle
        submittedTxId = nil
        lastDepositAddress = nil
        pendingSwapAlertMessage = nil
        backendOutcome = .pending
    }

    /// "Retry" from the failure screen: fetches a fresh Maya quote for the SAME coin,
    /// destination address, and Dash amount.
    /// - Returns: a new `OrderPreviewViewModel` ready for a fresh Order Preview when the quote
    ///   refresh succeeds; `nil` when it fails (in which case `swapStatus` is updated with the
    ///   new failure reason so the caller can stay on the failed screen).
    func retryQuote() async -> OrderPreviewViewModel? {
        guard !isRetrying else { return nil }
        isRetrying = true
        defer { isRetrying = false }

        do {
            let freshQuote = try await fetchFreshQuote()
            if let apiError = freshQuote.error {
                setFailure(apiError)
                return nil
            }
            return OrderPreviewViewModel(
                coin: coin,
                address: address,
                dashSatoshis: dashSatoshis,
                fromDashAmount: fromDashAmount,
                fromFiatAmount: fromFiatAmount,
                cryptoFiatRate: cryptoFiatRate,
                fiatCurrencyCode: fiatCurrencyCode,
                targetReceiveAmount: targetReceiveAmount,
                initialQuote: freshQuote,
                swapProvider: swapProvider
            )
        } catch {
            setFailure(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Private: Countdown

    private func startCountdown() {
        countdownCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.remainingSubmitSeconds > 0 else { return }
                self.remainingSubmitSeconds -= 1
            }
    }

    private func stopCountdown() {
        countdownCancellable?.cancel()
        countdownCancellable = nil
    }

    private func resetCountdown() {
        remainingSubmitSeconds = Constants.submitCountdownSeconds
    }

    // MARK: - Private: Quote Operations

    private func refreshQuoteForDisplay() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let refreshedPoint: QuotePoint
            if let targetReceiveAmount, targetReceiveAmount > 0 {
                refreshedPoint = try await convergeQuoteToTarget(targetReceiveAmount)
            } else {
                let newQuote = try await fetchFreshQuote(dashSatoshis: dashSatoshis)
                if let apiError = newQuote.error {
                    setFailure(apiError)
                    return
                }
                guard let point = makeQuotePoint(dashSatoshis: dashSatoshis, quote: newQuote) else {
                    setFailure(NSLocalizedString("Unable to refresh quote. Please try again.", comment: "Swap"))
                    return
                }
                refreshedPoint = point
            }
            dashSatoshis = refreshedPoint.dashSatoshis
            quote = refreshedPoint.quote
            applyQuote(refreshedPoint.quote)
            stopCountdown()
            resetCountdown()
            startCountdown()
        } catch {
            setFailure(error.localizedDescription)
        }
    }

    private func fetchFreshQuote() async throws -> SwapQuoteResult {
        try await fetchFreshQuote(dashSatoshis: dashSatoshis)
    }

    private func fetchFreshQuote(dashSatoshis: Int64) async throws -> SwapQuoteResult {
        try await swapProvider.fetchQuote(
            dashSatoshis: dashSatoshis,
            toAsset: coin.mayaAsset,
            destination: address
        )
    }

    private func submitSwap() async {
        guard !isSubmitting else { return }
        submittedTxId = nil
        lastDepositAddress = nil
        pendingSwapAlertMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            // Refresh quote immediately before commit so vault address and memo are fresh.
            // Mirrors Android's getSwapInfo call in MayaBlockchainApi.commitSwapTransaction.
            let freshQuote = try await fetchFreshQuote()
            if let apiError = freshQuote.error {
                setFailure(apiError)
                return
            }
            quote = freshQuote
            applyQuote(freshQuote)

            let execution = try resolveExecutionData(from: freshQuote)
            let tx = try await submitDashTransaction(using: execution)
            setSubmittedTransaction(tx, depositAddress: execution.vaultAddress)
        } catch {
            if case .some(.previousSwapPending) = error as? DashSpendError {
                pendingSwapAlertMessage = error.localizedDescription
                return
            }
            if case .some(.swapAwaitingInstantLock) = error as? DashSpendError {
                // Previous swap not yet IS-locked — show a soft "wait a moment" alert, not a failure.
                pendingSwapAlertMessage = error.localizedDescription
                return
            }
            if error.isUserAuthenticationCancellation {
                swapStatus = .idle
                return
            }
            setFailure(error.localizedDescription)
        }
    }

    private func mayaFieldError(_ message: String) -> Error {
        NSError(domain: "Maya", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func resolveExecutionData(from quote: SwapQuoteResult) throws -> SwapExecutionData {
        guard let vaultAddress = quote.inboundAddress, !vaultAddress.isEmpty else {
            throw mayaFieldError(NSLocalizedString("Vault address is missing. Please refresh and try again.", comment: "Maya"))
        }

        let memo: String?
        if let quoteMemo = quote.memo, !quoteMemo.isEmpty {
            memo = quoteMemo
        } else if swapProvider.buildsSwapKitDeposit {
            let shortAsset = coin.mayaAsset.uppercased().components(separatedBy: "-").first
                ?? coin.mayaAsset.uppercased()
            memo = "=:\(shortAsset):\(address)"
        } else {
            throw mayaFieldError(NSLocalizedString("Swap memo is missing. Please refresh and try again.", comment: "Maya"))
        }

        let resolvedExecutionNetwork = quote.executionNetwork?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SwapExecutionData(
            vaultAddress: vaultAddress,
            memo: memo,
            executionNetwork: {
                if let resolvedExecutionNetwork, !resolvedExecutionNetwork.isEmpty {
                    return resolvedExecutionNetwork
                }
                return swapProvider.displayName
            }()
        )
    }

    private func submitDashTransaction(using execution: SwapExecutionData) async throws -> DSTransaction {
        if swapProvider.buildsSwapKitDeposit {
            return try await sendCoinsService.sendSwapKitSwap(
                depositAddress: execution.vaultAddress,
                dashAmount: UInt64(dashSatoshis),
                memo: execution.memo
            )
        } else {
            guard let memo = execution.memo, !memo.isEmpty else {
                throw mayaFieldError(NSLocalizedString("Swap memo is missing. Please refresh and try again.", comment: "Maya"))
            }
            return try await sendCoinsService.sendMayaSwap(
                vaultAddress: execution.vaultAddress,
                dashAmount: UInt64(dashSatoshis),
                memo: memo
            )
        }
    }

    // MARK: - Private: State Mutation

    private func setFailure(_ message: String) {
        // Keep Maya failures on the status sheet path so SwiftUI does not try to
        // present a native alert and a bottom sheet for the same event.
        swapStatus = .failed(reason: userFacingErrorMessage(for: message))
    }

    private func userFacingErrorMessage(for message: String) -> String {
        if message.localizedCaseInsensitiveContains("invalidDestinationAddress") {
            let chainLabel = MayaCryptoCurrency.chainDisplayName(coin.chain)
            return String(
                format: NSLocalizedString(
                    "The destination address isn’t valid for %@ (%@). Go back and enter a %@ address.",
                    comment: "Swap"
                ),
                coin.name,
                chainLabel,
                chainLabel
            )
        }

        return message
    }

    private func setSubmittedTransaction(_ tx: DSTransaction, depositAddress: String) {
        submittedTransaction = tx
        submittedTxId = tx.txHashHexString
        lastDepositAddress = depositAddress
        swapStatus = .pendingConfirmation
        startObservingISLock(txid: tx.txHashHexString)
        if Self.successTrigger == .onDashConfirmation {
            startObservingDashConfirmation(tx: tx)
        }
        startPolling(txid: tx.txHashHexString)
    }

    // MARK: - Private: IS-Lock Observation

    private func startObservingISLock(txid: String) {
        isLockCancellable = NotificationCenter.default
            .publisher(for: .DSTransactionManagerTransactionStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }

                guard
                    let userInfo = notification.userInfo,
                    let tx = userInfo[DSTransactionManagerNotificationTransactionKey] as? DSTransaction,
                    tx.txHashHexString == txid
                else { return }

                guard
                    let changes = userInfo[DSTransactionManagerNotificationTransactionChangesKey] as? [String: Any],
                    changes[DSTransactionManagerNotificationInstantSendTransactionLockKey] != nil
                else { return }

                DSLogger.log("sendMayaSwap IS-lock received for \(txid)")

                if case .pendingConfirmation = self.swapStatus {
                    switch Self.successTrigger {
                    case .onISLock:
                        // Show success immediately. Polling keeps running in the background
                        // to track the real backend outcome (backendOutcome).
                        self.swapStatus = .completed(outHashes: [])
                    case .onObserved, .onDone, .onDashConfirmation:
                        // IS-lock alone is NOT success here — it only advances the UI to
                        // "processing". Success requires a block confirmation (or, for the
                        // other triggers, their own backend condition).
                        self.swapStatus = .processingSwap
                    }
                }

                self.isLockCancellable = nil  // one-shot
            }
    }

    // MARK: - Private: Dash Confirmation Observation

    /// Observes the broadcast Dash transaction locally and shows success once it reaches
    /// its first block confirmation. Uses DashSync state/notifications only — no external
    /// explorer. The transaction-status notification fires on every block/mempool sync
    /// update (sometimes without a transaction payload), so each firing simply re-reads the
    /// tracked tx's confirmation count.
    private func startObservingDashConfirmation(tx: DSTransaction) {
        // Fast path: already confirmed (e.g. re-entry after a quick block).
        if completeIfConfirmed(tx: tx) { return }

        confirmationCancellable = NotificationCenter.default
            .publisher(for: .DSTransactionManagerTransactionStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.completeIfConfirmed(tx: tx)
            }
    }

    /// Flips `swapStatus` to `.completed` when `tx` has >= 1 confirmation.
    /// Never regresses a terminal user-facing state. Returns true once terminal so the
    /// caller can stop observing.
    @discardableResult
    private func completeIfConfirmed(tx: DSTransaction) -> Bool {
        switch swapStatus {
        case .completed, .failed:
            confirmationCancellable?.cancel()
            confirmationCancellable = nil
            return true
        default:
            break
        }

        let confirmations = Self.confirmations(for: tx)
        guard confirmations >= 1 else { return false }

        DSLogger.log("Maya: Dash tx \(tx.txHashHexString) confirmed in block "
            + "(blockHeight=\(tx.blockHeight), confirmations=\(confirmations)) — showing success")
        swapStatus = .completed(outHashes: [])
        confirmationCancellable?.cancel()
        confirmationCancellable = nil
        return true
    }

    /// Number of block confirmations for `tx` against the current chain tip.
    /// Returns 0 while the tx is still in the mempool (`blockHeight == TX_UNCONFIRMED`).
    /// Mirrors the calculation in `Transaction.swift`.
    private static func confirmations(for tx: DSTransaction) -> Int {
        let lastHeight = DWEnvironment.sharedInstance().currentChain.lastTerminalBlockHeight
        let txHeight = tx.blockHeight
        guard txHeight != UInt32(TX_UNCONFIRMED), txHeight <= lastHeight else { return 0 }
        return Int(lastHeight - txHeight) + 1
    }

    // MARK: - Private: Polling

    private func startPolling(txid: String) {
        pollingTask?.cancel()
        // [weak self] prevents a retain cycle: the Task would otherwise keep self alive
        // indefinitely even after popToRootViewController releases all external references.
        // The @MainActor context is inherited, so all property accesses remain on main.
        pollingTask = Task { [weak self] in
            guard let self else { return }
            let maxIterations = 360 // 5 s × 360 = 30 min

            for iteration in 0..<maxIterations {
                guard !Task.isCancelled else { return }

                if iteration > 0 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { return }
                }

                do {
                    let info = try await swapProvider.fetchSwapStatus(
                        txid: txid,
                        depositAddress: self.lastDepositAddress
                    )

                    // Provider hasn't seen the Dash tx yet (block not confirmed) — keep waiting.
                    guard info.error == nil, info.isObserved else { continue }

                    let outcome = Self.classifyStatus(info)
                    if self.handlePollingOutcome(outcome, txid: txid) { return }
                } catch {
                    // Transient network error — keep current status and retry next tick.
                }
            }

            // 30-minute timeout.
            // If success was already shown, silently stop. backendOutcome stays .pending
            // which signals that the terminal state was never confirmed within 30 min.
            if !self.isSuccessAlreadyShown {
                self.swapStatus = .failed(reason: NSLocalizedString(
                    "Swap timed out after 30 minutes. Contact Maya support if funds were sent.",
                    comment: "Maya"
                ))
            }
        }
    }

    /// Applies a single polled Maya outcome to the view-model state.
    /// - Returns: `true` when a terminal state was reached and polling should stop.
    private func handlePollingOutcome(_ outcome: MayaBackendOutcome, txid: String) -> Bool {
        // Success already on screen — NEVER regress swapStatus; only record backendOutcome.
        if isSuccessAlreadyShown {
            switch outcome {
            case .pending:
                return false  // still running, continue polling
            case .done, .refunded:
                backendOutcome = outcome
                if case .refunded = outcome {
                    // Post-success refund detected. Record it; do not yank the success
                    // screen. Future: surface in tx history / a badge.
                    DSLogger.log("Maya: post-success refund detected for \(txid)")
                }
                return true  // terminal state reached, stop polling
            }
        }

        // Success not yet shown — drive swapStatus.
        switch outcome {
        case .done(let hashes):
            swapStatus = .completed(outHashes: hashes)
            backendOutcome = outcome
            return true
        case .refunded:
            swapStatus = .failed(reason: String(
                format: NSLocalizedString(
                    "Your DASH was refunded by %@.",
                    comment: "Swap refund message — %@ is the provider name e.g. Maya"
                ),
                swapProvider.displayName
            ))
            backendOutcome = outcome
            return true
        case .pending:
            advanceUIForPendingObservation()
            return false
        }
    }

    /// Advances the UI on a non-terminal Maya observation, per the active success trigger.
    private func advanceUIForPendingObservation() {
        switch Self.successTrigger {
        case .onObserved:
            // observedTx is present and not terminal-bad → show success.
            // Keep polling so backendOutcome is eventually resolved.
            swapStatus = .completed(outHashes: [])
        case .onISLock, .onDone, .onDashConfirmation:
            // For these triggers success is driven elsewhere (IS-lock, Maya done, or the
            // local block-confirmation observer). While still waiting, only advance
            // pending → processing; never overwrite a success that was already shown.
            if case .pendingConfirmation = swapStatus {
                swapStatus = .processingSwap
            }
        }
    }

    private var isSuccessAlreadyShown: Bool {
        if case .completed = swapStatus { return true }
        return false
    }

    /// Maps a `SwapStatusResult` to a `MayaBackendOutcome`.
    ///
    /// Normalised status strings:
    /// - `"done"`               — funds arrived at destination chain (terminal success)
    /// - `"refunded"/"aborted"` — sent DASH was returned (terminal, treated as failure for UX)
    /// - anything else          → `.pending`
    private static func classifyStatus(_ result: SwapStatusResult) -> MayaBackendOutcome {
        switch result.observedStatus {
        case "done":
            return .done(outHashes: result.outHashes ?? [])
        case "refunded", "aborted":
            return .refunded
        default:
            return .pending
        }
    }

    private func applyQuote(_ quote: SwapQuoteResult) {
        let expectedOut = assetDecimalFromBaseUnits(quote.expectedAmountOut)
        let fee = assetDecimalFromBaseUnits(quote.fees?.total ?? quote.fees?.outbound)
        let displayOut = targetReceiveAmount.flatMap { $0 > 0 ? $0 : nil } ?? expectedOut
        let total = displayOut + fee

        toAmount = formatCryptoAmount(displayOut)
        purchaseAmount = toAmount
        mayaFee = formatFeeAmount(fee)
        totalAmount = formatCryptoAmount(total)
        let resolvedExecutionNetwork = quote.executionNetwork?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedExecutionNetwork, !resolvedExecutionNetwork.isEmpty {
            executionNetwork = resolvedExecutionNetwork
        } else {
            executionNetwork = swapProvider.displayName
        }

        // Fiat lines = coin amount × cryptoFiatRate (fiat value of 1 destination coin), in the
        // active fiat currency — matching how the source-side fromFiatAmount is produced.
        // Rate unavailable (<= 0) → hide the lines instead of showing a wrong/zero value.
        if cryptoFiatRate > 0 {
            purchaseFiatAmount = formatFiat(displayOut * cryptoFiatRate)
            mayaFeeFiatAmount = fee > 0 ? formatFiat(fee * cryptoFiatRate) : nil
        } else {
            purchaseFiatAmount = nil
            mayaFeeFiatAmount = nil
        }
    }

    private func convergeQuoteToTarget(_ target: Decimal) async throws -> QuotePoint {
        let tolerance = max(target * Constants.targetToleranceFraction, Constants.minimumTolerance)
        var points: [QuotePoint] = []

        let firstQuote = try await fetchFreshQuote(dashSatoshis: dashSatoshis)
        if let apiError = firstQuote.error {
            throw mayaFieldError(apiError)
        }
        guard let firstPoint = makeQuotePoint(dashSatoshis: dashSatoshis, quote: firstQuote) else {
            throw mayaFieldError(NSLocalizedString("Unable to refresh quote. Please try again.", comment: "Swap"))
        }
        points.append(firstPoint)

        if isAcceptable(point: firstPoint, target: target, tolerance: tolerance) {
            return firstPoint
        }

        if let secondDashSatoshis = grossedUpDashSatoshis(for: target, from: firstPoint),
           secondDashSatoshis != firstPoint.dashSatoshis,
           let secondPoint = try await fetchPoint(dashSatoshis: secondDashSatoshis) {
            points.append(secondPoint)

            if isAcceptable(point: secondPoint, target: target, tolerance: tolerance) {
                return secondPoint
            }

            if let thirdDashSatoshis = secantDashSatoshis(previous: firstPoint, current: secondPoint, target: target),
               thirdDashSatoshis != secondPoint.dashSatoshis,
               let thirdPoint = try await fetchPoint(dashSatoshis: thirdDashSatoshis) {
                points.append(thirdPoint)
            }
        }

        return bestPoint(from: points, target: target)
    }

    private func fetchPoint(dashSatoshis: Int64) async throws -> QuotePoint? {
        let freshQuote = try await fetchFreshQuote(dashSatoshis: dashSatoshis)
        guard freshQuote.error == nil else { return nil }
        return makeQuotePoint(dashSatoshis: dashSatoshis, quote: freshQuote)
    }

    private func makeQuotePoint(dashSatoshis: Int64, quote: SwapQuoteResult) -> QuotePoint? {
        let net = assetDecimalFromBaseUnits(quote.expectedAmountOut)
        guard net > 0 else { return nil }
        let fee = assetDecimalFromBaseUnits(quote.fees?.total ?? quote.fees?.outbound)
        return QuotePoint(dashSatoshis: dashSatoshis, quote: quote, net: net, fee: fee)
    }

    private func grossedUpDashSatoshis(for target: Decimal, from point: QuotePoint) -> Int64? {
        let grossOut = point.net + point.fee
        guard grossOut > 0 else { return nil }

        let required = Decimal(point.dashSatoshis) * (target + point.fee) / grossOut
        var next = cappedDashSatoshis(roundUpToSatoshis(required))

        if next == point.dashSatoshis {
            if point.net < target, point.dashSatoshis < dashBalance {
                next = min(point.dashSatoshis + 1, dashBalance)
            } else {
                return nil
            }
        }

        return next
    }

    private func secantDashSatoshis(previous: QuotePoint, current: QuotePoint, target: Decimal) -> Int64? {
        let netDelta = current.net - previous.net
        guard netDelta != 0 else { return nil }

        let dashDelta = Decimal(current.dashSatoshis - previous.dashSatoshis)
        let next = Decimal(current.dashSatoshis) + (target - current.net) * dashDelta / netDelta
        guard next > 0 else { return nil }

        var nextSatoshis = cappedDashSatoshis(roundUpToSatoshis(next))
        if nextSatoshis == current.dashSatoshis {
            if current.net < target, current.dashSatoshis < dashBalance {
                nextSatoshis = min(current.dashSatoshis + 1, dashBalance)
            } else {
                return nil
            }
        }
        return nextSatoshis
    }

    private func isAcceptable(point: QuotePoint, target: Decimal, tolerance: Decimal) -> Bool {
        point.net >= target && absoluteDifference(point.net, target) <= tolerance
    }

    private func bestPoint(from points: [QuotePoint], target: Decimal) -> QuotePoint {
        let affordablePoints = points.filter { $0.net >= target }
        if let bestAffordable = affordablePoints.min(by: { absoluteDifference($0.net, target) < absoluteDifference($1.net, target) }) {
            return bestAffordable
        }

        return points.min(by: { absoluteDifference($0.net, target) < absoluteDifference($1.net, target) })!
    }

    private func absoluteDifference(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }

    private func roundUpToSatoshis(_ value: Decimal) -> Int64 {
        guard value > 0 else { return 0 }
        var raw = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .up)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    private func cappedDashSatoshis(_ value: Int64) -> Int64 {
        min(max(1, value), dashBalance)
    }

    private var dashBalance: Int64 {
        Int64(DWEnvironment.sharedInstance().currentAccount.balance)
    }

    // MARK: - Private: Formatting

    private func assetDecimalFromBaseUnits(_ raw: String?) -> Decimal {
        guard let raw, let value = Decimal(string: raw) else { return 0 }
        return value / Decimal(100_000_000)
    }

    private func formatCryptoAmount(_ value: Decimal) -> String {
        // Amount first, then coin code (e.g. "0.00042 BTC").
        "\(formatDecimal(value)) \(coin.code)"
    }

    private func formatFeeAmount(_ value: Decimal) -> String {
        value > 0 ? formatCryptoAmount(value) : "—"
    }

    /// Formats a fiat value in `fiatCurrencyCode`. Mirrors `MayaInputFormatter.fiat(_:currencyCode:)`
    /// so the Purchase/fee fiat lines match the source-side fiat format.
    private func formatFiat(_ value: Decimal) -> String {
        NumberFormatter.fiatDisplayFormatter(currencyCode: fiatCurrencyCode)
            .string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
