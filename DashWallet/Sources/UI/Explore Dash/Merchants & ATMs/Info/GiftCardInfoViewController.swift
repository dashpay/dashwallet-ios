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

class GiftCardInfoViewController: PointOfUseInfoViewController {
    override func configureHierarchy() {
        super.configureHierarchy()

        let contentView = UIStackView()
        contentView.axis = .vertical
        contentView.spacing = 30
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        let topStackView = UIStackView()
        topStackView.axis = .vertical
        topStackView.spacing = 10
        topStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addArrangedSubview(topStackView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .label
        titleLabel.font = .dw_font(forTextStyle: .title1)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = NSLocalizedString("How to Use a Gift Card", comment: "")
        topStackView.addArrangedSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.textColor = .label
        descLabel.font = UIFont.dw_font(forTextStyle: .callout)
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel
            .text = NSLocalizedString("Not all of the stores accept DASH directly, but you can buy a gift card with your Dash.",
                                      comment: "")
        topStackView.addArrangedSubview(descLabel)

        let titles = [
            NSLocalizedString("Find a merchant.", comment: ""),
            NSLocalizedString("Buy a gift card with Dash.", comment: ""),
            NSLocalizedString("Redeem your gift card online within seconds or at the cashier.", comment: ""),
        ]
        let icons = [
            "image.explore.dash.wts.map",
            "image.explore.dash.wts.card.blue",
            "image.explore.dash.wts.lighting",
        ]
        let itemCount: size_t = 3

        for i in 0..<itemCount {
            let title = titles[i]
            let icon = UIImage(named: icons[i])!
            let item = itemView(for: title, image: icon)
            contentView.addArrangedSubview(item)
        }

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor, constant: 74),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

        ])
    }

    func itemView(for title: String, image: UIImage) -> UIStackView {
        let itemStackView = UIStackView()
        itemStackView.axis = .horizontal
        itemStackView.spacing = 10
        itemStackView.translatesAutoresizingMaskIntoConstraints = false
        itemStackView.alignment = .firstBaseline

        let iconImageView = UIImageView(image: image)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .center
        itemStackView.addArrangedSubview(iconImageView)


        let itemTitleLabel = UILabel()
        itemTitleLabel.text = title
        itemTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        itemTitleLabel.textColor = .label
        itemTitleLabel.font = UIFont.dw_font(forTextStyle: .body)
        itemTitleLabel.textAlignment = .left
        itemTitleLabel.numberOfLines = 0;
        itemStackView.addArrangedSubview(itemTitleLabel)

        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 50),
            iconImageView.centerYAnchor.constraint(equalTo: itemTitleLabel.topAnchor, constant: 10),
        ])

        return itemStackView
    }
}
