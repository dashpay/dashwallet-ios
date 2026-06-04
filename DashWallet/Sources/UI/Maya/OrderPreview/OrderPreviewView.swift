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

import SwiftUI

struct OrderPreviewView: View {
    private enum Layout {
        static let cardSpacing: CGFloat = 2
        static let rowHPadding: CGFloat = 14
        static let rowVPadding: CGFloat = 12
        static let coinLogoSize: CGFloat = 20
        static let coinLogoCornerRadius: CGFloat = 7
        static let logoTextSpacing: CGFloat = 8
        static let labelSpacing: CGFloat = 20
        static let infoSpacing: CGFloat = 6
        static let rowMinHeight: CGFloat = 46
    }

    @ObservedObject var viewModel: OrderPreviewViewModel
    @StateObject private var reachability = NetworkReachabilityMonitor()
    let onCancel: () -> Void

    var body: some View {
        // This view is only the editable order-preview form. Once a swap is submitted, the
        // full-screen transaction status flow (pending → success / failure) is pushed by
        // OrderPreviewHostingController, which observes `viewModel.swapStatus`.
        orderPreviewContent
    }

    private var orderPreviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationBar(leading: {
                NavigationBarElement.back.button { onCancel() }
            })

            TopIntro(title: String(format: NSLocalizedString("Order Preview", comment: "Maya")))
                .padding(.top, 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            if reachability.isOnline {
                VStack(spacing: Layout.cardSpacing) {
                    fromRow
                    toRow
                    addressRow
                    purchaseRow
                    feeRow
                    totalRow
                }
                .modifier(MayaMenuCardStyle(shadowRadius: 20))
                .padding(.horizontal, 20)
            } else {
                // Confirm and refresh-quote both need network — show the offline state
                // in the content area. Cancel stays available below.
                NetworkUnavailableStateView()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 40)
            }

            Spacer(minLength: 0)

            VStack(spacing: 20) {
                DashButton(text: viewModel.confirmButtonText) {
                    Task { await viewModel.handlePrimaryAction() }
                }
                // Confirm / Refresh quote require network; Cancel below stays enabled.
                .disabled(viewModel.isSubmitting || viewModel.isRefreshing || !reachability.isOnline)

                DashButton(text: NSLocalizedString("Cancel", comment: "")) {
                    onCancel()
                }
                .overrideForegroundColor(.primaryText)
                .overrideBackgroundColor(.gray300Alpha10)
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Rows

    private var fromRow: some View {
        HStack(spacing: Layout.labelSpacing) {
            Text(NSLocalizedString("From", comment: "Maya"))
                .font(.subheadMedium)
                .foregroundColor(.tertiaryText)
                .fixedSize()

            HStack(spacing: Layout.logoTextSpacing) {
                Icon(name: .custom("dashCircleFilled"))
                    .frame(width: Layout.coinLogoSize, height: Layout.coinLogoSize)
                    .clipShape(.rect(cornerRadius: Layout.coinLogoCornerRadius))

                Text(NSLocalizedString("Dash Wallet", comment: "Maya"))
                    .font(.subhead)
                    .foregroundColor(.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Layout.rowHPadding)
        .padding(.vertical, Layout.rowVPadding)
        .frame(minHeight: Layout.rowMinHeight)
    }

    private var toRow: some View {
        HStack(spacing: Layout.labelSpacing) {
            Text(NSLocalizedString("To", comment: "Maya"))
                .font(.subheadMedium)
                .foregroundColor(.tertiaryText)
                .fixedSize()

            HStack(spacing: Layout.logoTextSpacing) {
                MayaCoinIconView(
                    coin: viewModel.coin,
                    size: Layout.coinLogoSize,
                    cornerRadius: Layout.coinLogoCornerRadius
                )

                Text(viewModel.coin.name)
                    .font(.subhead)
                    .foregroundColor(.primaryText)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Layout.rowHPadding)
        .padding(.vertical, Layout.rowVPadding)
        .frame(minHeight: Layout.rowMinHeight)
    }

    private var addressRow: some View {
        OrderPreviewTableRow(
            leading: String(format: NSLocalizedString("%@ address", comment: "Maya"), viewModel.coin.name),
            trailing: viewModel.address,
            rowHPadding: Layout.rowHPadding,
            rowVPadding: Layout.rowVPadding,
            labelSpacing: Layout.labelSpacing,
            rowMinHeight: Layout.rowMinHeight
        )
    }

    private var purchaseRow: some View {
        OrderPreviewTableRow(
            leading: NSLocalizedString("Purchase", comment: "Maya"),
            trailing: viewModel.purchaseAmount,
            trailingSecondary: viewModel.purchaseFiatAmount,
            rowHPadding: Layout.rowHPadding,
            rowVPadding: Layout.rowVPadding,
            labelSpacing: Layout.labelSpacing,
            rowMinHeight: Layout.rowMinHeight
        )
    }

    private var feeRow: some View {
        OrderPreviewFeeRow(
            feeTitle: NSLocalizedString("Maya fee", comment: "Maya"),
            feeText: viewModel.mayaFee,
            feeTextSecondary: viewModel.mayaFeeFiatAmount,
            rowHPadding: Layout.rowHPadding,
            rowVPadding: Layout.rowVPadding,
            labelSpacing: Layout.labelSpacing,
            infoSpacing: Layout.infoSpacing,
            rowMinHeight: Layout.rowMinHeight
        )
    }

    private var totalRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: Layout.labelSpacing) {
            Text(NSLocalizedString("Total", comment: "Maya"))
                .font(.subheadMedium)
                .foregroundColor(.tertiaryText)

            Text(viewModel.totalAmount)
                .font(.title3Medium)
                .foregroundColor(.primaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Layout.rowHPadding)
        .padding(.vertical, Layout.rowVPadding)
    }
}

#if DEBUG
#Preview {
    let quote = MayaSwapQuote(
        error: nil,
        expectedAmountOut: "25700000",
        dustThreshold: nil,
        expiry: nil,
        fees: MayaSwapFees(
            affiliate: nil,
            asset: nil,
            liquidity: nil,
            outbound: "180000",
            slippageBps: nil,
            total: "320000",
            totalBps: nil
        ),
        inboundAddress: "XhzzCcWvvx3rFfbEgkf39rE5Bqt7TP66hR",
        inboundConfirmationBlocks: nil,
        inboundConfirmationSeconds: nil,
        memo: "=:ETH.ETH:0x1234...",
        notes: nil,
        outboundDelayBlocks: nil,
        outboundDelaySeconds: nil,
        recommendedMinAmountIn: nil,
        slippageBps: nil,
        warning: nil,
        routeId: nil,
        routeProviders: nil,
        executionNetwork: nil
    )

    let viewModel = OrderPreviewViewModel(
        coin: MayaCryptoCurrency.supportedCoins[0],
        address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
        dashSatoshis: 10000000,
        fromDashAmount: "0.1",
        fromFiatAmount: "$2.75",
        cryptoFiatRate: 4000,
        fiatCurrencyCode: "USD",
        initialQuote: quote
    )

    OrderPreviewView(viewModel: viewModel, onCancel: {})
        .background(Color.primaryBackground.ignoresSafeArea())
}
#endif
