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

/// The Internal tab's opening step: where a transfer can go, picked before any
/// amount is typed.
///
/// Reports the balance rather than acting on it — the host owns navigation, and
/// this only knows which destinations exist.
struct PaymentsInternalCard: View {
    var onSelect: (ChainNetwork) -> Void

    var body: some View {
        PaymentsActionCard(
            caption: NSLocalizedString("Internal transfer to/from", comment: "Payments")) {
            PaymentsActionRow(
                iconSystemName: DashIcon.Features.shield.rawValue,
                title: ChainNetwork.shielded.balanceName,
                action: { onSelect(.shielded) })

            // Identity credits are topped up through the identity flow
            // (`topUpIdentityWithFunding`), not the transfer engine —
            // `ChainNetwork` has no case for them. Listed but inert until
            // that route exists here.
            PaymentsActionRow(
                iconSystemName: DashIcon.Features.identity.rawValue,
                title: NSLocalizedString("Identity", comment: "Payments"),
                isEnabled: false,
                action: {})

            PaymentsActionRow(
                iconSystemName: DashIcon.Features.platform.rawValue,
                title: ChainNetwork.platform.balanceName,
                action: { onSelect(.platform) })
        }
    }
}

#if DEBUG

private func internalCardSample() -> some View {
    PaymentsInternalCard(onSelect: { _ in })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Card") {
    internalCardSample()
}

@available(iOS 17, *)
#Preview("Dark") {
    internalCardSample()
        .preferredColorScheme(.dark)
}

/// The disabled Identity row and the two live ones must stay visibly different
/// at large sizes, where the dimming is the only cue left.
@available(iOS 17, *)
#Preview("Large type") {
    internalCardSample()
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
