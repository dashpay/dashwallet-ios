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

struct TransferSourceRow: View {
    let iconSystemName: String
    let caption: String
    let title: String
    let balanceTrailing: AnyView
    let selected: Bool
    /// False renders a fixed (non-picker) endpoint card: no radio circle
    /// and no selection border.
    var showsRadio: Bool = true
    /// With `showsRadio` false: true renders a tappable collapsed selector
    /// (chevron trailing, expands a picker on tap) instead of a fixed card.
    var showsChevron: Bool = false
    var action: () -> Void

    /// Trailing balance amount + Dash currency glyph, the standard trailing
    /// content for these rows.
    static func dashBalanceTrailing(_ formatted: String) -> AnyView {
        AnyView(
            HStack(spacing: 2) {
                Text(formatted)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.dash.primaryText)
                Image("icon_dash_currency")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            })
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color.dash.blue.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundColor(Color.dash.secondaryText)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.dash.primaryText)
                }

                Spacer()

                balanceTrailing

                if showsRadio {
                    radioIndicator
                } else if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.dash.secondaryText)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.dash.secondaryBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(showsRadio && selected ? Color.dash.blue : Color.clear,
                            lineWidth: showsRadio && selected ? 1.5 : 0))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(!showsRadio && !showsChevron)
    }

    private var radioIndicator: some View {
        ZStack {
            Circle()
                .stroke(selected ? Color.dash.blue : Color.dash.gray300.opacity(0.6), lineWidth: 1.5)
                .frame(width: 18, height: 18)
            if selected {
                Circle()
                    .fill(Color.dash.blue)
                    .frame(width: 10, height: 10)
            }
        }
    }
}

#if DEBUG

/// One row per trailing treatment, on the background the screen actually puts
/// them on — the selection border only reads correctly against it.
private func sourceRowGallery(
    balance: String = "2.45",
    title: String = "Transparent"
) -> some View {
    VStack(spacing: 8) {
        TransferSourceRow(
            iconSystemName: "d.circle.fill",
            caption: "From",
            title: title,
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(balance),
            selected: true,
            action: {})

        TransferSourceRow(
            iconSystemName: "creditcard.fill",
            caption: "From",
            title: "Platform",
            balanceTrailing: TransferSourceRow.dashBalanceTrailing("1.2"),
            selected: false,
            action: {})

        TransferSourceRow(
            iconSystemName: "shield.fill",
            caption: "To",
            title: "Shielded",
            balanceTrailing: TransferSourceRow.dashBalanceTrailing("0.785"),
            selected: false,
            showsRadio: false,
            action: {})

        TransferSourceRow(
            iconSystemName: "d.circle.fill",
            caption: "From",
            title: title,
            balanceTrailing: TransferSourceRow.dashBalanceTrailing(balance),
            selected: false,
            showsRadio: false,
            showsChevron: true,
            action: {})
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.dash.primaryBackground)
}

@available(iOS 17, *)
#Preview("Variants") {
    sourceRowGallery()
}

@available(iOS 17, *)
#Preview("Dark") {
    sourceRowGallery()
        .preferredColorScheme(.dark)
}

/// A 5-fraction-digit balance next to a long balance name is the widest the
/// row ever gets — the title must shrink or truncate before the amount does.
@available(iOS 17, *)
#Preview("Widest content") {
    sourceRowGallery(balance: "123.45678", title: "Transparent balance")
}

/// The caption/title column stacks at accessibility sizes; the balance and the
/// radio must stay on the same line as the icon.
@available(iOS 17, *)
#Preview("Large type") {
    sourceRowGallery()
        .environment(\.dynamicTypeSize, .accessibility1)
}

#endif
