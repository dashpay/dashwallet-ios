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

struct SwapTransactionFailureView: View {
    /// Specific failure reason surfaced from the swap or submission error.
    /// When nil, the generic fallback message is shown.
    var reason: String? = nil
    /// True while a fresh quote is being fetched after the user tapped Retry.
    var isRetrying: Bool = false
    /// Inbound Dash tx hash, when the swap failed AFTER broadcast. Drives the MayaScan deep link.
    /// nil when the failure happened before broadcast (quote/build error, cancelled PIN).
    var transactionHash: String? = nil
    let onRetry: () -> Void
    /// Close behavior: dismisses the failure screen (returns to the Maya Portal).
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            ErrorIllustration()
                .padding(.bottom, 30)

            VStack(spacing: 6) {
                Text(NSLocalizedString("Conversion failed", comment: "Maya"))
                    .font(.title1)
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.center)

                Text(reason ?? NSLocalizedString("Your DASH was not converted and no funds were deducted. Try again, or come back later.", comment: "Maya"))
                    .font(.subhead)
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 16)

            contactSupportButton

            Spacer()

            VStack(spacing: 16) {
                DashButton(
                    text: NSLocalizedString("Retry", comment: "Maya"),
                    isEnabled: !isRetrying,
                    isLoading: isRetrying
                ) {
                    onRetry()
                }

                DashButton(text: NSLocalizedString("Close", comment: "Maya")) {
                    onCancel()
                }
                .overrideBackgroundColor(Color.gray300Alpha10)
                .overrideForegroundColor(Color.black)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 60)
        }
    }

    private var contactSupportButton: some View {
        // With a broadcast tx, link the user to THEIR swap on MayaScan; otherwise fall back to
        // the generic Maya support docs.
        let (url, label): (URL, String) = {
            if let transactionHash, !transactionHash.isEmpty {
                return (
                    MayaConstants.mayaScanTransactionURL(txHash: transactionHash),
                    NSLocalizedString("View transaction on MayaScan", comment: "Maya")
                )
            }
            return (
                MayaConstants.supportURL,
                NSLocalizedString("Contact Maya Support", comment: "Maya")
            )
        }()

        return Button {
            openURL(url)
        } label: {
            Text(label)
                .font(.subheadMedium)
                .foregroundColor(.dashBlue)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Before broadcast — support fallback") {
    SwapTransactionFailureView(
        reason: "Input 0 is already spent by a pending transaction. Wait for the previous swap to confirm before initiating a new one.",
        onRetry: {},
        onCancel: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.primaryBackground)
}

#Preview("After broadcast — MayaScan link") {
    SwapTransactionFailureView(
        reason: "Your DASH was refunded by Maya Protocol.",
        transactionHash: "d891ed43f1f3eedfb7078e02d6be0423b741533b4b0407a822307b2637703649",
        onRetry: {},
        onCancel: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.primaryBackground)
}
#endif
