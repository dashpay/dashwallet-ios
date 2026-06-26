//
//  SwapCoinIconView.swift
//  DashWallet
//
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

/// Displays a coin icon loaded from the URL provided by SwapKit's `logoURI`.
///
/// Priority:
/// 1. Remote icon fetched from `coin.iconURL` (sourced from SwapKit `/tokens` `logoURI`)
/// 2. Placeholder (`convert.crypto`) while loading or if `iconURL` is nil / load fails
///
/// Remote icons crossfade in when loaded. Fast-scrolling is safe: the
/// `task(id: coin.iconURL)` modifier cancels in-flight requests when the view
/// disappears, and `remoteImage` resets to nil on reuse (because @State is
/// tied to view identity in LazyVStack).
struct SwapCoinIconView: View {
    let coin: MayaCryptoCurrency
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var remoteImage: UIImage? = nil

    var body: some View {
        Group {
            if let image = remoteImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Icon(name: .custom("convert.crypto", maxHeight: size))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .task(id: coin.mayaAsset) {
            remoteImage = nil
            let loaded = await MayaCoinIconLoader.shared.loadIcon(logoURI: coin.iconURL, ticker: coin.code)
            withAnimation(.easeIn(duration: 0.15)) { remoteImage = loaded }
        }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 16) {
        // Native asset with real logoURI — uses SwapKit source
        SwapCoinIconView(
            coin: MayaCryptoCurrency(
                id: "btc", code: "BTC", name: "Bitcoin",
                mayaAsset: "BTC.BTC", chain: "BTC",
                iconURL: "https://storage.googleapis.com/token-list-swapkit/images/btc.btc.png"
            ),
            size: 26, cornerRadius: 6
        )

        // No logoURI — exercises CoinCap / jsupa fallback chain
        SwapCoinIconView(
            coin: MayaCryptoCurrency(
                id: "dai", code: "DAI", name: "Dai",
                mayaAsset: "ARB.DAI-0XDA10009CBD5D07DD0CECC66161FC93D7C9000DA1", chain: "ARB"
            ),
            size: 26, cornerRadius: 6
        )

        // Truly unknown ticker — shows convert.crypto placeholder
        SwapCoinIconView(
            coin: MayaCryptoCurrency(
                id: "xyz", code: "XYZ", name: "Unknown",
                mayaAsset: "XYZ.XYZ", chain: "XYZ"
            ),
            size: 26, cornerRadius: 6
        )
    }
    .padding()
}
#endif
