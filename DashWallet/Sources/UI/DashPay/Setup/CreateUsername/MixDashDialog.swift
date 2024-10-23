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

public struct MixDashDialog: View {
    @Environment(\.presentationMode) private var presentationMode
    var positiveAction: () -> Void
    var negativeAction: () -> Void
    
    public var body: some View {
        BottomSheet(showBackButton: Binding<Bool>.constant(false)) {
            VStack(spacing: 0) {
                FeatureTopText(
                    title: NSLocalizedString("Mix your Dash Coins", comment: "CoinJoin"),
                    text: NSLocalizedString("To help prevent other people from seeing who you make payments to, it is recommended to mix your balance before you create your username.", comment: "CoinJoin"),
                    alignment: .leading
                )
                
                Spacer()
                
                ButtonsGroup(
                    orientation: .horizontal,
                    style: .regular,
                    size: .large,
                    positiveButtonText: NSLocalizedString("Mix coins", comment: "CoinJoin"),
                    positiveButtonAction: {
                        presentationMode.wrappedValue.dismiss()
                        positiveAction()
                    },
                    negativeButtonText: NSLocalizedString("Skip", comment: ""),
                    negativeButtonAction: {
                        presentationMode.wrappedValue.dismiss()
                        negativeAction()
                    }
                )
                .padding(.top, 20)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
    }
}
