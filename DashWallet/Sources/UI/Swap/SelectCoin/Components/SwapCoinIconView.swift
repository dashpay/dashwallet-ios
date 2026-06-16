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

/// Displays a Maya coin icon with automatic remote fallback.
///
/// Priority:
/// 1. Local asset (when `iconAssetName != "convert.crypto"`)
/// 2. SwapKit CDN icon fetched by full asset identifier
/// 3. jsupa remote fallback fetched by ticker code
/// 4. Placeholder (`convert.crypto`) if all remote loads fail
///
/// Remote icons crossfade in when loaded.  Fast-scrolling is safe: the
/// `task(id: coin.mayaAsset)` modifier cancels in-flight requests when the view
/// disappears, and `remoteImage` resets to nil on reuse (because @State is
/// tied to view identity in LazyVStack).
struct SwapCoinIconView: View {
    let coin: MayaCryptoCurrency
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var remoteImage: UIImage? = nil

    private var needsRemoteIcon: Bool {
        coin.iconAssetName == "convert.crypto"
    }

    var body: some View {
        Group {
            if let image = remoteImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Icon(name: .custom(coin.iconAssetName, maxHeight: size))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .task(id: coin.mayaAsset) {
            remoteImage = nil
            guard needsRemoteIcon else { return }

            var loaded = await MayaCoinIconLoader.shared.loadSwapKitIcon(for: coin.mayaAsset)
            if loaded == nil {
                loaded = await MayaCoinIconLoader.shared.loadJsupaIcon(for: coin.code)
            }
            withAnimation(.easeIn(duration: 0.15)) {
                remoteImage = loaded
            }
        }
    }
}

#if DEBUG
#Preview {
    HStack(spacing: 16) {
        // Coin with local icon
        SwapCoinIconView(
            coin: MayaCryptoCurrency(
                id: "btc", code: "BTC", name: "Bitcoin",
                mayaAsset: "BTC.BTC", chain: "BTC",
                iconAssetName: "maya.coin.btc"
            ),
            size: 26, cornerRadius: 6
        )

        // Coin without local icon — loads remotely
        SwapCoinIconView(
            coin: MayaCryptoCurrency(
                id: "sol", code: "SOL", name: "Solana",
                mayaAsset: "SOL.SOL", chain: "SOL",
                iconAssetName: "convert.crypto"
            ),
            size: 26, cornerRadius: 6
        )

        // Unknown coin — graceful fallback
        SwapCoinIconView(
            coin: MayaCryptoCurrency(
                id: "xyz", code: "XYZ", name: "Unknown",
                mayaAsset: "XYZ.XYZ", chain: "XYZ",
                iconAssetName: "convert.crypto"
            ),
            size: 26, cornerRadius: 6
        )
    }
    .padding()
}
#endif
