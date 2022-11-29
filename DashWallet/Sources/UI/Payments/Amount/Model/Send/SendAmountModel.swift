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

enum SendAmountError {
    case insufficientFunds
    case syncingChain

    var localizedString: String {
        switch self {
        case .insufficientFunds: return NSLocalizedString("Insufficient funds", comment: "Send screen")
        case .syncingChain: return NSLocalizedString("Wait until wallet is synced to complete the transaction", comment: "Send screen")
        }
    }

    var textColor: UIColor {
        switch self {
        case .insufficientFunds: return .systemRed
        case .syncingChain: return .secondaryLabel
        }
    }
}

class SendAmountModel: BaseAmountModel {
    override var showMaxButton: Bool { return false }

    var error: SendAmountError? {
        didSet {
            if let error {
                errorHandler?(error)
            }
        }
    }

    var errorHandler: ((SendAmountError) -> Void)?

    var isSendAllowed: Bool {
        amount.plainAmount > 0 && !canShowInsufficientFunds && (DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
            DWEnvironment.sharedInstance().currentChainManager.syncPhase == .synced)
    }

    var canShowInsufficientFunds: Bool {
        let plainAmount = amount.plainAmount

        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = account.maxOutputAmount

        let authenticationManager = DSAuthenticationManager.sharedInstance()
        let canShowInsufficientFunds = authenticationManager.didAuthenticate

        return canShowInsufficientFunds && (plainAmount > allAvailableFunds)
    }

    private var syncingActivityMonitor: SyncingActivityMonitor { SyncingActivityMonitor.shared }

    override init() {
        super.init()

        initializeSyncingActivityMonitor()
    }

    func selectAllFunds(_ preparationHandler: () -> Void) {
        let authManager = DSAuthenticationManager.sharedInstance()

        if authManager.didAuthenticate {
            selectAllFunds()
        }
        else {
            authManager.authenticate(withPrompt: nil, usingBiometricAuthentication: true, alertIfLockout: true) { [weak self] authenticatedOrSuccess, _, _ in
                if authenticatedOrSuccess {
                    self?.selectAllFunds()
                }
            }
        }
    }

    override func amountDidChange() {
        checkError()

        super.amountDidChange()
    }

    private func selectAllFunds() {
        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = account.maxOutputAmount

        if allAvailableFunds > 0 {
            updateCurrentAmountObject(with: Int64(allAvailableFunds))
        }
    }

    private func checkError() {
        guard DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
            DWEnvironment.sharedInstance().currentChainManager.syncPhase == .synced
        else {
            error = .syncingChain
            return
        }

        guard !canShowInsufficientFunds else {
            error = .insufficientFunds
            return
        }

        error = nil
    }

    deinit {
        syncingActivityMonitor.remove(observer: self)
    }
}

extension SendAmountModel: SyncingActivityMonitorObserver {
    private func initializeSyncingActivityMonitor() {
        syncingActivityMonitor.add(observer: self)
    }

    func syncingActivityMonitorProgressDidChange(_ progress: Double) {}

    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        checkError()
    }
}
