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

final class BuyDashViewController: BaseAmountViewController {
    override var actionButtonTitle: String? { NSLocalizedString("Continue", comment: "Buy Dash") }

    internal var buyDashModel: BuyDashModel {
        model as! BuyDashModel
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initializeModel() {
        model = BuyDashModel()
    }

    override func configureModel() {
        super.configureModel()
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        // amountView.removeFromSuperview()

        let sendingToView = SendingToView()
        sendingToView.translatesAutoresizingMaskIntoConstraints = false

        topKeyboardView = sendingToView
    }

    override func amountDidChange() {
        super.amountDidChange()

        actionButton?.isEnabled = true
    }
}
