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

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    private func configureHierarchy() {
        backgroundColor = .dw_background()
        layer.cornerRadius = 10

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .label
        titleLabel.text = NSLocalizedString("Pay with", comment: "Coinbase/Buy Dash")
        addSubview(titleLabel)

        let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.tintColor = .secondaryLabel
        addSubview(chevronView)

        let paymentMethodStackView = UIStackView()
        paymentMethodStackView.translatesAutoresizingMaskIntoConstraints = false
        paymentMethodStackView.spacing = 2
        paymentMethodStackView.axis = .horizontal
        addSubview(paymentMethodStackView)

        paymentMethodTitleLabel = UILabel()
        paymentMethodTitleLabel.text = "Credit Card *****1111"
        paymentMethodTitleLabel.textColor = .secondaryLabel
        paymentMethodStackView.addArrangedSubview(paymentMethodTitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),

            paymentMethodStackView.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -14),
            paymentMethodStackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
