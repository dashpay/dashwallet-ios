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

    var errorDescription: String? {
        switch self {
        case .maxUnavailable(let message): return message
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
        }
    }
}

// MARK: - SendAmountModel

class SendAmountModel: BaseAmountModel {
    override var isAllowedToContinue: Bool {
        super.isAllowedToContinue &&
            !canShowInsufficientFunds &&
            (DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
                SyncingActivityMonitor.shared.state == .syncDone)
    }

    var canShowInsufficientFunds: Bool {
        let plainAmount = amount.plainAmount
        let allAvailableFunds = SwiftDashSDKWalletState.shared.balance?.spendable ?? 0
        return plainAmount > allAvailableFunds
    }

    private var syncingActivityMonitor: SyncingActivityMonitor { SyncingActivityMonitor.shared }

    init() {
        super.init()

        initializeSyncingActivityMonitor()
        checkAmountForErrors()
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
            let balance = SwiftDashSDKWalletState.shared.balance
            error = SendAmountError.maxUnavailable(
                InternalTransferViewModel.coreZeroMaxMessage(
                    totalDuffs: balance?.total ?? 0,
                    confirmedSpendableDuffs: balance?.spendable ?? 0))
            return
        }

        updateCurrentAmountObject(with: allAvailableFunds)
    }

    override func checkAmountForErrors() {
        guard DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
            SyncingActivityMonitor.shared.state == .syncDone
        else {
            error = SendAmountError.syncingChain
            return
        }

        guard !canShowInsufficientFunds else {
            error = SendAmountError.insufficientFunds
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
