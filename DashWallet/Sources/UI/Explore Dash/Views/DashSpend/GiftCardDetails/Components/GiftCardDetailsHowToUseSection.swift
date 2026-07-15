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

struct GiftCardDetailsHowToUseSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text(NSLocalizedString("How to use your gift card", comment: "DashSpend"))
                .font(.subhead)
                .fontWeight(.medium)
                .foregroundColor(.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            FeatureSingleItem(
                iconName: .custom("dp_user_generic"),
                title: NSLocalizedString("Self-checkout", comment: "DashSpend"),
                description: NSLocalizedString("Request assistance and show the barcode on your screen for scanning.", comment: "DashSpend")
            )

            FeatureSingleItem(
                iconName: .custom("image.dashspend.shop"),
                title: NSLocalizedString("In store", comment: "DashSpend"),
                description: NSLocalizedString("Tell the cashier that you'd like to pay with a gift card and share the card number and pin.", comment: "DashSpend")
            )

            FeatureSingleItem(
                iconName: .custom("image.dashspend.online"),
                title: NSLocalizedString("Online", comment: "DashSpend"),
                description: NSLocalizedString("In the payment section of your checkout, select \"gift card\" and enter your card number and pin.", comment: "DashSpend")
            )
        }
        .padding(20)
        .background(Color.secondaryBackground)
        .cornerRadius(20)
    }
}

#Preview {
    GiftCardDetailsHowToUseSection()
        .padding()
        .background(Color.primaryBackground)
}
