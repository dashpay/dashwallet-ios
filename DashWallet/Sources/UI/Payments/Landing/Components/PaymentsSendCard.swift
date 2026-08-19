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
import DashUIKit

/// The Send tab's opening step: how to name a recipient. No caption — two rows
/// this plain need no heading.
struct PaymentsSendCard: View {
    var onScanQR: () -> Void
    var onSendToAddress: () -> Void

    var body: some View {
        PaymentsActionCard {
            PaymentsActionRow(
                iconSystemName: DashIcon.Menu.scanQR.rawValue,
                title: NSLocalizedString("Scan QR", comment: "Payments"),
                action: onScanQR
            )

            PaymentsActionRow(
                iconSystemName: DashIcon.Menu.sendAddress.rawValue,
                title: NSLocalizedString("Send to address", comment: "Payments"),
                action: onSendToAddress
            )
        }
    }
}

#if DEBUG

private func sendCardSample() -> some View {
    PaymentsSendCard(onScanQR: {}, onSendToAddress: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Card") {
    sendCardSample()
}

#endif
