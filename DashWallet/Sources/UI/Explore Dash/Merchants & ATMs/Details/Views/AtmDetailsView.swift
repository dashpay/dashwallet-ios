//
//  Created by Pavel Tikhonenko
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

import MapKit
import UIKit

class AtmDetailsView: PointOfUseDetailsView {
    override func configureHeaderView() {
        super.configureHeaderView()

        let buttonsStackView = UIStackView()
        buttonsStackView.spacing = 5
        buttonsStackView.axis = .horizontal
        buttonsStackView.distribution = .fillEqually
        headerContainerView.addArrangedSubview(buttonsStackView)

        let payButton = DWActionButton()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        payButton.addTarget(self, action: #selector(payAction), for: .touchUpInside)
        payButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
        payButton.setTitle(NSLocalizedString("Buy Dash", comment: "Buy Dash"), for: .normal)
        payButton.accentColor = UIColor(red: 0.235, green: 0.722, blue: 0.471, alpha: 1)
        buttonsStackView.addArrangedSubview(payButton)

        if let atm = merchant.atm, atm.type == .buySell || atm.type == .sell {
            let sellButton = DWActionButton()
            sellButton.translatesAutoresizingMaskIntoConstraints = false
            sellButton.addTarget(self, action: #selector(sellAction), for: .touchUpInside)
            sellButton.imageEdgeInsets = .init(top: 0, left: -10, bottom: 0, right: 0)
            sellButton.setTitle(NSLocalizedString("Sell Dash", comment: "Buy Dash"), for: .normal)
            sellButton.accentColor = .dw_dashBlue()
            buttonsStackView.addArrangedSubview(sellButton)
        }

        // TODO: Change to hairline view
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .black.withAlphaComponent(0.3)
        containerView.addArrangedSubview(separator)

        let buttonHeight: CGFloat = 48

        NSLayoutConstraint.activate([
            payButton.heightAnchor.constraint(equalToConstant: buttonHeight),
            separator.heightAnchor.constraint(equalToConstant: 1/UIScreen.main.scale),
        ])
    }

    override func configureLocationBlock() {
        let stackView = UIStackView()
        stackView.spacing = 15
        stackView.alignment = .top
        stackView.axis = .horizontal
        containerView.addArrangedSubview(stackView)

        coverImageView = UIImageView()
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.layer.cornerRadius = 8
        coverImageView.layer.masksToBounds = true
        stackView.addArrangedSubview(coverImageView)

        if let str = merchant.coverImage, let url = URL(string: str) {
            coverImageView.sd_setImage(with: url, completed: nil)
        } else {
            coverImageView.isHidden = true
        }

        let locationInfoStackView = UIStackView()
        locationInfoStackView.spacing = 5
        locationInfoStackView.axis = .vertical

        stackView.addArrangedSubview(locationInfoStackView)

        let subStackView = UIStackView()
        subStackView.spacing = 2
        subStackView.axis = .vertical
        locationInfoStackView.addArrangedSubview(subStackView)

        let subLabel = UILabel()
        subLabel.font = .dw_font(forTextStyle: .footnote)
        subLabel.textColor = .dw_secondaryText()
        subLabel.text = NSLocalizedString("This ATM is located in the", comment: "This ATM is located in the")
        subStackView.addArrangedSubview(subLabel)

        let nameLabel = UILabel()
        nameLabel.text = merchant.name;
        nameLabel.font = .dw_font(forTextStyle: .headline)
        subStackView.addArrangedSubview(nameLabel)

        addressLabel = UILabel()
        addressLabel.font = .dw_font(forTextStyle: .body)
        addressLabel.textColor = .dw_label()
        addressLabel.numberOfLines = 0
        addressLabel.lineBreakMode = .byWordWrapping
        addressLabel.text = merchant.address1
        locationInfoStackView.addArrangedSubview(addressLabel)

        if let currentLocation = DWLocationManager.shared.currentLocation, DWLocationManager.shared.isAuthorized {
            let distanceStackView = UIStackView()
            distanceStackView.spacing = 5
            distanceStackView.axis = .horizontal
            locationInfoStackView.addArrangedSubview(distanceStackView)

            let iconImageView = UIImageView(image: .init(named: "image.explore.dash.distance"))
            distanceStackView.addArrangedSubview(iconImageView)

            let distance = CLLocation(latitude: merchant.latitude!, longitude: merchant.longitude!)
                .distance(from: currentLocation)
            let subLabel = UILabel()
            subLabel.font = .dw_font(forTextStyle: .footnote)
            subLabel.textColor = .dw_secondaryText()
            subLabel.text = NSLocalizedString("This ATM is located in the", comment: "This ATM is located in the")
            distanceStackView.addArrangedSubview(subLabel)
            subLabel
                .text =
                "\(ExploreDash.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters)))"

            distanceStackView.addArrangedSubview(UIView())
        }

        NSLayoutConstraint.activate([
            coverImageView.widthAnchor.constraint(equalToConstant: 88),
            coverImageView.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    override func configureBottomButton() {
        // NOTE: do nothing here
    }
}
