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

final class TransactionItemView: UIView {

    private var imageContainer: UIView!
    private var imageView: UIImageView!

    private var labelContainer: UIStackView!
    private var titleLabel: UILabel!
    private var subtitleLabel: UILabel!

    private var amountLabel: UILabel!
    private var fiatAmountLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    func update(with transaction: DSTransaction, dataProvider: DWTransactionListDataProviderProtocol) {
        let dataItem = dataProvider.transactionData(for: transaction)

        imageContainer.backgroundColor = dataItem.direction.tintColor.withAlphaComponent(0.1)
        imageView.image = dataItem.direction.icon
        imageView.tintColor = dataItem.direction.tintColor

        titleLabel.text = dataItem.directionText
        subtitleLabel.text = dataProvider.shortDateString(for: transaction)
        amountLabel.attributedText = dataItem.dashAmount.formattedDashAmount.attributedAmountStringWithDashSymbol(tintColor: .dw_label())
        fiatAmountLabel.text = dataItem.fiatAmount
    }

    // MARK: Life cycle
    internal func configureHierarchy() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 15
        addSubview(stackView)

        imageContainer = UIView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.layer.cornerRadius = 19
        imageContainer.layer.masksToBounds = true
        stackView.addArrangedSubview(imageContainer)

        imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 11
        imageView.layer.masksToBounds = true
        imageContainer.addSubview(imageView)

        labelContainer = UIStackView()
        labelContainer.translatesAutoresizingMaskIntoConstraints = false
        labelContainer.axis = .vertical
        labelContainer.spacing = 4
        stackView.addArrangedSubview(labelContainer)

        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .dw_font(forTextStyle: .subheadline)
        labelContainer.addArrangedSubview(titleLabel)

        subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .dw_font(forTextStyle: .footnote)
        subtitleLabel.textColor = .dw_secondaryText()
        labelContainer.addArrangedSubview(subtitleLabel)

        let amountContainer = UIStackView()
        amountContainer.translatesAutoresizingMaskIntoConstraints = false
        amountContainer.axis = .vertical
        amountContainer.spacing = 4
        amountContainer.alignment = .trailing
        stackView.addArrangedSubview(amountContainer)

        amountLabel = UILabel()
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = .dw_font(forTextStyle: .subheadline)
        amountContainer.addArrangedSubview(amountLabel)

        fiatAmountLabel = UILabel()
        fiatAmountLabel.translatesAutoresizingMaskIntoConstraints = false
        fiatAmountLabel.font = .dw_font(forTextStyle: .footnote)
        fiatAmountLabel.textColor = .dw_secondaryText()
        amountContainer.addArrangedSubview(fiatAmountLabel)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageContainer.widthAnchor.constraint(equalToConstant: 38),
            imageContainer.heightAnchor.constraint(equalToConstant: 38),

            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22),
            imageView.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageContainer.centerYAnchor),
        ])
    }


}
