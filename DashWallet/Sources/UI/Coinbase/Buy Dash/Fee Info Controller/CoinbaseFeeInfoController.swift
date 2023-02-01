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

// MARK: - CoinbaseFeeInfoController

final class CoinbaseFeeInfoController: BaseViewController {

    private var scrollView: UIScrollView!
    private var iconView: UIImageView!
    private var titleLabel: UILabel!
    private var descriptionLabel: UILabel!
    private var learnMoreButton: UIButton!

    // MARK: Actions
    @objc
    func closeAction() {
        dismiss(animated: true)
    }

    @objc
    func learnMoreAction() {
        UIApplication.shared.open(kCoinbaseFeeInfoURL)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }
}

// MARK: Life cycle
extension CoinbaseFeeInfoController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_background()

        let action = UIAction { [weak self] _ in
            self?.closeAction()
        }
        let closeItem = UIBarButtonItem(systemItem: .close, primaryAction: action)
        navigationItem.rightBarButtonItem = closeItem

        scrollView = UIScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        iconView = UIImageView(image: UIImage(named: "coinbase.fee.info"))
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(iconView)

        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textAlignment = .center
        titleLabel.font = .dw_font(forTextStyle: .title2).withWeight(500)
        titleLabel.text = "Fees in crypto purchases"
        scrollView.addSubview(titleLabel)

        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = .natural
        descriptionLabel.font = .dw_font(forTextStyle: .body)
        descriptionLabel.text = """
            In addition to the displayed Coinbase fee, we include a spread in the price. When using Advanced Trade, no spread is included because you are interacting directly with the order book.\n
            Cryptocurrency markets are volatile, and this allows us to temporarily lock in a price for trade execution.
            """
        scrollView.addSubview(descriptionLabel)

        learnMoreButton = UIButton(type: .custom)
        learnMoreButton.translatesAutoresizingMaskIntoConstraints = false
        learnMoreButton.addTarget(self, action: #selector(learnMoreAction), for: .touchUpInside)
        learnMoreButton.tintColor = .dw_dashBlue()
        learnMoreButton.setTitleColor(.dw_dashBlue(), for: .normal)
        learnMoreButton.titleLabel?.font = .dw_font(forTextStyle: .subheadline).withWeight(UIFont.Weight.bold.rawValue)
        learnMoreButton.setTitle(NSLocalizedString("Learn More...", comment: "Info Screen"), for: .normal)
        scrollView.addSubview(learnMoreButton)

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

            learnMoreButton.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 15),
            learnMoreButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            learnMoreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -15),
            learnMoreButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
            learnMoreButton.heightAnchor.constraint(equalToConstant: 58),
        ])
    }
}

