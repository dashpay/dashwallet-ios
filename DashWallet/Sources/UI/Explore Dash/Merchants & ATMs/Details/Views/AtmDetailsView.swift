//
//  Created by Pavel Tikhonenko
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

import MapKit
import UIKit

class AtmDetailsView: PointOfUseDetailsView {
    override func configureGiftCardSection() {
        // Create first block with header and ATM buttons (no CTX section)
        let firstBlock = UIView()
        firstBlock.translatesAutoresizingMaskIntoConstraints = false
        firstBlock.backgroundColor = .dw_secondaryBackground()
        firstBlock.layer.cornerRadius = 12

        containerView.addArrangedSubview(firstBlock)

        let firstBlockStack = UIStackView()
        firstBlockStack.translatesAutoresizingMaskIntoConstraints = false
        firstBlockStack.axis = .vertical
        firstBlockStack.spacing = 16
        firstBlock.addSubview(firstBlockStack)

        // Header section
        let headerSection = createHeaderSection()
        firstBlockStack.addArrangedSubview(headerSection)

        // ATM Buttons section
        let buttonsStackView = UIStackView()
        buttonsStackView.spacing = 5
        buttonsStackView.axis = .horizontal
        buttonsStackView.distribution = .fillEqually
        firstBlockStack.addArrangedSubview(buttonsStackView)

        let payButton = ActionButton()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(payAction), for: .touchUpInside)
        payButton.setTitle(NSLocalizedString("Buy Dash", comment: "Buy Dash"), for: .normal)
        payButton.accentColor = UIColor(red: 0.235, green: 0.722, blue: 0.471, alpha: 1)
        buttonsStackView.addArrangedSubview(payButton)

        if let atm = merchant.atm, atm.type == .buySell || atm.type == .sell {
            let sellButton = ActionButton()
            sellButton.translatesAutoresizingMaskIntoConstraints = false
            sellButton.addTarget(self, action: #selector(sellAction), for: .touchUpInside)
            sellButton.setTitle(NSLocalizedString("Sell Dash", comment: "Sell Dash"), for: .normal)
            sellButton.accentColor = .dw_dashBlue()
            buttonsStackView.addArrangedSubview(sellButton)
        }

        NSLayoutConstraint.activate([
            payButton.heightAnchor.constraint(equalToConstant: 48),
            firstBlockStack.topAnchor.constraint(equalTo: firstBlock.topAnchor, constant: 16),
            firstBlockStack.leadingAnchor.constraint(equalTo: firstBlock.leadingAnchor, constant: 16),
            firstBlockStack.trailingAnchor.constraint(equalTo: firstBlock.trailingAnchor, constant: -16),
            firstBlockStack.bottomAnchor.constraint(equalTo: firstBlock.bottomAnchor, constant: -16)
        ])
    }
}
