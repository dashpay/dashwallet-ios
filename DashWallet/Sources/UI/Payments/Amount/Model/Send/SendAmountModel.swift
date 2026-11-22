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
    /// first amount (duffs) confirms; `availableNowDuffs` is the most the
    /// screen can send right now, or nil when no amount can be named (no
    /// purchase option, or a limit the screen cannot verify). See
    /// `SwiftDashSDKWalletState.sendVerdict`.
    case fundsStillConfirming(UInt64, availableNowDuffs: UInt64?)

    var errorDescription: String? {
        switch self {
        case .maxUnavailable(let message): return message
        case .fundsStillConfirming(let duffs, let availableNowDuffs):
            guard let availableNowDuffs else {
                return String(localized: "\(duffs.formattedDashAmountWithoutCurrencySymbol) DASH is still confirming.",
                              comment: "Send amount fits the balance once incoming funds confirm; no usable amount can be named")
            }
            guard availableNowDuffs > 0 else {
                return String(localized: "None of your balance can be used until \(duffs.formattedDashAmountWithoutCurrencySymbol) DASH confirms. Wait a few minutes.",
                              comment: "Send amount fits the balance once incoming funds confirm; nothing is usable before then")
            }
            return String(localized: "\(duffs.formattedDashAmountWithoutCurrencySymbol) DASH is still confirming. You can use up to \(availableNowDuffs.formattedDashAmountWithoutCurrencySymbol) DASH now, or wait a few minutes for the rest.",
                          comment: "Send amount fits the balance once incoming funds confirm; %2$@ is the most usable right now")
        case .insufficientFunds: return String(localized: "Insufficient funds", comment: "Send screen")
        case .syncingChain: return String(localized: "Wait until wallet is synced to complete the transaction",
                                                     comment: "Send screen")
        case .networkUnavailable: return String(localized: "Network Unavailable", comment: "Network Unavailable")
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
    /// would cover it, else "Insufficient funds". `availableNowDuffs` is read
    /// only for a "still confirming" verdict.
    init?(refusing verdict: SendFundsVerdict, availableNowDuffs: @autoclosure () -> UInt64?) {
        switch verdict {
        case .fits: return nil
        case .confirming(let duffs): self = .fundsStillConfirming(duffs, availableNowDuffs: availableNowDuffs())
        case .insufficient: self = .insufficientFunds
        }
    }

    /// The amount a "still confirming" refusal may offer: the screen's ceiling
    /// when the smallest amount it accepts fits under it, else 0, which
    /// selects the wait-only wording rather than an amount the screen refuses.
    static func usableNowDuffs(ceilingDuffs: UInt64, minimumDuffs: UInt64) -> UInt64 {
        ceilingDuffs >= minimumDuffs ? ceilingDuffs : 0
    }

    /// The amount a confirming refusal on a Core-funded asset-lock route may
    /// name: nil when the route's minimum or one lock's capacity
    /// (`lockCapDuffs`, the most the amount can be) is unknown, or when the
    /// typed ceiling leaves nothing but a lock can still be funded — the
    /// drain Max prices differently, so zero would not establish that nothing
    /// is usable. 0 only when no lock can be funded at all.
    static func assetLockOfferDuffs(ceilingDuffs: UInt64, minimumDuffs: UInt64?, lockCapDuffs: UInt64?) -> UInt64? {
        guard let minimumDuffs, let lockCapDuffs else { return nil }
        let offer = usableNowDuffs(ceilingDuffs: min(ceilingDuffs, lockCapDuffs), minimumDuffs: minimumDuffs)
        return offer == 0 && lockCapDuffs > 0 ? nil : offer
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
    /// a subclass that gates on another balance (Coinbase) returns
    /// false so its refusals stay "Insufficient funds".
    var gatesOnWalletSendPool: Bool { true }

    private var syncingActivityMonitor: SyncingActivityMonitor { SyncingActivityMonitor.shared }

    init() {
        super.init()

        initializeSyncingActivityMonitor()
        observeSendableCeiling()
        observeVerdictInputs()
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
    /// a "still confirming" note; `observeVerdictInputs` keeps a shown funds
    /// verdict current in between.
    private func observeSendableCeiling() {
        SwiftDashSDKWalletState.shared.sendableCeiling
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, Self.ceilingMoveRechecks(self.error) else { return }
                self.error = nil
                self.checkAmountForErrors()
                self.validationDidChangeHandler?()
            }
            .store(in: &cancellableBag)
    }

    /// A "still confirming" note names the fee-aware Max, which follows the fee
    /// reserve as well as the ceiling, and the reserve, or whether the pooled
    /// figure is known at all, can move on its own. While a funds verdict is
    /// up, every verdict input re-judges the amount, and the error is
    /// re-presented only when the refusal it would show differs.
    private func observeVerdictInputs() {
        SwiftDashSDKWalletState.shared.sendVerdictInputsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self,
                      let shown = self.error as? SendAmountError,
                      Self.verdictInputsRefresh(shown: shown, refreshed: self.gateRefusal())
                else { return }
                self.error = nil
                self.checkAmountForErrors()
                self.validationDidChangeHandler?()
            }
            .store(in: &cancellableBag)
    }

    /// Whether a re-judged refusal replaces the `shown` one: only a shown
    /// funds verdict, and only when the refusal now differs from it.
    static func verdictInputsRefresh(shown: SendAmountError, refreshed: SendAmountError?) -> Bool {
        shown.isFundsVerdict && refreshed != shown
    }

    /// Whether a moved ceiling may re-judge the amount over `error`: only when
    /// there is none or it is a funds verdict, the one thing the ceiling
    /// decides. Anything else — a Max explanation that `checkAmountForErrors`
    /// never sets again, a subclass's own failure such as a Coinbase API
    /// error — survives the ceiling move. (A sync-state change still re-checks
    /// unconditionally, as it did before.)
    static func ceilingMoveRechecks(_ error: Error?) -> Bool {
        guard let error else { return true }
        return (error as? SendAmountError)?.isFundsVerdict == true
    }

    /// This model's gate on the amount on screen: `nil` when it fits, else the
    /// refusal to show. The gate itself holds nothing back for the fee, but the
    /// build will: the verdict keeps the fee reserve, so "wait" is only said
    /// when the amount can actually be sent once the coins confirm.
    private func gateRefusal() -> SendAmountError? {
        guard canShowInsufficientFunds else { return nil }
        guard gatesOnWalletSendPool else { return .insufficientFunds }
        let state = SwiftDashSDKWalletState.shared
        // One UTXO walk at most, and none for an amount the pool can never cover.
        var gate: (max: UInt64, reserve: UInt64)?
        func readGate() -> (max: UInt64, reserve: UInt64) {
            if let gate { return gate }
            let read = state.feeAwareMaxSendableAndReserve()
            gate = read
            return read
        }
        let verdict = state.sendVerdict(
            requestedDuffs: amount.plainAmount,
            ceilingDuffs: state.sendableDuffs,
            reserveDuffs: readGate().reserve)
        // The gate holds nothing back for the fee, so the amount to offer is
        // the fee-aware one Max fills, not `sendableDuffs`.
        return SendAmountError(
            refusing: verdict,
            availableNowDuffs: SendAmountError.usableNowDuffs(
                ceilingDuffs: readGate().max,
                minimumDuffs: CoreTxConstants.minOutputAmount)) ?? .insufficientFunds
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
            // button. Same three states, same wording, as the internal
            // transfer's Core Max.
            let state = SwiftDashSDKWalletState.shared
            let balance = state.balance
            error = SendAmountError.maxUnavailable(
                InternalTransferViewModel.coreZeroMaxMessage(
                    totalDuffs: balance?.total ?? 0,
                    confirmedSpendableDuffs: balance?.spendable ?? 0,
                    // Without this a CoinJoin-only wallet is told its balance
                    // is too small to cover the fee, which is not why Max is
                    // empty — the pool simply cannot draw on mixed coins.
                    excludedFromPoolDuffs: state.excludedFromSendPoolDuffs))
            return
        }

        updateCurrentAmountObject(with: allAvailableFunds)
    }

    override func checkAmountForErrors() {
        guard DWGlobalOptions.sharedInstance().isResyncingCurrentNetworkWallet == false ||
            SyncingActivityMonitor.shared.state == .syncDone
        else {
            error = SendAmountError.syncingChain
            return
        }

        error = gateRefusal()
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
