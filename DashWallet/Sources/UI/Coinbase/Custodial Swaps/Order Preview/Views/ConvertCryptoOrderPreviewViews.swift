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

class ConvertCryptoOrderPreviewSourceCell: UITableViewCell {
    private var topLabel: UILabel!
    private var iconView: UIImageView!
    private var currencyCodeLabel: UILabel!
    private var currencyNameLabel: UILabel!
    private var valueLabel: UILabel!
    private var footnoteLabel: UILabel!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    func update(with item: PreviewOrderItem, account: CBAccount, value: String) {
        topLabel.text = item.localizedTitle
        currencyCodeLabel.text = account.info.currencyCode
        currencyNameLabel.text = account.info.currency.name
        footnoteLabel.text = item.localizedDescription

        if account.isDashAccount {
            valueLabel.attributedText = value.attributedAmountStringWithDashSymbol(tintColor: .dw_label())
        } else {
            valueLabel.text = value
        }

        iconView.isHidden = false
        iconView.sd_setImage(with: account.info.iconURL, placeholderImage: nil) { [weak iconView] image, _,_,_ in
            if image == nil {
                iconView?.isHidden = true
            }
        }
    }

    internal func configureHierarchy() {
        contentView.backgroundColor = .dw_background()

        let subheadlineFont = UIFont.dw_font(forTextStyle: .subheadline)

        let contentStackView = UIStackView()
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.spacing = 12
        contentStackView.alignment = .fill
        contentStackView.axis = .vertical
        contentView.addSubview(contentStackView)

        topLabel = UILabel()
        topLabel.translatesAutoresizingMaskIntoConstraints = false
        topLabel.font = subheadlineFont
        topLabel.textColor = .dw_secondaryText()
        contentStackView.addArrangedSubview(topLabel)

        let middleSectionView = UIStackView()
        middleSectionView.translatesAutoresizingMaskIntoConstraints = false
        middleSectionView.backgroundColor = .clear
        middleSectionView.axis = .horizontal
        middleSectionView.alignment = .center
        middleSectionView.distribution = .fill
        middleSectionView.spacing = 10
        contentStackView.addArrangedSubview(middleSectionView)

        iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 17
        iconView.backgroundColor = .dw_secondaryBackground()
        middleSectionView.addArrangedSubview(iconView)

        let labelStackView = UIStackView()
        labelStackView.translatesAutoresizingMaskIntoConstraints = false
        labelStackView.spacing = 2
        labelStackView.axis = .vertical
        middleSectionView.addArrangedSubview(labelStackView)

        currencyCodeLabel = UILabel()
        currencyCodeLabel.translatesAutoresizingMaskIntoConstraints = false
        currencyCodeLabel.font = .dw_font(forTextStyle: .body).withWeight(UIFont.Weight.medium.rawValue)
        currencyCodeLabel.textColor = .dw_label()
        labelStackView.addArrangedSubview(currencyCodeLabel)

        currencyNameLabel = UILabel()
        currencyNameLabel.translatesAutoresizingMaskIntoConstraints = false
        currencyNameLabel.font = .dw_font(forTextStyle: .footnote)
        currencyNameLabel.textColor = .dw_secondaryText()
        labelStackView.addArrangedSubview(currencyNameLabel)

        valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = subheadlineFont
        valueLabel.textColor = .dw_label()
        valueLabel.textAlignment = .right
        middleSectionView.addArrangedSubview(valueLabel)

        footnoteLabel = UILabel()
        footnoteLabel.translatesAutoresizingMaskIntoConstraints = false
        footnoteLabel.font = .dw_font(forTextStyle: .footnote)
        footnoteLabel.textColor = .dw_secondaryText()
        contentStackView.addArrangedSubview(footnoteLabel)

        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            contentStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),
        ])
    }
}
