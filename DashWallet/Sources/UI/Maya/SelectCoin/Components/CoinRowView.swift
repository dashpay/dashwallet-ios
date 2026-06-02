//
//  CoinRowView.swift
//  DashWallet
//
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

struct CoinRowView: View {

    private enum Layout {
        static let spacing: CGFloat = 16
        static let textSpacing: CGFloat = 1
        static let padding: CGFloat = 10
        static let iconSize: CGFloat = 30
        static let iconCornerRadius: CGFloat = 6
        static let badgeHPadding: CGFloat = 8
        static let badgeVPadding: CGFloat = 2
        static let badgeCornerRadius: CGFloat = 6
    }

    let item: CoinDisplayItem

    var body: some View {
        HStack(spacing: Layout.spacing) {
            coinIcon
            coinInfo
            trailingBadge
        }
        .padding(Layout.padding)
        .opacity(item.isHalted ? 0.5 : 1.0)
        .contentShape(.rect)


    }

    // MARK: - Subviews

    private var coinIcon: some View {
        MayaCoinIconView(
            coin: item.coin,
            size: Layout.iconSize,
            cornerRadius: Layout.iconCornerRadius
        )
    }

    private var coinInfo: some View {
        VStack(alignment: .leading, spacing: Layout.textSpacing) {
            Text(item.coin.name)
                .font(.subheadMedium)
                .foregroundColor(.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(item.coin.code)
                .font(.footnote)
                .foregroundColor(.tertiaryText)
                .kerning(0.26)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trailingBadge: some View {
        if item.isHalted {
            haltedLabel
        } else if let price = item.fiatPrice {
            Text(price)
                .font(.caption1)
                .foregroundColor(.tertiaryText)
        }
    }

    private var haltedLabel: some View {
        Text(NSLocalizedString("halted", comment: "Maya"))
            .font(.caption1)
            .foregroundColor(.tertiaryText)
            .padding(.horizontal, Layout.badgeHPadding)
            .padding(.vertical, Layout.badgeVPadding)
            .background(Color.black1000Alpha8)
            .clipShape(.rect(cornerRadius: Layout.badgeCornerRadius))
    }
}

#if DEBUG
#Preview("Available") {
    CoinRowView(item: CoinDisplayItem(
        id: "eth_arb",
        coin: MayaCryptoCurrency(id: "eth_arb", code: "ETH", name: "Ethereum (Arbitrum)", mayaAsset: "ARB.ETH", chain: "ARB", iconAssetName: "maya.coin.eth"),
        fiatPrice: "$65,000",
        isHalted: false
    ))
//    .background(.red.opacity(0.3))
}

#Preview("Halted") {
    VStack {
        CoinRowView(item: CoinDisplayItem(
            id: MayaCryptoCurrency.supportedCoins[7].id,
            coin: MayaCryptoCurrency.supportedCoins[7],
            fiatPrice: "$3,200",
            isHalted: true
        ))

        CoinRowView(item: CoinDisplayItem(
            id: MayaCryptoCurrency.supportedCoins[1].id,
            coin: MayaCryptoCurrency.supportedCoins[1],
            fiatPrice: "$3,200",
            isHalted: true
        ))
    }
}
#endif
