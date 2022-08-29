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

import UIKit
import CoreLocation

class MerchantItemCell: ExplorePointOfUseItemCell {
    private var paymentTypeIconView: UIImageView!
    
    override func update(with pointOfUse: ExplorePointOfUse) {
        super.update(with: pointOfUse)
        
        guard let merchant = pointOfUse.merchant else { return }
        
        if let currentLocation = DWLocationManager.shared.currentLocation,
           DWLocationManager.shared.isAuthorized, merchant.type != .online {
            subLabel.isHidden = false
            let distance = CLLocation(latitude: pointOfUse.latitude!, longitude: pointOfUse.longitude!).distance(from: currentLocation)
            let distanceText: String = App.distanceFormatter.string(from: Measurement(value: floor(distance), unit: UnitLength.meters))
            subLabel.text = distanceText
        }else{
            subLabel.isHidden = true
        }

        let isGiftCard = merchant.paymentMethod == .giftCard
        let paymentIconName = isGiftCard ? "image.explore.dash.wts.payment.gift-card" : "image.explore.dash.wts.payment.dash";
        paymentTypeIconView.image = UIImage(named: paymentIconName)
    }
}

extension MerchantItemCell {
    override func configureHierarchy() {
        super.configureHierarchy()
        
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
