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

// MARK: - SendAmountViewController

class SendAmountViewController: BaseAmountViewController {
    override var actionButtonTitle: String? { NSLocalizedString("Send", comment: "Send Dash") }

    internal var sendAmountModel: SendAmountModel {
        model as! SendAmountModel
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeModel() {
        model = SendAmountModel()
    }

    override func maxButtonAction() {
        sendAmountModel.selectAllFunds { [weak self] in
            self?.amountView.amountType = .main
        }
    }

    override func amountDidChange() {
        super.amountDidChange()

        actionButton?.isEnabled = sendAmountModel.isSendAllowed
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        actionButton?.isEnabled = sendAmountModel.isSendAllowed
    }
}
