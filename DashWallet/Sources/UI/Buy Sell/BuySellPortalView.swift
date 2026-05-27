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

// MARK: - MenuItemButtonStyle

private struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - MenuCardStyle

private struct MenuCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(Color.secondaryBackground)
            .clipShape(.rect(cornerRadius: 20))
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
    }
}

// MARK: - BuySellPortalView

struct BuySellPortalView: View {
    let showCoinbase: Bool
    var onBack: () -> Void
    var onUphold: () -> Void
    var onCoinbase: () -> Void
    var onTopper: () -> Void
    var onMaya: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavigationBar(leading: { NavigationBarElement.back.button { onBack() } })

                VStack(alignment: .leading, spacing: 20) {
                    topIntro

                    topperCard
                    upholdCard
                    if showCoinbase {
                        coinbaseCard
                    }
                    mayaCard
                }
                .padding(.top, 10)
                .padding(.horizontal, 20)
            }
        }
        .background(Color.primaryBackground.ignoresSafeArea())
    }

    // MARK: - Cards

    private var topperCard: some View {
        VStack(spacing: 2) {
            menuItem(for: .topper, action: onTopper)
            poweredByUpholdBadge
        }
        .modifier(MenuCardStyle())
    }

    private var upholdCard: some View {
        VStack(spacing: 2) {
            menuItem(for: .uphold, action: onUphold)
        }
        .modifier(MenuCardStyle())
    }

    private var coinbaseCard: some View {
        VStack(spacing: 2) {
            menuItem(for: .coinbase, action: onCoinbase)
        }
        .modifier(MenuCardStyle())
    }

    private var mayaCard: some View {
        VStack(spacing: 2) {
            menuItem(for: .maya, action: onMaya)
        }
        .modifier(MenuCardStyle())
    }

    private var poweredByUpholdBadge: some View {
        HStack(spacing: 6) {
            Image("uphold_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 16)

            Text(NSLocalizedString("Powered by Uphold", comment: "Buy Sell Portal"))
                .font(.caption1)
                .foregroundColor(.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color.gray300Alpha10)
        .clipShape(.rect(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func menuItem(for service: Service, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            BuySellMenuItem(
                iconName: service.icon,
                title: service.title,
                description: service.subtitle
            )
        }
        .buttonStyle(MenuItemButtonStyle())
    }

    // MARK: - Subviews

    private var topIntro: some View {
        TopIntro(
            title: NSLocalizedString("Buy & sell Dash", comment: "Buy Sell Portal"),
            subtitle: NSLocalizedString("Select a service to buy, sell, convert and transfer Dash", comment: "Buy Sell Portal")
        )
    }
}

#if DEBUG
#Preview("BuySell Portal - Coinbase") {
    BuySellPortalView(
        showCoinbase: true,
        onBack: {},
        onUphold: {},
        onCoinbase: {},
        onTopper: {},
        onMaya: {}
    )
}

#Preview("BuySell Portal - No Coinbase") {
    BuySellPortalView(
        showCoinbase: false,
        onBack: {},
        onUphold: {},
        onCoinbase: {},
        onTopper: {},
        onMaya: {}
    )
}
#endif
