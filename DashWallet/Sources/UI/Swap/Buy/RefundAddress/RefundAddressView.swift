//
//  RefundAddressView.swift
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

struct RefundAddressView: View {
    @ObservedObject var viewModel: RefundAddressViewModel
    @Environment(\.colorScheme) private var colorScheme

    var onBack: (() -> Void)?
    var onScanQR: (() -> Void)?
    var onOrderCreated: ((BuyOrder) -> Void)?

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: { DashUIKit.NavigationBarElement.back.button { onBack?() } },
                )

                VStack(spacing: 20) {
                    TopIntroView(
                        title: NSLocalizedString("Enter refund address", comment: "Dash DEX"),
                        mainDescription: viewModel.subtitle
                    )

                    addressContent

                    SystemMessageView(
                        title: NSLocalizedString("The refund address is required", comment: "Dash DEX"),
                        subtitle: NSLocalizedString("Your swap can NOT be processed without a refund address", comment: "Dash DEX"),
                        icon: .custom("info-rect", bundle: .dashUIKit),
                        backgroundColor: colorScheme == .dark ? Color.dash.blueAlpha10 : Color.dash.blueAlpha5,
                        onClose: {}
                    )

                    Spacer(minLength: 0)

                    if let orderError = viewModel.orderError {
                        Text(orderError)
                            .dashFont(.footnote)
                            .foregroundColor(Color.dash.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 40)
                    }

                    continueButton
                        .padding(.horizontal, 40)
                }
                .padding(.top, 10)
                .padding(.horizontal, 20)
            }
        }
        .dexOfflineToast(isOnline: viewModel.isOnline)
        .onChange(of: viewModel.addressText) { _ in
            viewModel.onAddressChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshClipboardAddress()
        }
        .onAppear {
            viewModel.refreshClipboardAddress()
        }
    }

    // MARK: - Content

    private var addressContent: some View {
        AddressFieldView(
            text: $viewModel.addressText,
            label: viewModel.addressLabel,
            placeholder: viewModel.placeholderText,
            hasError: viewModel.showAddressError,
            errorText: viewModel.addressValidationErrorMessage,
            onScanQR: onScanQR,
            onPaste: { viewModel.pasteFromClipboard() }
        )
        .accessibilityIdentifier("buy_refund_field")
    }

    private var continueButton: some View {
        DashUIKit.DashButton(
            text: NSLocalizedString("Continue", comment: ""),
            isEnabled: viewModel.isContinueEnabled && viewModel.isOnline && !viewModel.isSubmitting,
            isLoading: viewModel.isSubmitting,
            fillsWidth: true,
            size: .large,
            style: .filledBlue,
            action: {
                Task {
                    if let order = await viewModel.submitOrder() {
                        onOrderCreated?(order)
                    }
                }
            }
        )
        .accessibilityIdentifier("buy_refund_continue")
    }
}

#Preview("Default") {
    RefundAddressView(
        viewModel: RefundAddressViewModel(
            coin: SwapCryptoCurrency.supportedCoins[0],
            sellAmount: "0.1",
            swapProvider: RefundAddressPreviewSwapProvider()
        ),
        onBack: {}
    )
}

private final class RefundAddressPreviewSwapProvider: SwapProvider {
    var displayName: String { "Preview" }
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
        SwapQuoteResult(error: nil, expectedAmountOut: "1000000", fees: nil, inboundAddress: nil, memo: nil, executionNetwork: nil)
    }
    func fetchIndicativeQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        try await fetchQuote(dashSatoshis: dashSatoshis, toAsset: toAsset, destination: destination)
    }
    func fetchSwapStatus(txid: String, depositAddress: String?) async throws -> SwapStatusResult {
        SwapStatusResult(error: nil, isObserved: false, observedStatus: nil, outHashes: nil)
    }
    func createBuyOrder(sellAsset: String, sellAmount: String, destination: String, refundAddress: String) async throws -> BuyOrder {
        BuyOrder(depositAddress: "XPreviewDepositAddress", memo: nil, expectedDashAmount: 1, sellAsset: sellAsset, sellAmount: sellAmount)
    }
    func validateBuyOrder(sellAsset: String, sellAmount: String, refundAddress: String) async throws {}
    func trackerURL(for txid: String, depositAddress: String?) -> URL? { nil }
    func logoURL(for mayaAsset: String) -> URL? { nil }
}
