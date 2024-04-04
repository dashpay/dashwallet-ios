//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

struct FeatureTopText: View {
    var title: String
    var text: String
    var label: String? = nil
    var labelIcon: IconName? = nil
    var linkAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Font.system(size: 24).weight(.bold))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundColor(.primaryText)
          
            Text(text)
                .font(Font.system(size: 14))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundColor(.secondaryText)
            
            // TODO: features
            
            if let label = label {
                Button(action: {
                    linkAction?()
                }) {
                    HStack(spacing: 6) {
                        Text(label)
                            .font(Font.system(size: 13).weight(.semibold))
                            .lineSpacing(3)
                            .foregroundColor(.dashBlue)
                        
                        if let icon = labelIcon {
                            Icon(name: icon)
                                .foregroundColor(.dashBlue)
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
            }
        }
        .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .frame(maxWidth: .infinity);
    }
}

#Preview {
    FeatureTopText(
        title: "Simplify your crypto taxes",
        text: "Connect your crypto wallets to the ZenLedger platform. Learn more and get started with your Dash Wallet transactions.",
        label: "zenledger.io",
        labelIcon: .custom("external.link")
    )
}
