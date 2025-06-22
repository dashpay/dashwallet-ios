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
    case insufficientMixedFunds
    case syncingChain
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .insufficientMixedFunds: return NSLocalizedString("Insufficient mixed funds. Wait for CoinJoin mixing to finish or disable this feature in the settings to complete this transaction.", comment: "Send screen")
        case .insufficientFunds: return NSLocalizedString("Insufficient funds. Please add more Dash to your wallet or reduce the amount.", comment: "Send screen")
        case .syncingChain: return NSLocalizedString("Wait until wallet is synced to complete the transaction",
                                                     comment: "Send screen")
        case .networkUnavailable: return NSLocalizedString("Network Unavailable", comment: "Network Unavailable")
        }
    }

    var textColor: UIColor {
        switch self {
        case .insufficientFunds: return .systemRed
        case .insufficientMixedFunds: return .systemRed
        case .syncingChain: return .secondaryLabel
        case .networkUnavailable: return .secondaryLabel
        }
    }
}

// MARK: - SendAmountModel

class SendAmountModel: BaseAmountModel {
    @Published var coinJoinBalance: UInt64 = 0
    
    override var isAllowedToContinue: Bool {
        super.isAllowedToContinue &&
            !canShowInsufficientFunds &&
            (DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
                DWEnvironment.sharedInstance().currentChainManager.syncPhase == .synced)
    }

    var canShowInsufficientFunds: Bool {
        let plainAmount = amount.plainAmount

        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = CoinJoinService.shared.mixingState.isInProgress ? coinJoinBalance : account.maxOutputAmount

        return plainAmount > allAvailableFunds
    }

    private var syncingActivityMonitor: SyncingActivityMonitor { SyncingActivityMonitor.shared }

    override init() {
        super.init()

        initializeSyncingActivityMonitor()
        checkAmountForErrors()
        
        if CoinJoinService.shared.mixingState.isInProgress {
            CoinJoinService.shared.$progress
                .removeDuplicates()
                .sink { [weak self] progress in
                    self?.coinJoinBalance = progress.coinJoinBalance
                }
                .store(in: &cancellableBag)
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
        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = CoinJoinService.shared.mixingState.isInProgress ? coinJoinBalance : account.maxOutputAmount
        
        if allAvailableFunds > 0 {
            updateCurrentAmountObject(with: allAvailableFunds)
        }
    }

    override func checkAmountForErrors() {
        guard DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
            DWEnvironment.sharedInstance().currentChainManager.syncPhase == .synced
        else {
            error = SendAmountError.syncingChain
            return
        }

        guard !canShowInsufficientFunds else {
            error = CoinJoinService.shared.mixingState.isInProgress ? SendAmountError.insufficientMixedFunds : SendAmountError.insufficientFunds
            return
        }

        error = nil
    }

    internal func auth(completionBlock: @escaping ((Bool) -> Void)) {
        let authManager = DSAuthenticationManager.sharedInstance()

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
