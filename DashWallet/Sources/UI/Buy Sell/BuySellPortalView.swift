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
    @ObservedObject var model: BuySellPortalModel
    var onBack: () -> Void
    var onUphold: () -> Void
    var onCoinbase: () -> Void
    var onTopper: () -> Void
    var onMaya: () -> Void
    var onSwapKit: () -> Void

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
                    if SwapKitConstants.isConfigured {
                        swapKitCard
                    }
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

    private var swapKitCard: some View {
        VStack(spacing: 2) {
            menuItem(for: .swapKit, action: onSwapKit)
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
        let item = model.items.first { $0.service == service }

        // Show balance when an account-based service is connected.
        // For 0 balance we still show the amount (not the subtitle) so the
        // "connected" state is clear — MenuItem hides the fiat line for 0.
        let isConnected = item?.status == .authorized
            && (service == .uphold || service == .coinbase)

        let dashAmount: Int64? = isConnected
            ? Int64(item?.dashBalance ?? 0)
            : nil

        let subtitle: String? = isConnected
            ? nil
            : service.subtitle

        // Apply MenuItemButtonStyle to MenuItem's inner Button so the press
        // animation works without double-wrapping taps.
        return MenuItem(
            title: service.title,
            subtitle: subtitle,
            icon: .custom(service.icon),
            dashAmount: dashAmount,
            showDashAmountDirection: false,
            overrideFiatAmount: isConnected ? item?.fiatBalanceFormatted : nil,
            action: action
        )
        .buttonStyle(MenuItemButtonStyle())
    }

    // MARK: - Subviews

    private var topIntro: some View {
        TopIntro(
            title: NSLocalizedString("Buy & Sell Dash", comment: "Buy Sell Portal"),
            subtitle: NSLocalizedString("Select a service to buy, sell, convert and transfer Dash", comment: "Buy Sell Portal")
        )
    }
}

#if DEBUG
private extension BuySellPortalModel {
    static var preview: BuySellPortalModel { BuySellPortalModel() }
}

#Preview("BuySell Portal - Coinbase") {
    BuySellPortalView(
        showCoinbase: true,
        model: .preview,
        onBack: {},
        onUphold: {},
        onCoinbase: {},
        onTopper: {},
        onMaya: {},
        onSwapKit: {}
    )
}

#Preview("BuySell Portal - No Coinbase") {
    BuySellPortalView(
        showCoinbase: false,
        model: .preview,
        onBack: {},
        onUphold: {},
        onCoinbase: {},
        onTopper: {},
        onMaya: {},
        onSwapKit: {}
    )
}
#endif
