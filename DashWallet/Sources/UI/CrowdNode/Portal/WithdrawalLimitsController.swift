//
//  Created by Andrei Ashikhmin
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

// MARK: - WithdrawalLimitDialogModel

struct WithdrawalLimitDialogModel {
    let icon: String
    let buttonText: String?
    let limits: [Int]
    let highlightedLimit: Int
}

// MARK: - WithdrawalLimitsController

final class WithdrawalLimitsController: BaseViewController {

    private let limitLabels: [String] = [
        NSLocalizedString("per transaction", comment: "CrowdNode"),
        NSLocalizedString("per hour", comment: "CrowdNode"),
        NSLocalizedString("per 24 hours", comment: "CrowdNode"),
    ]

    var actionHandler: (() -> ())?
    var model: WithdrawalLimitDialogModel? = nil


    // MARK: Actions
    @objc
    func closeAction() {
        dismiss(animated: true)
    }

    @objc
    func actionButtonAction() {
        actionHandler?()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }
}

// MARK: Life cycle
extension WithdrawalLimitsController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        let action = UIAction { [weak self] _ in
            self?.closeAction()
        }
        let closeItem = UIBarButtonItem(systemItem: .close, primaryAction: action)
        navigationItem.rightBarButtonItem = closeItem

        let scrollView = UIScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        let iconView = UIImageView(image: UIImage(named: model?.icon ?? "image.crowdnode.info"))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textAlignment = .center
        titleLabel.font = .dw_font(forTextStyle: .title2).withWeight(500)
        titleLabel.text = NSLocalizedString("CrowdNode withdrawal limits", comment: "CrowdNode")
        scrollView.addSubview(titleLabel)

        let descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = .center
        descriptionLabel.font = .dw_font(forTextStyle: .body)
        descriptionLabel.textColor = .dw_secondaryText()
        descriptionLabel.text = NSLocalizedString("Due to CrowdNode’s terms of service users can withdraw no more than:", comment: "CrowdNode")
        scrollView.addSubview(descriptionLabel)

        let limitsStackView = UIStackView()
        limitsStackView.translatesAutoresizingMaskIntoConstraints = false
        limitsStackView.axis = .horizontal
        limitsStackView.distribution = .fillEqually
        scrollView.addSubview(limitsStackView)

        let limitLabelsStackView = UIStackView()
        limitLabelsStackView.translatesAutoresizingMaskIntoConstraints = false
        limitLabelsStackView.axis = .horizontal
        limitLabelsStackView.distribution = .fillEqually
        scrollView.addSubview(limitLabelsStackView)

        model?.limits.enumerated().forEach {
            let isHighlighted = $0.offset == model?.highlightedLimit
            let limit = createLimitText(limit: $0.element, isHighlighted: isHighlighted)
            limitsStackView.addArrangedSubview(limit)
            let limitLabel = createLimitLabel(label: limitLabels[$0.offset], isHighlighted: isHighlighted)
            limitLabelsStackView.addArrangedSubview(limitLabel)
        }

        let frameGuide = scrollView.frameLayoutGuide
        let contentGuide = scrollView.contentLayoutGuide

        NSLayoutConstraint.activate([
            frameGuide.topAnchor.constraint(equalTo: view.topAnchor),
            frameGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            frameGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            frameGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentGuide.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentGuide.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentGuide.widthAnchor.constraint(equalTo: frameGuide.widthAnchor),
            contentView.widthAnchor.constraint(equalTo: view.widthAnchor),

            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 100),
            iconView.heightAnchor.constraint(equalToConstant: 100),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),

            limitsStackView.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 25),
            limitsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            limitsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),

            limitLabelsStackView.topAnchor.constraint(equalTo: limitsStackView.bottomAnchor, constant: 0),
            limitLabelsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            limitLabelsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
        ])

        if let text = model?.buttonText {
            let onlineAccountHint = UILabel()
            onlineAccountHint.translatesAutoresizingMaskIntoConstraints = false
            onlineAccountHint.numberOfLines = 0
            onlineAccountHint.lineBreakMode = .byWordWrapping
            onlineAccountHint.textAlignment = .center
            onlineAccountHint.font = .dw_font(forTextStyle: .body)
            onlineAccountHint.textColor = .dw_secondaryText()
            onlineAccountHint.text = NSLocalizedString("Withdraw without limits with an online account on CrowdNode website.", comment: "CrowdNode")
            scrollView.addSubview(onlineAccountHint)

            let actionButton = UIButton(type: .custom)
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            actionButton.addTarget(self, action: #selector(actionButtonAction), for: .touchUpInside)
            actionButton.tintColor = .dw_dashBlue()
            actionButton.setTitleColor(.dw_dashBlue(), for: .normal)
            actionButton.titleLabel?.font = .dw_font(forTextStyle: .subheadline).withWeight(UIFont.Weight.bold.rawValue)
            actionButton.setTitle(text, for: .normal)
            scrollView.addSubview(actionButton)

            NSLayoutConstraint.activate([
                onlineAccountHint.topAnchor.constraint(equalTo: limitLabelsStackView.bottomAnchor, constant: 30),
                onlineAccountHint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
                onlineAccountHint.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),

                actionButton.topAnchor.constraint(equalTo: onlineAccountHint.bottomAnchor, constant: 15),
                actionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
                actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
                actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
                actionButton.heightAnchor.constraint(equalToConstant: 58),
            ])
        }
    }

    private func createLimitText(limit: Int, isHighlighted: Bool) -> UILabel {
        let amount = UILabel()
        let attachment = NSTextAttachment();
        attachment.image = UIImage(named: "icon_dash_currency")
        attachment.bounds = CGRect(x: 5, y: 1, width: 20, height: 16)
        let attachmentString = NSAttributedString(attachment: attachment)
        let limitString = NSMutableAttributedString(string: String(limit))
        limitString.append(attachmentString)
        amount.font = .dw_mediumFont(ofSize: 26)
        amount.textAlignment = .center
        amount.attributedText = limitString

        if isHighlighted {
            amount.textColor = .systemRed
        }

        return amount
    }

    private func createLimitLabel(label: String, isHighlighted: Bool) -> UILabel {
        let limitLabel = UILabel()
        limitLabel.font = .dw_regularFont(ofSize: 14)
        limitLabel.textColor = .dw_secondaryText()
        limitLabel.text = label
        limitLabel.textAlignment = .center
        if isHighlighted {
            limitLabel.textColor = .systemRed
        }

        return limitLabel
    }
}

