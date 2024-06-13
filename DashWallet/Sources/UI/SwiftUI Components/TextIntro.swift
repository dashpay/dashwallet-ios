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
    let icon: IconName
    var buttonLabel: String? = nil
    var action: (() -> Void)? = nil
    var inProgress: Binding<Bool>? = nil
    @ViewBuilder var topText: () -> FeatureTopText
    
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .center, vertical: .top)) {
            VStack(alignment: .leading, spacing: 0) {
                Icon(name: icon)
                    .frame(maxWidth: .infinity, maxHeight: 100, alignment: .center)
                
                topText().padding(.top, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          
                if let label = buttonLabel {
                    Button(action:{
                        if inProgress == nil || inProgress!.wrappedValue == false {
                            action?()
                        }
                    }, label: {
                        if inProgress == nil || inProgress!.wrappedValue == false {
                            Text(label)
                                .font(.system(size: 16)).fontWeight(.semibold)
                                .foregroundColor(.white)
                        } else {
                            SwiftUI.ProgressView()
                                .tint(.white)
                        }
                    })
                    .frame(maxWidth: .infinity, maxHeight: 46)
                    .alignmentGuide(.bottom) { d in d[.bottom] }
                    .background(Color.dashBlue)
                    .cornerRadius(12)
                    .padding(.top, 40)
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
