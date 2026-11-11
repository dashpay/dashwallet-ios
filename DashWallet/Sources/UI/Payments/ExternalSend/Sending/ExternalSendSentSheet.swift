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

/// The sent state of a send that does not end on the transaction screen: the amount and Done.
struct ExternalSendSentSheet: View {
    let amountDuffs: UInt64
    let fiatText: String?
    let onDone: () -> Void

    var body: some View {
        DashUIKit.BottomSheet.selfSizing(
            title: NSLocalizedString("Confirm", comment: "External send"),
            showBackButton: .constant(false),
            isDismissalEnabled: .constant(true),
            showsCloseButton: false,
            onClose: onDone,
            content: {
                VStack(spacing: 16) {
                    PaymentSuccessHeader(
                        title: NSLocalizedString("Sent", comment: "External send"),
                        amountDuffs: Int64(clamping: amountDuffs),
                        fiatText: fiatText ?? "")
                    DashUIKit.DashButton(
                        text: NSLocalizedString("Done", comment: ""),
                        fillsWidth: true,
                        size: .large,
                        style: .filledBlue,
                        action: onDone)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            })
    }
}

#if DEBUG

private func previewSheet(duffs: UInt64, fiat: String?) -> some View {
    Color.dash.primaryBackground.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ExternalSendSentSheet(amountDuffs: duffs, fiatText: fiat, onDone: {})
        }
}

#Preview("Sent, with local value") { previewSheet(duffs: 150_000_000, fiat: "$ 45.00") }

#Preview("Sent, no exchange rate") { previewSheet(duffs: 150_000_000, fiat: nil) }

#Preview("Large amount, large Dynamic Type") {
    previewSheet(duffs: 123_456_789_000, fiat: "$ 37,037.04").dynamicTypeSize(.accessibility3)
}

#endif
