//  
//  Created by Andrei Ashikhmin
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

protocol DepositWithdrawModelDelegate: CoinbaseTransactionDelegate {
    func coinbaseUserDidChange()

    func initiatePayment(with input: DWPaymentInput)
}

enum TransferDirection {
    case deposit
    case withdraw
    
    var imageName: String {
        switch self {
        case .deposit: return "image.explore.dash.wts.dash"
        case .withdraw: return "image.crowdnode.logo"
        }
    }
    
    var title: String {
        switch self {
        case .deposit: return "Deposit"
        case .withdraw: return "Withdraw"
        }
    }

    var direction: String {
        switch self {
        case .deposit: return "from Dash Wallet"
        case .withdraw: return "from CrowdNode"
        }
    }
    
    var keyboardHeader: String {
        switch self {
        case .deposit: return "Sending to CrowdNode account"
        case .withdraw: return "Sending to Dash Wallet on this device"
        }
    }
    
    var keyboardHeaderIcon: String {
        switch self {
        case .deposit: return "image.crowdnode.logo"
        case .withdraw: return "image.explore.dash.wts.dash"
        }
    }
}

final class DepositWithdrawModel: SendAmountModel, CoinbaseTransactionSendable {
    weak var delegate: TransferAmountModelDelegate?
    weak var transactionDelegate: CoinbaseTransactionDelegate? { delegate }
    
    public var address: String!
    public var direction: TransferDirection = .deposit
    
    internal var plainAmount: UInt64 { UInt64(amount.plainAmount) }
    
    var dashPriceDisplayString: String {
        let dashAmount = kOneDash
        let dashAmountFormatted = dashAmount.formattedDashAmount

        let priceManger = DSPriceManager.sharedInstance()
        let fiatBalanceFormatted = priceManger.localCurrencyString(forDashAmount: Int64(dashAmount)) ?? NSLocalizedString("Syncing", comment: "Price")

        let displayString = "\(dashAmountFormatted) DASH ≈ \(fiatBalanceFormatted)"
        return displayString
    }
    
    override func selectAllFunds(_ preparationHandler: () -> Void) {
        if direction == .deposit {
            super.selectAllFunds(preparationHandler)
        } else {
            // TODO:
            //            guard let balance = CrowdNode.shared.balance else { return }
            //
            //            let maxAmount = AmountObject(plainAmount: Int64(balance), fiatCurrencyCode: localCurrencyCode,
            //                                         localFormatter: localFormatter)
            //            updateCurrentAmountObject(with: maxAmount)
        }
    }
    
    func initializeTransfer() {
        
    }
    
    private func depositToCrowdNode() {
        //        // TODO: validate
                let amount = UInt64(amount.plainAmount)
        //
        //        obtainNewAddress { [weak self] address in
        //            guard let address else {
        //                self?.delegate?.transferFromCoinbaseToWalletDidFail(with: .transactionFailed(.failedToObtainNewAddress))
        //                return
        //            }
        //
        guard let paymentInput = DWPaymentInputBuilder().pay(toAddress: address, amount: amount) else {
            return
        }
        
//        self?.delegate?.initiatePayment(with: paymentInput)
    }
}


