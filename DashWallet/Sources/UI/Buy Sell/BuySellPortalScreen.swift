//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

private struct MenuCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(6)
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)
    }
}

struct BuySellPortalScreen: View {
    @Environment(\.colorScheme)
    private var colorScheme
    @ObservedObject var model: BuySellPortalModel
    private let onBack: () -> Void
    private let onTopper: () -> Void
    private let onCoinbase: () -> Void
    private let onUphold: () -> Void

    init(model: BuySellPortalModel,
         onBack: @escaping () -> Void,
         onTopper: @escaping () -> Void,
         onCoinbase: @escaping () -> Void,
         onUphold: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
        self.onTopper = onTopper
        self.onCoinbase = onCoinbase
        self.onUphold = onUphold
    }

    private var coinbaseItem: ServiceItem? {
        model.items.first { $0.service == .coinbase }
    }

    private var upholdItem: ServiceItem? {
        model.items.first { $0.service == .uphold }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack(onBack: onBack)

            TopIntro(
                title: NSLocalizedString("Buy & Sell Dash", comment: "Buy Sell Dash"),
                subtitle: NSLocalizedString("Select a service to buy, sell, convert and transfer Dash", comment: "Buy Sell Dash")
            )

            VStack(spacing: 20) {
                // Topper
                VStack(spacing: 0) {
                    MenuItem(
                        title: NSLocalizedString("Topper", comment: "Buy Sell Dash"),
                        subtitle: NSLocalizedString("Buy Dash · No account needed", comment: "Buy Sell Dash"),
                        icon: .custom("service-topper", maxHeight: 30),
                        action: onTopper
                    )
                    .frame(minHeight: 56)

                    HStack(spacing: 6) {
                        Image("service-uphold")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text(NSLocalizedString("Powered by Uphold", comment: "Buy Sell Dash"))
                            .font(.caption)
                            .foregroundColor(.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(colorScheme == .dark ? Color.whiteAlpha5 : Color.primaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .modifier(MenuCardStyle())

                // Coinbase
                VStack(spacing: 0) {
                    MenuItem(
                        title: NSLocalizedString("Coinbase", comment: "Buy Sell Dash"),
                        subtitle: coinbaseSubtitle,
                        icon: .custom("service-coinbase", maxHeight: 30),
                        trailingView: serviceBalanceView(item: coinbaseItem),
                        action: onCoinbase
                    )
                    .frame(minHeight: 56)
                }
                .modifier(MenuCardStyle())

                // Uphold
                VStack(spacing: 0) {
                    MenuItem(
                        title: NSLocalizedString("Uphold", comment: "Buy Sell Dash"),
                        subtitle: upholdSubtitle,
                        icon: .custom("service-uphold", maxHeight: 30),
                        trailingView: serviceBalanceView(item: upholdItem),
                        action: onUphold
                    )
                    .frame(minHeight: 56)
                }
                .modifier(MenuCardStyle())
            }

            Spacer()
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
    }

    // MARK: - Helpers

    private func serviceSubtitle(for item: ServiceItem?) -> String? {
        guard let item else {
            return NSLocalizedString("Link your account", comment: "Buy Sell Dash")
        }
        switch item.status {
        case .syncing:
            return NSLocalizedString("Syncing...", comment: "Buy Sell Dash")
        case .authorized:
            return nil
        default:
            return NSLocalizedString("Link your account", comment: "Buy Sell Dash")
        }
    }

    private var coinbaseSubtitle: String? { serviceSubtitle(for: coinbaseItem) }
    private var upholdSubtitle: String? { serviceSubtitle(for: upholdItem) }

    private func serviceBalanceView(item: ServiceItem?) -> AnyView? {
        guard let item, item.status == .authorized, let formattedAmount = item.dashBalanceFormatted else {
            return nil
        }

        return AnyView(
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(formattedAmount)
                        .font(.footnote)
                        .fontWeight(.medium)
                    Image("dash-logo-black")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 12)
                }
                .foregroundColor(.primaryText)
                if let fiat = item.fiatBalanceFormatted, (item.dashBalance ?? 0) > 0 {
                    Text(fiat)
                        .font(.caption)
                        .foregroundColor(.secondaryText)
                }
            }
        )
    }
}
