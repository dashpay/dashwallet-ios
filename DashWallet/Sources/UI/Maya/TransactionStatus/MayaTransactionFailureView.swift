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

struct MayaTransactionFailureView: View {
    /// Specific failure reason surfaced from the swap or submission error.
    /// When nil, the generic fallback message is shown.
    var reason: String? = nil
    let onRetry: () -> Void
    /// Close behavior: one pop back via onCancel (onNavigateHome if full exit is needed).
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            ErrorIllustration()
                .padding(.top, 20)
                .padding(.bottom, 10)

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
            .padding(.top, 20)
            .padding(.bottom, 32)

            Spacer()

            VStack(spacing: 16) {
                DashButton(text: NSLocalizedString("Try Again", comment: "Maya")) {
                    onRetry()
                }

                DashButton(text: NSLocalizedString("Close", comment: "")) {
                    onCancel()
                }
                .overrideBackgroundColor(Color.gray300Alpha10)
                .overrideForegroundColor(Color.black)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 60)
        }
    }
}

#if DEBUG
#Preview {
    MayaTransactionFailureView(
        reason: "Input 0 is already spent by a pending transaction. Wait for the previous swap to confirm before initiating a new one.",
        onRetry: {},
        onCancel: {}
    )
}

private struct MayaTransactionFailureSheetPreviewHost: View {
    @State private var isPresented = true

    var body: some View {
        Color.primaryBackground
            .ignoresSafeArea()
            .sheet(isPresented: $isPresented) {
                let sheet = BottomSheet(showBackButton: .constant(false)) {
                    MayaTransactionFailureView(
                        reason: "Input 0 is already spent by a pending transaction.",
                        onRetry: {},
                        onCancel: {}
                    )
                }
                if #available(iOS 16.0, *) {
                    sheet.presentationDetents([.large])
                } else {
                    sheet
                }
            }
    }
}

#Preview("Bottom sheet") {
    MayaTransactionFailureSheetPreviewHost()
}

#endif
