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

    override func update(with pointOfUse: ExplorePointOfUse) {
        super.update(with: pointOfUse)

        guard let merchant = pointOfUse.merchant else { return }

        if merchant.type == .online {
            subLabel.isHidden = true
        } else {
            // Use search center coordinate if available (when map is panned), otherwise use GPS
            let locationForDistance: CLLocation?
            if let searchCenter = searchCenterCoordinate {
                locationForDistance = CLLocation(latitude: searchCenter.latitude, longitude: searchCenter.longitude)
            } else if DWLocationManager.shared.isAuthorized {
                locationForDistance = DWLocationManager.shared.currentLocation
            } else {
                locationForDistance = nil
            }

            if let currentLocation = locationForDistance {
                subLabel.isHidden = false
                let distance = CLLocation(latitude: pointOfUse.latitude!, longitude: pointOfUse.longitude!)
                    .distance(from: currentLocation)
                let distanceText: String = ExploreDash.distanceFormatter
                    .string(from: Measurement(value: floor(distance), unit: UnitLength.meters))
                subLabel.text = distanceText
            } else {
                subLabel.isHidden = true
            }
        }

        let isGiftCard = merchant.paymentMethod == .giftCard
        let paymentIconName = isGiftCard ? "image.explore.dash.wts.payment.gift-card" : "image.explore.dash.wts.payment.dash";
        paymentTypeIconView.image = UIImage(named: paymentIconName)
        
        // Calculate the effective discount, filtering out PiggyCards when disabled
        let effectiveDiscount = calculateEffectiveDiscount(for: merchant)

        if effectiveDiscount > 0 {
            savingsLabel.isHidden = false
            savingsLabel.text = String(format: NSLocalizedString("~%.0f%%", comment: "Savings percentage"), effectiveDiscount)
        } else {
            savingsLabel.isHidden = true
        }
    }

    private func calculateEffectiveDiscount(for merchant: ExplorePointOfUse.Merchant) -> Double {
        // If not a gift card merchant, return the original discount
        guard merchant.paymentMethod == .giftCard else {
            return merchant.toSavingPercentages()
        }

        // When PiggyCards is disabled, calculate discount from CTX only
        #if !PIGGYCARDS_ENABLED
        // Find CTX provider and use its discount (converting from basis points to percentage)
        if let ctxProvider = merchant.giftCardProviders.first(where: { $0.provider == .ctx }) {
            // savingsPercentage is in basis points (600 = 6%), so divide by 100
            return Double(ctxProvider.savingsPercentage) / 100.0
        }
        // If no CTX provider found, return 0
        return 0
        #else
        // When PiggyCards is enabled, return the combined discount as before
        return merchant.toSavingPercentages()
        #endif
    }
}

extension MerchantItemCell {
    override func configureHierarchy() {
        super.configureHierarchy()

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
