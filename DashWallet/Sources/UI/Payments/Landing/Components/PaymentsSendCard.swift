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

/// The Send tab's opening step: how to name a recipient.
///
/// Two cards rather than one list, because the second is not another way to
/// name a Dash recipient — it leaves Dash entirely for another chain, and
/// putting it under the same roof as the three address rows would read as a
/// fourth way to do the same thing.
struct PaymentsSendCard: View {
    /// A username can only be sent to from an identity that has one, and the
    /// row opens the contact book — which has nothing to show without it.
    var showsSendToUsername: Bool = false
    var onSendToUsername: () -> Void = {}
    var onSendToAddress: () -> Void
    var onScanQR: () -> Void
    /// Off on testnet and without a SwapKit key — the portal swaps real assets
    /// and can do neither. The whole second card goes with it rather than
    /// showing a card with one dead row.
    var showsSwapToCrypto: Bool = false
    var onSwapToCrypto: () -> Void = {}

    private enum Layout {
        /// Enough to read as two groups without either drifting away from the
        /// selector above them.
        static let cardSpacing: CGFloat = 12
    }

    var body: some View {
        VStack(spacing: Layout.cardSpacing) {
            PaymentsActionCard {
                if showsSendToUsername {
                    PaymentsActionRow(
                        iconSystemName: DashIcon.Menu.sendAccount.rawValue,
                        title: NSLocalizedString("Send to username", comment: "Payments"),
                        action: onSendToUsername
                    )
                }

                PaymentsActionRow(
                    iconSystemName: DashIcon.Menu.sendAddress.rawValue,
                    title: NSLocalizedString("Send to Dash address", comment: "Payments"),
                    action: onSendToAddress
                )

                PaymentsActionRow(
                    iconSystemName: DashIcon.Menu.scanQR.rawValue,
                    title: NSLocalizedString("Scan Dash QR", comment: "Payments"),
                    action: onScanQR
                )
            }

            if showsSwapToCrypto {
                PaymentsActionCard {
                    PaymentsActionRow(
                        iconSystemName: DashIcon.Menu.swapDashCoin.rawValue,
                        title: NSLocalizedString("Swap to other crypto", comment: "Payments"),
                        action: onSwapToCrypto
                    )
                }
            }
        }
    }
}

#if DEBUG

private func sendCardSample(
    showsSendToUsername: Bool = false,
    showsSwapToCrypto: Bool = true
) -> some View {
    PaymentsSendCard(
        showsSendToUsername: showsSendToUsername,
        onSendToUsername: {},
        onSendToAddress: {},
        onScanQR: {},
        showsSwapToCrypto: showsSwapToCrypto,
        onSwapToCrypto: {})
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

/// No identity: the username row is absent and the first card carries two rows.
@available(iOS 17, *)
#Preview("No username") {
    sendCardSample()
}

/// Testnet, or a build with no SwapKit key: the second card is gone entirely
/// and the tab is the three Dash rows it was before.
@available(iOS 17, *)
#Preview("No swap") {
    sendCardSample(showsSendToUsername: true, showsSwapToCrypto: false)
}

/// The registered-identity presentation — the row this tab gains, and the one
/// that changes the first card's height.
@available(iOS 17, *)
#Preview("With username") {
    sendCardSample(showsSendToUsername: true)
}

@available(iOS 17, *)
#Preview("Dark") {
    sendCardSample(showsSendToUsername: true)
        .preferredColorScheme(.dark)
}

/// The two cards must stay legible as two groups when the rows grow — this is
/// where a single merged list would start to look right and be wrong.
@available(iOS 17, *)
#Preview("Large type") {
    sendCardSample(showsSendToUsername: true)
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
