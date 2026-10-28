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

enum SendAmountError: Error, ColorizedText, LocalizedError {
    case insufficientFunds
    case syncingChain
    case networkUnavailable
    /// "Max" had nothing to fill in, carrying the reason (empty balance,
    /// funds still confirming, or a balance below the fee reserve). Built by
    /// `InternalTransferViewModel.coreZeroMaxMessage`.
    case maxUnavailable(String)
    /// The amount is more than the confirmed balance but would fit once the
    /// carried amount (duffs) confirms. See
    /// `SwiftDashSDKWalletState.fundsStillConfirmingDuffs`.
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
    /// The refusal for an amount above a wallet gate: "still confirming" when
    /// the coins the gate does not count yet would cover it (see
    /// `SwiftDashSDKWalletState.fundsStillConfirmingDuffs`), else
    /// "Insufficient funds". `reserveDuffs` is what the gate holds back on top
    /// of the amount.
    static func walletShortfall(
        requestedDuffs: UInt64,
        ceilingDuffs: UInt64,
        reserveDuffs: @autoclosure () -> UInt64
    ) -> SendAmountError {
        SwiftDashSDKWalletState.shared.fundsStillConfirmingDuffs(
            requestedDuffs: requestedDuffs,
            ceilingDuffs: ceilingDuffs,
            reserveDuffs: reserveDuffs())
            .map(SendAmountError.fundsStillConfirming) ?? .insufficientFunds
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
        observeSendVerdictInputs()
        checkAmountForErrors()
    }

    /// The wallet can change under an amount typed earlier: the ceiling moves
    /// (a pooled read landing, or recovering from an outage and replacing the
    /// wallet-wide fallback with a much smaller transparent balance), coins
    /// start or finish confirming, which decides between "Insufficient funds"
    /// and "still confirming" with the ceiling where it was, and a Max
    /// explanation goes stale once Max can fill. `BaseAmountModel`'s balance
    /// subscription only refreshes `walletBalance`, and the view refreshes its
    /// button off `$amount`, so nothing else revalidates.
    private func observeSendVerdictInputs() {
        SwiftDashSDKWalletState.shared.sendVerdictInputsPublisher
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                switch Self.walletChangeAction(for: self.error) {
                case .recheckAmount:
                    self.error = nil
                    self.checkAmountForErrors()
                case .refreshMaxExplanation:
                    if let stillUnavailable = self.maxUnavailableError() {
                        self.error = stillUnavailable
                    } else {
                        // Max can fill now, but an amount typed before the
                        // tap is still on screen and needs its own verdict.
                        self.error = nil
                        self.checkAmountForErrors()
                    }
                case .keep:
                    return
                }
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
            error = maxUnavailableError()
            return
        }

        updateCurrentAmountObject(with: allAvailableFunds)
    }

    /// Why Max cannot fill anything right now, or `nil` once it can. Same
    /// three states, same wording, as the internal transfer's Core Max.
    private func maxUnavailableError() -> SendAmountError? {
        let state = SwiftDashSDKWalletState.shared
        // An empty ceiling needs no reserve to know Max stays empty; the
        // reserve is a walk over every pooled UTXO, and this runs on each
        // balance event while the explanation is up.
        guard state.sendableDuffs == 0 || state.feeAwareMaxSendable() == 0 else { return nil }
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

    override func checkAmountForErrors() {
        guard DWGlobalOptions.sharedInstance().isResyncingCurrentNetworkWallet == false ||
            SyncingActivityMonitor.shared.state == .syncDone
        else {
            error = SendAmountError.syncingChain
            return
        }

        guard !canShowInsufficientFunds else {
            // The gate itself holds nothing back for the fee, but the build
            // will: the fit keeps the fee reserve, so "wait" is only said when
            // the amount can actually be sent once the coins confirm.
            error = gatesOnWalletSendPool
                ? SendAmountError.walletShortfall(
                    requestedDuffs: amount.plainAmount,
                    ceilingDuffs: SwiftDashSDKWalletState.shared.sendableDuffs,
                    reserveDuffs: SwiftDashSDKTransactionSender.maxSendFeeReserveDuffs())
                : SendAmountError.insufficientFunds
            return
        }

        error = nil
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
