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
import DashUIKit

public struct MerchantTypesDialog: View {
    @Environment(\.presentationMode) private var presentationMode
    var action: (() -> Void)? = nil
    
    public var body: some View {
        DashUIKit.BottomSheet(showBackButton: .constant(false)) {
            TextIntro(
                icon: .custom("image.merchant"),
                buttonLabel: String(localized: "Ok", comment: ""),
                action: {
                    presentationMode.wrappedValue.dismiss()
                    action?()
                },
                inProgress: .constant(false),
                topText: {
                    FeatureTopText(
                        title: String(localized: "We have two types of merchants", comment: "Explore"),
                        text: String(localized: "The first one accepts Dash directly. The other ones accept gift cards that you can buy with Dash for the exact amount of your purchase in two taps.", comment: "Explore")
                    )
                },
                features: {[
                    FeatureSingleItem(iconName: .custom("image.explore.dash.wts.payment.dash"), title: String(localized: "Accept Dash directly", comment: "Explore"), description: String(localized: "You can pay with Dash at the cashier.", comment: "Explore")),
                    FeatureSingleItem(iconName: .custom("image.explore.dash.wts.card.orange"), title: String(localized: "Buy gift cards with your Dash", comment: "Explore"), description: String(localized: "Buy gift cards with your Dash for the exact amount of your purchase.", comment: "Explore")),
                ]}
            )
        }
    }
}
