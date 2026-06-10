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

import SwiftUI

struct GiftCardDetailsMerchantHeader: View {
    let merchantIcon: UIImage?
    let merchantName: String
    let purchaseDateText: String?

    var body: some View {
        HStack(spacing: 15) {
            ZStack(alignment: .bottomTrailing) {
                if let icon = merchantIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .transition(.opacity)
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    Image("image.explore.dash.wts.payment.gift-card")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                }

                if merchantIcon != nil {
                    Image("image.explore.dash.wts.payment.gift-card")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .frame(width: 23, height: 23)
                        .background(Circle().fill(Color.secondaryBackground))
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(merchantName)
                    .font(.subhead)
                    .fontWeight(.medium)
                    .foregroundColor(.primaryText)

                if let purchaseDateText = purchaseDateText {
                    Text(purchaseDateText)
                        .font(.footnote)
                        .foregroundColor(.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("With Icon") {
    GiftCardDetailsMerchantHeader(
        merchantIcon: UIImage(systemName: "cart.fill"),
        merchantName: "Amazon",
        purchaseDateText: "May 04, 2026 at 5:35 PM"
    )
    .padding()
    .background(Color.primaryBackground)
}

#Preview("No Icon") {
    GiftCardDetailsMerchantHeader(
        merchantIcon: nil,
        merchantName: "Target",
        purchaseDateText: "May 04, 2026 at 3:10 PM"
    )
    .padding()
    .background(Color.primaryBackground)
}
