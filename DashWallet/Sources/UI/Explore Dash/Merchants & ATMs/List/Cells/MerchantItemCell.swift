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

import CoreLocation
import UIKit

// MARK: - MerchantItemCell

class MerchantItemCell: PointOfUseItemCell {
    private var paymentTypeIconView: UIImageView!
    private var savingsLabel: UILabel!
    private var distanceLabel: UILabel!

    override func update(with pointOfUse: ExplorePointOfUse) {
        super.update(with: pointOfUse)

        guard let merchant = pointOfUse.merchant else { return }

        // Display distance under merchant name on search screen as per original implementation
        if let currentLocation = DWLocationManager.shared.currentLocation,
           DWLocationManager.shared.isAuthorized, merchant.type != .online {
            subLabel.isHidden = false
            let distance = CLLocation(latitude: pointOfUse.latitude!, longitude: pointOfUse.longitude!)
                .distance(from: currentLocation)
            let distanceText: String = ExploreDash.distanceFormatter
                .string(from: Measurement(value: floor(distance), unit: UnitLength.meters))
            subLabel.text = distanceText
        } else {
            subLabel.isHidden = true
        }
        
        // Hide separate distance label since we're using subLabel
        distanceLabel.isHidden = true

        let isGiftCard = merchant.paymentMethod == .giftCard
        let paymentIconName = isGiftCard ? "image.explore.dash.wts.payment.gift-card" : "image.explore.dash.wts.payment.dash";
        paymentTypeIconView.image = UIImage(named: paymentIconName)
        
        if merchant.savingsBasisPoints > 0 {
            savingsLabel.isHidden = false
            savingsLabel.text = String(format: NSLocalizedString("~%.0f%%", comment: "Savings percentage"), merchant.toSavingPercentages())
        } else {
            savingsLabel.isHidden = true
        }
    }
}

extension MerchantItemCell {
    override func configureHierarchy() {
        super.configureHierarchy()

        // Distance label (separate from merchant name)
        distanceLabel = UILabel()
        distanceLabel.translatesAutoresizingMaskIntoConstraints = false
        distanceLabel.font = .systemFont(ofSize: 12, weight: .regular)
        distanceLabel.textColor = .dw_tertiaryText()
        distanceLabel.isHidden = true
        distanceLabel.textAlignment = .right
        mainStackView.addArrangedSubview(distanceLabel)

        savingsLabel = UILabel()
        savingsLabel.translatesAutoresizingMaskIntoConstraints = false
        savingsLabel.font = .systemFont(ofSize: 14, weight: .medium)
        savingsLabel.textColor = .dw_secondaryText()
        savingsLabel.isHidden = true
        savingsLabel.textAlignment = .right
        mainStackView.addArrangedSubview(savingsLabel)

        paymentTypeIconView = UIImageView(image: UIImage(named: "image.explore.dash.wts.payment.dash"))
        paymentTypeIconView.translatesAutoresizingMaskIntoConstraints = false
        paymentTypeIconView.contentMode = .center
        mainStackView.addArrangedSubview(paymentTypeIconView)

        NSLayoutConstraint.activate([
            paymentTypeIconView.widthAnchor.constraint(equalToConstant: 24),
            paymentTypeIconView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }
}
