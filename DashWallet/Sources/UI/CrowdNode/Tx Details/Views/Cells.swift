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

// MARK: - CNCreateAccountTxDetailsTxItemCell

final class CNCreateAccountTxDetailsTxItemCell: UITableViewCell {
    private let txItemView: TransactionItemView

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        txItemView = TransactionItemView()

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with transaction: TransactionDataItem) {
        txItemView.update(with: transaction)
    }

    private func configureHierarchy() {
        txItemView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(txItemView)

        contentView.backgroundColor = .dw_background()

        NSLayoutConstraint.activate([
            txItemView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            txItemView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            txItemView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            txItemView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
        ])
    }
}

// MARK: - CNCreateAccountTxDetailsInfoCell

final class CNCreateAccountTxDetailsInfoCell: UITableViewCell {
    private let topLabel: UILabel
    private let infoLabel: UILabel

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        topLabel = UILabel()
        infoLabel = UILabel()

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureHierarchy() {
        contentView.backgroundColor = .dw_background()

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 5
        contentView.addSubview(stackView)

        topLabel.translatesAutoresizingMaskIntoConstraints = false
        topLabel.textColor = .dw_secondaryText()
        topLabel.font = .dw_font(forTextStyle: .subheadline)
        topLabel.text = NSLocalizedString("Why do I see all these transactions?", comment: "Crowdnode")
        stackView.addArrangedSubview(topLabel)

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.textColor = .dw_label()
        infoLabel.font = .dw_font(forTextStyle: .caption1)
        infoLabel.text = NSLocalizedString("Your CrowdNode account was created using these transactions. ", comment: "Crowdnode")
        infoLabel.numberOfLines = 0
        infoLabel.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(infoLabel)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }
}
