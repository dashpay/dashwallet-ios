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
import CoreData
import Foundation

private extension Error {
    var isUserAuthenticationCancellation: Bool {
        // `DashSpendError` is not Equatable, so match the case with `if case` instead of `==`.
        // `.some(...)` matches through the optional from `as?` (same form as `.previousSwapPending` below).
        if case .some(.authenticationCancelled) = self as? DashSpendError { return true }
        return false
    }
}

// MARK: - SwapSuccessTrigger

/// Controls when the success screen is shown to the user.
///
/// **ONE-LINER Product switch** — change `OrderPreviewViewModel.successTrigger`.
enum SwapSuccessTrigger {
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

// MARK: - SwapBackendOutcome

/// The true backend state of the swap as reported by Maya's API.
/// Never causes the user-facing `swapStatus` to regress — it is updated AFTER
/// success has already been shown, so the UI is never yanked away.
/// A post-success refund is recorded here for future surfacing in tx history.
enum SwapBackendOutcome: Equatable {
    case pending                          // Maya has not reached a terminal state yet
    case done(outHashes: [String])        // funds arrived at destination chain
    case refunded                         // Maya returned DASH to sender ("refunded"/"aborted")
}

// MARK: - SwapStatus

enum SwapStatus: Equatable {
    case idle
    case pendingConfirmation    // Dash tx broadcast, waiting for block
    case processingSwap         // Maya has observed the Dash tx, swap running
    case completed(outHashes: [String])
    case failed(reason: String)
}

@MainActor
final class OrderPreviewViewModel: ObservableObject {
    /// Deliberately NOT named `MayaConstants`: this type is used unqualified elsewhere in the
    /// file (`MayaConstants.mayaScanTransactionURL`), and a nested enum of that name shadows
    /// the global one.
    private enum MayaDepositRules {
        /// OP_RETURN standardness limit; a longer memo cannot be encoded on-chain.
        static let maxMemoBytes = 80
        /// Maya ignores deposits below its dust threshold.
        /// https://docs.mayaprotocol.com/mayachain-dev-docs/concepts/sending-transactions
        static let minimumDepositDuffs: Int64 = 10_000
    }

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
    static let successTrigger: SwapSuccessTrigger = .onISLock
    // ────────────────────────────────────────────────────────────────────────

    let coin: SwapCryptoCurrency
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
    @Published var swapStatus: SwapStatus = .idle
    @Published var pendingSwapAlertMessage: String?
    /// The true backend outcome from Maya's API, tracked independently of `swapStatus`.
    /// Updated by background polling after early success is shown.
    /// Never causes the success screen to be removed — only recorded for tx history.
    @Published var backendOutcome: SwapBackendOutcome = .pending
    @Published private(set) var isOnline: Bool

    /// Deep-link to the provider's hosted transaction tracker (nil for Maya).
    var trackerURL: URL? {
        guard let txid = submittedTxId, !txid.isEmpty else { return nil }
        return swapProvider.trackerURL(for: txid, depositAddress: lastDepositAddress)
    }

    /// Deep-link to the block explorer for the currently selected execution network.
    /// Mirrors Android's network-aware explorer resolution and stays independent of hosted trackers.
    var explorerLink: (url: URL, text: String)? {
        let network = resolvedExecutionNetwork.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedNetwork = network.lowercased()

        if network.isEmpty || lowercasedNetwork.contains("maya") {
            let url: URL
            if let txid = submittedTxId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !txid.isEmpty {
                url = MayaConstants.mayaScanTransactionURL(txHash: txid.uppercased())
            } else {
                url = URL(string: "https://www.mayascan.org/")!
            }

            return (
                url: url,
                text: NSLocalizedString("View MayaChain explorer", comment: "Dash DEX")
            )
        }

        if lowercasedNetwork.contains("near") {
            let url: URL
            if let depositAddress = lastDepositAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
               !depositAddress.isEmpty {
                url = NearConstants.explorerTransactionURL(depositAddress: depositAddress)
            } else {
                url = NearConstants.explorerHomeURL
            }

            return (
                url: url,
                text: NSLocalizedString("View NEAR Intents explorer", comment: "Dash DEX")
            )
        }

        return nil
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
                    ? NSLocalizedString("Swap fee", comment: "Dash DEX")
                    : String(format: NSLocalizedString("%@ fee", comment: "Dash DEX"), executionNetwork)
            )
    }

    var usesGenericFeeLabel: Bool {
        swapProvider.usesGenericFeeLabel
    }

    var timerText: String {
        String(
            format: NSLocalizedString("%ld sec", comment: "Dash DEX"),
            CLong(remainingSubmitSeconds)
        )
    }

    var confirmButtonText: String {
        // The countdown is shown separately as `timerText`, so the button is just "Confirm"
        // while the quote is live, and switches to "Refresh quote" once it expires.
        remainingSubmitSeconds > 0
            ? NSLocalizedString("Confirm", comment: "Dash DEX")
            : NSLocalizedString("Refresh quote", comment: "Dash DEX")
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
    private var daoCancellable: AnyCancellable?
    private var isLockCancellable: AnyCancellable?
    /// Wire-order txid (`Transaction.txHashData` convention) of the broadcast swap deposit,
    /// returned by `WalletSendService.send`. Used to re-fetch the tx's SDK-tracked state.
    private var submittedTxidWire: Data?
    private var didInitialLoad = false
    private var lastDepositAddress: String?
    private let networkStatus: NetworkStatusProviding
    private var networkCancellable: AnyCancellable?

    init(
        coin: SwapCryptoCurrency,
        address: String,
        dashSatoshis: Int64,
        fromDashAmount: String,
        fromFiatAmount: String,
        cryptoFiatRate: Decimal,
        fiatCurrencyCode: String,
        targetReceiveAmount: Decimal? = nil,
        initialQuote: SwapQuoteResult,
        swapProvider: SwapProvider = MayaSwapProvider(),
        networkStatus: NetworkStatusProviding = NetworkStatusService.shared
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
        self.networkStatus = networkStatus
        self.isOnline = networkStatus.isOnline
        self.quote = initialQuote
        applyQuote(initialQuote)
        subscribeToNetworkStatus()
    }

    deinit {
        countdownCancellable?.cancel()
        daoCancellable?.cancel()
        isLockCancellable?.cancel()
        networkCancellable?.cancel()
    }

    func handlePrimaryAction() async {
        guard isOnline else { return }
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
        daoCancellable?.cancel()
        daoCancellable = nil
        isLockCancellable?.cancel()
        isLockCancellable = nil
        submittedTxidWire = nil
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
        guard isOnline, !isRetrying else { return nil }
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

    // MARK: - Private: Network Status

    private func subscribeToNetworkStatus() {
        networkCancellable = networkStatus.statusPublisher
            .sink { [weak self] status in
                self?.isOnline = status == .online
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
            toAsset: coin.swapAsset,
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
            let txidWire = try await submitDashTransaction(using: execution)
            setSubmittedSwap(txidWire: txidWire, depositAddress: execution.vaultAddress)
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

    private func swapFieldError(_ message: String) -> Error {
        NSError(domain: "DashDEX", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func resolveExecutionData(from quote: SwapQuoteResult) throws -> SwapExecutionData {
        guard let vaultAddress = quote.inboundAddress, !vaultAddress.isEmpty else {
            throw swapFieldError(NSLocalizedString("Deposit address is missing. Please refresh and try again.", comment: "Dash DEX"))
        }

        let trimmedMemo = quote.memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedMemo = (trimmedMemo?.isEmpty == false) ? trimmedMemo : nil

        // Fund-loss safety net. A memo-bearing quote (a MAYACHAIN route) must reach the chain
        // with its memo in an OP_RETURN — a memo-less send would orphan the funds at the vault.
        // Over the 80-byte standardness limit the memo cannot be encoded at all, so refuse the
        // swap rather than broadcast one the network would treat as a plain send.
        if let resolvedMemo, resolvedMemo.utf8.count > MayaDepositRules.maxMemoBytes {
            throw swapFieldError(SwapKitErrorCopy.mayaMemoTooLongErrorCode)
        }

        // Maya's dust floor applies to memo-bearing deposits. Keyed on the memo alone: every
        // MAYACHAIN route carries one, and `executionNetwork` is a display label from
        // `prettifyProviders` — matching text in it would tie a money rule to UI copy.
        if resolvedMemo != nil, dashSatoshis < MayaDepositRules.minimumDepositDuffs {
            let minimum = Decimal(MayaDepositRules.minimumDepositDuffs) / Decimal(kOneDash)
            let format = NSLocalizedString("The minimum DASH deposit for this swap is %@.", comment: "Dash DEX")
            throw swapFieldError(String(format: format, minimum.formattedDashAmount))
        }

        let resolvedExecutionNetwork = quote.executionNetwork?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SwapExecutionData(
            vaultAddress: vaultAddress,
            memo: resolvedMemo,
            executionNetwork: {
                if let resolvedExecutionNetwork, !resolvedExecutionNetwork.isEmpty {
                    return resolvedExecutionNetwork
                }
                return swapProvider.displayName
            }()
        )
    }

    /// Broadcasts the DASH deposit and returns its wire-order txid.
    ///
    /// `dashSatoshis` is deposited as-is. SwapKit's `sellAmount` **is** the deposit amount and
    /// its `expectedBuyAmount` is already net of fees, so nothing is added on top. (Android's
    /// direct-Maya path adds the outbound fee to the vault output because MayaNode's
    /// `/quote/swap?amount=` means the swap amount, not the deposit — a different contract.)
    private func submitDashTransaction(using execution: SwapExecutionData) async throws -> Data {
        try await sendCoinsService.sendSwapKitSwap(
            depositAddress: execution.vaultAddress,
            dashAmount: UInt64(dashSatoshis),
            memo: execution.memo
        )
    }

    // MARK: - Private: State Mutation

    private func setFailure(_ message: String) {
        // Log before mapping: `userFacingErrorMessage` collapses anything unrecognised into a
        // generic "something went wrong", so this is the last point at which the real reason
        // still exists. Without it a "Conversion failed" screenshot has no counterpart in the
        // exported logs and cannot be diagnosed.
        DWLogger.log("Swap: conversion failed for \(coin.code) — raw: \(message)")
        // Keep Maya failures on the status sheet path so SwiftUI does not try to
        // present a native alert and a bottom sheet for the same event.
        swapStatus = .failed(reason: userFacingErrorMessage(for: message))
    }

    private func userFacingErrorMessage(for message: String) -> String {
        SwapKitErrorCopy.message(for: message, coin: coin)
    }

    private func setSubmittedSwap(txidWire: Data, depositAddress: String) {
        let txidHex = Transaction.displayHex(txidWire)
        // The success side needs a trace too: without it a log export can't distinguish
        // "the deposit never went out" from "it went out and the swap failed later".
        DWLogger.log("Swap: deposit broadcast for \(coin.code) — txid=\(txidHex) deposit=\(depositAddress)")
        submittedTxidWire = txidWire
        submittedTxId = txidHex
        lastDepositAddress = depositAddress
        swapStatus = .pendingConfirmation
        saveSwapOrder(txidHex: txidHex, depositAddress: depositAddress)
        startObservingISLock(txidWire: txidWire)
        startObservingDAO(orderId: txidHex)
    }

    // MARK: - Private: Swap order persistence

    private func saveSwapOrder(txidHex: String, depositAddress: String) {
        let service = swapProvider is MayaSwapProvider ? "maya" : "swapkit"
        let order = SwapOrder(
            id: txidHex,
            direction: "sell",
            service: service,
            provider: resolvedExecutionNetwork,
            fromAsset: "DASH",
            toAsset: coin.swapAsset,
            toAddress: address,
            depositAddress: depositAddress,
            expectedToAmount: toAmount,
            status: .notStarted
        )
        Task {
            await SwapOrdersDAOImpl.shared.create(dto: order)
        }
    }

    // MARK: - Private: IS-Lock Observation

    /// Observes the broadcast deposit's InstantSend lock via SwiftDashSDK. The Rust persister
    /// updates the tx's context byte (0=mempool → 1=instantSend) and saves, which fires
    /// `NSManagedObjectContextDidSave` — the same signal `HomeViewModel` refreshes on. On each
    /// save we re-read the tx's `state`; `.ok` means context >= 1 (InstantSend-locked or
    /// better). No `DS*` notifications and no `DSTransaction` are involved.
    private func startObservingISLock(txidWire: Data) {
        // Fast path: already locked (e.g. re-entry after a quick lock).
        if handleISLockIfLocked(txidWire: txidWire) { return }

        isLockCancellable = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                _ = self?.handleISLockIfLocked(txidWire: txidWire)
            }
    }

    /// Advances `swapStatus` once the deposit tx is InstantSend-locked (SDK `state == .ok`).
    /// Returns true once locked so the caller can stop observing. Never regresses a terminal state.
    @discardableResult
    private func handleISLockIfLocked(txidWire: Data) -> Bool {
        guard let tx = SwiftDashSDKWalletSource.fetch(txid: txidWire), tx.state == .ok else {
            return false
        }

        DWLogger.log("DashDEX: IS-lock observed for \(Transaction.displayHex(txidWire))")

        switch Self.successTrigger {
        case .onISLock, .onDashConfirmation:
            // context >= 1 (InstantSend-locked) is the on-chain finality signal under
            // SwiftDashSDK. DAO/tracking stays background-only and must not block Done.
            // TODO(swap-sdk-confirmation): a strict ".onDashConfirmation" (>= 1 block) would need
            // an SDK accessor for context >= 2 (inBlock); today `Transaction.state` only exposes
            // context == 0 vs >= 1, and IS-lock is a stronger finality signal than a single block.
            switch swapStatus {
            case .pendingConfirmation, .processingSwap:
                swapStatus = .completed(outHashes: [])
            default:
                break
            }
        case .onObserved, .onDone:
            if case .pendingConfirmation = swapStatus {
                // IS-lock alone is NOT success here — it only advances the UI to "processing".
                // Success requires the backend condition, surfaced via the DAO observer.
                swapStatus = .processingSwap
            }
        }

        isLockCancellable = nil  // one-shot
        return true
    }

    // MARK: - Private: DAO observation (replaces the in-memory 30-min polling loop)

    private func startObservingDAO(orderId: String) {
        daoCancellable?.cancel()
        daoCancellable = SwapOrdersDAOImpl.shared.observeAll()
            .compactMap { orders in orders.first { $0.id == orderId } }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] order in
                self?.applyDAOUpdate(order)
            }
    }

    /// Reacts to a DAO status write from `SwapTrackingService`.
    /// Never regresses a terminal user-facing state; only records `backendOutcome` silently
    /// when success is already on screen.
    private func applyDAOUpdate(_ order: SwapOrder) {
        if isSuccessAlreadyShown {
            switch order.status {
            case .completed:
                backendOutcome = .done(outHashes: [order.outboundTxHash].compactMap { $0 })
            case .refunded, .failed:
                backendOutcome = .refunded
                DWLogger.log("DEX: post-success \(order.status.rawValue) for \(order.id)")
            default: break
            }
            return
        }

        switch order.status {
        case .completed:
            swapStatus = .completed(outHashes: [order.outboundTxHash].compactMap { $0 })
            backendOutcome = .done(outHashes: [order.outboundTxHash].compactMap { $0 })
            daoCancellable?.cancel()
        case .refunded:
            swapStatus = .failed(reason: String(format: NSLocalizedString(
                "Your DASH was refunded by %@.",
                comment: "Swap refund message — %@ is the provider name e.g. Maya"
            ), swapProvider.displayName))
            backendOutcome = .refunded
            daoCancellable?.cancel()
        case .failed:
            if !isSuccessAlreadyShown {
                swapStatus = .failed(reason: NSLocalizedString(
                    "Swap timed out. Contact support if funds were sent.",
                    comment: "Dash DEX"
                ))
            }
            backendOutcome = .refunded
            daoCancellable?.cancel()
        case .pending, .swapping, .notStarted, .unknown, .expired:
            // `.expired` is a neutral age-out (funds may have arrived) — never flip the live screen
            // to a failure on it. It only occurs 24 h out, long after this screen is gone.
            if Self.successTrigger != .onISLock, case .pendingConfirmation = swapStatus {
                swapStatus = .processingSwap
            }
        }
    }

    private var isSuccessAlreadyShown: Bool {
        if case .completed = swapStatus { return true }
        return false
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
            throw swapFieldError(apiError)
        }
        guard let firstPoint = makeQuotePoint(dashSatoshis: dashSatoshis, quote: firstQuote) else {
            throw swapFieldError(NSLocalizedString("Unable to refresh quote. Please try again.", comment: "Swap"))
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
        // Cap swaps at the SDK's max-sendable balance (spendable minus the send fee reserve);
        // the frozen DashSync account balance reads stale/zero post-migration.
        Int64(SwiftDashSDKWalletState.shared.feeAwareMaxSendable())
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

    /// Formats a fiat value in `fiatCurrencyCode`. Mirrors `SwapInputFormatter.fiat(_:currencyCode:)`
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
