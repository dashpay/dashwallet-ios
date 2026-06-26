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

import DashUIKit
import SwiftUI

struct SwapPortalScaffold: View {
    let logoAssetName: String
    let title: String
    let description: String
    var showBuy: Bool = false
    var onBack: () -> Void
    var onBuyDash: (() -> Void)?
    var onSellDash: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            DashUIKit.NavigationBar(leading: {
                NavigationBarElement.back.button { onBack() }
            })

            ScrollView {
                VStack(spacing: 20) {
                    introSection
                    actionsCard
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.dash.primaryBackground.ignoresSafeArea())
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            logoContainer
            descriptionBlock
        }
        .modifier(MenuViewModifier(innerPadding: 20))
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            if showBuy {
                Button(
                    action: { onBuyDash?() },
                    label: {
                        DashUIKit.MenuItem(
                            leadingIcon: .custom("dash-dex-buy"),
                            title: NSLocalizedString("Buy Dash", comment: "Dash DEX Portal"),
                            helpText: NSLocalizedString("From any crypto to your Dash Wallet", comment: "Dash DEX Portal"),
                            accessory: .none
                        )
                    }
                )
                .buttonStyle(.plain)
            }

            Button(
                action: { onSellDash?() },
                label: {
                    DashUIKit.MenuItem(
                        leadingIcon: .custom("dash-dex-sell"),
                        title: NSLocalizedString("Sell Dash", comment: "Dash DEX Portal"),
                        helpText: NSLocalizedString("From Dash Wallet to any crypto", comment: "Dash DEX Portal"),
                        accessory: .none
                    )
                }
            )
            .buttonStyle(.plain)
        }
        .modifier(MenuViewModifier())
    }

    private var logoContainer: some View {
        Image(dash: .custom(logoAssetName))
            .resizable()
            .scaledToFit()
            .frame(width: 60, height: 60)
    }

    private var descriptionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Font.dash.title2)
                .foregroundColor(Color.dash.primaryText)

            Text(description)
                .font(Font.dash.footnote)
                .foregroundColor(Color.dash.secondaryText)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
