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
    @StateObject private var reachability = NetworkReachabilityMonitor()
    var onBack: (() -> Void)?
    var onCoinSelected: ((MayaCryptoCurrency) -> Void)?

    init(
        swapProvider: SwapProvider = MayaSwapProvider(),
        direction: SwapDirection = .sell,
        onBack: (() -> Void)? = nil,
        onCoinSelected: ((MayaCryptoCurrency) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: SelectCoinViewModel(swapProvider: swapProvider, direction: direction))
        self.onBack = onBack
        self.onCoinSelected = onCoinSelected
    }

    var body: some View {
        ZStack {
            Color.dash.primaryBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                DashUIKit.NavigationBar(
                    leading: { DashUIKit.NavigationBarElement.back.button { onBack?() } },
                    central: { Text(NSLocalizedString("Select coin", comment: "Maya")).font(Font.dash.subheadMedium) }
                )
                mainContent
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.showHaltedToast {
                Toast(
                    style: .warning,
                    message: NSLocalizedString("Some coins are not available because of the halted chain", comment: "Maya"),
                    onDismiss: { viewModel.showHaltedToast = false }
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, Layout.toastHPadding)
                    .padding(.bottom, Layout.toastBPadding)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showHaltedToast)
        .task {
            if reachability.isOnline {
                await viewModel.loadCoins()
            }
        }
        .onChange(of: reachability.isOnline) { isOnline in
            // Restore the coin list when connectivity returns. loadCoins() is a no-op
            // unless coins are missing or a prior fetch errored, so this never resets
            // an already-loaded list or its scroll position.
            guard isOnline else { return }
            Task { await viewModel.loadCoins() }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if !reachability.isOnline {
            NetworkUnavailableStateView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isLoading {
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
                Text(NSLocalizedString("No coins found", comment: "Maya"))
                    .font(Font.dash.footnote)
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
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.dash.blue)
                .cornerRadius(8)
        }
    }
}

#if DEBUG
#Preview {
    SelectCoinView(onBack: {})
}
#endif
