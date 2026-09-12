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

/// The card the payments landing's Internal and Send tabs open on: a list of
/// destinations to pick before any amount is entered.
///
/// The caption belongs inside the card rather than above it, which is why this
/// owns it instead of leaving it to the caller.
struct PaymentsActionCard<Rows: View>: View {
    /// Section label drawn above the rows, inside the card. `nil` on the Send
    /// tab, whose two rows need no heading.
    var caption: String? = nil
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let caption {
                Text(caption)
                    .dashFont(.footnote)
                    .foregroundColor(Color.dash.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }

            rows()
        }
        .modifier(MenuViewModifier())
    }
}

/// One destination inside `PaymentsActionCard`: a tinted glyph and a label.
///
/// No trailing chevron and no balance — this row picks *where* the flow goes;
/// the amount and the balances belong to the screen it opens.
struct PaymentsActionRow: View {
    let iconSystemName: String
    let title: String
    /// A destination the build cannot route yet renders dimmed and untappable
    /// rather than being hidden, so the card matches the designed list.
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            DashUIKit.MenuItem(
                leadingIcon: .custom(iconSystemName, bundle: .dashUIKit),
                isEnabled: isEnabled,
                title: title,
                accessory: .none
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

#if DEBUG

private func actionCardSample() -> some View {
    VStack(spacing: 20) {
        PaymentsActionCard(caption: "Internal transfer to/from") {
            PaymentsActionRow(iconSystemName: DashIcon.Features.shield.rawValue, title: "Shielded") {}
            PaymentsActionRow(
                iconSystemName: DashIcon.Features.identity.rawValue,
                title: "Identity",
                isEnabled: false) {}
            PaymentsActionRow(iconSystemName: DashIcon.Features.platform.rawValue, title: "Platform") {}
        }

        PaymentsActionCard {
            PaymentsActionRow(iconSystemName: "qrcode.viewfinder", title: "Scan QR") {}
            PaymentsActionRow(iconSystemName: "paperplane.fill", title: "Send to address") {}
        }
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Both cards") {
    actionCardSample()
}

@available(iOS 17, *)
#Preview("Dark") {
    actionCardSample()
        .preferredColorScheme(.dark)
}

/// Long labels are the only thing that can wrap a row — the glyph must stay
/// top-aligned with the first line rather than centring against two.
@available(iOS 17, *)
#Preview("Large type") {
    actionCardSample()
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
