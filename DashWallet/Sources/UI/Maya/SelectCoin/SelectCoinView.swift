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

import SwiftUI

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
    }

    @StateObject private var viewModel = SelectCoinViewModel()
    var onCoinSelected: ((MayaCryptoCurrency) -> Void)?

    init(onCoinSelected: ((MayaCryptoCurrency) -> Void)? = nil) {
        self.onCoinSelected = onCoinSelected
    }

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()
            mainContent
        }
        .overlay(alignment: .bottom) {
            if viewModel.showHaltedToast {
                HaltedToast(showHaltedToast: $viewModel.showHaltedToast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, Layout.toastHPadding)
                    .padding(.bottom, Layout.toastBPadding)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showHaltedToast)
        .task {
            await viewModel.loadCoins()
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if viewModel.isLoading {
            SwiftUI.ProgressView()
        } else if let error = viewModel.errorMessage {
            errorView(message: error)
        } else {
            contentView
        }
    }

    private var contentView: some View {
        VStack(spacing: Layout.contentSpacing) {
            SearchBar(text: $viewModel.searchText)
            coinList
        }
        .padding(.horizontal, Layout.hPadding)
        .padding(.top, Layout.topPadding)
    }

    // MARK: - Coin List

    private var coinList: some View {
        ScrollView {
            LazyVStack(spacing: Layout.listSpacing) {
                ForEach(viewModel.filteredCoins) { item in
                    Button {
                        onCoinSelected?(item.coin)
                    } label: {
                        CoinRowView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .modifier(MenuCardStyle())
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: Layout.errorIconSize))
                .foregroundColor(Color.secondaryText)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.errorTextHPadding)

            retryButton

            Spacer()
        }
    }

    private var retryButton: some View {
        Button(action: {
            Task { await viewModel.loadCoins() }
        }) {
            Text(NSLocalizedString("Retry", comment: ""))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.dashBlue)
                .cornerRadius(8)
        }
    }
}

#if DEBUG
#Preview {
    SelectCoinView()
}
#endif
