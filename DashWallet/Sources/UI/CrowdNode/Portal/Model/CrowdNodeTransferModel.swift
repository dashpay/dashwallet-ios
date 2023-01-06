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
    
    var successfulTransfer: String {
        switch self {
        case .deposit: return "Deposit sent"
        case .withdraw: return "Withdrawal requested"
        }
    }
    
    var successfulTransferDetails: String {
        switch self {
        case .deposit: return "It can take a minute for your balance to be updated."
        case .withdraw: return "It can take a minute for your funds to arrive."
        }
    }
    
    var failedTransfer: String {
        switch self {
        case .deposit: return "We couldn’t make a deposit to your CrowdNode account."
        case .withdraw: return "We couldn’t withdraw from your CrowdNode account."
        }
    }
}

final class CrowdNodeTransferModel: SendAmountModel {
    weak var delegate: TransferAmountModelDelegate?
    weak var transactionDelegate: CoinbaseTransactionDelegate? { delegate }
    public var direction: TransferDirection = .deposit
    
    override var isSendAllowed: Bool {
        let minDepositAmount = CrowdNode.apiOffset + ApiCode.maxCode().rawValue
        let minWithdrawAmount = CrowdNode.shared.balance / ApiCode.withdrawAll.rawValue
        let minValue = direction == .deposit ? minDepositAmount : minWithdrawAmount
        
        return super.isSendAllowed && amount.plainAmount > minValue
    }
    
    var dashPriceDisplayString: String {
        let dashAmount = kOneDash
        let dashAmountFormatted = dashAmount.formattedDashAmount

        let priceManger = DSPriceManager.sharedInstance()
        let fiatBalanceFormatted = priceManger.localCurrencyString(forDashAmount: Int64(dashAmount)) ?? NSLocalizedString("Syncing", comment: "Price")

        let displayString = "\(dashAmountFormatted) DASH ≈ \(fiatBalanceFormatted)"
        return displayString
    }
}
