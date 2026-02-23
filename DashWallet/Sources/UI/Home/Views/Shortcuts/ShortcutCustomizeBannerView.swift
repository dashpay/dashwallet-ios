//
//  Created by Claude
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

final class ShortcutCustomizeBannerView: UIView {
    var onDismiss: (() -> Void)?

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.image = UIImage(named: "shortcut_customize_banner")
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .dw_mediumFont(ofSize: 13)
        label.textColor = .dw_darkTitle()
        label.text = NSLocalizedString("Customize shortcut bar", comment: "Shortcut banner")
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .dw_regularFont(ofSize: 13)
        label.textColor = .dw_secondaryText()
        label.text = NSLocalizedString("Hold any button above to replace it with the function you need", comment: "Shortcut banner")
        label.numberOfLines = 0
        return label
    }()

    private let dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.tintColor = .dw_secondaryText()
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        // Card container
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .dw_background()
        card.layer.cornerRadius = 20
        card.layer.shadowColor = UIColor(red: 0.72, green: 0.76, blue: 0.80, alpha: 1.0).cgColor
        card.layer.shadowOpacity = 0.1
        card.layer.shadowOffset = CGSize(width: 0, height: 5)
        card.layer.shadowRadius = 10
        addSubview(card)

        // Icon container for centering
        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconContainer)

        iconContainer.addSubview(iconImageView)

        // Text stack
        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 1
        card.addSubview(textStack)

        // Dismiss button container for larger touch target
        card.addSubview(dismissButton)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            // Card pinned with 20px horizontal margins, 0 top margin (stack view handles spacing)
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Icon container
            iconContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            iconContainer.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 26),
            iconContainer.heightAnchor.constraint(equalToConstant: 26),

            // Icon centered in container
            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            // Text stack
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 16),
            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
            textStack.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -12),

            // Dismiss button
            dismissButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            dismissButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 24),
            dismissButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
