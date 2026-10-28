//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

// MARK: - SendAmountError

enum SendAmountError: Error, Equatable, ColorizedText, LocalizedError {
    case insufficientFunds
    case syncingChain
    case networkUnavailable
    /// "Max" had nothing to fill in, carrying the reason (empty balance,
    /// funds still confirming, or a balance below the fee reserve). Built by
    /// `InternalTransferViewModel.coreZeroMaxMessage`.
    case maxUnavailable(String)
    /// The amount is more than the confirmed balance but would fit once the
    /// carried amount (duffs) confirms. See
    /// `SwiftDashSDKWalletState.sendVerdict`.
    case fundsStillConfirming(UInt64)

    var errorDescription: String? {
        switch self {
        case .maxUnavailable(let message): return message
        case .fundsStillConfirming(let duffs):
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "%@ DASH is still confirming. Wait a few minutes or enter a smaller amount.",
                    comment: "Send amount fits the balance once incoming funds confirm"),
                duffs.formattedDashAmountWithoutCurrencySymbol)
        case .insufficientFunds: return NSLocalizedString("Insufficient funds", comment: "Send screen")
        case .syncingChain: return NSLocalizedString("Wait until wallet is synced to complete the transaction",
                                                     comment: "Send screen")
        case .networkUnavailable: return NSLocalizedString("Network Unavailable", comment: "Network Unavailable")
        }
    }

    var textColor: UIColor {
        switch self {
        case .insufficientFunds: return .systemRed
        case .syncingChain: return .secondaryLabel
        case .networkUnavailable: return .secondaryLabel
        // Informational, not a failure the user caused — same weight as the
        // syncing notice rather than the red insufficient-funds text.
        case .maxUnavailable: return .secondaryLabel
        // The money is there; it only needs time.
        case .fundsStillConfirming: return .secondaryLabel
        }
    }
}

extension SendAmountError {
    /// The refusal a wallet gate's verdict names, or `nil` when the amount
    /// fits: "still confirming" when the coins the gate does not count yet
    /// would cover it, else "Insufficient funds".
    init?(refusing verdict: SendFundsVerdict) {
        switch verdict {
        case .fits: return nil
        case .confirming(let duffs): self = .fundsStillConfirming(duffs)
        case .insufficient: self = .insufficientFunds
        }
    }

    /// An affordability verdict — the only kind a wallet-balance change may
    /// re-check without clearing something it does not own.
    var isFundsVerdict: Bool {
        switch self {
        case .insufficientFunds, .fundsStillConfirming: return true
        default: return false
        }
    }
}

// MARK: - SendAmountModel

class SendAmountModel: BaseAmountModel {
    override var isAllowedToContinue: Bool {
        super.isAllowedToContinue &&
            !canShowInsufficientFunds &&
            (DWGlobalOptions.sharedInstance().isResyncingCurrentNetworkWallet == false ||
                SyncingActivityMonitor.shared.state == .syncDone)
    }

    var canShowInsufficientFunds: Bool {
        let plainAmount = amount.plainAmount
        // The accounts a send can actually draw on, not the whole wallet:
        // `balance.spendable` also counts CoinJoin, which the funding pool
        // excludes by design, so gating on it accepts amounts the builder then
        // refuses with "insufficient unreserved core funds".
        let allAvailableFunds = SwiftDashSDKWalletState.shared.sendableDuffs
        return plainAmount > allAvailableFunds
    }

    /// Whether `canShowInsufficientFunds` refuses against the wallet's send
    /// pool. Only then can a shortfall be the wallet's coins still confirming;
    /// a subclass that gates on another balance (CrowdNode, Coinbase) returns
    /// false so its refusals stay "Insufficient funds".
    var gatesOnWalletSendPool: Bool { true }

    private var syncingActivityMonitor: SyncingActivityMonitor { SyncingActivityMonitor.shared }

    init() {
        super.init()

        initializeSyncingActivityMonitor()
        observeSendableCeiling()
        checkAmountForErrors()
    }

    /// The ceiling can move while this screen is open and the amount is
    /// untouched — a pooled read landing for the first time, coins confirming,
    /// or recovering from an outage and replacing the wallet-wide fallback
    /// with a much smaller transparent balance. `BaseAmountModel`'s balance
    /// subscription only refreshes `walletBalance`, and the view refreshes its
    /// button off `$amount`, so nothing revalidates an amount typed before the
    /// move.
    ///
    /// Both inputs matter, not just the pooled one: through a persistent pooled
    /// outage that value stays `nil` and `removeDuplicates` swallows every
    /// repeat, while `balance` keeps moving the fallback ceiling underneath.
    /// Deduplicating the RESOLVED ceiling instead reacts to whichever half
    /// changed, and still ignores updates that leave it where it was.
    ///
    /// Only a ceiling move re-judges here, not every verdict input: these
    /// screens present each assigned error (dropping a progress indicator and
    /// re-enabling Continue), so re-judging on every balance event is a hazard
    /// of its own. Coins that confirm raise the ceiling, which is what clears
    /// a "still confirming" note.
    private func observeSendableCeiling() {
        let state = SwiftDashSDKWalletState.shared
        SwiftDashSDKWalletState
            .sendableCeilingPublisher(
                pooled: state.$pooledSpendableDuffs.eraseToAnyPublisher(),
                walletSpendable: state.$balance.map { $0?.spendable }.eraseToAnyPublisher())
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let shown = self.error as? SendAmountError
                switch Self.walletChangeAction(for: self.error) {
                case .recheckAmount:
                    let next = self.amountError()
                    if next != shown { self.error = next }
                case .refreshMaxExplanation:
                    // Max can fill now: an amount typed before the tap is
                    // still on screen and needs its own verdict.
                    let next = self.maxUnavailableError() ?? self.amountError()
                    if next != shown { self.error = next }
                case .keep:
                    break
                }
                // Both re-assigning the error and the validation callback
                // re-present it on these screens, which drops any progress
                // indicator and resets Continue mid-build — so with the same
                // error still up neither runs. With no error the callback only
                // refreshes Continue, as it always has on a ceiling move.
                let changed = self.error is SendAmountError && (self.error as? SendAmountError) != shown
                guard self.error == nil || changed else { return }
                self.validationDidChangeHandler?()
            }
            .store(in: &cancellableBag)
    }

    enum WalletChangeAction: Equatable {
        /// Judge the amount again against the moved wallet state.
        case recheckAmount
        /// Max came up empty: say why again, or nothing once Max can fill.
        case refreshMaxExplanation
        /// Not the wallet's to decide.
        case keep
    }

    /// What a wallet-state change does to the error on screen. The amount is
    /// re-judged only when there is no error or a funds verdict, the one thing
    /// the wallet decides; `checkAmountForErrors` never sets a Max
    /// explanation, so that one is rebuilt rather than cleared; anything else —
    /// a subclass's own failure such as a Coinbase API error — stays until
    /// whoever set it clears it.
    static func walletChangeAction(for error: Error?) -> WalletChangeAction {
        guard let error else { return .recheckAmount }
        switch error as? SendAmountError {
        case .some(let verdict) where verdict.isFundsVerdict: return .recheckAmount
        case .some(.maxUnavailable): return .refreshMaxExplanation
        default: return .keep
        }
    }

    /// This model's gate on the amount on screen: `nil` when it fits, else the
    /// refusal to show. The gate itself holds nothing back for the fee, but the
    /// build will: the verdict keeps the fee reserve, so "wait" is only said
    /// when the amount can actually be sent once the coins confirm.
    private func gateRefusal() -> SendAmountError? {
        guard canShowInsufficientFunds else { return nil }
        guard gatesOnWalletSendPool else { return .insufficientFunds }
        let state = SwiftDashSDKWalletState.shared
        let verdict = state.sendVerdict(
            requestedDuffs: amount.plainAmount,
            ceilingDuffs: state.sendableDuffs,
            reserveDuffs: SwiftDashSDKTransactionSender.maxSendFeeReserveDuffs())
        return SendAmountError(refusing: verdict) ?? .insufficientFunds
    }

    override func selectAllFunds() {
        auth { [weak self] isAuthenticated in
            if isAuthenticated {
                self?.selectAllFundsWithoutAuth()
            }
        }
    }

    internal func selectAllFundsWithoutAuth() {
        // Fee-aware max: spendable minus the send fee reserve (the app-wide
        // WalletBalance.maxSendable contract), not raw spendable — the latter
        // leaves no room for the fee, so the send fails to build.
        let allAvailableFunds = SwiftDashSDKWalletState.shared.feeAwareMaxSendable()

        guard allAvailableFunds > 0 else {
            // A Max that can't fill anything must say why. Silently ignoring
            // the tap left the amount at 0 with no feedback, so an empty
            // balance, funds that are still confirming, and a balance too
            // small to also cover the fee were indistinguishable from a dead
            // button.
            error = maxUnavailableError(maxSendableDuffs: allAvailableFunds)
            return
        }

        updateCurrentAmountObject(with: allAvailableFunds)
    }

    /// Why Max cannot fill anything right now, or `nil` once it can. Same
    /// three states, same wording, as the internal transfer's Core Max.
    /// `maxSendableDuffs` is a Max the caller has just read, so the answer
    /// agrees with it; otherwise it is read here.
    private func maxUnavailableError(maxSendableDuffs: UInt64? = nil) -> SendAmountError? {
        let state = SwiftDashSDKWalletState.shared
        // An empty ceiling needs no reserve to know Max stays empty; the
        // reserve is a walk over every pooled UTXO, and this runs on each
        // balance event while the explanation is up.
        let maxDuffs = maxSendableDuffs ?? (state.sendableDuffs == 0 ? 0 : state.feeAwareMaxSendable())
        guard maxDuffs == 0 else { return nil }
        let balance = state.balance
        return SendAmountError.maxUnavailable(
            InternalTransferViewModel.coreZeroMaxMessage(
                totalDuffs: balance?.total ?? 0,
                confirmedSpendableDuffs: balance?.spendable ?? 0,
                // Without this a CoinJoin-only wallet is told its balance
                // is too small to cover the fee, which is not why Max is
                // empty — the pool simply cannot draw on mixed coins.
                excludedFromPoolDuffs: state.excludedFromSendPoolDuffs))
    }

    /// `final`: the ceiling subscription re-judges through `amountError()`,
    /// so a subclass gate added here would be skipped on wallet changes.
    final override func checkAmountForErrors() {
        error = amountError()
    }

    /// What `checkAmountForErrors` sets, without setting it.
    private func amountError() -> SendAmountError? {
        guard DWGlobalOptions.sharedInstance().isResyncingCurrentNetworkWallet == false ||
            SyncingActivityMonitor.shared.state == .syncDone
        else {
            return .syncingChain
        }
        return gateRefusal()
    }

    internal func auth(completionBlock: @escaping ((Bool) -> Void)) {
        let authManager = AuthenticationService.shared

        if authManager.didAuthenticate {
            completionBlock(true)
        }
        else {
            authManager.authenticate(withPrompt: nil,
                                     usingBiometricAuthentication: true,
                                     alertIfLockout: true) { authenticatedOrSuccess, _, _ in
                completionBlock(authenticatedOrSuccess)
            }
        }
    }

    deinit {
        syncingActivityMonitor.remove(observer: self)
    }
}

// MARK: SyncingActivityMonitorObserver

extension SendAmountModel: SyncingActivityMonitorObserver {
    private func initializeSyncingActivityMonitor() {
        syncingActivityMonitor.add(observer: self)
    }

    func syncingActivityMonitorProgressDidChange(_ progress: Double) { }

    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        checkAmountForErrors()
    }
}
