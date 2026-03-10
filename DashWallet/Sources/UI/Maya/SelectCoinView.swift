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
        .overlay(alignment: .bottom) {
            if viewModel.showHaltedToast {
                haltedToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showHaltedToast)
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
                        if !item.isHalted {
                            onCoinSelected?(item.coin)
                        }
                    } label: {
                        CoinRowView(item: item)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.isHalted)
                }
            }
            .background(Color.secondaryBackground)
            .cornerRadius(12)
            .shadow(color: .shadow, radius: 10, x: 0, y: 5)
            .padding(.horizontal, 20)
            .padding(.bottom, viewModel.showHaltedToast ? 80 : 20)
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

            Button(action: {
                Task {
                    await viewModel.loadCoins()
                }
            }) {
                Text(NSLocalizedString("Retry", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.dashBlue)
                    .cornerRadius(8)
            }

            Spacer()
        }
    }

    // MARK: - Halted Toast

    private var haltedToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color.systemYellow)
                .font(.system(size: 14))

            Text(NSLocalizedString("Some coins are not available because of the halted chain", comment: "Maya"))
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(2)

            Spacer(minLength: 4)

            Button {
                viewModel.showHaltedToast = false
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.95))
        .cornerRadius(12)
    }
}
