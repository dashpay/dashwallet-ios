//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

#if DEBUG
import Foundation

extension ExplorePointOfUse {
    static func previewMockMerchant(
        name: String = "Test Merchant",
        address1: String? = nil,
        city: String? = nil,
        territory: String? = nil,
        latitude: Double? = 33.5092,
        longitude: Double? = -112.0186,
        logoLocation: String? = nil,
        type: Merchant.`Type` = .onlineAndPhysical,
        savingsBasisPoints: Int = 1000
    ) -> ExplorePointOfUse {
        ExplorePointOfUse(
            id: 200,
            name: name,
            category: .merchant(
                Merchant(
                    merchantId: "preview-merchant",
                    paymentMethod: .giftCard,
                    type: type,
                    deeplink: nil,
                    savingsBasisPoints: savingsBasisPoints,
                    denominationsType: "Fixed",
                    denominations: [],
                    redeemType: "online",
                    giftCardProviders: [
                        Merchant.GiftCardProviderInfo(
                            providerId: "ctx",
                            savingsPercentage: savingsBasisPoints,
                            denominationsType: "Fixed",
                            sourceId: nil
                        )
                    ]
                )
            ),
            active: true,
            city: city,
            territory: territory,
            address1: address1,
            address2: nil,
            address3: nil,
            address4: nil,
            latitude: latitude,
            longitude: longitude,
            website: nil,
            phone: nil,
            logoLocation: logoLocation,
            coverImage: nil,
            source: nil
        )
    }
}
#endif
