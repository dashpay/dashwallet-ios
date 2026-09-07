//
//  Created by Roman Chornyi
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

import DashUIKit
import SwiftUI

struct SwapTransactionPendingView: View {
    let message: String
    let executionNetwork: String
    var onGoHome: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            LoadingIllustration()
                .padding(.bottom, 30)


            VStack(spacing: 6) {
                Text(NSLocalizedString("Conversion in progress", comment: "Dash DEX"))
                    .dashFont(.title1)
                    .foregroundColor(Color.dash.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 16)

            Spacer()

            VStack(spacing: 16) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Close and notify me", comment: "Dash DEX"),
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue
                ) {
                    onGoHome()
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 60)
        }
    }
}

#if DEBUG
#Preview {
    SwapTransactionPendingView(
        message: NSLocalizedString(
            "Your Dash transaction has been sent. Waiting for InstantSend lock — this usually takes a few seconds.",
            comment: "Dash DEX"
        ),
        executionNetwork: "NEAR",
        onGoHome: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dash.primaryBackground)
}
#endif
