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

import UIKit

class MerchantInfoViewController: PointOfUseInfoViewController {

    @objc func learnMoreAction() {
        let vc = GiftCardInfoViewController()
        present(vc, animated: true)
    }

    @objc func continueButtonAction() {
        dismiss(animated: true)
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        let contentView = UIStackView()
        contentView.axis = .vertical
        contentView.spacing = 30
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .dw_label()
        titleLabel.font = UIFont.dw_font(forTextStyle: .title1)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = NSLocalizedString("We have 2 types of merchants", comment: "")
        contentView.addArrangedSubview(titleLabel)

        var itemView: UIStackView?
        itemView = merchantTypeView(for: NSLocalizedString("Accepts DASH directly", comment: ""),
                                    subtitle: NSLocalizedString("Pay with the DASH Wallet.", comment: ""),
                                    image: UIImage(named: "image.explore.dash.wts.dash"))
        if let itemView {
            contentView.addArrangedSubview(itemView)
        }

        let giftCardStack = UIStackView()
        giftCardStack.axis = .vertical
        giftCardStack.spacing = 2
        contentView.addArrangedSubview(giftCardStack)

        itemView = merchantTypeView(for: NSLocalizedString("Buy gift cards with your Dash", comment: ""),
                                    subtitle: NSLocalizedString("Buy gift cards with your Dash for the exact amount of your purchase.",
                                                                comment: ""),
                                    image: UIImage(named: "image.explore.dash.wts.card.orange"))
        if let itemView {
            giftCardStack.addArrangedSubview(itemView)
        }

        let learnMoreButton = UIButton(type: .custom)
        learnMoreButton.setTitle(NSLocalizedString("Learn More", comment: ""), for: .normal)
        learnMoreButton.setTitleColor(UIColor.dw_dashBlue(), for: .normal)
        learnMoreButton.titleLabel?.font = UIFont.dw_font(forTextStyle: UIFont.TextStyle.footnote)
        learnMoreButton.addTarget(self, action: #selector(learnMoreAction), for: .touchUpInside)
        giftCardStack.addArrangedSubview(learnMoreButton)
        contentView.addArrangedSubview(UIView())

        let continueButton = DWActionButton()
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setTitle(NSLocalizedString("Continue", comment: ""), for: .normal)
        continueButton.addTarget(self, action: #selector(continueButtonAction), for: .touchUpInside)
        view.addSubview(continueButton)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor,
                                             constant: 74),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: continueButton.topAnchor,
                                                constant: 30),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                 constant: 15),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                  constant: -15),
            continueButton.heightAnchor.constraint(equalToConstant: 46),
            continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                   constant: -15),
            continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                                    constant: 15),
            continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                                     constant: -15),
        ])
    }

    func merchantTypeView(for title: String?, subtitle: String?, image: UIImage?) -> UIStackView? {
        let itemStackView = UIStackView()
        itemStackView.axis = .vertical
        itemStackView.spacing = 10
        itemStackView.translatesAutoresizingMaskIntoConstraints = false
        itemStackView.distribution = .equalSpacing

        let iconImageView = UIImageView(image: image)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        itemStackView.addArrangedSubview(iconImageView)

        let labelsStackView = UIStackView()
        labelsStackView.translatesAutoresizingMaskIntoConstraints = false
        labelsStackView.axis = .vertical
        labelsStackView.spacing = 1
        labelsStackView.alignment = .center
        itemStackView.addArrangedSubview(labelsStackView)

        let itemTitleLabel = UILabel()
        itemTitleLabel.text = title
        itemTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        itemTitleLabel.textColor = .dw_label()
        itemTitleLabel.font = UIFont.dw_font(forTextStyle: .body)
        itemTitleLabel.textAlignment = .center
        itemTitleLabel.numberOfLines = 0
        labelsStackView.addArrangedSubview(itemTitleLabel)

        let descLabel = UILabel()
        descLabel.text = subtitle
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.textColor = .dw_secondaryText()
        descLabel.font = UIFont.dw_font(forTextStyle: .footnote)
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        labelsStackView.addArrangedSubview(descLabel)
        return itemStackView
    }
}

