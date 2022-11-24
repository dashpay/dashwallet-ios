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

class SendAmountModel: BaseAmountModel {
    override var showMaxButton: Bool { return false }
    
    var isSendAllowed: Bool {
        (DWGlobalOptions.sharedInstance().isResyncingWallet == false ||
         DWEnvironment.sharedInstance().currentChainManager.syncPhase == .chainSync)
    }
    
    override init() {
        super.init()
    }
    
    func selectAllFunds(_ preparationHandler: (() -> Void)) {
        let authManager = DSAuthenticationManager.sharedInstance()
        
        if authManager.didAuthenticate {
            selectAllFunds()
        } else {
            authManager.authenticate(withPrompt: nil, usingBiometricAuthentication: true, alertIfLockout: true) { [weak self] authenticatedOrSuccess, _, _ in
                if (authenticatedOrSuccess) {
                    self?.selectAllFunds()
                }
            }
        }
    }
    
    private func selectAllFunds() {
        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = account.maxOutputAmount
        
        if allAvailableFunds > 0 {
            updateCurrentAmountObject(with: Int64(allAvailableFunds))
        }
    }
    
    internal func updateCurrentAmountObject(with amount: Int64) {
        let amountObject = AmountObject(plainAmount: Int64(amount), fiatCurrencyCode: localCurrencyCode, localFormatter: localFormatter)
        updateCurrentAmountObject(with: amountObject)
    }
    
    internal func updateCurrentAmountObject(with newObject: AmountObject) {
        if activeAmountType == .main {
            mainAmount = newObject
            supplementaryAmount = nil
        } else {
            mainAmount = nil
            supplementaryAmount = newObject.localAmount(localValidator: supplementaryAmountValidator, localFormatter: localFormatter, currencyCode: localCurrencyCode)
        }
        
        amountChangeHandler?(newObject)
    }
}
