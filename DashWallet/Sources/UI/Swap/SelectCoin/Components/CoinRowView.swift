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
        SwapCoinIconView(
            coin: item.coin,
            size: Layout.iconSize,
            cornerRadius: Layout.iconCornerRadius
        )
    }

    private var coinInfo: some View {
        VStack(alignment: .leading, spacing: Layout.textSpacing) {
            Text(item.displayName)
                .font(.subheadMedium)
                .foregroundColor(.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(item.coin.code)
                .font(.footnote)
                .foregroundColor(.tertiaryText)
                .lineLimit(1)
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
private func makeItem(
    id: String, coin: MayaCryptoCurrency,
    displayName: String? = nil, price: String? = nil, halted: Bool = false
) -> CoinDisplayItem {
    CoinDisplayItem(id: id, coin: coin, displayName: displayName ?? coin.name, fiatPrice: price, isHalted: halted)
}

// iOS hierarchy: full name (+ network) on top, code below.
#Preview("Network-qualified rows") {
    VStack(spacing: 0) {
        // USDC / USD Coin (Ethereum)
        CoinRowView(item: makeItem(
            id: "usdc",
            coin: MayaCryptoCurrency(id: "usdc", code: "USDC", name: "USD Coin",
                                     mayaAsset: "ETH.USDC-0XA0B8...", chain: "ETH",
                                     iconAssetName: "maya.coin.usdc"),
            displayName: "USD Coin (Ethereum)",
            price: "USD 1.00"
        ))
        // USDC / USD Coin (Arbitrum)
        CoinRowView(item: makeItem(
            id: "usdc_arb",
            coin: MayaCryptoCurrency(id: "usdc_arb", code: "USDC", name: "USD Coin (Arbitrum)",
                                     mayaAsset: "ARB.USDC-0XAF88...", chain: "ARB",
                                     iconAssetName: "maya.coin.usdc"),
            price: "UAH 44.54"
        ))
        // USDT / Tether (Ethereum)
        CoinRowView(item: makeItem(
            id: "usdt",
            coin: MayaCryptoCurrency(id: "usdt", code: "USDT", name: "Tether",
                                     mayaAsset: "ETH.USDT-0XDAC1...", chain: "ETH",
                                     iconAssetName: "maya.coin.usdt"),
            displayName: "Tether (Ethereum)",
            price: "USD 1.00"
        ))
        // USDT / Tether (Arbitrum)
        CoinRowView(item: makeItem(
            id: "usdt_arb",
            coin: MayaCryptoCurrency(id: "usdt_arb", code: "USDT", name: "Tether",
                                     mayaAsset: "ARB.USDT-0XFD08...", chain: "ARB",
                                     iconAssetName: "maya.coin.usdt"),
            displayName: "Tether (Arbitrum)",
            price: "USD 1.00"
        ))
    }
}

#Preview("Halted") {
    VStack {
        CoinRowView(item: makeItem(
            id: MayaCryptoCurrency.supportedCoins[7].id,
            coin: MayaCryptoCurrency.supportedCoins[7],
            price: "USD 3,200.00", halted: true
        ))
        CoinRowView(item: makeItem(
            id: MayaCryptoCurrency.supportedCoins[1].id,
            coin: MayaCryptoCurrency.supportedCoins[1],
            price: "USD 3,200.00", halted: true
        ))
    }
}
#endif
