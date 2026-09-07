//
//  BuyReceiveView.swift
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

import DashUIKit
import SwiftUI
import UIKit

struct BuyReceiveView: View {
    private enum Layout {
        static let hPadding: CGFloat = 20
        static let topPadding: CGFloat = 10
        static let contentSpacing: CGFloat = 20
        static let cardCornerRadius: CGFloat = 20
    }

    @ObservedObject var viewModel: BuyReceiveViewModel
    private let onBack: (() -> Void)?
    private let onBackHome: () -> Void
    private let onCopy: (String) -> Void
    private let autoLoadOnAppear: Bool

    init(
        viewModel: BuyReceiveViewModel,
        onBack: (() -> Void)? = nil,
        onBackHome: @escaping () -> Void = {},
        onCopy: @escaping (String) -> Void = { _ in },
        autoLoadOnAppear: Bool = true
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onBackHome = onBackHome
        self.onCopy = onCopy
        self.autoLoadOnAppear = autoLoadOnAppear
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: { DashUIKit.NavigationBarElement.back.button { onBack?() } }
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Layout.contentSpacing) {
                        TopIntro(title: viewModel.title, subtitle: viewModel.subtitle)
                        contentCard

                        SystemMessageView(
                            title: NSLocalizedString("This address expires in 10 minutes", comment: "Dash DEX"),
                            subtitle: String(format: NSLocalizedString("Send your %@ before the timer runs out. If you send after the address expires, your funds will be refunded — not converted.", comment: "Dash DEX"), viewModel.coinCode)
                        )

                        Spacer(minLength: 0)

                        DashUIKit.DashButton(
                            text: NSLocalizedString("Back home", comment: "Dash DEX"),
                            fillsWidth: true,
                            size: .large,
                            style: .tintedGray,
                            action: onBackHome
                        )
                        .padding(.horizontal, 40)
                    }
                    .padding(.horizontal, Layout.hPadding)
                    .padding(.top, Layout.topPadding)
                    .padding(.bottom, 24)
                }
            }
        }
        .task {
            guard autoLoadOnAppear else { return }
            await viewModel.load()
        }
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            qrSection
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            copyableDetailRow(
                title: NSLocalizedString("URI", comment: "Dash DEX"),
                displayValue: addressDisplayValue,
                copyValue: viewModel.copyText
            )

            if let memo = viewModel.memoText {
                Divider()
                copyableDetailRow(
                    title: NSLocalizedString("Memo / Tag", comment: "Dash DEX"),
                    displayValue: memo,
                    copyValue: memo,
                    helper: NSLocalizedString("Your transfer must include this memo. Funds sent without it cannot be matched to your swap and will be lost.", comment: "Dash DEX / dex_receive_memo_warning"),
                    helperColor: Color.dash.orange
                )
            }
        }
        .padding(20)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: Layout.cardCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var qrSection: some View {
        if let qrImage = viewModel.qrImage {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 200, maxWidth: 200, minHeight: 200, maxHeight: 200, alignment: .center)
                .padding(10)
                .accessibilityIdentifier("buy_receive_qr")
        } else {
            SwiftUI.ProgressView()
                .frame(minWidth: 200, maxWidth: 200, minHeight: 200, maxHeight: 200)
        }
    }

    private var addressDisplayValue: String {
        viewModel.copyText
    }

    private func copyableDetailRow(
        title: String,
        displayValue: String,
        copyValue: String,
        helper: String? = nil,
        helperColor: Color = Color.dash.tertiaryText
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .dashFont(.caption1)
                    .foregroundColor(Color.dash.secondaryText)

                Text(displayValue)
                    .dashFont(.subhead)
                    .foregroundColor(Color.dash.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let helper {
                    Text(helper)
                        .dashFont(.caption1)
                        .foregroundColor(helperColor)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            DashUIKit.DashButton(
                leadingIcon: DashIcon.Icons.copyOutline.source,
                isEnabled: !copyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, size: .medium,
                style: .tintedGray,
                action: {
                    guard !copyValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    onCopy(copyValue)
                }
            )
        }
    }
}

#if DEBUG
private struct BuyReceivePreviewHost: View {
    @StateObject private var viewModel: BuyReceiveViewModel

    init(coin: SwapCryptoCurrency = SwapCryptoCurrency.supportedCoins.first { $0.code == "BTC" } ?? SwapCryptoCurrency.supportedCoins[0]) {
        let order = BuyOrder(
            depositAddress: coin.code == "BTC"
                ? "bc1qpreviewaddress0000000000000000000000000"
                : "0xpreviewaddress0000000000000000000000000000",
            memo: coin.code == "BTC" ? "preview-memo" : nil,
            expectedDashAmount: Decimal(string: "0.25") ?? 0,
            sellAsset: coin.swapAsset,
            sellAmount: "0.25"
        )
        _viewModel = StateObject(wrappedValue: BuyReceiveViewModel(coin: coin, order: order))
    }

    var body: some View {
        BuyReceiveView(
            viewModel: viewModel,
            onBack: {},
            onBackHome: {},
            autoLoadOnAppear: false
        )
        .background(Color.dash.primaryBackground)
    }
}

#Preview("UTXO") {
    BuyReceivePreviewHost()
}

#Preview("Non-UTXO") {
    BuyReceivePreviewHost(
        coin: SwapCryptoCurrency.supportedCoins.first { $0.code == "USDC" && $0.chain == "ETH" }
            ?? SwapCryptoCurrency.supportedCoins.first { $0.code == "USDC" }
            ?? SwapCryptoCurrency.supportedCoins[0]
    )
}

#endif
