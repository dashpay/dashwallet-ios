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

public struct MerchantTypesDialog: View {
    @Environment(\.presentationMode) private var presentationMode
    var action: (() -> Void)? = nil

    public var body: some View {
        BottomSheet(showBackButton: .constant(false)) {
            TextIntro(
                icon: .custom("image.merchant"),
                buttonLabel: NSLocalizedString("Ok", comment: ""),
                action: {
                    presentationMode.wrappedValue.dismiss()
                    action?()
                },
                inProgress: .constant(false),
                topText: {
                    FeatureTopText(
                        title: NSLocalizedString("We have two types of merchants", comment: "Explore"),
                        text: NSLocalizedString("The first one accepts Dash directly. The other ones accept gift cards that you can buy with Dash for the exact amount of your purchase in two taps.", comment: "Explore")
                    )
                },
                features: {[
                    FeatureSingleItem(iconName: .custom("image.explore.dash.wts.payment.dash"), title: NSLocalizedString("Accept Dash directly", comment: "Explore"), description: NSLocalizedString("You can pay with Dash at the cashier.", comment: "Explore")),
                    FeatureSingleItem(iconName: .custom("image.explore.dash.wts.card.orange"), title: NSLocalizedString("Buy gift cards with your Dash", comment: "Explore"), description: NSLocalizedString("Buy gift cards with your Dash for the exact amount of your purchase.", comment: "Explore")),
                ]}
            )
        }
    }
}
