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

// MARK: - ConfirmOrderGeneralInfoCell

class ConfirmOrderGeneralInfoCell: UITableViewCell {
    public var infoHandle: (() -> Void)?

    internal var containerView: UIStackView!
    internal var mainContentView: UIView!
    internal var valueLabel: UILabel!
    internal var bottomConstraint: NSLayoutConstraint!

    private var nameLabel: UILabel!
    private var infoButton: UIButton!


    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    // MARK: Actions
    @objc func infoButtonAction() {
        infoHandle?()
    }

    func update(with item: ConfirmOrderItem, value: String) {
        infoButton.isHidden = item.isInfoButtonHidden

        if item == .totalAmount {
            valueLabel.font = valueLabel.font.withWeight(UIFont.Weight.medium.rawValue)
        } else {
            valueLabel.font = .dw_font(forTextStyle: .subheadline)
        }

        nameLabel.text = item.localizedTitle.uppercased()
        valueLabel.text = value
    }

    internal func configureHierarchy() {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)
        containerView = stackView

        mainContentView = UIView()
        mainContentView.translatesAutoresizingMaskIntoConstraints = false
        mainContentView.backgroundColor = .clear
        stackView.addArrangedSubview(mainContentView)

        let subheadlineFont = UIFont.dw_font(forTextStyle: .subheadline)

        nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = subheadlineFont
        nameLabel.textColor = .dw_secondaryText()
        mainContentView.addSubview(nameLabel)

        let configuration = UIImage.SymbolConfiguration(pointSize: subheadlineFont.pointSize, weight: .regular)
        let image = UIImage(systemName: "info.circle", withConfiguration: configuration)

        infoButton = UIButton(type: .custom)
        infoButton.setImage(image, for: .normal)
        infoButton.translatesAutoresizingMaskIntoConstraints = false
        infoButton.addTarget(self, action: #selector(infoButtonAction), for: .touchUpInside)
        mainContentView.addSubview(infoButton)

        valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = subheadlineFont
        valueLabel.textColor = .dw_label()
        mainContentView.addSubview(valueLabel)

        bottomConstraint = stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            bottomConstraint,

            mainContentView.heightAnchor.constraint(equalToConstant: 48),

            nameLabel.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),

            infoButton.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 7),
            infoButton.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),
        ])
    }
}

// MARK: - ConfirmOrderAmountInDashCell

final class ConfirmOrderAmountInDashCell: ConfirmOrderGeneralInfoCell {
    var descriptionLabel: UILabel!

    func update(with item: ConfirmOrderItem, value: String, amountString: String) {
        update(with: item, value: value)
    }

    override func update(with item: ConfirmOrderItem, value: String) {
        super.update(with: item, value: value)

        let descriptionString =
            String(format: NSLocalizedString("You will receive %@ Dash on your Dash Wallet on this device. Please note that it can take up to 2-3 minutes to complete a transfer.",
                                             comment: "Coinbase/Buy Dash/Confirm Order"),
                   value)

        valueLabel.attributedText = value.attributedAmountStringWithDashSymbol(tintColor: .dw_dashBlue())
        descriptionLabel.attributedText = descriptionString.attributedAmountStringWithDashSymbol(tintColor: .dw_label())
    }

    override func configureHierarchy() {
        super.configureHierarchy()

        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .dw_font(forTextStyle: .footnote)
        descriptionLabel.textColor = .dw_secondaryText()
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        containerView.addArrangedSubview(descriptionLabel)

        bottomConstraint.constant = -15
        setNeedsUpdateConstraints()
    }
}
