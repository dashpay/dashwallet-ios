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

    @objc func payWithTapGestureRecognizerAction() {
        let vc = PaymentMethodsController.controller()
        vc.paymentMethods = buyDashModel.paymentMethods
        present(vc, animated: true)
    }

    override func initializeModel() {
        model = BuyDashModel()
    }

    override func configureModel() {
        super.configureModel()
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        amountView.removeFromSuperview()
        contentView.addSubview(amountView)

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(payWithTapGestureRecognizerAction))

        let payWithView = PayWithView(frame: .zero)
        payWithView.translatesAutoresizingMaskIntoConstraints = false
        payWithView.addGestureRecognizer(tapGestureRecognizer)
        contentView.addSubview(payWithView)

        let sendingToView = SendingToView(frame: .zero)
        sendingToView.translatesAutoresizingMaskIntoConstraints = false

        topKeyboardView = sendingToView

        NSLayoutConstraint.activate([
            payWithView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            payWithView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            payWithView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            payWithView.heightAnchor.constraint(equalToConstant: 46),

            amountView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            amountView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            amountView.topAnchor.constraint(equalTo: payWithView.bottomAnchor, constant: 30),
            amountView.heightAnchor.constraint(equalToConstant: 60),
        ])
    }

    override func amountDidChange() {
        super.amountDidChange()

        actionButton?.isEnabled = true
    }
}
