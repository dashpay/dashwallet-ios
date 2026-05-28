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

let kMayaSupportURL = URL(string: "https://discord.gg/mayaprotocol")!

struct MayaTransactionFailureView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onSupport: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                failureIcon

                Text(NSLocalizedString("Conversion Failed", comment: "Maya"))
                    .font(.title1)
                    .foregroundColor(.primaryText)
                    .multilineTextAlignment(.center)
            }

            Text(message)
                .font(.subhead)
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Button(action: onSupport) {
                Text(NSLocalizedString("Contact Maya Support", comment: "Maya"))
                    .font(.subhead)
                    .foregroundColor(.dashBlue)
                    .padding(.vertical, 8)
            }

            VStack(spacing: 12) {
                DashButton(text: NSLocalizedString("Retry", comment: "Maya")) {
                    onRetry()
                }

                DashButton(text: NSLocalizedString("Cancel", comment: "Maya")) {
                    onCancel()
                }
                .overrideForegroundColor(.primaryText)
                .overrideBackgroundColor(.gray300Alpha10)


            }
            .padding(.horizontal, 60)
            .padding(.bottom, 20)
        }
    }

    private var failureIcon: some View {
        ZStack {
            Circle()
                .fill(Color.systemRed.opacity(0.1))
                .frame(width: 100, height: 100)

            Icon(name: .system("xmark.circle.fill"))
                .frame(width: 56, height: 56)
                .foregroundColor(.systemRed)
        }
    }
}

#if DEBUG
#Preview {
    MayaTransactionFailureView(
        message: NSLocalizedString(
            "The swap could not be submitted. Please check your network connection and try again.",
            comment: "Maya"
        ),
        onRetry: {},
        onCancel: {},
        onSupport: {}
    )
}


#endif
