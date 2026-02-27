//
//  BuySellPortalView.swift
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

struct BuySellPortalView: View {
    let showCoinbase: Bool
    var onUphold: () -> Void
    var onCoinbase: () -> Void
    var onTopper: () -> Void
    var onMaya: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title and subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Buy & sell Dash", comment: "Buy Sell Portal"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primaryText)

                    Text(NSLocalizedString("Select a service to buy, sell, convert and transfer Dash", comment: "Buy Sell Portal"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondaryText)
                }
                .padding(.trailing, 40)

                // Card 1: Uphold + Coinbase
                VStack(spacing: 2) {
                    serviceRow(
                        icon: "shortcut_uphold",
                        name: Service.uphold.title,
                        subtitle: Service.uphold.subtitle,
                        action: onUphold
                    )

                    if showCoinbase {
                        serviceRow(
                            icon: "shortcut_coinbase",
                            name: Service.coinbase.title,
                            subtitle: Service.coinbase.subtitle,
                            action: onCoinbase
                        )
                    }
                }
                .padding(6)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .shadow(color: .shadow, radius: 10, x: 0, y: 5)

                // Card 2: Topper + "Powered by Uphold" badge
                VStack(spacing: 0) {
                    serviceRow(
                        icon: "shortcut_topper",
                        name: Service.topper.title,
                        subtitle: Service.topper.subtitle,
                        action: onTopper
                    )

                    HStack(spacing: 6) {
                        Image("uphold_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 12, height: 16)

                        Text(NSLocalizedString("Powered by Uphold", comment: "Buy Sell Portal"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color(.sRGB, red: 176.0/255.0, green: 182.0/255.0, blue: 188.0/255.0, opacity: 0.1))
                    .cornerRadius(8)
                }
                .padding(6)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .shadow(color: .shadow, radius: 10, x: 0, y: 5)

                // Card 3: Maya
                VStack(spacing: 0) {
                    serviceRow(
                        icon: Service.maya.icon,
                        name: Service.maya.title,
                        subtitle: Service.maya.subtitle,
                        action: onMaya
                    )
                }
                .padding(6)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .shadow(color: .shadow, radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primaryBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func serviceRow(icon: String, name: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primaryText)

                    Text(subtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
        .cornerRadius(10)
    }
}
