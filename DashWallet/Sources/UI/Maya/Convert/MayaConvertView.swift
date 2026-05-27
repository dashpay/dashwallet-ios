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

// MARK: - MenuCardStyle

private struct MenuCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(Color.secondaryBackground)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
    }
}

// MARK: - MayaConvertView

struct MayaConvertView: View {

    private enum Layout {
        static let iconSize: CGFloat = 30
        static let hSpacing: CGFloat = 10
        static let textSpacing: CGFloat = 1
        static let padding: CGFloat = 10
    }

    enum MenuItemState {
        case coin(MayaCryptoCurrency, address: String)
        case dash(balance: String)
    }

    private let coin: MayaCryptoCurrency
    private let address: String
    private let dashBalance: String

    init(coin: MayaCryptoCurrency, address: String, dashBalance: String) {
        self.coin = coin
        self.address = address
        self.dashBalance = dashBalance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 2) {
                menuItem(state: .dash(balance: dashBalance))
                menuItem(state: .coin(coin, address: address))
            }
            .modifier(MenuCardStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Menu Item

    @ViewBuilder
    private func menuItem(state: MenuItemState) -> some View {
        HStack(spacing: Layout.hSpacing) {
            menuItemIcon(for: state)
            menuItemLabels(for: state)
            Spacer()
            if case .dash(let balance) = state {
                balanceView(balance: balance)
            }
        }
        .padding(Layout.padding)
        .contentShape(.rect)
    }

    // MARK: - Menu Item Subviews

    @ViewBuilder
    private func menuItemIcon(for state: MenuItemState) -> some View {
        switch state {
        case .coin(let coin, _):
            Icon(name: .custom(coin.iconAssetName))
                .frame(width: Layout.iconSize, height: Layout.iconSize)
        case .dash:
            Icon(name: .custom("dashCircleFilled"))
                .frame(width: Layout.iconSize, height: Layout.iconSize)
        }
    }

    private func menuItemLabels(for state: MenuItemState) -> some View {
        VStack(alignment: .leading, spacing: Layout.textSpacing) {
            Text(menuItemTitle(for: state))
                .font(.subheadMedium)
                .foregroundColor(.primaryText)

            Text(menuItemSubtitle(for: state))
                .font(.footnote)
                .foregroundColor(.tertiaryText)
        }
    }

    private func menuItemTitle(for state: MenuItemState) -> String {
        switch state {
        case .coin(let coin, _): return coin.name
        case .dash: return NSLocalizedString("Dash", comment: "Maya")
        }
    }

    private func menuItemSubtitle(for state: MenuItemState) -> String {
        switch state {
        case .coin(_, let address): return address
        case .dash: return NSLocalizedString("Dash Wallet", comment: "Maya")
        }
    }

    private func balanceView(balance: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 4) {
                Text(String(format: NSLocalizedString("Balance: %@", comment: "Maya"), balance))
                    .font(.subhead)
                    .foregroundColor(.primaryText)

                Icon(name: .custom("dash-logo-black", maxHeight: 12))
            }

            Text("0.00 US$")
                .font(.caption1)
                .foregroundColor(.tertiaryText)
        }
    }
}

#if DEBUG
#Preview {
    MayaConvertView(
        coin: MayaCryptoCurrency.supportedCoins[0],
        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        dashBalance: "0.00"
    )
    .background(Color.primaryBackground)
}
#endif
