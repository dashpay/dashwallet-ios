//
//  BuyEnterAmountView.swift
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

struct BuyEnterAmountView: View {
    private enum Layout {
        static let hPadding: CGFloat = 20
        static let topPadding: CGFloat = 20
        static let contentSpacing: CGFloat = 20
    }

    @StateObject private var viewModel: BuyEnterAmountViewModel
    @State private var showLocalCurrency = false
    private let onBack: (() -> Void)?
    private let onContinue: (SwapCryptoCurrency, String) -> Void

    init(
        viewModel: BuyEnterAmountViewModel,
        onBack: (() -> Void)? = nil,
        onContinue: @escaping (SwapCryptoCurrency, String) -> Void = { _, _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.NavigationBar(leading: { DashUIKit.NavigationBarElement.back.button { onBack?() } })
            TopIntro(
                title: NSLocalizedString("Enter Amount", comment: "Dash DEX")
            )
            .padding(.horizontal, Layout.hPadding)
            .padding(.bottom, 6)

            amountSection
            keyboard
        }
        .dexOfflineToast(isOnline: viewModel.isOnline)
        .sheet(isPresented: $showLocalCurrency) {
            let dialog = BottomSheet(
                showBackButton: Binding<Bool>.constant(false)
            ) {
                LocalCurrencyView { code in
                    viewModel.selectFiatCurrency(code)
                    showLocalCurrency = false
                }
            }

            if #available(iOS 16.0, *) {
                dialog.presentationDetents([.large])
            } else {
                dialog
            }
        }
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Layout.contentSpacing) {
            EnterAmountView(
                value: $viewModel.inputValue,
                selectedCurrency: $viewModel.selectedCurrency,
                options: viewModel.currencyOptions,
                onCurrencyTap: { showLocalCurrency = true },
                hidesSelectedOption: true
            )
            .frame(height: 70)

            statusSection
        }
        .padding(.horizontal, Layout.hPadding)
        .padding(.top, Layout.topPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: viewModel.inputValue.isEmpty)
    }

    @ViewBuilder
    private var statusSection: some View {
        if viewModel.isLoading {
            HStack(spacing: 8) {
                SwiftUI.ProgressView()

                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .dashFont(.caption1)
                        .foregroundStyle(Color.dash.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
        } else if viewModel.isValidating {
            HStack(spacing: 8) {
                SwiftUI.ProgressView()
                Text(NSLocalizedString("Checking amount…", comment: "Dash DEX"))
                    .dashFont(.caption1)
                    .foregroundStyle(Color.dash.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .transition(.opacity)
        } else if let error = viewModel.inlineMessage {
            Text(error)
                .dashFont(.caption1)
                .foregroundColor(Color.dash.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .transition(.opacity)
        }
    }

    // MARK: - Keyboard

    private var keyboard: some View {
        HardwareNumericKeyboardView(
            value: Binding(
                get: { viewModel.inputValue },
                set: { viewModel.setInput($0) }
            ),
            showDecimalSeparator: true,
            actionButtonText: NSLocalizedString("Continue", comment: ""),
            actionEnabled: viewModel.isActionEnabled,
            inProgress: viewModel.isLoading || viewModel.isValidating,
            actionHandler: {
                Task {
                    await viewModel.attemptContinue { coin, amount in
                        onContinue(coin, amount)
                    }
                }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: 320)
        .padding(.horizontal, Layout.hPadding)
        .background(Color.dash.secondaryBackground)
        .clipShape(.rect(cornerRadius: 20))
        .background(Color.dash.secondaryBackground, ignoresSafeAreaEdges: .bottom)
    }
}

#if DEBUG
#Preview {
    BuyEnterAmountView(
        viewModel: BuyEnterAmountViewModel(
            coin: SwapCryptoCurrency.supportedCoins[0],
            swapProvider: SwapBackend.swapKit.makeProvider()
        ),
        onBack: {}
    )
    .background(Color.dash.primaryBackground)
}
#endif
