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

                        DashUIKit.DashButton(
                            text: NSLocalizedString("Back home", comment: "Dash DEX"),
                            fillsWidth: true,
                            size: .large,
                            style: .filledBlue,
                            action: onBackHome
                        )
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

            if let amount = viewModel.displaySendAmount {
                Divider()
                copyableDetailRow(
                    title: NSLocalizedString("Amount to send", comment: "Dash DEX"),
                    displayValue: amount,
                    copyValue: amount
                )
            }

            if let memo = viewModel.memoText {
                Divider()
                copyableDetailRow(
                    title: NSLocalizedString("Memo / Tag", comment: "Dash DEX"),
                    displayValue: memo,
                    copyValue: memo,
                    helper: NSLocalizedString("Required — include this memo or your funds may be lost", comment: "Dash DEX"),
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
        if viewModel.isLoading, viewModel.qrImage == nil {
            VStack(spacing: 16) {
                SwiftUI.ProgressView()
                Text(NSLocalizedString("Resolving deposit address…", comment: "Dash DEX"))
                    .font(.footnote)
                    .foregroundColor(Color.dash.tertiaryText)
            }
            .frame(minWidth: 200, maxWidth: 200, minHeight: 200, maxHeight: 200)
        } else if let qrImage = viewModel.qrImage {
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(minWidth: 200, maxWidth: 200, minHeight: 200, maxHeight: 200, alignment: .center)
                .padding(10)
                .accessibilityIdentifier("buy_receive_qr")
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 16) {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(Color.dash.red)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Text(NSLocalizedString("Retry", comment: "Dash DEX"))
                }
            }
            .frame(minWidth: 200, maxWidth: 200, minHeight: 200, maxHeight: 200)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.dash.primaryBackground.opacity(0.8))
                .frame(minWidth: 200, maxWidth: 200, minHeight: 200, maxHeight: 200, alignment: .center)
                .overlay(
                    SwiftUI.ProgressView()
                )
        }
    }

    private var addressDisplayValue: String {
        if !viewModel.copyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.copyText
        }

        if viewModel.isLoading {
            return NSLocalizedString("Resolving deposit address…", comment: "Dash DEX")
        }

        return NSLocalizedString("Not available", comment: "Dash DEX")
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
                    .font(Font.dash.caption1)
                    .foregroundColor(Color.dash.secondaryText)

                Text(displayValue)
                    .font(Font.dash.subhead)
                    .foregroundColor(Color.dash.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let helper {
                    Text(helper)
                        .font(Font.dash.caption1)
                        .foregroundColor(helperColor)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            DashUIKit.DashButton(
                leadingIcon: .custom("copy-outline", bundle: .dashUIKit),
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
        let viewModel = BuyReceiveViewModel(
            coin: coin,
            refundAddress: "bc1qxhgnnp745zryn2ud8hm6k3mygkkpkm35020js0",
            sellAmount: "0.25",
            swapProvider: BuyReceivePreviewSwapProvider()
        )
        viewModel.depositAddress = coin.code == "BTC" ? "bc1qpreviewaddress0000000000000000000000000" : "0xpreviewaddress0000000000000000000000000000"
        viewModel.uri = coin.code == "BTC"
            ? "bitcoin:bc1qpreviewaddress0000000000000000000000000?amount=0.25&message=preview-memo"
            : "0xpreviewaddress0000000000000000000000000000"
        viewModel.memoText = coin.code == "BTC" ? "preview-memo" : nil
        viewModel.qrImage = UIImage(systemName: "qrcode")
        _viewModel = StateObject(wrappedValue: viewModel)
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

private final class BuyReceivePreviewSwapProvider: SwapProvider {
    var displayName: String { "SwapKit" }
    var usesGenericFeeLabel: Bool { true }
    var buildsSwapKitDeposit: Bool { true }
    var onBuyRoutabilityChanged: (() -> Void)?

    func fetchPools() async throws -> [SwapPool] { [] }
    func fetchInboundAddresses() async throws -> [SwapInboundAddress] { [] }
    func fetchPools(direction: SwapDirection) async throws -> [SwapPool] { [] }
    func networkLabels(for pools: [SwapPool]) async -> [String: String] { [:] }
    func haltedAssets(from inboundAddresses: [SwapInboundAddress], pools: [SwapPool]) async -> Set<String> { [] }
    func validateAddress(destination: String, toAsset: String) async -> String? { nil }
    func fetchQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        SwapQuoteResult(error: nil, expectedAmountOut: "1000000", fees: nil, inboundAddress: nil, memo: nil, executionNetwork: "NEAR")
    }
    func fetchIndicativeQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        try await fetchQuote(dashSatoshis: dashSatoshis, toAsset: toAsset, destination: destination)
    }
    func fetchSwapStatus(txid: String, depositAddress: String?) async throws -> SwapStatusResult {
        SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil)
    }
    func createBuyOrder(
        sellAsset: String,
        sellAmount: String,
        destination: String,
        refundAddress: String
    ) async throws -> BuyOrder {
        BuyOrder(
            depositAddress: "XyZPreviewDepositAddress123",
            memo: "preview-memo",
            expectedDashAmount: Decimal(string: "0.25") ?? 0,
            sellAsset: sellAsset,
            sellAmount: sellAmount
        )
    }
    func validateBuyOrder(
        sellAsset: String,
        sellAmount: String,
        refundAddress: String
    ) async throws {}
    func trackerURL(for txid: String, depositAddress: String?) -> URL? { nil }
    func logoURL(for mayaAsset: String) -> URL? { nil }
}
#endif
