//
//  SelectCoinView.swift
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

import Combine
import DashUIKit
import SwiftUI

// MARK: - SelectCoinView

struct SelectCoinView: View {
    private enum Layout {
        static let hPadding: CGFloat = 20
        static let topPadding: CGFloat = 10
        static let contentSpacing: CGFloat = 20
        static let listSpacing: CGFloat = 2
        static let listPadding: CGFloat = 6
        static let listCornerRadius: CGFloat = 12
        static let toastHPadding: CGFloat = 20
        static let toastBPadding: CGFloat = 16
        static let errorIconSize: CGFloat = 40
        static let errorTextHPadding: CGFloat = 40
        static let emptyStateIconSize: CGFloat = 28
        static let emptyStateSpacing: CGFloat = 8
        static let emptyStateTextHPadding: CGFloat = 24
    }

    @StateObject private var viewModel: SelectCoinViewModel
    var onBack: (() -> Void)?
    var onCoinSelected: ((SwapCryptoCurrency) -> Void)?

    init(
        swapProvider: SwapProvider = MayaSwapProvider(),
        direction: SwapDirection = .sell,
        networkStatus: NetworkStatusProviding = NetworkStatusService.shared,
        onBack: (() -> Void)? = nil,
        onCoinSelected: ((SwapCryptoCurrency) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: SelectCoinViewModel(
            swapProvider: swapProvider,
            direction: direction,
            networkStatus: networkStatus
        ))
        self.onBack = onBack
        self.onCoinSelected = onCoinSelected
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: { DashUIKit.NavigationBarElement.back.button { onBack?() } },
                    central: { Text(NSLocalizedString("Select coin", comment: "Dash DEX")).dashFont(.subheadMedium) }
                )
                mainContent
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.showHaltedToast {
                Toast(
                    style: .warning,
                    message: NSLocalizedString("Some coins are not available because of the halted chain", comment: "Dash DEX"),
                    onDismiss: { viewModel.showHaltedToast = false }
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, Layout.toastHPadding)
                    .padding(.bottom, Layout.toastBPadding)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showHaltedToast)
        .dexOfflineToast(isOnline: viewModel.isOnline)
        .task {
            await viewModel.loadCoins()
            await viewModel.keepRouteAvailabilityFresh()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            SwiftUI.ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            errorView(message: error)
        } else {
            contentView
        }
    }

    private var contentView: some View {
        VStack(spacing: Layout.contentSpacing) {
            DashUIKit.SearchBar(text: $viewModel.searchText)

            if viewModel.showSearchEmptyState {
                emptyStateView
            } else {
                coinList
            }
        }
        .padding(.horizontal, Layout.hPadding)
        .padding(.top, Layout.topPadding)
    }

    // MARK: - Coin List

    private var coinList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Layout.listSpacing) {
                    ForEach(viewModel.filteredCoins) { item in
                        Button {
                            viewModel.willSelectCoin(item)
                            onCoinSelected?(item.coin)
                        } label: {
                            CoinSelector(
                                name: item.displayName,
                                code: item.coin.code,
                                network: item.network,
                                trailing: item.isHalted ? .halted : item.fiatPrice.map { .price($0) }
                            ) {
                                SwapCoinIconView(coin: item.coin, size: 30, cornerRadius: 6)
                            }
                        }
                        .buttonStyle(.plain)
                        // Halted coins are shown (dimmed) but not selectable — the chain can't
                        // route a swap while halted, so block the tap here.
                        .disabled(item.isHalted)
                        // Block taps while offline without applying SwiftUI's disabled visual effect.
                        .allowsHitTesting(viewModel.isOnline)
                        .accessibilityIdentifier("swap_coin_\(item.id)")
                        .id(item.id)
                    }
                }
                .modifier(MenuViewModifier())
            }
            .onAppear {
                // Restore scroll position after back-navigation.
                // One run-loop defer lets the LazyVStack finish initial layout.
                guard let id = viewModel.scrollAnchorID else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack {
            VStack(spacing: Layout.emptyStateSpacing) {
                Text(NSLocalizedString("No coins found", comment: "Dash DEX"))
                    .dashFont(.footnote)
                    .foregroundColor(Color.dash.gray500)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: 100)
            .modifier(MenuViewModifier())

            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: Layout.errorIconSize))
                .foregroundColor(Color.dash.secondaryText)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(Color.dash.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.errorTextHPadding)

            retryButton

            Spacer()
        }
    }

    private var retryButton: some View {
        Button(action: {
            Task { await viewModel.loadCoins(force: true) }
        }) {
            Text(NSLocalizedString("Retry", comment: ""))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.dash.whiteText)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.dash.blue)
                .cornerRadius(8)
        }
    }
}

#if DEBUG
#Preview("Live labels") {
    SelectCoinView(
        swapProvider: SelectCoinPreviewSwapProvider(halted: []),
        networkStatus: SelectCoinPreviewNetworkStatus(),
        onBack: {}
    )
}

#Preview("Halted") {
    SelectCoinView(
        swapProvider: SelectCoinPreviewSwapProvider(halted: [SelectCoinPreviewSwapProvider.arbUSDT, "AVAX.AVAX"]),
        networkStatus: SelectCoinPreviewNetworkStatus(),
        onBack: {}
    )
}

#Preview("Loading") {
    SelectCoinView(
        swapProvider: SelectCoinPreviewSwapProvider(halted: [], loading: .neverAnswers),
        networkStatus: SelectCoinPreviewNetworkStatus(),
        onBack: {}
    )
}

#Preview("Error") {
    SelectCoinView(
        swapProvider: SelectCoinPreviewSwapProvider(halted: [], loading: .fails(URLError(.timedOut))),
        networkStatus: SelectCoinPreviewNetworkStatus(),
        onBack: {}
    )
}

#Preview("Offline") {
    SelectCoinView(
        swapProvider: SelectCoinPreviewSwapProvider(halted: []),
        networkStatus: SelectCoinPreviewNetworkStatus(status: .offline),
        onBack: {}
    )
}

/// Fixed coins and live answers for the previews: no network, no SwapKit.
private final class SelectCoinPreviewSwapProvider: SwapProvider {
    enum Loading {
        case answers
        /// Keeps the picker on its spinner.
        case neverAnswers
        case fails(Error)
    }

    static let arbUSDT = "ARB.USDT-0XFD086BC7CD5C481DCC9C85EBE478A1C0B69FCBB9"
    private static let labels: [String: RouteProvider] = [
        "BTC.BTC": .multiple,
        "ETH.ETH": .multiple,
        "SOL.SOL": .near,
        arbUSDT: .near,
        "AVAX.AVAX": .near,
    ]

    private let halted: Set<String>
    private let loading: Loading

    init(halted: Set<String>, loading: Loading = .answers) {
        self.halted = halted
        self.loading = loading
    }

    var displayName: String { "Preview" }
    var usesGenericFeeLabel: Bool { true }
    var buildsSwapKitDeposit: Bool { true }

    func fetchPools() async throws -> [SwapPool] {
        switch loading {
        case .answers:
            break
        case .neverAnswers:
            try await Task.sleep(nanoseconds: .max)
        case .fails(let error):
            throw error
        }
        // A zero price shows no fiat row, which keeps the currency exchanger out of the preview.
        return Self.labels.keys.map { SwapPool(asset: $0, status: "available", assetPriceUSD: "0") }
    }

    func fetchInboundAddresses() async throws -> [SwapInboundAddress] {
        Set(Self.labels.keys.compactMap { $0.components(separatedBy: ".").first }).map {
            SwapInboundAddress(
                chain: $0, halted: false, address: nil, chainLpActionsPaused: nil, chainTradingPaused: nil,
                dustThreshold: nil, gasRate: nil, gasRateUnits: nil, globalTradingPaused: nil,
                outboundFee: nil, outboundTxSize: nil, pubKey: nil
            )
        }
    }

    func fetchPools(direction: SwapDirection) async throws -> [SwapPool] { try await fetchPools() }

    func networkLabels(for pools: [SwapPool], direction: SwapDirection) async -> [String: String] {
        Self.labels.filter { !halted.contains($0.key) }.mapValues { $0.shortLabel }
    }

    func haltedAssets(
        from inboundAddresses: [SwapInboundAddress],
        pools: [SwapPool],
        direction: SwapDirection
    ) async -> Set<String> {
        halted
    }

    func validateAddress(destination: String, toAsset: String) async -> String? { nil }
    func fetchQuote(dashSatoshis: Int64, toAsset: String, destination: String) async throws -> SwapQuoteResult {
        SwapQuoteResult(
            error: nil, expectedAmountOut: nil, fees: nil, inboundAddress: nil, memo: nil, executionNetwork: nil
        )
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
        throw SwapProviderError.unsupportedBuyOrder
    }
    func validateBuyOrder(sellAsset: String, sellAmount: String, refundAddress: String) async throws {}
    func logoURL(for mayaAsset: String) -> URL? { nil }
}

private final class SelectCoinPreviewNetworkStatus: NetworkStatusProviding {
    let currentStatus: NetworkStatus
    var isOnline: Bool { currentStatus == .online }
    var statusPublisher: AnyPublisher<NetworkStatus, Never> { Just(currentStatus).eraseToAnyPublisher() }

    init(status: NetworkStatus = .online) {
        currentStatus = status
    }
}
#endif
