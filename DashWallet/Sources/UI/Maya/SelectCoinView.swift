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

struct SelectCoinView: View {
    @StateObject private var viewModel = SelectCoinViewModel()
    var onCoinSelected: ((MayaCryptoCurrency) -> Void)?

    var body: some View {
        ZStack {
            Color.primaryBackground.ignoresSafeArea()

            if viewModel.isLoading {
                SwiftUI.ProgressView()
            } else if viewModel.errorMessage != nil {
                errorView(message: viewModel.errorMessage ?? "")
            } else {
                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    coinList
                }
            }
        }
        .task {
            await viewModel.loadCoins()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.system(size: 14))

            TextField(NSLocalizedString("Search", comment: "Maya"), text: $viewModel.searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 14))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.gray400.opacity(0.1))
        .cornerRadius(16)
    }

    // MARK: - Coin List

    private var coinList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.filteredCoins) { item in
                    Button {
                        onCoinSelected?(item.coin)
                    } label: {
                        CoinRowView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(Color.secondaryText)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(Color.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(
                action: {
                    Task {
                        await viewModel.loadCoins()
                    }
                },
                label: {
                    Text(NSLocalizedString("Retry", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.dashBlue)
                        .cornerRadius(8)
                }
            )

            Spacer()
        }
    }
}
