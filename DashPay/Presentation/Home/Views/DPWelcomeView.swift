//
//  Created by Andrew Podkovyrin
//  Copyright © 2020 Dash Core Group. All rights reserved.
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

@objc
class DPWelcomeView: DWBasePressableControl {
    private let titleLabel: UILabel
    private let subtitleLabel: UILabel
    private let arrowImageView: UIImageView
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(frame: CGRect) {
        self.titleLabel = UILabel()
        self.subtitleLabel = UILabel()
        self.arrowImageView = UIImageView(image: UIImage(named: "pay_user_accessory"))

        super.init(frame: frame)

        backgroundColor = UIColor.clear
        layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        let shadowView = ShadowView(frame: .zero)
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.insetsLayoutMarginsFromSafeArea = true
        shadowView.isUserInteractionEnabled = false
        addSubview(shadowView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_background()
        contentView.layer.cornerRadius = 8.0
        contentView.layer.masksToBounds = true
        contentView.isUserInteractionEnabled = false
        shadowView.addSubview(contentView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .dw_darkTitle()
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = .dw_font(forTextStyle: .subheadline)
        titleLabel.text = NSLocalizedString("Join DashPay", comment: "")
        titleLabel.isUserInteractionEnabled = false
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textColor = UIColor.dw_tertiaryText()
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = .dw_font(forTextStyle: .footnote)
        subtitleLabel.text = NSLocalizedString("Create a username, add your friends.", comment: "")
        subtitleLabel.isUserInteractionEnabled = false
        contentView.addSubview(subtitleLabel)

        arrowImageView.translatesAutoresizingMaskIntoConstraints = false
        arrowImageView.isUserInteractionEnabled = false
        contentView.addSubview(arrowImageView)

        titleLabel.setContentCompressionResistancePriority(.required - 1, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.required - 2, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required - 1, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required - 2, for: .vertical)

        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            shadowView.topAnchor.constraint(equalTo: topAnchor),
            layoutMarginsGuide.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            contentView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            shadowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shadowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2.0),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            contentView.bottomAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),

            arrowImageView.leadingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor, constant: 12),
            arrowImageView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            arrowImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.trailingAnchor.constraint(equalTo: arrowImageView.trailingAnchor, constant: 12),

            arrowImageView.widthAnchor.constraint(equalToConstant: 32.0),
            arrowImageView.heightAnchor.constraint(equalToConstant: 32.0),
        ])
    }
}
