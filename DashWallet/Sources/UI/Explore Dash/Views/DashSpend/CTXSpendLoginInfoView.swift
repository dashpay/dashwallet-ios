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

struct CTXSpendLoginInfoView: View {
    let onCreateNewAccount: () -> Void
    let onLogIn: () -> Void
    let onTermsAndConditions: () -> Void
    @State private var inProgress: Bool = false
    
    var body: some View {
        BottomSheet(showBackButton: .constant(false)) {
            VStack {
                TextIntro(
                    icon: .custom("ctx.logo", maxHeight: 60),
                    inProgress: $inProgress
                ) {
                    FeatureTopText(
                        title: NSLocalizedString("Create an account or log into an existing one", comment: "DashSpend account title"),
                        label: NSLocalizedString("Terms & conditions", comment: "Terms & conditions"),
                        labelIcon: .custom("external.link"),
                        linkAction: onTermsAndConditions
                    )
                }
                
                ButtonsGroup(
                    orientation: .vertical,
                    size: .large,
                    positiveActionEnabled: true,
                    positiveButtonText: NSLocalizedString("Create new account", comment: ""),
                    positiveButtonAction: {
                        onCreateNewAccount()
                    },
                    negativeButtonText: NSLocalizedString("Log in", comment: ""),
                    negativeButtonAction: {
                        onLogIn()
                    }
                )
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
        }
    }
}

#Preview {
    CTXSpendLoginInfoView(
        onCreateNewAccount: {},
        onLogIn: {},
        onTermsAndConditions: {}
    )
}
