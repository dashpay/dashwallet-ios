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
