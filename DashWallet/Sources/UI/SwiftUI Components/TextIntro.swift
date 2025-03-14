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

struct TextIntro: View {
    var icon: IconName? = nil
    var buttonLabel: String? = nil
    var action: (() -> Void)? = nil
    var isActionEnabled: Bool = true
    var inProgress: Binding<Bool>? = nil
    @ViewBuilder var topText: () -> FeatureTopText
    var features: () -> [FeatureSingleItem] = {[]}
    var info: String? = nil
    
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .top)) {
            VStack(alignment: .leading, spacing: 0) {
                if let icon = icon {
                    Icon(name: icon)
                        .frame(maxWidth: .infinity, maxHeight: 100, alignment: .center)
                        .padding(.bottom, 24)
                }
                
                topText()
                    .frame(maxWidth: .infinity, alignment: .top)
                
                if !features().isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(0..<features().count, id: \.self) { index in
                                features()[index]
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 16)
                            }
                        }
                    }
                    .padding(.top, 20)
                }
                
                Spacer()
                
                if let info = info {
                    Text(info)
                        .multilineTextAlignment(.center)
                        .font(.footnote)
                        .foregroundColor(.tertiaryText)
                        .frame(maxWidth: .infinity)
                }
          
                if let label = buttonLabel {
                    ZStack(alignment: .center) {
                        DashButton(
                            text: inProgress != nil && inProgress!.wrappedValue ? "" : label,
                            isEnabled: isActionEnabled
                        ) {
                            if inProgress == nil || inProgress!.wrappedValue == false {
                                action?()
                            }
                        }
                        
                        if inProgress != nil && inProgress!.wrappedValue {
                            SwiftUI.ProgressView()
                                .tint(.white)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 20, trailing: 20))
    }
}

#Preview {
    TextIntro(
        icon: .custom("zenledger_large"),
        buttonLabel: NSLocalizedString("Export all transactions", comment: "ZenLedger"),
        action: {
            print("hello")
        },
        inProgress: .constant(false)
    ) {
        FeatureTopText(
            title: "Simplify your crypto taxes",
            text: "Connect your crypto wallets to the ZenLedger platform. Learn more and get started with your Dash Wallet transactions.",
            label: "zenledger.io",
            labelIcon: .custom("external.link")
        )
    }
}
