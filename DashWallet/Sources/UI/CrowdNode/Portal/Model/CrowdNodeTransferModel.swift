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

// MARK: - DepositWithdrawModelDelegate

protocol DepositWithdrawModelDelegate: CoinbaseTransactionDelegate {
    func coinbaseUserDidChange()

    func initiatePayment(with input: DWPaymentInput)
}

// MARK: - TransferDirection

enum TransferDirection {
    case deposit
    case withdraw

    var imageName: String {
        DSLogger.log("CrowdNodeDeposit: get imageName")
        switch self {
        case .deposit: return "image.explore.dash.wts.dash"
        case .withdraw: return "image.crowdnode.logo"
        }
    }

    var title: String {
        DSLogger.log("CrowdNodeDeposit: get title")
        switch self {
        case .deposit: return NSLocalizedString("Deposit", comment: "CrowdNode")
        case .withdraw: return NSLocalizedString("Withdraw", comment: "CrowdNode")
        }
    }

    var direction: String {
        DSLogger.log("CrowdNodeDeposit: get direction")
        switch self {
        case .deposit: return NSLocalizedString("from Dash Wallet", comment: "from Dash Wallet")
        case .withdraw: return NSLocalizedString("from CrowdNode", comment: "from CrowdNode")
        }
    }

    var keyboardHeader: String {
        DSLogger.log("CrowdNodeDeposit: get keyboardHeader")
        switch self {
        case .deposit: return NSLocalizedString("Sending to CrowdNode account", comment: "CrowdNode")
        case .withdraw: return NSLocalizedString("Sending to Dash Wallet on this device", comment: "CrowdNode")
        }
    }

    var keyboardHeaderIcon: String {
        DSLogger.log("CrowdNodeDeposit: get keyboardHeaderIcon")
        switch self {
        case .deposit: return "image.crowdnode.logo"
        case .withdraw: return "image.explore.dash.wts.dash"
        }
    }

    var successfulTransfer: String {
        switch self {
        case .deposit: return NSLocalizedString("Deposit sent", comment: "CrowdNode")
        case .withdraw: return NSLocalizedString("Withdrawal requested", comment: "CrowdNode")
        }
    }

    var successfulTransferDetails: String {
        switch self {
        case .deposit: return NSLocalizedString("It can take a minute for your balance to be updated.", comment: "CrowdNode")
        case .withdraw: return NSLocalizedString("It can take a minute for your funds to arrive.", comment: "CrowdNode")
        }
    }

    var failedTransfer: String {
        switch self {
        case .deposit: return NSLocalizedString("We couldn’t make a deposit to your CrowdNode account.", comment: "CrowdNode")
        case .withdraw: return NSLocalizedString("We couldn’t withdraw from your CrowdNode account.", comment: "CrowdNode")
        }
    }
}

// MARK: - CrowdNodeTransferModel

final class CrowdNodeTransferModel: SendAmountModel {
    weak var delegate: TransferAmountModelDelegate?
    weak var transactionDelegate: CoinbaseTransactionDelegate? { delegate }
    public var direction: TransferDirection = .deposit

    var dashPriceDisplayString: String {
        DSLogger.log("CrowdNodeDeposit: get dashPriceDisplayString")
        let dashAmount = kOneDash
        let dashAmountFormatted = dashAmount.formattedDashAmount
        let fiatBalanceFormatted = CurrencyExchanger.shared.fiatAmountString(in: localCurrencyCode, for: dashAmount.dashAmount)

        let displayString = "\(dashAmountFormatted) ≈ \(fiatBalanceFormatted)"
        return displayString
    }

    override var isAllowedToContinue: Bool {
        let minDepositAmount = CrowdNode.apiOffset + ApiCode.maxCode().rawValue
        let minWithdrawAmount = CrowdNode.shared.balance / ApiCode.withdrawAll.rawValue
        let minValue = direction == .deposit ? minDepositAmount : minWithdrawAmount

        return super.isAllowedToContinue && amount.plainAmount > minValue
    }

    override var canShowInsufficientFunds: Bool {
        if direction == .deposit {
            return super.canShowInsufficientFunds
        } else {
            return amount.plainAmount > CrowdNode.shared.balance
        }
    }

    override func selectAllFunds() {
        if direction == .deposit {
            super.selectAllFunds()
        } else {
            super.updateCurrentAmountObject(with: CrowdNode.shared.balance)
        }
    }
}
