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

import SwiftUI

struct SwapTransactionPendingView: View {
    let message: String
    let executionNetwork: String
    let detailMessage: String?
    let trackerURL: URL?
    var onGoHome: () -> Void = {}

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            LoadingIllustration()
                .padding(.bottom, 30)


            VStack(spacing: 6) {
                Text(NSLocalizedString("Conversion in progress", comment: "Maya"))
                    .font(.title1)
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subhead)
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                if let detailMessage, !detailMessage.isEmpty {
                    Text(detailMessage)
                        .font(.subhead)
                        .foregroundColor(.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, 8)
                }

                Text(
                    String(
                        format: NSLocalizedString("Network: %@", comment: "Maya/SwapKit"),
                        executionNetwork
                    )
                )
                .font(.subhead)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 8)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 16)

            if let trackerURL {
                Button {
                    openURL(trackerURL)
                } label: {
                    Text(NSLocalizedString("View details", comment: "Maya/SwapKit"))
                        .font(.subheadMedium)
                        .foregroundColor(.dashBlue)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 60)
            }

            Spacer()

            DashButton(text: NSLocalizedString("Go to Home", comment: "Maya")) {
                onGoHome()
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
            "Waiting for block confirmation. Maya swaps require one Dash block (~2–5 min) before the swap begins.",
            comment: "Maya"
        ),
        executionNetwork: "NEAR",
        detailMessage: NSLocalizedString(
            "Swaps via NEAR can take up to an hour to complete. Your Dash has been sent — you can safely close this screen and check back later.",
            comment: "Maya/SwapKit"
        ),
        trackerURL: URL(string: "https://example.com"),
        onGoHome: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.primaryBackground)
}
#endif
