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
    let item: CoinDisplayItem

    var body: some View {
        HStack(spacing: 12) {
            coinIcon

            VStack(alignment: .leading, spacing: 1) {
                Text(item.coin.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primaryText)

                Text(item.coin.code)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondaryText)
            }

            Spacer()

            if item.isHalted {
                Text(NSLocalizedString("halted", comment: "Maya"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray400.opacity(0.15))
                    .cornerRadius(6)
            } else if let price = item.fiatPrice {
                Text(price)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondaryText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(item.isHalted ? 0.5 : 1.0)
        .saturation(item.isHalted ? 0.0 : 1.0)
    }

    private var coinIcon: some View {
        Image(item.coin.iconAssetName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
