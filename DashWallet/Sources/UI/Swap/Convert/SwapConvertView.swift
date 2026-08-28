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

import DashUIKit
import SwiftUI

// MARK: - SwapConvertView

struct SwapConvertView: View {

    private enum Layout {
        static let iconSize: CGFloat = 30
        static let padding: CGFloat = 10
        static let hPadding: CGFloat = 20
        static let topPadding: CGFloat = 20
        static let contentSpacing: CGFloat = 20
    }

    @StateObject private var viewModel: SwapConvertViewModel
    @State private var showLocalCurrency = false
    private let onBack: (() -> Void)?
    private let onContinue: () -> Void

    init(viewModel: SwapConvertViewModel, onBack: (() -> Void)? = nil, onContinue: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onBack = onBack
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashUIKit.NavigationBar(leading: { DashUIKit.NavigationBarElement.back.button { onBack?() } })
            TopIntro(title: NSLocalizedString("Enter amount", comment: "Dash DEX"))
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

    // MARK: - Top Section

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Layout.contentSpacing) {
            EnterAmountView(
                value: $viewModel.inputValue,
                selectedCurrency: $viewModel.selectedCurrency,
                options: viewModel.currencyOptions,
                onMax: { viewModel.setMax() },
                onCurrencyTap: { showLocalCurrency = true },
                hidesSelectedOption: true
            )
            .frame(height: 70)
            conversionCard
            receiveSection
        }
        .padding(.horizontal, Layout.hPadding)
        .padding(.top, Layout.topPadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: viewModel.inputValue.isEmpty)
    }

    // MARK: - Conversion Card

    /// One-directional (Dash → coin) card built on DashUIKit's `ConverterCard`. No `onSwap`, so it
    /// shows the static `arrow-down` badge. The Dash row keeps its formatted entered-amount balance
    /// and the coin row keeps the remote icon + full (unwrapped) address.
    private var conversionCard: some View {
        ConverterCard(
            fromItem: ConverterCardItem(
                icon: .custom("dashCircleFilled", bundle: .main),
                title: NSLocalizedString("Dash", comment: "Dash DEX"),
                subtitle: NSLocalizedString("Dash Wallet", comment: "Dash DEX"),
                trailingView: AnyView(
                    DashBalanceView(
                        balance: viewModel.enteredDashFormatted,
                        fiat: viewModel.enteredAmountIsZero ? nil : viewModel.enteredFiatFormatted
                    )
                )
            ),
            toItem: ConverterCardItem(
                iconView: AnyView(SwapCoinIconView(coin: viewModel.coin, size: Layout.iconSize, cornerRadius: 7)),
                title: viewModel.coin.name,
                subtitle: viewModel.address,
                subtitleLineLimit: nil,
                showsBalance: false
            )
        )
    }

    // MARK: - Receive Section

    @ViewBuilder
    private var receiveSection: some View {
        if !viewModel.inputValue.isEmpty {
            VStack(alignment: .center, spacing: 0) {
                if viewModel.isLoading {
                    SwiftUI.ProgressView()
                } else if let error = viewModel.errorMessage {
                    // An error (e.g. insufficient balance after coin-mode gross-up) supersedes the
                    // receive estimate — both can be set at once, so show the error first.
                    Text(error)
                        .dashFont(.caption1)
                        .foregroundColor(Color.dash.red)
                        .multilineTextAlignment(.center)
                } else if let amount = viewModel.receiveAmount {
                    Text(NSLocalizedString("Receive amount", comment: "Dash DEX"))
                        .dashFont(.caption1)
                        .foregroundStyle(Color.dash.tertiaryText)

                    Text("~ \(amount)")
                        .dashFont(.subhead)
                        .foregroundStyle(Color.dash.primaryText)
                }
            }
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
            actionButtonText: NSLocalizedString("Convert", comment: "Dash Dex"),
            actionEnabled: viewModel.canOpenOrderPreview,
            inProgress: viewModel.isLoading,
            actionHandler: onContinue
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
    SwapConvertView(
        viewModel: SwapConvertViewModel(
            coin: SwapCryptoCurrency.supportedCoins[0],
            address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
        ),
        onBack: {}
    )
    .background(Color.dash.primaryBackground)
}
#endif
