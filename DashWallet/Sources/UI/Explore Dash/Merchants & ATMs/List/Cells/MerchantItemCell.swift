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

#if DEBUG
import SwiftUI
#endif

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
        
        // Show the highest discount from all providers
        var maxDiscountBasisPoints = 0
        if !merchant.giftCardProviders.isEmpty {
            // If we have provider-specific data, use the max discount
            maxDiscountBasisPoints = merchant.giftCardProviders.map { $0.savingsPercentage }.max() ?? 0
        } else {
            // Fallback to the merchant-level discount (legacy)
            maxDiscountBasisPoints = Int(merchant.toSavingPercentages())
        }

        if maxDiscountBasisPoints > 0 {
            savingsLabel.isHidden = false
            // Convert from basis points to percentage and round to nearest whole number (e.g., 400 -> 4%)
            let discountPercentage = round(Double(maxDiscountBasisPoints) / 100.0)
            savingsLabel.text = String(format: NSLocalizedString("~%.0f%%", comment: "Savings percentage"), discountPercentage)
        } else {
            savingsLabel.isHidden = true
        }
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

// MARK: - Previews

#if DEBUG

private struct MerchantItemCellRepresentable: UIViewRepresentable {
    let pointOfUse: ExplorePointOfUse

    func makeUIView(context: Context) -> UIView {
        let cell = MerchantItemCell(style: .default, reuseIdentifier: nil)
        cell.update(with: pointOfUse)
        return cell.contentView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview("Dash payment — no discount") {
    MerchantItemCellRepresentable(
        pointOfUse: .previewMock(
            name: "Starbucks",
            logoLocation: "https://piggy.cards/image/catalog/piggycards/logo2023_mobile.png",
            paymentMethod: .dash,
            type: .onlineAndPhysical,
            savingsBasisPoints: 0
        )
    )
    .frame(width: 375, height: 60)
    .background(Color(.systemBackground))
    .padding()
}

#Preview("Gift card — 4%") {
    MerchantItemCellRepresentable(
        pointOfUse: .previewMock(
            name: "Amazon",
            logoLocation: "https://piggy.cards/image/catalog/piggycards/logo2023_mobile.png",
            paymentMethod: .giftCard,
            type: .online,
            savingsBasisPoints: 0,
            giftCardProviders: [
                ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                    providerId: "ctx",
                    savingsPercentage: 400,
                    denominationsType: "Fixed",
                    sourceId: nil
                )
            ]
        )
    )
    .frame(width: 375, height: 60)
    .background(Color(.systemBackground))
    .padding()
}

#Preview("Gift card — 10% (multi-provider, max)") {
    MerchantItemCellRepresentable(
        pointOfUse: .previewMock(
            name: "Domino's",
            logoLocation: "https://piggy.cards/image/catalog/piggycards/logo2023_mobile.png",
            paymentMethod: .giftCard,
            type: .online,
            savingsBasisPoints: 0,
            giftCardProviders: [
                ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                    providerId: "ctx",
                    savingsPercentage: 1000,
                    denominationsType: "Fixed",
                    sourceId: nil
                ),
                ExplorePointOfUse.Merchant.GiftCardProviderInfo(
                    providerId: "ctx",
                    savingsPercentage: 500,
                    denominationsType: "Fixed",
                    sourceId: nil
                )
            ]
        )
    )
    .frame(width: 375, height: 60)
    .background(Color(.systemBackground))
    .padding()
}

#endif
