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
    var nameLabel: UILabel!
    var valueLabel: UILabel!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    func update(with item: ConfirmOrderItem, value: String) {
        nameLabel.text = item.localizedTitle.uppercased()
        valueLabel.text = value

        if item == .totalAmount {
            valueLabel.font = valueLabel.font.withWeight(UIFont.Weight.medium.rawValue)
        } else {
            valueLabel.font = .dw_font(forTextStyle: .subheadline)
        }
    }

    internal func configureHierarchy() {
        nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .dw_font(forTextStyle: .subheadline)
        nameLabel.textColor = .dw_secondaryText()
        contentView.addSubview(nameLabel)

        valueLabel = UILabel()
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .dw_font(forTextStyle: .subheadline)
        valueLabel.textColor = .dw_label()
        contentView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
}

// MARK: - ConfirmOrderAmountInDashCell

final class ConfirmOrderAmountInDashCell: ConfirmOrderGeneralInfoCell {
    var desciptionLabel: UILabel!

    override func update(with item: ConfirmOrderItem, value: String) {
        super.update(with: item, value: value)

        valueLabel.attributedText = value.attributedAmountStringWithDashSymbol(tintColor: .dw_dashBlue())
    }
}
