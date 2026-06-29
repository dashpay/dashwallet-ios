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

import UIKit

protocol SendAmountFlowSupporting: ErrorPresentable where Self: UIViewController {
    var sendAmountSupportModel: BaseAmountModel { get }
}

extension SendAmountFlowSupporting {
    func validateInputAmount() -> Bool {
        if sendAmountSupportModel.isEnteredAmountLessThenMinimumOutputAmount {
            let message = String.localizedStringWithFormat(
                NSLocalizedString("Dash payments can't be less than %@", comment: "Send Dash"),
                sendAmountSupportModel.minimumOutputAmountFormattedString
            )
            present(message: message, level: .error)
            return false
        }

        return true
    }

    func checkLeftoverBalance(isCrowdNodeTransfer: Bool = false, completion: @escaping (Bool) -> Void) {
        if CrowdNodeDefaults.shared.lastKnownBalance <= 0 && !isCrowdNodeTransfer {
            completion(true)
            return
        }

        let account = DWEnvironment.sharedInstance().currentAccount
        let allAvailableFunds = account.maxOutputAmount

        if sendAmountSupportModel.amount.plainAmount + CrowdNode.minimumLeftoverBalance > allAvailableFunds {
            let title = NSLocalizedString("Looks like you are emptying your Dash Wallet", comment: "Leftover balance warning")
            let message = String.localizedStringWithFormat(
                NSLocalizedString(
                    "Please note, you will not be able to withdraw your funds from CrowdNode to this wallet until you increase your balance to %@ Dash.",
                    comment: "Leftover balance warning"
                ),
                CrowdNode.minimumLeftoverBalance.formattedDashAmountWithoutCurrencySymbol
            )
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("Continue", comment: "Leftover balance warning"),
                    style: .default,
                    handler: { _ in completion(true) }
                )
            )
            alert.addAction(
                UIAlertAction(
                    title: NSLocalizedString("Cancel", comment: "Leftover balance warning"),
                    style: .cancel,
                    handler: { _ in completion(false) }
                )
            )
            present(alert, animated: true)
        } else {
            completion(true)
        }
    }
}

// MARK: - SendAmountViewController

class SendAmountViewController: BaseAmountViewController, SendAmountFlowSupporting {
    override var isMaxButtonHidden: Bool { false }

    override var actionButtonTitle: String? { NSLocalizedString("Send", comment: "Send Dash") }

    internal var sendAmountModel: SendAmountModel {
        model as! SendAmountModel
    }

    var sendAmountSupportModel: BaseAmountModel {
        model
    }

    init() {
        super.init(model: SendAmountModel())
    }

    override init(model: BaseAmountModel) {
        super.init(model: model)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
