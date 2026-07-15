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
    let explorerLink: (url: URL, text: String)?
    var onDone: () -> Void = {}

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            SuccessIllustration()
                .padding(.bottom, 30)

            VStack(spacing: 6) {
                Text(String(format: NSLocalizedString("You successfully converted DASH to %@", comment: "Dash DEX"), coinCode))
                    .dashFont(.title1)
                    .foregroundColor(Color.dash.primaryText)
                    .multilineTextAlignment(.center)

                Text(String(format: NSLocalizedString("It can take up to a few minutes for your %@ to arrive at the destination address using %@", comment: "Dash DEX"), coinName, executionNetwork))
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 20) {
                DashUIKit.DashButton(
                    text: NSLocalizedString("Done", comment: ""),
                    fillsWidth: true,
                    size: .large,
                    style: .filledBlue
                ) {
                    onDone()
                }

                if let explorerLink {
                    DashUIKit.DashButton(
                        text: explorerLink.text,
                        fillsWidth: true,
                        size: .large,
                        style: .tintedBlue
                    ) {
                        openURL(explorerLink.url)
                    }
                }
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
        executionNetwork: "NEAR",
        explorerLink: (url: URL(string: "https://example.com")!, text: "View NEAR Intents explorer")
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dash.primaryBackground)
}
#endif
