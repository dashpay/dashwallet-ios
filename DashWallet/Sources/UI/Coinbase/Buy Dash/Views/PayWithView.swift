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

final class PayWithView: UIView {
    private var paymentMethodTitleLabel: UILabel!
    private var paymentMethodValueLabel: UILabel!
    private var chevronView: UIView!

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    public func update(with paymentMethod: CoinbasePaymentMethod?) {
        guard let paymentMethod else {
            paymentMethodValueLabel.text = NSLocalizedString("No payment methods", comment: "Coinbase/Buy Dash")
            return
        }

        paymentMethodTitleLabel.text = paymentMethod.type.displayString
        paymentMethodValueLabel.text = paymentMethod.name
    }

    public func setChevronButtonHidden(_ isHidden: Bool) {
        chevronView.isHidden = isHidden
    }

    private func configureHierarchy() {
        backgroundColor = .dw_background()
        layer.cornerRadius = 10

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .label
        titleLabel.text = NSLocalizedString("Pay with", comment: "Coinbase/Buy Dash")
        addSubview(titleLabel)

        let trailingStackView = UIStackView()
        trailingStackView.translatesAutoresizingMaskIntoConstraints = false
        trailingStackView.spacing = 10
        trailingStackView.axis = .horizontal
        addSubview(trailingStackView)

        let paymentMethodStackView = UIStackView()
        paymentMethodStackView.translatesAutoresizingMaskIntoConstraints = false
        paymentMethodStackView.spacing = 3
        paymentMethodStackView.axis = .horizontal
        trailingStackView.addArrangedSubview(paymentMethodStackView)

        paymentMethodTitleLabel = UILabel()
        paymentMethodTitleLabel.textColor = .label
        paymentMethodTitleLabel.isHidden = true
        paymentMethodStackView.addArrangedSubview(paymentMethodTitleLabel)

        paymentMethodValueLabel = UILabel()
        paymentMethodValueLabel.textColor = .secondaryLabel
        paymentMethodStackView.addArrangedSubview(paymentMethodValueLabel)

        chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.tintColor = .secondaryLabel
        trailingStackView.addArrangedSubview(chevronView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            trailingStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
