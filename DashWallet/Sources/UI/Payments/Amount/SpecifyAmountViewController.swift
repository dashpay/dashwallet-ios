//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

// MARK: - SpecifyAmountViewControllerDelegate

@objc(DWSpecifyAmountViewControllerDelegate)
protocol SpecifyAmountViewControllerDelegate: AnyObject {
    func specifyAmountViewController(_ vc: SpecifyAmountViewController, didInput amount: UInt64)
}

// MARK: - SpecifyAmountViewController

@objc(DWSpecifyAmountViewController)
class SpecifyAmountViewController: BaseAmountViewController {
    @objc weak var delegate: SpecifyAmountViewControllerDelegate?

    override var actionButtonTitle: String? {
        NSLocalizedString("Receive", comment: "Specify Amount")
    }

    override func actionButtonAction(sender: UIView) {
        delegate?.specifyAmountViewController(self, didInput: UInt64(model.amount.plainAmount))
    }

    override func amountDidChange() {
        super.amountDidChange()

        actionButton?.isEnabled = model.isAmountValidForProceeding
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 26
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .dw_font(forTextStyle: .largeTitle).withWeight(UIFont.Weight.bold.rawValue)
        titleLabel.text = NSLocalizedString("Specify Amount", comment: "Specify Amount")
        stackView.addArrangedSubview(titleLabel)

        stackView.addArrangedSubview(amountView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }

    override func configureConstraints() {
        // NOP
    }
}
