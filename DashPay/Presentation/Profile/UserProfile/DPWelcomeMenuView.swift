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

@objc(DWDPWelcomeMenuView)
class DPWelcomeMenuView: UIView {
    private static let ButtonHeight: CGFloat = 39.0
    @objc
    var joinButton: ActionButton!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        backgroundColor = UIColor.clear

        let shadowView = ShadowView(frame: .zero)
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.insetsLayoutMarginsFromSafeArea = true
        addSubview(shadowView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .dw_background()
        contentView.layer.cornerRadius = 8.0
        contentView.layer.masksToBounds = true
        shadowView.addSubview(contentView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .dw_darkTitle()
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = .dw_font(forTextStyle: .subheadline)
        titleLabel.text = NSLocalizedString("Join DashPay", comment: "")
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textColor = .dw_tertiaryText()
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = .dw_font(forTextStyle: .footnote)
        subtitleLabel.text = NSLocalizedString("Create a username, add your friends.", comment: "")
        subtitleLabel.textAlignment = .center
        contentView.addSubview(subtitleLabel)

        let joinButton = ActionButton()
        joinButton.translatesAutoresizingMaskIntoConstraints = false
        joinButton.setTitle(NSLocalizedString("Join", comment: ""), for: .normal)
        contentView.addSubview(joinButton)
        self.joinButton = joinButton

        titleLabel.setContentCompressionResistancePriority(.required - 1, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required - 2, for: .vertical)

        let padding: CGFloat = 16.0
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 16
        
        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            shadowView.topAnchor.constraint(equalTo: topAnchor),
            trailingAnchor.constraint(equalTo: shadowView.trailingAnchor, constant: padding),
            bottomAnchor.constraint(equalTo: shadowView.bottomAnchor, constant: 8.0),

            contentView.leadingAnchor.constraint(equalTo: shadowView.leadingAnchor),
            contentView.topAnchor.constraint(equalTo: shadowView.topAnchor),
            shadowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shadowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 25.0),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            contentView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: horizontalPadding),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2.0),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalPadding),
            contentView.trailingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor, constant: horizontalPadding),

            joinButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 22.0),
            joinButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            contentView.bottomAnchor.constraint(equalTo: joinButton.bottomAnchor, constant: 12.0),

            joinButton.heightAnchor.constraint(equalToConstant: DPWelcomeMenuView.ButtonHeight),
        ])
    }
}

