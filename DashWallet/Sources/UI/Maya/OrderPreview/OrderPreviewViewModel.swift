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
    }

    // ── PRODUCT CONFIG ──────────────────────────────────────────────────────
    /// Change this ONE LINE to control when the success screen appears.
    static let successTrigger: MayaSuccessTrigger = .onDone
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
    @Published var submitErrorMessage: String?
    // Records that the Dash transaction was submitted to the blockchain network.
    // This does NOT confirm Maya swap completion — that requires separate on-chain confirmation.
    @Published var submittedTxId: String?
    @Published var swapStatus: MayaSwapStatus = .idle
    /// The true backend outcome from Maya's API, tracked independently of `swapStatus`.
    /// Updated by background polling after early success is shown.
    /// Never causes the success screen to be removed — only recorded for tx history.
    @Published var backendOutcome: MayaBackendOutcome = .pending

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

    private let dashSatoshis: Int64
    private var quote: MayaSwapQuote
    private var countdownCancellable: AnyCancellable?
    private let sendCoinsService = SendCoinsService()
    private var pollingTask: Task<Void, Never>?
    private var isLockCancellable: AnyCancellable?

    init(
        coin: MayaCryptoCurrency,
        address: String,
        dashSatoshis: Int64,
        fromDashAmount: String,
        fromFiatAmount: String,
        initialQuote: MayaSwapQuote
    ) {
        self.coin = coin
        self.address = address
        self.dashSatoshis = dashSatoshis
        self.fromDashAmount = fromDashAmount
        self.fromFiatAmount = fromFiatAmount
        self.quote = initialQuote
        applyQuote(initialQuote)
        startCountdown()
    }

    deinit {
        countdownCancellable?.cancel()
        pollingTask?.cancel()
        isLockCancellable?.cancel()
    }

    func handlePrimaryAction() async {
        if remainingSubmitSeconds > 0 {
            await submitSwap()
        } else {
            await refreshQuoteForDisplay()
        }
    }

    func resetToIdle() {
        pollingTask?.cancel()
        pollingTask = nil
        isLockCancellable?.cancel()
        isLockCancellable = nil
        swapStatus = .idle
        submittedTxId = nil
        backendOutcome = .pending
        // Clear error so the submitErrorMessage alert doesn't fire after the
        // failure sheet dismisses and swapStatus returns to .idle.
        submitErrorMessage = nil
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
            let newQuote = try await fetchFreshQuote()
            if let apiError = newQuote.error {
                submitErrorMessage = apiError
                return
            }
            quote = newQuote
            applyQuote(newQuote)
            resetCountdown()
        } catch {
            submitErrorMessage = error.localizedDescription
        }
    }

    private func fetchFreshQuote() async throws -> MayaSwapQuote {
        try await MayaAPIService.shared.fetchQuote(
            dashSatoshis: dashSatoshis,
            toAsset: coin.mayaAsset,
            destination: address
        )
    }

    private func submitSwap() async {
        guard !isSubmitting else { return }
        submittedTxId = nil
        submitErrorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            // Refresh quote immediately before commit so vault address and memo are fresh.
            // Mirrors Android's getSwapInfo call in MayaBlockchainApi.commitSwapTransaction.
            let freshQuote = try await fetchFreshQuote()
            if let apiError = freshQuote.error {
                setSubmitError(apiError)
                return
            }
            quote = freshQuote
            applyQuote(freshQuote)

            let execution = try resolveExecutionData(from: freshQuote)
            let tx = try await submitDashTransaction(using: execution)
            setSubmittedTransaction(tx)
        } catch {
            setSubmitError(error.localizedDescription)
        }
    }

    private func mayaFieldError(_ message: String) -> Error {
        NSError(domain: "Maya", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func resolveExecutionData(from quote: MayaSwapQuote) throws -> SwapExecutionData {
        guard let vaultAddress = quote.inboundAddress, !vaultAddress.isEmpty else {
            throw mayaFieldError(NSLocalizedString("Vault address is missing. Please refresh and try again.", comment: "Maya"))
        }
        guard let memo = quote.memo, !memo.isEmpty else {
            throw mayaFieldError(NSLocalizedString("Swap memo is missing. Please refresh and try again.", comment: "Maya"))
        }
        return SwapExecutionData(vaultAddress: vaultAddress, memo: memo, executionNetwork: "Maya")
    }

    private func submitDashTransaction(using execution: SwapExecutionData) async throws -> DSTransaction {
        try await sendCoinsService.sendMayaSwap(
            vaultAddress: execution.vaultAddress,
            dashAmount: UInt64(dashSatoshis),
            memo: execution.memo
        )
    }

    // MARK: - Private: State Mutation

    private func setSubmitError(_ message: String) {
        submitErrorMessage = message
        // Route ALL submission errors (pre-broadcast guard failures, network errors,
        // Maya API errors) through the failure sheet so the user sees the real reason.
        // Quote-refresh errors (refreshQuoteForDisplay) are intentionally excluded —
        // they don't change swapStatus and show as the submitErrorMessage alert instead.
        swapStatus = .failed(reason: message)
    }

    private func setSubmittedTransaction(_ tx: DSTransaction) {
        submittedTxId = tx.txHashHexString
        swapStatus = .pendingConfirmation
        startObservingISLock(txid: tx.txHashHexString)
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
                    case .onObserved, .onDone:
                        self.swapStatus = .processingSwap
                    }
                }

                self.isLockCancellable = nil  // one-shot
            }
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
                    let info = try await MayaAPIService.shared.fetchSwapTransactionInfo(txid: txid)

                    // Maya hasn't seen the Dash tx yet (block not confirmed) — keep waiting.
                    guard info.error == nil, let observedTx = info.observedTx else { continue }

                    let outcome = Self.classifyObservedTx(observedTx)
                    let successAlreadyShown: Bool = {
                        if case .completed = self.swapStatus { return true }
                        return false
                    }()

                    if successAlreadyShown {
                        // Success is on screen — NEVER regress swapStatus.
                        // Only update backendOutcome for tx history / future use.
                        switch outcome {
                        case .pending:
                            break  // still running, continue polling
                        case .done, .refunded:
                            self.backendOutcome = outcome
                            if case .refunded = outcome {
                                // Post-success refund detected. Record it; do not yank the
                                // success screen. Future: surface in tx history / a badge.
                                DSLogger.log("Maya: post-success refund detected for \(txid)")
                            }
                            return  // terminal state reached, stop polling
                        }
                    } else {
                        // Success not yet shown — drive swapStatus.
                        switch outcome {
                        case .done(let hashes):
                            self.swapStatus = .completed(outHashes: hashes)
                            self.backendOutcome = outcome
                            return
                        case .refunded:
                            self.swapStatus = .failed(reason: NSLocalizedString(
                                "Your DASH was refunded by Maya Protocol.",
                                comment: "Maya"
                            ))
                            self.backendOutcome = outcome
                            return
                        case .pending:
                            switch Self.successTrigger {
                            case .onISLock:
                                // IS-lock drives success; if IS-lock never arrived and we're
                                // still in pendingConfirmation, advance to processingSwap.
                                if case .pendingConfirmation = self.swapStatus {
                                    self.swapStatus = .processingSwap
                                }
                            case .onObserved:
                                // observedTx is present and not terminal-bad → show success.
                                // Keep polling so backendOutcome is eventually resolved.
                                self.swapStatus = .completed(outHashes: [])
                            case .onDone:
                                self.swapStatus = .processingSwap
                            }
                        }
                    }
                } catch {
                    // Transient network error — keep current status and retry next tick.
                }
            }

            // 30-minute timeout.
            let successAlreadyShown: Bool = {
                if case .completed = self.swapStatus { return true }
                return false
            }()

            if !successAlreadyShown {
                self.swapStatus = .failed(reason: NSLocalizedString(
                    "Swap timed out after 30 minutes. Contact Maya support if funds were sent.",
                    comment: "Maya"
                ))
            }
            // If success was already shown, silently stop. backendOutcome stays .pending
            // which signals that the terminal state was never confirmed within 30 min.
        }
    }

    /// Maps a Maya `observed_tx.status` string to `MayaBackendOutcome`.
    ///
    /// Status strings verified against Maya/Thorchain API:
    /// - `"done"`     — funds arrived at destination chain (terminal success)
    /// - `"refunded"` — Maya returned DASH to sender (terminal, treated as failure for UX)
    /// - `"aborted"`  — transaction aborted, may result in refund (terminal, treated as refund)
    /// - anything else (nil, "unknown", in-progress states) → `.pending`
    private static func classifyObservedTx(_ observedTx: MayaObservedTx) -> MayaBackendOutcome {
        switch observedTx.status {
        case "done":
            return .done(outHashes: observedTx.outHashes ?? [])
        case "refunded", "aborted":
            return .refunded
        default:
            return .pending
        }
    }

    private func applyQuote(_ quote: MayaSwapQuote) {
        let expectedOut = assetDecimalFromBaseUnits(quote.expectedAmountOut)
        let fee = assetDecimalFromBaseUnits(quote.fees?.total ?? quote.fees?.outbound)
        let total = expectedOut + fee

        toAmount = formatCryptoAmount(expectedOut)
        purchaseAmount = toAmount
        mayaFee = formatFeeAmount(fee)
        totalAmount = formatCryptoAmount(total)
        executionNetwork = quote.executionNetwork ?? "Maya"
    }

    // MARK: - Private: Formatting

    private func assetDecimalFromBaseUnits(_ raw: String?) -> Decimal {
        guard let raw, let value = Decimal(string: raw) else { return 0 }
        return value / Decimal(100_000_000)
    }

    private func formatCryptoAmount(_ value: Decimal) -> String {
        "\(coin.code) \(formatDecimal(value))"
    }

    private func formatFeeAmount(_ value: Decimal) -> String {
        value > 0 ? formatCryptoAmount(value) : "—"
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
