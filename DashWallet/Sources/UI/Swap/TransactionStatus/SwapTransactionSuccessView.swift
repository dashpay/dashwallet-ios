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

struct SwapTransactionSuccessView: View {
    let coinCode: String
    let coinName: String
    let executionNetwork: String
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            SuccessIllustration()
                .padding(.bottom, 30)

            VStack(spacing: 6) {
                Text(NSLocalizedString("You successfully converted DASH to \(coinCode)", comment: "Maya"))
                    .font(Font.dash.title1)
                    .foregroundColor(Color.dash.primaryText)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("It can take up to a few minutes for your \(coinName) to arrive at the destination address", comment: "Maya"))
                    .font(Font.dash.subhead)
                    .foregroundColor(Color.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 40)

            Spacer()

            DashUIKit.DashButton(
                text: NSLocalizedString("Done", comment: ""),
                fillsWidth: true,
                size: .large,
                style: .filledBlue
            ) {
                onDone()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 60)
        }
    }
}

#if DEBUG
#Preview {
    SwapTransactionSuccessView(
        coinCode: "BTC",
        coinName: "Bitcoin",
        executionNetwork: "Maya"
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dash.primaryBackground)
}
#endif
