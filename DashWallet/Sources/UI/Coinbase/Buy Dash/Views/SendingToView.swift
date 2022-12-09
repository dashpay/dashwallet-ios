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

final class SendingToView: UIView {

    override var intrinsicContentSize: CGSize {
        CGSize(width: SendingToView.noIntrinsicMetric, height: 56)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureHierarchy()
    }

    private func configureHierarchy() {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        addSubview(stackView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .dw_font(forTextStyle: .footnote)
        titleLabel.text = NSLocalizedString("Sending to", comment: "Buy Dash")
        stackView.addArrangedSubview(titleLabel)

        let destinationStackView = UIStackView()
        destinationStackView.translatesAutoresizingMaskIntoConstraints = false
        destinationStackView.axis = .horizontal
        destinationStackView.spacing = 6
        stackView.addArrangedSubview(destinationStackView)

        let dashIcon = UIImageView(image: UIImage(named: "dashCircleFilled"))
        destinationStackView.addArrangedSubview(dashIcon)

        let destinationLabel = UILabel()
        destinationLabel.translatesAutoresizingMaskIntoConstraints = false
        destinationLabel.textColor = .label
        destinationLabel.font = .dw_font(forTextStyle: .footnote)
        destinationLabel.text = NSLocalizedString("Dash Wallet on this device", comment: "Buy Dash")
        destinationStackView.addArrangedSubview(destinationLabel)

        let hairline = HairlineView(frame: .zero)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -15),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            dashIcon.widthAnchor.constraint(equalToConstant: 18),
            dashIcon.heightAnchor.constraint(equalToConstant: 18),
        ])
    }
}
